#!/usr/bin/perl

package FCC::ledger;

#######################################
#                                     #
#     FCC Ledger                      #
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
@EXPORT      = ();
@EXPORT_OK   = qw(posdb findtransaction balance history lasthistory volume);

use gfio 1.08;
use Digest::SHA qw(sha256_hex sha512_hex);
use Crypt::Ed25519;
use POSIX;
use gerr qw(error);
use JSON qw(decode_json encode_json);
use FCC::fccbase qw(dbadd dbget dbdel);
use FCC::transaction qw(hexdec validh64 readblock maketransid);
use FCC::wallet 1.02 qw(octhex hexoct securehash validatehash validwallet);

my $TRANSTYPES = {
  genesis => '0',
  in => '1',
  out => '2',
  coinbase => '3'
};

my $FCCVERSION = "0101";

1;

###################################################################################################################################
# =================================================================================================================================

# Ledger-blocks: (all big-endian)

# offset  length  content
#      0       4  difference of position of the previous transaction in the chain compared to this position (equal to length previous block)
#      4       4  difference of position of the next transaction in the chain compared to this position (equal to length block)
#      8      64  transaction id (next fields from 'number' on, secure-hashed (sha256(sha512(data)))
#     72      64  cumulative hash of all transaction in-id's and coinbase id's
#    136      12  transaction number in chain (0=genesis) 48 bit
#    148       4  version
#    152       1  type
#    153      64  previous id (any transaction type)

# In / Genesis / Coinbase

#    217       8  time, epoch is 00:00:00 UTC, January 1, 1970 (UNIX)
#    225       2  number of out addresses ( = 1 for genesis/coinbase)

# In

#    227       2  number of in addresses
#    229     192  signature (public key (64) followed by signature (128))
#    421   64num  list of id's of collected out-transactions to form in-addresses

# =================================================================================================================================

# Out / Coinbase / Genesis

#    217      68  FCC-wallet address
#    285      16  Amount in 64 bit (100000000 = 1 FCC)
#    301       4  fee = 0 for coinbase and genesis, minimum = 1 = 0,01% maximum = 10000 (100%)

# All

# 227/Xin/305  1  block identifier 'z'

# CAREFUL: Ledger will end with a pointer to the last block, which will be the beginning of the next block,
#          thus forming a double linked list to search from the beginning or the behind!

###################################################################################################################################
###################################################################################################################################

sub blockposdb_hdr {
  my($fh,$pos)=@_;
  $fh->seek($pos+4);
  my $next=hexdec($fh->read(4));
  my $tid=$fh->read(64);
  $fh->seek($pos+148);
  my $type=$fh->read(1);
  return ($next,$tid,$type)
}

sub blockposdb_outlist {  # inblock only
  my($fh,$pos,$type)=@_;
  my $outl=[];
  $fh->seek($pos+227);
  my $nin=hexdec($fh->read(2));
  $fh->seek($pos+421);
  for (my $i=0;$i<$nin;$i++) { push @{$outl},$fh->read(64) }
  return $outl;
}

sub blockposdb {
  if(!-e 'ledger.fcc'){ return undef }
  my $fh=gfio::open('ledger.fcc','r');
  my $DB = []; my $POS = 0;
  my $t;
  while($POS+4 < -s "ledger.fcc"){
    my ($size,$tid,$type)=blockposdb_hdr($fh,$POS);
    print "$type :: $tid :: $size     \r";
    if($type ne $TRANSTYPES->{out}){
      if($type eq $TRANSTYPES->{in}){
        # Del Spent OutBlock
        for my $tid ( @{blockposdb_outlist($fh,$POS)} ){
          dbdel($DB,$tid)
        }
      }
    }
    else{
      dbadd($DB,$tid,$POS);
    }
    $POS+=$size;
  }
  return ($DB,$POS)
}

###################################################################################################################################
###################################################################################################################################


sub rd_blockhdr {
  my($fh,$pos)=@_;
  $fh->seek($pos);
  my $prev=hexdec($fh->read(4));
  my $next=hexdec($fh->read(4));
  my $tid=$fh->read(64);
  my $cid=$fh->read(64);
  my $num=$fh->read(12);
  my $version=$fh->read(4);
  my $type=$fh->read(1);
  my $pid=$fh->read(64);
  return ($prev,$next,$tid,$cid,$num,$version,$type,$pid)
}

sub rd_block_tid {
  my($fh,$pos)=@_;
  $fh->seek($pos);
  my $prev=hexdec($fh->read(4));
  my $next=hexdec($fh->read(4));
  my $tid=$fh->read(64);
  return ($prev,$next,$tid)
}

sub rd_inblock {
  my($fh,$pos,$transaction)=@_;
  $fh->seek($pos+217);
  $transaction->{time}=hexdec($fh->read(8));
  $transaction->{numout}=hexdec($fh->read(2));
  $transaction->{outblocks}=[];
  $transaction->{inblocks}=[];
  if (!$transaction->{coinbase}) {
    $fh->seek($pos+227); $transaction->{numin}=hexdec($fh->read(2)); 
    $fh->seek($pos+421);
    print "[read $transaction->{numin} inblocks]\n";
    for (my $i=0;$i<$transaction->{numin};$i++) {
      push @{$transaction->{inblocks}},$fh->read(64)
    }
  }
}

sub rd_outblock {
  my($fh,$pos,$tid,$transaction)=@_;
  $fh->seek($pos+217);
  push @{$transaction->{outblocks}},{
    tid => $tid,
    wallet => $fh->read(68),
    amount => hexdec($fh->read(16)),
    fee => hexdec($fh->read(4))
  };
}

sub rd_pos {
  my($fh,$pos,$ftid)=@_;
  my($prev,$next,$tid)=rd_block_tid($fh,$pos);
  if ($ftid eq $tid) { return (1,$pos,$prev,$next) }
  return (0,-1,$prev,$next,$tid)
}

sub rd_inpos {
  my($fh,$pos)=@_;
  my($prev,$next,$tid,$cid,$num,$version,$type,$pid)=rd_blockhdr($fh,$pos);
  if ($type ne $TRANSTYPES->{out}) { return (1,$pos,$prev,$next) }
  return (0,-1,$prev,$next)
}

sub rd_block {
  my($fh,$pos)=@_;
  my($prev,$next,$tid)=rd_block_tid($fh,$pos);
  return ($tid,$prev,$next)
}

# =================================================================================================================================
###################################################################################################################################
# =================================================================================================================================
# Ledger & Wallet States
sub validstate {
  my ($wid) = @_;
  if (defined $wid && !validwallet($wid)) { return { wallet => $wid, error => 'invalid wallet' } }
  if (!-e 'ledger.fcc'){ return { wallet => $wid, error => 'no ledger found' } }
  return {};
}
# =================================================================================================================================

sub findtransaction {
  my ($ftid) = @_;
print "[find $ftid]\n";
  if (!validh64($ftid)) { return { error => 'invalid transaction ID' } }
  my $fh=gfio::open('ledger.fcc','r');
  my $spos=0;
  my $end = $fh->filesize()-4;
  my ($found,$fpos,$sprev,$snext)=(0,0);
  while($spos<$end && $found eq 0) {
    ($found,$fpos,$sprev,$snext)=rd_pos($fh,$spos,$ftid);
    if($found eq 0){ $spos+=$snext; }else{ $spos-=$sprev }
  }
  my $block=($fpos>0&&$fpos<$end ? readblock($fpos):undef);
  if(ref($block) eq 'HASH'){ 
    $block->{pos}=$fpos;
    $found=0;
    while($spos>=0 && $found eq 0) {
      ($found,$fpos,$sprev,$snext)=rd_inpos($fh,$spos);
      if($found eq 0){ $spos-=$sprev; }else{$spos+=$snext;}
    }
    $block->{inblock}=($fpos>-1&&$fpos<$end ? readblock($fpos):undef);
    if(ref($block->{inblock}) eq 'HASH'){
      $block->{inblock}{pos}=$fpos;
      $block->{inblock}{outblocks}={};
      $found=0;
      for(my $n=0;$n<$block->{inblock}{nout}&&$spos<$end;$n++){
        my ($tid,$sprev,$snext)=rd_block($fh,$spos);
        $block->{inblock}{outblocks}{$tid}=$spos;
        if($ftid eq $tid){ $block->{index}=$n }
        $spos+=$snext;
      }
    }
  }
  return $block
}

# =================================================================================================================================
# ? FCC::fccbase::gettid($pos);
# FCC::fccbase::dbadd($tid,$pos);
# FCC::fccbase::dbget($tid);
# =================================================================================================================================

sub balance {
  my ($wid) = @_;
  my $ckid=validstate($wid); if ($ckid->{error}){ return $ckid }
  my $fh=gfio::open('ledger.fcc','r');
  my $pos=0; my $end=$fh->filesize()-4;
  my $outlist={};
  my $lastin={};
  my $amountin = 0;
  my $amountspent = 0;
  my $feespent = 0;
  my $spendable = 0;
  my $debetblocks = 0;
  my $creditblocks = 0;
  while($pos<$end) {
    $fh->seek($pos+4);
    my $next=hexdec($fh->read(4));
    my $tid=$fh->read(64);
    $fh->seek($pos+152);
    my $type=$fh->read(1);
    if ($type eq $TRANSTYPES->{out}) {
      $lastin->{lastout}++;
      $fh->seek($pos+217);
      my $cwid=$fh->read(68);
      $outlist->{$tid}=$cwid;

      # skip change money
      if ($lastin->{numout} ne $lastin->{lastout}) {
        $fh->seek($pos+285);
        my $amount=hexdec($fh->read(16));
        my $fee=hexdec($fh->read(4));

        # spent money!
        if (!$lastin->{coinbase} && $wid eq $lastin->{wallet}) {
          my $ffee=$amount*($fee/10000);
          $amountspent+=$amount;
          $feespent+=$ffee;
          $creditblocks++;
        }

        # claimed money!
        if ($wid eq $cwid) {
          $amountin+=$amount;
          $debetblocks++;
        }

      }

    } else {
      $lastin->{tid}=$tid;
      $lastin->{coinbase}=($type ne $TRANSTYPES->{in} ? 1:0);
      $fh->seek($pos+217);
      $lastin->{time}=hexdec($fh->read(8));
      $lastin->{numout}=hexdec($fh->read(2));
      $lastin->{lastout}=0;
#      if (!$lastin->{coinbase}) {
        $fh->seek($pos+421);
        my $tid=$fh->read(64);
        $lastin->{wallet}=$outlist->{$tid};
#      }
    }
    $pos+=$next
  }  
  $fh->close;
  return {
    wallet => $wid,
    balance => {
      totalin => $amountin,
      totalspent => $amountspent,
      totalfee => $feespent,
      spendable => $amountin-$amountspent-$feespent,
      totalcredit => $creditblocks,
      totaldebet => $debetblocks
    }
  }  
}

# =================================================================================================================================

sub history {
  my ($wid) = @_;
  my $ckid=validstate($wid); if ($ckid->{error}){ return $ckid }
  my $fh=gfio::open('ledger.fcc','r');
  my $pos=0; my $end=$fh->filesize()-4;
  my $hist=[]; my $outlist={}; my $lastin={};
  my $amountin = 0;
  my $amountspent = 0;
  my $feespent = 0;
  my $spendable = 0;
  my $debetblocks = 0;
  my $creditblocks = 0;
  while($pos<$end) {
    $fh->seek($pos+4);
    my $next=hexdec($fh->read(4));
    my $tid=$fh->read(64);
    $fh->seek($pos+152);
    my $type=$fh->read(1);
    if ($type eq $TRANSTYPES->{out}) {
      $lastin->{lastout}++;
      # to spend money!
      $fh->seek($pos+217);
      my $cwid=$fh->read(68);
      $outlist->{$tid}=$cwid;

      # skip change money
      if ($lastin->{numout} ne $lastin->{lastout}) {
        $fh->seek($pos+285);
        my $amount=hexdec($fh->read(16));
        my $fee=hexdec($fh->read(4));

        if (!$lastin->{coinbase} && $wid eq $lastin->{wallet}) {
          my $ffee=int($amount*($fee/10000));
          $amountspent+=$amount;
          $feespent+=$ffee;
          $creditblocks++;
          push @$hist,{
            tid => $lastin->{tid},
            type => 'credit',
            amount => $amount,
            fee => $fee,
            to => $cwid,
            time => $lastin->{time}
          };
        }

        if ($wid eq $cwid) {
          $amountin+=$amount;
          $debetblocks++;
          push @$hist,{
            tid => $lastin->{tid},
            type => 'debet',
            amount => $amount,
            coinbase => $lastin->{coinbase},
            from => $lastin->{wallet},
            time => $lastin->{time}
          };
        }

      }

    } else {
      $lastin->{tid}=$tid;
      $lastin->{coinbase}=0;
      if ($type ne $TRANSTYPES->{in}) {
        $lastin->{coinbase}=1
      }
      $fh->seek($pos+217);
      $lastin->{time}=hexdec($fh->read(8));
      $lastin->{numout}=hexdec($fh->read(2));
      $lastin->{lastout}=0;
#      if (!$lastin->{coinbase}) {
        $fh->seek($pos+421);
        my $tid=$fh->read(64);
        $lastin->{wallet}=$outlist->{$tid};
#      }
    }
    $pos+=$next
  }  
  $fh->close;
  return {
    wallet => $wid,
    history => $hist,
    balance => {
      totalin => $amountin,
      totalspent => $amountspent,
      totalfee => $feespent,
      spendable => $amountin-$amountspent-$feespent,
      totalcredit => $creditblocks,
      totaldebet => $debetblocks
    }
  }  
}

# =================================================================================================================================

sub lasthistory {
  my ($wid,$time) = @_;
  my $ckid=validstate($wid); if ($ckid->{error}){ return $ckid }
  my $fh=gfio::open('ledger.fcc','r');
  my $pos=0; my $end=$fh->filesize()-4;
  my $hist=[]; my $outlist={}; my $lastin={};
  while($pos<$end) {
    $fh->seek($pos+4);
    my $next=hexdec($fh->read(4));
    my $tid=$fh->read(64);
    $fh->seek($pos+152);
    my $type=$fh->read(1);
    if ($type eq $TRANSTYPES->{out}) {
      $lastin->{lastout}++;
      # to spend money!
      $fh->seek($pos+217);
      my $cwid=$fh->read(68);
      $outlist->{$tid}=$cwid;

      # skip change money && history
      if ($lastin->{numout} ne $lastin->{lastout} && $lastin->{time} > $time) {
        $fh->seek($pos+285);
        my $amount=hexdec($fh->read(16));
        my $fee=hexdec($fh->read(4));

        if (!$lastin->{coinbase} && $wid eq $lastin->{wallet}) {
          push @$hist,{
            tid => $lastin->{tid},
            type => 'credit',
            amount => $amount,
            fee => $fee,
            to => $cwid,
            time => $lastin->{time}
          };
        }

        if ($wid eq $cwid) {
          push @$hist,{
            tid => $lastin->{tid},
            type => 'debet',
            amount => $amount,
            coinbase => $lastin->{coinbase},
            from => $lastin->{wallet},
            time => $lastin->{time}
          };
        }

      }

    } else {
      $lastin->{tid}=$tid;
      $lastin->{coinbase}=0;
      if ($type ne $TRANSTYPES->{in}) {
        $lastin->{coinbase}=1
      }
      $fh->seek($pos+217);
      $lastin->{time}=hexdec($fh->read(8));
      $lastin->{numout}=hexdec($fh->read(2));
      $lastin->{lastout}=0;
#      if (!$lastin->{coinbase}) {
        $fh->seek($pos+421);
        my $tid=$fh->read(64);
        $lastin->{wallet}=$outlist->{$tid};
#      }
    }
    $pos+=$next
  }  
  $fh->close;
  return {
    wallet => $wid,
    history => $hist
  }  
}

# =================================================================================================================================

sub volume {
  my $ckid=validstate(); if ($ckid->{error}){ return $ckid }
  my $fh=gfio::open('ledger.fcc','r');
  my $pos=0; my $end=$fh->filesize()-4;
  my $outtrans={};
  while($pos<$end) {
    $fh->seek($pos+4);
    my $next=hexdec($fh->read(4));
    $fh->seek($pos+152);
    my $type=$fh->read(1);
    if ($type eq $TRANSTYPES->{out}) {
      # to spend money!
      $fh->seek($pos+8);
      my $tid=$fh->read(64);
      $fh->seek($pos+285);
      my $amount=hexdec($fh->read(16));
      $outtrans->{$tid} = {
        amount => $amount
      }
    } elsif ($type eq $TRANSTYPES->{in}) {
      # spended money!
      $fh->seek($pos+227);
      my $numin=hexdec($fh->read(2)); $fh->seek($pos+421);
      for (my $i=0;$i<$numin;$i++) {
        my $itid=$fh->read(64);
        if ($outtrans->{$itid}) {
          delete $outtrans->{$itid}
        }
      }
    }
    $pos+=$next
  }
  my $totamount=0;
  foreach my $iid (keys %{$outtrans}) {
    my $amount=$outtrans->{$iid}{amount};
    $totamount+=$amount;
  }
  $fh->close;
  return $totamount
}

# EOF FCC::ledger by Chaosje
