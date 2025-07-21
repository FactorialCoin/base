#!/usr/bin/perl
# -w -CSDA

package gserv;

######################################################################
#                                                                    #
#          Round Robin Server                                        #
#           - websockets, telnet, http, raw, IceCast                 #
#           - *Multi-Domain* SSL support                             #
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
no warnings 'uninitialized';
no warnings 'utf8';
use Socket;
use IO::Socket::IP -register;
use IO::Handle;
use IO::Select;
use IO::Socket::SSL;
use POSIX qw(:sys_wait_h :errno_h EAGAIN EBUSY mktime);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Time::HiRes qw(usleep gettimeofday);
use Digest::SHA qw(sha256 sha256_hex sha512);
use Digest::SHA1 qw(sha1);
use Digest::MD5 qw(md5);
use HTTP::Date;
use Crypt::Ed25519;
use utf8;
use gerr qw(error);
use gpost 1.2.1;
use HTML::Entities;

use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '5.5.2';
@ISA         = qw(Exporter);
@EXPORT      = qw(wsmessage);
@EXPORT_OK   = qw(prtm localip init start wsmessage out burst takeloop broadcast wsbroadcast broadcastfunc httpresponse cpu32);

my $CID = 0;
my $SSLPATH='/etc/letsencrypt/live';
my $SSLCERT='cert.pem';
my $SSLKEY='privkey.pem';
my $SSLCA='chain.pem';

my $cpu32 = (~0 == 4294967295);

################################################################################
sub log {
  my($serv,@msg)=@_;
  if (ref($::LOG) eq 'CODE') { &{$::LOG}(@msg) }
  elsif (ref($::API_LOG) eq 'CODE') { &{$::API_LOG}(@msg) }
  else{ print STDOUT prtm(),@_,"\n" }
}
################################################################################

sub setssl {
  my ($path,$cert,$key,$ca) = @_;
  if ($path) { $SSLPATH=$path }
  if ($cert) { $SSLCERT=$cert }
  if ($key) { $SSLKEY=$key }
  if ($ca) { $SSLCA=$ca }
}

sub init {
  my ($clienthandle,$clientloop,$ssldomain,$serverhandle) = @_;
  if (ref($clienthandle) ne 'CODE') {
    error "Eureka server could not initialize: No clienthandle given."
  }
  if ((defined $clientloop) && (ref($clientloop) ne 'CODE')) {
    error "Eureka server could not initialize: Invalid clientloop-handle given."
  }
  my $self = {
    isserver => 1,
    name => "Eureka Server $VERSION by Chaosje (C) 2019 Domero",      # Server name
    version => $VERSION,                     # server version
    ssl => defined $ssldomain && $ssldomain, # Use SSL
    sske => 0,                               # Use SSKE
    ssldomain => $ssldomain,                 # SSL keys will be found in $SSLPATH/ssldomain
    ssldebug => 1,                           # debug SSL process information
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
    buffersize => 1024*64,                   # Bytes to read from socket at loop-passes
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
    serverhandle => $serverhandle,           # handle called on every processing loop
    activeclient => undef,                   # set when a process is in active handling to signal from outside
  };
  bless($self);
  return $self
}

sub start {
    my ($self, $autoloop, $servloop) = @_;
    if ($servloop && (ref($servloop) ne 'CODE')) { error "GServ.Start: ServLoop is not a coderef" }
    $self->{servloop} = $servloop;
    my $err = "";
    if ($self->{debug}) { $self->{verbosepingpong} = 1 }
    if ($self->{maxdatasize} < 65535) { $self->{maxdatasize} = 65535 } # (websockets) allow a minimum of 64Kb data packets.

    # Auto flush and select Console
    select(STDOUT); $| = 1;

    # Setup TCP/IP & SSL
    my $proto = getprotobyname('tcp');
    if ($self->{ssl}) {
        if (ref($self->{ssldomain}) ne 'ARRAY') {
            $self->{ssldomain} = [$self->{ssldomain}];
        }
        $self->{sslcert} = {};
        $self->{sslkey} = {};
        $self->{sslca} = {};
        for my $ssldomain (@{$self->{ssldomain}}) {
            $self->{sslcert}{$ssldomain} = "$SSLPATH/$ssldomain/$SSLCERT";
            if (!-e $self->{sslcert}{$ssldomain}) {
                $self->log("SSL-certificate '$self->{sslcert}{$ssldomain}' does not exist");
                return $self;
            }
            $self->{sslkey}{$ssldomain} = "$SSLPATH/$ssldomain/$SSLKEY";
            if (!-e $self->{sslkey}{$ssldomain}) {
                $self->log("SSL-key '$self->{sslkey}{$ssldomain}' does not exist");
                return $self;
            }
            $self->{sslca} = "$SSLPATH/$ssldomain/$SSLCA";
            if (!-e $self->{sslca}) {
                $self->log("SSL-ca '$self->{sslca}' does not exist");
                return $self;
            }
        }
    }

    # create a socket, make it reusable, set buffers
    socket($self->{server}{socket}, PF_INET, SOCK_STREAM, $proto) or $err = "Can't open socket: $!";
    if ($err) {
        if ($self->{ssl} && $self->{ssldebug}) { $self->log("SOCKET_SSL_ERROR: $err") }
        $self->{error} = $err;
        return $self;
    }
    setsockopt($self->{server}{socket}, SOL_SOCKET, SO_REUSEADDR, 1) or $err = "Can't set socket: $!";
    if ($err) {
        if ($self->{ssl} && $self->{ssldebug}) { $self->log("SOCKET_SSL_ERROR: $err") }
        $self->{error} = $err;
        return $self;
    }
    setsockopt($self->{server}{socket}, SOL_SOCKET, SO_RCVBUF, 1<<20) or $err = "Can't set socket's receive buffer: $!";
    if ($err) {
        if ($self->{ssl} && $self->{ssldebug}) { $self->log("SOCKET_SSL_ERROR: $err") }
        $self->{error} = $err;
        return $self;
    }
    setsockopt($self->{server}{socket}, SOL_SOCKET, SO_SNDBUF, 2<<20) or $err = "Can't set socket's send buffer: $!"; # 2 MB
    if ($err) {
        if ($self->{ssl} && $self->{ssldebug}) { $self->log("SOCKET_SSL_ERROR: $err") }
        $self->{error} = $err;
        return $self;
    }

    # grab a port on this machine
    my $paddr = sockaddr_in($self->{server}{port}, INADDR_ANY);

    # bind to a port, then listen
    bind($self->{server}{socket}, $paddr) or $err = "Can't bind to address $paddr: $!";
    if ($err) {
        if ($self->{ssl} && $self->{ssldebug}) { $self->log("SOCKET_SSL_ERROR: $err") }
        $self->{error} = $err;
        return $self;
    }
    listen($self->{server}{socket}, SOMAXCONN) or $err = "Server can't listen: $!";
    if ($err) {
        if ($self->{ssl} && $self->{ssldebug}) { $self->log("SOCKET_SSL_ERROR: $err") }
        $self->{error} = $err;
        return $self;
    }

    # set autoflush on
    $self->{server}{socket}->autoflush(1);

    # set server accept to non-blocking, otherwise the server will block waiting
    IO::Handle::blocking($self->{server}{socket}, 0);
    if ($^O =~ /win/i) {
        my $nonblocking = 1;
        ioctl($self->{server}{socket}, 0x8004667e, \$nonblocking);
    }

    $self->{server}{running} = 1;
    $self->{start} = gettimeofday();
    if ($self->{verbose}) { $self->log("Server '$self->{name}' started on port $self->{server}{port}") }
    if (ref($self->{serverhandle}) eq 'CODE') { &{$self->{serverhandle}}('connected') }

    # Internal Loopmode
    $self->{loopmode} = $autoloop;
    if ($autoloop) {
        while ($self->{server}{running}) {
            $self->takeloop;
        }
    }

    return $self;
}

################################################################################

sub takeloop {
  my ($self) = @_;
  if (!$self->{server}{running}) { return }
  my $client;
  my $func=$self->{serverhandle};
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

      # Client IP:PORT
      my ($port,$iph) = sockaddr_in($client_addr); 
      my $ip = inet_ntoa($iph);
      
      # Non-blocking
      my $socketerr=0;
      if ($^O =~ /win/i) {
        # Non-blocking for Windows. _IOW('f', 126, u_long)
        my $nonblocking = 1; ioctl($client, 0x8004667e, \$nonblocking);
      } else {
        # And just to make sure it is non-blocking a third method (nobody knows all systems)
        my $flags = fcntl($client, F_GETFL, 0) or $socketerr=1;
        $flags = fcntl($client, F_SETFL, $flags | O_NONBLOCK) or $socketerr=1;
        if ($socketerr) {
          &$func($client,'error',"[$ip\:$port] Cannot set non-blocking mode on socket!");
          if ($self->{verbose}) {
            $self->log("ERROR [$ip\:$port] Cannot set non-blocking mode on socket!\n");
          }
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
        &$func($client,'error',"[$ip\:$port] ILLEGAL ACCESS");
        if ($self->{verbose}) {
          $self->log("[$ip\:$port] ILLEGAL ACCESS\n");
        }  
        close($client)        
      } elsif (!$socketerr) {  
        my $tm=gettimeofday();
        my $host='localhost';
        if ($ip ne '127.0.0.1') {
          $host=gethostbyaddr($iph, AF_INET);
          if (!$host) {
            if (($ip =~ /^192\.168/) || ($ip =~ /^10\.0\.0/)) { $host='LAN' }
            else { $host='UnknownHost' }
          }
        }

        # SSL
        my $sslerr=0;
        my $sslforward=0;
        if ($self->{ssl}) {
          IO::Socket::SSL->start_SSL($client,
            SSL_server => 1,
            SSL_verify_mode => SSL_VERIFY_FAIL_IF_NO_PEER_CERT,#SSL_VERIFY_NONE
            SSL_cert_file => $self->{sslcert},
            SSL_key_file => $self->{sslkey},
            SSL_ca_file => $self->{sslca},
            Listen => 128
          ) or $sslerr=1;
          if ($sslerr) {
            &$func($client,'error',$SSL_ERROR);
            if (
              $SSL_ERROR =~ /\:1408F09C\:/gs #||   # SSL routines:ssl3_get_record:http request
            #  $SSL_ERROR =~ /\:14094416\:/gs      # SSL routines:ssl3_read_bytes:sslv3 alert certificate unknown
            #  $SSL_ERROR =~ /\:1422E0EA\:/gs      # SSL routines:final_server_name:callback failedlo:version too low
            ) {
              $sslforward=1;
              &$func($client,'ssl_forward',{ip=>$ip,port=>$port,host=>$host,error=>"http request"});
              if ($self->{verbose}) {
                $self->log("[Forwarding][$ip]");
              }
            }else{
              &$func($client,'ssl_error',{ip=>$ip,port=>$port,host=>$host,error=>$SSL_ERROR});
              if ($self->{verbose}) {
                $self->log("[$ip:$port] $SSL_ERROR");
              }
              close($client) 
            }
          }
        }

        if (!$sslerr||$sslforward) {
          $CID++;
          my $cl=gserv::client->new($self,{
            id => $CID,
            socket => $client,
            ssl => $sslforward ? undef : $self->{ssl},
            sslforward => $sslforward,
            handle => $client_addr,
            host => $host,
            ip => $ip,
            iphandle => $iph,
            port => $port,
            serverport => $self->{server}{port},
            server => $self,
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
            sskemode => 0,
            sskeactive => 0,
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
          });
          #if ($self->{sske}) {
          #  $cdata->{sske} = { transkey => createkey(), transfunc => createkey() };
          #  $cdata->{sskemode}=1
          #}
          #push @{$self->{clients}},$cdata;
          #$self->{numclients}++;
          #if ($self->{verbose}) { $self->log("JOIN $ip\:$port ($host)") }
          #if ($self->{serverhandle}) { my $func=$self->{serverhandle}; &$func('connect',$cdata) }
          #my $func=$self->{clienthandle};
          #&$func($cdata,'connect')
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

sub gtmtimestring {
  my @t=localtime(mktime(localtime(time())));
  my $tm=('Sun','Mon','Tue','Wed','Thu','Fri','Sat')[$t[6]]; $tm.=", ";
  my $yr=$t[5]+1900; my $mon=('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')[$t[4]];
  $tm.="$t[3] $mon $yr ";
  $tm.=join(':',sprintf("%02d",$t[2]),sprintf("%02d",$t[1]),sprintf("%02d",$t[0]));
  $tm.=" GMT";
  return $tm
}

sub httpforward_tohttps {
  my ($self,$client) = @_;
  my $loc="";
  if (ref($self) && ref($client)) {
    $loc="[SERV{$self}:CLIENT{$client}]";
    if (defined $client->{httpheader}) {
      my $uri=(defined $client->{httpheader}{uri} ? $client->{httpheader}{uri} : '/');
      my @out=(gserv::httpresponse(301));
      $loc="https://$client->{httpheader}{host}".($self->{server}{port} != 80 && $self->{server}{port} != 443 ? ":$self->{server}{port}":"").$uri;
      if ($client->{httpheader}{getdata}) { $loc.='?'.$client->{httpheader}{getdata} }
      my $html=<<EOT;
  <DOCTYPE html>
  <html><body><div style="left: 0; right: 0; top: 0; bottom: 0; border: 1px black; padding: 40px; margin: auto; color: black; ba
  ckground: red;">Site has been permanently moved<br />$loc</div></body></html>
EOT
      push @out,"Date: ".gtmtimestring();
      push @out,"Server: $self->{name}";
      push @out,"Location: $loc";
      push @out,"Content-Length: ".length($html);
      push @out,"Keep-Alive: timeout=5, max=100";
      push @out,"Connection: Keep-Alive";
      push @out,"Content-Type: text/html; charset=iso-8859-1";
      my $data=join("\r\n",@out)."\r\n\r\n".$html;
      $client->{killafteroutput}=1;
      gserv::burst($client,\$data);
      $self->log("[$client->{ip}:$client->{port}][HTTP_FORWARD > $loc]");
      #$self->log("$data\n");
    }else{
      $loc="no-http-header"
    }
  }else{
    $loc="undefined"
  }
  return $loc
}

sub loopall {
  my ($self) = @_;
  for (my $i=1;$i<=$self->{numclients};$i++) {
    $self->takeloop()
  }
}

################################################################################

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
      if ($client->{socket}) {
        if ($client->{ssl}) {
          $client->{socket}->close(SSL_no_shutdown => 1)
        } else {
          shutdown($client->{socket},2); close($client->{socket}); 
        }
      }
    }
  }
  if ($self->{verbose}) {
    # my $err=gerr::trace(); print "$err\n";
    $self->log("QUIT $ip\:$port");
  }
  if ($self->{serverhandle}) {
    my $func=$self->{serverhandle};
    &$func($client,'disconnect')
  }
  my $func=$self->{clienthandle};
  &$func($client,'quit',$msg);
  $self->removeclient();
  $self->{deleteflag}=1;
}

################################################################################

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
  # moved to the main loop to prevent: Deep recursion on subroutine "gserv::wsinput";
  if (length($client->{wsbuffer})) { $self->wsinput($client) }
}

sub handlews {
  my ($self,$client) = @_;
  my $func=$self->{clienthandle};
  if (length($client->{wsdata}) > $self->{maxdatasize}) { &func($client,'error',"1009 Datasize too large") }
  if ($client->{wstype} eq 'ping') {
    if ($client->{verbosepingpong}) {
      $self->log("*< PING $client->{ip}\:$client->{port}");
    }
    if ($client->{sskeactive}) { $client->{wsdata}=sskecrypt($client,$client->{wsdata},0) }
    wsmessage($client,$client->{wsdata},'pong');
    $client->{lastping}=gettimeofday();
    $client->{pingsent}=0
  } elsif ($client->{wstype} eq 'pong') {
    if ($client->{verbosepingpong}) {
      $self->log("*< PONG $client->{ip}\:$client->{port}");
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

################################################################################

sub wsmessage {
  my ($client,$msg,$command) = @_;
  if ($client->{isserver}) { error "Version 3 Design change! wsmessage($client,$msg,$command)" }
  if (!defined($msg) && !defined($command)) { return }  
  if (!$command) { $command='text' }
  # print " >> $client->{ip}:$client->{port} $command $msg     \n";
  if (!$client || (ref($client) !~ /^gserv\:\:client/) || $client->{killme} || $client->{closed} || $client->{dontsend}) { return }
  if ($client->{sskeactive}) { $msg=sskecrypt($client,$msg,1) }
  my $out=chr(129);
  if ($command eq 'binary') {
    $out=chr(130)
  }
  elsif ($command eq 'pong') {
    if ($client->{verbosepingpong}) {
      $client->{server}->log("*> PONG $client->{ip}\:$client->{port} $msg\n");
    }
    $out=chr(138);
    $client->{lastping}=gettimeofday();
    $client->{pingsent}=0
  }
  elsif ($command eq 'ping') {
    if ($client->{verbosepingpong}) {
      $client->{server}->log("*> PING $client->{ip}\:$client->{port} $msg\n");
    }
    $out=chr(137);
    $client->{pingsent}=0
  }
  elsif ($command eq 'close') {
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
  $client->out($out.$msg)
}

################################################################################

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

sub makewshandshake {
  my ($key1,$key2,$key3) = @_;
  my $sum=md5(decbin($key1).decbin($key2).$key3);
  return $sum;
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

################################################################################

sub outsock {
  my ($self,$client,$data) = @_;
  if (ref($client) !~ /^gserv\:\:client/) { 
    error("Gserv.OutSock: Client Design error, use gserv::client class input!");
    return 
  }
  return $client->outsock($data)
}

sub out {
  my ($client,$data) = @_;
  if (ref($client) !~ /^gserv\:\:client/) { 
    error("Gserv.Out: Design error, use gserv::client class input!");
    return 
  }
  return $client->out($data)
}

sub burst {
  # burst some output
  my ($client,$data,$killafteroutput) = @_;
  if (ref($client) !~ /^gserv\:\:client/) { 
    error("Gserv.Burst: Design error, use gserv::client class input!");
    return 
  }
  return $client->burst($data,$killafteroutput)
}

################################################################################

use threads;
use threads::shared;
use gtfio;
use POSIX qw(:sys_wait_h :errno_h mktime);
my %threaded :shared = ();
my %progress :shared = ();

sub burst_to_client {
  my ($id,$client)=@_;
  my $sz=32768<<2; # 128 Kb Packages
  if (ref($client->{burstdata}) eq 'SCALAR') {
    while ($client->{burstpointer} < $client->{burstlength}) {
      if ($client->{burstpointer}+$sz > $client->{burstlength}) { $sz=$client->{burstlength}-$client->{burstpointer} }
      if ($client->{burstpointer}>=0) {
        $client->outsock(substr(${$client->{burstdata}},$client->{burstpointer},$sz));
      }
      $client->{burstpointer}+=$sz;
      lock(%progress);
      $progress{$id} = $client->{burstpointer};
    }
  }
  elsif($client->{burstfile}) {
    my $f=gfio::open($client->{burstfile},'r');
    while ($client->{burstpointer} < $client->{burstlength}) {
      if ($client->{burstpointer}+$sz > $client->{burstlength}) { $sz=$client->{burstlength}-$client->{burstpointer} }
      $f->seek($client->{burstpointer});
      my $rd=$f->read($sz,1); if ($client->{bursthead}) { $rd=$client->{bursthead}.$rd; delete $client->{bursthead}; }
      $client->outsock($rd);
      $client->{burstpointer}+=$sz;
      lock(%progress);
      $progress{$id} = $client->{burstpointer};
    }
    $f->close();
  }
  lock(%threaded);
  $threaded{$id}++;
}

sub send_to_client {
  my ($id,$client)=@_;
  my $sz=32768<<3; # 256 Kb
  while ($client->{outputpointer} < $client->{outputlength}) {
    if ($client->{outputpointer}+$sz > $client->{outputlength}) { $sz=$client->{outputlength}-$client->{outputpointer} }
    if ($client->{outputpointer}>=0) {
      $client->outsock(substr($client->{outputbuffer},$client->{outputpointer},$sz));
    }
    $client->{outputpointer}+=$sz;
  }
}

sub handleclient {
    my ($self) = @_;
    my $client = $self->{clients}[$self->{current}];
    my $func = $self->{clienthandle};
    my $ctm = gettimeofday();

    if (!defined $client) {
        $self->log("ERROR: No client found at index $self->{current}\n");
        $self->{deleteflag} = 1;
        return;
    }

    if ($client->{closed} || $client->{killme}) {
        $self->deleteclient($client);
        return;
    }

    if ($client->{sslforward}) {
        my $forw = "[$client->{ip}:$client->{port}][HTTP_FORWARD " . $self->httpforward_tohttps($client) . "]";
        if (ref($func) eq 'CODE') {
            &$func($client, 'forward', $forw);
        }
        delete $client->{sslforward};
        return;
    }

    my $sock = $client->{socket};
    if (!$sock) {
        $self->deleteclient($client);
        return;
    }

    $self->{activeclient} = $client;

    if ($self->{timeout} && $client->{init} && $client->{httpreadheader} && ($ctm - $client->{start} > $self->{timeout})) {
        $self->outsock($client, "HTTP/1.1 408 REQUEST TIMEOUT\r\n\r\n");
        if (ref($func) eq 'CODE') {
            &$func($client, 'error', "408 Request Timeout");
        }
        $self->deleteclient($client);
        return;
    }

    if (defined $self->{clientloop} && ref($self->{clientloop}) eq 'CODE') {
        my $loopfunc = $self->{clientloop};
        &$loopfunc($client, 'loop');
        if ($client->{killme}) {
            $self->deleteclient($client);
            return;
        }
    } elsif (defined $self->{clientloop}) {
        error "Invalid loopfunction: $self->{clientloop}";
    }

    # Non-threaded file burst
    if ($client->{burstmode}) {
        my $sz = 32768 << 3; # 256 KB-blokken, zoals outputmode
        if ($client->{burstfile}) {
            my $f = gfio::open($client->{burstfile}, 'r');
            if (!$f) {
                $client->outsock("HTTP/1.1 500 INTERNAL SERVER ERROR\r\n\r\n");
                $client->{killme} = 1;
                return;
            }
            my $canwrite = 0;
            foreach my $handle ($client->{selector}->can_write(0.5)) { # 500ms timeout
                if ($handle == $sock) {
                    $canwrite++;
                    last;
                }
            }
            if ($canwrite) {
                $client->{last} = $ctm;
                if ($client->{burstpointer} < $client->{burstlength}) {
                    if ($client->{burstpointer} + $sz > $client->{burstlength}) {
                        $sz = $client->{burstlength} - $client->{burstpointer};
                    }
                    if (!IO::Socket::connected($sock)) {
                        $f->close();
                        $client->{killme} = 1;
                        return;
                    }
                    $f->seek($client->{burstpointer});
                    my $rd = $f->read($sz, 1);
                    if ($client->{bursthead}) {
                        $rd = $client->{bursthead} . $rd;
                        delete $client->{bursthead};
                    }
                    $client->outsock($rd);
                    if ($client->{killme}) {
                        $f->close();
                        return;
                    }
                    $client->{burstpointer} += $sz;
                    $client->{lastprogress} = $client->{burstpointer};
                    if (ref($func) eq 'CODE') {
                        my $speed = 0;
                        my $delta = $ctm - $client->{last};
                        if ($delta > 0) {
                            $speed = int(10 * (int($client->{burstpointer} / $delta) / 1024)) / 10;
                        }
                        &$func($client, "progress", "$speed Kbs, " . (int((1000 / $client->{burstlength}) * $client->{burstpointer}) / 10) . "%");
                    }
                }
                if ($client->{burstpointer} >= $client->{burstlength}) {
                    $f->close();
                    $client->{burstmode} = 0;
                    if ($client->{killafteroutput}) {
                        $client->{killme} = 1;
                    }
                    if (ref($func) eq 'CODE') {
                        &$func($client, "bursted", $client->{burstlength});
                    }
                }
            }
            $f->close() if !$client->{burstmode};
            return;
        } elsif (ref($client->{burstdata}) eq 'SCALAR') {
            my $canwrite = 0;
            foreach my $handle ($client->{selector}->can_write(0.5)) { # 500ms timeout
                if ($handle == $sock) {
                    $canwrite++;
                    last;
                }
            }
            if ($canwrite) {
                $client->{last} = $ctm;
                if ($client->{burstpointer} < $client->{burstlength}) {
                    if ($client->{burstpointer} + $sz > $client->{burstlength}) {
                        $sz = $client->{burstlength} - $client->{burstpointer};
                    }
                    if (!IO::Socket::connected($sock)) {
                        $client->{killme} = 1;
                        return;
                    }
                    $client->outsock(substr(${$client->{burstdata}}, $client->{burstpointer}, $sz));
                    if ($client->{killme}) {
                        return;
                    }
                    $client->{burstpointer} += $sz;
                    $client->{lastprogress} = $client->{burstpointer};
                    if (ref($func) eq 'CODE') {
                        my $speed = 0;
                        my $delta = $ctm - $client->{last};
                        if ($delta > 0) {
                            $speed = int(10 * (int($client->{burstpointer} / $delta) / 1024)) / 10;
                        }
                        &$func($client, "progress", "$speed Kbs, " . (int((1000 / $client->{burstlength}) * $client->{burstpointer}) / 10) . "%");
                    }
                }
                if ($client->{burstpointer} >= $client->{burstlength}) {
                    $client->{burstmode} = 0;
                    if ($client->{killafteroutput}) {
                        $client->{killme} = 1;
                    }
                    if (ref($func) eq 'CODE') {
                        &$func($client, "bursted", $client->{burstlength});
                    }
                }
            }
            return;
        }
    }

    # Bestaande output- en leeslogica
    if ($client->{outputmode}) {
        my $canwrite = 0;
        foreach my $handle ($client->{selector}->can_write(0.5)) { # 500ms timeout
            if ($handle == $sock) {
                $canwrite++;
                last;
            }
        }
        if ($canwrite) {
            $client->{last} = $ctm;
            for my $i (0..8) { # 2 Mb
                if ($client->{outputpointer} >= $client->{outputlength}) {
                    $client->{outputmode} = 0;
                    if ($client->{killafteroutput} || ($self->{killhttp} && $client->{httpmode})) {
                        if (ref($func) eq 'CODE') {
                            &$func($client, "donesend", $client->{outputlength});
                        }
                        $client->{delete} = 1;
                        return;
                    }
                }
                if ($client->{outputmode}) {
                    my $sz = 32768 << 3; # 256 Kb
                    if ($client->{outputpointer} + $sz > $client->{outputlength}) {
                        $sz = $client->{outputlength} - $client->{outputpointer};
                    }
                    $self->outsock($client, substr($client->{outputbuffer}, $client->{outputpointer}, $sz));
                    if ($client->{killme}) {
                        return;
                    }
                    $client->{outputpointer} += $sz;
                }
            }
        } elsif ($client->{httpmode}) {
            return;
        }
    } else {
        if ($client->{killafteroutput}) {
            $client->{delete} = 1;
            return;
        }
        if ($client->{signalws}) {
            $client->{signalws} = 0;
            if (ref($func) eq 'CODE') {
                &$func($client, 'handshake', 'WebSockets v' . $client->{wsversion});
            }
        }
    }

    # READ
    my $inbuf = "";
    my @ready = $client->{selector}->can_read(0);
    my $canread = 0;
    foreach my $handle (@ready) {
        if ($handle == $sock) {
            $canread = 1;
            last;
        }
    }

    if ($canread) {
        for my $i (1..32) { # 2 Mb
            my $rdbuf = "";
            if ($self->{ssl}) {
                sysread($sock, $rdbuf, 32768); # 32 Kb
            } else {
                recv($sock, $rdbuf, $self->{buffersize}, 0);
            }
            if ($rdbuf eq "") {
                if (($! != POSIX::EAGAIN) && ($! != POSIX::EBUSY) && ($! != POSIX::EWOULDBLOCK) && ($! != 10035)) {
                    if ($!) {
                        my $err = 0 + $!;
                        $self->log("READ ERROR $client->{ip}:$client->{port} [$err] $!");
                        $client->{dontsend} = 1;
                        if (ref($func) eq 'CODE') {
                            &$func($client, 'error', $err);
                        }
                        $self->deleteclient($client);
                        return;
                    }
                }
                last;
            } else {
                $inbuf .= $rdbuf;
            }
        }
    }

    if ($inbuf ne "") {
        my $len = length($inbuf);
        if (ref($func) eq 'CODE') {
            &$func($client, 'received', $len);
        }
        $client->{bytesreceived} += $len;
        $self->log("INBUF: '$inbuf' ($len)\n") if ($self->{debug});

        if ($client->{init}) {
            if (ord(substr($inbuf, 0, 1)) == 255) {
                if ($self->{websocketmode}) {
                    $self->log("ERROR $client->{ip}:$client->{port} [TELNET = NO WEBSOCKET CLIENT]");
                    $self->outsock($client, "HTTP/1.1 400 BAD REQUEST\r\n\r\n");
                    if (ref($func) eq 'CODE') {
                        &$func($client, 'error', "400 Bad Request");
                    }
                    $self->deleteclient($client);
                    return;
                }
                $client->{telnet} = 1;
                if (ref($func) eq 'CODE') {
                    &$func($client, 'telnet');
                }
                $inbuf = "";
                $client->{keepalive} = 1;
                $client->{init} = 0;
                return;
            } elsif ($inbuf =~ /^GET ([^\s]+) HTTP\/([0-1.]+)/i) {
                if ($self->{verboseheader}) {
                    $self->log("GET $1 $2\n");
                }
                my $getstr = $1;
                $client->{httpmode} = 1;
                $client->{httpreadheader} = 1;
                $client->{httpheader}{version} = $2;
                $client->{httpheader}{method} = 'get';
                my ($uri, $cgi) = split(/\?/, $getstr);
                $client->{httpheader}{uri} = $uri;
                $client->{httpheader}{getdata} = $cgi;
            } elsif ($inbuf =~ /^POST ([^\s]+) HTTP\/([0-1.]+)/i) {
                if ($self->{verboseheader}) {
                    $self->log("POST $1 $2\n");
                }
                $client->{httpmode} = 1;
                $client->{httpreadheader} = 1;
                $client->{httpheader}{uri} = $1;
                $client->{httpheader}{version} = $2;
                $client->{httpheader}{method} = 'post';
            } elsif ($inbuf =~ /^SOURCE (\/[^\s]+) ICE\/([0-9.]+)/i) {
                $client->{icecast} = 1;
                $client->{httpreadheader} = 1;
                $client->{mountpoint} = $1;
                $client->{iceversion} = $2;
            } elsif ($self->{websocketmode}) {
                $self->log("ERROR $client->{ip}:$client->{port} [RAW = NO WEBSOCKET CLIENT]");
                $self->outsock($client, "HTTP/1.1 400 BAD REQUEST\r\n\r\n");
                if (ref($func) eq 'CODE') {
                    &$func($client, 'error', 400);
                }
                $self->deleteclient($client);
                return;
            } else {
                if (ref($func) eq 'CODE') {
                    &$func($client, 'error', 405);
                }
                $self->deleteclient($client);
                return;
            }
            $client->{init} = 0;
        }

        $client->{last} = $ctm;

        if ($client->{websockets}) {
            $self->wsinput($client, $inbuf);
        } else {
            if (!$client->{httpmode} && !$client->{telnet} && !$self->{linemode}) {
                if (ref($func) eq 'CODE') {
                    &$func($client, 'input', $inbuf);
                }
                return;
            }
            if ($client->{httpreadheader}) {
                my @hdat = split(/\r\n/, $inbuf, -1);
                my $cnt = 0;
                foreach my $hline (@hdat) {
                    $cnt++;
                    if ($hline eq "") {
                        if ($self->{verboseheader}) {
                            $self->log("HEADER END]\n");
                        }
                        $client->{httpreadheader} = 0;
                        $self->httphandshake($client);
                        if ($client->{killme}) {
                            $self->deleteclient($client);
                            return;
                        }
                        if ($client->{websockets}) {
                            return;
                        }
                        if ($client->{httpheader}{method} eq 'post') {
                            $client->{readpostdata} = 1;
                            $client->{postdatalength} = $client->{httpheader}{'content-length'} || 0;
                            $client->{postdata} = join("\r\n", @hdat[$cnt..$#hdat]);
                            $client->{postdatalength} -= length($client->{postdata});
                            if ($client->{postdatalength} < 0) {
                                $client->{postdata} = substr($client->{postdata}, 0, $client->{postdatalength});
                                $client->{postdatalength} = 0;
                            }
                            if ($client->{postdatalength} == 0) {
                                $client->{readpostdata} = 0;
                                $client->{post} = gpost::init($client->{httpheader}{'content-type'}, $client->{postdata});
                                if (ref($func) eq 'CODE') {
                                    &$func($client, "ready", 'post');
                                }
                            }
                        } else {
                            $client->{post} = gpost::init('get', $client->{httpheader}{getdata});
                            if (ref($func) eq 'CODE') {
                                &$func($client, "ready", 'get');
                            }
                        }
                        last;
                    } else {
                        my ($key, $val) = split(/: /, $hline, 2);
                        if ((defined $key) && ($key ne "")) {
                            if (!defined $val) {
                                $val = "";
                            } else {
                                $val =~ s/^[\s]+//;
                                $val =~ s/[\s]+$//;
                            }
                            $client->{httpheader}{lc($key)} = $val;
                            if ($self->{verboseheader}) {
                                $self->log("[HEADER] '$key' => '$val'\n");
                            }
                        }
                    }
                }
            } elsif ($client->{readpostdata}) {
                $client->{postdata} .= $inbuf;
                $client->{postdatalength} -= length($inbuf);
                if ($client->{postdatalength} < 0) {
                    $client->{postdata} = substr($client->{postdata}, 0, $client->{postdatalength});
                    $client->{postdatalength} = 0;
                }
                if ($client->{postdatalength} == 0) {
                    $client->{readpostdata} = 0;
                    $client->{post} = gpost::init($client->{httpheader}{'content-type'}, $client->{postdata});
                    if (ref($func) eq 'CODE') {
                        &$func($client, "ready", 'post');
                    }
                }
            }
            if ($client->{killme}) {
                $self->deleteclient($client);
                return;
            }
            if (!$client->{readpostdata} && !$client->{httpmode} && !$client->{websockets}) {
                my @lines = split(/\n/, $inbuf);
                foreach my $line (@lines) {
                    $line =~ s/\r//g;
                    if (ref($func) eq 'CODE') {
                        &$func($client, 'input', $line);
                    }
                    if ($client->{killme}) {
                        $self->deleteclient($client);
                        return;
                    }
                }
            }
        }
    } elsif (
        ($self->{idletimeout} && ($ctm - $client->{last} >= $self->{server}{clienttimeout})) ||
        ($self->{server}{clienttimeout} && (!$client->{keepalive} && (gettimeofday() - $client->{last} >= $self->{server}{clienttimeout})))
    ) {
        $client->outsock("HTTP/1.1 408 REQUEST TIMEOUT\r\n\r\n");
        if (ref($func) eq 'CODE') {
            &$func($client, 'error', "408 Request Timeout");
        }
        $self->deleteclient($client);
        return;
    } elsif ($client->{websockets}) {
        if ($client->{pingtime}) {
            my $delta = 0;
            if ($client->{pingsent}) {
                $delta = $ctm - $client->{pingsent};
                if ($delta > $client->{pingtimeout}) {
                    if ($client->{killafteroutput}) {
                        $self->deleteclient($client);
                        return;
                    }
                    wsmessage($client, "2 PING TimeOut", "close");
                    $self->log(">! PING TIMEOUT $client->{ip}:$client->{port}");
                    $client->{killafteroutput} = 1;
                    return;
                }
            }
            $delta = $ctm - $client->{lastping};
            if ($delta > $client->{pingtime}) {
                my $pingmsg = 'eureka' . int(rand(1000000) + 100000);
                $client->{pings}{$pingmsg} = 1;
                wsmessage($client, $pingmsg, 'ping');
                if ($client->{verbosepingpong}) {
                    $self->log("> PING $client->{ip} $client->{port} $pingmsg");
                }
                $client->{pingsent} = $ctm + $client->{pingtime};
                $client->{lastping} = $ctm;
            }
        }
    }
}

################################################################################

sub httphandshake {
  my ($self,$client) = @_;
  #my @out=();
  my $sock=$client->{socket};
  if (!$sock) { return }
  my $func=$self->{clienthandle};
  my $date=time2str();
  my $caller=$self->{caller};
  # SSKE Handshake
  if ($client->{sske}) {
    $client->httpversion("1.1");
    if (!$self->checksske($client,$client->{sskemode})) {
      $self->log("[SSKE 460 Keys Expected]\n");
      return $client->httpcode(460)->httprespond(1)
    }
    if (!$self->checksske($client,$client->{sskemode}+1)) {
      $self->log("[SSKE 461 Invalid Keys]\n");
      return $client->httpcode(461)->httprespond(1)
    }
    $client->httpcode(100)
    #push @out,"HTTP/1.1 100 Continue"
  }
  # ICECAST Handshake
  if (!$client->{icecast} && ($client->{httpheader}{'ice-name'} || $client->{httpheader}{'ice-description'} || $client->{httpheader}{'ice-url'})) {
    $client->{icecast}=2;
    $client->{iceversion}=$client->{httpheader}{version};
    $client->{mountpoint}=$client->{httpheader}{uri}
  }
  # Websocket Handshake
  elsif ((defined $client->{httpheader}{upgrade}) && ($client->{httpheader}{upgrade} =~ /websocket/i)) {
    $client->{wsreadheader}=1;
    $client->{wsheadermode}=0;
    $client->{wsdata}="";
    $client->{wsversion}=$client->{httpheader}{'sec-websocket-version'};
    # WebSockets connection, so do handshake!
    # VERSION HyBi 00
    if ($client->{httpheader}{'sec-websocket-key1'}) {
      # hybi00 is vulnerable!!!
      $self->log("[WEBSOCKET HyBi00]\n");
      return $client->httpversion("1.1")->httpcode(400)->httphead("Sec-WebSocket-Version: $client->{wsversion}")->httprespond(1);
    }
    # VERSION HyBi 06
    $client->{websockets}=1;
    $client->{httpmode}=0;
    $client->{websocketprotocol}='hybi06';
    $client->httpversion("1.1")->httpcode(101)->httphead(
      "Upgrade: WebSocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Accept: ".encode_base64(sha1($client->{httpheader}{'sec-websocket-key'}."258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
    );
    $client->{signalws}=1
  }
  # Websocket Upgrade Error
  elsif ($self->{websocketmode}) {
    #out($client,"HTTP/1.1 426 Upgrade Required\r\nSec-WebSocket-Version: 13\r\nContent-type: text/html\r\n\r\nYou need to connect with the WebSocket protocol on this server.");
    &$func($client,'error',"426 Upgrade Required");
    return $client->httpversion("1.1")->httpcode(426)
      ->httphead("Sec-WebSocket-Version: 13")
      ->contentbody("You need to connect with the WebSocket protocol on this server.")
      ->httprespond(1);
    #$self->deleteclient($client); return
  }
  # ICECAST 1 Handshake
  if ($client->{icecast}==1) {
    $client->httpversion("1.0")->httpcode(200)->httphead(
      "Server: Icecast 2.5.0",
      "Connection: Close",
      "Allow: GET, SOURCE",
      "Date: $date",
      "Cache-Control: no-cache",
      "Pragma: no-cache",
      "Access-Control-Allow-Origin: *"
    );
  }
  # ICECAST 2 Handshake
  elsif ($client->{icecast}==2) {
    $client->httpversion("1.1")->httpcode(100)->httphead(
      "Server: Icecast 2.5.0",
      "Connection: Close",
      "Accept-Encoding: identity",
      "Allow: GET, SOURCE",
      "Date: $date",
      "Cache-Control: no-cache",
      "Pragma: no-cache",
      "Access-Control-Allow-Origin: *"
    );
  }
  # SSKE Handshake
  if ($client->{sske}) {
    if ($client->{sskemode} == 1) {
      $client->httphead(
        "Double-Symmetric-Key: ".octhex(scramblekey($client->{sske}{singlekey},$client->{sske}{transkey},$client->{sske}{transfunc})),
        "Double-Symmetric-Function: ".octhex(scramblekey($client->{sske}{singlefunc},$client->{sske}{transkey},$client->{sske}{transfunc}))
      );
      $client->{httpreadheader}=1;
      $client->{sskemode}=3
    } else {
      $client->{sske}{symkey}=scramblekey($client->{sske}{unlockedkey},$client->{sske}{transkey},$client->{sske}{transfunc});
      $client->{sske}{symfunc}=scramblekey($client->{sske}{unlockedfunc},$client->{sske}{transkey},$client->{sske}{transfunc})
    }
  }
  # Handshake Output
  if ($client->httpcode()){ #$#out >= 0) {
    #my $data=join("\r\n",@out)."\r\n\r\n";
    if ($self->{verboseheader}) {
      $self->log("[HEADER OUT]\n".join("\n",@{$client->httphead()}));
      #print "[HEADER OUT]\n".join("\n",@out)."\n"
    }
    $client->httprespond();
    #out($client,$data);
  }
  # Entering SSKE Mode
  if ($client->{sskemode} > 1) { $client->{sskeactive} = 1 }
}

####### Secure Symmetric Key Exchange #############

sub createkey {
  my ($pubkey, $privkey) = Crypt::Ed25519::generate_keypair;
  return $privkey
}

sub scramblekey {
  # 64 bit CPU-mode only!
  if ($cpu32) { return scramblekey32(@_) }
  my ($shared,$private,$fkey) = @_;
  my @plist=unpack('Q*',$private);
  my @flist=unpack('Q*',$fkey);
  my $key=""; my $i=0;
  for my $c (unpack('Q*',$shared)) {
    my $x = $c ^ $plist[$i];
    $key.=pack('Q',(($x & ~$flist[$i]) | (~$x & $flist[$i])));
    $i++
  }
  return $key
}

sub scramblekey32 {
  # 32 bit CPU-mode only!
  my ($shared,$private,$fkey) = @_;
  my @plist=unpack('N*',$private);
  my @flist=unpack('N*',$fkey);
  my $key=""; my $i=0;
  for my $c (unpack('N*',$shared)) {
    my $x = $c ^ $plist[$i];
    $key.=pack('N',(($x & ~$flist[$i]) | (~$x & $flist[$i])));
    $i++
  }
  return $key
}

sub sskecrypt {
  # EXTREME strong encoding
  my ($self,$data,$forceencode) = @_;
  my $decode=(substr($data,0,4) eq 'DSKE'); my $ofs=0;
  if ($forceencode) { $decode=0 }
  my $datalen=length($data)-8*$decode; my $orglen=$datalen;
  if ($decode) {
    $orglen=unpack('N',substr($data,4,4)); $ofs=8;
    my $rest=$orglen % 64; if ($rest) { $rest=64-$rest }
    if ($orglen+$rest != $datalen) {
      # Found size ($len) different from actual size ($datalen)
      return undef
    }
  } elsif ($datalen > 16777216) {
    error("Domero Encoder: Datalength exceeds 16Mb.")
  }
  my $sha=sha512($self->{sske}{symkey});
  my $scram; my $kscram;
  if ($datalen > 4096) {
    $scram=sha512($self->{sske}{symfunc});
    if ($datalen > 262144) {
      $kscram=sha512($sha.$scram);
    }
  }
  my $dataoffset=unpack('n',substr($sha,0,2)) % $orglen;
  if (!$decode) { $ofs+=$dataoffset }
  # add padding to get 64 byte granularity
  my $rest=$datalen % 64;
  if ($rest) { $data.=chr(0)x(64-$rest); $datalen+=64-$rest }
  my $nb = $datalen >> 6; my $out=""; my $dat;
  my $filter = $self->{sske}{symfunc};
  for my $b (1..$nb) {
    if (!$decode && ($ofs+64>$datalen)) {
      my $rest=64+$ofs-$datalen;
      $dat=substr($data,$ofs).substr($data,0,$rest); $ofs=$rest
    } else {
      $dat=substr($data,$ofs,64); $ofs+=64
    }
    $out.=scramblekey($dat,$self->{sske}{symkey},$filter);
    $filter=substr($filter,1).substr($filter,0,1);
    if ($b % 64 == 0) {
      # every 4Kb -> new filter (all used up), filter = 64 bytes * 4Kb = max 256Kb
      if ($b % 4096 == 0) {
        # every 256Kb -> new scram (all used up), kscram = 64 bytes * 256Kb = 16Mb
        my @sl=unpack('N*',$kscram); my $ns=""; my $i=0;
        for my $f (unpack('N*',$scram)) {
          $ns.=pack('N',$f ^ $sl[$i]); $i++
        }
        $scram=$ns;
        $kscram=substr($kscram,1).substr($kscram,0,1);
      }
      $filter=""; my $i=0;
      my @sl=unpack('N*',$scram);
      for my $f (unpack('N*',$self->{sske}{symfunc})) {
        $filter.=pack('N',$f ^ $sl[$i]); $i++
      }
      $scram=substr($scram,1).substr($scram,0,1);
    }
  }
  # add header
  if ($decode) {
    # delete encoded zeros padding ( = garbage) and re-adjust data for dataoffset
    $out=substr($out,$datalen-$dataoffset).substr($out,0,$orglen-$dataoffset)
  } else {  
    $out='DSKE'.pack('N',$orglen).$out
  }
  return $out
}

sub checksske {
  my ($self,$client,$mode) = @_;
  if (($mode == 1) || ($mode == 2)) {
    my $key=uc($client->{httpheader}{'symmetric-key'});
    my $fkey=uc($client->{httpheader}{'symmetric-function'});
    if ($mode == 1) {
      if (!$key || !$fkey) { return 0 }
    } else {
      if ($key !~ /[A-F0-9]{128}/) { return 0 }
      if ($fkey !~ /[A-F0-9]{128}/) { return 0 }
    }
    $client->{sske}{singlekey}=hexoct($key);
    $client->{sske}{singlefunc}=hexoct($fkey)
  } else {
    my $key=uc($client->{httpheader}{'unlocked-symmetric-key'});
    my $fkey=uc($client->{httpheader}{'unlocked-symmetric-function'});
    if ($mode == 3) {
      if (!$key || !$fkey) { return 0 }
    } else {
      if ($key !~ /[A-F0-9]{128}/) { return 0 }
      if ($fkey !~ /[A-F0-9]{128}/) { return 0 }
    }
    $client->{sske}{unlockedkey}=hexoct($key);
    $client->{sske}{unlockedfunc}=hexoct($fkey)
  }
  return 1
}

################################################################################

sub httpresponse {
  my ($code,$version) = @_; my $msg="Unknown"; if (!$version) { $version="1.1" }
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
  elsif ($code == 302) { $msg="Moved Temporary" }
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
  
  return "HTTP/$version $code $msg"
}

################################################################################

sub broadcast {
  my ($self,$message)=@_;
  foreach my $c (@{$self->{clients}}) {
    if ($c && !$c->{killme} && !$c->{closed} && !$c->{dontsend}) {
      $c->out($message)
    }
  }
}

sub wsbroadcast {
  my ($self,$message,$command)=@_;
  foreach my $c (@{$self->{clients}}) {
    if ($c->{websockets}) {
      $c->wsmessage($message,$command)
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

################################################################################

sub quit {
  my ($self,$msg)=@_;
  if (!$self->{server}{running}) { exit }
  $|=1; my $nc=$self->{numclients};
  if (!$msg) { $msg="[ no message ]" }
  if (!$nc) { $nc=0 }
  $self->log(prtm(),"Kill signal received!\nQuit: $msg\nKilling $nc clients .. \n");
  $self->wsbroadcast('quit','close');
  for (my $c=0;$c<$nc;$c++) {
    $self->{clients}[$c]{killafteroutput}=1;
  }
  for (my $c=0;$c<$nc;$c++) {
    $self->takeloop()
  }
  $self->log("Done.\n"); $self->log(prtm(),"Killing myself .. ");
  my $sock=$self->{server}{socket};
  if ($sock) { shutdown($sock,2); close($sock); }
  $self->{server}{running}=0;
  $self->{clients} = [];
  $self->{current} = 0;
  $self->{numclients} = 0;
  $self->log("Stopped!\n")
}

################################################################################

sub prtm {
  my ($s,$m,$h) = localtime;
  if (length($s)<2) { $s="0$s" }
  if (length($m)<2) { $m="0$m" }
  if (length($h)<2) { $h="0$h" }
  return "[$h:$m:$s] "
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

################################################################################
# EOF gserv.pm (C) 2018 Chaosje @ Domero
################################################################################

package gserv::client;

################################################################################

use strict;
use warnings; no warnings qw<uninitialized>;
#use Socket;
#use IO::Socket::IP -register;
#use IO::Handle;
#use IO::Select;
#use IO::Socket::SSL;
#use Time::HiRes qw(usleep gettimeofday);
#use Digest::SHA qw(sha256 sha256_hex sha512);
#use Digest::SHA1 qw(sha1);
#use Digest::MD5 qw(md5);
#use HTTP::Date;
use gerr qw(error);

sub new {
  my ($class,$serv,$client)=@_; if (ref($serv) !~ /^gserv/) { return }
  bless $client,$class;
  push @{$serv->{clients}}, $client;
  $client->{serv}=$serv;
  $serv->{numclients}++;
  $client->{http_response}={ version => "1.1", code => 0, head => [], body => "" };
  if ($serv->{sske}) {
    $client->{sske} = { transkey => gserv::createkey(), transfunc => gserv::createkey() };
    $client->{sskemode}=1
  }
  if ($serv->{verbose}) {
    $serv->log("JOIN $client->{ip}\:$client->{port} ($client->{host})")
  }
  if (ref($serv->{serverhandle}) eq 'CODE') { &{$serv->{serverhandle}}('connect',$client) }
  if (ref($serv->{clienthandle}) eq 'CODE') { &{$serv->{clienthandle}}($client,'connect') }
  return $client
}

sub delete {
  my ($client)=@_;
  $client->{server}->deleteclient($client);
}

################################################################################
# OUTPUT

sub wsmessage { my ($client,@msg)=@_; gserv::wsmessage($client,@msg); return $client }

sub out {
  my ($client,$data,$killafteroutput)=@_;
  if (!defined $data) { return }
  if (ref($data)){ $data=${$data} }
  if ($client->{sskeactive}) { $data=gserv::sskecrypt($client,$data,1) }
  if ($client->{outputmode}) {
    $client->{outputbuffer}.=$data;
    $client->{outputlength}+=length($data);
  } else {
    $client->{outputmode}=1;
    $client->{outputbuffer}=$data;
    $client->{outputlength}=length($data);
    $client->{outputpointer}=0
  }
  if (defined $killafteroutput) { $client->{killafteroutput}=$killafteroutput }
  return $client
}

sub outsock {
    my ($client, $data) = @_;
    if (!$client->{server}{isserver}) {
        error "Design change version 4! \$client->outsock demands the server! Use out or burst instead";
    }
    my $sock = $client->{socket};
    if (!$sock) {
        if (ref($client->{server}{clienthandle}) eq 'CODE') {
            $client->{server}{clienthandle}->($client, 'kill', "no socket");
        }
        $client->{killme} = 1;
        return;
    }
    if (!IO::Socket::connected($sock)) {
        if (ref($client->{server}{clienthandle}) eq 'CODE') {
            $client->{server}{clienthandle}->($client, 'kill', "not connected");
        }
        $client->{killme} = 1;
        return;
    }
    if ($client->{ssl}) {
        my $len = length($data);
        if ($len <= 16384) {
            my $written;
            while (1) {
                $written = syswrite($sock, $data, $len);
                if (defined $written && $written == $len) {
                    last; # Succes
                }
                #$client->{server}->log("ERROR: syswrite failed for client $client->{ip}:$client->{port} [expected $len, wrote " . (defined $written ? $written : "undef") . "] $!");
                if ($! == POSIX::EAGAIN || $! == POSIX::EWOULDBLOCK) {
                    Time::HiRes::usleep(10000); # 10ms wachten bij EAGAIN
                } else {
                    $client->{killme} = 1;
                    return; # Fatale fout
                }
            }
            return;
        }
        my $pos = 0;
        my $sz = 16384;
        while ($pos < $len) {
            if ($pos + $sz > $len) {
                $sz = $len - $pos;
            }
            my $written;
            while (1) {
                $written = syswrite($sock, substr($data, $pos, $sz), $sz);
                if (defined $written && $written == $sz) {
                    last; # Succes
                }
                #$client->{server}->log("ERROR: syswrite failed for client $client->{ip}:$client->{port} [expected $sz, wrote " . (defined $written ? $written : "undef") . "] $!");
                if ($! == POSIX::EAGAIN || $! == POSIX::EWOULDBLOCK) {
                    Time::HiRes::usleep(10000); # 10ms wachten bij EAGAIN
                } else {
                    $client->{killme} = 1;
                    return; # Fatale fout
                }
            }
            $pos += $written;
        }
    } else {
        for my $i (0..length($data)-1) {
            my $chr = substr($data, $i, 1);
            print $sock (ord($chr) < 256 ? $chr : HTML::Entities::encode_entities($chr));
        }
    }
    my $len = length($data);
    $client->{bytessent} += $len;
    if (ref($client->{server}{clienthandle}) eq 'CODE') {
        $client->{server}{clienthandle}->($client, 'sent', $len);
    }
    return $client;
}

sub burst {
  # burst some output
  my ($client,$data,$killafteroutput) = @_;
  if (ref($data) ne "SCALAR") { error("Gserv::Client.Burst: Design error, use \\\$data for much faster comunication!") }
  $client->{burstdata}=$data;
  $client->{burstlength}=length(${$data});
  $client->{burstpointer}=0;
  if ($client->{burstlength}) { $client->{burstmode}=1 }
  if (defined $killafteroutput) { $client->{killafteroutput}=$killafteroutput }
  if (ref($client->{server}{clienthandle}) eq 'CODE') {
    $client->{server}{clienthandle}->($client,'burst',"$client->{burstdata}:$client->{burstlength}:$client->{killafteroutput}:$client->{burstpointer}:".length(${$client->{burstdata}}))
  }
  return $client
}

sub burstfile {
  # burst some output
  my ($client,$head,$file,$killafteroutput,$filter) = @_;
  if (!-f $file) { error("Gserv::Client.BurstFile: File Not Found: $file") }
  $client->{bursthead}=$head;
  $client->{burstfile}=$file;
  $client->{burstfilter}=$filter;
  $client->{burstlength}=-s $file;
  $client->{burstpointer}=0;
  if ($client->{burstlength}) { $client->{burstmode}=1 }
  if (defined $killafteroutput) { $client->{killafteroutput}=$killafteroutput }
  if (ref($client->{server}{clienthandle}) eq 'CODE') {
    $client->{server}{clienthandle}->($client,'burst',"$client->{burstfile}:$client->{burstlength}:$client->{killafteroutput}:$client->{burstpointer}:".(-s $client->{burstfile}))
  }
  return $client
}

################################################################################
# HTTP RESPONSE

sub httpversion {
  my ($client,$version)=@_;
  if (defined $version) {
    $client->{http_response}{version}=$version;
    return $client
  }
  return $client->{http_response}{version}
}

sub httpcode {
  my ($client,$code)=@_;
  if (defined $code) {
    $client->{http_response}{code}=gserv::httpresponse($code,$client->{http_response}{version});
    return $client
  }
  return $client->{http_response}{code} 
}

sub httphead {
  my ($client,@header)=@_;
  if ($#header > -1) {
    push @{$client->{http_response}{head}},@header;
    return $client
  }
  return $client->{http_response}{head}
}

sub contenttype {
  my ($client,$type)=@_;
  if (defined $type) {
    if (!defined $client->{http_response}{type}) {
      $client->{http_response}{type}=$type;
      $client->httphead("Content-type: $client->{http_response}{type}")
    }
    return $client
  }
  return $client->{http_response}{type}
}

sub contentbody {
  my ($client,$body)=@_;
  if (defined $body) {
    $client->{http_response}{length} = length($body);
    $client->httphead("Content-length: $client->{http_response}{length}");
    $client->{http_response}{body} = $body;
    return $client
  }
  return $client->{http_response}{body}
}

sub httpresponse {
  my ($client)=@_;
  if (!defined $client->{http_response}{length} && length($client->{http_response}{body})) {
    $client->{http_response}{length} = length($client->{http_response}{body});
    $client->httphead("Content-length: $client->{http_response}{length}");
    if (!defined $client->{http_response}{type}) { $client->contenttype("text/html") }
  }
  if ($client->{http_response}{code} eq 0) { $client->httpcode(200) }
  return $client->httpcode()."\r\n".join("\r\n",@{$client->httphead()})."\r\n\r\n".$client->contentbody();
}

sub httprespond {
  my ($client,$killafteroutput)=@_;
  return $client->out($client->httpresponse(),$killafteroutput)
}


################################################################################
# EOF gserv::client.pm (C) 2020 OnEhIppY @ Domero
1