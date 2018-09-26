#!/usr/bin/perl

package FCC::fcc;

#######################################
#                                     #
#     FCC Currency Kernel             #
#                                     #
#    (C) 2018 Domero, Chaosje         #
#                                     #
#######################################

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.24';
@ISA         = qw(Exporter);
@EXPORT      = qw(version load save allowsave deref processledger collectspendblocks inblocklist saldo readblock readlastblock encodetransaction 
                  addtoledger ledgerdata createcoinbase createtransaction createfeetransaction calculatefee getdbhash getinblock sealinfo);
@EXPORT_OK   = qw(walletposlist);

use Crypt::Ed25519;
use gfio 1.10;
use gerr;
use FCC::global 1.28;
use FCC::wallet 2.12;
use FCC::fccbase 1.02;

my $SDB = []; # spendable outblocks in positions (non ordered quick search) => validate
my $OBL = []; # outblocklist in positions (ordered slow search) => create transaction
my $WDB = {}; # wallet block position guesslist
my $LEDGERBUFFER = "";
my $LEDGERSTACK = [];
my $REPORTONLY = 0;
my $LEDGERERROR = "";
my $BLOCKSAVE = 0;
my $DBHASH = "";

1;

sub addtoledger {
  my ($blocks) = @_;
  if (!-e "ledger$FCCEXT") {
    if (substr($blocks->[0],152,1) ne $TRANSTYPES->{genesis}) {
      error "No ledger found and not writing a genesis block"
    }
  }
  foreach my $block (@$blocks) {
    push @$LEDGERSTACK,$block
  }
  saveledgerdata()
}

sub encodetransaction {
  # I hope I've written it as clear as possible ;)
  # Don't mind the redundancy, it's for clearness in the code, things may change... ;)
  my ($inblock,$outblocks) = @_;
  my $tohash=""; my $blocks=[]; my $pin={};
  # inblock
  if ($inblock->{type} eq 'genesis') {
    my $block='0000'; # prev: signals double zero end searching from behind
    $block.='0000'; # next: to be changed later
    $block.='x'x64; # tid: to be changed later this sub
    $block.=$FCCMAGIC; # cumhash magical genesis init ;) h4x0rz
    $block.='000000000000'; # block-number = 0
    $block.=$FCCVERSION;
    $block.=$TRANSTYPES->{genesis};
    $block.='0'x64; # prev tid
    $block.=dechex($inblock->{fcctime},8);
    if ($COIN eq 'PTTP') {
      $block.='3E'; # 62 out blocks
    } else {
      $block.='01'; # 1 out block
    }
    # replace TID
    my $idhash=securehash(substr($block,136));
    substr($block,8,64,$idhash);
    push @$blocks,$block
  } elsif (($inblock->{type} eq 'coinbase') || ($inblock->{type} eq 'in') || ($inblock->{type} eq 'fee')) {
    # we already got the previous pointer! we'll correct this later in the ledger... (overwrite 4 bytes from behind)
    # so we'll make a perfect block to overwrite!
    # get previous transaction (last)
    if ($#{$outblocks}<0) {
      error "No outblocks given in transaction"
    }
    my $lastblock=readlastblock();
    my $block=dechex($lastblock->{next},4); # prev pointer
    $block.='0000'; # next: to be changed later
    $block.='x'x64; # tid: to be changed later this sub
    $block.='y'x64; # cumhash, to be filled in later this sub (when tid is knwon)
    $pin->{num}=$lastblock->{num}+1;
    $block.=dechex($pin->{num},12);
    $block.=$FCCVERSION;
    $block.=dechex($TRANSTYPES->{$inblock->{type}},1);
    $block.=$lastblock->{tid};
    $block.=dechex($inblock->{fcctime},8);
    if ($inblock->{type} eq 'in') {
      $block.=dechex(1+$#{$outblocks},2);
      $block.=dechex(1+$#{$inblock->{inblocks}},2);
      $block.=$inblock->{pubkey}.$inblock->{signature};
      if (length($block) != 421) {
        error "Do not try to input invalid transactions please ;) be kind, use a mirror and read Alice in Wonderland."
      }
      foreach my $ibid (@{$inblock->{inblocks}}) {
        if (!validh64($ibid)) {
          error "Invalid TID found in input block! do not temper please. Read a hitchhikers guide and stay on the infinite possibility path ;)"
        }
        $block.=$ibid
      }
    } elsif ($inblock->{type} eq 'coinbase') {
      $block.=dechex(1+$#{$outblocks},2); # 2 blocks (miner, node)
      $block.=dechex($inblock->{coincount},8); # needed to validate
      $block.=$inblock->{signature}; # signed by FCC-server
    } elsif ($inblock->{type} eq 'fee') {
      $block.=dechex(1+$#{$outblocks},4); # max 65535 nodes per block
      $block.=dechex($inblock->{spare},8); # unpayed amount to accumulate
      $block.=dechex($inblock->{blockheight},12);
      $block.=$inblock->{signature} # signed by FCC-server
    }
    # replace TID
    my $idhash=securehash(substr($block,136));
    substr($block,8,64,$idhash); $pin->{tid}=$idhash;
    # cumulative hash (validates the whole ledger)
    my $cumhash=securehash($idhash.$lastblock->{tcum});
    substr($block,72,64,$cumhash); $pin->{tcum}=$cumhash;
    $pin->{size}=length($block)+1;
    push @$blocks,$block    
  } else {
    error "Error: unknown inblock found: '$inblock->{type}'"
  }
  # outblocks
  if ($inblock->{type} eq 'genesis') {
    if ($COIN eq 'PTTP') {
      for (my $b=0;$b<62;$b++) {
        my $block;
        if ($b==0) {
          $block=dechex(228,4); # relative offset to position of previous block
        } else {
          $block=dechex(306,4); # relative offset to previous outblock
        }
        $block.='0000'; # next: to be changed later (when size is known)
        $block.='x'x64; # tid: to be changed later this sub (when data to hash is knwon)
        $block.='y'x64; # cumhash, to be filled in later this sub (when tid is knwon)
        $block.=dechex($b+1,12); # block-number
        $block.=$FCCVERSION;
        $block.=$TRANSTYPES->{$outblocks->[$b]{type}};
        $block.=substr($blocks->[$#{$blocks}],8,64); # prev tid
        $block.=$outblocks->[$b]{wallet}; # FCC-wallet of receiver
        $block.=dechex($outblocks->[$b]{amount},16); # ICO / GIVE AWAY / DEVELOPERS / TESTERS / FIRST JOINERS!!!
        $block.='0000'; # fee = 0 (wouldn't make any sense since I'm the only node starting it up)
        # replace TID
        my $idhash=securehash(substr($block,136));
        substr($block,8,64,$idhash);
        # cumulative hash (validates the whole ledger)
        my $cumhash=securehash($idhash.substr($blocks->[$#{$blocks}],72,64));
        substr($block,72,64,$cumhash);
        push @$blocks,$block
      }
    } else {
      # create the genesis out-block (yes the genesis is spendable, weird Satoshi 50 BTC)
      my $block=dechex(228,4); # relative offset to position of previous block
      $block.='0000'; # next: to be changed later (when size is known)
      $block.='x'x64; # tid: to be changed later this sub (when data to hash is knwon)
      $block.='y'x64; # cumhash, to be filled in later this sub (when tid is knwon)
      $block.='000000000001'; # block-number = 1
      $block.=$FCCVERSION;
      $block.=$TRANSTYPES->{$outblocks->[0]{type}};
      $block.=substr($blocks->[0],8,64); # prev tid
      $block.=$outblocks->[0]{wallet}; # FCC-wallet of receiver
      $block.=dechex($outblocks->[0]{amount},16); # ICO / GIVE AWAY / DEVELOPERS / TESTERS / FIRST JOINERS!!!
      $block.='0000'; # fee = 0 (wouldn't make any sense since I'm the only node starting it up)
      # replace TID
      my $idhash=securehash(substr($block,136));
      substr($block,8,64,$idhash);
      # cumulative hash (validates the whole ledger)
      my $cumhash=securehash($idhash.substr($blocks->[0],72,64));
      substr($block,72,64,$cumhash);
      push @$blocks,$block
    }
  } elsif (($inblock->{type} eq 'in') || ($inblock->{type} eq 'coinbase') || ($inblock->{type} eq 'fee')) {
    foreach my $outblock (@$outblocks) {
      my $block=dechex($pin->{size},4);
      $block.='0000'; # next: to be changed later (when size is known)
      $block.='x'x64; # tid: to be changed later this sub (when data to hash is knwon)
      $block.='y'x64; # cumhash, to be filled in later this sub (when tid is knwon)
      $pin->{num}++;
      $block.=dechex($pin->{num},12);
      $block.=$FCCVERSION;
      $block.=$TRANSTYPES->{out};
      $block.=$pin->{tid}; # prev tid
      if (!validwallet($outblock->{wallet})) {
        error "Invalid wallet given in outblock of transaction"
      }
      $block.=$outblock->{wallet};
      $block.=dechex($outblock->{amount},16);
      $block.=dechex($outblock->{fee},4);
      if ($outblock->{expire}) {
        $block.=dechex($outblock->{expire},10);
      }
      # replace TID
      my $idhash=securehash(substr($block,136));
      substr($block,8,64,$idhash);
      # cumulative hash (validates the whole ledger)
      my $cumhash=securehash($idhash.$pin->{tcum});
      substr($block,72,64,$cumhash); $pin->{tcum}=$cumhash;
      $pin->{size}=length($block)+1; $pin->{tid}=$idhash;
      push @$blocks,$block    
    }
  }
  # Process blocks, add block identifier, set size/next
  foreach (my $b=0;$b<=$#{$blocks};$b++) {
    $blocks->[$b].='z';
    my $blen=length($blocks->[$b]);
    my $next=dechex($blen,4);
    substr($blocks->[$b],4,4,$next);
  }
  return $blocks
}

sub creategenesis {
  if ($COIN eq 'PTTP') {
    use FCC::pttp;
    my ($inblock,$outblocks)=pttpgenesis();
    my $blocks=encodetransaction($inblock,$outblocks);
    addtoledger($blocks); save();
    return
  }
  my $wallet=loadwallet();
  if (!$wallet) { $wallet=newwallet(); savewallet($wallet) }
  my $inblock = {
    type => 'genesis',
    fcctime => time + $FCCTIME,
    in => []
  };
  my $outblock = {
    type => 'out',
    wallet => $wallet->{wallet},
#    addr => '51037C0927DE0688B4A7544B3CFFDE543ECB75A421CA5A5F6850EBC0D2D5730D909A', # if you only had the private key :P
    amount => '501500000000000' # ICO and give-aways
  };
  my $blocks=encodetransaction($inblock,[$outblock]);
  addtoledger($blocks); save()
}

sub createcoinbase {
  my ($fcctime,$coincount,$signature,$outblocks) = @_;
  my $inblock = {
    type => 'coinbase',
    fcctime => $fcctime,
    coincount => $coincount,
    signature => $signature
  };
  my $blocks=encodetransaction($inblock,$outblocks);
  addtoledger($blocks);
  return 1
}

sub createtransaction {
  my ($fcctime,$pubkey,$signature,$inblocks,$outblocks) = @_;
  my $inblock = {
    type => 'in',
    fcctime => $fcctime,
    inblocks => $inblocks,
    pubkey => $pubkey,
    signature => $signature
  };
  my $blocks=encodetransaction($inblock,$outblocks);
  addtoledger($blocks);
}

sub createfeetransaction {
  my ($fcctime,$blockheight,$spare,$signature,$outblocks) = @_;
  my $inblock = {
    type => 'fee',
    fcctime => $fcctime,
    blockheight => $blockheight,
    spare => $spare,
    signature => $signature
  };
  my $blocks=encodetransaction($inblock,$outblocks);
  addtoledger($blocks);
}

sub allowsave {
  $BLOCKSAVE=0
}

sub save {
  if ($BLOCKSAVE) { return }
  my $last=readlastblock();
  if (-e "savepoint$FCCEXT") {
    my $data=gfio::content("savepoint$FCCEXT");
    my ($pos,$cumhash) = split(/ /,$data);
    if ($cumhash eq $last->{tcum}) { return }
  }
  gfio::create("savepoint$FCCEXT",join(' ',$last->{pos},$last->{tcum},$DBHASH));
  savewalletlist();
  saveoutblocklist();
  dbsave($SDB,"spenddb$FCCEXT")
}

sub load {
  if (!-e "ledger$FCCEXT") { killdb(); gfio::create("ledger$FCCEXT",''); return }  
  my $lastblock=readlastblock(); my $pos=0; my $cumhash='init';
  if (-e "savepoint$FCCEXT") {
    my $data=gfio::content("savepoint$FCCEXT");
    ($pos,$cumhash,$DBHASH) = split(/ /,$data);
    if (!$DBHASH) {
      print "\r ** Creating Database Hash"; print " "x54; print "\n";
      killdb(); $BLOCKSAVE=0; $DBHASH="";
      processledger(0,{ next => 0, num => -1, tid => '0'x64 })
    } else {
      loadwalletlist();
      loadoutblocklist();
      $SDB=dbload("spenddb$FCCEXT");
      if (($lastblock->{tcum} eq $cumhash) && ($lastblock->{pos} == $pos)) {
        return
      }
      processledger($pos,$lastblock)
    }
  } else {
    processledger(0,{ next => 0, num => -1, tid => '0'x64 })
  }
  save()
}

sub dbhash {
  my ($data) = @_;
  $DBHASH=securehash($DBHASH.$data)
}

sub getdbhash {
  return $DBHASH
}

sub addwallet {
  my ($wid,$pos) = @_;
  $wid=substr($wid,2,4);
  #print "{WADD $wid - $pos}\n";
  if (!defined $WDB->{$wid} || ($#{$WDB->{$wid}}<0)) {
    $WDB->{$wid}=[ $pos ]
  } else {
    my @pl=@{$WDB->{$wid}}; my $npl=$#{$WDB->{$wid}};
    #print "{WALFND $npl ",join(", ",@pl),"}\n";
    my $num=1+$#{$WDB->{$wid}};
    my $bn=int (log($num)/log(2));
    my $bp=2**$bn; my $jump=$bp; my $flag=0;
    do {
      $jump>>=1;
      my $sp=$WDB->{$wid}[$bp-1];
      if (!$sp || ($sp>$pos)) {
        $bp-=$jump; $flag=1
      } else {
        $bp+=$jump; $flag=2
      }
      $bn--
    } until ($bn<0);
    if ($flag==1) {
      splice(@{$WDB->{$wid}},$bp-1,0,$pos)
    } else {
      splice(@{$WDB->{$wid}},$bp,0,$pos)
    }
  }
}

sub delwallet {
  my ($wid,$pos) = @_;
  my $ow=$wid;
  $wid=substr($wid,2,4);
  #print "{WDEL $wid - $pos}\n";
  my $num=1+$#{$WDB->{$wid}};
  if (!$num) { error("DelWallet: wallet does not exist in database, position = $pos\n$ow") }
  my $bn=int (log($num)/log(2));
  my $bp=2**$bn; my $fnd=0; my $jump=$bp;
  do {
    $jump>>=1;
    my $sp=$WDB->{$wid}[$bp-1];
    if (!$sp || ($sp>$pos)) {
      $bp-=$jump
    } elsif ($sp==$pos) {
      $fnd=1
    } else {
      $bp+=$jump
    }
    $bn--
  } until ($fnd || ($bn<0));
  if (!$fnd) {
    error "Internal error: No existing wallet/position deleted!"
  }
  splice(@{$WDB->{$wid}},$bp-1,1)
}

sub walletposlist {
  my ($wid) = @_;
  $wid=substr($wid,2,4);
  return $WDB->{$wid}
}

sub savewalletlist {
  my $rawdata="";
  foreach my $wkey (keys %$WDB) {
    my $val=0;
    for (my $i=0;$i<4;$i++) {
      $val=($val<<4)+$HP->{substr($wkey,$i,1)}
    }
    $rawdata.=pack('n',$val);
    my $num=1+$#{$WDB->{$wkey}};
    $rawdata.=pack('N',$num);
    foreach my $pos (@{$WDB->{$wkey}}) {
      # assume ledger is 1Tb .. is 40 bit, 48 bit will do for now
      $rawdata.=pack('n',$pos>>32);
      $rawdata.=pack('N',$pos)
    }
  }
  gfio::create("walletdb$FCCEXT",$rawdata)
}

sub loadwalletlist {
  $WDB={};
  if (!-e "walletdb$FCCEXT") { return }
  my $data=gfio::content("walletdb$FCCEXT");
  my $pos=0; my $sz=length($data);
  my @hexlist=(0,1,2,3,4,5,6,7,8,9,'A','B','C','D','E','F');
  while ($pos<$sz) {
    my $val=unpack('n',substr($data,$pos,2)); $pos+=2;
    my $wid="";
    for (my $i=0;$i<4;$i++) {
      $wid=$hexlist[$val & 15].$wid; $val>>=4;
    }
    $WDB->{$wid}=[];
    my $num=unpack('N',substr($data,$pos,4)); $pos+=4;
    for (my $p=0;$p<$num;$p++) {
      push @{$WDB->{$wid}},(unpack('n',substr($data,$pos,2))<<32)+unpack('N',substr($data,$pos+2,4)); $pos+=6
    }
  }
}

sub saveoutblocklist {
  my $rawdata="";
  foreach my $pos (@{$OBL}) {
    $rawdata.=pack('n',$pos>>32);
    $rawdata.=pack('N',$pos)
  }
  gfio::create("outblocks$FCCEXT",$rawdata)
}

sub loadoutblocklist {
  $OBL=[];
  if (!-e "outblocks$FCCEXT") { return }
  my $data=gfio::content("outblocks$FCCEXT");
  my $pos=0; my $len=length($data);
  while ($pos<$len) {
    push @$OBL,(unpack('n',substr($data,$pos,2))<<32)+unpack('N',substr($data,$pos+2,4)); $pos+=6
  }
}

sub killdb {
  foreach my $file ("savepoint$FCCEXT","spenddb$FCCEXT","outblocks$FCCEXT","walletdb$FCCEXT") {
    if (-e $file) { unlink $file }
  }
  $BLOCKSAVE=1
}

sub truncateledger {
  my $fh=gfio::open("ledger$FCCEXT",'rw');
  my $sz=$fh->filesize(); my $pos=$sz-1;
  while ($pos>0) {
    $fh->seek($pos);  my $c=$fh->read(1); $pos--;
    if ($c eq 'z')  { last }
  }
  while ($pos>0) {
    $fh->seek($pos);
    my $c=$fh->read(1);
    if ($c eq 'z')  {
      my $block=readblock($pos+1);
      if ($RTRANSTYPES->{$block->{type}} ne 'out') {
        $fh->truncate($pos+5); $fh->close; return
      }
    }
    $pos--
  }
  $fh->close; unlink("ledger$FCCEXT")
}

sub illegalblock {
  my ($bi,$pbi,@error) = @_;
  my $error=join("\n",@error); my $bnr=$pbi->{num}+1; $bi->{error}=$error;
  if ($REPORTONLY) {
    $LEDGERERROR="Block $bnr. Pos $bi->{pos}.\n$error"; return
  }
  print "\n\n>>>>> ! LEDGER CORRUPT ! <<<<<\n\n$error\n\nPosition in file: $bi->{pos}\n    Block number: $bnr\n\n";
  print "Make a choice:\n1. Truncate the ledger\n2. Delete the ledger\n\n0. exit without action\n\n";
  do {
    print "Enter your choice (1) > ";
    my $choice=<STDIN>; chomp $choice;
    if ($choice eq "") { $choice=1 }
    if ($choice eq '1') {
      truncateledger($pbi); killdb();
      print "\nLedger truncated!\nPlease start the node again\n\n"; exit 1
    }
    if ($choice eq '2') {
      unlink("ledger$FCCEXT"); killdb();
      print "\nLedger deleted!\nPlease start the node again\n\n"; exit 1
    }
    if ($choice eq '0') {
      print "\nLedger still corrupted!\nPlease take appropriate action\n\n"; exit 1
    }
  } until (0)
}

sub validatespend {
  my ($fh,$bi,$md) = @_;
  my $w; $md->{signdata}=""; $md->{inamount}=0;
  foreach my $inblock (@{$md->{inblocks}}) {
    my $res=dbget($SDB,$inblock);
    if ($res<0) {
      $bi->{error}="Block '$inblock' in in-block is not a valid spendable out-block";
      return 0
    }
    $fh->seek($res+217); my $odat=$fh->read(84);
    my $wallet=substr($odat,0,68);
    #print ">> RES=$res; WALLET = $wallet\n";
    my $amount=hexdec(substr($odat,68));
    if (!$w) { $w=$wallet }
    elsif ($w ne $wallet) {
      $bi->{error}="In-block consists of different wallets";
      return 0
    }
    $md->{signdata}.=$inblock;
    $md->{inamount}+=$amount;
  }  
  my $vw=createwalletaddress($md->{pubkey});
  if ($vw ne $w) {
    $bi->{error}="Signing public key does not match the spending wallet";
    return 0
  }
  my $posdata="";
  foreach my $inblock (@{$md->{inblocks}}) {
    # mark block as unspendable
    my $res=dbget($SDB,$inblock); $posdata.=$res;
    if (!dbdel($SDB,$inblock)) {
      die "Chaosje: DBDEL should work!"
    }
    # binary search OBL
    my $num=$#{$OBL}+1;
    my $bn=int (log($num)/log(2));
    my $bp=2**$bn; my $fnd=0; my $jump=$bp;
    do {
      $jump>>=1;
      my $sp=$OBL->[$bp-1];
      if (!$sp || ($sp>$res)) {
        $bp-=$jump
      } elsif ($sp == $res) {
        splice(@$OBL,$bp-1,1); $fnd=1
      } else {
        $bp+=$jump
      }
      $bn--
    } until ($fnd || ($bn<0));
    if (!$fnd) { error "Chaosje, get your code straight" }
    delwallet($w,$res);
  }
  dbhash($md->{signdata}.$w.$posdata);
  return 1
}

sub processblock {
  my ($fh,$bi,$pbi,$md,$data) = @_;
  $bi->{error}="";
  if ($data =~ /[^0-9A-Zz]/) {
    illegalblock($bi,$pbi,"Corrupted block: invalid data");
    if ($LEDGERERROR) { return }
  }
  $bi->{tid}=substr($data,8,64);
  my $idhash=securehash(substr($data,136));
  if ($idhash ne $bi->{tid}) {
    illegalblock($bi,$pbi,"TID of block does not match the data in the block","TID found: $bi->{tid}","TID calculated: $idhash");
    if ($LEDGERERROR) { return }
  }
  $bi->{tcum}=substr($data,72,64);
  if ($bi->{pos}>0) {
    my $vcum=securehash($bi->{tid}.$pbi->{tcum});
    if ($vcum ne $bi->{tcum}) {
      illegalblock($bi,$pbi,"Cumulative hash invalid, corrupted ledger: advisable to delete this ledger","Expected: $vcum","   Found: $bi->{tcum}","Previous: $pbi->{tcum}");
      if ($LEDGERERROR) { return }
    }
  }
  $bi->{num}=hexdec(substr($data,136,12));
  # print "BINUM: $bi->{num} PBINUM: ",ref($pbi)," $pbi->{num}\n";
  if ($bi->{num} != $pbi->{num}+1) {
    # we got a gap in the chain, maybe merged two files together
    my $ebnr=$pbi->{num}+1;
    illegalblock($bi,$pbi,"Illegal block count","Found block: $bi->{num}","Expected block: $ebnr");
    if ($LEDGERERROR) { return }
  }
  $bi->{version}=substr($data,148,4);
  if ($FCCVERSION lt $bi->{version}) {
    # let the man speak for Christ' sake
    print "\n\n>>>>> ! RUNNING BEHIND ! PLEASE UPGRADE VERSION ! <<<<<\n\nVersion found: $bi->{version}\nOur version: $FCCVERSION\nBlock number: $bi->{num}\nPosition: $bi->{pos}\n\n";
    exit 1
  }
  $bi->{type}=hexdec(substr($data,152,1));
  if (!$RTRANSTYPES->{$bi->{type}}) {
    # should never happen under running the right version
    illegalblock($bi,$pbi,"Unknown block type found","Block type: $bi->{type}");
    if ($LEDGERERROR) { return }
  }
  $bi->{pid}=substr($data,153,64);
  if ($pbi->{tid} ne $bi->{pid}) {
    # this can appear when the cumulative hash isn't checked before adding a block
    illegalblock($bi,$pbi,"Illegal block in chain, pointing to different previous block","Previous block TID: $pbi->{tid}","TID of previous block found: $bi->{pid}");
    if ($LEDGERERROR) { return }    
  }
  if ($bi->{type} ne $TRANSTYPES->{out}) {
    if ($md->{outtogo}) {
      # this error actually should never appear or transactions are put into the ledger by hand
      illegalblock($bi,$pbi,"Ident-block found where out-block expected","Block-type: $RTRANSTYPES->{$bi->{type}}");
      if ($LEDGERERROR) { return }
    }
    $md->{outamount}=0; $md->{outfee}=0; $bi->{time}=hexdec(substr($data,217,8));
    if ($bi->{type} eq $TRANSTYPES->{fee}) {
      $bi->{nout}=hexdec(substr($data,225,4));
    } else {
      $bi->{nout}=hexdec(substr($data,225,2));
    }
    if (!$bi->{nout}) {
      # huh?
      illegalblock($bi,$pbi,"Ident-block found without out-blocks attached","Block-type: $RTRANSTYPES->{$bi->{type}}");
      if ($LEDGERERROR) { return }
    }
    $md->{outtogo}=$bi->{nout};
  } 
  if ($bi->{type} eq $TRANSTYPES->{genesis}) {
    if ($bi->{tcum} ne $FCCMAGIC) {
      illegalblock($bi,$pbi,"This ledger is not the original FCC ledger!","Initstring: $bi->{tcum}");
      if ($LEDGERERROR) { return }
    }
    $md->{inamount}=-1
  } elsif ($bi->{type} eq $TRANSTYPES->{in}) {
    $bi->{nin}=hexdec(substr($data,227,2));
    $bi->{pubkey}=substr($data,229,64);
    $md->{pubkey}=$bi->{pubkey};
    $bi->{sign}=substr($data,293,128); # This is what makes Ed25519 rules, deterministic signing.
    $md->{sign}=$bi->{sign};
    $md->{inblocks}=[]; my $p=421;
    for (my $i=0;$i<$bi->{nin};$i++) {
      push @{$md->{inblocks}},substr($data,$p,64); $p+=64
    }
    if (!validatespend($fh,$bi,$md)) {
      illegalblock($bi,$pbi,"The spendable blocks does not validate the in-block",$bi->{error});
      if ($LEDGERERROR) { return }
    }
  } elsif ($bi->{type} eq $TRANSTYPES->{coinbase}) {
    $md->{pubkey}=$FCCSERVERKEY;
    my $cc=substr($data,227,8);
    $bi->{coincount}=hexdec($cc);
    $bi->{sign}=substr($data,235,128);
    $md->{sign}=$bi->{sign};
    $md->{signdata}=$cc;
    $md->{inamount}=-1
  } elsif ($bi->{type} eq $TRANSTYPES->{fee}) {
    $md->{pubkey}=$FCCSERVERKEY;
    my $cc=substr($data,229,20);
    $bi->{spare}=hexdec(substr($cc,0,8));
    $bi->{blockheight}=hexdec(substr($cc,8,12));
    $bi->{sign}=substr($data,249,128);
    $md->{sign}=$bi->{sign};
    $md->{signdata}=$cc;
    $md->{inamount}=-1
  } elsif ($bi->{type} eq $TRANSTYPES->{out}) {
    if (!$md->{outtogo}) {
      # the most potential hackable point: Creating an extra out-block to spend, we will check the balance too soon
      illegalblock($bi,$pbi,"Out-block found where new ident-block expected");
      if ($LEDGERERROR) { return }
    }
    $md->{outtogo}--;
    $bi->{wallet}=substr($data,217,68);
    if (!validwallet($bi->{wallet})) {
      my $blen=length($data);
      illegalblock($bi,$pbi,"Illegal wallet found in out-block","Wallet found: $bi->{wallet}","BLen=$blen");
      if ($LEDGERERROR) { return }
    }
    my $amount=substr($data,285,16);
    my $fee=substr($data,301,4);
    my $expire="";
    if (length($data)>=315) {
      $expire=substr($data,305,10)
    }
    $bi->{amount}=hexdec($amount);
    $bi->{fee}=hexdec($fee);
    if ($expire) { $bi->{expire}=hexdec($expire) }
    $md->{signdata}.=$bi->{wallet}.$amount.$fee.$expire;
    $md->{outamount}+=$bi->{amount};
    if ($bi->{fee}) {
      $md->{outfee}+=doggyfee($bi->{amount},$bi->{fee})
    }
    if (!$md->{outtogo}) {
      my $tsa=$md->{outamount}+$md->{outfee};
      if (($md->{inamount}>=0) && ($tsa != $md->{inamount})) {
        illegalblock($bi,$pbi,"The spended money does not match the money available","Amount to be spend: $md->{outamount}","Fee to be spend: $md->{outfee}","Change amount: $bi->{amount}","Total Spend Amount: $tsa","Amount of spendable blocks: $md->{inamount}");
        if ($LEDGERERROR) { return }
      }
      if ($md->{pubkey}) {
        if (!Crypt::Ed25519::verify($md->{signdata},hexoct($md->{pubkey}),hexoct($md->{sign}))) {
          illegalblock($bi,$pbi,"The Ed25519 signature of the supposed owner of this transaction does not match the public spending key");
          if ($LEDGERERROR) { return }
        }
      }
    }
    if ($bi->{amount} > 0) {
      dbadd($SDB,$bi->{tid},$bi->{pos});
      push @$OBL,$bi->{pos};
      addwallet($bi->{wallet},$bi->{pos});
      dbhash($bi->{tid}.$bi->{wallet}.$bi->{pos})
    }
  }
  #print "* BLOCK $bi->{num} = $bi->{error}\n"
}

sub processledger {
  my ($pos,$pbi) = @_;
  if (!$pos) { $pos=0 }
  if (!-e "ledger$FCCEXT") { return }
  my $fh=gfio::open("ledger$FCCEXT");
  if (!$fh->{size}) { $fh->close; return }
  my $size=$fh->{size}-4; my $bi = { next => 0 }; my $bnr=0;
  my $md = { outtogo => 0, signdata => "", sign => "", pubkey => "", outamount => 0, outfee => 0, inamount => 0, inblocks => [] };
  while ($pos<$size) {
    # print " ** PROCESS $pos **\n";
    $fh->seek($pos);
    $bi = { pos => $pos };
    if ($pos+4>$size) {
      $fh->close; my $fsz=$size-$pos;
      illegalblock($bi,$pbi,'Incomplete block',"Found Size: $fsz","Expected size: Unknown")
    }
    $bi->{prev}=hexdec($fh->read(4));
    if ($bi->{prev} != $pbi->{next}) {
      $fh->close;
      illegalblock($bi,$pbi,'Position previous block does not match',"Read position: $bi->{prev}","Expected position: $pbi->{next}")
    }
    if ($pos+8>$size) {
      $fh->close; my $fsz=$size-$pos;
      illegalblock($bi,$pbi,'Incomplete block',"Found Size: $fsz","Expected size: Unknown")
    }
    $bi->{next}=hexdec($fh->read(4));
    if ($pos+$bi->{next}>$size) {
      $fh->close; my $fsz=$size-$pos;
      illegalblock($bi,$pbi,'Incomplete block',"Found Size: $fsz","Expected size: $bi->{next}")
    }
    my $blockdata=$fh->read($bi->{next}-8);
    my $dlt=substr($blockdata,-1,1);
    if ($dlt ne 'z') {
      $fh->close; my $fsz=$size-$pos;
      illegalblock($bi,$pbi,'Illegal block terminator (Incomplete or corrupted block)',"Found Size: $fsz","Delimiter found: $dlt (must be 'z')")
    }
    # delimiter is not signed!
    $blockdata=dechex($bi->{prev},4).dechex($bi->{next},4).substr($blockdata,0,-1);
    processblock($fh,$bi,$pbi,$md,$blockdata);
    $pbi=$bi; $pos+=$bi->{next};
  }
  $fh->seek($pos);
  my $pp=hexdec($fh->read(4));
  if ($pp != $bi->{next}) {
    $fh->close;
    illegalblock($bi,$pbi,"Ledger is not finalized by the pointer to the previous block")
  }
  if ($md->{outtogo}) {
    $fh->close;
    illegalblock($bi,$pbi,"Ledger has missing out blocks at the end")
  }
  $fh->close
}

sub readblock {
  my ($pos) = @_;
  my $fh=gfio::open("ledger$FCCEXT");
  $fh->seek($pos); 
  my $bi = { pos => $pos };
  my $prev=$fh->read(4);
  my $next=$fh->read(4);
  $bi->{prev}=hexdec($prev);
  $bi->{next}=hexdec($next);
  my $data=$prev.$next.$fh->read($bi->{next}-9);
  $fh->close;
  $bi->{tid}=substr($data,8,64);
  $bi->{tcum}=substr($data,72,64);
  $bi->{num}=hexdec(substr($data,136,12));
  $bi->{version}=substr($data,148,4);
  $bi->{type}=hexdec(substr($data,152,1));
  $bi->{pid}=substr($data,153,64);
  if ($bi->{type} ne $TRANSTYPES->{out}) {
    $bi->{fcctime}=hexdec(substr($data,217,8));
    if ($bi->{type} eq $TRANSTYPES->{fee}) {
      $bi->{nout}=hexdec(substr($data,225,4))
    } else {
      $bi->{nout}=hexdec(substr($data,225,2))
    }
  }
  if ($bi->{type} eq $TRANSTYPES->{in}) {
    $bi->{nin}=hexdec(substr($data,227,2));
    $bi->{pubkey}=substr($data,229,64);
    $bi->{sign}=substr($data,293,128);
    $bi->{inblocks}=[]; my $p=421;
    for (my $i=0;$i<$bi->{nin};$i++) {
      push @{$bi->{inblocks}},substr($data,$p,64); $p+=64
    }
  } elsif ($bi->{type} eq $TRANSTYPES->{coinbase}) {
    $bi->{coincount}=hexdec(substr($data,227,8));
    $bi->{sign}=substr($data,235,128);
  } elsif ($bi->{type} eq $TRANSTYPES->{fee}) {
    $bi->{spare}=hexdec(substr($data,229,8));
    $bi->{height}=substr($data,237,12);
    $bi->{sign}=substr($data,249,128);
  }
  if ($bi->{type} eq $TRANSTYPES->{out}) {
    $bi->{wallet}=substr($data,217,68);
    $bi->{amount}=hexdec(substr($data,285,16));
    $bi->{fee}=hexdec(substr($data,301,4));
    $bi->{fccamount}=fccstring($bi->{amount}/100000000);
    $bi->{fccfee}=fccstring($bi->{amount}*$bi->{fee}/1000000000000);
    if (length($data)>=315) {
      $bi->{expire}=hexdec(substr($data,305,10))
    }
  }
  return $bi  
}

sub readlastblock {
  if (-e "ledger$FCCEXT") {
    my $fh=gfio::open("ledger$FCCEXT");  
    my $sz=$fh->filesize();
    if ($sz>4) {
      $fh->seek($sz-4);
      my $pp=hexdec($fh->read(4));
      $fh->close;
      return readblock($sz-4-$pp)
    }
  }
  return { prev => 0, next => 0, pos => 0, num => -1, tcum => 'init' }
}

sub lastledgerprev {
  my $fh=gfio::open("ledger$FCCEXT");  
  my $sz=$fh->filesize();
  $fh->seek($sz-4);
  my $pp=hexdec($fh->read(4));
  $fh->close;
  return $pp
}

sub saveledgerdata {
  if (!-e "ledger$FCCEXT") { gfio::create("ledger$FCCEXT",'') }
  my $fh=gfio::open("ledger$FCCEXT",'rw');
  my $md = { outtogo => 0, signdata => "", sign => "", pubkey => "", outamount => 0, outfee => 0, inamount => 0 };
  my $iblock=$LEDGERSTACK->[0];
#  print "Iblock: $iblock\n";
  if (!$iblock) { $fh->close; return 1 }
  my $type=hexdec(substr($iblock,152,1));
  my $write="";
  if ($type eq $TRANSTYPES->{genesis}) {
    if ($#{$LEDGERSTACK}<1) { $fh->close; return 1 }
    #my $bsz=hexdec(substr($LEDGERSTACK->[0],4,4));
    my $last = { prev => 0, pos => 0, next => 0, num => -1, tid => '0'x64 };
    my $bi = { prev => 0, pos => 0, num => 0 };
    my $numblocks=2; my $pos=0;
    if ($COIN eq 'PTTP') {
      $numblocks=63
    }
    while ($numblocks>0) {
      my $block=shift @$LEDGERSTACK;
      $bi->{next}=length($block);
      $bi->{pos}=$pos; $pos+=$bi->{next};
      my $next=hexdec(substr($block,4,4));
      if ($bi->{next} != $next) {
        print " * Invalid Ledger block: length of block dismatch\n";
        $fh->close; return 0
      }
      $REPORTONLY=1;
      processblock($fh,$bi,$last,$md,substr($block,0,$next-1));
      $REPORTONLY=0;
      if ($LEDGERERROR) {
        print " * Invalid Ledger block: $LEDGERERROR\n";
        $LEDGERERROR="";
        $fh->close; return 0
      }
      $write.=$block;
      if ($numblocks<2) {
        $write.=dechex($bi->{next},4);
      }
      $last={ %$bi }; $bi->{prev}=$last->{next};
      $numblocks--
    }
  } elsif (($type eq $TRANSTYPES->{in}) || ($type eq $TRANSTYPES->{coinbase}) || ($type eq $TRANSTYPES->{fee})) {
    my $nout;
    if ($type eq $TRANSTYPES->{fee}) {
      $nout=hexdec(substr($iblock,225,4))
    } else {
      $nout=hexdec(substr($iblock,225,2));
    }
    # print "OUTBLOCKS: $nout\n";
    if ($nout > $#{$LEDGERSTACK}) {
      # not a complete transaction yet
      $fh->close; return 1
    }
    my $last=readlastblock(); my $numblocks=$nout+1;
    while ($numblocks>0) {
      my $block=shift @$LEDGERSTACK;
      # print "Block: $block\n";
      my $bi = { 
        pos => $last->{pos}+$last->{next},
        prev => hexdec(substr($block,0,4)),
        next => hexdec(substr($block,4,4)) 
      };
      if ($last->{next} != $bi->{prev}) {
        print " * Invalid Ledger block: Position previous block does not match. Read position: $bi->{prev}. Expected position: $last->{next}\n";
        $fh->close; return 0
      }
      $REPORTONLY=1;
      processblock($fh,$bi,$last,$md,substr($block,0,$bi->{next}-1));
      $REPORTONLY=0;
      if ($LEDGERERROR) {
        print " * Invalid Ledger block: $LEDGERERROR\n";
        $LEDGERERROR="";
        $fh->close; return 0
      }
      $write.=substr($block,4).dechex($bi->{next},4);
      $last={ %$bi }; $numblocks--
    }
  }
  if ($write ne "") {
    # print "APPEND DATA: $write\n";
    $fh->appenddata($write)
  }
  $fh->close; delcache; return 1
}

sub ledgerdata {
  # data can contain part of a block!
  my ($data,$init) = @_;
  if ($init && (-e "ledger$FCCEXT")) {
    $LEDGERBUFFER=dechex(lastledgerprev(),4)
  }
  $LEDGERBUFFER.=$data;
  while (length($LEDGERBUFFER)>=217) {
    my $next=hexdec(substr($LEDGERBUFFER,4,4));
    if (length($LEDGERBUFFER)<$next) {
      # not a complete block yet
      return 1
    }
    # process a block
    if (substr($LEDGERBUFFER,$next-1,1) ne 'z') {
      print " * Invalid Ledger block: Invalid delimiter found\n";
      return 0
    }
    my $block=substr($LEDGERBUFFER,0,$next);
    $LEDGERBUFFER=substr($LEDGERBUFFER,$next);
    my $type=hexdec(substr($block,152,1));
    #print "GOT BLOCK $type\n";
    if ($type ne $TRANSTYPES->{out}) {
      if (!saveledgerdata()) { return 0 }
    }
    my $len=length($block);
    #print "PUSH: $block ($len)\n";
    push @$LEDGERSTACK,$block
  }
  if (!saveledgerdata()) { return 0 }
  return 1
}

########### FEE #############################

sub calculatefee {
 my ($spos,$len) = @_; 
 my $bpos=$spos;
 my $epos=$spos+$len;
 my $fh=gfio::open("ledger$FCCEXT");
 if ($fh->filesize()<$epos) {
   $fh->close(); return 0
 }
 my $totfee=0;
 # Calculate total Fee till the End of Pos+Length
 while($spos+305 <= $epos){
   $fh->seek($spos+4);
   my $next=hexdec($fh->read(4)); # Next Block Pos
   $fh->seek($spos+152);
   if ($RTRANSTYPES->{$fh->read(1)} eq 'out') { # Found Outblock
     $fh->seek($spos+285);
     my $amount=hexdec($fh->read(16));
     my $fee=hexdec($fh->read(4));
     if ($fee) { $totfee+=doggyfee($amount,$fee) }
   }
   $spos+=$next;
 }
 $fh->close(); return $totfee
}

###############################################################

sub inblocklist {
  my ($blocks) = @_;
  my $fh=gfio::open("ledger$FCCEXT");
  my $ibl=[];
  foreach my $b (@$blocks) {
    $fh->seek($b+8); push @$ibl,$fh->read(64)
  }
  $fh->close;
  return $ibl
}

sub collectspendblocks {
  # blocks are gathered from the beginning of the ledger
  my ($wid,$amount,$spended) = @_;
  my %sp=(); if ($spended) { foreach my $s (@$spended) { $sp{$s}=1 } }
  my $coll=0; my $blocks=[];
  my $fh=gfio::open("ledger$FCCEXT");
  my $wpl=walletposlist($wid);
  my $fcctime = time + $FCCTIME;
  foreach my $obp (@$wpl) {
    $fh->seek($obp+4);
    my $len=hexdec($fh->read(4));
    if ($len>=315) {
      # check if spend-lock is expired
      $fh->seek($obp+305);
      my $expire=hexdec($fh->read(10));
      if ($expire>$fcctime) { next }
    }
    if ($spended) {
      $fh->seek($obp+8);
      my $tid=$fh->read(64);
      if ($sp{$tid}) { next }
    }
    $fh->seek($obp+217);
    my $rw=$fh->read(68);
    if ($rw eq $wid) {
      push @$blocks,$obp;
      $coll+=hexdec($fh->read(16));
      if ($coll>=$amount) {
        $fh->close;
        return ($blocks,$coll-$amount)
      }
    }
  }
  $fh->close;
  return ([],0)
}

sub getinblock {
  my ($pos) = @_;
  my $fh=gfio::open("ledger$FCCEXT");
  if (!$pos) { return readblock(0) }
  $fh->seek($pos-1);
  my $dmt=$fh->read(1);
  if ($dmt ne 'z') {
    error "GetInBlock: Illegal position given - $pos"
  }
  do {
    $fh->seek($pos); my $prev=hexdec($fh->read(4));
    $fh->seek($pos+152); my $type=hexdec($fh->read(1));
    if ($type ne $TRANSTYPES->{out}) {
      return readblock($pos)
    }
    $pos-=$prev
  } until ($pos<0)
}

sub sealinfo {
  my ($pos) = @_;
  my $info = { inblock => getinblock($pos), outblocks => [] };
  $info->{size}=$info->{inblock}{next}; $pos=$info->{inblock}{pos}+$info->{size};
  $info->{amount}=0; $info->{change}=0; $info->{fee}=0;
  my $block;
  for (my $b=1;$b<=$info->{inblock}{nout};$b++) {
    $block=readblock($pos);
    if ($block->{type} eq $TRANSTYPES->{out}) {
      push @{$info->{outblocks}},$block;
      if (($b == $info->{inblock}{nout}) && !$block->{fee} && ($info->{inblock}{type} eq $TRANSTYPES->{in})) {
        $info->{change}=$block->{amount}
      } else {
        $info->{amount}+=$block->{amount};
        $info->{fee}+=$block->{amount}*$block->{fee}/10000;
      }
      $info->{size}+=$block->{next}; $pos+=$block->{next}
    }
  }
  $info->{change}=fccstring($info->{change}/100000000);
  $info->{amount}=fccstring($info->{amount}/100000000);
  $info->{fee}=fccstring($info->{fee}/100000000);
  return $info
}

sub checkgenesis {
  my ($pubkey) = @_;
  my $wallet=createwalletaddress($pubkey);
  my $list=collectspendblocks($wallet,1);
  my $pos=$list->[0];
  my $iblock=getinblock($pos);
  return ($iblock->{type} eq $TRANSTYPES->{genesis})
}

sub saldo {
  my ($wid) = @_;
  my $coll=0;
  my $fh=gfio::open("ledger$FCCEXT");
  my $wpl=walletposlist($wid);
  foreach my $obp (@$wpl) {
    $fh->seek($obp+217);
    my $rw=$fh->read(68);
    if ($rw eq $wid) {
      $coll+=hexdec($fh->read(16));
    }
  }
  $fh->close;
  return $coll
}

#################################################################################

sub deref {
  my ($dat) = @_;
  if (!defined $dat) { return undef }
  if (ref($dat) eq 'ARRAY') {
    my $a=[];
    foreach my $d (@$dat) {
      push @$a,deref($d)
    }
    return $a
  } elsif (!ref($dat)) {
    return $dat
  } else {
    my $h={};
    foreach my $k (keys %$dat) {
      $h->{$k}=deref($dat->{$k})
    }
    return $h
  }
}

#################################################################################

# EOF FCC::fcc (C) 2018 Chaosje, Domero
