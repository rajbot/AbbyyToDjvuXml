#!/usr/bin/perl

use strict;
use warnings;
use XML::Twig;
use Cwd 'abs_path';
use File::Basename;
use XML::Simple;

my $abbyyXml    = $ARGV[0];
my $itemDir     = $ARGV[1];
my $sourceRoot  = $ARGV[2];
my $outputXml   = $ARGV[3];
#my $scanDataXml= $ARGV[4];


# read scandata
#______________________________________________________________________________
my $gotScanData   = 0;
my $gotJp2Archive = 0;
my $gotJpgArchive = 0;
my $gotTifArchive = 0;
my $scanData;
my @archiveFileNames;

if ($#ARGV < 3) {
    die "Too few arguments!\n";
}

if (4 == $#ARGV) {
    my $scanDataXml = $ARGV[4];
    my $xml         = new XML::Simple (KeyAttr=>[]);
    $scanData       = $xml->XMLin("$scanDataXml", forcearray=>['page']); #in case there's only one page
    $gotScanData    = 1;
} else {
    #If scandata.zip doesn't exist, try to grab leaf names from _jp2.zip/_jp2.tar/_jpg.zip/_jpg.tar/_tif.zip
    #I wish Archive::Zip was installed!
    my $jp2Zip = "${itemDir}/${sourceRoot}_jp2.zip";
    my $jp2Tar = "${itemDir}/${sourceRoot}_jp2.tar";
    my $jpgZip = "${itemDir}/${sourceRoot}_jpg.zip";
    my $jpgTar = "${itemDir}/${sourceRoot}_jpg.tar";
    my $tifZip = "${itemDir}/${sourceRoot}_tif.zip";
    my $results;

    if (-e $jp2Zip) {
        open($results, '-|', 'unzip', '-qq', '-l', $jp2Zip); #safe for bizarro characters in the filename
        $gotJp2Archive = 1;
    } elsif (-e $jp2Tar) {
        open($results, '-|', 'tar', '-tf', $jp2Tar);
        $gotJp2Archive = 1;
    } elsif (-e $jpgZip) {
        open($results, '-|', 'unzip', '-qq', '-l', $jpgZip);
        $gotJpgArchive = 1;
    } elsif (-e $jpgTar) {
        open($results, '-|', 'tar', '-tf', $jpgTar);
        $gotJpgArchive = 1;
    } elsif (-e $tifZip) {
        open($results, '-|', 'unzip', '-qq', '-l', $tifZip);
        $gotTifArchive = 1 ;
    }

    if ($gotJp2Archive) {
        my @unsorted;
        my $j=0;
        my $line;
        my $filename;

        foreach $line(<$results>) {
            if ($line =~ /(\S+\.jp2$)/) {
                $filename = $1;                 #capture dir/file.jpg
                $filename =~ s/^(.+)\///;       #strip dir/ if it exists
                $unsorted[$j] = $filename;
                $j++;
            }
        }
        @archiveFileNames = sort @unsorted;
    } elsif ($gotJpgArchive) {
        my @unsorted;
        my $j=0;
        my $line;
        my $filename;

        foreach $line(<$results>) {
            if ($line =~ /(\S+\.jpg$)/) {
                $filename = $1;                  #capture dir/file.jpg
                $filename =~ s/^(.+)\///;        #strip dir/ if it exists
                $unsorted[$j] = $filename;
                $j++;
            }
        }
        @archiveFileNames = sort @unsorted;
    } elsif ($gotTifArchive) {
        my @unsorted;
        my $j=0;
        my $line;
        my $filename;

        foreach $line(<$results>) {
            if ($line =~ /(\S+\.tif$)/) {
                $filename = $1;                 #capture dir/file.tif
                $filename =~ s/^(.+)\///;       #strip dir/ if it exists
                $unsorted[$j] = $filename;
                $j++;
            }
        }
        @archiveFileNames = sort @unsorted;
    }
}

print "gotScanData=$gotScanData, gotJp2Archive=$gotJp2Archive, gotJpgArchive=$gotJpgArchive, gotTifArchive=$gotTifArchive\n";


# open output for writing
#______________________________________________________________________________
my $outputFH;
open $outputFH, ">$outputXml" or die "Can't open $outputFH for writing!";
$| = 1; #set autoflush on STDOUT

# print header
#______________________________________________________________________________
# We could call $doc->wrap_in("DjVuXML") in the document tag handler, instead
# of printing the opening and closing DjVuXML tags ourselves. However, since
# we want to call $twig->flush() after every page is processed, and because
# the document is a top-level tag, we need to make the handler a start_tag_handler.
# Unfortunately, wrap_in doesn't work properly when using start_tag_handlers
# and flush(), So we'll just write the enclosing <DjVuXML> tag ourself.
# We want to make sure the <?xml> prolog tag is printed before <DjVuXML>, so
# we call $twig->new() with no_prolog. It would be OK to leave out the <?xml>
# and the DOCTYPE tags entirely. The HEAD element has been omitted.

#move these down below, in order to get the encoding from abbyy.xml
#print $outputFH "<?xml version=\"1.0\" ?>\n";
#print $outputFH "<!DOCTYPE DjVuXML>\n";
#print $outputFH "<DjVuXML>\n";

# build and process the twig
#______________________________________________________________________________
my $fname       = $itemDir . "/" . $sourceRoot . ".djvu";
my $i           = 0;    #A global! :(

my $twig= new XML::Twig(
    TwigHandlers =>
    { page              => sub { page(@_, $fname, $sourceRoot) },
      block             => \&block,
      row               => sub { $_->erase; }, # Abbyy creates <row> and <cell> elements when it recognizes a
      cell              => sub { $_->erase; }, # table; we want to bypass them and just grab their contents
      text              => \&text,
      par               => \&par,
      line              => sub { change_name(@_, "LINE") },
      formatting        => \&formatting
    },
    pretty_print => "nice",
    start_tag_handlers => {
        document        => \&start_doc
    },
    ignore_elts   =>
    {
        'region' => 1
    },
    no_prolog     => 1,
    keep_encoding => 1
    );


$twig->parsefile($abbyyXml);
$twig->flush($outputFH);


print $outputFH "</DjVuXML>\n";
close $outputFH;
print "\n";
### end of main()




# convert page to object tags
#______________________________________________________________________________
sub page {
    my($twig, $page, $fname, $sourceRoot)= @_;

    #These have been moved from above
    if (0 == $i) {
        print $outputFH "<?xml version=\"1.0\" encoding=\"" . $twig->encoding() . "\"?>\n";
        print $outputFH "<!DOCTYPE DjVuXML>\n";
        print $outputFH "<DjVuXML>\n";
    }

#        if (defined($page->prev_sibling)) {
#                $twig->flush_up_to($page->prev_sibling);
#        }

    #my $absPath  = abs_path($fname);
    my $absFname = "file://localhost/" . $fname;

    my $addThisPage = 1;
    my $leafNum     = $i;
    my $leafName = $sourceRoot . "_" . sprintf("%04d", $leafNum) . ".djvu";

    #print "Processing page $i\n";
    if ($gotScanData) {
        if (defined(${$scanData->{pageData}->{page}}[$i])) {
            $addThisPage = (!(defined(${$scanData->{pageData}->{page}}[$i]->{addToAccessFormats})) or (${$scanData->{pageData}->{page}}[$i]->{addToAccessFormats} eq "true"));
            $leafNum  = ${$scanData->{pageData}->{page}}[$i]->{leafNum};
            $leafName = $sourceRoot . "_" . sprintf("%04d", $leafNum) . ".djvu";
        } else {
            ### Sometimes, the scandata.xml file has no entry for the last few pages.
            print "Scandata corrupt! No page object found for page $i, setting addToAccessFormats=0!\n";
            $addThisPage = 0;
        }
    } elsif ($gotJp2Archive) {
        $leafName = $archiveFileNames[$i];
        $leafName =~ s/\.jp2$/\.djvu/;
    } elsif ($gotJpgArchive) {
        $leafName = $archiveFileNames[$i];
        $leafName =~ s/\.jpg$/\.djvu/;
    } elsif ($gotTifArchive) {
        $leafName = $archiveFileNames[$i];
        $leafName =~ s/\.tif$/\.djvu/;
    }

    if ($addThisPage) {

        $page->set_tag("OBJECT");
        $page->set_att(        "data" => $absFname,
                        "type" => "image/x.djvu",
                        "usemap" => $leafName
            );

        $page->insert("HIDDENTEXT");

        my $resolution = $page->att("resolution");
        $page->insert_new_elt(
            "PARAM",
            {
                name => "DPI",
                value => $resolution
            }
            );


        $page->insert_new_elt(
            "PARAM",
            {
                name => "PAGE",
                value => $leafName
            }
            );


        $page->del_att( "originalCoords", "resolution");

        $page->insert_new_elt(
            "after",
            "MAP",
            {
                name => $leafName
            }
            );

        $twig->flush($outputFH);
        print "+";

    } else {
        $page->delete();
        print "-";
    }

    if (49 == ($i % 50)) {
        print "\n";
    } elsif (9 == ($i % 10)) {
        print " ";
    }

    $i++;

}

# sub document
#______________________________________________________________________________
sub start_doc {
    my($twig, $doc)= @_;
    $doc->del_atts();
    $doc->set_tag("BODY");
}

# sub block
#______________________________________________________________________________
sub block {

    my($twig, $block)= @_;
    $block->del_atts();
    $block->set_tag("PAGECOLUMN");
    #$twig->flush;
}

# sub text
#______________________________________________________________________________
sub text {

    my($twig, $text)= @_;
    $text->set_tag("REGION");
    #$twig->flush;
}

# sub par
#______________________________________________________________________________
sub par {

    my($twig, $par)= @_;
    $par->del_atts();
    $par->set_tag("PARAGRAPH");
    #$twig->flush;
}

# sub change_name
#______________________________________________________________________________
sub change_name {

    my($twig, $element, $name)= @_;
    $element->del_atts();
    $element->set_tag($name);
    #$twig->flush;
}

# sits_on_baseline is to return 1 for characters we're pretty
# sure sit right on the baseline, and return 0 for characters
# which have a descender.
#
# This is just an approximation of course, and our goal is
# to, in most cases, get some characters we can use to guess
# what the baseline for a word should be.  (The actual baseline
# reported in the abbyy data doesn't seem to work so well.)
#______________________________________________________________________________
sub sits_on_baseline {
    my $value=ord($_[0]);
    if (($value>=ord('a'))&&($value<=ord('z'))) {
        if (($value==ord('g'))||
            ($value==ord('j'))||($value==ord('p'))||
            ($value==ord('q'))||($value==ord('y'))) {
            return 0;
        } else {
            return 1;
        }
    } elsif (($value>=ord('A'))&&($value<=ord('Z'))) {
        if ($value==ord('Q')) {
            return 0;
        } else {
            return 1;
        }
    } else {
        return 0;
    }
}

# sub formatting
# logic copied from the php version
#______________________________________________________________________________
sub formatting {
    my($twig, $formatting)= @_;
    my $l         = 50000;
    my $t         = 50000;
    my $r         = 0;
    my $b         = 0;
    my $base_line=0; # per word baseline

    my $wbuf = '';

    my @children = $formatting->cut_children("charParams");
    $formatting->cut_children(); #cut all the children

    # We keep track of the characters without descenders so that we can
    # report a proxy for a baseline for each word: it is to be the
    # average of the non-descending letters' bounding box lower
    # heights.  (If there are no such, we just use the average over
    # all the characters.)
    my $letter_count=0;
    my $non_descender_letter_count=0;
    my $letter_y_sum=0;
    my $non_descender_letter_y_sum=0;

    foreach my $charParams (@children) {
        my $value = htmlspecialchars($charParams->text());

        my $myl = $charParams->att('l');
        my $myt = $charParams->att('t');
        my $myr = $charParams->att('r');
        my $myb = $charParams->att('b');

        $letter_count++;
        $letter_y_sum+=$myb;
        if (&sits_on_baseline($value)==1) {
            $non_descender_letter_count++;
            $non_descender_letter_y_sum+=$myb;
        }

        my $wordStart = $charParams->att("wordStart");
        if(!$wordStart) { $wordStart = ""; }

        #print "wordstart = $wordStart\n";
        if (($wordStart eq "true") || ($value eq ' ') || ($value eq '\'')) {
            if ($wbuf) {
                if ($non_descender_letter_count>0) {
                    $base_line=$non_descender_letter_y_sum/$non_descender_letter_count;
                } elsif ($letter_count>0) {
                    $base_line=$letter_y_sum/$letter_count;
                } else {
                    $base_line=0; # Maybe loop is empty, so just give b a value
                }
                $base_line=int($base_line);
                $letter_count=0;
                $letter_y_sum=0;
                $non_descender_letter_count=0;
                $non_descender_letter_y_sum=0;
                $formatting->insert_new_elt('last_child', "WORD", {coords => "$l,$b,$r,$t,$base_line"}, $wbuf);
            }

            $l         = 50000;
            $t         = 50000;
            $r         = 0;
            $b         = 0;
            $base_line = 0;
            $wbuf = '';
        }

        if (($value ne ' ') && ($value ne '\'')) {
            $wbuf .= $value;
            if ($myl < $l) { $l = $myl; }
            if ($myt < $t) { $t = $myt; }
            if ($myr > $r) { $r = $myr; }
            if ($myb > $b) { $b = $myb; }
        }

    } #foreach $charParams

    if ($wbuf) {
        if ($non_descender_letter_count>0) {
            $base_line=
                $non_descender_letter_y_sum/$non_descender_letter_count;
        } elsif ($letter_count>0) {
            $base_line=$letter_y_sum/$letter_count;
        } else {
            $base_line=0; # Maybe loop is empty, so just give b a value
        }
        $base_line=int($base_line);
        $formatting->insert_new_elt('last_child', "WORD", {coords => "$l,$b,$r,$t,$base_line"}, $wbuf);
    }

    $formatting->erase();

    #$twig->flush;
}



# PHP htmlspecialchars emulation
#______________________________________________________________________________
sub htmlspecialchars {
    my ($value) = @_;

    $value =~ s/</&amp;lt;/g;
    $value =~ s/>/&amp;gt;/g;
    $value =~ s/\"/&quot;/g;

    return $value;
}
