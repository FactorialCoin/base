#!/usr/bin/perl

package FCC::fccbase;

#######################################
#                                     #
#     FCC Database                    #
#                                     #
#    (C) 2018 Chaosje, Domero         #
#                                     #
#######################################

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '2.2.1';
@ISA         = qw(Exporter);
@EXPORT      = qw(dbadd dbdel dbget dbsave dbload dbprint dblist delcache);
@EXPORT_OK   = qw();

use gfio 1.10;
use gerr;
use FCC::global 2.2.1;
use FCC::wallet 2.1.4;

my $HP = {}; for (my $i=0;$i<10;$i++) { $HP->{$i}=$i }
$HP->{'A'}=10; $HP->{'B'}=11; $HP->{'C'}=12; $HP->{'D'}=13; $HP->{'E'}=14; $HP->{'F'}=15; 
my $CACHE={};

1;

sub delcache {
  $CACHE={}
}

sub unp48 {
  my ($data,$pos) = @_;
  if (!defined $pos) { error("FCC.fccbase.unp48: No position given") }
  return (unpack('n',substr($data,$pos,2))<<32)+unpack('N',substr($data,$pos+2,4));
}
sub pck48 {
  my ($pos) = @_;
  if (!defined $pos) { error("FCC.fccbase.pck48: No position given") }
  if ($pos =~ /[^0-9]/) { error("FCC.fccbase.pck48: Illegal position '$pos' given") }
  return pack('n',$pos>>32).pack('N',$pos)
}

sub gettid {
  my ($pos) = @_;
  my $fh=gfio::open("ledger$FCCEXT");
  my $sz=$fh->filesize;
  if ($pos>=$sz) {
    $fh->close;
    if (!$CACHE->{$pos}) {
      return 0
    }
    return $CACHE->{$pos}
  }
  $fh->seek($pos+8); my $tid=$fh->read(64); $fh->close;
  return $tid
}

sub getwallet {
  my ($pos) = @_;
  my $fh=gfio::open("ledger$FCCEXT");
  my $sz=$fh->filesize;
  if ($pos>=$sz) {
    $fh->close;
    if (!$CACHE->{$pos}) {
      return 0
    }
    return $CACHE->{$pos}
  }
  $fh->seek($pos+152); my $type=hexdec($fh->read(1));
  my $wallet;
  if ($type eq $TRANSTYPES->{in}) {
    $fh->seek($pos+229); my $pubkey=$fh->read(64); $wallet=substr(createwalletaddress($pubkey),2,64)
  } else {
    $fh->seek($pos+219); $wallet=$fh->read(64)
  }
  $fh->close;
  return $wallet
}

sub searchpos {
  my ($data,$search) = @_;
  my $tot=int(length($data) / 7);
  my $bn=int(log($tot)/log(2));
  my $bp=2**$bn; my $jump=$bp;
  do {
    $jump>>=1; my $pos=($bp-1)*7;
    my $sp=0;
    if ($bp<=$tot) {
      $sp=unp48($data,$pos+1);
    }
    if (($bp>$tot) || ($sp>$search)) {
      $bp-=$jump
    } elsif ($sp == $search) {
      return $pos
    } else {
      $bp+=$jump
    }
    $bn--
  } until ($bn<0);
  error("FCC.fccbase.searchpos: Position '$search' not found in $tot datablocks")
}

sub walletlist {
  my ($data) = @_;
  my $list=[]; my $pos=0;
  while ($pos<length($data)) {
    my $item = { pos => unp48($data,$pos+1) };
    my $flags = ord(substr($data,$pos,1));
    $item->{type}=$flags & 15;
    $item->{spent}=$flags>>7;
    push @$list,$item;
    $pos+=7
  }
  return $list
}

sub dbadd {
  my ($db,$tid,$pos,$gethash,$arraymode,$type,$spent) = @_;
  if (length($tid) == 68) { $tid=substr($tid,2,64) }
  $CACHE->{$pos}=$tid;
  my $p=0; my $fnd=0; my $h;
  if (!$gethash) {
    if ($arraymode) {
      $gethash=\&getwallet
    } else {
      $gethash=\&gettid 
    }
  }
  do {
    $h=$HP->{substr($tid,$p,1)};
    my $v=$db->[$h];
    if (!defined $v) {
      # new node
      $fnd=2
    } elsif (ref($v)) {
      $db=$v
    } else {
      if ($arraymode) {
        my $rtid=&$gethash(unp48($v,1));
        if ($tid eq $rtid) {
          $fnd=4
        } else {
          $fnd=3
        }
      } elsif ($pos==$v) {
        $fnd=1 # already stored
      } else {
        $fnd=3 # make new link for previous node
      }
    }
    $p++
  } until ($fnd || ($p>=64));
  # fnd == 1: do nothing
  if ($fnd == 2) {
    # new node
    if ($arraymode) {
      if ($spent) {
        error("FCC.fccbase.dbadd: Wallet '$tid' at position '$pos' not found to be marked as spent")
      }
      $db->[$h]=chr($type).pck48($pos)
    } else {
      $db->[$h]=$pos
    }
  } elsif ($fnd == 3) {
    # new link
    my $rpos=$db->[$h];
    $db->[$h]=[];
    my $hpos=$rpos;
    if ($arraymode) { $hpos=unp48($rpos,1) }
    my $ptid=&$gethash($hpos);
    my $nh=$HP->{substr($tid,$p,1)};
    my $nr=$HP->{substr($ptid,$p,1)};
    while ($nr == $nh) {
      $db=$db->[$h];
      $db->[$nh]=[];
      $p++; $h=$nh;
      $nh=$HP->{substr($tid,$p,1)};
      $nr=$HP->{substr($ptid,$p,1)};      
    }
    if ($arraymode) {
      $db->[$h][$nh]=chr($type).pck48($pos)
    } else {
      $db->[$h][$nh]=$pos
    }
    $db->[$h][$nr]=$rpos;
  } elsif ($fnd == 4) {
    if ($spent) {
      my $sp=searchpos($db->[$h],$pos);
      my $f=ord(substr($db->[$h],$sp,1));
      $f |= 128;
      substr($db->[$h],$sp,1) = chr($f)
    } else {
      $db->[$h].=chr($type).pck48($pos)
    }
  }
}

sub dbget {
  my ($db,$tid,$arraymode,$pos) = @_;
  my $p=0; my $h;
  if (!$tid) {
    if ($arraymode) { return [] }
    return -1 # tid not stored!
  }
  if (length($tid) == 68) { $tid=substr($tid,2,64) }
  do {
    $h=$HP->{substr($tid,$p,1)};
    my $v=$db->[$h];
    if (!defined $v) {
      if ($arraymode) { return [] }
      return -1 # tid not stored!
    } elsif (ref($v)) {
      $db=$v
    } else {
      if ($arraymode) {
        if (length($v)>0) {
          my $wpos=unp48($v,1);
          my $wal=getwallet($wpos);
          if ($wal eq $tid) {
            if (defined $pos) {
              my $fp=searchpos($v,$pos);
              my $flags=substr($v,$fp,1);
              # listpos can be used for dbdel
              return { listpos => $fp, type => $flags & 15, spent => $flags>>7 }
            }
            return walletlist($v)
          }
          return []
        } else {
          return []
        }
      }
      return $v
    }
    $p++
  } until ($p>=64);
  if ($arraymode) { return [] }
  return -1
}

sub dbdel {
  my ($db,$tid,$pos) = @_;
  if (!$tid) { return 0 }
  if (length($tid) == 68) { $tid=substr($tid,2,64) }
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
    if (defined $pos) {
      my $fp=searchpos($db->[$h],$pos);
      $db->[$h]=substr($db->[$h],0,$pos).substr($db->[$h],$pos+7);
      return 1
    }
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
        print "=".ord($db->[$i])."\n"
      }
    }
  }
  return $tot
}

sub dblist {
  my ($db,$sp,$list) = @_;
  my $tot=0;
  if (!$list) { $list=[] }
  if (!$sp) { $sp='' }
  for (my $i=0;$i<16;$i++) {
    if (defined $db->[$i]) {
      my $hv=(0,1,2,3,4,5,6,7,8,9,'A','B','C','D','E','F')[$i];
      if (ref($db->[$i])) {
        my ($t,$l)=dblist($db->[$i],$sp.$hv,$list);
        $tot+=$t;
        $list=$l;
      } else {
        $tot++; push @{$list}, $sp.$hv."=".ord($db->[$i])
      }
    }
  }
  return ($tot,$list)
}

sub dbsaveblock {
  my ($db,$arraymode) = @_;
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
        $rawdata.=dbsaveblock($db->[$i],$arraymode)  
      } else {
        if ($arraymode) {
          my $numdata=int(length($db->[$i]) / 7);
          $rawdata.=substr(pack('N',$numdata),1).$db->[$i]
        } else {
          $rawdata.=pck48($db->[$i]);
        }
      }
    }
  }
  return $rawdata
}

sub dbsave {
  my ($db,$name,$arraymode) = @_;
  if (!defined $db) { error "FCC.fccbase.dbsave: Database not defined" }
  if (!defined $name) { error "FCC.fccbase.dbsave: Name not defined" }
  my $data=dbsaveblock($db,$arraymode);
  if (length($data) > 4) {
    gfio::create($name,$data)
  }
}

sub dbloadblock {
  my ($data,$pos,$arraymode) = @_;
  my $db = [];
  my $bpl=unpack('N',substr($data,$pos,4)); $pos+=4;
  my @bp=();
  for (my $be=0;$be<=15;$be++) {
    my $ch=$bpl & 3; $bpl>>=2; unshift @bp,$ch;
  }
  my $be=0;
  foreach my $b (@bp) {
    if ($b == 2) {
      if ($arraymode) {
        my $numdata=unpack('N',"\0".substr($data,$pos,3));
        $pos+=3;
        $db->[$be]=substr($data,$pos,$numdata*7);
        $pos+=$numdata*7
      } else {
        $db->[$be]=unp48($data,$pos);
        $pos+=6
      }
    } elsif ($b == 3) {
      ($db->[$be],$pos)=@{ dbloadblock($data,$pos,$arraymode) };
    }
    $be++
  }
  return [ $db, $pos ]
}

sub dbload {
  my ($name,$arraymode) = @_;
  if (!-e $name) { return [] }
  my $data=gfio::content($name);
  my ($db,$pos)= @{ dbloadblock($data,0,$arraymode) };
  return $db
}

# EOF FCC database (C) 2018 Chaosje, Domero