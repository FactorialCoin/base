#!/usr/bin/perl

package FCC::Explorer;
# FCC / PTTP Explorer Server
# (C) 2019 Chaosje, Domero
# (C) 2020 OnEhIppY, Domero

use gserv 4.3.2;
use gclient 8.1.1;
use gpost 2.1.2;
use glib;
use Time::HiRes qw(gettimeofday);
use FCC::global 2.2.1;
use FCC::fccbase 2.2.1;
use FCC::fcc 1.2.6;
use FCC::leaf 2.1.1;
use FCC::wallet 2.1.4;

use gerr qw(error trace);
use JSON;

$SIG{'INT'}=\&intquit;
$SIG{'TERM'}=\&termquit;
$SIG{__DIE__}=\&fatal;
$SIG{__WARN__}=\&fatal;

my $EVALMODE=0;
my $SOURCE="";
my $SERV;
my $LEAF;
my $CTIME=0;
my $INBLOCK;
my $LEDGERLEN=0;
my $LEDGERWANTED=0;
my $LEDGERWAIT=0;
my $LEDGERDATA="";
my $HTML;
my $TRANS;
my $BLOCKPOS;
my $INFO;
my $CSS;
my $JS;
my $DBNUM = [];
my $DBOUT = [];
my $DBPOS = [];
my $DBNCB = [];
my $DBFEE = [];
my $DBWAL = [];
my $PLOTVOL = [];
my $PLOTACT = [];
my $LDGCOUNT = -1;
my $SHOWCB = 1;
my $SHOWFEE = 0;
my $NCBPOS;
my $FEEPOS;
my $SPENT;
my $VOLUME = 0;
my $ACTIVITY = 0;
my $ACTMAX = 0;

my $LOCALIP = gserv::localip();
my $ONSERVER = ($LOCALIP eq '149.210.194.88');
my $SSLCERT = 'factorialcoin.nl';

my $PTTP = (-e 'ledger.pttp');
if ($PTTP) { setcoin('PTTP') }

my $HTMLBASE=gfio::content('html');

if ($ONSERVER) {
  $CSS=gfio::content('css');
  $JS=gfio::content('js');
  $HTMLBASE =~ s/\<style\>/<style>\r\n$CSS\r\n/;
  $HTMLBASE =~ s/\<script\>/<script>\r\n$JS\r\n/;
}

my $BOX = <<EOT;
    <div id="trans" class="box">  
      <div class="boxtit">!title!!prev!!next!</div>
      <table class="boxtab">
!boxcont!
      </table>
    </div>
EOT
my $FCCICON="<img src=\"image/".lc($COIN)."ico.png\" style=\"vertical-align: top\" height=\"18\" />";

my $STARTTIME = 0;

$| = 1;

sub init {
  print " * $COIN Blockchain Explorer\n\nCalculating Databases .. ";
  process_ledger();
  print " done.\n\n";

  print "Ledger start time = ".fcctimestring($STARTTIME)."\n";
  print "Ledger age = ".$#{$PLOTVOL}." hours\n";
  print "Market Volume = $VOLUME\n";

  print "\n";
  print "Starting Server .. ";
  start();
}

sub start {
  $SERV=gserv::init(\&handleclient,\&loopclient,$ONSERVER,\&serverhandle);
  my $port=5152; my $ssl="";
  if ($PTTP) { $port=9613 }
  if ($::EXPLORERPORT) { $port=$::EXPLORERPORT }
  if (!$ONSERVER) {
    $SERV->{server}{host}='127.0.0.1';
  } else {
    $SERV->{server}{host}='factorialcoin.nl';
    $SERV->{ssldomain}=$SSLCERT; $ssl="s"
  }
  $SERV->{server}{port}=$port;
  $SOURCE="http$ssl://".$SERV->{server}{host}.":".$port."/";
  $SERV->{allowedip}=['*'];
  $SERV->{buffersize} = 1024 *128;
  $SERV->{idletimeout}=10;
  $SERV->{clienttimeout}=60;
  #$SERV->{verbose}=1;
  print "Starting $SOURCE\n"; $SERV->start(1,\&serverloop);
  if ($SERV->{error}) {
    print "SERV::ERROR $SERV->{error}\n\n"
  }
}

sub serverhandle {
  my ($command) = @_;
  if ($command eq 'connected') {
    print "OK (Port = $SERV->{server}{port})\n\n"
  }
}

sub handleclient {
  my ($client,$command,$data) = @_;  
  #print "Handle Client $client->{ip} $command $data\n";
  if ($command eq 'ready') {
    makesite($client)
  }
}

sub loopclient {}

sub serverloop {
  my $tm=gettimeofday();
  if (!ref($LEAF)){
    print "Starting $COIN Leaf .. "; 
    connectleaf();
  }
  FCC::leaf::leafloop();
  if ($tm-$CTIME>60) {
    if ($LEDGERWANTED) {
      if (!$LEDGERWAIT) {
        print "\r\t Wanted $LEDGERWANTED\t Got $LEDGERLEN        \n";
        my $togo=$LEDGERWANTED-$LEDGERLEN;
        my $ll=length($LEDGERDATA); $togo-=$ll;
        my $read=$togo; if ($read>32768) { $read=32768 }
        my $final=($LEDGERLEN + $ll + $read == $LEDGERWANTED);
        $LEAF->getledgerdata($LEDGERLEN+$ll,$read,$final);
        $LEDGERWAIT=1
      }
    } elsif (!$LEDGERWAIT) {
      print "\n Call ledgerinfo\n";
      $LEAF->ledgerinfo();
      $LEDGERWAIT=1;
    } else {
      if ($LOOPWAIT != int($tm)) {
        $LOOPWAIT = int($tm);
        print "\r\t Time ".int($tm-$CTIME)."\t Wanted $LEDGERWANTED\t Got $LEDGERLEN        \r";
        if ($tm-$CTIME > 60*60) { print "\n * Restarting $COIN Leaf .. "; connectleaf(); }
      }
    }
  }
}

sub connectleaf {
  if ($LEAF) { $LEAF->quit() }
  my $nodes=gclient::website('https://'.$FCCSERVERHOST.':'.$FCCSERVERPORT.'/?nodelist');
  my @nodelist=split(/ /,$nodes->content());
  foreach my $node (@nodelist) {
    my ($host,$port) = split(/\:/,$node);
    $LEAF=FCC::leaf::startleaf($host,$port,\&handleleaf);
    if (!$LEAF->{error}) {
      print " OK [ $LEAF->{host}:$LEAF->{port} ]\n\n";
      my $tm=gettimeofday();
      $CTIME=$tm-61; serverloop();
      return
    }
    $LEAF->{verbose}=1;
    $LEAF->{debug}=1;
  }
  print " Cannot connect to the $COIN core.\n\n"; exit
}

sub handleleaf {
  my ($leaf,$command,$data) = @_;
  print "HandleLeaf [$command]\n";# [".join(',',@{[keys %$data]})."][".join(',',@{[values %$data]})."]\n";
  if ($command eq 'disconnect') {
    print "\nTrying to reconnect to the $COIN core .. \n";
    $LEDGERWANTED=0; $LEDGERWAIT=0; $CTIME=gettimeofday();
    connectleaf()
  } elsif ($command eq 'ledgerinfo') {
    print "\nLedgerInfo Callback : $data->{size}\n";
    my @tm=localtime(); my $hr=$tm[2]; my $min=$tm[1];
    if ($hr<10) { $hr="0$hr" } if ($min<10) { $min="0$min" }
    if ($data->{size}>$LEDGERLEN) {
      $LEDGERWANTED=$data->{size}; my $togo=$LEDGERWANTED-$LEDGERLEN;
      print "[$hr:$min] Gathering $togo bytes of ledgerdata\n"
    } else {
      print "[$hr:$min] Ledger is up to date\n";
      $CTIME=gettimeofday()
    }
    $LEDGERWAIT=0
  } elsif ($command eq 'ledgerdata') {
    $LEDGERDATA.=b64z($data->{data});
    if ($data->{final}) {
      gfio::append("ledger$FCCEXT",$LEDGERDATA);
      $LEDGERDATA="";
      my $pos=$LEDGERLEN-4;
      $LEDGERLEN=$LEDGERWANTED;
      $LEDGERWANTED=0;
      calcledger($pos);
      $CTIME=gettimeofday()
    }
    $LEDGERWAIT=0
  } elsif ($command eq 'response') {
    $leaf->ledgerinfo();
  }
}

sub blockpos {
  $BLOCKPOS=0;
  if ($TRANS <= $#{$DBNUM}) {
    $BLOCKPOS=$DBNUM->[$TRANS]
  }
  if ($SHOWFEE) {
    $BLOCKPOS=searchfee();
    $TRANS=$DBLIST->{$BLOCKPOS}
  } elsif (!$SHOWCB) {
    $BLOCKPOS=searchncb();
    $TRANS=$DBLIST->{$BLOCKPOS}
  }
  return $BLOCKPOS
}

sub searchncb {
  my $num=1+$#{$DBNCB};
  my $bn=int (log($num)/log(2));
  my $bp=2**$bn; my $fnd=0; my $jump=$bp;
  do {
    $jump>>=1;
    my $sp=$DBNCB->[$bp-1];
    if (!defined $sp || ($sp>$BLOCKPOS)) {
      $bp-=$jump
    } elsif ($sp==$BLOCKPOS) {
      $fnd=1
    } else {
      $bp+=$jump
    }
    $bn--
  } until ($fnd || ($bn<0));
  if ($fnd) {
    $NCBPOS=$bp-1;
  } else {
    $NCBPOS=$#{$DBNCB}
  }
  return $DBNCB->[$NCBPOS]
}

sub searchfee {
  my $num=1+$#{$DBFEE};
  my $bn=int (log($num)/log(2));
  my $bp=2**$bn; my $fnd=0; my $jump=$bp;
  do {
    $jump>>=1;
    my $sp=$DBFEE->[$bp-1];
    if (!defined $sp || ($sp>$BLOCKPOS)) {
      $bp-=$jump
    } elsif ($sp==$BLOCKPOS) {
      $fnd=1
    } else {
      $bp+=$jump
    }
    $bn--
  } until ($fnd || ($bn<0));
  if ($fnd) {
    $FEEPOS=$bp-1;
  } else {
    $FEEPOS=$#{$DBFEE}
  }
  return $DBFEE->[$FEEPOS]
}

sub setprev {
  my ($box,$num) = @_;
  my $begin="";
  if (defined $num) {
    if (!$SHOWFEE || ($FEEPOS>0)) {
      my $first=0;
      if ($SHOWFEE) { $first=$DBLIST->{$DBFEE->[0]} }
      $begin="<img class=\"tobegin muis\" src=\"/image/tobegin.png\" height=\"22\" onclick=\"gotrans($first)\" />";
    }
  }
  if (!defined $num) {
    $box =~ s/\!prev\!/$begin/;
  } else {
    $box =~ s/\!prev\!/$begin\<img class=\"prev muis\" src=\"\/image\/prev.png\" height=\"32\" onclick=\"gotrans($num)\" \/\>/
  }
  return $box
}

sub setnext {
  my ($box,$num,$last) = @_;
  my $end="";
  if (defined $num || $last) {
    if (!$SHOWFEE || ($FEEPOS<$#{$DBFEE})) {
      my $last=$LDGCOUNT;
      if ($SHOWFEE) { $last=$DBLIST->{$DBFEE->[$#{$DBFEE}]} }
      elsif ($SHOWCB || ($NCBPOS<$#{$DBNCB})) {
        if (!$SHOWCB) { $last=$DBLIST->{$DBNCB->[$#{$DBNCB}]} }
        $end="<img class=\"toend muis\" src=\"/image/toend.png\" height=\"22\" onclick=\"gotrans($last)\" />";
      }
    }
  }
  if (!defined $num) {
    $box =~ s/\!next\!/$end/;
  } else {
    $box =~ s/\!next\!/$end\<img class=\"next muis\" src=\"\/image\/next.png\" height=\"32\" onclick=\"gotrans($num)\" \/\>/
  }
  return $box
}

sub box { 
  my ($title) = @_;
  my $box=$BOX;
  if (!$title) {
    my $show=1; my $next; my $prev;
    if ($TRANS < $LDGCOUNT) {
      $next=$TRANS+1;
      if ($SHOWFEE) {
        $show=($FEEPOS < $#{$DBFEE});
        if ($show) {
          $next=$DBLIST->{$DBFEE->[$FEEPOS+1]}
        }
      } elsif (!$SHOWCB) {
        $show=($NCBPOS < $#{$DBNCB});
        if ($show) {
          $next=$DBLIST->{$DBNCB->[$NCBPOS+1]}
        }
      }
    }
    if ($show) {
      $box=setnext($box,$next,1)
    } else {
      $box=setnext($box,undef,1)
    }
    if ($TRANS>0) {
      $prev=$TRANS-1;
      if ($SHOWFEE) {
        if ($FEEPOS == 0) {
          $prev=undef
        } else {
          $prev=$DBLIST->{$DBFEE->[$FEEPOS-1]}
        }
      } elsif (!$SHOWCB) {
        $prev=$DBLIST->{$DBNCB->[$NCBPOS-1]};
      }
      $box=setprev($box,$prev)
    } else {
      $box=setprev($box)
    }
    $title="Transaction Seal"
  } else {
    $box=setnext($box);
    $box=setprev($box)
  }
  $box =~ s/\!title\!/$title/;
  return $box
}

sub boxrow {
  my ($tit,$val,$style) = @_;
  if (!$style) { $style="" }
  else { $style=" style=\"$style\"" }
  return "<tr class=\"tt\"$style><td class=\"tr\">$tit</td><td>$val</td></tr>"
}

sub boxout {
  my ($num) = @_;
  if (!$num) { $num=0 }
  my @rows=();
  push @rows,boxrow('TID',$INFO->{outblocks}[$num]{tid});
  push @rows,boxrow('Amount',$FCCICON." ".$INFO->{outblocks}[$num]{fccamount});
  push @rows,boxrow('Wallet',$INFO->{outblocks}[$num]{wallet});
  return @rows
}

sub box_genesis {
  my $box=box();
  my @rows=();
  push @rows,boxrow('Number #',$TRANS);
  push @rows,boxrow('Type',"Genesis");
  push @rows,boxrow('Time',fcctimestring($INBLOCK->{fcctime}));
  push @rows,boxrow('TID',$INBLOCK->{tid});
  push @rows,boxrow('Cumulative ID',$INBLOCK->{tcum});
  push @rows,boxrow('Position',$BLOCKPOS);
  push @rows,boxrow('Size',$INFO->{size});
  push @rows,boxrow('Amount',"$FCCICON $INFO->{amount}");
  push @rows,boxrow('Outblocks',$INBLOCK->{nout});
  my $cont=join("\n",@rows);
  $box =~ s/\!boxcont\!/$cont/;
  return $box
}

sub box_ico {
  return box_out(undef,1);
}

sub box_in {
  my $box=box();
  my @rows=();
  push @rows,boxrow('Number #',$TRANS);
  push @rows,boxrow('Type',"Standard Transaction");
  push @rows,boxrow('Time',fcctimestring($INBLOCK->{fcctime}));
  push @rows,boxrow('TID',$INBLOCK->{tid});
  push @rows,boxrow('Cumulative ID',$INBLOCK->{tcum});
  push @rows,boxrow('Position',$BLOCKPOS);
  push @rows,boxrow('Size',$INFO->{size});
  push @rows,boxrow('Amount',"$FCCICON $INFO->{amount}");
  push @rows,boxrow('Fee',"$FCCICON $INFO->{fee}");
  push @rows,boxrow('Outblocks',$INBLOCK->{nout});
  push @rows,boxrow('Public Key',$INBLOCK->{pubkey});
  push @rows,boxrow('Signature',$INBLOCK->{sign},"height: 44px;");
  my @out=(); my $spent=0;
  foreach my $ib (@{$INBLOCK->{inblocks}}) {
    $spent++;
    my $pos=dbget($DBOUT,$ib);
    my $inblock=getinblock($pos);
    my $tnr=$DBLIST->{$inblock->{pos}};
    push @out,"<div class=\"muis\" onclick=\"spenttrans($tnr,$spent)\" id=\"spent$spent\" style=\"color: #ddffdd\">$ib</div>"
  }
  push @rows,boxrow('Spent Blocks',join("",@out));
  my $cont=join("\n",@rows);
  $box =~ s/\!boxcont\!/$cont/;
  return $box
}

sub box_out {
  my ($nodes,$ico) = @_;
  my $t="Recipients";
  if ($ico) { $t="Initial Coin Offering" }
  if ($nodes) { $t="Nodes $t" }
  my $box=box($t);
  my @rows=(); my $cnt=0; my $out="";
  foreach my $block (@{$INFO->{outblocks}}) {
    my $txt="Amount"; $cnt++;
    my $fee=""; my $hr="";
    my $col; if ($SPENT && ($block->{tid} eq $SPENT)) { $col=" style=\"color: #ffbbbb;\""}
    if (($cnt == $INBLOCK->{nout}) && ($block->{fee} == 0) && !$nodes) {
      $txt="Change"
    } else {
      if (!$nodes && !$ico) {
        $fee=<<EOT;
          <tr class="tt"><td class="tr">Fee</td><td$col>$FCCICON $block->{fccfee}</td></tr>
EOT
      }
      if ($cnt < $INBLOCK->{nout}) {
        $hr=<<EOT;
          <tr><td colspan="2"><hr width="100%"></td></tr>
EOT
      }
    }
    $out.=<<EOT;
          <tr class="tt"><td class="tr">TID</td><td$col>$block->{tid}</td></tr>
          <tr class="tt"><td class="tr">$txt</td><td$col>$FCCICON $block->{fccamount}</td></tr>$fee
          <tr class="tt"><td class="tr">Wallet</td><td$col>$block->{wallet}</td></tr>$hr
EOT
  }
  $box =~ s/\!boxcont\!/$out/;
  return $box
}

sub box_coinbase {
  my $box=box();
  my @rows=();
  push @rows,boxrow('Number #',$TRANS);
  push @rows,boxrow('Type',"Coinbase");
  push @rows,boxrow('Time',fcctimestring($INBLOCK->{fcctime}));
  push @rows,boxrow('TID',$INBLOCK->{tid});
  push @rows,boxrow('Cumulative ID',$INBLOCK->{tcum});
  push @rows,boxrow('Position',$BLOCKPOS);
  push @rows,boxrow('Size',$INFO->{size});
  push @rows,boxrow('Amount',"$FCCICON $INFO->{amount}");  
  my $cont=join("\n",@rows);
  $box =~ s/\!boxcont\!/$cont/;
  return $box
}

sub box_miner {
  my $box=box("Miner Reward");
  my @rows=boxout();
  my $cont=join("\n",@rows);
  $box =~ s/\!boxcont\!/$cont/;
  return $box
}

sub box_node {
  my $box=box("Node Reward");
  my @rows=boxout(1);
  my $cont=join("\n",@rows);
  $box =~ s/\!boxcont\!/$cont/;
  return $box
}

sub box_fee {
  my $box=box();
  my @rows=();
  push @rows,boxrow('Number #',$TRANS);
  push @rows,boxrow('Type',"Node Fee Payout");
  push @rows,boxrow('Time',fcctimestring($INBLOCK->{fcctime}));
  push @rows,boxrow('TID',$INBLOCK->{tid});
  push @rows,boxrow('Cumulative ID',$INBLOCK->{tcum});
  push @rows,boxrow('Position',$BLOCKPOS);
  push @rows,boxrow('Size',$INFO->{size});
  push @rows,boxrow('Amount',"$FCCICON $INFO->{amount}");  
  push @rows,boxrow('Outblocks',$INBLOCK->{nout});
  my $cont=join("\n",@rows);
  $box =~ s/\!boxcont\!/$cont/;
  return $box
}

sub controls {
  my $img="vink_ok.png"; if (!$SHOWCB) { $img="vink_no.png" }
  my $fimg="vink_ok.png"; if (!$SHOWFEE) { $fimg="vink_no.png" }
  my $html=<<EOT;
    <div id="controls" class="box">
      <div class="boxtit">Controls</div>
      <div class="boxcont">
        <div id="gototit">Go to</div><input id="goto" onkeyup="checkdigit(event,'goto')" onkeydown="checkenter(event)" onchange="gototrans()" />
        <div id="volume">Volume: $VOLUME</div>
        <div id="searchtit">Search</div><input id="search" onkeydown="checkenter(event)" onchange="search()" />
        <img id="switchcb" src="image/$img" onclick="switchcb()" class="muis" />
        <div id="switchdbtit">Show Coinbase</div>
        <img id="switchfee" src="image/$fimg" onclick="switchfee()" class="muis" />
        <div id="switchfeetit">Only Fee Payouts</div>
      </div>
    </div>
    <input type="hidden" id="showcb" value="$SHOWCB" />
    <input type="hidden" id="showfee" value="$SHOWFEE" />
    <input type="hidden" id="transaction" value="$TRANS" />
    <input type="hidden" id="spent" value="" />
EOT
  return $html
}

sub html {
  $HTML=$HTMLBASE;
  my $controls=controls();
  $HTML =~ s/\!controls\!/$controls/;
  my $left;
  if ($INBLOCK->{type} eq $TRANSTYPES->{genesis}) {
    $left=box_genesis().box_ico();
  } elsif ($INBLOCK->{type} eq $TRANSTYPES->{in}) {
    $left=box_in().box_out();
  } elsif ($INBLOCK->{type} eq $TRANSTYPES->{coinbase}) {
    $left=box_coinbase().box_miner().box_node();
  } elsif ($INBLOCK->{type} eq $TRANSTYPES->{fee}) {
    $left=box_fee().box_out(1)
  }
  $HTML =~ s/\!boxes\!/$left/;
  if (!$ONSERVER) {
    $CSS=gfio::content('css');
    $JS=gfio::content('js');
    $HTML =~ s/\<style\>/<style>\r\n$CSS\r\n/;
    $HTML =~ s/\<script\>/<script>\r\n$JS\r\n/;
    my $rs=<<EOT;
<div id="restart" class="muis" onclick="restart()">Restart</div>
<iframe id="rsf"></iframe>
EOT
    $HTML =~ s/\<\/body\>/<\/body>$rs/;
  }
}

########################################################################################

sub json_genesis {
  my ($J)=@_;
  $J->{trans}{ibType} = "genesis";
  $J->{trans}{IbType} = "Genesis";
  $J->{trans}{change} = $INFO->{change};
  json_out($J,undef,1);
}

sub json_in {
  my ($J)=@_;
  $J->{trans}{ibType} = "in";
  $J->{trans}{IbType} = "Standard Transaction";
  $J->{trans}{fee} = $INFO->{fee};
  $J->{trans}{change} = $INFO->{change};
  $J->{trans}{pubkey} = $INBLOCK->{pubkey};
  $J->{trans}{sign} = $INBLOCK->{sign};
  $J->{trans}{wallet} = createwalletaddress($INBLOCK->{pubkey});
  $J->{trans}{nin} = $INBLOCK->{nin};
  $J->{inblocks} = [];
  my $spent=0;
  foreach my $ib (@{$INBLOCK->{inblocks}}) {
    $spent++;
    my $pos=dbget($DBOUT,$ib);
    my $inblock=getinblock($pos);
    push @{$J->{inblocks}}, {
      tid => $ib, 
      pos => $pos, 
      tnr => $DBLIST->{$inblock->{pos}}, 
      spent => $spent
    };
  }
  json_out($J);
}

sub json_out {
  my ($J,$nodes,$ico) = @_;
  my $type="Recipients";
  if ($ico) { $type="Initial Coin Offering" }
  if ($nodes) { $type="Nodes $type" }
  $J->{outblocks}=[];
  my $cnt=0;
  foreach my $block (@{$INFO->{outblocks}}) {
    $cnt++;
    my $out={
      "obtype"=>2,
      "obType"=>"out",
      "ObType"=>$type,
      "bnr" => $cnt,
      "tid" => $block->{tid},
      "wallet" => $block->{wallet},
      "amount" => $block->{amount},
      "fccamount" => $block->{fccamount},
      "spent" => ($SPENT && ($block->{tid} eq $SPENT) ? true : false),
    };
    if (($cnt == $INBLOCK->{nout}) && ($block->{fee} == 0) && !$nodes) {
      $out->{"change"}=true
    } elsif (!$nodes && !$ico) {
      $out->{"fee"}=$block->{fee};
      $out->{"fccfee"}=$block->{fccfee}
    }
    push @{$J->{outblocks}}, $out
  }
}

sub json_coinbase {
  my ($J) = @_;
  $J->{trans}{ibType} = "coinbase";
  $J->{trans}{IbType} = "Coinbase";
  $J->{outblocks}=[];
  for(my $r=0;$r<=1;$r++){
    push @{$J->{outblocks}},
      {
        "obtype"=>2,
        "obType"=>"out",
        'ObType' => ($r == 0 ? "Miner Reward" : "Node Reward"),
        "bnr" => $r+1,
        'tid' => $INFO->{outblocks}[$r]{tid},
        'amount' => $INFO->{outblocks}[$r]{amount},
        'fccamount' => $INFO->{outblocks}[$r]{fccamount},
        'wallet' => $INFO->{outblocks}[$r]{wallet},
        "spent" => ($SPENT && ($INFO->{outblocks}[$r]{tid} eq $SPENT) ? true : 0),
      }
  }
}

sub json_fee {
  my ($J) = @_;
  $J->{trans}{ibType} = "fee";
  $J->{trans}{IbType} = "Node Fee Payout";
  $J->{trans}{nout} = $INBLOCK->{nout};
  json_out($J,1);
}

sub json_nav {
  my ($J) = @_;
  my $show=1;
  my $next;
  my $prev;
  $J->{nav}={
    transnr => $TRANS||'0',
    coinbase => $SHOWCB||'0',
    fee => $SHOWFEE||'0',
    pos => $BLOCKPOS||'0',
    size => $INFO->{size}||'0'
  };
  $J->{trans}={
    ibtype => $INBLOCK->{type},
    fcctime => $INBLOCK->{fcctime},
    time => fcctimestring($INBLOCK->{fcctime}),
    tid => $INBLOCK->{tid},
    tcum => $INBLOCK->{tcum},
    nout => $INBLOCK->{nout},
    amount => $INFO->{amount},
  };
  # Begin
  if (!$SHOWFEE || ($FEEPOS>0)) {
    my $first=0;
    if ($SHOWFEE) { $first=$DBLIST->{$DBFEE->[0]} }
    if ($TRANS != $first) { $J->{nav}{begin}=$first }
  }
  # Prev
  if ($TRANS>0) {
    $prev=$TRANS-1;
    if ($SHOWFEE) {
      if ($FEEPOS == 0) {
        $prev=$DBLIST->{$DBFEE->[0]}
      } else {
        $prev=$DBLIST->{$DBFEE->[$FEEPOS-1]}
      }
    } elsif (!$SHOWCB) {
      $prev=$DBLIST->{$DBNCB->[$NCBPOS-1]};
    }
    $J->{nav}{prev}=$prev;
  }
  # Next
  if ($TRANS < $LDGCOUNT) {
    $next=$TRANS+1;
    if ($SHOWFEE) {
      $show=($FEEPOS < $#{$DBFEE});
      if ($show) {
        $next=$DBLIST->{$DBFEE->[$FEEPOS+1]}
      }
    } elsif (!$SHOWCB) {
      $show=($NCBPOS < $#{$DBNCB});
      if ($show) {
        $next=$DBLIST->{$DBNCB->[$NCBPOS+1]}
      }
    }
    if ($show) { $J->{nav}{next}=$next }
  }
  # End
  if (!$SHOWFEE || ($FEEPOS<$#{$DBFEE})) {
    my $last=$LDGCOUNT;
    if ($SHOWFEE) { $last=$DBLIST->{$DBFEE->[$#{$DBFEE}]} }
    elsif (!$SHOWCB || ($NCBPOS<$#{$DBNCB})) {
      if (!$SHOWCB) { $last=$DBLIST->{$DBNCB->[$#{$DBNCB}]} }
    }
    if ($TRANS != $last) { $J->{nav}{last}=$last }
  }
}

sub json_html {
  my $J={
#    seal => $INFO,
    ledger => {
      length => $LEDGERLEN,
      seals => $LDGCOUNT,
    }
  };
  json_nav($J);
  if ($INBLOCK->{type} eq $TRANSTYPES->{genesis}) {
    json_genesis($J);
  } elsif ($INBLOCK->{type} eq $TRANSTYPES->{in}) {
    json_in($J);
  } elsif ($INBLOCK->{type} eq $TRANSTYPES->{coinbase}) {
    json_coinbase($J);
  } elsif ($INBLOCK->{type} eq $TRANSTYPES->{fee}) {
    json_fee($J);
  }
  $HTML=encode_json($J);
}

########## API #####################################################################

sub api {
  my ($client,@out) = @_;
  my $post=$client->{post};
  my $inp={}; my $info={};
  # JSON input?
  $EVALMODE=1;
  my $json = eval { decode_json($client->{postdata}) };
  $EVALMODE=0;
  if ($@) {
    # post/get
    foreach my $k (keys %{$client->{post}{key}}) {
      $inp->{$k}=$client->{post}{key}{$k}[0]
    }
  } else {
    $inp=$json
  }
  if (!$inp->{command}) {
    $out[0]=gserv::httpresponse(400); # bad request
    $info->{error}="Could not interpret request or find command, use GET/POST or HTTP-JSON, and include a 'command' field."
  } else {
    print "\t Handling ".($PTTP ? "PTTP":"FCC")." Client $client->{ip} $inp->{command} $inp->{filter} $inp->{pagesize} $inp->{startpage} $inp->{wallet}".(" " x 48)."\n";
    my $func="api_".$inp->{command};
    if (defined &$func) {
      $info=&$func($inp)
    } else {
      $info->{error}="Invalid command: '$inp->{command}'."
    }
  }
  $HTML=toJSON($info);
  if ($inp->{zip}) { $HTML=glib::zip($HTML) }
  push @out,"Content-Type: application/json";
  push @out,"Content-Length: ".length($HTML);
  push @out,"Cache-Control: no-cache, no-store, must-revalidate";
  my $data=join("\r\n",@out)."\r\n\r\n".$HTML;
  gserv::burst($client,\$data);
  $client->{killafteroutput}=1;
  print "\t Handled ".($PTTP ? "PTTP":"FCC")." Client $client->{ip} $inp->{command} ".(defined $inp->{filter} ? $inp->{filter}:"").(" " x 48)."\n";
}

sub toJSON {  return JSON->new->utf8->canonical->pretty->encode($_[0]) }

sub api_help {
  return {
    commands => [
      { name => 'get', params => [
        {'seal'=>'sealid'},
        {'tid'=>"transid"},
        {
          'wallet'=>"wallet",
          'descending'=>'*optional* [0 || 1]. Ommition defaults to 0',
          'filter'=>'*optional* [balance || coinbase || fee]. Ommition returns raw seal output.',
          'pagesize'=>'*optional* [1..items]. Ommition gives full record list',
          'startpage'=>'*optional* [0..pages]. Used in combination with [pagesize]. Ommition defaults to 0',
          'start' => '*optional* [fcctime]. Used in combination with [pagesize]. Ommition defaults to unused and 0',
          'startseal' => '*optional* [sealid]. Used in combination with [pagesize]. Ommition defaults to unused and 0',
          'startpos' => '*optional* [nextpos]. Used in combination with [pagesize]. Ommition defaults to unused and 0',
        },
      ] },
      { name => 'graph', params => ['volume','activity'] },
      { name => 'help' },
      { name => 'info' }
    ]
  }
}

sub process {
  my ($inp,$pos,$index) = @_;

  if ($inp->{pagesize} && $inp->{startpage}) {
    my $startpage=0; if (defined $inp->{startpage}) { $startpage=$inp->{startpage}; $startpage =~ s/[^0-9]//g; }
    if (!$startpage) { $startpage=0 }
    if ($index < $inp->{pagesize} * $startpage) { return 0 }
  }

  my $startpos=0; if (defined $inp->{startpos}) { $startpos=$inp->{startpos}; $startpos =~ s/[^0-9]//g; }
  if (!$startpos) { $startpos=0 }
  if ($startpos) {
    if (($inp->{descending} && $pos > $startpos) || (!$inp->{descending} && $pos < $startpos)) { return 0 }
  }

  my $start=0; if (defined $inp->{start}) { $start=$inp->{start}; $start =~ s/[^0-9]//g; }
  if (!$start) { $start=0 }
  if ($start) {
    my $block=getinblock($pos);
    if (($inp->{descending} && $block->{fcctime} > $start) || (!$inp->{descending} && $block->{fcctime} < $start)) { return 0 }
  }

  my $startseal=0; if (defined $inp->{startseal}) { $startseal=$inp->{startseal}; $startseal =~ s/[^0-9]//g; }
  if (!$startseal) { $startseal=0 }
  if ($startseal) {
    my $block=getinblock($pos);
    my $seal=$DBLIST->{$block->{pos}};
    if (($inp->{descending} && $seal > $startseal) || (!$inp->{descending} && $seal < $startseal)) { return 0 }
  }

  return 1
}

sub api_graph {
  my ($inp) = @_;
  my $type=$inp->{type}; my $db=$PLOTVOL;
  if (!$type) { $type="volume" }
  elsif ($type eq 'activity') {
    $db=$PLOTACT
  }
  my $start=$inp->{start};  
  if (!$start) { $start=0 }
  elsif ($start < $STARTTIME) { $start=0 }
  else {
    $start=int (($start-$STARTTIME) / 3600);
  }
  my $dur=$#{$db}+1; if ($inp->{duration}) { $dur=$inp->{duration} }
  my $gran=1;
  if ($inp->{gran}) {
    if ($inp->{gran} eq 'days') {
      $gran=24
    } elsif ($inp->{gran} eq 'weeks') {
      $gran=168
    } elsif ($inp->{gran} eq 'months') {
      $gran=730.5
    }
  }
  my $data=[];
  my $pos=$start; my $prev=$db->[$pos] || 0; my $prevpos=0; my $pcnt=0;
  if ($inp->{display} eq 'line') {
    push @$data,[ $prevpos, $prev ]
  }
  my $cd=$dur; my $val=0;
  while (($pos <= $#{$db}) && $cd) {
    $val=$db->[$pos];
    if ($inp->{display} eq 'line') {
      if ($val != $prev) {
        $prev=$val;
        push @$data,[ $pcnt, $prev ];
        $pcnt=0
      }
    } else {
      push @$data,$val;
    }
    $pos+=$gran; $cd--; $pcnt++
  }
  my $begin = 3600 * int( ($STARTTIME + $start * 3600) / 3600);
  my $info = {
    genesis => $STARTTIME,
    begin => $begin,
    start => $start,
    gran => $gran,
    duration => $dur,
    data => $data
  };
  if ($type eq 'activity') {
    $info->{max}=$ACTMAX
  }
  return $info
}

sub api_volume {
  return {
    volume => $VOLUME,
    age => $#{$PLOTVOL}
  }
}

sub api_get {
  my ($inp) = @_;
  my $info={ };
  if ($inp->{tid}) {
    my $tid=uc($inp->{tid});
    if ((length($tid) != 64) || ($tid =~ /[^0-9A-F]/)) {
      $info->{tid}=$tid;
      $info->{error}="Invalid TID given."
    } else {
      my $pos=dbget($DBPOS,$tid);
      if ($pos<0) {
        $info->{tid}=$tid;
        $info->{error}="TID not found."
      } else {
        $info=readblock($pos);
        $info->{seal}=$DBLIST->{$pos}
      }
    }
  } elsif (defined $inp->{seal}) {
    my $seal=$inp->{seal};
    if (($seal =~ /[^0-9]/) || ($seal > $LDGCOUNT)) {
      $info->{seal}=$seal;
      $info->{error}="Invalid seal-number given."
    } else {
      my $pos=$DBNUM->[$seal];
      $info=sealinfo($pos);
      $info->{seal}=$seal;
    }
  } elsif ($inp->{wallet}) {
    my $wallet=uc($inp->{wallet});
    $info->{wallet}=$wallet;
    if (!validwallet($wallet)) {
      $info->{error}="Invalid wallet given."
    } else {
      my $wlist=dbget($DBWAL,$wallet,1);
      if ($wlist eq '-1') {
        $info->{error}="Wallet not found."
      } else {
        if ($inp->{descending}) {
          $wlist=[sort { $b->{pos} <=> $a->{pos} } @$wlist];
        }
        if (defined $inp->{filter}) {
          if ($inp->{filter} eq 'coinbase') {
            $info->{filtered}=[];
            my $clist=[];
            foreach my $bp (@$wlist) {
              if ($bp->{type} eq $TRANSTYPES->{coinbase}) { push @$clist, $bp }
            }
            $info->{items}=(1+$#{$clist});
            if ($inp->{pagesize}) { 
              $info->{page}=int($inp->{startpage}||0); 
              $info->{pages}=int($info->{items}/$inp->{pagesize}); 
            }
            my $index=0;
            foreach my $bp (@$clist) {
              if (process($inp,$bp->{pos},$index)) {
                $itemnum++;
                my $block = readblock($bp->{pos});
                my $trans = sealinfo($bp->{pos});
                $trans->{seal}=$DBLIST->{$trans->{inblock}{pos}};
                if (!defined $inp->{pagesize} || ($inp->{pagesize}-1 > $#{$info->{filtered}}+1)) {
                  push @{$info->{filtered}},{
                    page => int($page),
                    item => $itemnum,
                    seal => $DBLIST->{$trans->{inblock}{pos}},
                    amount => $block->{fccamount},
                    fcctime => $trans->{inblock}{fcctime},
                    num => $block->{num}
                  }
                } else {
                  $info->{nextblock}=$trans->{inblock}{fcctime};
                  $info->{requesttime}=$trans->{inblock}{fcctime};
                  last
                }
              }
              $index++;
            }
          }
          elsif ($inp->{filter} eq 'fee') {
            $info->{filtered}=[];
            my $clist=[];
            foreach my $bp (@$wlist) {
              if ($bp->{type} eq $TRANSTYPES->{fee}) { push @$clist, $bp }
            }
            $info->{items}=(1+$#{$clist});
            if ($inp->{pagesize}) { 
              $info->{page}=int($inp->{startpage}||0); 
              $info->{pages}=int($info->{items}/$inp->{pagesize}); 
            }
            my $index=0;
            foreach my $bp (@$clist) {
              if (process($inp,$bp->{pos},$index)) {
                my $block = readblock($bp->{pos});
                my $trans = sealinfo($bp->{pos});
                $trans->{seal}=$DBLIST->{$trans->{inblock}{pos}};
                if (!defined $inp->{pagesize} || ($inp->{pagesize}-1 > $#{$info->{filtered}}+1)) {
                  push @{$info->{filtered}},{ 
                    seal => $DBLIST->{$trans->{inblock}{pos}},
                    amount => $block->{fccamount},
                    fcctime => $trans->{inblock}{fcctime},
                    num => $block->{num}
                  }
                } else {
                  $info->{nextblock}=$trans->{inblock}{fcctime};
                  $info->{requesttime}=$trans->{inblock}{fcctime};
                  last
                }
              }
              $index++
            }
          }
          elsif ($inp->{filter} eq 'balance') {
            $info->{filtered}=[];
            $info->{coinbase}=0;
            $info->{fee}=0;
            $info->{balance}=0;
            $info->{credited}=0;
            $info->{feespent}=0;
            $info->{wallet}=$wallet;
            my $clist=[];
            foreach my $bp (@$wlist) {
              if (
                $bp->{type} eq $TRANSTYPES->{in} ||
                $bp->{type} eq $TRANSTYPES->{genesis} ||
                $bp->{type} eq $TRANSTYPES->{out}
              ) { push @$clist, $bp }
            }
            $info->{items}=(1+$#{$clist});
            if ($inp->{pagesize}) { 
              $info->{page}=int($inp->{startpage}||0); 
              $info->{pages}=int($info->{items}/$inp->{pagesize}); 
            }
            my $index=0;
            foreach my $bp (@$clist) {
              if (process($inp,$bp->{pos},$index)) {
                if (defined $inp->{pagesize} && ($inp->{pagesize}-1 < $#{$info->{filtered}}+1)) { 
                  $info->{pos} = $inp->{startpos}||0;
                  $info->{nextpos} = $bp->{pos};
                  last 
                }
                if ($bp->{type} eq $TRANSTYPES->{in}) {
                  my $seal=sealinfo($bp->{pos}); my $to=[];
                  foreach my $b (@{$seal->{outblocks}}) {
                    if ($b->{wallet} ne $wallet) {
                      $info->{credited} += $b->{fccamount};
                      $info->{feespent} += $b->{fccfee};
                      push @$to,{ amount => $b->{fccamount}, fee => $b->{fccfee}, wallet => $b->{wallet}, num => $b->{num}, tid=>$b->{tid} }
                    }
                  }
                  push @{$info->{filtered}},{
                    seal => $DBLIST->{$seal->{inblock}{pos}},
                    num => $seal->{inblock}{num},
                    balance => 'credit',
                    fcctime => $seal->{inblock}{fcctime},
                    to => $to,
                    tid=>$seal->{inblock}{tid}
                  }
                }
                elsif ($bp->{type} eq $TRANSTYPES->{genesis}) {
                  my $ib=getinblock($bp->{pos});
                  my $block=readblock($bp->{pos});
                  push @{$info->{filtered}},{
                    balance => 'debet',
                    fcctime => $ib->{fcctime},
                    seal => 0, num => 0,
                    title => 'Genesis',
                    amount => $block->{fccamount},
                    tid=>$block->{tid}
                  }
                }
                elsif ($bp->{type} eq $TRANSTYPES->{out})  {
                  my $ib=getinblock($bp->{pos});
                  my $block=readblock($bp->{pos});
                  if (!$bp->{spent}) { $info->{balance}+=$block->{fccamount} }
                  my $from=createwalletaddress($ib->{pubkey});
                  if ($from ne $wallet) {
                    push @{$info->{filtered}},{
                      balance => 'debet',
                      fcctime => $ib->{fcctime},
                      from => $from,
                      amount => $block->{fccamount},
                      seal => $DBLIST->{$ib->{pos}},
                      num => $block->{num},
                      tid => $block->{tid}
                    }
                  }
                }
              }
              $index++;
            }
          }
          else {
            $info->{error}="Unknown filter."
          }
        }
        else {
          $info->{coinbase}=0; $info->{fee}=0;
          $info->{balance}=0; $info->{translist}=[];
          $info->{items}=(1+$#{$wlist});
          if ($inp->{pagesize}) { 
            $info->{page}=int($inp->{startpage}||0); 
            $info->{pages}=int($info->{items}/$inp->{pagesize}); 
          }
          my $index=0;
          foreach my $bp (@$wlist) {
            if (process($inp,$bp->{pos},$index)) {
              if (defined $inp->{pagesize} && ($inp->{pagesize}-1 < $#{$info->{translist}}+1)) { 
                $info->{pos} = $inp->{startpos}||0;
                $info->{nextpos} = $bp->{pos};
                last 
              }
              if ($bp->{type} eq $TRANSTYPES->{coinbase}) {
                my $ib=getinblock($bp->{pos});
                my $block=readblock($bp->{pos});
                $coinbase+=$block->{fccamount};
                if (!$bp->{spent}) { $info->{balance}+=$block->{amount} }
                push @{$info->{translist}},{ seal => $DBLIST->{$ib->{pos}}, in => $ib, out => $block }
              } elsif ($bp->{type} eq $TRANSTYPES->{fee}) {
                my $ib=getinblock($bp->{pos});
                my $block=readblock($bp->{pos});
                $info->{fee}+=$block->{amount};
                if (!$bp->{spent}) { $info->{balance}+=$block->{amount} }
                push @{$info->{translist}},{ seal => $DBLIST->{$ib->{pos}}, in => $ib, out => $block }
              } elsif ($bp->{type} eq $TRANSTYPES->{in}) {
                my $seal=sealinfo($bp->{pos});
                $seal->{seal}=$DBLIST->{$seal->{inblock}{pos}};
                push @{$info->{translist}},$seal
              } elsif (($bp->{type} eq $TRANSTYPES->{out}) || ($bp->{type} eq $TRANSTYPES->{genesis})) {
                my $ib=getinblock($bp->{pos});
                my $block=readblock($bp->{pos});
                if (!$bp->{spent}) { $info->{balance}+=$block->{amount} }
                push @{$info->{translist}},{ seal => $DBLIST->{$ib->{pos}}, in => $ib, out => $block }
              }
            }
            $index++;
          }
          $info->{fccamount}=fccstring($info->{balance}/100000000);
        }
      }
    }
  } else {
    $info->{error}="Don't know what to get (seal, tid, wallet)."
  }
  $info->{requesttime} = 1+( defined $info->{nextblock} ? $info->{filtered}[$#{$info->{filtered}}]{fcctime} : time+$FCCTIME );
  return $info
}

########  HTTPD  ##########################################################################

sub makesite {
  my ($client) = @_;
  my @out=(gserv::httpresponse(200));
  my $uri=$client->{httpheader}{uri};
  push @out,"Host: ".$SERVER->{server}{host}.":".$SERVER->{server}{port};
  push @out,"Access-Control-Allow-Origin: *";
  push @out,"Server: $COIN-Explorer-Server 1.0";
  push @out,"Date: ".fcctimestring();
  if ($uri =~ /\/api/) {
    api($client,@out)
  } elsif ($uri =~ /image\/(.+)$/) {
    my $file=$1;
    my $mime="png";
    if ($file =~ /gif$/i) { $mime='gif' }
    elsif ($file =~ /jpg$/i) { $mime='jpeg' }
    burstfile($client,"image/$file","image/$mime",@out);
  } elsif ($uri =~ /favicon\.ico$/) {
    my $file="favicon-32.png";
    my $mime="png";
    burstfile($client,"image/$file","image/$mime",@out);
  } else {
    my $tm=fcctimestring();
    if (-e "access.log") {
      gfio::append("access.log",$tm." ".$client->{ip}."\n")
    } else {
      gfio::create("access.log",$tm." ".$client->{ip}."\n")    
    }
    my $post=$client->{post};
    if (!$ONSERVER && $post->exists('restart')) {
      print " ! Restart through website\n";
      $SERV->quit;
      exit
    }
    $SHOWCB=($post->exists('showcoinbase') ? $post->get('showcoinbase') : 1);
    $SHOWFEE=($post->exists('showfee') ? $post->get('showfee') : 0);
    $TRANS=$post->get('transaction');
    $SPENT=$post->get('spent');
    $TRANS =~ s/[^0-9]//g;
    if (!defined $TRANS || ($TRANS > $LDGCOUNT)) { $TRANS=$LDGCOUNT }
    $INFO=sealinfo(blockpos());
    $INBLOCK=$INFO->{inblock};
    my $ctype="text/html";
    html();
    push @out,"Content-Type: $ctype";
    push @out,"Content-Length: ".length($HTML);
    push @out,"Cache-Control: no-cache, no-store, must-revalidate";
    my $data=join("\r\n",@out)."\r\n\r\n".$HTML;
    gserv::burst($client,\$data);
  }
  $client->{killafteroutput}=1
}

sub burstfile {
  my ($client,$file,$mime,@out)=@_;
  my $data="";
  if (!-e $file) {
    print " > n/a: $file\n";
    $out[0]=gserv::httpresponse(404)
  } else {
    $data=gfio::content($file);
    push @out,"Content-Type: $mime";
    push @out,"Content-Length: ".length($data);
    push @out,"Cache-Control: public, max-age=31536000";
  }
  my $hdata=join("\r\n",@out)."\r\n\r\n";
  $data=$hdata.$data;
  gserv::burst($client,\$data);
  $client->{killafteroutput}=1
}

###########  DATABASES  ###################################################################

sub addplotvol {
  my ($fcctime) = @_;
  my $val=$VOLUME; my $db=$PLOTVOL;
  my $hour = int (($fcctime - $STARTTIME) / 3600);
  if ($hour == $#{$db}) {
    if ($val > $db->[$#{$db}]) { $db->[$#{$db}]=$val }
  } elsif ($hour > $#{$db}) {
    my $pv=$db->[$#{$db}];
    for my $i ($#{$db}+1 .. $hour-1) {
      push @$db,$pv
    }
    push @$db,$val
  }
}
sub addplotact {
  my ($fcctime,$val) = @_;
  my $db=$PLOTACT;
  my $hour = int (($fcctime - $STARTTIME) / 3600);  
  if ($hour == $#{$db}) {
    $db->[$#{$db}]+=$val
  } elsif ($hour > $#{$db}) {
    my $pv=$db->[$#{$db}];
    for my $i ($#{$db}+1 .. $hour-1) {
      push @$db,0
    }
    push @$db,$val
  }
}

sub process_ledger {
  if (!-e "ledger$FCCEXT") {
    print "Ledger does not exist"; exit
  }
  $LEDGERLEN=-s "ledger$FCCEXT";
  if ($LEDGERLEN) {
    my $block=readblock(0); $STARTTIME=$block->{fcctime};
  }
  my $pos=0;
  if (-e "savepoint$FCCEXT") {
    loaddata();
    $VOLUME=$PLOTVOL->[$#{$PLOTVOL}];
    my $data=gfio::content("savepoint$FCCEXT");
    ($pos,$LDGCOUNT) = split(/\s/,$data);
  }
  calcledger($pos)
}

sub calcledger {
  my ($pos) = @_;
  if ($pos+5 > $LEDGERLEN) { return }
  my $fh=gfio::open("ledger$FCCEXT");  
  my $sz=$fh->filesize();
  $fh->seek($sz-5); my $c=$fh->read(1);
  if ($c ne 'z') {
    print " *! Ledger is corrupted, repairing!\n";
    FCC::fcc::truncateledger();
    unlink "savepoint$FCCEXT";
    process_ledger();
    return
  }
  my $block=readblock($pos);
  my $log="";
  while ($pos+5 < $LEDGERLEN) {
    my $typeval=$block->{type};
    my $type=$RTRANSTYPES->{$typeval};
    my $fcctime=$block->{fcctime};
    $LDGCOUNT++;
    if ($LDGCOUNT % 100 == 0) {
      my $pct=int (10000 * $pos / $LEDGERLEN)/100;
      $log = "\rCalculating Databases .. $pos ($pct %) of $LEDGERLEN   "
    }
    push @$DBNUM,$pos; $DBLIST->{$pos}=$#{$DBNUM};
    dbadd($DBPOS,$block->{tid},$pos);
    #$log .=".";
    if ($type ne 'coinbase') {
      push @$DBNCB,$pos;
      if ($type eq 'fee') {
        #$log .="1";
        push @$DBFEE,$pos
      } elsif ($type eq 'in') {
        #$log .="2";
        my $wallet=createwalletaddress($block->{pubkey});
        dbadd($DBWAL,$wallet,$pos,undef,1,$block->{type});
        $typeval=$TRANSTYPES->{out};
        # get all spendable blocks, and ..
        foreach my $ib (@{$block->{inblocks}}) {
          my $wp=dbget($DBOUT,$ib);
          # .. mark as spent
          dbadd($DBWAL,$wallet,$wp,undef,1,undef,1)
        }
      }
    }
    #$log .=".";
    my $last=0; my $act=0; my $pact=0;
    do {
      $pos+=$block->{next};
      if ($pos+5 > $LEDGERLEN) {
        $last=1
      } else {
        $block=readblock($pos);
        if ($block->{type} eq $TRANSTYPES->{out}) {
          $act+=$pact; $pact=0;
          dbadd($DBOUT,$block->{tid},$pos);
          dbadd($DBWAL,$block->{wallet},$pos,undef,1,$typeval);
          if (($type eq 'genesis') || ($type eq 'coinbase')) {
            #$log .="3";
            $VOLUME+=$block->{fccamount}
          } elsif ($type eq 'in') {
            #$log .="4";
            $pact=$block->{fccamount}+$block->{fccfee};
          }
        }
      }
    } until ($last || ($block->{type} ne $TRANSTYPES->{out}));
    #$log .=",";
    addplotvol($fcctime); addplotact($fcctime,$act);
    print $log;
  }
  print "\rCalculating Databases .. $pos (100%) of $LEDGERLEN   \n";
  savedata();
}

sub savedb {
  my ($db,$name) = @_;
  my $data="";
  foreach my $pos (@$db) {
    $data.=pack('n',$pos>>32).pack('N',$pos)
  }
  gfio::create("$name$FCCEXT",$data)
}
sub saveplot {
  my ($db,$name) = @_;
  my $data="";
  for my $i (0..$#{$db}) {
    $data.=pack('N',$db->[$i])
  }
  gfio::create("$name$FCCEXT",$data)
}
sub savedata {
  print "\r ** Saving data ";
  savedb($DBNUM,'dbnum'); print "num ";
  savedb($DBNCB,'dbncb'); print "ncb ";
  savedb($DBFEE,'dbfee'); print "fee ";
  dbsave($DBPOS,"dbpos$FCCEXT"); print "pos ";
  dbsave($DBOUT,"dbout$FCCEXT"); print "out ";
  dbsave($DBWAL,"dbwal$FCCEXT",1); print "wal ";
  saveplot($PLOTVOL,"dbplotvol"); print "vol ";
  saveplot($PLOTACT,"dbplotact"); print "act ";
  my $block=readlastblock(); my $sz=$block->{pos}+$block->{next};
  if (!-e "savepoint$FCCEXT") { calcmaxact() }
  gfio::create("savepoint$FCCEXT","$sz $LDGCOUNT");
  print " savepoint ** \n";
}

sub calcmaxact {
  foreach my $v (@$PLOTACT) {
    if ($v > $ACTMAX) { $ACTMAX = $v }
  }
}

sub loaddb {
  my ($db,$name) = @_;
  my $data=(-f "$name$FCCEXT" ? gfio::content("$name$FCCEXT"):"");
  my $num=length($data) / 6; my $pos=0;
  for (my $i=1;$i<=$num;$i++) {
    my $hp=(unpack('n',substr($data,$pos,2))<<32)+unpack('N',substr($data,$pos+2,4));
    push @$db,$hp;
    if ($name eq 'dbnum') { $DBLIST->{$hp}=$i-1 }
    $pos+=6
  }
}

sub loadplot {
  my ($db,$name) = @_;
  my $data=(-f "$name$FCCEXT" ? gfio::content("$name$FCCEXT"):"");
  my $num=length($data)>>2; my $pos=0;
  for my $i (0..$num-1) {
    push @$db,unpack('N',substr($data,$pos,4)); $pos+=4
  }
}

sub loaddata {
  loaddb($DBNUM,'dbnum');
  loaddb($DBNCB,'dbncb');
  loaddb($DBFEE,'dbfee');
  $DBPOS=dbload("dbpos$FCCEXT");
  $DBOUT=dbload("dbout$FCCEXT");
  $DBWAL=dbload("dbwal$FCCEXT",1);
  loadplot($PLOTVOL,"dbplotvol");
  loadplot($PLOTACT,"dbplotact");
  calcmaxact()
}

######### IO CONTROL ##########################################################

sub killserver {
  $SERV->quit(@_);
}

sub fatal {
  if ($EVALMODE) { return }
  if (!-e "error.log") { gfio::create("error.log","Error Log $COIN Explorer\n") }
  gfio::append("error.log","\nFatal Error: @_\n".trace());
  killserver(error("return=1","!!!! FATAL ERROR !!!!\n",@_,"\n"));
  exit
}
sub intquit {
  killserver('130 Interrupt signal received'); exit
}  
sub termquit {
  killserver('108 Client forcably killed connection'); exit
}

# EOF FCC/PTTP Blockchain Explorer (C) 2018 Chaosje, Domero