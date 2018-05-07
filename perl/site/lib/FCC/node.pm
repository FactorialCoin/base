#!/usr/bin/perl

package FCC::node;

#######################################
#                                     #
#     FCC Node                        #
#                                     #
#    (C) 2017 Domero                  #
#                                     #
#######################################

use strict;
no strict 'refs';
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '2.01';
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw();

use POSIX;
use JSON;
use gerr;
use gfio 1.10;
use Digest::SHA qw(sha256_hex sha512_hex);
use Crypt::Ed25519;
use gserv 3.1.2 qw(prtm wsmessage);
use gclient 7.2.2;
use Time::HiRes qw(gettimeofday usleep);
use FCC::global;
use FCC::wallet 1.02;
use FCC::fcc;
use gparse;

my $DEBUG=0;

# some to become config
my $SERVER;              # gserv-handle of node-server
my $SERVERNODE;          # active node if parent
my $PARENTLOOP=0;
my $SERVERLEAF;          # active leaf
my $LEAFLOOP=0;
my $KILLED=0;
my $DATASENT=0;
my $EVALMODE=0;
my $DATARECEIVED=0;
my $LASTCLIENTRUN=0;
my $WALLET;
my $WALLETPASS;
my $FCCSERVER = [ $FCCSERVERIP, $FCCSERVERPORT ];
my $FCCSERVERLAN = [ '192.168.1.103', '5151' ]; # debug on LAN mode (localmode)
my $FCCHANDLE;           # gclient handle to the FCC-Server
my $FCCLOOPTIME=0;
my $CYCLELOOP=0;
my $FCCINIT=0;           # Initialisation state
my $FCCRECONNECT= { sec => 0, time => time };
my $FCCHANDSHAKE=0;
my $TRYTIME=0;
my $MAXNODES=500;        # max clients to our node
my $MAXPARENTS=500;
my $MAXFAULTS=3;
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
my $SYNCING=1;
my $LEDGERWANTED=0;
my $REQUESTED=0;
my $REQBLOCKPOS=0;
my $SYNCBLOCKS={};
my $SYNCERROR=0;
my $SYNCINIT=1;
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
my $MINER;

my $printed={};

$SIG{'INT'}=\&intquit;
$SIG{'TERM'}=\&termquit;
$SIG{'PIPE'}=\&sockquit;
$SIG{__DIE__}=\&fatal;
$SIG{__WARN__}=\&fatal;

1;

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
  print " * Connecting to FCC-SERVER ";
  if ($localmode) {
    print join(":",@$FCCSERVERLAN); print " .. ";
    $FCCHANDLE=gclient::websocket(@$FCCSERVERLAN,0,\&handlefccserver,0)
  } else {
    print join(":",@$FCCSERVER); print " .. ";
    $FCCHANDLE=gclient::websocket(@$FCCSERVER,0,\&handlefccserver,1)
  }
  if ($FCCHANDLE->{error}) {
    print "Failed! $FCCHANDLE->{error}\n"; return 0
  }
  $FCCHANDLE->{fcc}={ isparent=>1 };
  $FCCHANDLE->takeloop();
  print "OK!\n";
  return 1
}

sub newwall {
  print "Not found! Create wallet now? (Y/n) ";
  my $res=<STDIN>; chomp $res;
  if (substr(lc($res),0,1) eq 'n') { exit }
  $WALLET=newwallet();
  print "Encode wallet with password [ leave blank for none ]: ";
  $WALLETPASS=<STDIN>; chomp $WALLETPASS;
  savewallet($WALLET,$WALLETPASS)
}

sub start {
  my ($myport,$slavemode,$localmode,$fccserv) = @_;
  if ($fccserv) {
    if ($localmode) { $FCCSERVERLAN->[0]=$fccserv } else { $FCCSERVER->[1]=$fccserv }
  }
  if (-e "update.fcc"){ unlink("update.fcc") }
  my $vers=join('.',substr($FCCVERSION,0,2)>>0,substr($FCCVERSION,2,2));
  # in slavemode call $node->takeloop() while $node->{server}{running}
  # use localmode for testing on LAN
  print <<EOT;

  FFFF  CCC   CCC
  F    C     C          FULL NODE SERVER $vers
  FF   C     C            (C) 2018 Domero
  F     CCC   CCC

EOT
  print "Opening wallet .. ";
  if (!walletexists()) {
    newwall()
  } else {
    if (-e 'nodewallet.fcc') { 
      $WALLET=decode_json(gfio::content('nodewallet.fcc')) 
    } else {
      if (walletisencoded()) {
        print "\nEnter wallet password .. ";
        $WALLETPASS=<STDIN>; chomp $WALLETPASS;
        if (!validwalletpassword($WALLETPASS)) {
          print "Illegal password!\n"; exit
        }
      }
      my $wlist=loadwallets($WALLETPASS);
      if ($#{$wlist} < 0) {
        newwall()
      } elsif ($#{$wlist} == 0) {
        $WALLET=$wlist->[0]
      } else {
        print "\nChoose a wallet .. \n";
        my $num=0;
        foreach my $w (@$wlist) {
          $num++; print "$num\. ";
          if ($w->{name}) { print $w->{name}."\n   " }
          print $w->{wallet}."\n"
        }
        print "\n0. exit\n\nMake a choice .. ";
        my $ch=<STDIN>; chomp $ch;
        if (!$ch) { exit }
        if ($ch =~ /[^0-9]/) { exit }
        if (($ch < 1) || ($ch > $num)) { exit }
        $WALLET=$wlist->[$ch-1]
      }
      gfio::create('nodewallet.fcc',encode_json({ name => $WALLET->{name}, wallet => $WALLET->{wallet} }))
    }
  }
  print $WALLET->{name}." ".$WALLET->{wallet},"\n";
  print "Searching our IP .. ";
  my $myip=myip(); if (!$myip) { print "Failed!\n"; exit }
  my $localip=gclient::localip();
  print "$myip ($localip)\n";
  print "Starting FCC Node Server $vers\n";
  print "Making the world a more loving place to live\n\n";
  if (!$myport) { $myport=7050 }
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
  $SERVER->{pingtime}=60;
  $SERVER->{debug}=0;
  $SERVER->{name}="FCC Node $vers by Chaosje";
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
  $SERVER->start(!$slavemode,\&serverloop);
  if ($SERVER->{error}) {
    print prtm()," ** Could not start server: $SERVER->{error}\n"
  }
  return $SERVER
}

sub killserver {
  my ($msg) = @_;
  if (!$msg) { $msg="Node-Server terminated" }
  print " !! Killing server .. $msg\n";
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
  if ($SERVER) {
    $SERVER->quit()
  }
  print " *!* Server killed *!*\n";
  exit 1
}

sub killclient {
  my ($client,$msg) = @_;
  if (!$msg) { $msg='quit' }  
  if ($client && !$client->{killed}) {
    my $f=""; if ($client->{ip} && $CLIENTIP->{$client->{ip}}) { $CLIENTIP->{$client->{ip}}-- }
    if ($client->{fcc} && $client->{fcc}{function}) {
      $f='('.$client->{fcc}{function}.')'
    }
    print "   x Disconnected $f $client->{mask}: $msg\n";
    if ($client->{isparent}) {
      if ($PARENTLIST->{$client->{mask}}{identified}) {
        if ($FCCINIT == 255) { $REQUESTED -- }
      }
      delete $PARENTLIST->{$client->{mask}};
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
      if ($client->{fcc}{isparent}) {
        $client->wsquit($msg);
      } else {
        wsmessage($client,$msg,'close');
      }
      $client->{killed}=1
    }
  }
}

sub fatal {
  if ($EVALMODE) { return }
  error("!!!! FATAL ERROR !!!!\n",@_,"\n");
#  print "!!!! FATAL ERROR !!!!\n",@_,"\n";
#  killserver("Fatal Error"); error(@_)
}
sub intquit {
  killserver('130 Interrupt signal received')
}  
sub termquit {
  killserver('108 Client forcably killed connection')
}
sub sockquit {
  my $client=$SERVER->{activeclient};
  if ($client) {
    killclient($client,"32 TCP/IP Connection error")
  } elsif ($SERVERNODE) {
    killclient($SERVERNODE,"32 TCP/IP Connection error");
  } else {
    print " *!* WARNING *!* Unexpected SIGPIPE in node-kernel. @_\n"
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
    print "SERV >OUT WS ($func): $command - $msg\n"
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
      if ($client->{fcc}{isparent}) { $func='parent' }
      print "SERV >OUT JSON ($func): "
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
        print join(", ",@out),"\n"
      } else {
        print "$json\n"
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
    wsmessage($client,$data)
  }
}

sub outparents {
  my ($data) = @_;
  foreach my $p (keys %$PARENTLIST) {
    my $node=$PARENTLIST->{$p};
    if ($node->{identified}) {
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
    print "OK\n"
  } else {
    print $newclient->{error},"\n";
    if (!$node->{connectcount}) {
      $node->{connectcount}=1
    } else {
      $node->{connectcount}++
    }
    if ($node->{connectcount}>=3) {
      my $mask=$node->{host}.':'.$node->{port};
      print "Node $mask is unreachable\n";
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
  if (!$SERVER->{fcc}{localmode}) {
    if ($host eq $SERVER->{fcc}{ip}) { return }
  }
  my $mask=join(":",$host,$port);
  if ($NODES->{$mask}) { return } # already connected as a child

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
      blockheight => -1,
      sync => 0,
      syncpos => 0,
      synclen => 0,
      synctime => 0
    }
  }
}

sub minerspresent {
  foreach my $leaf (keys %$LEAVES) {
    if ($leaf->{fcc} && $leaf->{fcc}{function} eq 'miner') { return 1 }
  }
  return 0
}

sub createsyncblocks {
  $SYNCBLOCKS={};
  my $togo=$LEDGERWANTED-$LEDGERLEN;
  my $nb=$togo>>15; my $pos=$LEDGERLEN;
  for (my $i=0;$i<$nb;$i++) {
    $SYNCBLOCKS->{$pos}={ length=>32768, data=>undef, reading=>0, ready=>0 };
    $pos+=32768
  }
  my $rest=$LEDGERWANTED-$pos;
  if ($rest) {
    $SYNCBLOCKS->{$pos}={ length=>$rest, data=>undef, reading=>0, ready=>0 };
  }
}

sub savedb {
  print "\n ** Saving databases .. ";
  save(); print "OK!\n";
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
    print " <- [FCC] $command = $data\n"
  }
  if ($command eq 'init') {
    $FCCRECONNECT->{sec}=0
  }
  if ($command eq 'connect') {
    if ($FCCINIT >= 65535) { $FCCINIT=16383 } else { $FCCINIT=3 }
    $FCCHANDSHAKE=1
  } elsif ($command eq 'input') {
    my $json;
    $EVALMODE=1;
    eval("\$json=decode_json(\$data)");
    $EVALMODE=0;
    if($@){
      print "**WARNING** FCC-Server Posted not a Json String!\n$data\n$@\n"
    }else{
      my $cmd=$json->{command};
      my $func='cfcc_'.$cmd;
      if (defined(&$func)) { &$func($client,$json) }
      else { print "**WARNING** FCC-Server Function '$cmd' not yet implemented!\n" }
    }
  } elsif (($command eq 'quit') || ($command eq 'error')) {
    if ($FCCHANDLE) {
      if ($FCCRECONNECT->{sec}==0) {
        print " *!* ERROR: Lost the connection to the FCC-Server: $data\n";
        gclient::wsout($FCCHANDLE,$data,'close');
        $FCCHANDLE=undef
      }
    }
    $FCCRECONNECT={ sec => 10, time => time }
  }
}

sub cfcc_fcctime {
  my ($client,$k) = @_;
  setfcctime($k->{fcctime}-time);
  print prtm(),"> [FCC] Time offset set to $FCCTIME\n";
  $FCCINIT |= 8;
}

sub cfcc_nodelist {
  my ($client,$k) = @_;
  my $num=1+$#{$k->{nodes}};
  print prtm(),"> [FCC] The Core-network has $num nodes connected\n";
  foreach my $node (@{$k->{nodes}}) { addcandidate($node->{host},$node->{port}) }
  $FCCINIT |= 16;
}

sub cfcc_newnode {
  my ($client,$k) = @_;
  addcandidate($k->{host},$k->{port})
}

sub cfcc_init {
  my ($client,$k) = @_;
  print " !!! NODE INITIALISED AND ACTIVE !!!\n";
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
    $UPDATEMODE=0;
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
      print " * Updated $UPDATEDIR/$k->{file}\n"
    } else {
      my $tlong=length($decoded) - $k->{size};
      print " * ERROR updating $UPDATEDIR/$k->{file}: Size Mismatch of $tlong - ";
    }
  } else {
    print " * ERROR updating $UPDATEDIR/$k->{file}: Signature Incorrect\n"
  }
  if ($#{$UPDATEFILES}<0) {
    gfio::create('update.fcc',1);
    killserver("Restarting for updates")
  } else {
    my $file=shift @$UPDATEFILES;
    outfcc({ command => 'updatefile', file => $file });
    print "Update Next File $file ...\n";
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
  outjson($MINER,{ command => 'error', error => "Illegal solution given" });
}

sub cfcc_solution {
  my ($client,$k) = @_;
  outjson($MINER,{ command => 'solution' })
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
  if ($ADDCOINBASE && ($ADDCOINBASE eq $data->{signature})) {
    # running behind
    $TRANSLIST->{$data->{signature}}={ coinbase => 1, transhash => $data->{signature} };
    $VOTE={ transhash => $data->{signature} };
    transtoledger({ transhash => $data->{signature} });
    $ADDCOINBASE=undef
  }
  $CYCLELOOP=0
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
  my $sign=dechex($k->{coincount},8);
  $sign.=signoutblockdata($k->{outblocks});
  if (Crypt::Ed25519::verify($sign,hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
    addcoinbase($k)
  }
}

sub cfcc_message {
  my ($client,$k) = @_;
  if ($k->{message}) {
    if (Crypt::Ed25519::verify($k->{message},hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
      print "\n================== FCC Message ====================\n\n$k->{message}\n";
      print "\n=====================================================\n";
    }
  }  
}

sub cfcc_shutdown {
  my ($client,$k) = @_;
  if ($k->{message}) {
    if (Crypt::Ed25519::verify($k->{message},hexoct($FCCSERVERKEY),hexoct($k->{signature}))) {
      gfio::create('update.fcc',1);
      print "\n================== Shutting Down ====================\n\n$k->{message}\n";
      print "\n=====================================================\n";
      $SHUTDOWNMODE=1
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
  $SYNCING=0;
}

sub serverloop {
  # The FCC Node Control Kernel
  if (!$SERVER) { exit }
  my $ctm=gettimeofday();
  # parents are a bit different, since we are in non-loopmode for each client, where the server is in loopmode for each of it's clients
  if ($SHUTDOWNMODE) {
    my @tl=keys (%$TRANSLIST);
    if (!$VOTING && ($#tl<0) && !$TRANSDIST && ($#{$TRANSDISTLIST}<0)) {
      killserver("Shutting down for core-update .. FCC Towards a brighter future!");
      exit
    }
  }
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
          print "   - Retrying $node->{mask} .. "
        } else {
          print "   - Connecting to $node->{mask} .. "
        }
        addparent($nodes[$start]); $done=1
      } elsif ($node->{connected} && !$node->{fcc}{identified} && ($ctm-$node->{lastconnect}>=10)) {
        killclient($node->{handle},"408 Request TimeOut");
        print "   x TimeOut $node->{mask} (no identify)\n"
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
#  if ($FCCHANDSHAKE || ($ctm-$FCCLOOPTIME>0.001)) {
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
#    $FCCLOOPTIME=$ctm
#  }
  # maintenance
  if ($ctm-$LASTCLIENTRUN>0.01) {
    # FCC-Server initisaling sequence
    # Initialise our node, connect to nodes, sync ledger
    if ($FCCINIT == 65535) {
      $LASTCLIENTRUN=$ctm; return
    } elsif ($FCCINIT == 0) {
      print " * Loading and verifying the ledger .. ";
      load(); print "OK!\n";
      $LASTBLOCK=readlastblock(); $LEDGERLEN=0;
      if ($LASTBLOCK->{prev}) { $LEDGERLEN=$LASTBLOCK->{pos}+$LASTBLOCK->{next}+4 }
      $FCCINIT=1
    } elsif ($FCCINIT == 1) {
      fccconnect($SERVER->{fcc}{localmode});
      $FCCINIT=2;
    } elsif ($FCCINIT == 2) {
      if ($FCCHANDLE) { $FCCHANDLE->takeloop() }
      if (time-$FCCRECONNECT->{time}>5) {
        print " *!* ERROR: The FCC-Server did not initialise properly .. Reconnecting\n";
        fccconnect($SERVER->{fcc}{localmode});
        $FCCRECONNECT->{time}=time+10
      }
    } elsif ($FCCINIT == 3) {
      if ($UPDATEMODE >= 1) {
        if ($UPDATEMODE == 1) {
          print " * Connected to the FCC-Server .. Checking for updates ..\n";
          outfcc({ command => 'updatelist' });
          $UPDATEMODE=2
        }
      } else {
        print " * Checking time and nodelist\n";
        outfcc({ command => 'fcctime' });
        outfcc({ command => 'nodelist' });
        $FCCINIT=7
      }
    } elsif ($FCCINIT == 31) {
      # do we have nodes to sync the ledger?
      my @nodes=keys %{$PARENTLIST}; my $num=1+$#nodes;
      if (!$num) {
        print " * There are no nodes in the pool\n";
        $FCCINIT=16383
      } else {
        print " * Accumulating nodes from the pool of $num nodes .. \n";      
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
      print " * Syncing-process of the ledger data has started\n";      
      my @nodes=(keys %$PARENTLIST); $REQUESTED=0;
      foreach my $mask (@nodes) {
        my $node=$PARENTLIST->{$mask};
        if ($node->{identified}) {
          outjson($node->{handle},{ command => 'ledgerinfo' });
          $REQUESTED++
        }
      }
      print " * Requested information from $REQUESTED nodes\n";
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
      print " * Evaluating responses from $num nodes .. ";
      if (!$num) { print "OK!\n"; $FCCINIT=16383; return }
      if ($#nodes < 0) { print "OK!\n"; $FCCINIT=16383; return }
      $LEDGERWANTED=$PARENTLIST->{$nodes[0]}{ledgerlen};
      my $todo=$LEDGERWANTED-$LEDGERLEN;
      if ($todo < 0) {
        print " * Our ledger is ahead, no syncing necessary\n";
        $FCCINIT=16383
      } elsif ($todo == 0) {
        print " * Ledger is perfectly synced\n";
        $FCCINIT=16383
      } else {
        print " * Syncing $todo bytes\n";
        $FCCINIT=1023
      }
    } elsif ($FCCINIT == 1023) {
      # get ledgerdata
      createsyncblocks(); $REQBLOCKPOS=-1;
      $FCCINIT=2047
    } elsif ($FCCINIT == 2047) {
      # ready to add to ledger?
      my @nodes=(keys %$PARENTLIST);
      if ($#nodes < 0) { $FCCINIT=16383 }
      if ($SYNCBLOCKS->{$LEDGERLEN}{ready}) {
        if (!$LEDGERLEN) { $SYNCINIT=0 }
        if (!ledgerdata($SYNCBLOCKS->{$LEDGERLEN}{data},$SYNCINIT)) {
          $SYNCERROR++; 
          if (($SYNCERROR > 10) || ($#nodes <= 0)) {
            print " !! Error syncing !!\n";
            killserver("Error syncing");
            return
          }
          # error detected, reread this block
          $SYNCBLOCKS->{$LEDGERLEN}{ready}=0;
          $SYNCBLOCKS->{$LEDGERLEN}{data}="";
          $SYNCBLOCKS->{$LEDGERLEN}{reading}=0;
        } else {
          my $size=$SYNCBLOCKS->{$LEDGERLEN}{length};
          delete $SYNCBLOCKS->{$LEDGERLEN};
          $LEDGERLEN+=$size; $SYNCINIT=0;
          # done?
          if ($LEDGERLEN >= $LEDGERWANTED) {
            print " * Ledger is synced!\n";
            savedb(); $LASTBLOCK=readlastblock();
            $FCCINIT=16383; return
          }
        }
      }
      # get an empty block, lowest position first
      my $esb=-1;
      foreach my $sb (sort (keys %$SYNCBLOCKS)) {
        if (!$SYNCBLOCKS->{$sb}{reading}) { $esb=$sb; last }
      }
      if ($esb>=0) {
        my $end=$esb+$SYNCBLOCKS->{$esb}{length};
         # print " >> END = $end\n";
        my $pos=$REQBLOCKPOS; my $fnd=0;
        do {
          $pos++;
          if ($pos > $#nodes) { $pos=0 }
          my $node=$PARENTLIST->{$nodes[$pos]};
           # print " >> POS=$pos NP=$nodes[$pos] LL=$node->{ledgerlen}\n";
          if ($node->{identified}) {
            # node free to accept reading ledgerdata?
            if (!$node->{sync} && ($node->{ledgerlen}>=$end)) {
              my $len=$SYNCBLOCKS->{$esb}{length};
              $node->{sync}=1;
              $node->{syncpos}=$esb;
              $node->{synclen}=$len;
              $node->{synctime}=$ctm;
              $SYNCBLOCKS->{$esb}{reading}=1;
              outjson($node->{handle},{ command => 'reqledger', pos => $esb, length => $len });
              $fnd=1
            }
          }
        } until ($fnd || ($pos == $REQBLOCKPOS));
        $REQBLOCKPOS=$pos
      }
    } elsif ($FCCINIT == 16383) {
      $SYNCINIT=1; goactive();
    }
    $LASTCLIENTRUN=$ctm
  }
}

sub checkleafjob {
  my ($client,$ctm) = @_;
  if (!$client || !$client->{fcc}) { return }
  if (!$client->{fcc}{identified}) {
    if ($ctm-$client->{fcc}{hellotime}>=10) {
      killclient($client,"408 Request TimeOut")
    }
  } else {
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
}

sub prin {
  my ($func,$command,$data) = @_;
  print "SERV <IN ($func): $command - ";
  $EVALMODE=1;
  my $msg; eval { $msg=decode_json($data) };
  $EVALMODE=0;
  if ($@) { print $data."\n"; return }
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
    print join(", ",@out),"\n"
  } else {
    print "$data\n"
  }
}

sub handleserver {
  # Incoming message from a client we serve to
  my ($client,$command,$data) = @_;
  if ($client->{killed}) { return }
  if ($command eq 'init') {
    print "Init $client->{ip}\n";
    if (!$CLIENTIP->{$client->{ip}}) {
      $CLIENTIP->{$client->{ip}}=1;
    } else {
      $CLIENTIP->{$client->{ip}}++;
      if ($CLIENTIP->{$client->{ip}} > 5) {
        push @{$SERVER->{blockedip}},$client->{ip};
        $client->{killme}=1;
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
    if (!$client->{websockets}) {
      $client->{killme}=1; return
    }
    if ($FCCINIT < 65535) {
      print " x illegal connect $client->{ip}\n";
      outjson($client,{ command => 'error', error => 'Trying to connect to non initialised node' });
    } else {
      print " + connected $client->{ip}\n";
      outjson($client,{ command => 'hello', version => $FCCVERSION, host=>$SERVER->{fcc}{host}, port=>$SERVER->{fcc}{port} });
    }
  } elsif ($command eq 'input') {
    $EVALMODE=1;
    my $k; eval { $k=decode_json($data) };
    $EVALMODE=0;
    if ($@) {
      print prtm(),"Illegal data received from $client->{ip}:$client->{port}: $data\n";
      killclient($client,$data); return
    }    
    my $cmd=$k->{command};
    if (!$cmd) {
      print prtm(),"Illegal data (no command in JSON) received from $client->{ip}:$client->{port}\n";
      killclient($client,$data); return
    }
    my $func="c_$cmd";
    if (defined &$func) {
      &$func($client,$k)
    } else {
      print prtm(),"Illegal JSON-command '$cmd' received from $client->{ip}:$client->{port}\n";
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
      print prtm(),"JSON error ($mask): $@\n";
      killclient($node,"JSON error: $@\n")
    }
    my $cmd=$k->{command};
    if (!$cmd) { return }
    my $proc="c_$cmd";
    if (defined &$proc) {
      &$proc($node,$k)
    } else {
      print prtm(),"Illegal command received from $mask: $cmd\n";
      fault($node)
    }
  } elsif ($cmd eq 'error') {
    print prtm(),"Lost connection to node $mask: $msg\n";
    killclient($node,$msg);
  } elsif ($cmd eq 'quit') {
    if ($FCCINIT == 255) { $REQUESTED-- }
    print prtm(),"Node $mask terminated: $msg\n";
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
  my $mask=join(':',$k->{host},$k->{port});
  if ($client->{ischild}) { 
    print " !*! Rejected! Child-Node $client->{mask} tried to identify as a parent !*!\n";
    killclient($client,"Don't hack"); return
  }
  if ($client->{mask} ne $mask) {
    print " !*! Rejected! Parent-Node $client->{mask} tried to identify as $mask !*!\n";
    killclient($client,"Don't hack"); return
  }
  if ($DEBUG) {
    print prtm(),"Response from node $client->{mask} -> Identify as node\n";
  }
  if ($k->{version} gt $FCCVERSION) {
    print prtm(),"! Node $client->{mask} has version $k->{version}, we only have version $FCCVERSION";
    killclient($client,"Version $k->{version} is not supported by this node");
    return    
  }
  $client->{fcc}{port}=$k->{port};
  $client->{mask}=$mask;
  if (!$PARENTLIST->{$client->{mask}}) {
    print prtm(),"! The port the node gave us is unknown in the core-list";
    killclient($client,"The port the node gave us is unknown in the core-list");
    return
  }
  $client->{fcc}{version}=$k->{version};
  $client->{fcc}{entrytime} = time+$FCCTIME;
  my $send= {
    command => 'identify',
    type => 'node',
    version => $FCCVERSION,
    host => $SERVER->{fcc}{host},
    port => $SERVER->{fcc}{port}
  };
  $client->{fcc}{function}='node';
  $client->{fcc}{identified}=1;
  $PARENTLIST->{$client->{mask}}{identified}=1;
  outjson($client,$send);
  if ($FCCINIT == 65535) {
    outjson($client,{ command => 'ready' })
  }
  $client->outburst();
}

sub c_identify {
  my ($client,$k) = @_;
  if ($SHUTDOWNMODE) { killclient($client,"Service temporarely unavailable"); return }
  if ($k->{type} eq 'node') {
    my $mask=join(':',$k->{host},$k->{port});
    $client->{mask}=join(':',$client->{ip},$k->{port});
    if ($client->{mask} ne $mask) {
      print " !*! Rejected! Child-Node $client->{mask} tried to identify as $mask !*!\n";
      killclient($client,"Don't hack"); return
    }
  } elsif ($client->{isparent}) {
    print " !*! Rejected! Parent-Node $client->{mask} tried to identify as a child !*!\n";
    killclient($client,"Don't hack"); return
  } else {
    $client->{mask}=join(':',$client->{ip},"[".$client->{port}."]");
    $client->{fcc}{jobs}=[];
    $LEAVES->{$client->{mask}}=$client
  }
  $client->{fcc}{identified}=1;
  $client->{fcc}{function}=$k->{type};
  $client->{fcc}{version}=$k->{version};
  if ($k->{type} eq 'node') {
    $client->{fcc}{port}=$k->{port};
    if (!checklanwan($client->{ip})) {
      killclient($client,"LAN/WAN Intrucion"); return
    }
    $NODES->{$client->{mask}}=$client;
  }
  if ($k->{version} gt $FCCVERSION) {
    # assume backwards-compatiblity
    print prtm()," !*! Client $client->{mask} is running version $k->{version}. We only $FCCVERSION!\n";
    killclient($client,"Version $k->{version} is not supported by this node");
    return
  }
  if ($k->{type} eq 'miner') {
    outfcc({ command => 'challenge' }) 
  }
  $client->{fcc}{version}=$k->{version};
  print prtm(),"Client $client->{mask} is a $k->{type} v$k->{version}\n";
}

sub c_ready {
  my ($client) = @_;
  $client->{fcc}{ready}=1
}

sub c_transaction {
  my ($client,$k) = @_;
  if ($FCCINIT < 65535) { return }
  addtransaction($client,$k->{data})
}

sub c_coinbasetrans {
  my ($client,$k) = @_;
  if ($FCCINIT < 65535) { return }
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
  $MINER=$client;
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
  $node->{blockheight}=$k->{height}
}

sub c_reqledger {
  my ($client,$k) = @_;
  if ($FCCINIT < 65535) { return }
  if ($k->{pos}+$k->{length}>$LEDGERLEN) {
    fault($client); return
  }
  my $data=zb64(gfio::content('ledger.fcc',$k->{pos},$k->{length}));
  outjson($client,{ command => "ledgerdata", pos => $k->{pos}, data => $data, final => $k->{final} || 0, first => $k->{first} || 0 })
}

sub c_ledgerdata {
  my ($client,$k) = @_;
  $k->{data}=b64z($k->{data});
  if (!$SYNCING) {
    ledgerdata($k->{data},$k->{first});
    if ($k->{final}) {
      $LASTBLOCK=readlastblock(); $LEDGERLEN=$LASTBLOCK->{pos}+$LASTBLOCK->{next}+4;
    }
    return
  }
  if ($SYNCBLOCKS->{$k->{pos}} && (length($k->{data}) == $SYNCBLOCKS->{$k->{pos}}{length})) {
    my $node=$PARENTLIST->{$client->{mask}};
    if (($node->{synclen} == $SYNCBLOCKS->{$k->{pos}}{length}) && ($node->{syncpos} == $k->{pos})) {
      $SYNCBLOCKS->{$k->{pos}}{ready}=1;
      $SYNCBLOCKS->{$k->{pos}}{data}=$k->{data};
      $node->{sync}=0
    } else {
      fault($client)
    }
  } else {
    fault($client)
  }
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
        $to->{fee}=$MINIMUMFEE
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
    illegal => $k->{illegal}, consensus => $k->{consensus} 
  };
  $VOTE->{received}[$k->{round}]++;
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
    print " *! Transerror: $trans->{error}\n";
    fault($client); return
  }
  $TRANSDISTDONE->{$client->{mask}.$trans->{transhash}}=1;
  if ($TRANSLIST->{$trans->{transhash}}) { return } # already present
  if ($TRANSLISTDONE->{$trans->{transhash}}) { return } # already done
  checkinblocks($trans);
  if ($trans->{error}) {
    print " *! Transerror: $trans->{error}\n";
    fault($client); return
  }
  if (!$skipvalidate) {
    validateblock($trans);
    if ($trans->{error}) {
      print " *! Transerror: $trans->{error}\n";
      fault($client); return
    }
  }
  $trans->{status}=0;
  if ($client->{fcc}{function} eq 'leaf') {
    $trans->{client}=$client
  }
  $trans->{tobs}=1;
  print " ++ Transaction $trans->{transhash} (fee = $trans->{fee})\n";
  $TRANSLIST->{$trans->{transhash}}=$trans;
  $CYCLELOOP=0;
  if ($TRANSCATCHUP->{$trans->{transhash}}) {
    # if not deleted, used as error-marker in voting round 1
    delete $TRANSCATCHUP->{$trans->{transhash}};
  } else {
    push @$TRANSDISTLIST,$data;
  }
}

sub checkinblocks {
  my ($trans) = @_;
  my %cib=(); foreach my $ib (@{$trans->{inblocks}}) { $cib{$ib}=1 }
  foreach my $t (keys %$TRANSLIST) {
    if ($TRANSLIST->{$t}{pubkey} eq $trans->{pubkey}) {
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
  if ((length($data)<416) || ($data =~ /[^0-9A-F]/)) { return { error => 1 } }
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
  $info->{wallet}=createwalletaddress($info->{pubkey});
  my $blen=length($info->{sign}); my $outpos=$blen-$info->{numout}*88;
  if ($outpos % 64 != 0) { return { error => "outpos ($outpos) not divisable by 64" } }
  if ($outpos == 0) { return { error => "Money does not come from nothing" } }
  if ($outpos / 64 > 255) { return { error => "Too many data needed to make this transaction. Please split up into smaller amounts" } }
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
    if ($TRANSLIST->{$trans}{wallet} eq $wallet) {
      push @$blocks,@{$TRANSLIST->{$trans}{inblocks}}
    }
  }
  return $blocks
}

############### Voting System ###################################

sub votesuggest {
  my ($activate) = @_;
  
  if ($VOTING) { return }
  if ($ADDCOINBASE) { return }

  $printed={};

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
#  print "********** Votesuggest = $tr\n";

  my $nodelist=corelist();
  if ($trans) {
    # we found a transaction to suggest to the core (first voting round)
    my $tm=gettimeofday();
    $VOTE={
      round => 0,
      transhash => $trans,
      coinbase => $coinbase,
      responses => [],
      total => 1+$#{$nodelist},
      received => [],
      consensus => 0,
      start => $tm
    };
    $VOTE->{received}[0]=0;
    $VOTE->{responses}[0]={};
    if ($#{$nodelist}<0) {
      # we are the only node! God save the Mohacans
      transtoledger($TRANSLIST->{$trans})
    } else {
      $VOTING=1;
      outcorejson({ command => 'vote', transhash => $trans, round => 0, ledgerlen => $LEDGERLEN, coinbase => $TRANSLIST->{$trans}{coinbase} })
    }
  } elsif ($activate) {
    if (!$TRANSLISTDONE->{$activate}) {
      # TRANSLIST seems to be empty, but they are voting on something.. get it (in voting round 0) and vote along!
      if (length($activate) == 128) {
        $coinbase=1;
        $TRANSLIST->{$activate} = { coinbase => 1, transhash => $activate };
      }
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
      };
      $VOTE->{received}[0]=0;
      $VOTE->{responses}[0]={};
      $VOTING=1;
      my $ot={ command => 'vote', transhash => $activate, round => 0, ledgerlen => $LEDGERLEN, coinbase => $coinbase };
      outcorejson($ot)
    }
  }
  # if ($VOTING) { print "  **** Tumbling down the rabbithole ****\n" }
}

sub analysevotes {

  if (!$VOTING) { return }

  if (!$printed->{$VOTE->{round}}) {
    #print "Voting Round = $VOTE->{round} Total = $VOTE->{total}\n";
    $printed->{$VOTE->{round}}=1
  }

  my $action=0; my $tm=gettimeofday();
  if (!$VOTE->{received}[$VOTE->{round}]) {
    $VOTE->{received}[$VOTE->{round}]=0;
    $VOTE->{responses}[$VOTE->{round}]={}
  }
  if (($VOTE->{received}[$VOTE->{round}] >= $VOTE->{total}) || ($tm-$VOTE->{start}>=5)) {
    my @rplist=();
    foreach my $mask (keys %{$VOTE->{responses}[$VOTE->{round}]}) {
      my $rp=$VOTE->{responses}[$VOTE->{round}]{$mask}; push @rplist,$rp
    }
    my $nrp = 1 + $#rplist;
    #print "Voting: Received = $VOTE->{received}[$VOTE->{round}] NRP = $nrp\n";
    if ($#rplist < 0) {
      # we are stalled ..
      if ($VOTE->{total}) {
        $VOTE->{start}=$tm
      } else {
        # we're the only node left in the core (the other one just quit)
        transtoledger($TRANSLIST->{$VOTE->{transhash}})
      }
      return
    }

  ######### Round 0 - Checking ledger sync & catching missing transactions ################

    if ($VOTE->{round} == 0) {
      # syncing transaction round, necessary for checking illegal transactions (distributed flood attack)!
      my $lll={};
      foreach my $rp (@rplist) {
        if (!defined $lll->{$rp->{ledgerlen}}) {
          $lll->{$rp->{ledgerlen}}=1
        } else {
          $lll->{$rp->{ledgerlen}}++
        }
      }
      my @sll = sort { $lll->{$b} <=> $lll->{$a} } keys %$lll;
      if ($sll[0] != $LEDGERLEN) {
        # Desynced !!!
        if ($sll[0] > $LEDGERLEN) {
          my $node;
          foreach my $rp (@rplist) {
            if ($rp->{ledgerlen} == $sll[0]) {
              $node=$rp; last
            }
          }
          my $len=$sll[0]-$LEDGERLEN; my $pos=$LEDGERLEN; my $first=1;
          while ($len>0) {
            # should be a small block .. but if transactions go very fast on a slow computer, we just keep syncing..
            my $sz=32768; my $final=0; if ($sz>=$len) { $sz=$len; $final=1 }
            outjson($node,{ command => 'reqledger', pos => $pos, length => $sz, first=> $first, final => $final });
            $pos+=$sz; $len-=$sz; $first=0
          }
        } else {
          # Mhzzzz... We have more ledger then everybody else?? Should never happen..
          # Not sure what to do here yet.. it should catch up.. I guess..
        }
      }
      # catch up missing transactions and vote
      my $sent={};
      $VOTE->{round}=1;
      $VOTE->{total}=1+$#rplist;
      $VOTE->{start}=$tm;
      foreach my $rp (@rplist) {
        if ((!$TRANSLIST->{$rp->{transhash}}) && (length($rp->{transhash}) == 64)) {
          if (!$sent->{$rp->{transhash}}) { $sent->{$rp->{transhash}}=0 }
          if ($sent->{$rp->{transhash}}<3) {
            outjson($rp->{node},{ command => 'reqtrans', transhash => $rp->{transhash} });
            $TRANSCATCHUP->{$rp->{transhash}}=1;
            $sent->{$rp->{transhash}}++
          }
        }
        outjson($rp->{node},{ command => 'vote', round => 1, transhash => $VOTE->{transhash} })
      }
      return
    }

  ########### Round 1 - Initialising first responses #################

    my $list={}; my $vtot=0; my $illcnt=0;
    foreach my $rp (@rplist) {
      if ($rp->{illegal}) { $illcnt++ }
      my $q=1; if ($rp->{consensus}) { $q=$rp->{consensus} }
      $list->{$rp->{transhash}}+=$q; $vtot+=$q;
    }
    my @slist = sort { $list->{$b} <=> $list->{$a} } keys %$list;
    # print "Voting count:\n"; foreach my $s (@slist) { print "$list->{$s} $s\n" }
    if ($VOTE->{round} == 1) {

      if ($#slist == 0) {
        # 100% consensus without voting! (This is the normal state)
        if ($TRANSLIST->{$slist[0]}) {
          # this is the perfect state, a perfectly synced core
          my $tr=$TRANSLIST->{$slist[0]};
          transtoledger($TRANSLIST->{$slist[0]});
          return
        } elsif ($TRANSCATCHUP->{$slist[0]}) {
          # RED FLAG: this is an attack-state!
          # we should have this transaction, but it bounced after getting it!
          # transactions only bounce when invalid (probably we will be signalled to have an invalid too!)
        } else {
          # obviously a transaction is a) not received yet b) too fresh
          my $sent=0;
          for (my $m=0;$m<=$#rplist;$m++) {
            if ($rplist[$m]{transhash} eq $slist[0]) {
              outjson($rplist[$m]{node},{ command => 'reqtrans', transhash => $slist[0] });
              $sent++; if ($sent == 3) { last }
            }
          }
        }
      }
      if (!$TRANSCATCHUP->{$slist[0]}) {
        $VOTE->{transhash}=$slist[0];
        $VOTE->{consensus}=int (100 * $list->{$slist[0]} / $vtot);
      } else {
        # find the best valid suggestion
        my $max=0; my $stot=0; my $sug={}; my $select=$VOTE->{transhash};
        foreach my $rp (@rplist) {
          if ($TRANSLIST->{$rp->{transhash}}) { 
            $sug->{$rp->{transhash}}++; $stot++;
            if ($sug->{$rp->{transhash}}>$max) { $max=$sug->{$rp->{transhash}}; $select=$rp->{transhash} }
          }
        }
        $VOTE->{transhash}=$select;
        $VOTE->{consensus}=int (100 * $max / $stot);
      }
      $VOTE->{round}=2;
      $VOTE->{start}=$tm;
      $VOTE->{total}=1+$#rplist;
      foreach my $rp (@rplist) {
        my $ill=0; if ($TRANSCATCHUP->{$rp->{transhash}}) { $ill=1 }
        outjson($rp->{node},{ command => 'vote', round => 2, transhash => $VOTE->{transhash}, illegal => $ill, consensus => $VOTE->{consensus} })
      }

    } else {

  ############# Voting rounds 2+  - consensus #####################################

      if (($illcnt>1) || ($illcnt && ($VOTE->{total}==1))) {
        delvote();
        # now we are out of sync, cannot suggest, must vote?
        if (($#slist == 0) && ($VOTE->{transhash} eq $rplist[0]->{transhash})) {
          # all the same invalid
          return          
        }
        foreach my $rp (@rplist) {
          if (!$TRANSCATCHUP->{$rp->{transhash}}) {
            # found at least one valid
            $VOTING=1; last
          }
          if (!$VOTING) {
            # everybody will now have deleted
            return
          }
        }
      }
      if ($#slist == 0) {
        if ($TRANSLIST->{$slist[0]}) {
          # got consensus!
          transtoledger($TRANSLIST->{$slist[0]});
          return
        }
      }
      if ($TRANSLIST->{$slist[0]}) {
        $VOTE->{transhash}=$slist[0];
        $VOTE->{consensus}=int (100 * $list->{$slist[0]} / $vtot);
      } else {
        # find best suggestion
        my $max=0; my $stot=0; my $sug={}; my $select=$VOTE->{transhash};
        foreach my $rp (@rplist) {
          if ($TRANSLIST->{$rp->{transhash}}) {
            if (!$sug->{$rp->{transhash}}) { $sug->{$rp->{transhash}}=1 } else { $sug->{$rp->{transhash}}++ }
            $stot++;
            if ($sug->{$rp->{transhash}}>$max) { $max=$sug->{$rp->{transhash}}; $select=$rp->{transhash} }
          }
        }
        $VOTE->{transhash}=$select;
        $VOTE->{consensus}=int (100 * $max / $stot);
      }
      if ($VOTE->{consensus} > 90) {
        transtoledger($TRANSLIST->{$VOTE->{transhash}}); return
      }
      $VOTE->{round}++;
      $VOTE->{start}=$tm;
      $VOTE->{total}=1+$#rplist;
      foreach my $rp (@rplist) {
        outjson($rp->{node},{ command => 'vote', round => $VOTE->{round}, transhash => $VOTE->{transhash}, consensus => $VOTE->{consensus} })
      }      
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
    print " %! Transaction rejected\n";
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
        print " % Feetransaction created\n";
        foreach my $out (@{$cb->{outblocks}}) {
          if ($out->{wallet} eq $WALLET->{wallet}) {
            print "% We earned FCC ".extdec($out->{amount}/100000000)." !\n"
          }
        }
        createfeetransaction($cb->{fcctime},$cb->{blockheight},$cb->{spare},$cb->{signature},$cb->{outblocks});
        return 1
      } else {
        print " % Coinbase created\n";
        if ($cb->{outblocks}[1]{wallet} eq $WALLET->{wallet}) {
          print " % We've earned a bonus of FCC ".extdec($MINEBONUS/100000000)." !\n"
        }
        createcoinbase($cb->{fcctime},$cb->{coincount},$cb->{signature},$cb->{outblocks});
        return 1
      }
    }
  }
  return 0
}

sub transtoledger {
  my ($trans) = @_;
  if (length($trans->{transhash}) == 128) {
    if (!addcoinbasetoledger($trans->{transhash})) {
      # still waiting for the FCC-server
      $ADDCOINBASE=$trans->{transhash}
    }
  } else {
    print " % Transaction created (fee = ".extdec($trans->{fee}/100000000).")\n";
    createtransaction($trans->{fcctime},$trans->{pubkey},$trans->{signature},$trans->{inblocks},$trans->{outblocks});
    if ($trans->{client}) {
      outjson($trans->{client},{ command => 'processed', transhash => $trans->{transhash}, wallet => $trans->{wallet}, amount => $trans->{amount}, fee => $trans->{fee} })
    }
  }
  $LASTBLOCK=readlastblock(); $LEDGERLEN=$LASTBLOCK->{pos}+$LASTBLOCK->{next}+4;
  delvote(1)
}

# I love it when a plan comes together :)

# EOF FCC Node by Chaosje (C) 2018 Domero