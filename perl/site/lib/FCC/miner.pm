#!/usr/bin/perl

package FCC::miner;

#############################################################
#                                                           #
#     FCC Miner functions                                   #
#                                                           #
#    (C) 2018 Chaosje Domero                                #
#    Leaves are less strict, the node will check all        #
#                                                           #
#############################################################

use strict;
no strict 'refs';
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.01';
@ISA         = qw(Exporter);
@EXPORT      = qw(fac perm minehash solhash);
@EXPORT_OK   = qw();

use FCC::global;

1;

sub fac {
  my ($f) = @_;
  my $fac=1; while ($f>1) { $fac*=$f; $f-- } return $fac
}

sub perm {
  my ($init,$k) = @_;
  my $n=length($init); my $dn=$n;
  my $out=""; my $m=$k;
  for (my $i=0;$i<$n;$i++) {
    my $ind=$m % $dn;  
    $out.=substr($init,$ind,1);
    $m=$m / $dn;  
    substr($init,$ind,1,substr($init,$dn-1,1));
    $dn--
  }
  return $out
}

sub minehash {
  my ($coincount,$suggest) = @_;
  return securehash('FCC'.dechex($coincount,8).$suggest);
}

sub solhash {
  my ($wallet,$solution) = @_;
  return securehash($wallet.$solution)
}