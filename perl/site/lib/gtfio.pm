#!/usr/bin/perl

 #############################################################################
 #                                                                           #
 #   Eureka Multi-Threads File System                                        #
 #   (C) 2016 Domero, Groningen, NL                                          #
 #   ALL RIGHTS RESERVED                                                     #
 #                                                                           #
 #############################################################################

package gtfio;

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Digest::SHA1 qw(sha1);
use gsem;

$VERSION     = '1.01';
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw();

use Fcntl qw (:DEFAULT :flock);
use gerr qw(error);

my %OPENED = ();

1;
 
sub open {
  my ($file) = @_;
  my $sha=sha1($file); my $sem="_tfio_$sha";
  if (!gsem::exists($sem)) {
    gsem::create($sem)
  }
  gsem::wait($sem);
  if (!$OPENED{$file}) {
    my $handle;
    if (!-e $file) {
      sysopen($handle,$file,O_CREAT | O_RDWR | O_BINARY) || error("GTFIO.Open: Cannot open '$file': $!");
    } else {
      sysopen($handle,$file,O_RDWR | O_BINARY) || error("GTFIO.Open: Cannot open '$file': $!")
    }
    $OPENED{$file}={
      handle => $handle,
      sem => $sem
    }
  }
  gsem::release($sem);
}

sub lock {
  my ($file) = @_;
  if (!$OPENED{$file}) {
    error("GTFIO.Lock: File '$file' is not opened")
  }
  gsem::wait($OPENED{$file}{sem});
}

sub unlock {
  my ($file) = @_;
  if (!$OPENED{$file}) {
    error("GTFIO.UnLock: File '$file' is not opened")
  }
  gsem::release($OPENED{$file}{sem});
}

sub closeall {
  foreach my $file (keys %OPENED) { close($OPENED{$file}{handle}) }
}

sub close {
  my ($file) = @_;
  if (!$OPENED{$file}) {
    error("GTFIO.Close: File '$file' is not opened")
  }
  close($OPENED{$file}{handle});
  delete $OPENED{$file}
}

sub read {
  my ($file,$start,$len) = @_;
  if (!$OPENED{$file}) {
    error("GTFIO.Read: File '$file' is not opened, start='$start', len='$len'")
  }
  gsem::wait($OPENED{$file}{sem});
  my $size = -s $file;
  if ($start+$len>$size) {
    error("GFTIO.Read: Reading beyong boundary of file '$file', start='$start', len='$len', size='$size'")
  }
  sysseek($OPENED{$file}{handle},$start,0) || error("GTFIO.Read: Error seeking in file '$file' pos='$start': $!");
  my $data;
  sysread($OPENED{$file}{handle},$data,$len) || error("GTFIO.Read: Error reading from file '$file', start='$start', len=$len: $!");
  gsem::release($OPENED{$file}{sem});
  return $data
}

sub write {
  my ($file,$start,$data) = @_;
  if (!length($data)) { return }
  if (!$OPENED{$file}) {
    error("GTFIO.Write: File '$file' is not opened, start='$start'")
  }
  gsem::wait($OPENED{$file}{sem});
  my $size = -s $file;
  if ($start>$size) {
    error("GTFIO.Write: Writing beyond boundary of file '$file', start='$start', size='$size'")
  }
  sysseek($OPENED{$file}{handle},$start,0) || error("GTFIO.Write: Error seeking in file '$file' pos='$start': $!");
  syswrite($OPENED{$file}{handle},$data) || error("GTFIO.Write: Error writing to file '$file', start='$start': $!");;
  gsem::release($OPENED{$file}{sem});
}


sub crop {
  my ($file,$length) = @_;
  if (!$OPENED{$file}) {
    error("GTFIO.Crop: File '$file' is not opened, length='$length'")
  }
  gsem::wait($OPENED{$file}{sem});
  truncate($OPENED{$file}{handle},$length);
  gsem::release($OPENED{$file}{sem});
}

sub insert {
  my ($file,$start,$data) = @_;
  if (!$OPENED{$file}) {
    error("GTFIO.Insert: File '$file' is not opened, start='$start'")
  }
  gsem::wait($OPENED{$file}{sem});
  my $size = -s $file;
  if ($start>$size) {
    error("GTFIO.Insert: Writing beyond boundary of file '$file', start='$start', size='$size'")
  }
  sysseek($OPENED{$file}{handle},$start,0) || error("GTFIO.Insert: Error seeking in file '$file' pos='$start': $!");
  my $rdat;
  if ($size>$start) {
    sysread($OPENED{$file}{handle},$rdat,$size-$start) || error("GTFIO.Insert: Error reading from file '$file', start='$start': $!");
  }
  if (length($rdat)) { $data.=$rdat }
  sysseek($OPENED{$file}{handle},$start,0) || error("GTFIO.Insert: Error seeking in file '$file' pos='$start': $!");
  if (length($data)) {
    syswrite($OPENED{$file}{handle},$data) || error("GTFIO.Insert: Error writing to file '$file', start='$start': $!");
  }
  gsem::release($OPENED{$file}{sem});  
}

sub append {
  my ($file,$data) = @_;
  if (!length($data)) { return }
  if (!$OPENED{$file}) {
    error("GTFIO.Append: File '$file' is not opened")
  }
  gsem::wait($OPENED{$file}{sem});
  my $size = -s $file;
  sysseek($OPENED{$file}{handle},$size,0) || error("GTFIO.Append: Error seeking in file '$file' pos='$size': $!");
  syswrite($OPENED{$file}{handle},$data) || error("GTFIO.Append: Error writing to file '$file', start='$size': $!");
  gsem::release($OPENED{$file}{sem});  
}

sub extract {
  my ($file,$start,$length) = @_;
  if (!defined($length) || !$length) { return }
  if (!$OPENED{$file}) {
    error("GTFIO.Extract: File '$file' is not opened, start='$start', len='$length'")
  }
  gsem::wait($OPENED{$file}{sem});
  my $size = -s $file;
  if ($start+$length>$size) {
    error("GFTIO.Extract: Deleting beyong boundary of file '$file', start='$start', len='$length', size='$size'")
  }
  my $pos=$start+$length;
  sysseek($OPENED{$file}{handle},$pos,0) || error("GTFIO.Extract: Error seeking in file '$file' pos='$pos': $!");
  my $rdat;
  if ($size>$pos) {
    sysread($OPENED{$file}{handle},$rdat,$size-$pos) || error("GTFIO.Extract: Error reading from file '$file', start='$start': $!");
  }
  sysseek($OPENED{$file}{handle},$start,0) || error("GTFIO.Extract: Error seeking in file '$file' pos='$start': $!");
  if (length($rdat)) {
    syswrite($OPENED{$file}{handle},$rdat) || error("GTFIO.Extract: Error writing to file '$file', start='$start': $!");
  }
  $size-=$length;
  truncate($OPENED{$file}{handle},$size);
  gsem::release($OPENED{$file}{sem});
}

sub content {
  my ($file) = @_;
  if (!$OPENED{$file}) {
    error("GTFIO.Content: File '$file' is not opened")
  }
  gsem::wait($OPENED{$file}{sem});
  my $size = -s $file;
  sysseek($OPENED{$file}{handle},0,0) || error("GTFIO.Content: Error seeking in file '$file' pos='0': $!");
  my $rdat;
  sysread($OPENED{$file}{handle},$rdat,$size) || error("GTFIO.Content: Error reading from file '$file', size='$size': $!");
  gsem::release($OPENED{$file}{sem});
  return $rdat
}

# EOF gtfio.pm