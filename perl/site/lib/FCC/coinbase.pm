#!/usr/bin/perl

package FCC::coinbase;

################################################
#                                              #
#     FCC Coinbase server & functions          #
#                                              #
#      (C) 2019 Domero                         #
#                                              #
################################################

use strict;
no strict 'refs';
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.1.2';
@ISA         = qw(Exporter);
@EXPORT      = qw($MINERPAYOUT perm minehash encrypt);
@EXPORT_OK   = qw();

use gfio 1.10;
use Crypt::Ed25519;
use Time::HiRes qw(gettimeofday usleep);
use gerr;
use gserv 3.1.2 qw(localip wsmessage burst);
use gclient 7.4.1;
use FCC::global 2.3.2;
use FCC::miner 1.1.3;
use FCC::wallet 2.1.4;
use JSON;

################################################################################

my $DEBUG=0;

my $SERVER;
my $COINBASETIME = 300; # one every 5 minutes to mine
my $NODELIST = {};
my $FCCINIT = 0;
my $CBCOUNT = 0;
my $CBPASS = "";
my $CBKEY = "";
my $TABLE = [];
my $PROBLEM = "";
my $DFAC = 9;
my $DIFF = fac($DFAC);
my $TARDIFF = $DIFF;
my $HINTS = 0;
my $EHINTS = 0;
my $HINTSTR = "";
my $EHINTSTR = "";
my $START = 0;
my $ANSWER = "";
my $WINNER = "";
my $WINNERNODE = "";
my $WINTIME = 0;
my $FLOODLIST = {};
my $FLOODMAX = 10;
my $FLOODTIMEOUT = {};
my $FLOODTIME = 0;
my $UPDATEMODE = 0;
my $UPDATELIST = {};
my $UPDATEDIR = "";
my $LASTSOL = "";
my $CALLBACKLIST = [];
my $CALLBACKCLIENTS = [];
my $CALLBACKPOS = 0;
my $MAXLL = 0;

my $FEEINIT = 0;
my $FEEMINIMUM = 1000000;
my $FEETIME = 3600;
my $FEETIMEBLOCK = int((time+$FCCTIME) / $FEETIME);
my $FEEWEEK = int((time+$FCCTIME-345600) / 604800);
my $FEESENT = 0;
my $FEERECEIVED = [];
my $FEESTART = 0;
my $FEELEDGER = 0;
my $FEEBEGIN = 0;
my $FEEBLOCKHEIGHT = 0;
my $FEEBLOCKS = [];
my $PAYOUT = {}; 

$SIG{'INT'}=\&intquit;
$SIG{'TERM'}=\&termquit;
$SIG{'PIPE'}=\&sockquit;
$SIG{__DIE__}=\&fatal;
$SIG{__WARN__}=\&fatal;

1;

############### Error handling #################

sub killserver {
  my ($msg) = @_;
  $SERVER->{killing}=1;
  if (!$msg) { $msg="FCC-Server terminated" }
  print " !! Killing server .. $msg\n";
  $SERVER->quit()
}

sub killnode {
  my ($client,$msg) = @_;
  if ($client->{killafteroutput}) {
    $client->{killme}=1
  } else {
    wsmessage($client,$msg,'close');
    $client->{killafteroutput}=1
  }
}

sub fatal {
  print "!!!! FATAL ERROR !!!!\n",@_,"\n";
  killserver("Fatal Error"); error(@_)
}
sub intquit {
  print "** INTERRUPT RECEIVED **\n".gerr::trace()."\n";
  killserver('130 Interrupt signal received')
}  
sub termquit {
  killserver('108 Client forcably killed connection')
}
sub sockquit {
  my $client=$SERVER->{activeclient};
  if ($client) {
    killnode($client,"32 TCP/IP Connection error")
  } else {
    print " *!* WARNING *!* Unexpected SIGPIPE in server-kernel. @_\n"
  }
}

################################################################################
#
# COINBASE
#
################################################################################

sub readtable {
  if (-e 'table.fcc') {
    my @rows = split(/\n/,gfio::content('table.fcc'));
    foreach my $r (@rows) {
      my ($diff,$time,$sol) = split(/ /,$r);
      if (!$time) { $time=1 }
      push @$TABLE,{ diff => $diff, time => $time, solution => $sol }
    }
    if ($TABLE->[0]) {
      $LASTSOL=$TABLE->[0]{solution}
    }
  }
}

sub writetable {
  my @dat=();
  foreach my $r (@$TABLE) {
    push @dat,join(" ",$r->{diff},$r->{time})
  }
  gfio::create('table.fcc',join("\n",@dat))
}

sub getdiff {
  if ($#{$TABLE}<0) { return }
  my $td=0; my $tt=0;
  foreach my $t (@$TABLE) {
    $td+=$t->{diff}; $tt+=$t->{time}
#    $hr+=$weight*($t->{diff}/$t->{time});
#    $wt+=$weight; $weight=$weight*0.9
  }
  my $wt=(1+$#{$TABLE})*$COINBASETIME;
  my $adf=int($td / (1+$#{$TABLE}));
  my $tfac=$wt / $tt;
  $DIFF = int ($adf * $tfac); $TARDIFF=$DIFF;
  my $fc=1; $DFAC=1;
  while ($fc<$DIFF) { $DFAC++; $fc*=$DFAC }
  if ($DFAC<10) { $DFAC=10; $HINTS=0; $DIFF=fac($DFAC); return }
  # $DFAC--; # testmode
  $HINTS=$DFAC-int ($DFAC*($fc-$DIFF) / $fc);
  if ($HINTS == 1) {
    # X.1 is the same as X-1.X-1 = X-1.0
    $DFAC--; $HINTS=0; $DIFF=fac($DFAC); return
  }
  if ($HINTS == 0) {
    # X.0 stays X.0
    $DIFF=fac($DFAC); return
  }
  if ($HINTS >= $DFAC) {
    # X.X is X.0
    $HINTS=0; $DIFF=fac($DFAC); return 
  }
  $DIFF=fac($DFAC-1)*$HINTS
}

sub getsecdiff {
  $EHINTS=0;
  if ($HINTS) {
    my $cfac = fac($DFAC-2)*$HINTS;
    my $efac = int ($TARDIFF / $cfac);
    if ($efac >= $DFAC) { return }
    if ($efac <= 0) { return }
    if ($efac == 1) { $efac = 2 }
    $EHINTS = $efac;
    $DIFF = $cfac * $EHINTS
  }
}

sub create {
  getdiff(); getsecdiff();
  $CBCOUNT++;
  my $cumm=""; for (my $i=0;$i<$DFAC;$i++) { $cumm.=chr(65+$i) }
  $PROBLEM=perm($cumm,int rand(fac($DFAC)));
  $HINTSTR=""; $EHINTSTR="";
  if ($HINTS) {
    my $target=substr($PROBLEM,0,1); my $hints=1; my $chars = { $target => 1 };
    $HINTSTR=$target;
    while ($hints<$HINTS) {
      my $char=chr(65 + int rand($DFAC));
      if (!$chars->{$char}) {
        $chars->{$char}=1; $HINTSTR.=$char; $hints++
      }
    }
    $HINTSTR=perm($HINTSTR,int rand(fac($HINTS)))
  }
  if ($EHINTS) {
    my $target=substr($PROBLEM,1,1); my $hints=1; my $chars = { $target => 1 };
    $EHINTSTR=$target;
    while ($hints<$EHINTS) {
      my $char=chr(65 + int rand($DFAC));
      if (!$chars->{$char}) {
        $chars->{$char}=1; $EHINTSTR.=$char; $hints++
      }
    }
    $EHINTSTR=perm($EHINTSTR,int rand(fac($EHINTS)))
  }
  $ANSWER=minehash($CBCOUNT,$PROBLEM);
  $START=gettimeofday();
  prtm(); print "Challenge $CBCOUNT - $DFAC : $HINTS : $EHINTS $DIFF\n"
}

sub validate {
  my ($client,$solhash,$wallet) = @_;
  if (!validwallet($wallet)) { return 0 } # answer doesn not matter if you cannot claim
  if ($solhash ne solhash($wallet,$PROBLEM)) { return 0 } # not the correct solution
  # we got a winner!
  my $passed=int (gettimeofday()-$START);
  if (!$passed) { $passed=1 } # avoid nasty zero's
  writecount();
  unshift @$TABLE, { diff => $DIFF, time => $passed, solution => $PROBLEM };
  $LASTSOL=$PROBLEM;
  while ($#{$TABLE} >= 36) { pop @$TABLE }
  writetable();
  $WINNER=$wallet;
  $WINNERNODE=$NODELIST->{$client->{fccinit}}{wallet};
  $WINTIME=time + $FCCTIME;
  $passed = (int ($passed*1000))/1000;
  prtm(); print "Solution $CBCOUNT - $passed $wallet\n";
  return 1
}

sub challenge {
  return {
    command => 'mine',
    challenge => $ANSWER,
    coincount => $CBCOUNT,
    diff => $DIFF,
    length => $DFAC,
    hints => $HINTSTR,
    ehints => $EHINTSTR,
    reward => $MINERPAYOUT,
    time => time + $FCCTIME,
    lastsol => $LASTSOL
  }
}

sub readcount {
  $CBCOUNT=0;
  if (-e 'coinbase.fcc') { $CBCOUNT=gfio::content('coinbase.fcc') }
}

sub writecount {
  gfio::create('coinbase.fcc',$CBCOUNT)
}

sub readupdates {
  if (-e 'updates.fcc') {
    my $data=gfio::content('updates.fcc');
    my $dir=$INC{'gfio.pm'}; $dir =~ s/\\/\//g;
    my @sdir=split(/\//,$dir); pop @sdir;
    $UPDATEDIR=join("/",@sdir);
    $UPDATELIST={};
    foreach my $file (split(/\n/,$data)) {
      my $data=gfio::content("$UPDATEDIR/$file");
      my @stat=stat("$UPDATEDIR/$file");
      my $ud = {
        mtime => $FCCTIME + $stat[9],
        content => zb64($data),
        size => length($data)
      };
      $ud->{fhash}=securehash($ud->{content});
      $UPDATELIST->{$file}=$ud
    }
  }
}

sub setfeeledger {
  my ($len,$blockheight) = @_;
  $FEELEDGER=$len; $FEEBLOCKHEIGHT=$blockheight;
  gfio::create('ledgerlen.fcc',"$FEELEDGER $FEEBEGIN $FEEBLOCKHEIGHT")
}

sub getfeeledger {
  if (-e 'ledgerlen.fcc') {
    ($FEELEDGER,$FEEBEGIN,$FEEBLOCKHEIGHT)=split(/ /,gfio::content('ledgerlen.fcc'))
  }
  if (-e 'feeblocks.fcc') {
    $FEEBLOCKS=decode_json(gfio::content('feeblocks.fcc'))
  }
  if (-e 'feepayout.fcc') {
    $PAYOUT=decode_json(gfio::content('feepayout.fcc'))
  }
}

sub savefeeblocks {
  gfio::create('feeblocks.fcc',encode_json($FEEBLOCKS))
}

sub savepayout {
  gfio::create('feepayout.fcc',encode_json($PAYOUT))
}

sub setpass {
  my ($pass) = @_; $CBPASS=$pass;
  gfio::create('password.fcc',securehash($pass))
}

sub checkpass {
  my ($pass) = @_;
  if (!-e 'password.fcc') { return 0 }
  my $cp=gfio::content('password.fcc');
  if (securehash($pass) eq $cp) {
    $CBPASS=$pass; return 1
  }
  return 0
}

sub encrypt {
  my ($pass,$key) = @_;
  my $h=securehash('fcc'.$pass);
  my $kl=length($key);
  my $hl=length($h);
  my $pos=0; my $hpos=0; my $res="";
  while ($pos<$kl) {
    my $v=hexdec(substr($key,$pos,1));
    my $w=hexdec(substr($h,$hpos,1));
    my $x=$v ^ $w;
    $res.=dechex($x,1);
    $pos++; $hpos++; if ($hpos==$hl) { $hpos=0 }
  }
  return $res
}

sub coinbase {
  my $sign=dechex($CBCOUNT,8).$WINNER.dechex($MINERPAYOUT,16).'0000'.$WINNERNODE.dechex($MINEBONUS,16).'0000';
  my $signature=octhex(Crypt::Ed25519::sign($sign,hexoct($FCCSERVERKEY),hexoct($CBKEY)));
  return {
    command => 'coinbase',
    coincount => $CBCOUNT,
    outblocks => [
      { type=>'out', wallet => $WINNER, amount => $MINERPAYOUT, fee => 0 },
      { type=>'out', wallet => $WINNERNODE, amount => $MINEBONUS, fee => 0 }
    ],
    fcctime => $WINTIME,
    signature => $signature
  }
}

################################################################################
# Node Lists

sub getnode {
  my($key)=@_;
  if (defined $NODELIST->{$key}){
    return $NODELIST->{$key}
  }
}

sub getnodelist {
  my $list=[];
  foreach my $k (keys %$NODELIST) { push @$list,$k }
  my $rlist=[]; my $tot=1+$#{$list};
  while ($tot>0) {
    my $sel=int rand($tot);
    push @$rlist,$list->[$sel];
    splice(@$list,$sel,1);
    $tot--
  }
  return $rlist
}

################################################################################
# Broadcast 

sub bjson {
  my($data,$mask)=@_;
  foreach my $node (keys %$NODELIST) {
    if (!$mask || ($node ne $mask)) {
      outjson($NODELIST->{$node}{client},$data)
    }
  }
}

################################################################################
# Send

sub outjson {
  my ($client,$msg) = @_;
  if (!$msg) {
    error "FCC::coinbase::outjson: Empty message"
  }
  if (!ref($msg)) { 
    error "FCC::coinbase::outjson: Message has to be array or hash reference to be converted to JSON"
  }
  if ($client->{fcc} && $client->{fcc}{callback}) {
    gclient::wsout($client,encode_json($msg))
  } else {
    wsmessage($client,encode_json($msg))
  }
}

################################################################################
#
#   START FCC
#
################################################################################

sub startfcc {
  my ($coin,$password) = @_;
  if ($coin eq 'PTTP') { setcoin('PTTP') }
  if ($COIN eq 'FCC') {
    print <<EOT;

  FFFF  CCC   CCC
  F    C     C          COINBASE SERVER $FCCBUILD
  FF   C     C            (C) 2019 Domero
  F     CCC   CCC

EOT
  } else {
    print <<EOT

  PPPP  TTTTT TTTTT PPPP
  P   P   T     T   P   P   COINBASE SERVER $FCCBUILD
  PPPP    T     T   PPPP      (C) 2019 Domero
  P       T     T   P
  P       T     T   P

EOT
  }
  if (!-e 'password.fcc') {
    print "Initializing the server!\n\n";
    print "Please enter a new password for the $COIN-server: ";
    my $pass=<STDIN>; chomp $pass;
    setpass($pass); writecount();
    # create keys
    my $wallet;
    if ($COIN eq 'PTTP') {
      print "Mining a public key starting with '11111' .. this may take a while .. \n";
      do {
        $wallet=newwallet();
      } until (substr($wallet->{pubkey},0,5) eq '11111');
    } else {
      print "Mining a public key starting and ending with 'FCC' .. this may take a while .. \n";
      do {
        $wallet=newwallet();
      } until ((substr($wallet->{pubkey},0,3) eq 'FCC') && (substr($wallet->{pubkey},-3) eq 'FCC'));
    }
    print "\nPublic key = $wallet->{pubkey}\n";
    gfio::create('pubkey.fcc',$wallet->{pubkey});
    print "Please distribute 'pubkey.fcc' in the package before releasing the coin or hardcode it in global.pm as \$FCCSERVERKEY.\n";
    my $enc=encrypt($pass,$wallet->{privkey});
    gfio::create('thekey.fcc',$enc);
    print "Saved 'thekey.fcc', don't distribute this file (although it's scrambled)!\n** NEVER LOOSE THIS FILE **\n";
    $CBKEY=$wallet->{privkey};
    print "Ready to roll .. press any key .. ";
    my $pk=<STDIN>; return
  }
  my $pass=$password;
  if (!$pass) {
    print "Please enter password: ";
    $pass=<STDIN>;
    if (!$pass) { exit }
    chomp $pass;
  }
  if (!checkpass($pass)) {
    print "Invalid password!\n"; exit
  }
  if (!-e 'thekey.fcc') {
    print "Private key not found!!!\nThis is a serious error .. the whole coinbase now has changed.\nPlease initialize again.. delete 'password.fcc', then notify all nodes to update 'pubkey.fcc'!\n";
    exit
  }
  my $key=gfio::content('thekey.fcc');
  $CBKEY=encrypt($pass,$key);
  readcount(); readtable(); getfeeledger(); readupdates();
  my $ssl=''; if (localip() eq $FCCSERVERIP) { $ssl='factorialcoin.nl' }
  $SERVER=gserv::init(\&handle,\&clientloop,$ssl,\&servhandler);
  $SERVER->{name}="$COIN Coinbase Server $FCCBUILD (C) 2019 Domero";
  print "Connecting on port $FCCSERVERPORT\n";
  $SERVER->{server}{port}=$FCCSERVERPORT;
  $SERVER->{allowedip}=[ '*' ];
  $SERVER->{timeout}=5;
  $SERVER->{verbose}=$DEBUG;
  $SERVER->{debug}=0;
  # $SERVER->{verboseheader}=1;
  print "Starting $SERVER->{name}\n";
  $SERVER->start(1,\&loop);
  if ($SERVER->{error}) {
    print "Server error: $SERVER->{error}\n"
  }
  print "Server terminated.\n\n"
}

################################################################################
#
#   HANDLE 
#
################################################################################

sub clientloop {
  my ($client) = @_;
  if ($FLOODTIMEOUT->{$client->{ip}}) {
    $client->{killme}=1
  }
}

sub servhandler {
  my ($client,$cmd,@data)=@_; $cmd //= ''; @data = (@data);
  if (ref($cmd) =~ /^gserv\:\:client/) { my $c = $client; $client = $cmd; $cmd = $c }
  return if ($cmd eq 'connect');
  if (ref($client) =~ /^gserv\:\:client/) {
    my @post = (map { $_ } keys %{$client->{post}{key}});
    print prtm(), 
      "ServHandler ($client->{ip}):[", 
      ($client->{httpheader}{uri} ? ":$client->{httpheader}{method} $client->{httpheader}{uri}".($client->{httpheader}{getdata} ? "?$client->{httpheader}{getdata}":'') : ''), 
      "]: ",
      "\n";
  }
}

sub handle {
  my ($client,$command,$data) = @_;
  if ($SERVER->{killing}) { return }
  if (!$data) { $data="" } my @out;
  if ($DEBUG==2) {
    if (($command ne 'sent') && ($command ne 'received')) {
      print " -> $command * $data\n";
    }
  }
  if ($command eq 'connect') {
    if ($FLOODLIST->{$client->{ip}}) {
      $FLOODLIST->{$client->{ip}}++;
      if ($FLOODLIST->{$client->{ip}} >= $FLOODMAX) {
        if ($FLOODLIST->{$client->{ip}} == $FLOODMAX) {
          print prtm(),"Flood detected from IP $client->{ip}\n";
          gserv::out($client,"Flood detected");
          $client->{killafteroutput}=1;
        } else {
          $client->quit()
        }
        $FLOODTIMEOUT->{$client->{ip}}=time+3600;
        return
      }
    } else {
      $FLOODLIST->{$client->{ip}}=1;      
    }
  }
  if ($command eq 'telnet') {
    $client->{killme}=1; return
  }
  if ($command eq 'ready') {
    if ($data ne 'get') {
      @out=(gserv::httpresponse(405))
    }
    $client->{httpdata}=''; my @out=(); my $mime="text/plain";
    if ($client->{post}->exists('nodelist')) {
      @out=(gserv::httpresponse(200));
      my $nodelist=getnodelist();
      $client->{httpdata}=join(" ",@$nodelist)
    } 
    elsif ($client->{post}->exists('challenge')) {
      @out=(gserv::httpresponse(200));
      my $challenge=challenge();
      $client->{httpdata}=encode_json($challenge);
      $mime="application/json";
    } elsif ($client->{post}->exists('ping')) {
      @out=(gserv::httpresponse(200));
      my $response="PONG";
      my $pong=$client->{post}->get('ping');
      if ($pong) { $response.=" $pong" }
      $client->{httpdata}=$response
    } elsif ($client->{post}->exists('time') || $client->{post}->exists('fcctime')) {
      @out=(gserv::httpresponse(200));
      $client->{httpdata}=time + $FCCTIME
    } elsif ($client->{post}->exists('wallet')) {
      @out=(gserv::httpresponse(200));
      my $w=newwallet();
      $client->{httpdata}=encode_json({ encryted => 0, wlist => [{ wallet=>$w->{wallet}, pubkey=>$w->{pubkey}, privkey=>$w->{privkey}, name=>$w->{name} }]});
      $mime="application/json";
    } elsif ($client->{post}->exists('update')) {
      readupdates();
      @out=(gserv::httpresponse(200));
      $client->{httpdata}="Filelist updated."
    } else {
      @out=(gserv::httpresponse(200));
      $client->{httpdata}="$COIN Server $FCCBUILD\r\nLedger version = ".ledgerversion()."\r\ntime = ".fcctimestring()." (".(time + $FCCTIME).")\r\nGET Options = nodelist, ping, time, wallet\r\n\r\n(C) 2019 Domero, Groningen, NL"
    }
    push @out,"Host: ".$SERVER->{server}{host}.":".$SERVER->{server}{port};
    push @out,"Access-Control-Allow-Origin: *";
    push @out,"Content-Type: $mime";
    push @out,"Content-Length: ".length($client->{httpdata});
    push @out,"Server: $COIN-Server 1.0";
    push @out,"Date: ".fcctimestring();
    if ($FLOODLIST->{$client->{ip}}) { $FLOODLIST->{$client->{ip}}-- }
    my $data=join("\r\n",@out)."\r\n\r\n".$client->{httpdata};
    $client->{killafteroutput}=1;
    gserv::burst($client,\$data);
    # my $cmd=$client->{post}->get('command')
  } elsif ($command eq 'handshake') {
    print " + Node connected $client->{ip}:$client->{port}\n";
  } elsif ($command eq 'input') {
    $::EVALMODE++;
    my $k; eval { $k=decode_json($data) };
    $::EVALMODE--;
    if ($@) {
      print prtm(),"Illegal data (no JSON) received from $client->{ip}:$client->{port}: `$data`\n";
      $client->{killme}=1; return
    }
    my $cmd=$k->{command};
    if (!$cmd) {
      print prtm(),"Illegal data (no command) received from $client->{ip}:$client->{port}: $cmd\n";
      outjson($client,{ command=>'error', error=>"No command given in input" });
      if ($FLOODLIST->{$client->{ip}}) { 
        $FLOODLIST->{$client->{ip}}--;
        if (!$FLOODLIST->{$client->{ip}}) { delete $FLOODLIST->{$client->{ip}} }
      }
      $client->{killafteroutput}=1;
      return
    }
    my $func="c_$cmd";
    if (defined &$func) {
      &$func($client,$k)
    } else {
      print prtm(),"Illegal command received from $client->{ip}:$client->{port}: $cmd\n";
      outjson($client,{ command=>'error', error=>"Unknown command given in input" }); 
      if ($FLOODLIST->{$client->{ip}}) { 
        $FLOODLIST->{$client->{ip}}--;
        if (!$FLOODLIST->{$client->{ip}}) { delete $FLOODLIST->{$client->{ip}} }
      }
      $client->{killafteroutput}=1;
    }
  } elsif (($command eq 'quit') || ($command eq 'error')) {
    my $sg='-'; if ($command eq 'error') { $sg='x' }
    if (!$data) { $data='quit' }
    if ($FLOODLIST->{$client->{ip}}) {
      $FLOODLIST->{$client->{ip}}--;
      if (!$FLOODLIST->{$client->{ip}}) { delete $FLOODLIST->{$client->{ip}} }
    }
    if ($client->{websockets}) {
      foreach my $key (keys %$NODELIST) {
        if (($NODELIST->{$key}{host} eq $client->{ip}) && ($NODELIST->{$key}{realport} eq $client->{port})) {
          print " $sg Node exited $key ($data)\n";
          delete $NODELIST->{$key}; last
        }
      }
    } elsif ($command eq 'error') {
      print " x Client error ($client->{ip}:$client->{port}): $data\n"
    }
  }
}

################################################################################
#
#   CALLBACK SYSTEM
#
################################################################################

sub callback {
  my $ctm=gettimeofday();
  if ($#{$CALLBACKCLIENTS} >= 0) {
    if ($CALLBACKPOS > $#{$CALLBACKCLIENTS}) { $CALLBACKPOS = 0 }
    my $client=$CALLBACKCLIENTS->[$CALLBACKPOS];
    if ($ctm-$client->{fcc}{time}>5) {
      $client->quit("callback timeout")
    }
    $client->takeloop();
    $CALLBACKPOS++
  }
  if ($#{$CALLBACKLIST} < 0) { return }
  my $new=shift @$CALLBACKLIST;
  my $client=gclient::websocket($new->{ip},$new->{port},0,\&handlecallback,0,5);
  $client->{fcc} = { callback => 1, time => $ctm, port => $new->{port} };
  if ($client->{error}) {
    print " xx Illegal callback from $new->{ip}:$new->{port}: $client->{error}\n"
  } else {
    push @$CALLBACKCLIENTS,$client
  }
}

sub handlecallback {
  my ($client,$command,$data) = @_;
  if ($command eq 'connect') {
    my $p='Unknown'; if ($client->{fcc} && $client->{fcc}{port}) { $p=$client->{fcc}{port} }
    print " -> Calling back $client->{host}:$p\n";
    my $signature=octhex(Crypt::Ed25519::sign($client->{host}.'callback',hexoct($FCCSERVERKEY),hexoct($CBKEY)));
    outjson($client,{ command => 'callback', signature => $signature })
  } elsif ($command eq 'quit') {
    splice(@$CALLBACKCLIENTS,$CALLBACKPOS,1);
    $client->quit
  } elsif ($command eq 'error') {
    my $ip="0.0.0.0"; if($client){ $ip=$client->{ip} }
    my $port="????"; if ($client->{fcc}) { $port=$client->{fcc}{port} }
    print " !! Error callback \n";
    if($client){ print "CLIENT:$client\n" }else{print "NOCLIENT\n" }
    if($ip){ print "IP:$ip\n" }
    if($port){ print "PORT:$port\n" }
    if($data) { print "DATA:$data\n" }
    splice(@$CALLBACKCLIENTS,$CALLBACKPOS,1);
    $client->quit
  }
}

################################################################################
#
#   MAIN LOOP
#
################################################################################

sub loop {
  usleep(10000);

  callback();

  ##############################################################################
  # Fee History & Payout
  my $tm=time+$FCCTIME;
  if (int($tm / 60) != $FLOODTIME) {
    $FLOODTIME=int($tm / 60);
    my @fl=sort { $FLOODTIMEOUT->{$a} <=> $FLOODTIMEOUT->{$b} } (keys %$FLOODTIMEOUT);
    my $p=0;
    while (($p<=$#fl) && ($FLOODTIMEOUT->{$fl[$p]} <= time)) {
      delete $FLOODTIMEOUT->{$fl[$p]}; $p++
    }
  }
  if (int($tm / $FEETIME) != $FEETIMEBLOCK) {
    $FEETIMEBLOCK=int($tm / $FEETIME);
    $FEEINIT=1
  }
  if ($FEEINIT == 1) {
    my $nodes=getnodelist(); $FEESENT=0; $FEERECEIVED=[]; $FEESTART=gettimeofday();
    for (my $n=0;(($n<9) && ($n<=$#{$nodes}));$n++) {
      outjson($NODELIST->{$nodes->[$n]}{client},{ command => 'ledgerstatus' });
      $FEESENT++
    }
    if ($FEESENT == 0) { $FEEINIT=0 }
    else { $FEEINIT=2 }
  } elsif ($FEEINIT == 2) {
    my $ctm=gettimeofday();
    if (($#{$FEERECEIVED}>=$FEESENT-1) || ($ctm - $FEESTART > 10)) {
      if ($#{$FEERECEIVED} < 0) { $FEEINIT=0 }
      else {
        my $ll={}; my $bh={};
        foreach my $k (@$FEERECEIVED) {
          $bh->{$k->{ledgerlength}}=$k->{blockheight};
          if (!$ll->{$k->{ledgerlength}}) { $ll->{$k->{ledgerlength}}=1 } else { $ll->{$k->{ledgerlength}}++ }          
        }
        my @sl = sort { $ll->{$b} <=> $ll->{$a} } (keys %$ll);
        if ($FEELEDGER == $sl[0]) {
          my $nodes=getnodelist(); my $wallets=[];
          foreach my $node (@$nodes) {
            if ($tm-$NODELIST->{$node}{connected} >= $FEETIME) {
              push @$wallets,$NODELIST->{$node}{wallet}
            }
          }
          push @$FEEBLOCKS,{ fee => 0, wallets => $wallets };
          savefeeblocks();
          $FEEINIT=15;
          print " [ No Fee this hour ]\n"
        } else {
          $FEEBEGIN=$FEELEDGER;
          setfeeledger($sl[0],$bh->{$sl[0]});
          $FEEINIT=3
        }
      }
    }
  } elsif ($FEEINIT == 3) {
    my $nodes=getnodelist(); $FEESENT=0; $FEERECEIVED=[]; $FEESTART=gettimeofday();
    for (my $n=0;(($n<9) && ($n<=$#{$nodes}));$n++) {
      outjson($NODELIST->{$nodes->[$n]}{client},{ command => 'calculatefee', position => $FEEBEGIN-4, length => $FEELEDGER - $FEEBEGIN });
      $FEESENT++
    }
    if ($FEESENT == 0) { $FEEINIT=0 }
    else { $FEEINIT=7 }
  } elsif ($FEEINIT == 7) {
    my $ctm=gettimeofday();
    if (($#{$FEERECEIVED}>=$FEESENT-1) || ($ctm - $FEESTART > 10)) {
      if ($#{$FEERECEIVED} < 0) { $FEEINIT=0 }
      else {
        my $ll={};
        foreach my $k (@$FEERECEIVED) {
          if(!$k->{totfee}) { 
            print "FEE ERROR:\n";
            for my $kk ( keys %$k ) {
              print "* $kk = $k->{$kk}\n";
            }
          } else {
            if (!$ll->{$k->{totfee}}) { $ll->{$k->{totfee}}=1 } else { $ll->{$k->{totfee}}++ }
          }
        }
        my @sl = sort { $ll->{$b} <=> $ll->{$a} } (keys %$ll);
        my $nodes=getnodelist(); my $wallets=[];
        foreach my $node (@$nodes) {
          if ($tm-$NODELIST->{$node}{connected} >= $FEETIME) {
            push @$wallets,$NODELIST->{$node}{wallet}
          }
        }
        if ($#sl >= 0) {
          if (!$sl[0] || ($sl[0] =~ /[^0-9]/)) { $sl[0]=0 }
          push @$FEEBLOCKS,{ fee => $sl[0], wallets => $wallets };
          savefeeblocks();
          print " [ Fee this hour = $sl[0] ]\n"
        } else {
          print " [ No fee this hour ]\n"
        }
        $FEEINIT=0;
      }
    }
  }
  if (int(($tm-345600) / 604800) != $FEEWEEK) {
    $FEEWEEK=int(($tm-345600) / 604800);
    my $wc={}; my $tot=0; my $totfee=0;
    foreach my $b (@$FEEBLOCKS) {
      $totfee += $b->{fee};
      foreach my $w (@{$b->{wallets}}) {
        if (!$wc->{$w}) { $wc->{$w}=1 } else { $wc->{$w}++ }
        $tot++
      }
    }
    print " [ Weekly earnings = $totfee.]\n";
    my $payout=0; my $savefee=0; my $ownfee=0;
    foreach my $w (keys %$wc) {
      my $fee=int($totfee*$wc->{$w} / $tot);
      $payout+=$fee;
      if ($COIN eq 'PTTP') {
        my $wfee=int ($fee*5/11);
        my $pfee=int ($fee*3/11);
        my $ofee=$fee-($wfee+$pfee);
        $savefee+=$pfee; $ownfee+=$ofee;
        if (!$PAYOUT->{$w}) { $PAYOUT->{$w}=$wfee } else { $PAYOUT->{$w}+=$wfee }
      } else {
        if (!$PAYOUT->{$w}) { $PAYOUT->{$w}=$fee } else { $PAYOUT->{$w}+=$fee }
      }
    }
    my $spare=$totfee-$payout;
    my $sign=dechex($spare,8) . dechex($FEEBLOCKHEIGHT,12);
    my $outblocks=[]; my $totpay=0; my $num=0;
    if ($savefee) {
      push @$outblocks,{ type => 'out', wallet => '112CBF4A764AE20C7204918147E74F95F74D173EE6A29517D859470266F5B8D43C8D', amount => $savefee, fee => 0 }
    }
    if ($ownfee) {
      push @$outblocks,{ type => 'out', wallet => '1127F7C5D8A14D67349228D941B2099A59D966B77EE3F0B038F929F01939CB33EF49', amount => $ownfee, fee => 0 }
    }
    foreach my $w (keys %$PAYOUT) {
      if ($PAYOUT->{$w} > $FEEMINIMUM) {
        push @$outblocks,{ type => 'out', wallet => $w, amount => $PAYOUT->{$w}, fee => 0 };
        $sign.=$w.dechex($PAYOUT->{$w},16).'0000';
        $totpay+=$PAYOUT->{$w}; $num++;
        delete $PAYOUT->{$w}
      }
    }
    print " [ Weekly payout = $totpay to $num nodes ]\n";
    if ($#{$outblocks} >= 0) {
      my $sign=octhex(Crypt::Ed25519::sign($sign,hexoct($FCCSERVERKEY),hexoct($CBKEY)));
      my $tm=time+$FCCTIME;
      bjson({ command => 'feepayout', fcctime => $tm, blockheight => $FEEBLOCKHEIGHT, spare => $spare, signature => $sign, outblocks => $outblocks })
    }
    $FEEBLOCKS=[];
    savefeeblocks();
    savepayout();
  }
}

sub c_ledgerstatus {
  my ($client,$k) = @_;
  push @$FEERECEIVED,$k;  
}

sub c_calculatefee {
  my ($client,$k) = @_;
  push @$FEERECEIVED,$k;  
}

################################################################################
#
#   NODE INIT
#
################################################################################

sub c_init {
  my ($client,$k) = @_;
  if (!validwallet($k->{wallet})) {
    outjson($client,{ command=>'error', error=>"Init: Invalid wallet given" }); 
    $client->{killafteroutput}=1;
    return
  }
  if (!$k->{ledgerlength}) {
    outjson($client,{ command=>'error', error=>"Init: No ledger found" });
    $client->{killafteroutput}=1;
    return
  }
  if (!$MAXLL) {
    $MAXLL=$k->{ledgerlength}
  } else {
    if ($MAXLL-$k->{ledgerlength}>100000) {
      outjson($client,{ command=>'error', error=>"Init: Ledger too small" });
      $client->{killafteroutput}=1;
      return
    } elsif ($k->{ledgerlength}>$MAXLL) {
      $MAXLL=$k->{ledgerlength}
    }
  }
  my $fcctm=time+$FCCTIME;
  my $key=$client->{ip}.":".$k->{port};
  $NODELIST->{$key}={}; $client->{fccinit}=$key;
  $NODELIST->{$key}{client}       = $client;
  $NODELIST->{$key}{host}         = $client->{ip};
  $NODELIST->{$key}{realport}     = $client->{port};
  $NODELIST->{$key}{port}         = $k->{port};
  $NODELIST->{$key}{connected}    = $fcctm;
  $NODELIST->{$key}{wallet}       = $k->{wallet};
  $NODELIST->{$key}{cumhash}      = $k->{cumhash};
  $NODELIST->{$key}{blockheight}  = $k->{blockheight};
  $NODELIST->{$key}{ledgerlength} = $k->{ledgerlength};
  outjson($client,{ command => 'init', fcctime => $fcctm });
  my $announce={ command=>'newnode', host=>$client->{ip}, port=>$k->{port} };
  print " * Initiated $key\n";
  bjson($announce,$key);
}

################################################################################
#
#   MINER COINBASE COMMANDS
#
################################################################################

sub c_challenge {
  my ($client,$k) = @_;
  if (!$FCCINIT) { create(); $FCCINIT=1 }
  if ($client->{fccinit}) {
    outjson($client,challenge())
  } else {
    print prtm(),"Not initialised: $client->{ip}:$client->{port} calling 'challenge'\n";
    outjson($client,{ command=>'error', error=>"Not initialised calling 'challenge'" });
    $client->{killafteroutput}=1
  }
}

sub c_solution {
  my ($client,$k) = @_;
  if ($client->{fccinit}) {
    if (validate($client,$k->{solhash},$k->{wallet})) {
      outjson($client,{ command => 'solution' });
      bjson(coinbase());
      create();
      bjson(challenge())
    } else {
      outjson($client,{ command => 'solerr' }); return
    }
  } else {
    print prtm(),"Not initialised: $client->{ip}:$client->{port} calling 'solution'\n";
    outjson($client,{ command=>'error', error=>"Not initialised calling 'solution'" });
    $client->{killafteroutput}=1
  }
}

################################################################################
#
#   Base Commands
#
################################################################################

sub c_fcctime {
  my ($client) = @_;
  outjson($client,{ command => 'fcctime', fcctime => time + $FCCTIME })
}

sub c_nodelist {
  my ($client) = @_;
  my $nodes=getnodelist();
  my $nodelist=[];
  foreach my $node (@$nodes) {
    my ($host,$port)=split(/\:/,$node);
    push @$nodelist,{ host => $host, port => $port }
  }
  outjson($client,{ command => 'nodelist', nodes => $nodelist })
}

sub c_updatelist {
  my ($client) = @_;
  my $flist=[];
  foreach my $file (keys %$UPDATELIST) {
    push @$flist,{ file => $file, fhash => $UPDATELIST->{$file}{fhash}, mtime => $UPDATELIST->{$file}{mtime} }
  }
  outjson($client,{ command => 'updatelist', files => $flist })
}

sub c_updatefile {
  my ($client,$k) = @_;
  if ($UPDATELIST->{$k->{file}}) {
    my $size=$UPDATELIST->{$k->{file}}{size};
    my $data=$UPDATELIST->{$k->{file}}{content};
    my $signature=octhex(Crypt::Ed25519::sign($k->{file}.$size.$data,hexoct($FCCSERVERKEY),hexoct($CBKEY)));
    outjson($client,{ command => 'download', file => $k->{file}, size => $size, data => $data, signature => $signature })
  } else {
    outjson($client,{ command => 'error', error => 'Requested file to download does not exist' });
  }
}

sub c_callmeback {
  my ($client,$k) = @_;
  if (!$k->{port} || ($k->{port} =~ /[^0-9]/) || ($k->{port} > 65535)) {
    outjson($client,{ command => 'quit', message => "Illegal port given in callback request" });
    $client->{killafteroutput}=1; return
  }
  print " <- Callback $client->{ip}:$k->{port}\n";
  push @$CALLBACKLIST,{ ip => $client->{ip}, port => $k->{port} }
}

################## Down the rabbithole ######################

sub c_rabbithole {
  my ($client,$k) = @_;
  print " *!* RABBITHOLE $k->{caterpillar}\n";
  if (!checkpass($k->{password})) {
    outjson($client,{ command => 'error', error => 'Illegal password' });
    return
  }
  if ($k->{caterpillar} eq 'shutdown') {
    my $msg=$k->{message};
    if (!$msg) { $msg="The core is rebooting because of a major update"}
    my $signature=octhex(Crypt::Ed25519::sign($msg,hexoct($FCCSERVERKEY),hexoct($CBKEY)));
    bjson({ command => 'shutdown', message => $msg, signature => $signature });
    outjson($client,{ command => 'rabbithole', message => "Core shutdown" })
  } elsif ($k->{caterpillar} eq 'message') {
    if ($k->{message}) {
      my $signature=octhex(Crypt::Ed25519::sign($k->{message},hexoct($FCCSERVERKEY),hexoct($CBKEY)));
      bjson({ command => 'message', message => $k->{message}, signature => $signature });
      outjson($client,{ command => 'rabbithole', message => "Message sent" })
    } else {
      outjson($client,{ command => 'error', error => 'No message given' });
    }
  } elsif ($k->{caterpillar} eq 'reset') {
    if ($k->{message}) {
      my $signature=octhex(Crypt::Ed25519::sign($k->{message},hexoct($FCCSERVERKEY),hexoct($CBKEY)));
      bjson({ command => 'reset', message => $k->{message}, signature => $signature });
      outjson($client,{ command => 'rabbithole', message => "Databases reset" })
    }
  } elsif ($k->{caterpillar} eq 'hardreset') {
    if ($k->{message}) {
      my $signature=octhex(Crypt::Ed25519::sign($k->{message},hexoct($FCCSERVERKEY),hexoct($CBKEY)));
      bjson({ command => 'hardreset', message => $k->{message}, signature => $signature });
      outjson($client,{ command => 'rabbithole', message => "Ledger reset" })
    }
  } elsif ($k->{caterpillar} eq 'resetip') {
    if ($k->{message}) {
      my $signature=octhex(Crypt::Ed25519::sign($k->{message},hexoct($FCCSERVERKEY),hexoct($CBKEY)));
      bjson({ command => 'resetip', message => $k->{message}, mask => $k->{mask}, signature => $signature });
      outjson($client,{ command => 'rabbithole', message => "Resetting your node" })
    }
  }
}

# EOF FCC::coinbase (C) 2019 Domero
