#!/usr/bin/perl

package FCC::miner;

#############################################################
#                                                           #
#     FCC Miner functions                                   #
#                                                           #
#    (C) 2019 Chaosje Domero                                #
#    Leaves are less strict, the node will check all        #
#                                                           #
#############################################################

use strict;
no strict 'refs';
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.1.3';
@ISA         = qw(Exporter);
@EXPORT      = qw(fac initperm perm minehash solhash);
@EXPORT_OK   = qw();

use FCC::global 2.3.1;

1;

sub fac {
  my ($f) = @_;
  my $fac=1; while ($f>1) { $fac*=$f; $f-- } return $fac
}

sub initperm {
  my ($len) = @_;
  my $p=""; for my $i (0..$len-1) { $p.=chr(65+$i) } return $p
}

sub perm {
  my ($init,$k) = @_;
  my $n=length($init); my $dn=$n;
  my $out=""; my $m=$k;
  for (my $i=0;$i<$n;$i++) {
    my $ind=$m % $dn;  
    $out.=substr($init,$ind,1);
    $m=$m / $dn;  
    $dn--;
    substr($init,$ind,1,substr($init,$dn,1));
  }
  return $out
}

sub minehash {
  my ($coincount,$suggest) = @_;
  return securehash($COIN.dechex($coincount,8).$suggest);
}

sub solhash {
  my ($wallet,$solution) = @_;
  return securehash($wallet.$solution)
}