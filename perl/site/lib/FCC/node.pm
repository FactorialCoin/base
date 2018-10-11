#!/usr/bin/perl

package FCC::node;

#######################################
#                                     #
#     FCC & PTTP Node                 #
#                                     #
#    (C) 2018 Chaosje, Domero         #
#                                     #
#######################################

use strict;
no strict 'refs';
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '3.01';
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw();

use POSIX;
use JSON;
use gerr;
use gfio 1.10;
use Digest::SHA qw(sha256_hex sha512_hex);
use Crypt::Ed25519;
use gserv 4.3.2;
use gclient 7.7.3;
use Time::HiRes qw(gettimeofday usleep);
use FCC::global 2.01;
use FCC::wallet 2.12;
use FCC::fcc 1.25;

my $DEBUG = 0;
my $DEBUGMODE = 0;
my $AVT = 0;

# some to become config
my $SERVER;              # gserv-handle of node-server
my $SERVQUIT=0;          # prevent double quit
my $FIREWALL = {};       # IP firewall
my $CHECKROUTING=1;      # check if we have checked if we have portforwarding
my $PARENTLOOP=0;        # loop all parents one by one
my $SERVERNODE;          # active node in parentloop
my $LEAFLOOP=0;          # loop all leaves one by one
my $SERVERLEAF;          # active leaf in leafloop
my $DATASENT=0;          # bytes sent in total
my $DATARECEIVED=0;      # bytes received in total
my $EVALMODE=0;            # soon to be a goner!

# Infomode is a way to restore from hardforks in combination with the FCC-server (a must in dev-mode)
my $INFOMODE=0;          # Run node to gain information
my $INFOTIME=0;          # Just some extra time to let more nodes connect
my $INFODOWNLOAD=0;      # download the best ledger?
my $INFONODE;            # node to read ledger from
my $INFOLL=0;            # ledgerlength wanted
my $INFOPOS=0;           # position we are downloading ledger from
my $INFOREAD=0;          # event busy?

my $LASTCLIENTRUN=0;     # maintenance timekeeper
my $WALLET;              # node wallet
my $WALLETPASS;          # node wallet password, if protected
my $FCCSERVER = [ $FCCSERVERIP, $FCCSERVERPORT ];
my $FCCSERVERLAN = [ '192.168.1.103', $FCCSERVERPORT ]; # debug on LAN mode (localmode)
my $FCCHANDLE;           # gclient handle to the FCC-Server
my $CYCLELOOP=0;         # ready to check for votes?
my $FCCINIT=0;           # Initialisation state
my $STATUSTIME=time;     # status-message timekeeper
my $FCCRECONNECT= { sec => 0, time => time };
my $FCCHANDSHAKE=0;      # FCC-server identified?
my $TRYTIME=0;           # Start time of accumulating nodes on init
my $MAXNODES=500;        # max clients to our node
my $MAXPARENTS=500;      # max parents to connect to
my $MAXFAULTS=3;         # max faults a client may make
my $FCCDNS = [
  'http://icanhazip.com/',
  'http://plain-text-ip.com/',
  'https://api.ipify.org/',
  'https://wtfismyip.com/text'
];
my $CORENODES=0;
my $LEDGERLEN=0;
my $LASTBLOCK;
my $PARENTLIST={};
my $NODES={};
my $LEAVES={};
my $CLIENTIP={};

my $SYNC={};
my $SYNCING=0;
my $FIRSTSYNC=1;
my $LEDGERWANTED=0;
my $SYNCPOS=0;
my $SYNCBUF={};
my $SYNCSTORED=0;
my $REQUESTED=0;
my $REQBLOCKPOS=0;

my $TRESLIST={};
my $TRANSLIST={};
my $TRANSLISTDONE={};
my $TRANSDISTLIST=[];
my $TRANSDIST=0;
my $TRANSDISTDATA;
my $TRANSDISTDONE={};
my $BLOCKLIST={};
my $VOTE={};
my $VOTING=0;
my $ADDCOINBASE;
my $TRANSCATCHUP={};
my $UPDATEFILES=[];
my $UPDATEDIR;
my $UPDATEMODE=1;
my $SHUTDOWNMODE=0;
my $CURVERSION;
my $COINBASELIST=[];
my $MINING=0;
my @SOLMINER=();
my $CALLBACKTIME=0;

$SIG{'INT'}=\&intquit;
$SIG{'TERM'}=\&termquit;
$SIG{'PIPE'}=\&sockquit;
$SIG{__DIE__}=\&fatal;
$SIG{__WARN__}=\&fatal;

1;

sub infomode {
  $INFOMODE=1; $INFODOWNLOAD=0
}

sub prout {
  my (@txt) = @_;
  my $text=join('',@txt);
  if (!$DEBUGMODE && (substr($text,0,3) eq ' *>')) { return }
  $text =~ s/\n$//;
  my ($s,$m,$h) = localtime(time + $FCCTIME);
  if (length($m)<2) { $m="0$m" }
  if (length($h)<2) { $h="0$h" }
  my $tm="[$h:$m] ";
  my @lines = split(/\n/,$text);
  foreach my $line (@lines) {
    while (length($line)>71) {
      my $sl=substr($line,0,67)." ..";
      my $space=(' 'x(71-length($sl)));
      print STDOUT "\r$tm$sl$space\n";
      $line=substr($line,67)
    }
    my $space=(' 'x(71-length($line)));
    print STDOUT "\r$tm$line$space\n"
  }
}

sub datasent {
  return $DATASENT
}

# OneHippy
sub getci {
  my ($client,$var,$function) = @_;
  if ($client->{fcc}) {
    if ($client->{fcc}{function} eq $function) {
      push @$var,{ host => $client->{mask}, starttime => $client->{fcc}{hellotime}, faults => $client->{fcc}{faults}, version => $client->{fcc}{version} }
    }
  }
}
sub connectinfo {
  my $parents=[];
  foreach my $mask (keys %$PARENTLIST) {
    my $node=$PARENTLIST->{$mask}; my $c=$node->{handle};
    if ($c) {
      push @$parents,{ mask => $mask, starttime => $c->{fcc}{hellotime}, faults => $c->{fcc}{faults}, version => $c->{fcc}{version} }
    }
  }
  my $leaves=[]; my $miners=[]; my $nodes=[]; my $unknowns=[];
  $SERVER->broadcastfunc(\&getci,$leaves,'leaf');
  $SERVER->broadcastfunc(\&getci,$miners,'miner');
  $SERVER->broadcastfunc(\&getci,$nodes,'node');
  $SERVER->broadcastfunc(\&getci,$unknowns,'unknown');
  return { parents => $parents, leaves => $leaves, miners => $miners, nodes => $nodes, unknowns => $unknowns }
}
sub setserv {
 my($ip,$port)=@_;
 $FCCSERVERLAN = [ $ip,$port ];
}

################# FCC MAGIC #############################################################################################################

sub fccconnect {
  my ($localmode) = @_;
  my $txt=" * Connecting to $COIN-SERVER ";
  if ($localmode) {
    prout $txt,join(":",@$FCCSERVERLAN)," .. ";
    $FCCHANDLE=gclient::websocket(@$FCCSERVERLAN,0,\&handlefccserver,0)
  } else {
    prout $txt,join(":",@$FCCSERVER)," .. ";
    $FCCHANDLE=gclient::websocket(@$FCCSERVER,0,\&handlefccserver,1)
  }
  if ($FCCHANDLE->{error}) {
    prout " * Connecting to $COIN-Server Failed! $FCCHANDLE->{error}\n"; return 0
  }
  $FCCHANDLE->{fcc}={ isparent=>1, isfccserver => 1 };
  $FCCHANDLE->takeloop();
  return 1
}

sub newwall {
  prout "Not found! Create wallet now? (Y/n) ";
  my $res=<STDIN>; chomp $res;
  if (substr(lc($res),0,1) eq 'n') { exit }
  $WALLET=newwallet();
  prout "Encode wallet with password [ leave blank for none ]: ";
  $WALLETPASS=<STDIN>; chomp $WALLETPASS;
  savewallet($WALLET,$WALLETPASS)
}

sub start {
  allowsave();
  if ((defined $_[0]) && (uc($_[0]) eq 'PTTP')) {
    setcoin('PTTP'); shift @_;
    $FCCSERVER = [ $FCCSERVERIP, $FCCSERVERPORT ];
    $FCCSERVERLAN = [ '192.168.1.103', $FCCSERVERPORT ]; # debug on LAN mode (localmode)
  }
  my ($myport,$slavemode,$localmode,$fccserv) = @_;
  if ($fccserv) {
    if ($localmode) { $FCCSERVERLAN->[0]=$fccserv } else { $FCCSERVER->[0]=$fccserv }
  }
  if (-e "update$FCCEXT") { unlink("update$FCCEXT") }
  my $vers=join('.',substr($FCCVERSION,0,2)>>0,substr($FCCVERSION,2,2));
  # in slavemode call $node->takeloop() while $node->{server}{running}
  # use localmode for testing on LAN
  if ($COIN eq 'PTTP') {
    prout <<EOT;

  PPPP  TTTTT TTTTT  PPPP
  P   P   T     T    P   P   FULL NODE SERVER v$FCCBUILD
  PPPP    T     T    PPPP      Ledger Version: $vers
  P       T     T    P           (C) 2018 Domero
  P       T     T    P

EOT
  } else {
    prout <<EOT;

  FFFF  CCC   CCC
  F    C     C          FULL NODE SERVER v$FCCBUILD
  FF   C     C            Ledger Version: $vers
  F    C     C              (C) 2018 Domero
  F     CCC   CCC
  
EOT
  }
  prout "Opening wallet .. ";
  if (!walletexists()) {
    newwall()
  } else {
    if (-e "nodewallet$FCCEXT") { 
      $WALLET=decode_json(gfio::content("nodewallet$FCCEXT")) 
    } else {
      if (walletisencoded()) {
        prout "\nEnter wallet password .. ";
        $WALLETPASS=<STDIN>; chomp $WALLETPASS;
        if (!validwalletpassword($WALLETPASS)) {
          prout "Illegal password!\n"; exit
        }
      }
      my $wlist=loadwallets($WALLETPASS);
      if ($#{$wlist} < 0) {
        newwall()
      } elsif ($#{$wlist} == 0) {
        $WALLET=$wlist->[0]
      } else {
        prout "\nChoose a wallet .. \n";
        my $num=0;
        foreach my $w (@$wlist) {
          $num++; prout "$num\. ";
          if ($w->{name}) { prout $w->{name}."\n   " }
          prout $w->{wallet}."\n"
        }
        prout "\n0. exit\n\nMake a choice .. ";
        my $ch=<STDIN>; chomp $ch;
        if (!$ch) { exit }
        if ($ch =~ /[^0-9]/) { exit }
        if (($ch < 1) || ($ch > $num)) { exit }
        $WALLET=$wlist->[$ch-1]
      }
      gfio::create("nodewallet$FCCEXT",encode_json({ name => $WALLET->{name}, wallet => $WALLET->{wallet} }))
    }
  }
  prout $WALLET->{name}." ".$WALLET->{wallet};
  prout "Searching our IP .. ";
  my $myip=myip(); if (!$myip) { prout "Failed!\n"; exit }
  my $localip=gclient::localip();
  prout "$myip ($localip)";
  prout "Starting $COIN Node Server $FCCBUILD ($vers)";
  prout "+++ Making time and space worth loving for +++"; prout(' ');
  if (!$myport) {
    if ($COIN eq 'PTTP') {
      $myport=9633
    } else {
      $myport=7050 
    }
  }
  # start node
  $SERVER=gserv::init(\&handleserver,\&serverloop);
  $SERVER->{fcc}={};
  $SERVER->{fcc}{ip}=$myip;
  $SERVER->{fcc}{localip}=$localip;
  $SERVER->{fcc}{port}=$myport;
  $SERVER->{server}{port}=$myport;
  $SERVER->{fcc}{slavemode}=$slavemode;
  $SERVER->{fcc}{localmode}=$localmode || 0;
  $SERVER->{fcc}{status}=0;
  $SERVER->{fcc}{ledgersynced}=0;
  $SERVER->{maxclients}=$MAXNODES;
  $SERVER->{websocketmode}=1;
  $SERVER->{killhttp}=1;
  $SERVER->{pingtime}=80+int(rand(20));
  $SERVER->{debug}=0;
  $SERVER->{name}="$COIN Node $vers ($FCCBUILD) by Chaosje";
  push @{$SERVER->{allowedip}},'*';
  $SERVER->{verbose}=$DEBUG;
  $SERVER->{verbosepingpong}=($DEBUG>1);
  if ($localmode) {
    $SERVER->{fcc}{host}=$localip;
    $SERVER->{fcc}{mask}=$localip.":".$myport
  } else {
    $SERVER->{fcc}{host}=$myip;
    $SERVER->{fcc}{mask}=$myip.":".$myport    
  }
  # now we go into infinity
  prout " ** Starting server $SERVER->{name}";
  $SERVER->start(!$slavemode,\&serverloop);
  if ($SERVER->{error}) {
    prout " ** Could not start server: $SERVER->{error}\n"
  }
  return $SERVER
}

sub killserver {
  my ($msg) = @_;
  if ($SERVQUIT) { exit }
  $SERVQUIT=1;
  if (!$msg) { $msg="Node-Server terminated" }
  prout " !! Killing server .. $msg";  
  savedb();
  my @nodes=keys %$PARENTLIST;
  foreach my $mask (@nodes) {
    my $node=$PARENTLIST->{$mask};
    if ($node->{handle}) {
      if ($node->{identified}) {
        if ($FCCINIT == 255) { $REQUESTED -- }
      }
      delete $PARENTLIST->{$mask};
      $node->{handle}->wsquit($msg);
    }
  }
  if ($FCCHANDLE) {
    $FCCHANDLE->wsquit($msg);
  }
  $SERVER->quit();
  prout " *!* Server killed *!*";
  print STDOUT "\n";
  exit
}

sub killclient {
  my ($client,$msg) = @_;
  if (!$msg) { $msg='quit' }  
  if ($client && !$client->{killed}) {
    my $f=""; if ($client->{ip} && $CLIENTIP->{$client->{ip}}) { $CLIENTIP->{$client->{ip}}-- }
    if ($client->{fcc} && $client->{fcc}{function}) {
      $f='('.$client->{fcc}{function}.')'
    }
    prout "   x Disconnected $f $client->{mask}: $msg\n";
    if ($client->{fcc}{isparent}) {
      if ($PARENTLIST->{$client->{mask}}{identified}) {
        if ($FCCINIT == 255) { $REQUESTED -- }
      }
      delete $PARENTLIST->{$client->{mask}};
      $client->wsquit($msg);
    } elsif ($client->{fcc}) {
      if ($client->{fcc}{function} eq 'node') {
        if ($VOTING && $client->{fcc}{ready}) { $VOTE->{totak}-- }
        delete $NODES->{$client->{mask}}
      } elsif ($client->{fcc}{function} eq 'leaf') {
        delete $LEAVES->{$client->{mask}};
        if ($TRESLIST->{$client->{mask}}) {
          delete $TRESLIST->{$client->{mask}}
        }
      } elsif ($client->{fcc}{function} eq 'miner') {
        delete $LEAVES->{$client->{mask}};
      }
      wsmessage($client,$msg,'close');
      $client->{killed}=1
    }
  }
}

sub fatal {
  if ($EVALMODE) { return }
  error("!!!! FATAL ERROR !!!!\n",@_,"\n");
#  prout "!!!! FATAL ERROR !!!!\n",@_,"\n";
#  killserver("Fatal Error"); error(@_)
}
sub intquit {
  #print " ---> Servquit = $SERVQUIT           \n";
  if (!$SERVQUIT) {
    killserver('130 Interrupt signal received');
    $SERVQUIT=1
  }
  exit
}  
sub termquit {
  killserver('108 Client forcably killed connection'); exit
}
sub sockquit {
  my $client=$SERVER->{activeclient};
  if ($client) {
    killclient($client,"32 TCP/IP Connection error")
  } elsif ($SERVERNODE) {
    killclient($SERVERNODE,"32 TCP/IP Connection error");
  } else {
    prout " *!* WARNING *!* Unexpected SIGPIPE in node-kernel. @_\n"
  }
}

################ Global functions ###################

sub myip {
  my $ip=""; my $p=0;
  while (($ip !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) && ($p<=$#{$FCCDNS})) {
    my $res=gclient::website($FCCDNS->[$p]);
    $ip=$res->{content}; chomp($ip); $p++;
  }
  return $ip
}

sub takeloop {
  my ($client) = @_;
  if ($SERVER->{slavemode}) {
    $SERVER->takeloop()
  }
}

sub checklanwan {
  my ($host) = @_;
  if (($host =~ /^192.168/) || ($host =~ /^10.0.0/) || ($host =~ /^127.0.0.1/)) {
    return $SERVER->{fcc}{localmode}
  }
  return !$SERVER->{fcc}{localmode}
}

sub outws {
  my ($client,$msg,$command) = @_;
  if ($DEBUG) {
    my $func=$client->{fcc}{function};
    if ($client->{fcc}{isparent}) { $func='parent' }
    prout "SERV >OUT WS ($func): $command - $msg\n"
  }
  if ($client->{fcc}{isparent}) {
    $client->wsout($msg,$command)
  } else {
    wsmessage($client,$msg,$command)
  }
}

sub outjson {
  my ($client,$msg) = @_;
  if ($client && $client->{fcc} && !$client->{killed}) {
    if ($DEBUG) {
      my $func=$client->{fcc}{function};
      if ($client->{fcc}{isfccserver}) { $func='FCC' }
      elsif ($client->{fcc}{isparent}) { $func='parent' }
      prout "SERV >OUT JSON ($func): "
    }
    if (!$msg) {
      error "FCC::node::outjson: Empty message"
    }
    if (!ref($msg)) { 
      error "Message has to be array or hash reference to be converted to JSON"
    }
    $EVALMODE=1;
    my $json; eval { $json=encode_json($msg) };
    $EVALMODE=0;
    if ($@) { error "JSON error: $@" }
    if ($DEBUG) {
      if (ref($msg) eq 'HASH') {
        my @out=();
        foreach my $k (sort keys %$msg) {
          my $v=$msg->{$k};
          if (ref($v) eq 'HASH') {
            push @out,"$k={".join(", ",sort (keys %$v))."}"
          } elsif (ref($v) eq 'ARRAY') {
            my $num=$#{$v};
            push @out,"$k=ARRAY[$num]"
          } elsif (defined($v)) {
            if (length($v)>500) { $v=substr($v,0,500)." ..." }
            push @out,"$k=$v"
          } else {
            push @out,"$k=[undef]"
          }
        }
        prout join(", ",@out),"\n"
      } else {
        prout "$json\n"
      }
    }
    if ($client->{fcc}{isparent}) {
      gclient::wsout($client,$json)
    } else {
      wsmessage($client,$json)
    }
  }
}

sub outnc {
  my ($client,$data) = @_;
  if (($client->{fcc}{function} eq 'node') && ($client->{fcc}{ready})) {
    if ($DEBUG) {
      prout "SERV >OUT JSON (node): $data"
    }
    wsmessage($client,$data)
  }
}

sub outparents {
  my ($data) = @_;
  foreach my $p (keys %$PARENTLIST) {
    my $node=$PARENTLIST->{$p};
    if ($node->{identified}) {
      if ($DEBUG) {
        prout "SERV >OUT JSON (parent): $data"
      }
      gclient::wsout($node->{handle},$data)
    }
  }
}

sub outjsonparents {
  my ($data) = @_;
  foreach my $p (keys %$PARENTLIST) {
    my $node=$PARENTLIST->{$p};
    if ($node->{identified}) {
      outjson($node->{handle},$data)
    }
  }
}

sub outcore {
  my ($data) = @_;
  $SERVER->broadcastfunc(\&outnc,$data);
  outparents($data)
}

sub outcorejson {
  my ($data) = @_;
  if (ref($data) ne "HASH") { error("Outcorejson: HASH-ref expected") }
  outcore(encode_json($data))
}

sub getcl {
  my ($client,$nodes) = @_;
  if (($client->{fcc}{function} eq 'node') && ($client->{fcc}{ready})) {
    push @$nodes,$client
  } 
}

sub corelist {
  my $nodes=[];
  $SERVER->broadcastfunc(\&getcl,$nodes);
  foreach my $p (keys %$PARENTLIST) {
    my $node=$PARENTLIST->{$p};
    if ($node->{identified}) {
      push @$nodes,$node->{handle}
    }
  }
  return $nodes
}

sub addparent {
  my ($mask) = @_;
  my $node=$PARENTLIST->{$mask}; my $ctm=gettimeofday();
  $node->{tried}=1; $node->{lastconnect}=$ctm;
  my $newclient=gclient::websocket($node->{host},$node->{port},0,\&handlenode);
  $newclient->{mask}=$mask;
  if (!$newclient->{error}) {
    $newclient->{fcc} = { host=>$node->{host}, port=>$node->{port}, function=>'node', isparent=>1, identified=>0, hellotime=>$ctm };
    $node->{handle}=$newclient;
    prout " + Connected to $mask\n"
  } else {
    prout $newclient->{error},"\n";
    if (!$node->{connectcount}) {
      $node->{connectcount}=1
    } else {
      $node->{connectcount}++
    }
    if ($node->{connectcount}>=3) {
      my $mask=$node->{host}.':'.$node->{port};
      prout "Node $mask is unreachable\n";
      if ($PARENTLIST->{$mask}) {
        delete $PARENTLIST->{$mask}
      }
    }
  }
}

sub addcandidate {
  my ($host,$port) = @_;

  # Do not connect to ourself!
  if (($host eq $SERVER->{fcc}{host}) && ($port eq $SERVER->{fcc}{port})) { return }
  #if (!$SERVER->{fcc}{localmode}) {
  #  if (!$INFOMODE) {
  #    if ($host eq $SERVER->{fcc}{ip}) { return }
  #  }
  #}
  my $mask=join(":",$host,$port);
  if ($NODES->{$mask}) { return } # already connected as a child
  foreach my $bip (@{$SERVER->{blockedip}}) { if ($bip eq $host) { return } } # blocked by firewall

  if (!$PARENTLIST->{$mask}) {
    $PARENTLIST->{$mask} = {
      host => $host,
      port => $port,
      mask => $mask,
      handle => undef,
      connected => 0,
      identified => 0,
      lastconnect => 0,
      tried => 0,
      ledgerlen => 0,
      lastcum => "",
      blockheight => -1
    }
  }
}

sub minerspresent {
  foreach my $leaf (keys %$LEAVES) {
    if ($leaf->{fcc} && $leaf->{fcc}{function} eq 'miner') { return 1 }
  }
  return 0
}

sub savedb {
  prout " ** Saving databases .. ";
  save(); prout " ** Databases saved OK!";
}

sub addnodelist {
  my ($host,$port) = @_;
  my $sm="$host $port";
  if (!-e "nodelist$FCCEXT") {
    gfio::create("nodelist$FCCEXT",$sm)
  } else {
    my @nodes = split(/\n/,gfio::content("nodelist$FCCEXT"));
    my @out=();
    foreach my $node (@nodes) {
      if ($node eq $sm) { return }
      push @out,$node
    }
    unshift @out,$sm;
    gfio::create("nodelist$FCCEXT",join("\n",@out))
  }
}

sub firewall {
  # todo: make timebased
  my ($ip) = @_;
  if (!$FIREWALL->{$ip}) { $FIREWALL->{ip}=1 } 
  else { 
    $FIREWALL->{ip}++;
    if ($FIREWALL->{ip} >= 10) {
      prout " ! blocked IP $ip";
      push @{$SERVER->{blockedip}},$ip
    }
  }
}

################## FCC-Server ################################

sub outfcc {
  my ($data) = @_;
  outjson($FCCHANDLE,$data)
}

sub handlefccserver {
  my ($client,$command,$data) = @_;
  if ($DEBUG) {
    if (!$data) { $data="" }
    prout " <- [$COIN] $command = $data\n"
  }
  if ($command eq 'init') {
    $FCCRECONNECT->{sec}=0
  }
  if ($command eq 'connect') {
    prout " * Succesfully connected to the $COIN\-Server";
    if ($FCCINIT >= 65535) { $FCCINIT=16383 } else { $FCCINIT=3 }
    $FCCHANDSHAKE=1
  } elsif ($command eq 'input') {
    my $json;
    $EVALMODE=1;
    eval("\$json=decode_json(\$data)");
    $EVALMODE=0;
    if($@){
      prout "**WARNING** $COIN\-Server Posted not a Json String!\n$data\n$@"
    } else {
      my $cmd=$json->{command};
      my $func='cfcc_'.$cmd;
      if (defined(&$func)) { &$func($client,$json) }
      else { prout "**WARNING** $COIN\-Server Function '$cmd' not yet implemented!" }
    }
  } elsif ($command eq 'quit') {
    if ($FCCHANDLE) {
      if ($FCCRECONNECT->{sec}==0) {
        prout " *!* ERROR: Lost the connection to the $COIN\-Server: $data";
        gclient::wsout($FCCHANDLE,$data,'close');
        $FCCHANDLE=undef
      }
    }
    $FCCRECONNECT={ sec => 10, time => time }
  } elsif ($command eq 'error') {
    prout " *!!* $COIN\-Server responded with ERROR: $data"
  }
}

sub cfcc_error {
  my ($client,$k) = @_;
  prout " *!!* $COIN\-Server responded with ERROR: $k->{error}"
}

sub cfcc_fcctime {
  my ($client,$k) = @_;
  setfcctime($k->{fcctime}-time);
  prout "> [$COIN] Time offset set to $FCCTIME\n";
  $FCCINIT |= 8;
}

sub cfcc_nodelist {
  my ($client,$k) = @_;
  my $num=1+$#{$k->{nodes}};
  prout "> [$COIN] The Core-network has $num nodes connected\n";
  foreach my $node (@{$k->{nodes}}) { addcandidate($node->{host},$node->{port}) }
  $FCCINIT |= 16;
}

sub cfcc_newnode {
  my ($client,$k) = @_;
  addcandidate($k->{host},$k->{port})
}

sub cfcc_init {
  my ($client,$k) = @_;
  prout " !!! NODE INITIALISED AND ACTIVE !!!\n";
  outjsonparents({ command => 'ready' });
  $FCCHANDSHAKE=0; $FCCINIT = 65535
}

sub cfcc_calculatefee {
  my ($client,$k) = @_;
  outfcc({ command => 'calculatefee', totfee => calculatefee($k->{position},$k->{length}) })
}

sub cfcc_ledgerstatus {
  my ($client,$k) = @_;
  outfcc({ command => 'ledgerstatus', blockheight => $LASTBLOCK->{num}, ledgerlength => $LEDGERLEN })
}

sub cfcc_updatelist {
  my ($client,$k) = @_;
  my $dir=$INC{'gfio.pm'}; $dir =~ s/\\/\//g;
  my @sdir=split(/\//,$dir); pop @sdir;
  $UPDATEDIR=join("/",@sdir);
  $UPDATEFILES=[];
  foreach my $file (@{$k->{files}}) {
    my $fname="$UPDATEDIR/$file->{file}";
    if (-e $fname) {
      my $cont=gfio::content($fname);
      if (securehash($cont) ne $file->{fhash}) {
        my @stat=stat($fname);
        if ($stat[9] < $FCCTIME + $file->{mtime}) {
          push @$UPDATEFILES,$file->{file}
        }
      }
    } else {
      push @$UPDATEFILES,$file->{file}
    }
  }
  if ($#{$UPDATEFILES} < 0) {
    $UPDATEMODE=3;
  } else {
    outfcc({ command => 'updatefile', file => shift @$UPDATEFILES })
  }
}

sub cfcc_download {
  my ($client,$k) = @_;
  my $sign=$k->{file}.$k->{size}.$k->{data};
  if (Crypt::Ed25519::verify($sign,hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
    my $decoded=b64z($k->{data});
    if (length($decoded) == $k->{size}) {
      gfio::create("$UPDATEDIR/".$k->{file},$decoded);
      prout " * Updated $UPDATEDIR/$k->{file}\n"
    } else {
      my $tlong=length($decoded) - $k->{size};
      prout " * ERROR updating $UPDATEDIR/$k->{file}: Size Mismatch of $tlong - ";
    }
  } else {
    prout " * ERROR updating $UPDATEDIR/$k->{file}: Signature Incorrect\n"
  }
  if ($#{$UPDATEFILES}<0) {
    gfio::create("update$FCCEXT",1);
    killserver("Restarting for updates")
  } else {
    my $file=shift @$UPDATEFILES;
    outfcc({ command => 'updatefile', file => $file });
    prout " > Update File $file ...\n";
  }
}

sub cfcc_mine {
  my ($client,$k) = @_;
  foreach my $leaf (keys %$LEAVES) {
    if ($LEAVES->{$leaf}{fcc}{function} eq 'miner') {
      outjson($LEAVES->{$leaf},$k)
    }
  }
}

sub cfcc_solerr {
  my ($client,$k) = @_;
  my $miner = shift @SOLMINER;
  if ($miner) {
    if ($miner->{fcc}{wrongcount}) {
      $miner->{fcc}{wrongcount}++;
      if ($miner->{fcc}{wrongcount}>=5) {
        killclient($miner,"Too many wrong solutions tried")
      }
    } else {
      $miner->{fcc}{wrongcount}=1
    }
    outjson($miner,{ command => 'wrong', message => "Illegal solution given" });
  }
}

sub cfcc_solution {
  my ($client,$k) = @_;
  my $miner = shift @SOLMINER;
  if ($miner) {
    $miner->{fcc}{wrongcount}=0;
    outjson($miner,{ command => 'solution' })
  }
}

sub signoutblockdata {
  my ($outblocks) = @_;
  my $sign="";
  foreach my $block (@$outblocks) {
    $sign.=$block->{wallet}.dechex($block->{amount},16).dechex($block->{fee},4);
    if ($block->{expire}) { $sign.=dechex($block->{expire},10) }
  }
  return $sign
}

sub addcoinbase {
  my ($data) = @_;
  foreach my $cb (@$COINBASELIST) {
    if ($cb->{signature} eq $data->{signature}) { return }
  }  
  push @$COINBASELIST,$data;
  if ($VOTING && ($VOTE->{transhash} eq $data->{signature})) {
    prout " *> Adding coinbase to translist";
    # we missed this one, catching up
    $TRANSLIST->{$data->{signature}}={ coinbase => 1, transhash => $data->{signature} }
  }
}

sub cfcc_feepayout {
  my ($client,$k) = @_;
  my $sign=dechex($k->{spare},8) . dechex($k->{blockheight},12);
  $sign.=signoutblockdata($k->{outblocks});
  if (Crypt::Ed25519::verify($sign,hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
    addcoinbase($k)
  }
}

sub cfcc_coinbase {
  my ($client,$k) = @_;
  prout " *> Coinbase received $k->{coincount}";
  my $sign=dechex($k->{coincount},8);
  $sign.=signoutblockdata($k->{outblocks});
  if (Crypt::Ed25519::verify($sign,hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
    addcoinbase($k)
  } else {
    prout " *> Coinbase Signature failed"
  }
}

sub cfcc_message {
  my ($client,$k) = @_;
  if ($k->{message}) {
    if (Crypt::Ed25519::verify($k->{message},hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
      prout "\n================== $COIN Message ====================\n\n$k->{message}\n";
      prout "\n=====================================================\n";
    }
  }  
}

sub cfcc_shutdown {
  my ($client,$k) = @_;
  if ($k->{message}) {
    if (Crypt::Ed25519::verify($k->{message},hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
      gfio::create("update$FCCEXT",1);
      prout "\n================== Shutting Down ====================\n\n$k->{message}\n";
      prout "\n=====================================================\n";
      killserver("$COIN Reset requested");
    }
  }
}

sub cfcc_reset {
  my ($client,$k) = @_;
  if ($k->{message}) {
    if (Crypt::Ed25519::verify($k->{message},hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
      gfio::create("update$FCCEXT",1);
      prout "\n================= Resetting databases ===============\n\n$k->{message}\n";
      prout "\n=====================================================\n";
      FCC::fcc::killdb();
      killserver("$COIN Database Update requested");
    }
  }  
}

sub cfcc_resetip {
  my ($client,$k) = @_;
  if ($k->{mask} eq $SERVER->{fcc}{mask}) {
    if ($k->{message}) {
      if (Crypt::Ed25519::verify($k->{message},hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
        gfio::create("update$FCCEXT",1);
        killserver("$COIN Restart requested");
      }
    }
  }  
}

sub cfcc_hardreset {
  my ($client,$k) = @_;
  if ($k->{message}) {
    if (Crypt::Ed25519::verify($k->{message},hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
      gfio::create("update$FCCEXT",1);
      prout "\n================= Resetting Ledger ===============\n\n$k->{message}\n";
      prout "\n=====================================================\n";
      FCC::fcc::killdb();
      unlink("ledger$FCCEXT");
      killserver("$COIN Hard Restart requested");
    }
  }  
}

################# Node handling ##########################

sub goactive {
  outfcc({ 
    command=>'init',
    wallet=>$WALLET->{wallet},
    port=>$SERVER->{server}{port},
    cumhash=>$LASTBLOCK->{tcum},
    blockheight=>$LASTBLOCK->{num},
    ledgerlength=>$LEDGERLEN,
    version=>$FCCVERSION
  });
  $FCCINIT |= 32767;
}

sub statusmsg {
  if (time ne $STATUSTIME) {
   $STATUSTIME=time;
   my $inf=connectinfo();
   my $nparents=(1+$#{$inf->{parents}});
   my $nnodes=(1+$#{$inf->{nodes}});
   my $nleaves=(1+$#{$inf->{leaves}});
   my $nminers=(1+$#{$inf->{miners}});
   my $nunknowns=(1+$#{$inf->{unknowns}});
   my $ntrans=(1+$#{[keys %$TRANSLIST]});
   my $vote='X'; if ($VOTING) { $vote=$VOTE->{round} }
   print STDOUT prtm(),
     ($nparents ? "Par=$nparents ":"").
     ($nnodes ? "Chld=$nnodes ":"").
     ($nleaves ? "Lvs=$nleaves ":"").
     ($nminers ? "Min=$nminers ":"").
     ($nunknowns ? "U=$nunknowns ":"").
     "Pnd=$ntrans Vote=$vote Ldg=$LEDGERLEN     \r"
  }
}

sub serverloop {
  # The FCC Node Control Kernel
  if (!$SERVER) { die "Lost $COIN Server Handle" }
  my $ctm=gettimeofday();
  # parents are a bit different, since we are in non-loopmode for each client, where the server is in loopmode for each of it's clients
  if ($SHUTDOWNMODE) {
    my @tl=keys (%$TRANSLIST);
    if (!$VOTING && ($#tl<0) && !$TRANSDIST && ($#{$TRANSDISTLIST}<0)) {
      killserver("Shutting down for core-update .. $COIN Towards a brighter future!");
    }
  }
  statusmsg();
  my @nodes=(keys %$PARENTLIST); my $done=0;
  if ($#nodes >= 0) {
    if ($PARENTLOOP > $#nodes) { $PARENTLOOP=0 }
    my $start=$PARENTLOOP;
    do {
      my $node=$PARENTLIST->{$nodes[$start]};
      if ($node->{handle}) {
        $SERVERNODE=$node->{handle};
        $SERVERNODE->takeloop();
        $SERVERNODE=undef;
        $done=1
      } elsif (!$node->{connected} && ($#nodes<$MAXPARENTS-1)) {
        if ($node->{lastconnect} && ($ctm-$node->{lastconnect}>=10)) {
          prout "   - Retrying $node->{mask} .. "
        } else {
          prout "   - Connecting to $node->{mask} .. "
        }
        addparent($nodes[$start]); $done=1
      } elsif ($node->{connected} && !$node->{fcc}{identified} && ($node->{lastconnect} && ($ctm-$node->{lastconnect}>=10))) {
        killclient($node->{handle},"408 Request TimeOut");
        prout "   x TimeOut $node->{mask} (no identify)\n"
      }
      $start++; if ($start>$#nodes) { $start=0 }
    } until ($done || ($start==$PARENTLOOP));
    $PARENTLOOP=$start
  }
  $CYCLELOOP++; my @ndl=keys %$NODES;
  if ($CYCLELOOP>=(1 + $#nodes)+(1 + $#ndl)) {
    $CYCLELOOP=0;
    if ($VOTING) { analysevotes() }
  }
  # check unknown timed-out clients
  $SERVER->broadcastfunc(\&checkhellotimeout,$ctm);
  # client jobs - one at a a time in the global loop to make it more fluent in execution
  my @leaves=(sort keys %$LEAVES);
  if ($#leaves >= 0) {
    if ($LEAFLOOP > $#leaves) { $LEAFLOOP=0 }
    my $client=$LEAVES->{$leaves[$LEAFLOOP]};
    $SERVERLEAF=$client;
    checkleafjob($client,$ctm);
    $SERVERLEAF=undef;
    $LEAFLOOP++
  }
  # transaction distribution
  if ($TRANSDIST) {
    my $fnd=0; my $nodes=corelist();
    my $th=substr($TRANSDISTDATA,-64);
    foreach my $node (@$nodes) {
      if (!$TRANSDISTDONE->{$node->{mask}.$th}) {
        outjson($node,{ command => 'transaction', data => $TRANSDISTDATA });
        $TRANSDISTDONE->{$node->{mask}.$th}=1;
        $fnd=1; last
      }
    }
    if (!$fnd) {
      $TRANSDIST=0; $TRANSLIST->{$th}{tobs}=0;
      foreach my $node (@$nodes) {
        delete $TRANSDISTDONE->{$node->{mask}.$th}
      }
    }
  } else {
    my @list=keys %$TRANSLIST;
    if (!$VOTING && (($#list>=0) || ($#{$COINBASELIST}>=0))) {
      if ($CYCLELOOP == 0) {
        votesuggest()
      }
    }
    if ($#{$TRANSDISTLIST}>=0) {
      $TRANSDISTDATA=shift @$TRANSDISTLIST; $TRANSDIST=1
    }
  }
  # fcc-server loop
  if ($FCCRECONNECT->{sec}>0) {
    if (time-$FCCRECONNECT->{time}>=10) {
      my $res=fccconnect($SERVER->{fcc}{localmode});
      if ($res) {
        $FCCRECONNECT->{sec}=0;
        if (minerspresent() && $FCCHANDSHAKE) {
          outfcc({ command => 'challenge' })
        }
      } else {
        $FCCRECONNECT->{time}=time+10
      }
    }
  } elsif ($FCCHANDLE) {
    $FCCHANDLE->takeloop();
  }
  # maintenance
  if ($ctm-$LASTCLIENTRUN>0.01) {
    # FCC-Server initisaling sequence
    # Initialise our node, connect to nodes, sync ledger
    if ($FCCINIT == 65535) {
      $LASTCLIENTRUN=$ctm; return
    } elsif ($FCCINIT == 0) {
      prout " * Loading and verifying the ledger .. ";
      load(); prout " * Ledger verified OK!\n";
      $LASTBLOCK=readlastblock(); $LEDGERLEN=0;
      if ($LASTBLOCK->{prev}) { $LEDGERLEN=$LASTBLOCK->{pos}+$LASTBLOCK->{next}+4 }
      $FCCINIT=1
    } elsif ($FCCINIT == 1) {
      fccconnect($SERVER->{fcc}{localmode});
      $FCCINIT=2;
    } elsif ($FCCINIT == 2) {
      if ($FCCHANDLE) { $FCCHANDLE->takeloop() }
      if (time-$FCCRECONNECT->{time}>5) {
        prout " *!* ERROR: The $COIN\-Server seems to be offline ..\n";
        if (!-e "forward$FCCEXT") {
          prout " -> You have not done a port-forwarding check yet\n -> You cannot do this while the $COIN\-Server is offline\n -> Please try again later!";
          killserver("Portforwarding check impossible"); exit
        }
        $FCCRECONNECT->{time}=time+10;
        if (-e "nodelist$FCCEXT") {
          my @nodes=split(/\n/,gfio::content("nodelist$FCCEXT"));
          if ($#nodes >= 0) {
            prout " -> Retrieving nodes from stored nodelist ..\n";
            foreach my $node (@nodes) {
              addcandidate(split(/ /,$node))
            }
            $FCCINIT=31; return
          }
        }
        prout " -> I have no way to find any nodes .. try again later!\n";
        killserver("Missing nodelist"); exit
      }
    } elsif ($FCCINIT == 3) {
      if ($UPDATEMODE >= 1) {
        if ($UPDATEMODE == 1) {
          prout " * Checking for updates ..\n";
          outfcc({ command => 'updatelist' });
          $UPDATEMODE=2
        } elsif ($UPDATEMODE == 3) {
          if (-e "forward$FCCEXT") {
            $UPDATEMODE=0
          } else {
            # port forwarding check, need to be performed only once
            print " * Port forwarding check ..\n";
            outfcc({ command => 'callmeback', port => $SERVER->{fcc}{port} });
            $CALLBACKTIME = $ctm;
            $UPDATEMODE=4
          }
        } elsif ($UPDATEMODE == 4) {
          if ($ctm - $CALLBACKTIME >= 5) {
            portforwarding();
            killserver("Port forwarding disabled"); exit
          }
        }
      } else {
        prout " * Checking time and nodelist\n";
        outfcc({ command => 'fcctime' });
        outfcc({ command => 'nodelist' });
        $FCCINIT=7
      }
    } elsif ($FCCINIT == 31) {
      # do we have nodes to sync the ledger?
      my @nodes=keys %$PARENTLIST; my $num=1+$#nodes;
      if (!$num) {
        prout " * There are no active nodes in the pool\n";
        $FCCINIT=16383
      } else {
        prout " * Accumulating nodes from the pool of $num nodes .. \n";
        $FCCINIT=63; $TRYTIME=$ctm
      }
    } elsif ($FCCINIT == 63) {
      # enough connected nodes to sync ledger?
      my $connected=0; my $tried=0;
      my @nodes=keys %$PARENTLIST; my $total=1+$#nodes;
      foreach my $mask (@nodes) {
        my $node=$PARENTLIST->{$mask};
        if ($node->{identified}) { $connected++ }
        if ($node->{tried}) { $tried++ }
      }
      if (($connected>=10) || ($connected>=$total) || (($tried>=$total) && ($ctm-$TRYTIME>10))) {
        $FCCINIT=127
      }
    } elsif ($FCCINIT == 127) {
      # collect information about the ledger
      prout " * Syncing-process of the ledger data has started\n";      
      my @nodes=(keys %$PARENTLIST); $REQUESTED=0;
      foreach my $mask (@nodes) {
        my $node=$PARENTLIST->{$mask};
        if ($node->{identified}) {
          outjson($node->{handle},{ command => 'ledgerinfo' });
          $REQUESTED++
        }
      }
      prout " * Requested information from $REQUESTED nodes\n";
      $FCCINIT=255
    } elsif ($FCCINIT == 255) {
      # wait for ledgerinfo responses
      my @nodes=(keys %$PARENTLIST); my $total=0;
      foreach my $mask (@nodes) {
        my $node=$PARENTLIST->{$mask};
        if ($node->{ledgerlen}) { $total++ }
      }
      # parting nodes are handled in killclient, so every node should answer
      if ($total >= $REQUESTED) { $FCCINIT=511 } 
    } elsif ($FCCINIT == 511) {      
      my @responses=();
      my @nodes = sort { $PARENTLIST->{$b}{ledgerlen} <=> $PARENTLIST->{$a}{ledgerlen} } (keys %$PARENTLIST);
      foreach my $mask (@nodes) {
        my $node=$PARENTLIST->{$mask};
        if ($node->{ledgerlen}) {
          push @responses,$node->{ledgerlen}
        }
      }
      my $num=1+$#responses;
      if ($INFOMODE) {
        if ($INFOMODE == 1) {
          prout " * INFORMATION MODE - Getting information from $num nodes.. ";
          $INFOTIME=$ctm; $INFOMODE=2
        } elsif ($INFOMODE == 2) {
          if ($ctm - $INFOTIME > 5) {
            my @nodes = sort { $PARENTLIST->{$b}{ledgerlen} <=> $PARENTLIST->{$a}{ledgerlen} } (keys %$PARENTLIST);
            if ($#nodes < 0) {
              prout " !*! No nodes connected !";
              killserver("InfoMode completed");
              exit
            }
            my $cnt=1;
            foreach my $mask (@nodes) {
              my $node=$PARENTLIST->{$mask};
              prout(rsp($cnt,2).". ".rsp($node->{host},15)." ".rsp($node->{port},5)." ".rsp($node->{ledgerlen},12)." ".rsp($node->{blockheight},8)." ".substr($node->{lastcum},0,26));
              if ($cnt==1) { $INFOLL=$node->{ledgerlen}; $INFONODE=$node->{handle} }
              $cnt++
            }
            if ($INFODOWNLOAD) {
              $INFOMODE=3; $INFOPOS=0; gfio::create("ledger.download$FCCEXT","");
            } else {
              killserver("InfoMode completed");
              exit              
            }
          }
        } elsif ($INFOMODE == 3) {
          if (!$INFOREAD) {
            if ($INFOPOS>=$INFOLL) {
              prout " * Done reading ledger.download$FCCEXT - $INFOLL bytes";
              killserver("InfoMode completed");
              exit
            }
            my $len=32768; if ($INFOLL<$INFOPOS+$len) { $len=$INFOLL-$INFOPOS }
            prout " -> Reading $INFOPOS - $len";
            $INFOREAD=1;
            outjson($INFONODE,{ command => 'reqledger', pos => $INFOPOS, length => $len })
          }
        }
        return
      }
      prout " * Evaluating responses from $num nodes .. ";
      if (!$num) { 
        prout " * No nodes responded. Going into single-core-mode.";
        $FCCINIT=16383; return
      }
      if ($#nodes < 0) { 
        prout " * Nodes that were present has quit during connection-phase\n * Going into single-core-mode.";
        $FCCINIT=16383; return
      }
      $LEDGERWANTED=$PARENTLIST->{$nodes[0]}{ledgerlen};
      my $todo=$LEDGERWANTED-$LEDGERLEN;
      if ($todo < 0) {
        prout " * Our ledger is ahead, no syncing necessary\n";
        $FCCINIT=16383
      } elsif ($todo == 0) {
        prout " * Ledger is perfectly synced\n";
        $FCCINIT=16383
      } else {
        prout " * Syncing $todo bytes\n";
        $FCCINIT=1023
      }
    } elsif ($FCCINIT == 1023) {
      # get ledgerdata
      if (!$SYNCING) {
        $SYNCPOS=$LEDGERLEN; $FIRSTSYNC=1; $SYNCING=1
      }
      syncledger();
    } elsif ($FCCINIT == 16383) {
      goactive();
    }
    $LASTCLIENTRUN=$ctm
  }
}

sub checkhellotimeout {
  my ($client,$ctm) = @_;
  if (!$client->{fcc}{identified}) {
    if ($ctm-$client->{fcc}{hellotime}>=5) {
      killclient($client,"Please identify yourself");
      firewall($client->{ip})
    }
  }
}

sub checkleafjob {
  my ($client,$ctm) = @_;
  if (!$client || !$client->{fcc} || !$client->{fcc}{identified}) { return }
  if ($#{$client->{fcc}{jobs}} >= 0) {
    my $job=shift @{$client->{fcc}{jobs}};
    if ($job->{command} eq 'balance') {
      outjson($client,{ command => $job->{command}, wallet => $job->{wallet}, balance => saldo($job->{wallet}) })
    } elsif ($job->{command} eq 'newtransaction') {
      my $wallet=createwalletaddress($job->{pubkey});
      my ($blocks,$change)=collectspendblocks($wallet,$job->{amount},transinblocks($wallet));
      if ($#{$blocks}<0) {
        outjson($client,{ command => 'newtransaction', transid=>$job->{transid}, error => "Insufficient funds" })
      } elsif ($#{$blocks}>255) {
        outjson($client,{ command => 'newtransaction', transid=>$job->{transid}, error => "Too many funds needed to make this transactions. Please split up into smaller amounts" })
      } else {
        if (!$job->{changewallet}) { $job->{changewallet}=$wallet }
        $job->{outsign}.=$job->{changewallet}.dechex($change,16).'0000';
        my $iblocks=inblocklist($blocks);
        my $sign=join('',@$iblocks).$job->{outsign};
        my $fcctime=newtrans($client,$job->{transid},$wallet,$job->{pubkey},$sign,$job->{numout});
        outjson($client,{ command=>'newtransaction', transid=>$job->{transid}, sign=>$sign, fcctime=>$fcctime })
      }
    }
  }
}

sub getsyncpos {
  my $pos=$SYNCPOS; my $opos=$pos;
  do {
    $opos=$pos;
    foreach my $slot (keys %$SYNC) {
      if ($SYNC->{$slot}{pos} == $pos) {
        $pos+=$SYNC->{$slot}{length}
      }
    }
    while ($SYNCBUF->{$pos}) {
      $pos+=length($SYNCBUF->{$pos})
    }
  } until ($pos == $opos);
  return $pos
}

sub syncledger {
  my @nodes = sort { $PARENTLIST->{$b}{ledgerlen} <=> $PARENTLIST->{$a}{ledgerlen} } (keys %$PARENTLIST);
  if ($#nodes < 0) {
    prout " *!* No nodes left to sync with .. advisable to delete ledger, and restart"; killserver("Error syncing"); exit
  }
  foreach my $slot (keys %$SYNC) {
    $SYNC->{$slot}{ok}=0
  }
  while ($SYNCBUF->{$SYNCPOS}) {
    if (ledgerdata($SYNCBUF->{$SYNCPOS})) {
      my $len=length($SYNCBUF->{$SYNCPOS});
      delete $SYNCBUF->{$SYNCPOS};
      $SYNCSTORED--;
      $SYNCPOS+=$len
    } else {
      delete $SYNCBUF->{$SYNCPOS};
      $SYNCSTORED--;
      $SYNCPOS=-s "ledger$FCCEXT";
      $FIRSTSYNC=1
    }
  }
  my $tm=gettimeofday();
  foreach my $mask (@nodes) {
    my $node=$PARENTLIST->{$mask};
    if ($node->{identified} && (!$SYNC->{$mask} || !$SYNC->{$mask}{busy})) {
      if ($LEDGERWANTED <= $node->{ledgerlen}) {
        my $len=32768; my $pos=getsyncpos();
        if ($pos + $len >= $LEDGERWANTED) { $len=$LEDGERWANTED - $pos }
        if ($len > 0) {
          $SYNC->{$mask}={
            ok => 1,
            node => $node,
            busy => 1,
            ready => 0,
            pos => $pos,
            length => $len,
            data => "",
            time => $tm,
            first => $FIRSTSYNC
          };
          $FIRSTSYNC=0;
          outjson($node->{handle},{ command => 'reqledger', pos => $pos, length => $len });
        }
      } else {
        # node catched up yet?
        if (!$SYNC->{$mask}{busy}) {
          outjson($node->{handle},{ command => 'ledgerinfo' });
          $SYNC->{$mask}{busy}=1
        }
      }
    } elsif ($SYNC->{$mask}{ready}) {
      if ($SYNC->{$mask}{pos} == $SYNCPOS) {
        if (!ledgerdata($SYNC->{$mask}{data},$SYNC->{$mask}{first})) {
          prout " * Node $mask sent illegal ledger data";
          killclient($node->{client},"Desynced on syncing");
          $SYNC->{$mask}{ok}=0;
          $SYNCPOS=-s "ledger$FCCEXT";
          $FIRSTSYNC=1
        } else {
          $SYNCPOS+=$SYNC->{$mask}{length};
          $SYNC->{$mask}{busy}=0;
          $SYNC->{$mask}{pos}=0;
          $SYNC->{$mask}{ok}=1;
        }
        $SYNC->{$mask}{ready}=0;
        if ($SYNCPOS == $LEDGERWANTED) {
          prout " * Finished syncing";
          $LASTBLOCK=readlastblock(); $LEDGERLEN=$LASTBLOCK->{pos}+$LASTBLOCK->{next}+4;
          $FCCINIT=16383; $SYNC={}; $SYNCBUF={};
          save()
        }
      } else {
        # memory buffer, limited to 128Mb (= 4096 blocks of 32Kb)
        if ($SYNCSTORED < 4096) {
          $SYNCBUF->{$SYNC->{$mask}{pos}}=$SYNC->{$mask}{data};
          $SYNCSTORED++;
          $SYNC->{$mask}{ready}=0;
          $SYNC->{$mask}{busy}=0;
          $SYNC->{$mask}{pos}=0;
          $SYNC->{$mask}{ok}=1;
        }
      }
    } elsif ($SYNC->{$mask}{busy}) {
      $SYNC->{$mask}{ok}=1;
      if ($tm - $SYNC->{$mask}{time} >= 3) {
        $SYNC->{$mask}{ok}=0
      }
    }
  }
  foreach my $slot (keys %$SYNC) {
    if (!$SYNC->{$slot}{ok}) { delete $SYNC->{$slot} }
  }
}

sub prin {
  my ($func,$command,$data) = @_;
  my $out = "SERV <IN ($func): $command - ";
  $EVALMODE=1;
  my $msg; eval { $msg=decode_json($data) };
  $EVALMODE=0;
  if ($@) { prout $out.$data."\n"; return }
  if (ref($msg) eq 'HASH') {
    my @out=();
    foreach my $k (sort keys %$msg) {
      my $v=$msg->{$k};
      if (ref($v) eq 'HASH') {
        push @out,"$k={".join(", ",sort (keys %$v))."}"
      } elsif (ref($v) eq 'ARRAY') {
        my $num=$#{$v};
        push @out,"$k=ARRAY[$num]"
      } elsif (defined($v)) {
        if (length($v)>500) { $v=substr($v,0,500)." ..." }
        push @out,"$k=$v"
      } else {
        push @out,"$k=[undef]"
      }
    }
    prout $out,join(", ",@out),"\n"
  } else {
    prout $out,"$data\n"
  }
}

sub handleserver {
  # Incoming message from a client we serve to
  my ($client,$command,$data) = @_;
  if ($client->{killed}) { return }
  if ($command eq 'init') {
    prout "Init $client->{ip}\n";
    if (!$CLIENTIP->{$client->{ip}}) {
      $CLIENTIP->{$client->{ip}}=1;
    } else {
      $CLIENTIP->{$client->{ip}}++;
      if ($CLIENTIP->{$client->{ip}} > 5) {
        killclient($client,"Maximum connections on this IP exceeded");
        return
      }
    }
  }
  elsif ($command eq 'sent') {
    $DATASENT+=$data; return
  } elsif ($command eq 'received') {
    $DATARECEIVED+=$data; return
  } elsif ($command eq 'connect') {    
    $client->{ischild}=1;
    $client->{mask}=$client->{ip}.":????";
    my $ctm=gettimeofday();
    $client->{fcc} = { function => 'unknown', faults => 0, identified => 0, hellotime => $ctm };
  }
  if ($DEBUG && ($command ne 'loop') && ($command ne 'noinput')) {
    if (!$data) { $data="" }
    my $func=$client->{fcc}{function};
    if (!$func) { $func='unknown client' }
    prin($func,$command,$data)
  }
  if ($command eq 'quit') {
    killclient($client,$data)
  } elsif ($command eq 'error') {
    killclient($client,$data)
  } elsif ($command eq 'handshake') {    
    if ($FCCINIT < 65535) {
      if (($FCCINIT == 3) && ($UPDATEMODE == 4)) {
        print " < Callback connection established\n";
      } else {
        prout "   x illegal connect $client->{ip}\n";
        killclient($client,'Trying to connect to non initialised node');
      }
    } else {
      prout "   + connected $client->{ip}\n";
      outjson($client,{ command => 'hello', version => $FCCVERSION, host=>$SERVER->{fcc}{host}, port=>$SERVER->{fcc}{port} });
    }
  } elsif ($command eq 'input') {
    $EVALMODE=1;
    my $k; eval { $k=decode_json($data) };
    $EVALMODE=0;
    if ($@) {
      prout "Illegal data received from $client->{ip}:$client->{port}: $data\n";
      killclient($client,$data); return
    }    
    my $cmd=$k->{command};
    if (!$cmd) {
      prout "Illegal data (no command in JSON) received from $client->{ip}:$client->{port}\n";
      killclient($client,$data); return
    }
    my $func="c_$cmd";
    if (defined &$func) {
      &$func($client,$k)
    } else {
      prout "Illegal JSON-command '$cmd' received from $client->{ip}:$client->{port}\n";
      outjson($client,{ command=>'error', error=>"Unknown command given in input" }); 
      fault($client)
    }
  }
}

sub handlenode {
  # Incoming message from a node we are client to
  my ($node,$cmd,$msg) = @_;
  if (!$node || $node->{error} || $node->{killed}) { return }
  if (!$msg) { $msg="" }
  my $mask=$node->{mask};
  if (!$mask) { $mask='unknown' }
  if ($DEBUG && ($cmd ne 'loop') && ($cmd ne 'noinput')) {
    prin('parent',$cmd,$msg)
  }
  if ($cmd eq 'connect') {
    $PARENTLIST->{$mask}{connected}=1
  } elsif ($cmd eq 'input') {
    if (!$msg) { return }
    $EVALMODE=1;
    my $k; eval { $k=decode_json($msg) };
    $EVALMODE=0;
    if ($@) {
      prout " !*! JSON error ($mask): $@\n";
      killclient($node,"JSON error: $@\n")
    }
    my $cmd=$k->{command};
    if (!$cmd) { return }
    my $proc="c_$cmd";
    if (defined &$proc) {
      &$proc($node,$k)
    } else {
      prout "Illegal command received from $mask: $cmd\n";
      fault($node)
    }
  } elsif ($cmd eq 'error') {
    prout "Lost connection to node $mask: $msg\n";
    killclient($node,$msg);
  } elsif ($cmd eq 'quit') {
    if ($FCCINIT == 255) { $REQUESTED-- }
    prout "Node $mask terminated: $msg\n";
    killclient($node,$msg);
  }
}

sub bcn {
  my ($client,$json) = @_;
  if ($client->{fcc} && ($client->{fcc}{function} eq 'node')) {
    wsmessage($client,$json)
  }
}

sub c_quit {
  my ($client) = @_;
  killclient($client)
}

sub c_error {
  my ($client,$k) = @_;
  killclient($client,$k->{message},1);
}

###################### handshake ##############################

sub c_hello {
  my ($client,$k) = @_;
  if (!$k->{build}) { $k->{build} = '1.01' }
  my $mask=join(':',$k->{host},$k->{port});
  if ($client->{ischild}) { 
    prout " !*! Rejected! Child-Node $client->{mask} tried to identify as a parent !*!\n";
    killclient($client,"Don't hack"); return
  }
  if ($client->{mask} ne $mask) {
    prout " !*! Rejected! Parent-Node $client->{mask} tried to identify as $mask !*!\n";
    killclient($client,"Don't hack"); return
  }
  if ($DEBUG) {
    prout "Response from node $client->{mask} -> Identify as node\n";
  }
  if ($k->{version} gt $FCCVERSION) {
    prout "! Node $client->{mask} has version $k->{version}, we only have version $FCCVERSION";
    killclient($client,"Version $k->{version} is not supported by this node");
    return    
  }
  $client->{fcc}{port}=$k->{port};
  $client->{mask}=$mask;
  if (!$PARENTLIST->{$client->{mask}}) {
    prout "! The port the node gave us is unknown in the core-list";
    killclient($client,"The port the node gave us is unknown in the core-list");
    return
  }
  $client->{fcc}{version}=$k->{version};
  $client->{fcc}{build}=$k->{build};
  $client->{fcc}{entrytime} = time+$FCCTIME;
  my $send= {
    command => 'identify',
    type => 'node',
    version => $FCCVERSION,
    build => $FCCBUILD,
    host => $SERVER->{fcc}{host},
    port => $SERVER->{fcc}{port}
  };
  $client->{fcc}{function}='node';
  $client->{fcc}{identified}=1;
  $PARENTLIST->{$client->{mask}}{identified}=1;
  addnodelist($client->{host},$client->{fcc}{port});
  outjson($client,$send);
  if ($FCCINIT == 65535) {
    outjson($client,{ command => 'ready' });
  }
  $client->outburst();
}

sub c_callback {
  my ($client,$k) = @_;
  if (Crypt::Ed25519::verify($SERVER->{fcc}{host}.'callback',hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
    prout " * Callback received !! Your portforwarding is active !!";
    gfio::create("forward$FCCEXT",1);
    $UPDATEMODE=0;
    killclient($client,"Succesful callback")
  } else {
    killclient($client,"Illegal callback")
  }
}

sub c_identify {
  my ($client,$k) = @_;
  if (!$k->{build}) { $k->{build} = '1.01' }
  if ($SHUTDOWNMODE) { killclient($client,"Service temporarely unavailable"); return }
  if ($k->{type} eq 'node') {
    my $mask=join(':',$k->{host},$k->{port});
    $client->{mask}=join(':',$client->{ip},$k->{port});
    if ($client->{mask} ne $mask) {
      prout " !*! Rejected! Child-Node $client->{mask} tried to identify as $mask !*!\n";
      killclient($client,"Don't hack"); return
    }
  } elsif ($client->{isparent}) {
    prout " !*! Rejected! Parent-Node $client->{mask} tried to identify as a child !*!\n";
    killclient($client,"Don't hack"); return
  } else {
    $client->{mask}=join(':',$client->{ip},"[".$client->{port}."]");
    $client->{fcc}{jobs}=[];
    $LEAVES->{$client->{mask}}=$client
  }
  $client->{fcc}{identified}=1;
  $client->{fcc}{function}=$k->{type};
  $client->{fcc}{version}=$k->{version};
  $client->{fcc}{build}=$k->{build};
  if ($k->{type} eq 'node') {
    $client->{fcc}{port}=$k->{port};
    if (!checklanwan($client->{ip})) {
      killclient($client,"LAN/WAN Intrucion"); return
    }
    $NODES->{$client->{mask}}=$client;
  }
  if ($k->{version} gt $FCCVERSION) {
    # assume backwards-compatiblity
    prout " !*! Client $client->{mask} is running version $k->{version}. We only $FCCVERSION!\n";
    killclient($client,"Version $k->{version} is not supported by this node");
    return
  }
  if ($k->{type} eq 'miner') {
    outfcc({ command => 'challenge' }) 
  }
  $client->{fcc}{version}=$k->{version};
  prout "Client $client->{mask} is a $k->{type} v$k->{build} ($k->{version})\n";
}

sub c_ready {
  my ($client) = @_;
  if (!$client->{fcc} || !$client->{fcc}{port} || ($client->{fcc}{function} ne 'node')) { killclient($client,"H4x0rz"); return }
  prout " *> Node $client->{ip}:$client->{port} is identified";
  $client->{fcc}{ready}=1;
}

sub c_transaction {
  my ($client,$k) = @_;
  if ($FCCINIT < 65535) { return }
  if (!$k->{data} || !$client->{fcc} || !$client->{fcc}{port} || ($client->{fcc}{function} ne 'node')) { killclient($client,"H4x0rz"); return }
  if (!$client->{fcc}{isparent} && !$client->{fcc}{ready}) { killclient($client,"H4x0rz"); return }
  # here we check for illegal voting
  my $trans=addtransaction($client,$k->{data});  
  if (!$trans->{nocheck}) {
    if ($trans->{error}) {
      prout (" !* Illegal transaction received from $client->{mask} - $trans->{error}");
      if ($VOTE->{transhash} eq $trans->{transhash}) {
        $VOTE->{illegal}=1
      }
    }
  }
}

sub c_coinbasetrans {
  my ($client,$k) = @_;
  if ($FCCINIT < 65535) { return }
  $k=$k->{data};
  if (!$k || !$k->{coincount} || !$k->{outblocks} || !$k->{signature}) {
    fault($client);
    prout " !*! Illegal coinbase $client->{ip}:$client->{port}"; return
  }
  my $sign=dechex($k->{coincount},8);
  $sign.=signoutblockdata($k->{outblocks});
  if (Crypt::Ed25519::verify($sign,hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
    addcoinbase($k);
    $TRANSLIST->{$k->{signature}}={ coinbase => 1, transhash => $k->{signature} }
  }
}

##################### mining ######################################

sub c_solution {
  my ($client,$k) = @_;
  push @SOLMINER,$client;
  outfcc({ command => 'solution', wallet => $k->{wallet}, solhash => $k->{solhash} })
}

####################### Sync Ledger ############################################

sub c_reqtrans {
  my ($client,$k) = @_;
  if ($FCCINIT < 65535) { return }
  if ($TRANSLIST->{$k->{transhash}}) {
    if (length($k->{transhash}) == 128) {
      # coinbase request
      foreach my $cb (@$COINBASELIST) {
        if ($cb->{signature} eq $k->{transhash}) {
          outjson($client, { command => 'coinbasetrans', data => $cb }); return
        }
      }
    }
    outjson($client,{ command => 'transaction', data => $TRANSLIST->{$k->{transhash}}{data} })
  }
}

sub c_ledgerinfo {
  my ($client,$k) = @_;
  if ($FCCINIT<255) { return }
  outjson($client,{ command=>'ledgerresponse', size=>$LEDGERLEN, height=>$LASTBLOCK->{num}, cumhash=>$LASTBLOCK->{tcum} })
}

sub c_ledgerresponse {
  my ($client,$k) = @_;
  if ($client->{ischild}) { return }
  my $node=$PARENTLIST->{$client->{mask}};
  $node->{ledgerlen}=$k->{size};
  $node->{lastcum}=$k->{cumhash};
  $node->{blockheight}=$k->{height};
  if ($SYNC->{$client->{mask}}) {
    $SYNC->{$client->{mask}}{busy}=0
  }
}

sub c_reqledger {
  my ($client,$k) = @_;
  if ($FCCINIT < 65535) { return }
  if ($k->{pos}+$k->{length}>$LEDGERLEN) {
    fault($client); return
  }
  my $sz=-s "ledger$FCCEXT";
  if ($sz<$k->{pos}+$k->{length}) {
    outjson($client,{ command => 'ledgerdata', error => 'Cannot supply block', pos => $k->{pos}, data => "", final => $k->{final} || 0, first => $k->{first} || 0 })
  } else {
    my $data=zb64(gfio::content("ledger$FCCEXT",$k->{pos},$k->{length}));
    outjson($client,{ command => "ledgerdata", pos => $k->{pos}, data => $data, final => $k->{final} || 0, first => $k->{first} || 0 })
  }
}

sub c_ledgerdata {
  my ($client,$k) = @_;
  if ($k->{error}) {
    killclient($client,"Desynced ($k->{error})"); return
  }
  $k->{data}=b64z($k->{data});
  if ($INFOMODE) {
    gfio::append("ledger.download$FCCEXT",$k->{data});
    $INFOREAD=0; $INFOPOS+=32768;
    return
  }
  if ($SYNC->{$client->{mask}}) {
    $SYNC->{$client->{mask}}{ready}=1;
    $SYNC->{$client->{mask}}{data}=$k->{data};
  } elsif (!ledgerdata($k->{data},$k->{first})) {
    prout " *> Node $client->{ip}:$client->{port} sent illegal ledgerdata";
    killclient($client,"Desynced")
  }
  $LASTBLOCK=readlastblock(); $LEDGERLEN=$LASTBLOCK->{pos}+$LASTBLOCK->{next}+4;
}

##################### LEAF ##########################################

sub c_balance {
  my ($client,$k) = @_;
  my $error="";
  if ($SHUTDOWNMODE) { killclient($client,"Service temporarely unavailable"); return }
  if ($FCCINIT<65535) {
    $error="I'm not initialised yet"
  } elsif (!$client->{fcc} || !$client->{fcc}{identified}) {
    $error="You are not identified yet"
  } elsif (!$client->{fcc}{function} eq 'leaf') {
    $error="You are not connected as a leaf"
  } elsif (!validwallet($k->{wallet})) {
    $error="Invalid wallet given"
  } elsif ($#{$client->{fcc}{jobs}} >= 4) {
    $error="Too many requests"
  }
  if ($error) {
    outjson($client,{ command => 'balance', error => $error })
  } else {
    push @{$client->{fcc}{jobs}},{ command => 'balance', wallet => $k->{wallet} }
  }
}

sub c_history {
}

sub c_newtransaction {
  my ($client,$k) = @_;
  if ($SHUTDOWNMODE) { killclient($client,"Service temporarely unavailable"); return }
  my $error=""; my $amount=0; my $outsign="";
  if ($FCCINIT<65535) {
    $error="I'm not initialised yet"
  } elsif (!$k->{transid}) {
    $error="No transaction-identification given"
  } elsif ($TRESLIST->{$client->{mask}} && ($TRESLIST->{$client->{mask}}{$k->{transid}})) {
    $error="transaction-identification already exists"
  } elsif (!$k->{pubkey} || !validh64($k->{pubkey})) {
    $error="Invalid public key given"
  } elsif ($BLOCKLIST->{$k->{pubkey}}) {
    $error="You are banned from making transactions, bad scriptkiddo!"
  } elsif (!$client->{fcc} || !$client->{fcc}{identified}) {
    $error="You are not identified yet"
  } elsif ($client->{fcc}{function} ne 'leaf') {
    $error="You are not connected as a leaf"
  } elsif (!$k->{to} || (ref($k->{to}) ne 'ARRAY')) {
    $error="Invalid to-spend-list given"
  } elsif ($#{$k->{to}}>=255) {
    $error="Too many recipients in to-spend-list (max=255)"
  } elsif ($k->{changewallet} && !validwallet($k->{changewallet})) {
    $error="Invalid Change-wallet given"
  } else {
    foreach my $to (@{$k->{to}}) {
      if ((ref($to) ne 'HASH') || (!validwallet($to->{wallet})) || (!$to->{amount}) || ($to->{amount} =~ /[^0-9]/)) {
        $error="Invalid spend-block in to-spend-list"; last
      } elsif ((!$to->{fee}) || ($to->{fee} =~ /[^0-9]/) || ($to->{fee}<$MINIMUMFEE)) {
        if (!checkgenesis($k->{pubkey})) {
          $to->{fee}=$MINIMUMFEE
        } else {
          $to->{fee}=0
        }
      }
      my $afee=doggyfee($to->{amount},$to->{fee});
      $amount+=$to->{amount}+$afee;
      $outsign.=$to->{wallet}.dechex($to->{amount},16).dechex($to->{fee},4)
    }
  }
  if (!$amount && !$error) { $error="No orders given in to-spend-list" }
  if ($error) {
    outjson($client,{ command => 'newtransaction', transid => $k->{transid}, error => $error })
  } else {
    push @{$client->{fcc}{jobs}},{
      command => 'newtransaction',
      pubkey => $k->{pubkey},
      amount => $amount,
      transid => $k->{transid},
      changewallet => $k->{changewallet} || "",
      outsign => $outsign,
      numout => 2+$#{$k->{to}}
    }
  }
}

sub c_signtransaction {
  my ($client,$k) = @_;
  my $error=""; my $mask=$client->{mask}; my $hash="";
  if ($FCCINIT<65535) {
    $error="I'm not initialised yet"
  } elsif (!$client->{fcc} || !$client->{fcc}{identified}) {
    $error="You are not identified yet"
  } elsif (!$client->{fcc}{function} eq 'leaf') {
    $error="You are not connected as a leaf"
  } elsif (!$k->{signature} || ($k->{signature} =~ /[^0-9A-F]/) || (length($k->{signature}) != 128)) {
    $error="Illegal signature syntax"
  } elsif (!$k->{transid} || $k->{transid} =~ /[^0-9]/) {
    $k->{transid}='error';
    $error="Illegal transaction id"
  } elsif (!$TRESLIST->{$mask} || !$TRESLIST->{$mask}{$k->{transid}}) {
    $error="Transaction with id $k->{transid} is unknown"
  } else {
    my $trans=$TRESLIST->{$mask}{$k->{transid}};
    if (!Crypt::Ed25519::verify($trans->{signdata},hexoct($trans->{pubkey}),hexoct($k->{signature}))) {
      $error="Ed25519 Verification mismatch on signature"
    } else {
      # Broadcast transaction!
      my $data=dechex($trans->{fcctime},8).$trans->{pubkey}.dechex($trans->{numout},2).$trans->{signdata}.$k->{signature};
      $hash=securehash($data); $data.=$hash;
      #addtransaction($client,$data,1);
      my $trans=addtransaction($client,$data);
      if ($trans->{error}) { $error=$trans->{error} }
    }
    delete $TRESLIST->{$mask}{$k->{transid}}
  }
  if ($error) {
    outjson($client,{ command => 'signtransaction', transid => $k->{transid}, error => $error })
  } else {
    outjson($client,{ command => 'signtransaction', transid => $k->{transid}, transhash => $hash })
  }
}

############ voting response #######################

sub c_vote {
  my ($client,$k) = @_;
  # prout " *> Vote [$k->{round}] $client->{host}:$client->{port} ".substr($k->{transhash},0,20);
  if (!defined $k->{round} || ($k->{round} =~ /[^0-9]/)) { killclient($client,"Illegal voting round") }
  if (!defined $k->{transhash} || (($k->{transhash} !~ /^[0-9A-F]{64}$/) && ($k->{transhash} !~ /^[0-9A-F]{128}$/))) { killclient($client,"Illegal transhash in voting") }
  if (!$VOTING && ($k->{round} == 0)) {
    votesuggest($k->{transhash})
  }
  if (!$VOTE->{responses}[$k->{round}]) { 
    $VOTE->{responses}[$k->{round}] = {};
    $VOTE->{received}[$k->{round}] = 0;
  }
  $VOTE->{responses}[$k->{round}]{$client->{mask}}={ 
    node => $client, round => $k->{round}, transhash => $k->{transhash}, ledgerlen => $k->{ledgerlen},
    tcum => $k->{tcum}, illegal => $k->{illegal}, consensus => $k->{consensus} 
  };
  $VOTE->{received}[$k->{round}]++;
  # prout " *> Vote Noted [$k->{round}] $client->{host}:$client->{port} ".substr($k->{transhash},0,20)
}

############## Faults made by others ########################

sub fault {
  my ($client) = @_;
  $client->{fcc}{faults}++;
  if ($client->{fcc}{faults}>$MAXFAULTS) {
    outjson($client,{ command => 'error', error=>'Too many errors' });
    killclient($client)
  }
}

############### Transactions @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub newtrans {
  my ($client,$transid,$wallet,$pubkey,$sign,$numout) = @_;
  my $mask=$client->{mask}; my $ctm=time+$FCCTIME;
  if (!$TRESLIST->{$mask}) {
    $TRESLIST->{$mask}={}
  }
  $TRESLIST->{$mask}{$transid} = {
    transid => $transid, # needed when copied to translist
    wallet => $wallet,
    pubkey => $pubkey,
    signdata => $sign,
    fcctime => $ctm,
    numout => $numout
  };
  return $ctm
}

sub transexists {
  my ($transhash) = @_;
  foreach my $trans (@$TRANSLIST) {
    if ($trans->{transhash} eq $transhash) { return 1 }
  }
  return 0
}

sub addtransaction {
  my ($client,$data,$skipvalidate) = @_;
  my $trans=splittransdata($data);
  if ($trans->{error}) {
    prout " *! Transerror: $trans->{error}\n";
    fault($client); return $trans
  }
  $TRANSDISTDONE->{$client->{mask}.$trans->{transhash}}=1;
  if ($TRANSLIST->{$trans->{transhash}}) { $trans->{nocheck}=1; return $trans } # already present
  if ($TRANSLISTDONE->{$trans->{transhash}}) { $trans->{nocheck}=1; return $trans } # already done
  validateblock($trans);
  if ($trans->{error}) {
    prout " *! Transerror: $trans->{error}\n";
    fault($client); return $trans
  }
  checkinblocks($trans);
  if ($trans->{error}) {
    prout " *! Transerror: $trans->{error}\n";
    fault($client); return $trans
  }
  $trans->{status}=0;
  if ($client->{fcc}{function} eq 'leaf') {
    $trans->{client}=$client
  }
  $trans->{tobs}=1;
  prout " ++ Transaction $trans->{transhash} (fee = $trans->{fee})\n";
  $TRANSLIST->{$trans->{transhash}}=$trans;
  if ($TRANSCATCHUP->{$trans->{transhash}}) {
    # if not deleted, used as error-marker in voting round 1
    delete $TRANSCATCHUP->{$trans->{transhash}};
  } else {
    push @$TRANSDISTLIST,$data;
  }
  return $trans
}

sub checkinblocks {
  my ($trans) = @_;
  my %cib=(); foreach my $ib (@{$trans->{inblocks}}) { $cib{$ib}=1 }
  foreach my $t (keys %$TRANSLIST) {
    if ($TRANSLIST->{$t}{pubkey} && ($TRANSLIST->{$t}{pubkey} eq $trans->{pubkey})) {
      foreach my $ib (@{$TRANSLIST->{$t}{inblocks}}) {
        if ($cib{$ib}) {
          $trans->{error}="Double spending transaction flood detected";
          # We are under transaction-flood attack (like Verge was brought down april 2018)
          $BLOCKLIST->{$trans->{pubkey}}=time; return
        }
      }
    }
  }  
}

sub validateblock {
  my ($trans) = @_;
  if (!$trans->{amount}) { $trans->{error}="No amount given in transaction"; return }
  if ($#{$trans->{inblocks}}<0) { $trans->{error}="no inblocks"; return }
  if ($#{$trans->{outblocks}}<0) { $trans->{error}="No outblocks"; return }
  for (my $b=0; $b<=$#{$trans->{outblocks}}; $b++) {
    my $out=$trans->{outblocks}[$b];
    if (!validwallet($out->{wallet})) { $trans->{error}="Invalid wallet: $out->{wallet}"; return }
    if (($b<$#{$trans->{outblocks}}) || ($#{$trans->{outblocks}} == 0)) {
      if (!$out->{amount}) { $trans->{error}="No amount in send-block"; return }
      if ($out->{fee} < $MINIMUMFEE) { $trans->{error}="Illegal fee in send-block"; return }
    }
  }
  my ($inblocks,$change)=collectspendblocks($trans->{wallet},$trans->{amount}+$trans->{fee},transinblocks($trans->{wallet}));
  my $iblist=inblocklist($inblocks);
  if ($#{$iblist} != $#{$trans->{inblocks}}) { $trans->{error}="Not the same number of inblocks"; return }
  for (my $i=0;$i<=$#{$iblist};$i++) {
    if ($iblist->[$i] ne $trans->{inblocks}[$i]) { $trans->{error}="Not the same sequence of inblocks"; return }
  }
  if (!Crypt::Ed25519::verify($trans->{sign},hexoct($trans->{pubkey}),hexoct($trans->{signature}))) { $trans->{error}="Ed25519 Signature failed to verify"; return }
}

sub splittransdata {
  my ($data) = @_;
  if (!$data) { return { error => 'no data in transaction data' } }
  if ((length($data)<416) || ($data =~ /[^0-9A-F]/)) { return { error => 'illegal transaction data' } }
  my $info = {
   error => 0,
   fcctime => hexdec(substr($data,0,8)),
   pubkey => substr($data,8,64),
   numout => hexdec(substr($data,72,2)),
   signature => substr($data,-192,128),
   transhash => substr($data,-64),
   sign => substr($data,74,-192),
   inblocks => [],
   outblocks => []
  };
  my $epk=('0'x64); if ($epk eq $info->{pubkey}) { return { error => "Zero pubkey, h4x0rz" } }
  $info->{wallet}=createwalletaddress($info->{pubkey});
  my $blen=length($info->{sign}); my $outpos=$blen-$info->{numout}*88;
  if ($outpos % 64 != 0) { return { error => "outpos ($outpos) not divisable by 64" } }
  if ($outpos <= 0) { return { error => "Money does not come from nothing" } }
  if (($outpos>>6) > 255) { return { error => "Too many data needed to make this transaction. Please split up into smaller amounts" } }
  my $bl=0; my $numin=$outpos >> 6; my $pi=0;
  while ($bl<$numin) {
    push @{$info->{inblocks}},substr($info->{sign},$pi,64);
    $pi+=64; $bl++
  }
  my $amount=0; my $fee=0; $bl=0;
  while ($bl<$info->{numout}) {
    my $a=hexdec(substr($info->{sign},$pi+68,16));
    my $f=hexdec(substr($info->{sign},$pi+84,4));
    if ($bl<$info->{numout}-1) {
      $amount+=$a; $fee+=doggyfee($a,$f)
    }
    push @{$info->{outblocks}},{
      type => 'out',
      wallet => substr($info->{sign},$pi,68),
      amount => $a,
      fee => $f
    };
    $pi+=88; $bl++
  }
  $info->{amount}=$amount;
  $info->{fee}=$fee;
  $info->{data}=$data;
  return $info
}

sub transinblocks {
  my ($wallet) = @_;
  my $blocks=[];
  foreach my $trans (keys %$TRANSLIST) {
    if ($TRANSLIST->{$trans}{wallet} && ($TRANSLIST->{$trans}{wallet} eq $wallet)) {
      push @$blocks,@{$TRANSLIST->{$trans}{inblocks}}
    }
  }
  return $blocks
}

############### Voting System ###################################

sub votesuggest {
  my ($activate) = @_;
  
  if ($VOTING) { return }
#  if ($ADDCOINBASE) { return }

  # auto garbage collection
  $TRANSCATCHUP={};

  my $trans; my $coinbase=0;
  if ($#{$COINBASELIST}>=0) {
    $coinbase=1; $trans=$COINBASELIST->[0]{signature};
    $TRANSLIST->{$trans}={ coinbase => 1, transhash => $trans }
  } elsif (!$activate || (length($activate) == 64)) {
    my @tlist=sort { ($TRANSLIST->{$b}{fee} <=> $TRANSLIST->{$a}{fee}) || ($TRANSLIST->{$a}{fcctime} <=> $TRANSLIST->{$b}{fcctime}) } keys %$TRANSLIST;
    foreach my $t (@tlist) {
      if (!$TRANSLIST->{$t}{tobs} && !$TRANSLISTDONE->{$t}) {
        $trans=$t; last
      }
    }
  }

  my $tr=$trans || $activate;
  if (!$tr) { return }
#  prout "********** Votesuggest = $tr\n";

  my $nodelist=corelist();
  my $tm=gettimeofday();
  if ($trans) {
    # we found a transaction to suggest to the core (first voting round)
    $VOTE={
      round => 0,
      transhash => $trans,
      coinbase => $coinbase,
      responses => [],
      total => 1+$#{$nodelist},
      received => [],
      consensus => 0,
      start => $tm,
      illegal => 0
    };
    $VOTE->{received}[0]=0;
    $VOTE->{responses}[0]={};
    if ($#{$nodelist}<0) {
      # we are the only node! God save the Mohacans
      transtoledger($TRANSLIST->{$trans})
    } else {
      $VOTING=1;
      outcorejson({ command => 'vote', transhash => $trans, round => 0, ledgerlen => $LEDGERLEN, tcum => $LASTBLOCK->{tcum}, coinbase => $TRANSLIST->{$trans}{coinbase} })
    }
  } elsif ($activate) {
    if (!$TRANSLISTDONE->{$activate}) {
      # TRANSLIST seems to be empty, but they are voting on something.. get it (in voting round 0) and vote along!
      my $tm=gettimeofday();
      $VOTE={
        round => 0,
        transhash => $activate,
        coinbase => $coinbase,
        responses => [],
        total => 1+$#{$nodelist},
        received => [],
        consensus => 0,
        start => $tm,
        illegal => 0
      };
      $VOTE->{received}[0]=0;
      $VOTE->{responses}[0]={};
      if ($#{$nodelist}<0) {
        # we are the only node! God save the Mohacans
        transtoledger($TRANSLIST->{$trans})
      } else {
        $VOTING=1;
        my $ot={ 
          command => 'vote',
          transhash => $activate,
          round => 0,
          ledgerlen => $LEDGERLEN,
          tcum => $LASTBLOCK->{tcum},
          coinbase => $coinbase,
          dbhash => getdbhash()
        };
        outcorejson($ot)
      }
    }
  }
  if ($VOTING) { prout " *> Voting system activated" } else { prout " *> Voting suggestion rejected" }
  $AVT=0
}

sub analysevotes {

  if (!$VOTING) { return }

  my $action=0; my $tm=gettimeofday();
  if (!$VOTE->{received}[$VOTE->{round}]) {
    $VOTE->{received}[$VOTE->{round}]=0;
    $VOTE->{responses}[$VOTE->{round}]={}
  }
  my $dtm=int (100*($tm-$VOTE->{start}))/100; 
  if ($dtm-$AVT>1) {
    my $rec=$VOTE->{received}[$VOTE->{round}];
    prout " *> VOTE [$VOTE->{round}] Received = $rec/$VOTE->{total} Time = $dtm";
    $AVT=$dtm
  }
  if (($VOTE->{received}[$VOTE->{round}] >= $VOTE->{total}) || ($tm-$VOTE->{start} >= 3)) {
    my @rplist=();
    foreach my $mask (keys %{$VOTE->{responses}[$VOTE->{round}]}) {
      my $rp=$VOTE->{responses}[$VOTE->{round}]{$mask}; push @rplist,$rp
    }
    my $nrp = 1 + $#rplist;
    # prout " *> Voting: Received = $VOTE->{received}[$VOTE->{round}] NRP = $nrp\n";
    if ($#rplist < 0) {
      # we are stalled ..
      if ($VOTE->{total}) {
        killserver(" !*! No votes received ($VOTE->{total} expected) !*!"); exit
      } else {
        # we're the only node left in the core (the other one just quit)
        transtoledger($TRANSLIST->{$VOTE->{transhash}})
      }
      return
    }

  ######### Round 0 - Checking ledger sync & catching missing and illegal transactions ################

    if ($VOTE->{round} == 0) {
      # syncing transaction round, necessary for checking illegal transactions (distributed flood attack)!
      # search largest ledgerlength (if garbage, kill node afterwards)
      my @sortll = sort { $b->{ledgerlen} <=> $a->{ledgerlen} } @rplist;
      my $llwanted = $sortll[0]{ledgerlen};
      if ($llwanted > $LEDGERLEN) {
        # Running behind
        if ($VOTE->{catchup} && ($tm-$VOTE->{start} < 2.3)) { return } # already syncing
        my $len=$llwanted-$LEDGERLEN; my $pos=$LEDGERLEN; my $first=1;
        prout " * Running $len bytes behind, catching up";
        while ($len>0) {
          # should be a small block .. but if transactions go very fast on a slow computer, we just keep syncing..
          my $sz=32768; my $final=0; if ($sz>=$len) { $sz=$len; $final=1 }
          outjson($sortll[0]{node},{ command => 'reqledger', pos => $pos, length => $sz, first=> $first, final => $final });
          $pos+=$sz; $len-=$sz; $first=0
        }
        $VOTE->{catchup}=1
      } elsif ($llwanted == $LEDGERLEN) {
        my $lch={};
        foreach my $rp (@rplist) {
          if ($rp->{tcum}) {
            if (!defined $lch->{$rp->{tcum}}) {
              $lch->{$rp->{tcum}}=1
            } else {
              $lch->{$rp->{tcum}}++
            }
          }
        }
        my @sch = sort { $lch->{$b} <=> $lch->{$a} } keys %$lch;
        if (($#sch>=0) && ($sch[0] ne $LASTBLOCK->{tcum})) {
          # Desynced !!!
          killserver("Unfortunately the ledger is desynced. Maybe the ledger should be deleted. Please restart the node."); exit
        } else {
          my $dbl={};
          foreach my $rp (@rplist) {
            if ($rp->{dbhash}) {
              if (!defined $lch->{$rp->{dbhash}}) {
                $dbl->{$rp->{dbhash}}=1
              } else {
                $dbl->{$rp->{dbhash}}++
              }
            }
          }
          my @sdl = sort { $dbl->{$b} <=> $dbl->{$a} } keys %$dbl;
          if (($#sdl>=0) && ($sdl[0] ne getdbhash())) {
            # Desynced !!!
            killdb();
            killserver("Unfortunately the databases are desynced. The databases are being rebuild after you restart the node."); exit
          } else {
            my $list={};
            foreach my $rp (@rplist) {
              $list->{$rp->{transhash}}++
            }
            my @slist = sort { $list->{$b} <=> $list->{$a} } keys %$list;
            my $n=1+$#slist;
            $VOTE->{transhash}=$slist[0];
            if (!$TRANSLIST->{$slist[0]} && !$VOTE->{illegal}) {
              if (!$TRANSCATCHUP->{$slist[0]}) {
                if ($tm - $VOTE->{start} >= 1) {
                  $TRANSCATCHUP->{$slist[0]}=1;
                  my $sent=0;
                  foreach my $rp (@rplist) {
                    if ($rp->{transhash} eq $slist[0]) {
                      outjson($rp->{node},{ command => 'reqtrans', transhash => $rp->{transhash} });
                      $sent++; if ($sent==3) { last }
                    }
                  }
                }
              } elsif ($VOTE->{illegal} || ($tm - $VOTE->{start} >= 3)) {
                # could not fetch transaction or illegal
                delvote(0); return
              }
            } else {
              $VOTE->{round}=1;
              $VOTE->{total}=1+$#rplist;
              $VOTE->{start}=$tm;
              foreach my $rp (@rplist) {
                outjson($rp->{node},{ command => 'vote', round => 1, transhash => $VOTE->{transhash}, illegal => $VOTE->{illegal} })
              }
            }
          }
        }
      }
      return
    }

  ########### Voting rounds #################

    my $list={}; my $vtot=0; my $illcnt=0;
    foreach my $rp (@rplist) {
      if ($rp->{illegal}) { $illcnt++ }
      my $q=1; if ($rp->{consensus}) { $q=$rp->{consensus} }
      $list->{$rp->{transhash}}+=$q; $vtot+=$q;
    }
    my @slist = sort { $list->{$b} <=> $list->{$a} } keys %$list;
    if ($#slist == 0) {
      # 100% consensus
      if ($TRANSLIST->{$slist[0]}) {
        # vote must be legal or would not be in translist
        # this is the perfect state, a perfectly synced core, even if we don't agree, then never mind
        transtoledger($TRANSLIST->{$slist[0]})
      } else {
        if ($VOTE->{illegal}) {
          if (!$illcnt) {
            prout " !*! The core approved a transaction we determined illegal !*!";
            killserver("Unexpected illegal transaction")
          }
          delvote(0)
        } else {
          # the core voted on a new unknown transaction!
          if (!$TRANSCATCHUP->{$slist[0]}) {
            if ($tm - $VOTE->{start} >= 1) {
              $TRANSCATCHUP->{$slist[0]}=1;
              my $sent=0;
              foreach my $rp (@rplist) {
                if ($rp->{transhash} eq $slist[0]) {
                  outjson($rp->{node},{ command => 'reqtrans', transhash => $rp->{transhash} });
                  $sent++; if ($sent==3) { last }
                }
              }
            }
          } elsif ($VOTE->{illegal} || ($tm - $VOTE->{start} >= 3)) {
            # could not fetch transaction or illegal
            delvote(0)
          }          
        }
      }
      return
    }
    # No consensus!
    $VOTE->{illegal}=0;
    $VOTE->{transhash}=$slist[0];
    if ($TRANSLIST->{$slist[0]}) {
      # switch vote to majority
      $VOTE->{consensus}=int (100 * $list->{$slist[0]} / $vtot);
      $VOTE->{round}++;
      $VOTE->{start}=$tm;
      foreach my $rp (@rplist) {
        outjson($rp->{node},{ command => 'vote', round => $VOTE->{round}, transhash => $VOTE->{transhash}, illegal => $VOTE->{illegal}, consensus => $VOTE->{consensus} })
      }
      return
    }
    if (!$TRANSCATCHUP->{$slist[0]}) {
      if ($tm - $VOTE->{start} >= 1) {
        $TRANSCATCHUP->{$slist[0]}=1;
        my $sent=0;
        foreach my $rp (@rplist) {
          if ($rp->{transhash} eq $slist[0]) {
            outjson($rp->{node},{ command => 'reqtrans', transhash => $rp->{transhash} });
            $sent++; if ($sent==3) { last }
          }
        }
      }
    } elsif ($VOTE->{illegal} || ($tm - $VOTE->{start} >= 3)) {
      # could not fetch transaction or illegal
      delvote(0)
    }          
  }
}

sub delvote {
  my ($success) = @_;
  if (length($VOTE->{transhash}) == 128) {
    for (my $i=0;$i<=$#{$COINBASELIST};$i++) {
      if ($COINBASELIST->[$i]{signature} eq $VOTE->{transhash}) {
        splice(@$COINBASELIST,$i,1); last
      }
    }
  } elsif (!$success) {
    my $trans=$TRANSLIST->{$VOTE->{transhash}};
    prout " %! Transaction rejected\n";
    if ($trans->{client}) {
      outjson($trans->{client},{ command => 'processed', transhash => $trans->{transhash}, error => "Rejected by the core" })
    }
  }
  $TRANSLISTDONE->{$VOTE->{transhash}}=1;
  delete $TRANSLIST->{$VOTE->{transhash}};
  $VOTING=0;
  $VOTE = {}
}

sub addcoinbasetoledger {
  my ($transhash) = @_;
  for (my $i=0;$i<=$#{$COINBASELIST};$i++) {
    if ($COINBASELIST->[$i]{signature} eq $transhash) {
      my $cb=$COINBASELIST->[$i];
      if ($cb->{blockheight}) {
        prout " % Feetransaction created\n";
        foreach my $out (@{$cb->{outblocks}}) {
          if ($out->{wallet} eq $WALLET->{wallet}) {
            prout "% We earned $COIN ".extdec($out->{amount}/100000000)." !\n"
          }
        }
        createfeetransaction($cb->{fcctime},$cb->{blockheight},$cb->{spare},$cb->{signature},$cb->{outblocks});
        return 1
      } else {
        prout " % Coinbase $cb->{coincount} created\n";
        if ($cb->{outblocks}[1]{wallet} eq $WALLET->{wallet}) {
          prout " % We've earned a bonus of $COIN ".extdec($MINEBONUS/100000000)." !\n"
        }
        createcoinbase($cb->{fcctime},$cb->{coincount},$cb->{signature},$cb->{outblocks});
        return 1
      }
    }
  }
  prout " *> Coinbase not found";
  return 0
}

sub transtoledger {
  my ($trans) = @_;
  if (length($trans->{transhash}) == 128) {
    if (!addcoinbasetoledger($trans->{transhash})) {
      # still waiting for the FCC-server
      prout " *> Failed to add coinbase to ledger";
      $ADDCOINBASE=$trans->{transhash}
    }
  } else {
    prout " % Transaction created (fee = ".extdec($trans->{fee}/100000000).")\n";
    createtransaction($trans->{fcctime},$trans->{pubkey},$trans->{signature},$trans->{inblocks},$trans->{outblocks});
    if ($trans->{client}) {
      outjson($trans->{client},{ command => 'processed', transhash => $trans->{transhash}, wallet => $trans->{wallet}, amount => $trans->{amount}, fee => $trans->{fee} })
    }
  }
  $LASTBLOCK=readlastblock(); $LEDGERLEN=$LASTBLOCK->{pos}+$LASTBLOCK->{next}+4;
  delvote(1)
}

sub portforwarding {
  if ($FCCRECONNECT->{sec} > 0) { return }
  if ($SERVER->{killed}) { return } # dirty
  my $CNT="FCC !!"; if ($COIN eq 'PTTP') { $CNT='PTTP !' }
  print <<EOT;

******************************************************************************
*                                                                            *
*     PORT FORWARDING                                                        *
*                                                                            *
*     Your node has not been properly initialised for Port-Forwarding.       *
*     This means that although you can reach a bi-directional connection     *
*     from within, nodes cannot reach you from without, establishing a       *
*     connection.                                                            *
*                                                                            *
*     To fix this you must enable port forwarding, just like in most         *
*     Internet-games, in your router.                                        *
*                                                                            *
*     The default port is  7050  which must point to your local IP,          *
*     e.g. 192.168.xxx.xxx or 10.0.0.x                                       *
*     To find this local IP you can use ipconfig or ifconfig                 *
*                                                                            *
*     If this is all too difficult for you, stick to your wallet !           *
*     You don't need a node to be able to use $CNT Only nerds do.          *
*                                                                            *
*     Good luck,                                                             *
*                                                                            *
*     Chaosje                                                                *
*                                                                            *
******************************************************************************

EOT
}

# I love it when a plan comes together :)

# EOF FCC/PTTP Node by Chaosje (C) 2018 Domero