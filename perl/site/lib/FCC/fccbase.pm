#!/usr/bin/perl

package FCC::fccbase;

#######################################
#                                     #
#     FCC Database                    #
#                                     #
#    (C) 2017 Domero                  #
#                                     #
#######################################

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.01';
@ISA         = qw(Exporter);
@EXPORT      = qw(dbadd dbdel dbget dbsave dbload dbprint delcache);
@EXPORT_OK   = qw();

use gfio 1.08;
use gerr;

my $HP = {}; for (my $i=0;$i<10;$i++) { $HP->{$i}=$i }
$HP->{'A'}=10; $HP->{'B'}=11; $HP->{'C'}=12; $HP->{'D'}=13; $HP->{'E'}=14; $HP->{'F'}=15; 
my $CACHE={};

1;

sub delcache {
  $CACHE={}
}

sub gettid {
  my ($pos) = @_;
  my $fh=gfio::open('ledger.fcc');
  my $sz=$fh->filesize;
  if ($pos>=$sz) {
    if (!$CACHE->{$pos}) {
      return 0
    }
    return $CACHE->{$pos}
  }
  $fh->seek($pos+8); my $tid=$fh->read(64); $fh->close;
  return $tid
}

sub dbadd {
  my ($db,$tid,$pos,$gethash,$doublemode,$overwrite) = @_;
  $CACHE->{$pos}=$tid;
  my $p=0; my $fnd=0; my $h;
  if (!$gethash) { $gethash=\&gettid }
  do {
    $h=$HP->{substr($tid,$p,1)};
    my $v=$db->[$h];
    if (!defined $v) {
      $fnd=1 # new node
    } elsif (ref($v)) {
      $db=$v
    } else {
      if ($doublemode) {
        my $rtid=&$gethash($v);
        if ($tid eq $rtid) {
          if ($overwrite) {
            $fnd=1
          } else {
            $fnd=2
          }
        } else {
          $fnd=3
        }
      } elsif ($pos==$v) {
        $fnd=2 # already stored
      } else {
        $fnd=3 # make new link for previous node
      }
    }
    $p++
  } until ($fnd || ($p>=64));
  if ($fnd == 1) {
    # new node
    $db->[$h]=$pos
  } elsif ($fnd == 3) {
    # new link
    my $rpos=$db->[$h];
    $db->[$h]=[];
    my $ptid=&$gethash($rpos);
    my $nh=$HP->{substr($tid,$p,1)};
    my $nr=$HP->{substr($ptid,$p,1)};
    while ($nr == $nh) {
      $db=$db->[$h];
      $db->[$nh]=[];
      $p++; $h=$nh;
      $nh=$HP->{substr($tid,$p,1)};
      $nr=$HP->{substr($ptid,$p,1)};      
    }
    $db->[$h][$nh]=$pos;
    $db->[$h][$nr]=$rpos;
  }
}

sub dbget {
  my ($db,$tid) = @_;
  my $p=0; my $h;
  do {
    $h=$HP->{substr($tid,$p,1)};
    my $v=$db->[$h];
    if (!defined $v) {
      return -1 # tid not stored!
    } elsif (ref($v)) {
      $db=$v
    } else {
      return $v
    }
    $p++
  } until ($p>=64);
  return -2
}

sub dbdel {
  my ($db,$tid) = @_;
  foreach my $k (keys %$CACHE) {
    if ($CACHE->{$k} eq $tid) { delete $CACHE->{$k} }
  }
  my $p=0; my $pf=0; my ($h,$v); my $pdb = []; my $ph;
  do {
    $h=$HP->{substr($tid,$p,1)};
    $v=$db->[$h];
    if (!defined $v) {
      return 0 # tid not stored!
    } elsif (ref($v)) {
      push @$pdb,[$db,$h]; $db=$v
    } else {
      $pf=1;
    }
    $p++
  } until ($pf || ($p>=64));
  if ($pf) {
    $db->[$h]=undef;
    my $cnt=0; my $fpos=0;
    do {
      # if still multiple leaves in brench, leave alone, if only one, see if this is a leaf
      for (my $t=0;$t<16;$t++) {
        if (defined $db->[$t]) {
          $fpos=$t; $cnt++; if ($cnt>1) { last }
        }
      }
      if ($cnt==1) {
        if (ref($db->[$fpos])) {
          # leaf can split up further nodes, then leave them alone, if scalar then delete
          return 1
        }
        # roll back single link to previous
        my $rpos=$db->[$fpos];
        $db->[$fpos]=undef;
        my $pp=pop @$pdb;
        if ($pp) {
          $pp->[0][$pp->[1]]=$rpos;
          $db=$pp->[0]
        }
      }
    } until ($cnt != 1);
    return 1
  }
  return 0
}

sub dbprint {
  my ($db,$sp) = @_;
  my $tot=0;
  if (!$sp) { $sp='' }
  for (my $i=0;$i<16;$i++) {
    if (defined $db->[$i]) {
      my $hv=(0,1,2,3,4,5,6,7,8,9,'A','B','C','D','E','F')[$i];
      if (ref($db->[$i])) {
        $tot+=dbprint($db->[$i],$sp.$hv)
      } else {
        print $sp; print $hv; $tot++;
        print "=".$db->[$i]."\n"
      }
    }
  }
  return $tot
}

sub dbsaveblock {
  my ($db) = @_;
  my $bytedata=""; my $rawdata="";
  for (my $i=0;$i<=15;$i++) {
    if (defined $db->[$i]) {
      if (ref($db->[$i])) {
        $bytedata.='11'
      } else {
        $bytedata.='10'
      }
    } else {
      $bytedata.='00';
    }
  }
  $rawdata=pack('B32',$bytedata);
  for (my $i=0;$i<=15;$i++) {
    if (defined $db->[$i]) {
      if (ref($db->[$i])) {
        $rawdata.=dbsaveblock($db->[$i])  
      } else {
        $rawdata.=pack('n',$db->[$i]>>32);
        $rawdata.=pack('N',$db->[$i])
      }
    }
  }
  return $rawdata
}

sub dbsave {
  my ($db,$name) = @_;
  if (!defined $db) { error "Database not defined" }
  if (!defined $name) { error "Name not defined" }
  gfio::create("$name.fcc",dbsaveblock($db))
}

sub dbloadblock {
  my ($data,$pos) = @_;
  my $db = [];
  my $bpl=unpack('N',substr($data,$pos,4)); $pos+=4;
  my @bp=();
  for (my $be=0;$be<=15;$be++) {
    my $ch=$bpl & 3; $bpl>>=2; unshift @bp,$ch;
  }
  my $be=0;
  foreach my $b (@bp) {
    if ($b == 2) {
      $db->[$be]=(unpack('n',substr($data,$pos,2))<<32)+unpack('N',substr($data,$pos+2,4));
      $pos+=6
    } elsif ($b == 3) {
      ($db->[$be],$pos)=@{ dbloadblock($data,$pos) };
    }
    $be++
  }
  return [ $db, $pos ]
}

sub dbload {
  my ($name) = @_;
  if (!-e "$name.fcc") { return [] }
  my $data=gfio::content("$name.fcc");
  my ($db,$pos)= @{ dbloadblock($data,0) };
  return $db
}

# EOF FCC database (C) 2017 Chaosje, Domero