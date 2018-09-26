#!/usr/bin/perl

# FCC Local Wallet Server
use lib qw(../modules);
use strict;
no strict 'refs';
use warnings;
use Time::HiRes qw(usleep gettimeofday);
use Crypt::Ed25519;
use Browser::Open qw(open_browser);
use gfio;
use gserv 4.1.1 qw(wsmessage broadcastfunc);
use gclient 7.2.2;
use FCC::global;
use FCC::miner;
use FCC::wallet 2.01 qw(validwallet validwalletpassword walletisencoded newwallet loadwallets savewallet savewallets);
use FCC::leaf 2.01 qw(startleaf leafloop closeleaf);
use gerr qw(error);
use JSON;


my $DEBUG = 1;
my $INIT = 0;
my $SERVER;
my $POOL;
my $WEBSITEINIT=0;
my $FCCSERVER='https://'. $FCCSERVERIP.':'.$FCCSERVERPORT;
my @NODES=(); my $NODENR=0; my $WLIST=[]; my $PASS;
my $TRANSCOUNT = 0;
my $MINER;
my $MINING=0;
my $MINEDATA={ coincount => 0 };
my $MINFHASH=undef;
my $MAXFHASH=undef;
my $MINERWALLET="";
my $POWERDOWN=0;
my $MINERDISCON=0;

my $VERSION = "010104";

################################################################################
###### Use the file trusted.nodes to force connecting to trusted nodes #########

my $TRUSTEDNODES=(-e "trusted.nodes" ? decode_json(gfio::content("trusted.nodes")) : []);
my $FORCENODE; if($#$TRUSTEDNODES>-1){ $FORCENODE=$TRUSTEDNODES->[int(rand()*(1+$#$TRUSTEDNODES))] }

my $TRUSTEDPOOLS=(-e "pool.nodes" ? decode_json(gfio::content("pool.nodes")) : []);
my $MINERNODE; if($#$TRUSTEDPOOLS>-1){ $MINERNODE=$TRUSTEDPOOLS->[int(rand()*(1+$#$TRUSTEDPOOLS))] }

################################################################################
# Local Wallet Listen Port
my $PORT =
  $ARGV[0] && $ARGV[0] =~ /[0-9]+/ ? $ARGV[0] : 
  -e "wallet.port" ? gfio::content("wallet.port") : 
  5115;
################################################################################
# Local Wallet Chat Nick & Ident
my $NICKIDENT;
if (-e "nickident.chat") {
  $NICKIDENT=decode_json(gfio::content("nickident.chat"));
} else {
  $NICKIDENT={}
}
################################################################################

################################################################################
# Signaling 

$SIG{'INT'}=\&intquit;
$SIG{'TERM'}=\&termquit;
$SIG{'PIPE'}=\&sockquit;
$SIG{__DIE__}=\&fatal;
$SIG{__WARN__}=\&fatal;

#versionCheck();

################################################################################

sub fatal {
  print "!!!! FATAL ERROR !!!!\n",@_,"\n";
  killserver("Fatal Error",1); error(@_)
}
sub intquit {
  killserver('130 Interrupt signal received'); exit
}  
sub termquit {
  killserver('108 Client forcably killed connection'); exit
}
sub sockquit {
  killserver("32 TCP/IP Connection error"); exit
}

###### Development Wallet Updater by SkyDrive & OnEhIppY #######################

sub versionCheck {
  my $github={base => "https://raw.githubusercontent.com/FactorialCoin/base/master"};
  $github->{dev}="$github->{base}/FCC/Wallet/wallet.dev";
  my $fil = ['wallet.cgi','wallet.js','wallet.htm','wallet.css','image/clipboard.png','image/del.png','image/favicon-16.png','image/favicon-32.png','image/fccico.png','image/fcclogo.png','image/pause.png','image/pickaxe.gif','image/powerdown.png','image/save.png','image/start.png'];
  my $fccversion = get("$github->{base}/version.txt"); $fccversion=~s/[^0-9]//gs;
  print "** Github FCC base Version is: $fccversion\n";
  my $version = get("$github->{dev}/version.txt"); $version=~s/[^0-9]//gs;
  my ($MAIN, $MAJOR, $MINOR) = (substr($VERSION,0,2),substr($VERSION,2,2),substr($VERSION,4,2));
  my ($main, $major, $minor) = (substr($version,0,2),substr($version,2,2),substr($version,4,2));
  print "** Our Wallet Version is: $MAIN.$MAJOR.$MINOR\n";
  print "** Github FCC/Wallet/wallet.dev Version is: $main.$major.$minor\n";
  my $upd=0;
  if( $version > $VERSION ){ # ipv if( ($main > $MAIN) || ($major > $MAJOR && $main >= $MAIN) || ($minor > $MINOR && $major >= $MAJOR && $main >= $MAIN) ){
    print "** Updating to Version $VERSION to new Version $version .. ** \n";
    my $up=0;
    for my $f (@$fil) {
      $up++;
      print "** Updating ($up of ".(1+$#{$fil}).": $f ".(" "x16)."\r";
      if($f =~ /image\//){
        if(!-e $f){
          my $d=get("$github->{dev}/$f");
          if($d) { gfio::content($f,$d) }
        }
      } else {
        my $d=get("$github->{dev}/$f");
        if($d) { gfio::content($f,$d) }
      }
    }
    gfio::content("wallet.updated",$version);
    $upd++;
  }else{
    # check for missing files after update (new images)
    my $mss=0;
    for my $f (@$fil) { if (!-e $f) {
      if(!$mss){ $mss=1; print "** Updating missing files or images of Current Version $VERSION .. ** \n" }
      print "** Updating ($mss of ".(1+$#{$fil}).": $f ".(" "x16)."\r";
      $upd++; my $d=get("$github->{dev}/$f"); if($d){ $mss++; gfio::content($f,$d) } 
    } }
  }
  if($upd){
    print "\n ** 5 ** Please Restart your wallet.. ** \r";
    for(my $s=5;$s>0;$s--){ print " ** $s \r"; usleep(1000000) }
    exit
  }
}

sub get { 
  my $req=gclient::website(@_);
  if($req->{error}){
    print "\nError requesting : $_[0]\n$req->{error}\n\n";
    return
  }
  return $req->{content}
}

################################################################################

sub killleaves {
  my ($client,$message) = @_;
  if ($client->{fcc}{leaf}) {
    $client->{fcc}{leaf}->wsquit($message)
  }
  if ($client->{fcc}{miner}) {
    $client->{fcc}{miner}->wsquit($message)
  }
}

sub killserver {
  if ($SERVER) {
    broadcastfunc($SERVER,\&killleaves,$_[0]);
    print "Terminating FCC Local Wallet Server .. \n";
    $SERVER->quit($_[0]);
  }
  if ($MINER) { $MINER->closeleaf() }
  if (!$_[1]) { exit }
}

sub quitleaf {
  my ($client) = @_;
  if ($client->{fcc}){
    if($client->{fcc}{leaf}) {
      closeleaf($client->{fcc}{leaf})
    }
    elsif($client->{fcc}{miner}) {
      closeleaf($client->{fcc}{miner})
    }
  }
}

initfcc();
print "Starting FCC localhost Wallet Server .. \n";
$SERVER=gserv::init(\&handle,\&loop);
$SERVER->{name}="FCC Local Wallet Server v1.0";
$SERVER->{server}{port}=$PORT;
$SERVER->{allowedip}=['127.0.0.1'];
$SERVER->{verbose}=0;
$SERVER->start(1,\&serverloop);
if ($SERVER->{error}) {
  print "Error starting server: $SERVER->{error}\n"
} else {
  print "Server terminated o.k.\n"
}
exit;

sub loopclient {
  my ($client) = @_;
  if ($client->{fcc}) {
    if ($client->{fcc}{connectnode}) {
      connecttonode($client)
    } elsif ($client->{fcc}{leaf} && $client->{fcc}{leafready}) {
      my $leaf=$client->{fcc}{leaf};
      if ( $#{$client->{fcc}{jobs}} >=0 ) {        
        my $job=shift @{$client->{fcc}{jobs}};
        if ($job->{command} eq 'balance') {
          if ($job->{time}) {
            my $ctm=gettimeofday();
            if ($ctm-$job->{time} < 10) {
              unshift @{$client->{fcc}{jobs}},$job;
              return
            }
          }
          $leaf->balance($job->{wallet})
        } elsif ($job->{command} eq 'transfer') {
          $leaf->transfer($job->{pubkey},$job->{change},$job->{outlist})
        } elsif ($job->{command} eq 'startminer') {
          print "Starting Miner\n";
          if(!$MINING || !$MINER || $MINERDISCON){
            $MINERDISCON=0;
            print "Opening Miners Node Connection: $client->{fcc}{leafip}:$client->{fcc}{leafport}\n";
            $MINER=startleaf($client->{fcc}{leafip},$client->{fcc}{leafport},\&slaveminercall,0,1);
          }
          if ($MINER->{error}) {
            print " ! Error starting miner - $MINER->{error}\n"
          } elsif ($MINER->{quit}) {
            print " ! Error starting miner - Connection Quit\n"
          } else {
            $MINER->{client}=$client;
            print " * Miner sucessfully started .. may the FCC be with you ;)\n"
          }
        }
      }
    } else {
      # unexpected fallback
      connecttonode($client)
    }
  }
}

sub serverloop {
  if (!$WEBSITEINIT) {
    print " * Opening wallet website\n";
    eval("open_browser(\"http://127.0.0.1:$PORT\");");
    $WEBSITEINIT=1
  }
  leafloop();
  broadcastfunc($SERVER,\&loopclient);
  if ($MINING) {
    my $tb=1;
    my $lsz=1000;
    for (my $i=0;$i<$lsz;$i++) {
      mineloop()
    }
    my $tm=gettimeofday();
    $MINEDATA->{fhash}+=$lsz;
    my $bnr=int (($tm-$MINEDATA->{minestart})/$tb);
    if ($bnr != $MINEDATA->{timeblock}) {
      $MINEDATA->{timeblock}=$bnr;
      my $hr=int ($MINEDATA->{fhash} / $tb);
      if(!defined $MINFHASH || $MINFHASH > $hr){ $MINFHASH=$hr }
      if(!defined $MAXFHASH || $MAXFHASH < $hr){ $MAXFHASH=$hr }
      my $done=$MINEDATA->{hashtot}+=$MINEDATA->{fhash};
      $done=int (10000 * $done / $MINEDATA->{diff}) / 100;
      if ($MINER->{client}) { wsmessage($MINER->{client},"miner Speed: $hr Fhash/sec ($done %)") }
      print " Speed: $hr Fhash/sec ($done %) $MINER->{client} \r";
      $MINEDATA->{fhash}=0
    }
  }
  if($POWERDOWN){
    leafloop();
    if($POWERDOWN > 100){
      exit 1;
    }
    $POWERDOWN++
  }
  usleep($MINING ? 100:10000);
}

sub challenge {
  my ($data) = @_;
  if(!defined $data->{init}){ $data->{init}="" }
  if($MINEDATA){
    if($MINEDATA->{coincount} ne $data->{coincount}){
      $data->{minestart}=gettimeofday(); 
      $data->{timeblock}=0;
      $data->{fhash}=0;
      $data->{hashtot}=0;
    }else{
      $data->{minestart}=$MINEDATA->{minestart};
      $data->{timeblock}=$MINEDATA->{timeblock};
      $data->{fhash}=$MINEDATA->{fhash};
      $data->{hashtot}=$MINEDATA->{hashtot};
    }
  }else{
      $data->{minestart}=gettimeofday(); 
      $data->{timeblock}=0;
      $data->{fhash}=0;
      $data->{hashtot}=0;
  }
  $MINEDATA=$data; $MINING=1;
  if ($MINEDATA->{init}) {
    $MINEDATA->{tryhint}=$MINEDATA->{init}
  }
  else{
    if ($MINEDATA->{hints}) {
      $MINEDATA->{hints}=perm($MINEDATA->{hints},int(rand(fac(length($MINEDATA->{hints})))));
      $MINEDATA->{hintpos}=0;
      $MINEDATA->{tryhint}=substr($MINEDATA->{hints},0,1);
      if ($MINER->{client}) { wsmessage($MINER->{client},"miner Trying suggestion $MINEDATA->{tryhint}") }
      print " * Trying suggestion $MINEDATA->{tryhint}     \n";
    } else {
      $MINEDATA->{tryhint}=""
    }
  }
  $MINEDATA->{tryinit}="";
  for (my $i=0;$i<$MINEDATA->{length};$i++) {
    my $c=chr(65+$i);
    if ($MINEDATA->{tryhint} !~ /$c/) { $MINEDATA->{tryinit}.=$c }
  }
  $MINEDATA->{trymax}=fac(length($MINEDATA->{tryinit}));
  $MINEDATA->{try}=int rand($MINEDATA->{trymax});
  $MINEDATA->{trystart}=$MINEDATA->{try};
}

sub mineloop {
  if (!$MINING) { usleep(10000); return }
  my $suggest=$MINEDATA->{tryhint}.perm($MINEDATA->{tryinit},$MINEDATA->{try});
  if (minehash($MINEDATA->{coincount},$suggest) eq $MINEDATA->{challenge}) {
    # found the solution!
    if($MINEDATA->{init}){
      my $solhash=solhash($MINERWALLET,$suggest);
      print " **!! SOLUTION !!** $suggest\n";
      $MINER->solution($MINERWALLET,$suggest);
    }else{
      my $solhash=solhash($MINERWALLET,$suggest);
      print " **!! SOLUTION !!** $suggest\n";
      $MINER->solution($MINERWALLET,$solhash);
    }
    $MINING=0; return
  }
  $MINEDATA->{try}++;
  if ($MINEDATA->{try} >= $MINEDATA->{trymax}) {
    $MINEDATA->{try}=0
  }
  if ($MINEDATA->{try} == $MINEDATA->{trystart}) {
    if($MINEDATA->{init}){
      print "Nop, not this block $MINEDATA->{init}.... at $MINEDATA->{fhash} Fhs...                        \n";
      if ($MINER->{client}) { wsmessage($MINER->{client},"miner Nop, not this block $MINEDATA->{init} :-|") }
      $MINER->outnode({command=>'challenge',nope=>$MINEDATA->{init}});
      $MINING=0;
    }else{
      $MINEDATA->{hintpos}++;
      if ($MINEDATA->{hintpos} < length($MINEDATA->{hints})) {
        $MINEDATA->{tryhint}=substr($MINEDATA->{hints},$MINEDATA->{hintpos},1);
        if ($MINER->{client}) { wsmessage($MINER->{client},"miner Trying suggestion: $MINEDATA->{tryhint}") }
        print " * Trying suggestion: $MINEDATA->{tryhint}   \n";
        $MINEDATA->{tryinit}="";
        for (my $i=0;$i<$MINEDATA->{length};$i++) {
          if ($MINEDATA->{tryhint} ne chr(65+$i)) {
            $MINEDATA->{tryinit}.=chr(65+$i);
          }
        }
      } else {
        print "Error.. mined all possibilities\n";
        if ($MINER->{client}) { wsmessage($MINER->{client},"miner Error.. mined all possibilities :-(") }
      }
    }
  }
}

sub initfcc {
  print "Initialising FCC Private Wallet Server ..\n";
  if (!$FORCENODE) {
    print "Connecting to FCC-Server .. \n";
    my $req=gclient::website("$FCCSERVER/?fcctime");
    if ($req->{error}) {
      print "Error connecting: $req->{error}\n"; exit
    }
    fcctime($req->{content});
    print "FCC-Time set to $FCCTIME\n";
    $req=gclient::website("$FCCSERVER/?nodelist");
    @NODES=split(/ /,$req->{content}); my $nc=1+$#NODES;
    if (!$nc) {
      print "The core is exhausted.. quitting.\n"; exit
    }
  }
}

sub init {
  my ($client) = @_;
  if ($client->{fcc}{connected}) { return }
  $client->{fcc}={};
  status($client,"FCC-Time offset to local clock = $FCCTIME seconds");
  if ($FORCENODE) {
    status($client,"Forcably using $FORCENODE\n")
  } else {
    my $nc=1+$#NODES;
    status($client,"The core has $nc nodes active");
  }
  $client->{fcc}{connectnode} = 1;
  $client->{fcc}{connected} = 1;
  $client->{fcc}{trans} = [];
}

sub initwallet {
  $WLIST=loadwallets($PASS);
  if ($#{$WLIST}<0) {
    print "Creating new wallet\n";
    my $wallet=newwallet("Main wallet");
    savewallet($wallet,$PASS);
    push @$WLIST,$wallet
  }
  $INIT=1
}

sub addwallets {
  my ($client) = @_;
  print "Initialising wallets and addressbook\n";
  status($client,"Initialising wallets and addressbook");
  foreach my $wallet (@$WLIST) {
    my $name=""; if ($wallet->{name}) { $name=$wallet->{name} }
    wsmessage($client,"addwallet $wallet->{wallet} $name")
  }
  if (-e 'addressbook.fcc') {
    my $cont=gfio::content('addressbook.fcc');
    my @lines=split(/\n/,$cont);
    foreach my $line (@lines) {
      wsmessage($client,"adrbook $line")
    }
  }
}

sub refreshnodelist {
  if ($FORCENODE) { return }
  print " * Refreshing node-list\n";
  my $req=gclient::website("$FCCSERVER/?nodelist");
  @NODES=split(/ /,$req->{content}); my $nc=1+$#NODES;
  if (!$nc) {
    print "The core is exhausted.. quitting.\n"; exit
  }  
  $NODENR=0
}

sub connecttonode {
  my ($client) = @_;
  if ($client->{fcc}{reconnect} && (time < $client->{fcc}{reconnect})) { return }
  $client->{fcc}{reconnect}=time+10;
  my ($ip,$port);
  my ($nip,$nport);
  if ($FORCENODE) {
    ($ip,$port) = split(/\:/,$FORCENODE)
  } else {
    ($ip,$port) = split(/\:/,$NODES[$NODENR]);
  }
  if ($MINERNODE) {
    ($nip,$nport) = split(/\:/,$MINERNODE)
  }else{
    ($nip,$nport) = ($ip,$port)
  }
  status($client,"Connecting to node $ip:$port .. ");
  $NODENR++; if ($NODENR>$#NODES) { $NODENR=0 }
  $client->{fcc}{leaf}=startleaf($ip,$port,\&slavecall);
  if ($client->{fcc}{leaf}{error}) {
    print "Connection error to $ip:$port: $client->{fcc}{leaf}{error}\n";
    status($client,"<span style=\"color: red; font-weight: bold\">Connection error to $ip:$port: $client->{fcc}{leaf}{error}</span>");
  } else {    
    $client->{fcc}{leafid}=$client->{fcc}{leaf}{leafid};
    $client->{fcc}{leafip}=$nip; $client->{fcc}{leafport}=$nport;
    $client->{fcc}{connectnode}=0;
  }
}

sub calctotal {
  my ($client) = @_;
  my $total=0;
  foreach my $t (@{$client->{fcc}{trans}}) {
    $total+=$t->{total}
  }
  wsmessage($client,"transtotal ".fccstring($total))
}

sub getpubkey {
  my ($wallet) = @_;
  foreach my $w (@$WLIST) {
    if ($w->{wallet} eq $wallet) { return $w->{pubkey} }
  }
}

sub getprivkey {
  my ($wallet) = @_;
  foreach my $w (@$WLIST) {
    if ($w->{wallet} eq $wallet) { return $w->{privkey} }
  }
}

sub handle {
  my ($client,$command,$data) = @_;
  if ($command eq 'handshake') {
    print "Website connected\n";
  } elsif ($command eq 'input') {
    if ($data eq 'init') {
      if (!$INIT) {
        if (walletisencoded()) {
          wsmessage($client,"getpass"); return
        }
      }
      initwallet();
      addwallets($client);
      init($client);
      wsmessage($client,"actwal ".$WLIST->[0]{wallet});
      if($MINING && $MINERWALLET){
        wsmessage($client,"mining ".encode_json({wallet=>$MINERWALLET,size=>[$MINFHASH,$MAXFHASH],data=>$MINEDATA}));
      }
    } elsif ($data =~ /^pass (.+)$/) {
      my $password=$1;
      if (validwalletpassword($password)) {
        $PASS=$password;
        print "Password accepted\n";
        status($client,"Password accepted");
        initwallet();
        addwallets($client);
        init($client);
        wsmessage($client,"passok");
        wsmessage($client,"actwal ".$WLIST->[0]{wallet})
      } else {
        wsmessage($client,"passinvalid")
      }
    } elsif ($data =~ /^newpass (.+)$/) {
      $PASS=$1; savewallets($WLIST,$PASS);
      status($client,"Password is set")
    } elsif ($data eq 'createwallet') {
      if (!$INIT) { return }
      my $wallet=newwallet();
      push @$WLIST,$wallet;
      savewallet($wallet,$PASS);
      wsmessage($client,"addwallet $wallet->{wallet}")      
    } elsif ($data =~ /^balance (.+)$/) {
      my $wallet=$1;
      push @{$client->{fcc}{jobs}},{ command => 'balance', wallet => $wallet }
    } elsif ($data =~ /^setname ([^\s]+) (.+)$/) {
      my $wallet=$1; my $name=$2;
      foreach my $w (@$WLIST) {
        if ($w->{wallet} eq $wallet) {
          $w->{name}=$name; savewallets($WLIST); last
        }
      }
    } elsif ($data =~ /^delwallet (.+)$/) {
      my $wallet=$1; my $NWL=[];
      foreach my $w (@$WLIST) {
        if ($w->{wallet} ne $wallet) { push @$NWL,$w }
      }
      $WLIST=$NWL;
      savewallets($WLIST);
      status($client,"Wallet $wallet deleted")      
    } elsif ($data =~ /^adrbook ([^\s]+) (.+)$/) {
      my $wallet=$1; my $name=$2;
      if (validwallet($wallet)) {
        if (-w 'addressbook.fcc') {
          gfio::append('addressbook.fcc',"\n$wallet $name")
        } else {
          gfio::create('addressbook.fcc',"$wallet $name")
        }
        status($client,"Added '$name' to addressbook");
        wsmessage($client,"adrbook $wallet $name")
      } else {
        wsmessage($client,"transerr Not added: Invalid wallet")
      }
    } elsif ($data =~ /^chadrbook ([^\s]+) (.+)$/) {
      my $wallet=$1; my $name=$2;
      if (!defined $name) { $name='' }
      my $data=gfio::content('addressbook.fcc');
      my @alist=split(/\n/,$data); my @out=();
      foreach my $entry (@alist) {
        my ($wal,@nlist) = split(/ /,$entry);
        if ($wal eq $wallet) {
          push @out,"$wal $name"
        } else {
          push @out,$entry
        }
      }
      gfio::create('addressbook.fcc',join("\n",@out))
    } elsif ($data =~ /^deladrbook (.+)$/) {
      my $wallet=$1;
      my $data=gfio::content('addressbook.fcc');
      my @alist=split(/\n/,$data); my @out=();
      foreach my $entry (@alist) {
        my ($wal,@nlist) = split(/ /,$entry);
        if ($wal ne $wallet) {
          push @out,$entry
        }
      }
      gfio::create('addressbook.fcc',join("\n",@out))
    } elsif ($data =~ /^checktrans ([^\s]+) ([^\s]+) (.+)/) {
      my $wallet=$1; my $amount=$2; my $fee=$3;
      if (!validwallet($wallet)) {
        wsmessage($client,"transerr Invalid wallet given for recipient")
      } elsif (($amount !~ /^[0-9]+$/) && ($amount !~ /^[0-9]+\.?[0-9]+$/)) {
        wsmessage($client,"transerr Invalid syntax for amount given")        
      } elsif (($fee !~ /^[0-9]+$/) && ($fee !~ /^[0-9]+\.?[0-9]+$/)) {
        wsmessage($client,"transerr Invalid syntax for fee given")
      } elsif ($amount == 0) {
        wsmessage($client,"transerr Amount must be larger then zero")        
      } elsif ($fee*100 < $MINIMUMFEE) {
        my $minfee=$MINIMUMFEE/100;
        wsmessage($client,"transerr The minimum fee is $minfee\%")
      } elsif ($fee>655.35) {
        wsmessage($client,"transerr The fee cannot be above 655.35%")
      } else {
        $TRANSCOUNT++; my $doggyfee=int($fee*100);
        $amount=fccstring($amount);
        $fee=calcfee($amount,$fee);
        my $total=fccstring($amount + $fee);
        wsmessage($client,"transok $TRANSCOUNT $amount $fee $total");
        push @{$client->{fcc}{trans}},{ 
          nr => $TRANSCOUNT, wallet => $wallet, amount => $amount, doggyfee => $doggyfee, fee => $fee, total => $total 
        };
        calctotal($client)
      }
    } elsif ($data =~ /^deltrans ([0-9]+)$/) {
      my $delnr=$1; my $cnt=0;
      foreach my $t (@{$client->{fcc}{trans}}) {
        if ($t->{nr} == $delnr) {
          splice(@{$client->{fcc}{trans}},$cnt,1); last
        }
        $cnt++
      }
      calctotal($client)
    } elsif ($data =~ /^transfer ([^\s]+) (.+)$/) {
      my $wallet=$1; my $change=$2;
      my $outlist=[];
      foreach my $t (@{$client->{fcc}{trans}}) {
        push @{$outlist},{ wallet => $t->{wallet}, amount => $t->{amount}*100000000, fee => $t->{doggyfee} }
      }
      push @{$client->{fcc}{jobs}},{ command => 'transfer', pubkey => getpubkey($wallet), change => $change, outlist => $outlist };
      $client->{fcc}{pubkey}=getpubkey($wallet);
      $client->{fcc}{privkey}=getprivkey($wallet);
      $client->{fcc}{trans}=[];
    } elsif ($data =~ /startminer (.+)$/) {
      $MINERWALLET=$1;
      push @{$client->{fcc}{jobs}},{ command => 'startminer' }
    } elsif ($data =~ /stopminer/) {
      if ($MINING) {
        $MINER->closeleaf(); $MINING=0; $MINEDATA->{coincount}=0
      }
    } elsif ($data =~ /powerdown/) {
      wsmessage($client,"powerdownnow");
      if ($MINING) { $MINER->closeleaf(); $MINING=0; $MINEDATA->{coincount}=0 }
      $POWERDOWN=1;
    } elsif ($data =~ /^savechat ([^\s]+) ([^\s]+)$/) {
      my $scc=$1; my $scv=$2; my $scs=0;
      if(($scc eq 'nick')||($scc eq 'ident')||($scc eq 'auto')||($scc eq 'zoom')){
        if(!defined $NICKIDENT->{$PORT}){
          $NICKIDENT->{$PORT}={$scc=>$scv};
        } else {
          $NICKIDENT->{$PORT}{$scc}=$scv;
        }
        gfio::create("nickident.chat",encode_json($NICKIDENT))
      }
    }

  } elsif ($command eq 'error') {
    if ($client->{websockets}) {
      print "Error in website connection! $data\n";
      $SERVER->quit();
      exit
    }
  } elsif ($command eq 'quit') {
    if ($client->{websockets}) {
      quitleaf($client);
      print "Lost connection to website! Reload website or press CNTRL C\n";
    }
  } elsif ($command eq 'ready') {
    # a very tiny httpd ;)
    my $uri=$client->{httpheader}{uri};
    my @out=(gserv::httpresponse(200));
    push @out,"Host: ".$SERVER->{server}{host}.":".$SERVER->{server}{port};
    push @out,"Access-Control-Allow-Origin: *";
    push @out,"Server: FCC-Private Wallet Server 1.0";
    push @out,"Date: ".fcctimestring();
    if ($uri eq '/') {
      burstfile($client,'wallet.htm','text/html',1,@out);
    } elsif ($uri eq '/wallet.js') {
      burstfile($client,'wallet.js','text/javascript',1,@out);
    } elsif ($uri eq '/wallet.css') {
      burstfile($client,'wallet.css','text/css',1,@out);
    } elsif ($uri =~ /image\/(.+)$/) {
      burstfile($client,"image/$1",$1 =~ /gif$/ ? 'image/gif':'image/png',0,@out);
    } else {
      $out[0]=gserv::httpresponse(404);
      my $hdata=join("\r\n",@out)."\r\n\r\n";
      gserv::burst($client,\$hdata);      
    }
    $client->{killafteroutput}=1
  }
  usleep($MINING ? 100:10000);
}

sub burstfile {
  my($client,$file,$meme,$filter,@out)=@_;
  my $data=($filter ? filtervars(gfio::content($file)) : gfio::content($file));
  push @out,"Content-Type: $meme";
  push @out,"Content-Length: ".length($data);
  my $hdata=join("\r\n",@out)."\r\n\r\n";
  $data=$hdata.$data;
  gserv::burst($client,\$data);
  return @out
}

sub filtervars {
  my($data)=@_;
  $data =~ s/\$PORT/$PORT/gs;

  if(defined $NICKIDENT->{$PORT} && defined $NICKIDENT->{$PORT}{nick}) {
    $data =~ s/\$NICK/$NICKIDENT->{$PORT}{nick}/gs;
  } else {
    $data =~ s/\$NICK//gs;
  }

  if (defined $NICKIDENT->{$PORT} && defined $NICKIDENT->{$PORT}{ident}) {
    $data =~ s/\$IDENT/$NICKIDENT->{$PORT}{ident}/gs;
  } else {
    $data =~ s/\$IDENT//gs;
  }

  if (defined $NICKIDENT->{$PORT} && $NICKIDENT->{$PORT}{auto}) {
    $data =~ s/\$AUTOSTART/openchat();/gs;
    $data =~ s/\$CHATAUTO/checked/gs;
  } else {
    $data =~ s/\$AUTOSTART//gs;
    $data =~ s/\$CHATAUTO//gs;
  }

  my $zm=100; if (defined $NICKIDENT->{$PORT} && $NICKIDENT->{$PORT}{zoom}) { $zm=$NICKIDENT->{$PORT}{zoom} }
  my @zo=();
  my @zc=();
  for my $z (500,400,300,250,200,175,150,125,120,110,100,90,80,75,70,60,50,40,30,25,20,15,10,5) {
    my $s=$z/100;
    push @zo, "<option value='$z'".($z==$zm ? ' selected':'').">$z %</option>";
    push @zc, ".zm$z { -ms-zoom: $s; -moz-transform: scale($s); -o-transform: scale($s); -webkit-transform: scale($s); -moz-transform-origin: 0 0; -o-transform-origin: 0 0; -webkit-transform-origin: 0 0; }"
  }
  my $zop=join('',@zo);   $data =~ s/\$ZOOMOPTION/$zop/gs;
  my $zcss=join("\n",@zc); $data =~ s/\$ZOOMCSS/$zcss/gs;

  return $data
}


sub status {
  my ($client,$txt) = @_;
  if (!$txt) { $txt="ERROR???" }
  wsmessage($client,"status $txt")
}

sub loop { }

sub handlecall {
  my ($client,$leaf,$command,$data) = @_;
  if (!$client->{fcc} || !$client->{fcc}{leafid} || !$leaf->{leafid}) { return }
  if ($client->{fcc}{leafid} == $leaf->{leafid}) {
    if ($command eq 'error') {
      if(ref($data) eq 'HASH' && $data->{message} && $data->{error}){
        print "Error '$data->{message}': $data->{error}\n";
        status($client,"<span style=\"color: red; font-weight: bold\">Error '$data->{message}': $data->{error}</span>");
      }else{
        print "Error '$data'\n";
      }
      $client->{fcc}{connectnode}=1;
      refreshnodelist();
    } elsif (($command eq 'disconnect') || ($command eq 'terminated')) {
      $MINERDISCON=1;
      $MINING=0;
      status($client,"<span style=\"color: red; font-weight: bold\">Disconnected from node.. Reconnecting to the FCC-core..</span>");
      $client->{fcc}{connectnode}=1;
      refreshnodelist();
    } elsif ($command eq 'response') {
      $client->{fcc}{leafready}=1;
      status($client," * Connected to node $data->{node} running FCC v$data->{version}")
    } elsif ($command eq 'balance') {
      my $balance=fccstring($data->{balance}/100000000);
      wsmessage($client,"balance $balance $data->{wallet}")
    } elsif ($command eq 'sign') {
      my $signature=octhex(Crypt::Ed25519::sign($data->{data},hexoct($client->{fcc}{pubkey}),hexoct($client->{fcc}{privkey})));
      $leaf->sign($data->{transid},$signature)
    } elsif ($command eq 'transstatus') {
      if ($data->{status} && ($data->{status} eq 'success')) {
        status($client,"<span style=\"color: darkgreen; font-weight: bold\">Transaction successfully processed</span>");
        push @{$client->{fcc}{jobs}},{ command => 'balance', wallet => $data->{wallet} }
      } elsif ($data->{error}) {
        status($client,"<span style=\"color: red; font-weight: bold\">Transaction refused: $data->{error}</span>")
      } else {
        status($client,"Transaction succesfully sent under id '$data->{transhash}'")
      }
    }
  }
}

sub slavecall {
  my ($leaf,$command,$data) = @_;
  if (!$data || (ref($data) ne 'HASH')) { error("No data HASHREF given from leaf! command = $command") }
  broadcastfunc($SERVER,\&handlecall,@_)
}

sub slaveminercall {
  my $log="coinbase.$PORT.log";
  my ($leaf,$command,$data) = @_;
  if ($data && $data->{error}) {
    print " <Node] $command : $data->{error}\n";
  }
  if (!$data || (ref($data) ne 'HASH')) { error("No data HASHREF given from leaf! command = $command") }
  if (!$data->{message}) { $data->{message}=$command }
  if (!$data->{error}) { $data->{error}="OK" }
  if ($command eq 'error') {
    print "Miner Error '$data->{message}': $data->{error}\n";
    wsmessage($leaf->{client},"miner <span style=\"color: red; font-weight: bold\">Error '$data->{message}': $data->{error}</span>");
#    wsmessage($leaf->{client},"minerstop");
    $MINERDISCON=1;
    $MINING=0
  } elsif (($command eq 'disconnect') || ($command eq 'terminated')) {
    if ($MINING) {
      my $mstr=time." stopped $MINEDATA->{coincount} $MINEDATA->{diff}\n";
      if (-e $log) { gfio::append($log,$mstr) } else { gfio::create($log,$mstr) }
      print "Miner Stopped '$data->{message}': $data->{error}\n";
      wsmessage($leaf->{client},"miner <span style=\"color: red; font-weight: bold\">Terminated '$data->{message}': $data->{error}</span>");
#      wsmessage($leaf->{client},"minerstop");
      $MINERDISCON=1;
      $MINING=0
    }
  }
  if ($command eq 'mine') {
    if(!defined $data->{init}){ $data->{init}="" }
    if (!$MINING || ($data->{coincount} > $MINEDATA->{coincount})) {
      print "miner New challenge: Coincount = $data->{coincount} Difficulty = $data->{diff} Reward = $data->{reward} Len = $data->{length} Hints = $data->{hints} eHints = $data->{ehints} Init = $data->{init}\n";
      my $mstr=time." coinbase $data->{coincount} $data->{diff}\n";
      if (-e $log) { gfio::append($log,$mstr) } else { gfio::create($log,$mstr) }
      if (($data->{coincount} > $MINEDATA->{coincount}) && $MINER->{client}) {
        wsmessage($MINER->{client},"miner New challenge: Coincount = $data->{coincount} Difficulty = $data->{diff} Reward = $data->{reward} Len = $data->{length} Hints = $data->{hints} eHints = $data->{ehints} Init = $data->{init}")
      }else{
        wsmessage($MINER->{client},"miner Next challenge: Coincount = $data->{coincount} Difficulty = $data->{diff} Reward = $data->{reward} Len = $data->{length} Hints = $data->{hints} eHints = $data->{ehints} Init = $data->{init}")
      }
      challenge($data);
    }
  } elsif ($command eq 'solution') {
    my $mstr=time." solution $MINEDATA->{coincount} $MINEDATA->{diff}\n";
    if (-e $log) { gfio::append($log,$mstr) } else { gfio::create($log,$mstr) }
    print " *** Found solution!! Earned FCC ".extdec($MINEDATA->{reward} / 100000000)." ***\n";
    if ($MINER->{client}) {
      wsmessage($MINER->{client},"miner <span style=\"color: darkgreen; font-weight: bold\">Found solution!! Earned FCC ".extdec($MINEDATA->{reward} / 100000000)."</span>");
      my $ctm=gettimeofday();
      push @{$MINER->{client}{fcc}{jobs}},{ command => 'balance', wallet => $MINERWALLET, time => $ctm }
    }
  }
}

# EOF (C) 2018 Chaosje
