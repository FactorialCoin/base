#!/usr/bin/perl -w

package gserv;

######################################################################
#                                                                    #
#          Round Robin Server                                        #
#           - websockets, telnet, http, raw, IceCast                 #
#           - SSL support                                            #
#           - fully bidirectional non-blocking, all systems          #
#                                                                    #
#          (C) 2018 Domero                                           #
#          ALL RIGHTS RESERVED                                       #
#                                                                    #
#      Events:                                                       #
#                                                                    #
#      connect: an uninitialized client has connected on TCP/IP      #
#      handshake: a client has performed an initializing handshake   #
#      input: a client received a message from the server            #
#      quit: a client has quit the connection                        #
#      error: a client has encountered an error                      #
#      telnet: a client is running under telnet                      #
#      http: a client is running under HTTP                          #
#      websockets: a client is running under WebSockets              #
#      sent: a block data has finished sending to the server         #
#                                                                    #
#      Errors:                                                       #
#                                                                    #
#         1 Server has been terminated                               #
#         2 Ping Timeout                                             #
#       106 Client aborted connection                                #
#       108 Client forcebly closed connection                        #
#       110 Connection timed out                                     #
#       113 No route to host                                         #
#       130 Killed by interrupt                                      #
#       400 Bad request                                              #
#       405 Method not allowed                                       #
#       408 Request timeout                                          #
#       426 Upgrade required                                         #
#      1000 Process killed by administrator                          #
#      1002 Protocol error                                           #
#      1009 Insufficient storage                                     #
#                                                                    #
######################################################################

use strict;
use warnings;
use Socket;
use IO::Handle;
use IO::Select;
use IO::Socket::SSL;
use POSIX qw(:sys_wait_h EAGAIN EBUSY);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Time::HiRes qw(usleep gettimeofday);
use Digest::SHA1 qw(sha1);
use Digest::MD5 qw(md5);
use utf8;
use gerr qw(error);
use gpost 1.2.1;
use HTTP::Date;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '4.3.1';
@ISA         = qw(Exporter);
@EXPORT      = qw(wsmessage);
@EXPORT_OK   = qw(prtm localip init start wsmessage out burst takeloop broadcast wsbroadcast broadcastfunc httpresponse);

my $CID = 0;
my $SSLPATH='/etc/letsencrypt/live';
my $SSLCERT='cert.pem';
my $SSLKEY='privkey.pem';
my $SSLCA='chain.pem';

1;

sub setssl {
  my ($path,$cert,$key,$ca) = @_;
  if ($path) { $SSLPATH=$path }
  if ($cert) { $SSLCERT=$cert }
  if ($key) { $SSLKEY=$key }
  if ($ca) { $SSLCA=$ca }
}

sub init {
  my ($clienthandle,$clientloop,$ssldomain) = @_;
  if (ref($clienthandle) ne 'CODE') {
    error "Eureka server could not initialize: No clienthandle given."
  }
  if ((defined $clientloop) && (ref($clientloop) ne 'CODE')) {
    error "Eureka server could not initialize: No clientloop-handle given."
  }
  my $self = {
    isserver => 1,
    name => "Eureka Server $VERSION by Chaosje (C) 2018 Domero",      # Server name
    version => $VERSION,                     # server version
    ssl => defined $ssldomain && $ssldomain, # Use SSL
    ssldomain => $ssldomain,                 # SSL keys will be found in $SSLPATH/ssldomain
    verbose => 1,                            # Output to STDOUT
    debug => 0,                              # verbose everything
    websocketmode => 0,                      # Only allow websocket connections
    linemode => 0,                           # Split lines even in raw mode
    killhttp => 0,                           # kill http-clients automatically when done with output
    maxdatasize => 52428800,                 # 50MB, Maximum data-size which may be received in one package (websockets) (must be more than 65534)
    pingtime => 30,                          # seconds on ilde to check we're still alive
    pingtimeout => 5,                        # seconds for clients to respond on ping with pong before ping-timeout
    verbosepingpong => 0,                    # Verbose ping/pong requests and responses
    verboseheader => 0,                      # Verbose the HTTP-header
    timeout => 10,                           # Seconds to idle to server before timeout (0=unlimited)
    buffersize => 1024,                      # Bytes to read from socket at loop-passes
    server => {
      host => localip(),                     # Our IP-addres
      loopwait => 1000,                      # Main wait-time if idle in nanoseconds (1000000/number of user to expect)
      port => 12345,                         # port to connect to
      clienttimeout => 20,                   # time the server will respond to clients, 0 = no timeout
      starttime => 0,                        # time in usec when server was started.
      running => 0,                          # Is the server running?
    },
    userlist => {},                          # allowed logins
    clients => [],                           # connected clients for round robin
    current => 0,                            # current executing process
    numclients => 0,                         # number of connected clients
    maxclients => 1000,                      # maximum connections allowed (0 = unlimited)
    allowedip => [
      '10.*',      
      '192.168.*',      
      '127.0.0.1',
    ],                                       # allowed IP's, leave empty ([]) for all.
    blockedip => [],                         # the firewall
    idletimeout => 0,                        # kills a client on X seconds of inactivity (0 = no timeout)
    clienthandle => $clienthandle,           # handle called whenever there is a client-method
    clientloop => $clientloop,               # handle called on every processing loop
    activeclient => undef,                   # set when a process is in active handling to signal from outside
  };
  bless($self);
  return $self
}

sub start {
  my ($self,$autoloop,$servloop) = @_;
  if ($servloop && (ref($servloop) ne 'CODE')) { error "GServ.Start: ServLoop is not a coderef" }
  $self->{servloop}=$servloop; my $err="";
  if ($self->{debug}) { $self->{verbosepingpong}=1 }
  if ($self->{maxdatasize}<65535) { $self->{maxdatasize}=65535 } # (websockets) allow a minimum of 64Kb data packets.
  
  # Auto flush and select Console
  select(STDOUT); $|=1;

  # Setup TCP/IP & SSL
  my $proto = getprotobyname('tcp');
  if ($self->{ssl}) {
    $self->{sslcert}="$SSLPATH/$self->{ssldomain}/$SSLCERT";
    if (!-e $self->{sslcert}) {
      print STDOUT "SSL-certificate '$self->{sslcert}' does not exist"; return $self
    }
    $self->{sslkey}="$SSLPATH/$self->{ssldomain}/$SSLKEY";
    if (!-e $self->{sslkey}) {
      print STDOUT "SSL-key '$self->{sslkey}' does not exist"; return $self
    }
    $self->{sslca}="$SSLPATH/$self->{ssldomain}/$SSLCA";
    if (!-e $self->{sslca}) {
      print STDOUT "SSL-ca '$self->{sslca}' does not exist"; return $self
    }
  }

  # create a socket, make it reusable, set buffers
  socket($self->{server}{socket}, PF_INET, SOCK_STREAM, $proto) or $err="Can't open socket: $!";
  if ($err) { $self->{error}=$err; return $self }
  setsockopt($self->{server}{socket}, SOL_SOCKET, SO_REUSEADDR, 1) or $err="Can't set socket: $!";
  if ($err) { $self->{error}=$err; return $self }
  setsockopt($self->{server}{socket}, SOL_SOCKET, SO_RCVBUF, 1<<23) or $err="Can't set socket's receive buffer: $!";
  if ($err) { $self->{error}=$err; return $self }
  setsockopt($self->{server}{socket}, SOL_SOCKET, SO_SNDBUF, 1<<23) or $err="Can't set socket's send buffer: $!";
  if ($err) { $self->{error}=$err; return $self }

  # grab a port on this machine 
  my $paddr = sockaddr_in($self->{server}{port}, INADDR_ANY);

  # bind to a port, then listen 
  bind($self->{server}{socket}, $paddr) or $err="Can't bind to address $paddr: $!"; 
  if ($err) { $self->{error}=$err; return $self }
  listen($self->{server}{socket}, SOMAXCONN) or $err="Server can't listen: $!";
  if ($err) { $self->{error}=$err; return $self }

  # set autoflush on
  $self->{server}{socket}->autoflush(1);

  # set server accept to non-blocking, otherwise the server will block waiting
  IO::Handle::blocking($self->{server}{socket},0);
  if ($^O =~ /win/i) {
    my $nonblocking=1;
    ioctl($self->{server}{socket}, 0x8004667e, \$nonblocking);
  } 

  $self->{server}{running}=1;

  $self->{start}=gettimeofday();

  if ($self->{verbose}) {
    print STDOUT prtm(),"Server '$self->{name}' started on port $self->{server}{port}\n"
  }
  $self->{loopmode}=$autoloop;
  if ($autoloop) {
    while ($self->{server}{running}) {
      $self->takeloop;
    }
  }
  return $self
}

sub outsock {
  my ($self,$client,$data) = @_;
  if (!$self->{isserver}) { error "Design change version 4! $self->outsock demands the server! Use out or burst instead" }
  my $sock=$client->{socket};
  my $func=$self->{clienthandle};
  if (!$sock) { $client->{killme}=1; return }
  if (!IO::Socket::connected($sock)) { $client->{killme}=1; return }
  if ($client->{ssl}) {
    my $len=length($data);
    if ($len<=16384) {
      syswrite($sock,$data,$len); return
    }
    my $pos=0; my $sz=16384; 
    while ($pos<$len) {
      if ($pos+$sz>$len) { $sz=$len-$pos }
      syswrite($sock,substr($data,$pos,$sz),$sz);
      $pos+=$sz
    }
  } else {
    print $sock $data
  }
  my $len=length($data); $client->{bytessent}+=$len;
  &$func($client,'sent',$len);
}

sub takeloop {
  my ($self) = @_;
  if (!$self->{server}{running}) { return }
  my $client;
  if (($self->{numclients}<$self->{maxclients}) || ($self->{maxclients} == 0)) {
    my $client_addr = accept($client, $self->{server}{socket});
    if ($client_addr) {
      
      # :) Let's help the patient
      
      # make sure binmode
      binmode($client);

      # Autoflush must be on
      $client->autoflush(1);

      # Non-blocking for UNIX. Won't harm other systems
      $client->blocking(0);
      my ($port,$iph) = sockaddr_in($client_addr); 
      my $ip = inet_ntoa($iph);
      my $socketerr=0;
      if ($^O =~ /win/i) {
        # Non-blocking for Windows. _IOW('f', 126, u_long)
        my $nonblocking = 1; ioctl($client, 0x8004667e, \$nonblocking);
      } else {
        # And just to make sure it is non-blocking a third method (nobody knows all systems)
        my $flags = fcntl($client, F_GETFL, 0) or $socketerr=1;
        $flags = fcntl($client, F_SETFL, $flags | O_NONBLOCK) or $socketerr=1;
        if ($socketerr) {
          print STDOUT "ERROR [$ip\:$port] Cannot set non-blocking mode on socket!\n";
          close($client)
        }
      }    

      # find out who connected 
      my $valid=0;
      foreach my $aip (@{$self->{allowedip}}) {
        if ($aip eq '*') { $valid=1; last }
        if ($ip =~ /$aip/) { $valid=1 }
      }
      foreach my $bip (@{$self->{blockedip}}) {
        if ($ip =~ /$bip/) { $valid=0 }
      }
      if (!$valid) {
        if ($self->{verbose}) {
          print STDOUT "ILLEGAL ACCESS: $ip\:$port\n"
        }  
        close($client)        
      } elsif (!$socketerr) {  
        my $tm=gettimeofday();
        my $host='localhost';
        if ($ip ne '127.0.0.1') {
          $host=gethostbyaddr($iph, AF_INET);
          if (!$host) {
            if (($ip =~ /^192\.168/) || ($ip =~ /^10\.0\.0/)) { $host='LAN' }
            else { $host='Unknown' }
          }
        }

        # SSL
        my $sslerr=0;
        if ($self->{ssl}) {
          IO::Socket::SSL->start_SSL($client,
            SSL_server => 1,
            SSL_cert_file => $self->{sslcert},
            SSL_key_file => $self->{sslkey},
            SSL_ca_file => $self->{sslca},
          ) or $sslerr=1;
          if ($sslerr) { print STDOUT prtm(),"Failed to ssl handshake: $SSL_ERROR\n"; close($client) }
        }

        if (!$sslerr) {
          $CID++;
          my $cdata = {
            id => $CID,
            socket => $client,
            ssl => $self->{ssl},
            handle => $client_addr,
            host => $host,
            ip => $ip,
            iphandle => $iph,
            port => $port,
            serverport => $self->{server}{port},
            start => $tm,
            last => $tm,
            quit => 0,
            keepalive => 1,
            pingtime => $self->{pingtime},
            pingtimeout => $self->{pingtimeout},
            lastping => $tm,
            pingsent => 0,
            pings => {},
            telnet => 0,
            httpmode => 0,
            httpreadheader => 0,
            httpheader => {},
            websockets => 0,
            icecast => 0,
            iceversion => "",
            mountpoint => "",
            killme => 0,
            killafteroutput => 0,
            init => 1,
            verbosepingpong => $self->{verbosepingpong},
            outputmode => 0,
            outputbuffer => "",
            outputpointer => 0,
            outputlength => 0,
            httpreadpost => 0,
            postdata => '',
            post => {},
            selector => IO::Select->new($client),
            bytessent => 0,
            bytesreceived => 0,
            bustmode => 0,
            wsbuffer => "",
            wsdata => "",
            wstype => "",
          };
          push @{$self->{clients}},$cdata;
          $self->{numclients}++;
          if ($self->{verbose}) {
            print STDOUT prtm(),"JOIN $ip\:$port ($host)\n"
          }
          my $func=$self->{clienthandle};
          &$func($cdata,'connect')
        }
      }
    }
  }
  if ($self->{numclients}) {
    # We probably got work to do!
    my $start=gettimeofday();
    $self->{deleteflag}=0;
    $self->handleclient();
    $self->{activeclient}=undef;
    if (!$self->{deleteflag}) { $self->{current}++; }
    if ($self->{current}>=$self->{numclients}) {
      $self->{current}=0
    }
    my $end=gettimeofday();
    if (($end<$start) || ($end-$start<$self->{server}{loopwait})) {
      my $dtm=$self->{server}{loopwait}-($end-$start);
      usleep($dtm)
    }
  } else {
    # Get some sleep
    usleep($self->{server}{loopwait})
  }
  if ($self->{servloop}) {
    my $caller=$self->{servloop};
    &$caller($self)
  }
}

sub loopall {
  my ($self) = @_;
  for (my $i=1;$i<=$self->{numclients};$i++) {
    $self->takeloop()
  }
}

sub removeclient {
  my ($self) = @_;
  if ($self->{numclients}) {
    $self->{clients}[$self->{current}]=undef;
    splice(@{$self->{clients}},$self->{current},1);
    $self->{numclients}--;    
  }
}

sub deleteclient {
  my ($self,$client,$msg) = @_;
  my $ip='closed'; my $port='closed';
  if ($client) {
    $ip=$client->{ip}; $port=$client->{port};
    if (!$client->{closed}) { 
      $client->{closed}=1;
      if ($client->{selector}) {
        $client->{selector}->remove($client->{socket});
      }
      # Signal WebSocket server to delete client and round things up.
      if ($client->{ssl}) {
        $client->{socket}->close(SSL_no_shutdown => 1)
      } else {
        shutdown($client->{socket},2); close($client->{socket}); 
      }
    }
  }
  if ($self->{verbose}) {
    # my $err=gerr::trace(); print "$err\n";
    print STDOUT prtm(),"QUIT $ip\:$port\n"
  }
  my $func=$self->{clienthandle};
  &$func($client,'quit',$msg);
  $self->removeclient();
  $self->{deleteflag}=1;
}

sub wschardecode {
  my ($client,$key)=@_;
  my $pos=$client->{wsbufferread} & 3;
  return chr($key ^ $client->{wsmask}[$pos]);
}

sub wsinput {
  # WebSockets hybi06 - v13 - Not the easiest protocol ever..
  # RFC 6455
  my ($self,$client,$data) = @_;
  my $func=$self->{clienthandle};
  if (defined $data) { $client->{wsbuffer}.=$data }
  my $blen=length($client->{wsbuffer});
  if ($blen < 2) { return }
  #print " << INPUT [$len] $self->{host}:$self->{port}     \n";
  my $firstchar=ord(substr($client->{wsbuffer},0,1));
  my $secondchar=ord(substr($client->{wsbuffer},1,1));
  my $type=$firstchar & 15;
  my $final=$firstchar & 128;
  my $continue=0;
  my $blocktype;
  if ($type == 0) { $continue=1 }
  elsif ($type == 1) { $blocktype='text' }
  elsif ($type == 2) { $blocktype='binary' }
  elsif ($type == 8) { $blocktype='close' }
  elsif ($type == 9) { $blocktype='ping' }
  elsif ($type == 10) { $blocktype='pong' }
  else {
    &$func($client,'error',"Invalid WS frame type: $type"); return
  }
  if (!$continue) { $client->{wstype}=$blocktype }
  my $mask=$secondchar & 128;
  if (!$mask) {
    # RFC 6455 - Data MUST be masked!
    &$func($client,'error',"Non-Masked data found in input from client"); return
  }
  my $len=$secondchar & 127; my $offset=2;
  if ($len==126) {
    if ($blen < 4) { return }
    $len=ord(substr($client->{wsbuffer},2,1));
    $len=($len<<8)+ord(substr($client->{wsbuffer},3,1));
    $offset=4
  } elsif ($len==127) {
    if ($blen < 10) { return }
    $len=0;
    for (my $p=0;$p<8;$p++) {
      $len=($len<<8)+ord(substr($client->{wsbuffer},$offset,1));
      $offset++
    }
  }
  if ($blen<$offset+4+$len) { return }
  # YES! We got a package!
  my @mask=();
  for (my $m=0;$m<4;$m++) {
    push @mask,ord(substr($client->{wsbuffer},$offset,1)); $offset++
  }
  my $fdata=""; my $mp=0;
  for (my $i=0;$i<$len;$i++) {
    $fdata.=chr(ord(substr($client->{wsbuffer},$offset,1)) ^ $mask[$mp]); 
    $offset++; $mp=($mp+1) & 3
  }
  $client->{wsdata}.=$fdata;
  if ($final) {
    $self->handlews($client);
    $client->{wsdata}=""
  }
  $client->{wsbuffer}=substr($client->{wsbuffer},$offset);
  if (length($client->{wsbuffer})) { $self->wsinput($client) }
}

sub handlews {
  my ($self,$client) = @_;
  my $func=$self->{clienthandle};
  if (length($client->{wsdata}) > $self->{maxdatasize}) { &func($client,'error',"1009 Datasize too large") }
  if ($client->{wstype} eq 'ping') {
    if ($client->{verbosepingpong}) {
      print STDOUT prtm(),"*< PING $client->{ip}\:$client->{port}\n";
    }
    wsmessage($client,$client->{wsdata},'pong');
    $client->{lastping}=gettimeofday();
    $client->{pingsent}=0
  } elsif ($client->{wstype} eq 'pong') {
    if ($client->{verbosepingpong}) {
      print STDOUT prtm(),"*< PONG $client->{ip}\:$client->{port}\n";
    }
    if ($client->{pings}{$client->{wsdata}}) {
      delete $client->{pings}{$client->{wsdata}};
    }
    $client->{lastping}=gettimeofday();
    $client->{pingsent}=0
  } elsif ($client->{wstype} eq 'close') {
    $self->deleteclient($client,$client->{wsdata})
  } else {
    &$func($client,"input",$client->{wsdata})
  }
}

sub wsmessage {
  my ($client,$msg,$command) = @_;
  if ($client->{isserver}) { error "Version 3 Design change! wsmessage($client,$msg,$command)" }
  if (!defined($msg) && !defined($command)) { return }  
  if (!$command) { $command='text' }
  # print " >> $client->{ip}:$client->{port} $command $msg     \n";
  if (!$client || (ref($client) ne 'HASH') || $client->{killme} || $client->{closed} || $client->{dontsend}) { return }
  my $out=chr(129);
  if ($command eq 'binary') {
    $out=chr(130)
  } elsif ($command eq 'pong') {
    if ($client->{verbosepingpong}) {
      print STDOUT "*> PONG $client->{ip}\:$client->{port} $msg\n";
    }
    $out=chr(138);
    $client->{lastping}=gettimeofday();
    $client->{pingsent}=0
  } elsif ($command eq 'ping') {
    if ($client->{verbosepingpong}) {
      print STDOUT "*> PING $client->{ip}\:$client->{port} $msg\n";
    }
    $out=chr(137);
    $client->{pingsent}=0
  } elsif ($command eq 'close') {
    $out=chr(136);
    if (!$msg) { $msg="" }
    if ($msg =~ /^([0-9]+) (.+)/) {
      my $code=$1; my $txt=$2; utf8::encode($txt);
      $code=chr($code>>8).chr($code & 255);
      $msg=$code.$txt;
    } else {
      my $code=chr(1000>>8).chr(1000 & 255); utf8::encode($msg);
      $msg=$code.$msg
    }
  }
  my $len=length($msg);
  if ($len<126) {
    $out.=chr($len)
  } elsif ($len<65536) {
    $out.=chr(126);
    $out.=chr($len>>8).chr($len & 255)
  } else {
    $out.=chr(127);
    my $tout=chr(0)x8;
    my $p=7;
    while ($len>0) {
      my $val=$len & 255;
      substr($tout,$p,1,chr($val));
      $len>>=8; $p--;
      if ($p<0) { last } # 128 bit computers ;)
    }
    $out.=$tout;
  }
  out($client,$out.$msg)
}

sub decbin {
  # 32 bit decimal->string
  my ($dn) = @_; my $bs=""; my $cnt=4;
  while ($dn>0) {
    my $sn=$dn % 256; 
    $bs=chr($sn).$bs; 
    $dn>>=8; $cnt--;
  }
  $bs=(chr(0)x$cnt).$bs; 
  return $bs
}

sub out {
  my ($client,$data) = @_;
  if (!defined $data) { return }
  if ($client->{outputmode}) {
    $client->{outputbuffer}.=$data;
    $client->{outputlength}+=length($data);
  } else {
    $client->{outputmode}=1;
    $client->{outputbuffer}=$data;
    $client->{outputlength}=length($data);
    $client->{outputpointer}=0
  }
}

sub burst {
  # burst some output
  my ($client,$data) = @_;
  if (ref($data) ne "SCALAR") { error("Gserv.Burst: Design error, use \\\$data for much faster comunication!") }
  $client->{burstdata}=$data;
  $client->{burstlength}=length(${$data});
  $client->{burstpointer}=0;
  if ($client->{burstlength}) { $client->{burstmode}=1 }
}

sub makewshandshake {
  my ($key1,$key2,$key3) = @_;
  my $sum=md5(decbin($key1).decbin($key2).$key3);
  return $sum;
}

sub handleclient {
  my ($self) = @_;
  my $client=$self->{clients}[$self->{current}];
  my $ctm=gettimeofday();
  if ($client->{closed}) { $self->deleteclient($client) }
  $self->{activeclient}=$client;
  if ($client->{killme}) { $self->deleteclient($client); return }
  my $sock=$client->{socket};
  my $func=$self->{clienthandle};
  if (!$sock) { $self->deleteclient($client); return }
  if ($client->{burstmode}) {
    my @ready = $client->{selector}->can_write(0);
    my $canwrite=0;
    foreach my $handle (@ready) {
      if ($handle == $sock) {
        $canwrite=1; last
      }
    }
    if ($canwrite) {
      $client->{last}=$ctm;
      if ($client->{burstpointer} >= $client->{burstlength}) {
        $client->{burstmode}=0;
        &$func($client,"bursted");
        if ($client->{killafteroutput} || $client->{killme}) { $self->deleteclient($client) }
        return
      }
      my $sz=32768;
      if ($client->{burstpointer}+$sz > $client->{burstlength}) {
        $sz=$client->{burstlength}-$client->{burstpointer}
      }
      $self->outsock($client,substr(${$client->{burstdata}},$client->{burstpointer},$sz));
      $client->{burstpointer}+=$sz;
    }
    return
  }
  if ($self->{timeout}) {
    if ($client->{init}) {
      if ($client->{httpreadheader}) {
        if ($ctm-$client->{start}>$self->{timeout}) {
          $self->outsock($client,"HTTP/1.1 408 REQUEST TIMEOUT\r\n\r\n");
          &$func($client,'error',"408 Request Timeout");
          $self->deleteclient($client); return
        }
      }
    }
  }
  my $loopfunc=$self->{clientloop};
  if (defined $loopfunc) {
    if (defined &$loopfunc) {
      &$loopfunc($client)
    } else {
      error "Invalid loopfunction: $loopfunc"
    }
  }
  if ($client->{killme}) { $self->deleteclient($client); return }

  # WRITE
  if ($client->{outputmode}) {
    my @ready = $client->{selector}->can_write(0);
    my $canwrite=0;
    foreach my $handle (@ready) {
      if ($handle == $sock) {
        $canwrite=1; last
      }
    }
    if ($canwrite) { 
      $client->{last}=$ctm;
      if ($client->{outputpointer} >= $client->{outputlength}) {
        # we're done
        if ($client->{killafteroutput} || ($self->{killhttp} && $client->{httpmode})) {
          $self->deleteclient($client); return
        }
        $client->{outputmode}=0;
      }
      if ($client->{outputmode}) {
        my $sz=32768;
        if ($client->{outputpointer}+$sz > $client->{outputlength}) {
          $sz=$client->{outputlength}-$client->{outputpointer}      
        }
        $self->outsock($client,substr($client->{outputbuffer},$client->{outputpointer},$sz));
        $client->{outputpointer}+=$sz
      }
    } elsif ($client->{httpmode}) {
      # HTTP only needs to output at this stage
      return
    }
  }
  if (!$client->{outputmode}) {
    if ($client->{killme} || $client->{killafteroutput}) {
      $self->deleteclient($client); return
    }
    if ($client->{signalws}) {
      $client->{signalws}=0;
      &$func($client,'handshake','WebSockets v'.$client->{wsversion})
    }
  }

  # READ
  my @ready = $client->{selector}->can_read(0);
  my $canread=0;
  foreach my $handle (@ready) {
    if ($handle == $sock) {
      $canread=1; last     
    }
  }
  my $inbuf="";
  if ($canread) {
    if ($self->{ssl}) {
      sysread($sock,$inbuf,32768)
    } else {
      recv($sock,$inbuf,$self->{buffersize},0);
    }
    if ($inbuf eq "") {
      if (($! != EAGAIN) && ($! != EBUSY) && ($! != 10035)) { 
        # 10035 = WSAEWOULDBLOCK (Windows sucking non-blocking sockets)
        if ($!) {
          if ($self->{verbose}) {
            my $err=0+$!;
            print STDOUT prtm(),"ERROR $client->{ip}\:$client->{port} [$err] $!\n";
            $client->{dontsend}=1;
            &$func($client,'error',$err)
          }
          $self->deleteclient($client); return
        }  
      }
    }
  }  
  if ($inbuf ne "") {
    my $len=length($inbuf);
    &$func($client,'received',$len); $client->{bytesreceived}+=$len;
    if ($self->{debug}) {
      print STDOUT "INBUF: '$inbuf' ($len)\n";
    }
    if ($client->{init}) {
      if (ord(substr($inbuf,0,1))==255) {
        if ($self->{websocketmode}) {
          print STDOUT prtm(),"ERROR $client->{ip}\:$client->{port} [TELNET = NO WEBSOCKET CLIENT]\n";
          $self->outsock($client,"HTTP/1.1 400 BAD REQUEST\r\n\r\n");
          &$func($client,'error',"400 Bad Request");
          $self->deleteclient($client); return
        }
        $client->{telnet}=1;
        my $func=$self->{clienthandle};
        &$func($client,'telnet');
        # negate Telnet ident string
        $inbuf="";
        # Output human message
        $client->{keepalive}=1;
        $client->{init}=0;
        return
      } elsif ($inbuf =~ /^GET ([^\s]+) HTTP\/([0-1.]+)/i) {
        if ($self->{verboseheader}) { print STDOUT "GET $1 $2\n" }
        my $getstr=$1;
        $client->{httpmode}=1;
        $client->{httpreadheader}=1;
        $client->{httpheader}{version}=$2;
        $client->{httpheader}{method}='get';
        my ($uri,$cgi) = split(/\?/,$getstr);
        $client->{httpheader}{uri}=$uri;
        $client->{httpheader}{getdata}=$cgi;
      } elsif ($inbuf =~ /^POST ([^\s]+) HTTP\/([0-1.]+)/i) {
        if ($self->{verboseheader}) { print STDOUT "POST $1 $2\n" }
        $client->{httpmode}=1;
        $client->{httpreadheader}=1;
        $client->{httpheader}{uri}=$1;
        $client->{httpheader}{version}=$2;
        $client->{httpheader}{method}='post';
      } elsif ($inbuf =~ /^SOURCE (\/[^\s]+) ICE\/([0-9.]+)/i) {
        $client->{icecast}=1;
        $client->{httpreadheader}=1;
        $client->{mountpoint}=$1;
        $client->{iceversion}=$2
      } elsif ($self->{websocketmode}) {
        print STDOUT prtm(),"ERROR $client->{ip}\:$client->{port} [RAW = NO WEBSOCKET CLIENT]\n";
        $self->outsock($client,"HTTP/1.1 400 BAD REQUEST\r\n\r\n");
        &$func($client,'error',400);
        $self->deleteclient($client); return
      } else {
        &$func($client,'error',405); $self->deleteclient($client); return
      }
      $client->{init}=0;
    }
    $client->{last}=$ctm;
    if ($client->{websockets}) {
      $self->wsinput($client,$inbuf);
    } else {
      # print "* PROCESS ".length($inbuf)." *\n";
      if (!$client->{httpmode} && !$client->{telnet} && !$self->{linemode}) {
        &$func($client,'input',$inbuf); return
      }
      if ($client->{httpreadheader}) {
        my @hdat=split(/\r\n/,$inbuf,-1); my $cnt=0;
        foreach my $hline (@hdat) {
          $cnt++;
          if ($hline eq "") {
            if ($self->{verboseheader}) {
              print STDOUT "[HEADER END]\n"
            }
            $client->{httpreadheader}=0;
            $self->httphandshake($client);
            if ($client->{killme}) { $self->deleteclient($client); return }
            if ($client->{websockets}) { return }
            if ($client->{httpheader}{method} eq 'post') {
              # post data from now on!
              $client->{readpostdata}=1;
              $client->{postdatalength}=$client->{httpheader}{'content-length'} || 0;
              $client->{postdata}=join("\r\n",@hdat[$cnt..$#hdat]);
              $client->{postdatalength}-=length($client->{postdata});
              if ($client->{postdatalength} < 0) {
                # http post exploits
                $client->{postdata}=substr($client->{postdata},0,$client->{postdatalength});
                $client->{postdatalength}=0
              }
              if ($client->{postdatalength} == 0) {
                $client->{readpostdata}=0;
                  #foreach my $k (sort keys %{$client->{httpheader}}) {
                  #  print "$k => $client->{httpheader}{$k}\n"
                  #}
                $client->{post}=gpost::init($client->{httpheader}{'content-type'},$client->{postdata});
                &$func($client,"ready",'post'); 
              }
            } else {
              $client->{post}=gpost::init('get',$client->{httpheader}{getdata});
              &$func($client,"ready",'get')
            }
            last # prevent exploits, negate extra data
          } else {
            my ($key,$val) = split(/: /,$hline,2);
            if ((defined $key) && ($key ne "")) {
              if (!defined $val) { $val="" }
              else {
                $val =~ s/^[\s]+//; $val =~ s/[\s]+$//;
              }
              $client->{httpheader}{lc($key)}=$val;
              if ($self->{verboseheader}) {
                print STDOUT "[HEADER] '$key' => '$val'\n"
              }
            }
          }
        }
      } elsif ($client->{readpostdata}) {
        $client->{postdata}.=$inbuf;
        $client->{postdatalength}-=length($inbuf);
        if ($client->{postdatalength} < 0) {
          # http post exploits
          $client->{postdata}=substr($client->{postdata},0,$client->{postdatalength});
          $client->{postdatalength}=0
        }
        if ($client->{postdatalength} == 0) {
          $client->{readpostdata}=0;
          $client->{post}=gpost::init($client->{httpheader}{'content-type'},$client->{postdata});
          &$func($client,"ready",'post');
        }
      }
      if ($client->{killme}) { $self->deleteclient($client); return }
      if (!$client->{readpostdata} && !$client->{httpmode} && !$client->{websockets}) {
        my @lines = split(/\n/,$inbuf);
        foreach my $line (@lines) {
          $line =~ s/\r//g;
          &$func($client,'input',$line);
          if ($client->{killme}) { $self->deleteclient($client); return }
        }
      }  
    }
  } elsif ($self->{idletimeout} && ($ctm-$client->{last}>=$self->{server}{clienttimeout})) { 
    $self->outsock($client,"HTTP/1.1 408 REQUEST TIMEOUT\r\n\r\n");
    &$func($client,'error',"408 Request Timeout");
    $self->deleteclient($client); return
  } elsif ($self->{server}{clienttimeout} && (!$client->{keepalive} && (gettimeofday()-$client->{last}>=$self->{server}{clienttimeout}))) {
    $self->outsock($client,"HTTP/1.1 408 REQUEST TIMEOUT\r\n\r\n");
    &$func($client,'error',"408 Request Timeout");
    $self->deleteclient($client); return
  } elsif ($client->{websockets}) {
    if ($client->{pingtime}) {
      my $delta=0;
      if ($client->{pingsent}) {
        $delta=$ctm-$client->{pingsent};
        if ($delta>$client->{pingtimeout}) {
          if ($client->{killafteroutput}) {
            $self->deleteclient($client); return
          }
          # ping timeout
          wsmessage($client,"2 PING TimeOut","close");
          print STDOUT prtm(),">! PING TIMEOUT $client->{ip}\:$client->{port}\n";
          $client->{killafteroutput}=1;
          return
        }
      }
      $delta=$ctm-$client->{lastping};
      if ($delta>$client->{pingtime}) {
        # time to ping
        my $pingmsg='eureka'.int(rand(1000000)+100000);
        $client->{pings}{$pingmsg}=1;
        wsmessage($client,$pingmsg,'ping');
        if ($client->{verbosepingpong}) {
          print STDOUT prtm(),"> PING $client->{ip} $client->{port} $pingmsg\n"
        }
        $client->{pingsent}=$ctm+$client->{pingtime};
        $client->{lastping}=$ctm
      }
    }
  }
  # I love it when a plan comes together;)
}

sub decode_websocket {
  my @k=@_;
  my @s=(0,0);
  my @n=("","");
  for (my $i=0;$i<=1;$i++) {
    for (my $c=0;$c<length($k[$i]);$c++) {
      my $cc=substr($k[$i],$c,1);
      if ($cc eq ' ') { $s[$i]++ }
      elsif ($cc =~ /[0-9]/) { $n[$i].=$cc }
      # else negate!!
    }
    if ($s[$i]==0) {
      # This may never be the case!
      return (0,0)
    } else {
      $k[$i]=int $n[$i]/$s[$i];
    }
  }
  return @k
}

sub httphandshake {
  my ($self,$client) = @_;
  my @out=();
  my $sock=$client->{socket};
  if (!$sock) { return }
  my $func=$self->{clienthandle};
  my $date=time2str();
  my $caller=$self->{caller};
  if (!$client->{icecast} && ($client->{httpheader}{'ice-name'} || $client->{httpheader}{'ice-description'} || $client->{httpheader}{'ice-url'})) {
    $client->{icecast}=2;
    $client->{iceversion}=$client->{httpheader}{version};
    $client->{mountpoint}=$client->{httpheader}{uri}
  } elsif ((defined $client->{httpheader}{upgrade}) && ($client->{httpheader}{upgrade} =~ /websocket/i)) {
#  print "#[-1]#\r\n";
    $client->{wsreadheader}=1;
    $client->{wsheadermode}=0;
    $client->{wsdata}="";
    $client->{wsversion}=$client->{httpheader}{'sec-websocket-version'};
    # WebSockets connection, so do handshake!
    # VERSION HyBi 00
    if ($client->{httpheader}{'sec-websocket-key1'}) {

      # wybi00 is vulnerable!!!
      print STDOUT "[WEBSOCKET HyBi00]\n";
      out($client,"HTTP/1.1 400 Bad Request\r\nSec-WebSocket-Version: $client->{wsversion}\r\n\r\n");
      $client->{killafteroutput}=1;
      return;
    }
    # VERSION HyBi 06
    $client->{websockets}=1;
    $client->{httpmode}=0;
    $client->{websocketprotocol}='hybi06';
    my $handshake=$client->{httpheader}{'sec-websocket-key'};    
    $handshake.="258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    $handshake = sha1($handshake);
    $handshake = encode_base64($handshake);
    push @out,"HTTP/1.1 101 Switching Protocols";
    push @out,"Upgrade: WebSocket";
    push @out,"Connection: Upgrade";
    push @out,"Sec-WebSocket-Accept: ".$handshake;
    $client->{signalws}=1
  } elsif ($self->{websocketmode}) {
    out($client,"HTTP/1.1 426 Upgrade Required\r\nSec-WebSocket-Version: 13\r\nContent-type: text/html\r\n\r\nYou need to connect with the WebSocket protocol on this server.");
    &$func($client,'error',"426 Upgrade Required");
    $self->deleteclient($client); return
  }
  if ($client->{icecast}==1) {
    push @out,"HTTP/1.0 200 OK";
    push @out,"Server: Icecast 2.5.0";
    push @out,"Connection: Close";
    push @out,"Allow: GET, SOURCE";
    push @out,"Date: $date";
    push @out,"Cache-Control: no-cache";
    push @out,"Pragma: no-cache";
    push @out,"Access-Control-Allow-Origin: *";
  } elsif ($client->{icecast}==2) {
    push @out,"HTTP/1.1 100 Continue";
    push @out,"Server: Icecast 2.5.0";
    push @out,"Connection: Close";
    push @out,"Accept-Encoding: identity";
    push @out,"Allow: GET, SOURCE";
    push @out,"Date: $date";
    push @out,"Cache-Control: no-cache";
    push @out,"Pragma: no-cache";
    push @out,"Access-Control-Allow-Origin: *";
  }
  if ($#out >= 0) {
    my $data=join("\r\n",@out)."\r\n\r\n";
    out($client,$data);
  }
}

sub httpresponse {
  my ($code) = @_;
  my $msg="Unknown";
  # information
  if ($code == 100) { $msg="Continue" }
  elsif ($code == 101) { $msg="Switching Protocols" }
  elsif ($code == 102) { $msg="Processing" }
  # succesful
  elsif ($code == 200) { $msg="OK" }
  elsif ($code == 201) { $msg="Created" }
  elsif ($code == 202) { $msg="Accepted" }
  elsif ($code == 203) { $msg="Non-Authoritative Information" }
  elsif ($code == 204) { $msg="No Content" }
  elsif ($code == 205) { $msg="Reset Content" }
  elsif ($code == 206) { $msg="Partial Content" } # Streaming content in blocks - RFC 7233
  elsif ($code == 207) { $msg="Multi-Status" } # WebDAV - RFC 4918
  elsif ($code == 208) { $msg="Already Reported" } # WebDAV - RFC 5842
  elsif ($code == 226) { $msg="IM Used" } # RFC 3229
  # redirection
  elsif ($code == 300) { $msg="Multiple Choices" }
  elsif ($code == 301) { $msg="Moved Permanently" }
  elsif ($code == 302) { $msg="Found" }
  elsif ($code == 303) { $msg="See Other" }
  elsif ($code == 304) { $msg="Not Modified" } # RFC 7232
  elsif ($code == 305) { $msg="Use Proxy" }
  elsif ($code == 306) { $msg="Switch Proxy" }
  elsif ($code == 307) { $msg="Temporary Redirect" }
  elsif ($code == 308) { $msg="Permanent Redirect" } # RFC 7538
  # client errors
  elsif ($code == 400) { $msg="Bad Request" }
  elsif ($code == 401) { $msg="Unauthorized" }
  elsif ($code == 402) { $msg="Payment Required" }
  elsif ($code == 403) { $msg="Forbidden" }
  elsif ($code == 404) { $msg="Not Found" }
  elsif ($code == 405) { $msg="Method Not Allowed" }
  elsif ($code == 406) { $msg="Not Acceptable" }
  elsif ($code == 407) { $msg="Proxy Authentication Required" }
  elsif ($code == 408) { $msg="Request Timeout" }
  elsif ($code == 409) { $msg="Conflict" }
  elsif ($code == 410) { $msg="Gone" }
  elsif ($code == 411) { $msg="Length Required" }
  elsif ($code == 412) { $msg="Precondition Failed" } # RFC 7232
  elsif ($code == 413) { $msg="Payload Too Large" } # RFC 7231
  elsif ($code == 414) { $msg="URI Too Long" } # RFC 7231
  elsif ($code == 415) { $msg="Unsupported Media Type" }
  elsif ($code == 416) { $msg="Range Not Satisfiable" }
  elsif ($code == 417) { $msg="Expectation Failed" }
  elsif ($code == 418) { $msg="I'm a teapot" } # RFC 2324
  elsif ($code == 421) { $msg="Misdirected Request" } # RFC 7540
  elsif ($code == 422) { $msg="Unprocessable Entity" } # WebDAV - RFC 4918
  elsif ($code == 423) { $msg="Locked" } # WebDAV - RFC 4918
  elsif ($code == 424) { $msg="Failed Dependency" } # WebDAV - RFC 4918
  elsif ($code == 426) { $msg="Upgrade Required" }
  elsif ($code == 428) { $msg="Precondition Required" } # RFC 6585
  elsif ($code == 429) { $msg="Too Many Requests" } # RFC 6585
  elsif ($code == 431) { $msg="Request Header Fields Too Large" } # RFC 6585
  elsif ($code == 451) { $msg="Unavailable For Legal Reasons" } # RFC 7725 Don't burn books :)
  # server errors
  elsif ($code == 500) { $msg="Internal Server Error" }
  elsif ($code == 501) { $msg="Not Implemented" }
  elsif ($code == 502) { $msg="Bad Gateway" }
  elsif ($code == 503) { $msg="Service Unavailable" }
  elsif ($code == 504) { $msg="Gateway Timeout" }
  elsif ($code == 505) { $msg="HTTP Version Not Supported" }
  elsif ($code == 506) { $msg="Variant Also Negotiates" } # RFC 2295
  elsif ($code == 507) { $msg="Insufficient Storage" } # WebDAV - RFC 4918
  elsif ($code == 508) { $msg="Loop Detected" } # WebDAV - RFC 5842
  elsif ($code == 510) { $msg="Not Extended" } # RFC 2774
  elsif ($code == 511) { $msg="Network Authentication Required" } # RFC 6585
  
  return "HTTP/1.1 $code $msg"
}

sub broadcast {
  my ($self,$message)=@_;
  foreach my $c (@{$self->{clients}}) {
    if ($c && !$c->{killme} && !$c->{closed} && !$c->{dontsend}) {
      out($c,$message)
    }
  }
}

sub wsbroadcast {
  my ($self,$message,$command)=@_;
  foreach my $c (@{$self->{clients}}) {
    if ($c->{websockets}) {
      wsmessage($c,$message,$command)
    }
  }
}

sub broadcastfunc {
  my ($self,$func,@data)=@_;
  if (ref($func) ne 'CODE') { error "gserv.broadcastfunc: Not a code reference" }
  foreach my $c (@{$self->{clients}}) {
    if ($c && !$c->{killme} && !$c->{closed} && !$c->{dontsend}) {
      &$func($c,@data)
    }
  }
}

sub quit {
  my ($self)=@_;
  if (!$self->{server}{running}) { exit }
  $|=1; my $nc=$self->{numclients};
  print STDOUT prtm(),"Kill signal received! Killing $nc clients .. ";
  $self->wsbroadcast('quit','close');
  for (my $c=0;$c<$nc;$c++) {
    $self->{clients}[$c]{killafteroutput}=1;
  }
  for (my $c=0;$c<$nc;$c++) {
    $self->takeloop()
  }
  print STDOUT "Done.\n"; print STDOUT prtm()."Killing myself .. ";
  my $sock=$self->{server}{socket};
  if ($sock) { shutdown($sock,2); close($sock); }
  $self->{server}{running}=0;
  $self->{clients} = [];
  $self->{current} = 0;
  $self->{numclients} = 0;
  print STDOUT "Stopped!\n"
}

sub prtm {
  my ($s,$m,$h) = localtime;
  if (length($s)<2) { $s="0$s" }
  if (length($m)<2) { $m="0$m" }
  if (length($h)<2) { $h="0$h" }
  print STDOUT "[$h:$m:$s] ";
  return ""
}

sub encode_base64_char {
  my ($code,$c62,$c63) = @_;
  if (!$c62) { $c62='+' }
  if (!$c63) { $c63='/' }
  if ($code<26) { return chr(ord('A') + $code) }
  if ($code<52) { return chr(ord('a') + $code-26) }
  if ($code<62) { return chr(ord('0') + $code-52) }
  if ($code==62) { return $c62 }
  if ($code==63) { return $c63 }
  error "Invalid code in Encode Base64 - Must be 0-63! code=$code"
}

sub encode_base64 {
  # RFC 3548
  my ($data) = @_;
  my $c62='+'; my $c63="/";
  my $pad="="; 
  my $len=length($data);
  my $pos=0; my $val=0; my $br=0; my $out=""; my $written=0;
  while ($pos<$len) {
    my $code=ord(substr($data,$pos,1)); $val<<=8; $val+=$code; $br+=8;
    while ($br>=6) {
      my $c=($val>>($br-6)); $br-=6; $val&=((1<<$br)-1);
      $out.=encode_base64_char($c,$c62,$c63); $written++
    }
    $pos++;
  }
  if ($br) {
    $val<<=(6-$br); $out.=encode_base64_char($val,$c62,$c63); $written++;
  }  
  # padding
  while ($written % 4 > 0) {
    $out.=$pad; $written++; 
  }
  return $out
}

sub localip {
  my $socket = IO::Socket::INET->new(
    Proto       => 'udp',
    PeerAddr    => '198.41.0.4', # a.root-servers.net
    PeerPort    => '53', # DNS
  );
  return $socket->sockhost;
}

# EOF gserv.pm (C) 2018 Chaosje @ Domero