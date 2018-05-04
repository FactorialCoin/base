#!/usr/bin/perl

 #############################################################################
 #                                                                           #
 #   Eureka Error System v1.0.2                                              #
 #   (C) 2017 Domero, Groningen, NL                                          #
 #   ALL RIGHTS RESERVED                                                     #
 #                                                                           #
 #############################################################################

package gerr;

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.02';
@ISA         = qw(Exporter);
@EXPORT      = qw(error);
@EXPORT_OK   = qw(trace);

1;

sub error {
  my @msg=@_; push @msg,"";
  select(STDOUT); binmode(STDOUT); $|=1;
  print "\n "; print ("*"x32); print " FATAL ERROR "; print ("*"x33); print "\n";
  foreach my $line (@msg) {
    while (length($line)>0) {
      print " * ";
      if (length($line)>74) {
        my $disp=substr($line,0,71)."..."; print $disp; print " *\n";
        $line="...".substr($line,71)
      } else {
        print $line; print (" "x(74-length($line))); print " *\n";
        $line=""
      }
    }
  }    
  print " "; print ("*"x32); print " FATAL ERROR "; print ("*"x33); print "\n";
  print trace();
  exit 1
}

sub trace {
  my $i=1; my $out="";
  while (($i>0) && ($i<20)) {
    my ($package,$filename,$line,$subroutine,$hasargs,$wantarray,$evaltext,$is_require,$hints,$bitmask,$hinthash)=caller($i);
    if (!$package) { $i=0 }
    else {
      $out.="$package($filename): Line $line calling $subroutine\n";
      $i++
    }
  }
  return $out
}

# EOF gerr.pm (C) 2017 Domero