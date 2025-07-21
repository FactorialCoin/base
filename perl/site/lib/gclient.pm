#!/usr/bin/perl

package gclient;

######################################################################
#                                                                    #
#          TCP/IP client                                             #
#           - raw, telnet, HTTP/1.1, WebSockets, IceCast2            #
#           - SSL & SSKE support                                     #
#           - fully bidirectional non-blocking, all systems          #
#           - http reader supports chunked, gzip, auto redirect      #
#           - RSS compatible                                         #
#                                                                    #
#          (C) 2019 Chaosje, Domero                                  #
#          ALL RIGHTS RESERVED                                       #
#                                                                    #
######################################################################

############## Caller Events #########################################
#                                                                    #
#  command    data                                                   #
#  ---------- ------------------------------------------------------ #
#  error      error message                                          #
#  init       called before connect, init variables                  #
#  verboseheader  debug HTTP headers                                 #
#  connect    connection established, you may read and write now     #
#  input      raw byte input received                                #
#  noinput    no input received after read attempt                   #
#  loop       called in every takeloop if loopmode==1 (master mode)  #
#  quit       connection lost                                        #
#                                                                    #
###### HTTP/1.1 ######################################################
#  connected  connection time                                        #
#  request    require request method                                 #
#  header     require header information                             #
#  auth       require authorization information                      #
#  post       set post data                                          #
#  inform     information about server returns                       #
#  reconnect  client has quit, new handle is the parameter           #
#  ready      headers & website has been read                        #
#                                                                    #
###### TELNET ########################################################
#                                                                    #
###### ICECAST 2 #####################################################
#  icemount   mounting info required                                 #
#  icedelay   called every 100msec                                   #
#  icesong    new song info required (for metadata)                  #
#  icedata    new data required                                      #
#                                                                    #
######################################################################
#  N.B. To signal if a socket connection has established,            #
#       use connectcallback, this to not break a server that has a   #
#       client in its loop.                                          #
#                                                                    #
#       When loopmode==0, call $clienthandle->takeloop() as part of  #
#       your own main-loop.                                          #
#                                                                    #
######################################################################

use strict;
no strict 'refs';
use warnings; no warnings qw<uninitialized>;
use Socket;
use utf8;
use gerr qw(error);
use IO::Handle;
use IO::Select;
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::SSL;
use Crypt::Ed25519;
use Digest::SHA qw(sha256 sha256_hex sha512);
use URL::Encode qw(url_encode_utf8);
use MIME::QuotedPrint;
use Exporter;
use Time::HiRes qw(gettimeofday usleep);
use Digest::SHA1 qw(sha1);
use Compress::Bzip2 qw(bzinflateInit);
use Compress::Raw::Zlib;
use Compress::Zlib;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use gparse;

$VERSION     = '9.1.4';
@ISA         = qw(Exporter);
@EXPORT      = qw(out websocket tcpip http wsmsg wsquit wsinput localip telnet website icecast2 icecast2_metadata cpu32);
@EXPORT_OK   = qw(openconnection in spliturl querydata encode_base64);

my $TELNET=telnet_init();
my $cpu32 = (~0 == 4294967295);

1;

sub openconnection {
  # Opens a RAW binary non-blocking bi-directional connection, timeout in seconds.
  my ($host,$port,$linemode,$timeout,$ssl,$connectcallback,$sni) = @_;
  my $self = {}; bless $self;
  if (!$linemode) { $linemode=0 }
  if (!$timeout) { $timeout=10 }

  $self->{error}="";
  $self->{host}=$host;
  $self->{port}=$port;
  $self->{localip}=localip();
  $self->{ssl}=$ssl;
  $self->{timeout}=$timeout;
  $self->{linemode}=$linemode;
  $self->{upgrademode}=0;
  $self->{upgradebuf}="";
  $self->{upgradetime}=0;
  $self->{connected}=0;
  $self->{connecttime}=0;
  $self->{loopmode}=0;
  $self->{protocol}="";
  $self->{websocket}=0;
  $self->{telnet}=0;
  $self->{http}=0;
  $self->{icecast}=0;
  $self->{error}="";
  $self->{quit}=0;
  $self->{caller}=\&dummycaller;
  $self->{buffer}=[];
  $self->{curline}="";
  $self->{dataready}=0;
  $self->{inputfound}=0;
  $self->{output}=0;
  $self->{outputpointer}=0;
  $self->{outputlength}=0;
  $self->{outputbuffer}="";
  $self->{outputlines}=[];
  $self->{connectlooptime}=0.01,
  $self->{waitforinput}=1;
  $self->{connectcallback}=$connectcallback;
  $self->{lastconnect}=gettimeofday();
  $self->{readbufsize}=16384*16;

  # Connect to server
  my $proto = (getprotobyname('tcp'))[2];
  my $iaddr = inet_aton($self->{host});
  my $err=""; my $sock;
  $self->{servervec} = "";

  if ((!defined $iaddr) || (length($iaddr)!=4)) {
    $self->{error}="Unable to resolve IP"; return $self
  } elsif ($ssl) {
    my $sslerr=0;
    if ($sni) {
      $self->{socket}=IO::Socket::SSL->new(
        PeerHost => $self->{host},
        PeerPort => $self->{port},
        SSL_verify_mode => SSL_VERIFY_PEER,
        SSL_verifycn_name => $sni,
        SSL_verifycn_scheme => 'http',
        SSL_hostname => $sni
      ) or $sslerr=1;
    } else {
      $self->{socket}=IO::Socket::SSL->new(
        PeerHost => $self->{host},
        PeerPort => $self->{port},
        SSL_verify_mode => SSL_VERIFY_PEER
      ) or $sslerr=1;
    }
    if ($sslerr) { $self->{error}=$SSL_ERROR; return $self }
    $sock=$self->{socket};
    select($sock); $|=1; select(STDOUT);
    # Set non blocking mode
    $sock->blocking(0);                                             # linux
    my $nonblocking = 1; ioctl($sock, 0x8004667E, \$nonblocking);   # windows

    # Set autoflush on socket
    $sock->autoflush(1);
    #select($self->{socket}); 
    binmode($sock); 

    setsockopt($sock,SOL_SOCKET, SO_RCVTIMEO, 15);
    setsockopt($sock,SOL_SOCKET, SO_SNDTIMEO, 15);
  } else {
    $self->{socket}=undef;
    socket($sock, AF_INET, SOCK_STREAM, $proto) or $err="Cannot create socket on [$host:$port]: $!";
    if ($err) { $self->{error}=$err; return $self }  

    select($sock); $|=1; select(STDOUT);
    # Set non blocking mode
    $sock->blocking(0);                                             # linux
    my $nonblocking = 1; ioctl($sock, 0x8004667E, \$nonblocking);   # windows

    # Set autoflush on socket
    $sock->autoflush(1);
    #select($self->{socket}); 
    binmode($sock); 

    setsockopt($sock,SOL_SOCKET, SO_RCVTIMEO, 15);
    setsockopt($sock,SOL_SOCKET, SO_SNDTIMEO, 15);

    my $paddr = sockaddr_in($self->{port}, $iaddr);

    vec($self->{servervec}, fileno($sock), 1) = 1;
    select(undef, $self->{servervec}, undef, $self->{connectlooptime});
    my $vec=vec($self->{servervec}, fileno($sock), 1);
    if(!connect($sock, $paddr)){
      if ($!{EINPROGRESS}) {
        my $select = IO::Select->new($sock);
        my @ready = $select->can_write($self->{timeout});
        if (!@ready) {
          $err = "Connection timeout or error $! ".(0+$!);
        }
      } else {
        $err = "Could not connect to server [$host:$port]: $! ".(0+$!);
      }
    }
    select(STDOUT); $|=1;
    if ($err) {
      if (($err !~ /\s140$/) && ($err !~ /\s115$/)) {
        shutdown($sock,2); close($sock);
        my ($i,$e) = split(/\]\: /,$err);
        if (($e =~ /no connection/i) && ($e =~ /refused/i)) {
          $err="Remote host is offline"
        } elsif ((($e =~ /forcibly/i) || ($e =~ /closed/i)) && (($e =~ /existing/i) || ($e =~ /established/i))) {
          $err="Lost connection to remote host"
        } elsif (($e =~ /forcibly.*closed/i) || ($e =~ /established.*aborted/i)) {
          $err="Remote host closed the connection"
        }
        $self->{error}=$err; return $self
      }
    }
    $self->{socket}=$sock;
  }

  # Set output to console
  select(STDOUT); if ($::GCLIENT_UTF8) { binmode STDOUT, ":encoding(UTF-8)" } else { binmode STDOUT }; $|=1;

  # selectors are used to poll the pipe if we can read/write, so we don't flood an never waste any time.
  $self->{selector}=IO::Select->new($sock);

  return $self
}

sub connectready {
  # non-blocking connect !
  my ($self) = @_;
  if ($self->{quit}) { return }
  my $sock=$self->{socket};
  if (!$sock) { $self->quit }
  vec($self->{servervec}, fileno($sock), 1) = 1;
  select(undef, $self->{servervec}, undef, $self->{connectlooptime});
  if (vec($self->{servervec}, fileno($sock), 1)) {
    $self->{waitforinput}=0;
    $self->{connecttime}=gettimeofday();
    my $tm=$self->{connecttime}-$self->{lastconnect};
    $self->{connectspeed}=$tm;
    $self->{connected}=1;
    if ($self->{connectcallback}) {
      my $callback=$self->{connectcallback};
      &$callback($self,$tm)
    }
  } elsif ($self->{connected}) {
    my $tm=gettimeofday()-$self->{lastconnect};
    if ($tm>$self->{timeout}) {
      $self->{error}="Could not establish connection to server [$self->{host}:$self->{port}]";
      $self->quit;
    }
  }
}

sub dummycaller {
  my ($client,$cmd,$data) = @_;
}

sub canread {
  my ($self) = @_;
  my $sock=$self->{socket};
  my @ready = $self->{selector}->can_read(0);
  foreach my $handle (@ready) {
    if ($handle == $sock) {
      return 1
    }
  }
  return 0
}

sub canwrite {
  my ($self) = @_;
  my $sock=$self->{socket};
  my @ready = $self->{selector}->can_write(0);
  foreach my $handle (@ready) {
    if ($handle == $sock) {
      return 1
    }
  }
  return 0
}

sub readsocket {
  my ($self,$func) = @_;
  if ($self->{quit}) { return }
  if ($self->{waitforinput}) {
    $self->connectready;    
    if ($self->{waitforinput}) {
      return ""
    }
  }
  my $sock=$self->{socket};
  my $caller=$self->{caller};
  if (!$sock) { 
    &$caller($self,'error',"Socket disconnected");
    $self->{error}="Socket disconnected"; $self->quit; return
  }
  my $buf="";
  if ($self->canread()) {
    if ($self->{ssl}) {
      sysread($sock,$buf,$self->{readbufsize})
    } else {
      recv($sock,$buf,$self->{readbufsize},0)
    }
    if ($self->{debug}) { print STDOUT print "READ: $buf\n" }
    if ($buf eq "") {
      my $err = $! + 0;
      if ($err) {
        if ($self->{debug}) { print STDOUT print "ERR $err\n" }
        if (($! != 11) && ($! != 16)) { # EAGAIN EBUSY
          if ($err == 10035) {
            # 10035 = WSAEWOULDBLOCK (Windows sucking non-blocking sockets)
            return
          } elsif ($err == 140) {
            # 140 = A non-blocking socket operation could not be completed immediately.
            return 
          } elsif ($err == 10053) {
            &$caller($self,'error',"Connection terminated by client");
            $self->{error}="Connection terminated by client"; $self->quit; return
          } elsif ($err == 10054) {
            &$caller($self,'error',"Lost Internet");
            $self->{error}="Lost Internet"; $self->quit; return
          } else {
            # ERROR !
            &$caller($self,'error',"Connection error: [$err] $!");
            $self->{error}="Connection error: [$err] $!"; $self->quit; return
          }
        }   
      } elsif ($self->{dataready} && length($self->{curline})) {
        push @{$self->{buffer}},$self->{curline};
        $self->{curline}="";
      } elsif (!$func) {
        &$caller($self,'noinput');
      } elsif ($self->{lastconnect}) {
        my $tmo=int(gettimeofday() - $self->{lastconnect});
        if ($self->{debug}) { print STDOUT print "\r$tmo" }
        if ($tmo > 10) {
          if (!defined $self->{waitingloop}){ $self->{waitingloop}=0 }
          $self->{waitingloop}++;
          if($self->{waitingloop}>10000) {
            &$caller($self,'error',"Connection Timeout!");
            $self->{error}="Connection Timeout!"; $self->quit; return
          }
        }
      } else {
        $self->{lastconnect}=gettimeofday()
      }
    } else {
      if ($self->{debug}) { print STDOUT "[INPUT-buffer]\n$buf\n[end-INPUT]\n" }
      if (!$self->{linemode}) {
        $self->{dataready}=1;
        $self->{curline}.=$buf
      } else {
        my $data=$self->{curline}.$buf;
        my $line=$self->{curline}; my $pos=length($self->{curline}); my $len=length($data); 
        my $cr=0; if ($pos>0) { if (ord(substr($line,-1)) == 13) { $pos--; $line=substr($line,0,-1); $cr=1 } }
        while ($pos<$len) {
          my $c=substr($data,$pos,1);
          if (ord($c) == 13) {
            if ($cr) { $line.=chr(13) }
            $cr=1;
          } elsif (ord($c) == 10) {
            if ($cr || ($pos+1==$len)) {
              $self->{dataready}=1;
              push @{$self->{buffer}},$line; $line=""
            } else {
              $line.=chr(10)
            }
            $cr=0
          } else {
            if ($cr) { $line.=chr(13) }
            $line.=$c; $cr=0
          }
          $pos++
        }
        if ($cr) { $line.=chr(13) }
        $self->{curline}=$line;
      }
    }
  }
}

sub in {
  my ($self,$func) = @_;
  if ($self->{quit}) { return }
  $self->readsocket($func);
  if (!$self->{dataready}) { return undef }
  if (!$self->{linemode}) {
    my $dat=$self->{curline};
    $self->{curline}="";
    $self->{dataready}=0;
    return $dat
  }  
  my $line=$self->{buffer}[0];
  splice(@{$self->{buffer}},0,1);
  if ($#{$self->{buffer}} < 0) {
    $self->{dataready}=0    
  }
  return $line
}

sub out {
  my ($self,$data) = @_;
  if ($self->{quit}) { return }
  if ($self->{waitforinput}) {
    $self->connectready;    
    if ($self->{waitforinput}) { return }
  }
  if (!defined $data) { return }
  if (!length($data)) { return }
  if (ref($self->{sske}) eq 'HASH' && $self->{sskeactive}) { $data=$self->crypt($data,1) }
  if ($self->{linemode}) {
    $self->{output}=1;
    foreach my $line (split (/\n/,$data)) {
      $line =~ s/\r//g;
      push @{$self->{outputlines}},$line
    }
  } elsif (!$self->{output}) {
    $self->{output}=1;
    $self->{outputbuffer}=$data;
    $self->{outputpointer}=0;
    $self->{outputlength}=length($data)
  } else {
    $self->{outputbuffer}.=$data;
    $self->{outputlength}+=length($data)
  }
}

sub outloop {
  my ($self) = @_;
  if ($self->{quit}) { $self->{output}=0; return }
  if ($self->{waitforinput}) {
    if ($self->{quitting}) { $self->{output}=0; return }
    $self->connectready;    
    if ($self->{waitforinput}) {
      # not connected yet
      return
    }
  }
  if (!$self->{output}) { return }
  my $sz=16384;
  my $sock=$self->{socket};
  if (!$sock || !IO::Socket::connected($sock)) {
    my $caller=$self->{caller};
    $self->{output}=0;
    &$caller($self,'error',"Socket disconnected");
    $self->{error}="Socket disconnected"; $self->quit; return
  }
  if ($self->canwrite) {
    if ($self->{linemode}) {
      my $data=shift @{$self->{outputlines}};
      $data.="\r\n";
      if ($self->{ssl}) {
        syswrite($sock,$data,length($data))
      } else {
        send($sock,$data,0);
      }
      if ($#{$self->{outputlines}}<0) {
        $self->{output}=0
      }
    } elsif ($self->{outputpointer}<$self->{outputlength}) {
      if ($self->{outputlength}-$self->{outputpointer}<$sz) { $sz=$self->{outputlength}-$self->{outputpointer} }
      my $data=substr($self->{outputbuffer},$self->{outputpointer},$sz);
      if ($self->{debug}) { print STDOUT " >> $self->{host} $sz\n" }
      if ($self->{ssl}) {
        syswrite($sock,$data,length($data))
      } else {
        send($sock,$data,0);      
      }
      $self->{outputpointer}+=$sz;
      if ($self->{outputlength}<=$self->{outputpointer}) {
        $self->{output}=0
      }
    } else {
      $self->{output}=0
    }
  }
}

sub outburst {
  my ($self) = @_;
  if (!$self->{burstmode}) {
    $self->{burstmode}=1;
    while ($self->{output}) {
      $self->outloop()
    }
    $self->{burstmode}=0;
  }
}

sub takeloop {
  my ($self) = @_;
  my $caller=$self->{caller};
  if ($self->{quit}) {
    if ($self->{loopmode}) { exit 1 }
    return
  }
  if ($self->{websocket}) { 
    $self->wsinput() 
  } else {
    my $data=$self->in('loop');
    if ($self->{upgrademode}) {
      if (!$data) {
        if (gettimeofday()-$self->{upgradetime}>$self->{timeout}) {
          $self->{error}="WebSocket upgrade timeout";
          &$caller($self,"error","62 WebSocket upgrade timeout");
          $self->quit; return
        }
      } else {
        $self->wsupgrade($data)
      }
    } elsif (defined $data) {
      &$caller($self,"input",$data)
    }
  }
  if ($self->{loopmode}) {
    &$caller($self,"loop");
  }
  $self->outloop()
}

###############################################################################
# Raw TCP/IP                                                                  #
###############################################################################

sub tcpipconnected {
  my ($self,$tm) = @_;
  my $caller=$self->{caller};
  &$caller($self,'connect',$tm)
}

sub tcpip {
  my ($host,$port,$loopmode,$caller,$ssl,$linemode,$timeout,$connectcallback,$sni) = @_;
  if (ref($caller) ne 'CODE') { error "GClient.tcpip: Caller is not a procedure-reference" }
  if (!defined $connectcallback || !$connectcallback || (ref($connectcallback) ne 'CODE')) {
    $connectcallback=\&tcpipconnected
  }  
  my $self=openconnection($host,$port,$linemode,$timeout,$ssl,$connectcallback,$sni);
  $self->{caller}=$caller;
  if ($self->{error}) { &$caller($self,"quit",$self->{error}); $self->quit; return $self }
  if ($loopmode) { $self->{loopmode}=1 }
  &$caller($self,'init',gettimeofday());
  if ($loopmode) {
    while (!$self->{quit}) { $self->takeloop() }
  }
  return $self
}

###############################################################################
# Telnet                                                                      #
###############################################################################

sub telnet {
  # RFC 854 & 855
  my ($host,$port,$loopmode,$caller,$timeout,$ssl,$sni) = @_;
  if (ref($caller) ne 'CODE') { error "GClient.telnet: Caller is not a procedure-reference" }
  if (!$port) { 
    $port=23;
    if ($ssl) { $port=1337 } # as used by stunnel, ssl on telnet is arbitrary
  }
  my $self=openconnection($host,$port,$loopmode,$timeout,$ssl,\&tcpipconnected,$sni);
  $self->{protocol}='telnet'; $self->{telnet}=1;
  $self->{usercaller}=$caller;
  $self->{caller}=\&handle_telnet;
  if ($self->{error}) { &$caller($self,"quit",$self->{error}); $self->quit; return $self }
  if ($loopmode) { $self->{loopmode}=1 }
  $self->{status}={ 
    mode => 'char',
    echo => 1,
    binary => 1,
    localchars => 1,
    buffer => "",
    xpos => 0, ypos => 0,
    width => 80, height => 24
  };
  &$caller($self,'init',gettimeofday());
  if ($loopmode) {
    while (!$self->{quit}) { $self->takeloop() }
  }
  return $self
}

sub handle_telnet {
  my ($self,$command,$data) = @_;
  my $mode=$self->{status}{mode};
  if ($command eq 'input') {
    if ($mode eq 'char') {
      my $chr=ord($data)
    } elsif ($mode eq 'line') {
      my $last=ord(substr($data,-1,1));

    }
    # set line mode

  } elsif ($command eq 'connect') {
    $self->telnet_cmd('DO Binary');
    
  }
}

sub telnet_cmd {
  my ($self,$command) = @_;
  my @list = split(/ /,$command);
  my @bytes = ();
  foreach my $cmd (@list) {
    if ($TELNET->{$cmd}) { push @bytes,$TELNET->{$cmd} }
    else { error "GClient.telnet_cmd: Command '$cmd' unknown in '$command'" }
  }

}

sub telnet_init {
  return {
    NUL => 0, BEL => 7, BS => 8, HT => 9, LF => 10, VT => 11, FF => 12, CR => 13,
    SE => 240, NOP => 241, DataMark => 242, BRK => 243, IP => 244, AO => 245,
    AYT => 246, EC => 247, EL => 248, GA => 249, SB => 250,
    WILL => 251, WONT => 252, DO => 253, DONT => 254, IAC => 255,
    ExtOpt => 255, Binary => 0, Echo => 1, SupGA => 3, Status => 5, TimeMark => 6,
    LineMode => 34, Reconnect => 2, AprSize => 4, RC => 7, OutWidth => 8, OutPageSize => 9,
    OutCR => 10, OutTabStops => 11, OutTab => 12, OutFF => 13, OutVertTabsStops => 14,
    OutVertTab => 15, OutLF => 16, ExtAsc => 17, Logout => 18, ByteMacro => 19,
    DataEntry => 20, SUPDUP => 21, SUPDUPOut => 22, SendLoc => 23, TermType => 24,
    EOR => 25, TACACS => 26, OutMark => 27, TermLoc => 28, '3270' => 29, X3Pad => 30,
    NegWinSize => 31, TermSpeed => 32, RemoteFlow => 33, XDispLoc => 35, EnvOpt => 39,
    AuthOpt => 37
  }
}

###############################################################################
# Hyper Text Transfer Protocol (HTTP) version 1.1                             #
###############################################################################

sub http {
  # RFC 2068, 2616
  # ZLIB RFC 1950, DEFLATE RFC 1951, GZIP RFC 1952
  # Chunked data encoding RFC 2616 3.6.1
  # RFC 2616 14.23 HTTP/1.1 requires request Host 
  my ($host,$port,$loopmode,$caller,$timeout,$ssl,$sni,$sske,$path,$query,$user,$pass) = @_;
  if (ref($caller) ne 'CODE') { error "GClient.http: Caller is not a procedure-reference" }
  if (!$port) { $port=($ssl ? 443:80) }
  if ($path && (substr($path,0,1) ne '/')) { $path='/'.$path }
  my $self=openconnection($host,$port,0,$timeout,$ssl,\&tcpipconnected,$sni);
  $self->{path}=$path; $self->{query}=$query;
  $self->{protocol}='http'; $self->{http}=1;
  $self->{usercaller}=$caller; $self->{sskeround}=1;
  $self->{caller}=\&handle_http;
  if ($self->{error}) { &$caller($self,"quit",$self->{error}); $self->quit; return $self }
  if ($loopmode) { $self->{loopmode}=1 }
  $self->{httpinfo} = {
    request => "", header => {}, postdata => "", wantpost => 0,
    user => $user, pass => $pass,
    response => "", rescode => 0, readhead => 1, reshead => {}, wanted => 0,
    website => "", chunked => 0, chunkmode => 0, chunkhex => "", chunkext => "",
    chunkdata => "", chunksize => 0, encoding => "", trailer => {}
  };
  $self->{sskeactive}=0;
  if ($sske) {
    $self->{sske} = {
      symkey => createkey(),
      symfunc => createkey(),
      transkey => createkey(),
      transfunc => createkey()
    };
    $self->{httpinfo}{header}{'Symmetric-Key'}=octhex(scramblekey($self->{sske}{symkey},$self->{sske}{transkey},$self->{sske}{transfunc}));
    $self->{httpinfo}{header}{'Symmetric-Function'}=octhex(scramblekey($self->{sske}{symfunc},$self->{sske}{transkey},$self->{sske}{transfunc}));
  } else {
    $self->{sskeround} = 9
  }
  # parameters one can change on init event
  $self->{noredirect}=0;
  &$caller($self,'init',gettimeofday());
  if ($loopmode) {
    while (!$self->{quit}) { $self->takeloop() }
  }
  return $self  
}

sub handle_http {
  my ($self,$command,$data) = @_;
  if ($self->{debug} && $command ne 'loop') { print STDOUT "#### $command - $data\n" }
  my $caller=$self->{usercaller};
  if ($command eq 'error') {
    &$caller($self,'error',$data)
  } elsif ($command eq 'connect') {
    if (ref($self->{sske}) ne 'HASH' || ($self->{sskeround} == 1)) {
      &$caller($self,'connected',$data)
    }
    if (!$self->{httpinfo}{request} || (ref($self->{sske}) eq 'HASH' && ($self->{sskeround} == 1))) {
      $self->{httpinfo}{request}="GET / HTTP/1.1";
      $self->{httpinfo}{wantpost}=0;
      if ($self->{debug}) { print STDOUT "[SET-REQUEST][$self->{httpinfo}{request}]\n" }
    }
    if (!$self->{norequest} && (ref($self->{sske}) ne 'HASH' || ($self->{sskeround} > 1))) {
      #if (!$self->{path} && !$self->{query}) {
      &$caller($self,'request');
      #} else {
      #  my $rfunc=$self->{reqmeth}||'';
      #  if ($rfunc && defined &$rfunc) {
      #    &$rfunc($self,$self->{path},$self->{query})
      #  } else {
      #    &$caller($self,'error',"Invalid request method: $rfunc")
      #  }
      #}
      if ($self->{debug}) { print STDOUT "[SET-REQUEST][$self->{httpinfo}{request}]\n" }
      if ($self->{httpinfo}{wantpost}) {
        $self->boundary();
        &$caller($self,'post')
      }
    }
    # store request to detect cyclic redirect loops
    my $hist={ host => $self->{host}, port => $self->{port} };
    if ($self->{history}) {
      push @{$self->{history}},$hist
    } else {
      $self->{history} = [ $hist ]
    }
    if (!$self->{norequest} && (ref($self->{sske}) ne 'HASH' || ($self->{sskeround} > 1))) {
      &$caller($self,'header')
    }
    if (!$self->{httpinfo}{header}{Host} && (!ref($self->{sske}) || ($self->{sskeround} == 1))) {
      # host required in HTTP/1.1
      $self->{httpinfo}{header}{Host}=$self->{host};
    }
    if ($self->{sskeround} > 1) {
      if ($self->{httpinfo}{user} && $self->{httpinfo}{pass}) {
        $self->auth(undef,$self->{httpinfo}{user},$self->{httpinfo}{pass})
      } elsif ($self->{httpinfo}{pass}) {
        $self->auth('bearer',undef,$self->{httpinfo}{pass})
      }
    }
    if ($self->{debug}) { print STDOUT "[handle_http]".gparse::str($self)."\n" }
    $self->sendheader()
  } elsif ($command eq 'input') {
    if ($self->{httpinfo}{chunkmode}) {
      $self->readchunks($data); return
    }
    my @sl=split(/\r\n/,$data,-1); # LIMIT of -1 maintains the presence of undef at end-of-list 
    while ($self->{httpinfo}{readhead}) {
      if ($#sl < 0) { last }
      my $line=shift @sl;
      if (!$self->{httpinfo}{response}) {
        $self->{httpinfo}{response}=$line;
        my ($ver,$code,@txt) = split(/ /,$line);
        $self->{httpinfo}{rescode}=$code;
      } elsif ($line eq "") { 
        $self->{httpinfo}{readhead}=0;
        $self->correctheader();
        $self->handlesske();
        if ($self->{verboseheader}) {
          my @out=("[HEADER IN]");
          for my $k (sort keys %{$self->{httpinfo}{reshead}}) {
            push @out,"$k => ".$self->{httpinfo}{reshead}{$k}
          }
          print STDOUT join("\n",@out)."\n"
        }
        $data=join("\r\n",@sl);
      } else {
        my ($key,@val) = split(/\:/,$line);
        my $v=join(":",@val); $v =~ s/^[\s\t]+//; $v =~ s/[\s\t]+$//;
        $self->{httpinfo}{reshead}{lc($key)}=$v;
        if (lc($key) eq 'content-length') {
          $self->{httpinfo}{wanted}=$v
        } elsif (lc($key) eq 'vary') {
          &$caller($self,'inform','vary '.$v)
        } elsif (lc($key) eq 'content-encoding') {
          $self->{httpinfo}{encoding}=lc($v)
        } elsif (lc($key) eq 'transfer-encoding') {
          if (lc($v) =~ /chunked/i) {
            $self->{httpinfo}{chunked}=1
          }
        } elsif (lc($key) eq 'trailer') {
          $v =~ s/[\s]//; my @tl=split(/\,/,$v);
          for my $t (@tl) {
            $self->{httpinfo}{trailer}{lc($t)}=1
          }
        }
      }
    }

    if (!$self->{httpinfo}{readhead}) {
      if (!$self->{httpinfo}{chunked}) {
        if ($self->{httpinfo}{wanted}) {
          $self->{httpinfo}{website}.=$data;
          if (length($self->{httpinfo}{website}) >= $self->{httpinfo}{wanted}) {
            $self->http_analyse()
          }
        } else {
          # no content-length info whatsoever.. just quit reading
          $self->http_analyse()
        }
      } else {
        $self->{httpinfo}{chunkmode}=1;
        $self->{httpinfo}{chunkdata}="";
        $self->readchunks($data);        
      }
    }
  }
}

sub readchunks {
  my ($self,$data) = @_;
  my $dt=$data; $dt =~ s/\r/\\r/gs; $dt =~ s/\n/\\n/gs;
  $self->{httpinfo}{chunkdata}.=$data;
  $data=$self->{httpinfo}{chunkdata};
  do {
    if ($self->{httpinfo}{chunkmode} == 1) {
      # read chunk (hexsize*[;ext[=val]]CRLF)
      if ($data =~ /^\r\n0[\r\n]*/) {
        $self->http_analyse(); return
      }
      if ($data =~ /^\r\n/) {
        my ($dump,@rest) = split(/\r\n/,$data,-1);
        $data=join("\r\n",@rest);
      }
      if ($data =~ /\r\n/) {
        my ($chunk,@rest) = split(/\r\n/,$data);
        $data=join("\r\n",@rest);
        $self->{httpinfo}{chunkdata}=$data;
        my $hex=""; my @cl = split(//,$chunk);
        for my $i (0..$#cl) {
          if ($cl[$i] =~ /[0-9a-fA-F]/) {
            $hex.=$cl[$i]
          } else {
            $self->{httpinfo}{chunkext}=substr($chunk,$i); last
          }
        }
        $self->{httpinfo}{chunksize}=hex($hex);
        $self->{httpinfo}{chunkmode}=2
      } else {
        # read more data
        return
      }  
    }
    if ($self->{httpinfo}{chunkmode} == 2) {
      # read chunklen data and take as is
      if ($self->{httpinfo}{chunksize}) {
        if (length($data) >= $self->{httpinfo}{chunksize}) {
          $self->{httpinfo}{website}.=substr($data,0,$self->{httpinfo}{chunksize});
          $data=substr($data,$self->{httpinfo}{chunksize});
          $self->{httpinfo}{chunkdata}=$data;
          $self->{httpinfo}{chunkmode}=1
        } else {
          # read more data
          return
        }
      } else {
        if ($data =~ /^\r\n0[\r\n]*/) {
          $self->http_analyse(); return
        }
        if ($data =~ /^\r\n/) {
          my ($dump,@rest) = split(/\r\n/,$data,-1);
          $data=join("\r\n",@rest);
        }
        if ($self->{httpinfo}{trailer}) {
          $self->{httpinfo}{chunkmode}=3;
        } else {
          $self->{httpinfo}{chunkmode}=1
        }
      }
    }
    if ($self->{httpinfo}{chunkmode} == 3) {
      # read trailer
      my @hl = split(/\r\n/,$data,-1);
      for my $line (@hl) {
        if (!$line) { $self->http_analyse(); return }
        my ($key,$val) = split(/\:/,$line); $val =~ s/^[\s]+//; $val =~ s/[\s]+$//;
        if (!$self->{httpinfo}{trailer}{lc($key)}) {
          my $caller=$self->{usercaller};
          &$caller($self,"inform","trailer illegal $key = $val")
        } else {
          $self->{httpinfo}{trailer}{lc($key)}=$val;
          $self->{httpinfo}{reshead}{lc($key)}=$val;
        }
      }
      $self->http_analyse(); return
    }
  } until (0)
}

# POST data

sub boundary {
  my ($self) = @_;
  if ($self->{boundary}) { return }
  my $seed=int (rand(100000000)+12345678); $seed.="Domero";
  foreach my $k (keys %{$self->{httpinfo}{header}}) {
    $seed.=$k.$self->{httpinfo}{header}{$k}
  }
  $self->{boundary}=substr(sha256_hex($seed),10,20);
  $self->sethdr("Content-Type","multipart/form-data; boundary=\"".$self->{boundary}."\"")
}

sub posturl {
  my ($self,$data) = @_;
  my $post=""; my @pl=();
  foreach my $k (keys %$data) {
    push @pl,$k."=".url_encode_utf8($data->{$k})
  }
  $post=join("&",@pl);
  $self->sethdr("Content-Type","application/x-www-form-urlencoded");
  $self->{httpinfo}{postdata}=$post;
  $self->sethdr("Content-Length",length($self->{httpinfo}{postdata}));
}

sub postjson {
  my ($self) = @_;
  $self->sethdr("Content-Type","application/json");
  $self->{httpinfo}{postdata}=JSON->new->allow_blessed->convert_blessed->utf8->canonical->pretty->encode($self->{query});
  $self->sethdr("Content-Length",length($self->{httpinfo}{postdata}));
}

sub postfile {
  my ($self,$type,$data,$encode) = @_;
  # for executables use type 'application/octet-stream' and encode undef
  if (!$encode) { $encode="" } $encode=lc($encode);
  $self->sethdr("Content-Type",$type);
  $self->setcoding($encode);
  $self->{httpinfo}{postdata}=encode($data,$encode);
  $self->sethdr("Content-Length",length($self->{httpinfo}{postdata}));
}

sub postdata {
  # RFC 7578
  my ($self,$name,$value,$filename,$type,$encode) = @_;
  if (!$value) { $value="" }
  my $data="--".$self->{boundary}."\r\nContent-Disposition: form-data";
  if ($name) { $data.="; name=\"$name\"" }
  if ($filename) { $data.="; filename=\"$filename\"" }
  if ($type) { $data.="\r\nContent-Type: $type" }
  if ($encode) {
    if (($encode eq 'base64') || ($encode eq 'quoted-printable') || ($encode eq '8bit') ||
        ($encode eq '7bit') || ($encode eq 'binary')) {
      # HTTP does not use the Content-Transfer-Encoding (CTE) field of RFC 2045.
      # Proxies and gateways from MIME-compliant protocols to HTTP MUST remove any non-identity CTE
      # ("quoted-printable" or "base64") encoding prior to delivering the response message
      # to an HTTP client.
      # (Chaosje) But a lot of servers will understand the CTE, so include it!
      $data.="\r\nContent-Transfer-Encoding: $encode"
    } elsif ($encode) {
      $data.="\r\nContent-Encoding: $encode"
    }
  }
  $self->{httpinfo}{postdata}.=$data."\r\n\r\n".encode($value,$encode)."\r\n";
}

sub postbody {
  my ($self,$mime,$data) = @_;
  if (!$mime) { $mime="text/html" }
  $self->sethdr("Content-Type",$mime);
  $self->{httpinfo}{postdata}=$data;
  my $len=0; if (defined $data) { $len=length($data) }
  $self->sethdr("Content-Length",$len)
}

sub setcharset {
  # RFC 7578 4.6 Set default charset (recommended)
  my ($self,$charset) = @_;
  if (!$charset) { $charset='utf8' }
  my $data="--".$self->{boundary}."\r\nContent-Disposition: form-data; name=\"_charset_\"";
  $self->{httpinfo}{postdata}.=$data."\r\n\r\n".$charset."\r\n"
}

sub postcharset {
  #  RFC 7578 4.5 Set charset for one Content-Disposition (not recommended)
  my ($self,$name,$value,$charset) = @_;
  if (!$value) { $value="" }
  if (!$charset) { $charset='utf8' }
  my $data="--".$self->{boundary}."\r\nContent-Disposition: form-data";
  if ($name) { $data.="; name=\"$name\"" }
  $data.="\r\nContent-Type: text/plain; charset=$charset\r\nContent-Transfer-Encoding: quoted-printable";
  $self->{httpinfo}{postdata}.=$data."\r\n\r\n".encode_qp($value)."\r\n"
}

sub nosniff {
  my ($self) = @_;
  $self->sethdr("X-Content-Type-Options","nosniff")
}

# http-requests

sub get {
  my ($self,$path,$info) = @_;
  req_get($self,'GET',$path,$info);
  return $self
}
sub head {
  # query GET but no response data expected
  my ($self,$path,$info) = @_;
  req_get($self,'HEAD',$path,$info);
  return $self
}
sub post {
  my ($self,$path) = @_;
  req_post($self,'POST',$path);
  return $self
}
sub patch {
  # update some data, 200 = OK, 204 = Not found
  my ($self,$path) = @_;
  req_post($self,'PATCH',$path);
  return $self
}
sub delete {
  # returns 200 = OK, 202 = Accepted, 204 = Not found  
  my ($self,$path) = @_;
  req_post($self,'DELETE',$path);
  return $self
}
sub put {
  # returns 200 = OK, 201 = Created new field, 204 = Not found 
  my ($self,$path) = @_;
  req_post($self,'PUT',$path);
  return $self
}
sub options {
  my ($self,$path) = @_;
  req_post($self,'OPTIONS',$path);
  return $self
}
sub trace {
  # debug POST call, no response data sent
  my ($self,$path) = @_;
  req_post($self,'TRACE',$path);
  return $self
}
sub connect {
  # open bi-directional tunnel to HTTPd
  my ($self,$path) = @_;
  req_post($self,'CONNECT',$path);
  return $self
}
sub source {
  # open bi-directional tunnel to HTTPd
  my ($self,$path,$info) = @_;
  req_get($self,'SOURCE',$path,$info);
  return $self
}

# Request-headers

sub auth {
  # RFC 2617
  my ($self,$method,$login,$pass) = @_;
  if (!$method) { $method='basic' }
  $method=lc($method); 
  if (!$login) { $login=$pass }
  if ($method eq 'basic') {
    my $code = encode_base64($login.":".$pass);
    $self->sethdr("Authorization","Basic $code")
  } elsif ($method eq 'bearer') {
    $self->sethdr("Authorization","Bearer $pass")
  }
  return $self
}

sub agent {
  my ($self,$agent) = @_;
  if (!$agent) { $agent='Mozilla/5.0 (compatible; Domero Perl Client '.$VERSION.')' }
  $self->sethdr('User-Agent',$agent);
  return $self
}
sub setcontent {
  my ($self,$type) = @_;
  if (!$type) { $type="text/html" }
  $self->sethdr("Content-Type",$type);
  return $self
}
sub accept {
  my ($self,$mime) = @_;
  if (!$mime) { $mime='*' }
  $self->setpar("Accept",$mime);
  return $self
}
sub lang {
  my ($self,$lang,$qval) = @_;
  if (!$lang) { $lang='*' }
  $self->setpar('Accept-Language',$lang,$qval);
  return $self
}
sub charset {
  my ($self,$charset,$qval) = @_;
  if (!$charset) { $charset='utf-8' }
  $self->setpar('Accept-Charset',$charset,$qval);
  return $self
}
sub ranges {
  my ($self,$ranges,$qval) = @_;
  if (!$ranges) { $ranges='bytes' }
  $self->setpar('Accept-Ranges',$ranges,$qval);
  return $self
}
sub age {
  my ($self,$age,$qval) = @_;
  if (!$age) { return $self }
  $self->sethdr('Age',$age);
  return $self
}
sub cache {
  # max-age=<seconds>, max-stale[=<seconds>, min-fresh=<seconds>, no-cache,
  # no-store, no-transform, only-if-cached
  my ($self,$cache) = @_;
  if (!$cache) { $cache='max-age=31536000' }
  $self->setpar('Cache-Control',$cache);
  return $self
}
sub nocache {
  my ($self) =@_;
  $self->sethdr('Cache-Control','no-cache');
  return $self
}

# current encoding

sub setcoding {
  my ($self,$code) = @_;
  if (!$code) { return }
  $code=lc($code);
  if (($code eq 'base64') || ($code eq 'quoted-printable') || ($code eq '8bit') ||
      ($code eq '7bit') || ($code eq 'binary') || ($code eq 'x-token')) {
    $self->sethdr("Content-Transfer-Encoding",$code)
  } else {
    $self->sethdr("Content-Encoding",$code);
  }
  return $self
}

# request encoding

sub nocoding {
  my ($self,$qval) = @_;
  $self->setpar('Accept-Encoding','identity',$qval);
  return $self
}
sub allcoding {
  my ($self,$qval) = @_;
  $self->setpar('Accept-Encoding','*',$qval);
  return $self
}
sub setcompress {
  my ($self,$qval) = @_;
  $self->setpar('Accept-Encoding','compress',$qval);
  return $self
}
sub gzip {
  my ($self,$qval) = @_;
  $self->setpar('Accept-Encoding','gzip',$qval);
  return $self
}
sub deflate {
  my ($self,$qval) = @_;
  $self->setpar('Accept-Encoding','deflate',$qval);
  return $self
}
sub broti {
  my ($self,$qval) = @_;
  $self->setpar('Accept-Encoding','br',$qval);
  return $self
}
sub setbzip2 {
  my ($self,$qval) = @_;
  $self->setpar('Accept-Encoding','bzip2',$qval);
  return $self
}
sub trailers {
  my ($self,$qval) = @_;
  $self->setpar('TE','trailers',$qval);
  return $self
}

# calls for website ready

sub response { my ($self) = @_; return $self->{httpinfo}{response} }
sub responsecode { my ($self) = @_; return $self->{httpinfo}{rescode} }
sub headers { my ($self) = @_; return $self->{httpinfo}{reshead} }
sub contenttype { my ($self) = @_; return $self->{httpinfo}{reshead}{'content-type'} }
sub content { my ($self) = @_; return $self->{httpinfo}{website} }

# internal http functions

sub req_get {
  my ($self,$req,$path,$info) = @_;
  if (!$path) { $path='/' }
  $self->{httpinfo}{request}="$req $path";
  if ($info) {
    if (ref($info)) {
      my @kl=keys %$info;
      if ($#kl>=0) {
        $self->{httpinfo}{request}.="?"; my @kv=();
        for my $k (@kl) {
          push @kv,$k."=".url_encode_utf8($info->{$k})
        }
        $self->{httpinfo}{request}.=join('&',@kv)
      }
    } else {
      $self->{httpinfo}{request}.="?$info"
    }
  }
  $self->{httpinfo}{request}.=" HTTP/1.1";
  return $self
}

sub req_post {
  my ($self,$req,$path) = @_;
  if (!$path) { 
    if($self->{debug}) { print "[ReqPost($req):PATH_NOT_SET]\n" }
    $path=$self->{path} || '/'
  }
  $self->{httpinfo}{request}="$req $path HTTP/1.1";
  $self->{httpinfo}{wantpost}=1;
  return $self
}

sub sethdr {
  my ($self,$key,$par) = @_;
  $self->{httpinfo}{header}{$key}=$par;
  return $self
}
sub setpar {
  my ($self,$key,$par,$qval) = @_;
  if ($qval) { $par.=";q=$qval" }
  if ($self->{httpinfo}{header}{$key}) {
    $self->{httpinfo}{header}{$key}.=", $par"
  } else {
    $self->{httpinfo}{header}{$key}=$par
  }
  return $self
}

########## INTERNAL ########################

sub sendheader {
  my ($self) = @_;
  my @data=( $self->{httpinfo}{request} );
  for my $k (keys %{$self->{httpinfo}{header}}) {
    if (defined $k) {
      push @data,$k.": ".($self->{httpinfo}{header}{$k}||'')
    }
  }
  my $rd=join("\r\n",@data)."\r\n\r\n";
  if ($self->{debug}) { print STDOUT "[sendheader]\n$rd\[end]\n" }
  $self->out($rd); $self->takeloop();
  if ($self->{sskeround} > 1) {
    $self->{sskeactive} = 1; # entering DSKE mode
  }
  if ($self->{httpinfo}{postdata}) {
    my $bd=""; if ($self->{boundary}) { $bd="--".$self->{boundary}."--" }
    if ($self->{debug}) { print STDOUT "[postdata]\n$self->{httpinfo}{postdata}$bd\r\n[end]\n" }
    $self->out($self->{httpinfo}{postdata}.$bd."\r\n");
    $self->takeloop()
  }
}

sub correctheader {
  # look for possible conflicts in the header not allowed by the RFC's and correct them
  my ($self) = @_;
  # Content-Length vs. chunked
  if ($self->{httpinfo}{chunked}) {
    if ($self->{httpinfo}{wanted}) {
      $self->{httpinfo}{wanted}=0;
      delete $self->{httpinfo}{reshead}{'content-length'}
    }
  }
}

sub decode {
  my ($self) = @_;
  if ($self->{httpinfo}{encoding} eq 'identity') { return }
  if (($self->{httpinfo}{encoding} eq 'gzip') || ($self->{httpinfo}{encoding} eq 'x-gzip')) {
    $self->{httpinfo}{website}=Compress::Zlib::memGunzip($self->{httpinfo}{website});
  } elsif ($self->{httpinfo}{encoding} eq 'deflate') {
    my $x = new Compress::Raw::Zlib::Inflate( -WindowBits => -MAX_WBIT );
    my $decoded;
    my $status = $x->inflate($self->{httpinfo}{website},$decoded);
    $self->{httpinfo}{website} = $decoded
  } elsif (($self->{httpinfo}{encoding} eq 'compress') || ($self->{httpinfo}{encoding} eq 'x-compress')) {
    my $x = new Compress::Raw::Zlib::Inflate( -WindowBits => WANT_GZIP_OR_ZLIB );
    my $decoded;
    my $status = $x->inflate($self->{httpinfo}{website},$decoded);
    $self->{httpinfo}{website} = $decoded
  } elsif ($self->{httpinfo}{encoding} eq 'bzip2') {
    my $bz; my $status; my $decoded;
    ($bz, $status) = bzinflateInit();
    ($decoded, $status) = $bz->bzinflate($self->{httpinfo}{website});
    $self->{httpinfo}{website} = $decoded
  }
  # Br = Brotli => No Perl implementation found. On todo list. RFC 7932
}

sub http_analyse {
  my ($self) = @_;
  my $caller=$self->{usercaller};
  # guard against exploits and http-data injection
  my $len=length($self->{httpinfo}{website});
  if ($self->{httpinfo}{wanted} && ($self->{httpinfo}{wanted} < $len)) {
    $len-=$self->{httpinfo}{wanted};
    $self->{httpinfo}{exploit}=substr($self->{httpinfo}{website},$self->{httpinfo}{wanted});
    substr($self->{httpinfo}{website},$self->{httpinfo}{wanted},$len,"");
    &$caller($self,'inform',"Exploit found of $len bytes")
  }
  # check errors
  if ($self->{httpinfo}{rescode} == 401) {
    # Authorization required
    my $wanted=$self->{httpinfo}{reshead}{'www-authenticate'};    
    &$caller($self,'auth',$wanted);
    if (!$self->{httpinfo}{header}{'Authorization'}) {
      &$caller($self,"error","Authorization required"); return
    }
    if (!$self->{noredirect}) {
      my $new=http($self->{host},$self->{port},$self->{loopmode},$caller,$self->{timeout},$self->{ssl});
      $self->copyvar($new); $new->{norequest}=1;
      &$caller($self,'reconnect',$new);
    } else {
      &$caller($self,'quit')
    }

  }
  # client errors (4xx) and server errors (5xx)
  if (($self->{httpinfo}{rescode} >= 400) && ($self->{httpinfo}{rescode} <= 599)) {
    &$caller($self,"error",$self->{httpinfo}{response});
    return
  }
  # check redirects
  if (($self->{httpinfo}{rescode} >= 300) && ($self->{httpinfo}{rescode} <= 399)) {
    if (!$self->{httpinfo}{reshead}{location}) {
      &$caller($self,'error',"Location missing on redirect"); return
    }
    &$caller($self,'inform',"redirect $self->{httpinfo}{rescode} $self->{httpinfo}{reshead}{location}");
    my $url=spliturl($self->{httpinfo}{reshead}{location});
    $self->quit();
    # check for cyclic redirect loops
    for my $h (@{$self->{history}}) {
      if (($h->{host} eq $url->{host}) && ($h->{port} eq $url->{port})) {
        &$caller($self,'error',"Cyclic redirect detected on $h->{host}:$h->{port}");
        &$caller($self,"quit")
      }
    }
    # auto redirect
    if (!$self->{noredirect}) {
      my $new=http($url->{host},$url->{port},$self->{loopmode},$caller,$self->{timeout},$url->{ssl});
      $self->copyvar($new); $new->{norequest}=1;
      $new->{history}=$self->{history};
      &$caller($self,'reconnect',$new);
    } else {
      &$caller($self,'quit')
    }
    return
  }
  if ($self->{httpinfo}{encoding}) {
    $self->decode()
  }
  my $tm=gettimeofday()-$self->{connecttime};
  if (ref($self->{sske}) ne 'HASH' || ($self->{sskeround} > 1)) {
    &$caller($self,'ready',$tm)
  } else {
    $self->{sskeround} = 2;
    &{$self->{caller}}($self,'connect',$tm)
  }
}

sub handlesske {
  my ($self) = @_;
  if (ref($self->{sske}) ne 'HASH') { return }
  $self->{httpinfo}{header} = {
    'Unlocked-Symmetric-Key' => octhex(scramblekey(hexoct($self->{httpinfo}{reshead}{'double-symmetric-key'}),$self->{sske}{transkey},$self->{sske}{transfunc})),
    'unlocked-Symmetric-Function' => octhex(scramblekey(hexoct($self->{httpinfo}{reshead}{'double-symmetric-function'}),$self->{sske}{transkey},$self->{sske}{transfunc}))
  };
}

sub copyvar {
  my($self,$new) = @_;
  for my $k (%{$self->{httpinfo}}) {
    if ($k) { $new->{httpinfo}{$k}=$self->{httpinfo}{$k} }
  }  
}

sub spliturl {
  my ($url) = @_;
  my $endslash=0; if (substr($url,-1) eq '/') { $endslash=1 }
  my $info={ scheme => 'http', port => 80, ssl => 0, path => "", query => "" };
  my $data;
  ($data,$url) = split(/\:\/\//,$url);
  if (defined $url) { $info->{scheme}=lc($data) } else { $url=$data }
  if (substr($info->{scheme},-1,1) eq 's') {
    $info->{port}=443; $info->{ssl}=1
  }
  ($data,$url) = split(/\@/,$url);
  if (defined $url) {
    my ($user,$pass) = split(/\:/,$data);
    $info->{user}=$user;
    if (defined $pass) { $info->{password}=$pass }
  } else {
    $url=$data
  }
  ($url,$data) = split(/\#/,$url);
  if (defined $data) {
    $info->{fragment}=$data
  }
  ($url,$data) = split(/\?/,$url);
  if (defined $data) {
    $info->{query}=$data
  }
  my @path; ($url,@path) = split(/\//,$url);
  if ($#path>=0) { $info->{path}=join('/',@path) }
  if ($endslash) { $info->{path}.='/' }
  ($url,$data) = split(/\:/,$url);
  if (defined $data) { $info->{port}=$data }
  $info->{host}=$url;
  return $info
}

sub querydata {
  my ($url)=@_;
  my $info=spliturl($url);
  my $data={};
  for my $item (split/\&/,$info->{query}) {
    my($k,$v)=split(/\=/,$item);
    $data->{$k}=$v
  }
  return $data
}

#### Website/RSS reader ##############################

sub website {
  my ($url,$user,$pass,$timeout) = @_; my $sni;
  my $info=spliturl($url);
  if ($info->{host} =~ /[^0-9\.]/) { $sni=$info->{host} }
  my $self=http($info->{host},$info->{port},1,\&handle_website,$timeout,$info->{ssl},$sni,undef,$info->{path},$info->{query},$user,$pass);
  return $self 
}

sub handle_website {
  my ($self,$command,$data) = @_;
  if ($command eq 'init') {
    $self->{debug}=0;
  } elsif ($command eq 'request') {
    $self->get($self->{path},$self->{query})
  } elsif ($command eq 'header') {
    $self->agent()->lang('*')->allcoding()->charset('*')->cache()
  } elsif ($command eq 'error') {
    $self->quit()
  } elsif ($command eq 'reconnect') {
    $self=$data
  } elsif ($command eq 'ready') {
    $self->quit()
  }   
}

###############################################################################
# IceCast2                                                                    #
###############################################################################

sub icecast2 {
  #   my ($host,$port,$loopmode,$caller,$ssl,$linemode,$timeout,$connectcallback) = @_;
  my ($host,$port,$loopmode,$caller,$timeout,$ssl,$sni) = @_;
  if (ref($caller) ne 'CODE') { error "GClient.icecast2: Caller is not a procedure-reference" }
  if (!$port) { error "GClient.icecast2: No port given" }
  my $self=openconnection($host,$port,0,$timeout,$ssl,\&tcpipconnected,$sni);
  $self->{protocol}='icecast'; $self->{icecast}=1;
  $self->{usercaller}=$caller;
  $self->{caller}=\&handle_icecast2;
  if ($self->{error}) { &$caller($self,"quit",$self->{error}); $self->quit; return $self }
  if ($loopmode) { $self->{loopmode}=1 }
  $self->{iceinfo} = {
    meta => 1, bitrate => 0, samplerate => 0, mountpoint => "",
    login => "source", password => "",
    name => "", desc => "Domero - IceCast 2 stream", url => "", genre => 'Various',
    header => {}, postdata => "", readhead => 1, response => "", responsecode => 0,
    ready => 0, icesong => "", icedata => "", boost => 0, datatime => 0,
    buffersize => 0, framesize => 0, frametime => 0, lasttime => 0
  };
  # parameters one can change on init event
  $self->handle_icecast2('init',gettimeofday());
  if ($loopmode) {
    while (!$self->{quit}) { 
      $self->takeloop();
      if ($self->{iceinfo}{ready}) {
        $self->icecastloop()
      }
    }
  }
  return $self
}

sub takeiceloop {
  my ($self) = @_;
  $self->takeloop();
  if ($self->{iceinfo}{ready}) {
    $self->icecastloop()
  }
}

sub handle_icecast2 {
  my ($self,$command,$data) = @_;
  my $caller=$self->{usercaller};
  if ($command ne 'loop') {
    my $d=$data; if (!$d) { $d='[undef]' }
    # print " > CMD > $command - $d\n"
  }
  if ($command eq 'error') {
    &$caller($self,'error',$data)
  } elsif ($command eq 'init') {
    &$caller($self,'icemount');
    if (!$self->{iceinfo}{bitrate}) { &$caller($self,'error',"No bitrate given") }
    if (!$self->{iceinfo}{samplerate}) { &$caller($self,'error',"No samplerate given") }
    if (!$self->{iceinfo}{mountpoint}) { &$caller($self,'error',"No mountpoint given") }
    if (!$self->{iceinfo}{password}) { &$caller($self,'error',"No password given") }
    $self->{iceinfo}{framesize} = int (144 * $self->{iceinfo}{bitrate} / $self->{iceinfo}{samplerate});
    my $onesec = $self->{iceinfo}{bitrate} >> 3;
    $self->{iceinfo}{frametime} = $self->{iceinfo}{framesize} / $onesec;
    print STDOUT " * framesize = $self->{iceinfo}{framesize}\n * frametime = $self->{iceinfo}{frametime}\n";
  } elsif ($command eq 'connect') {
    &$caller($self,'connected',$data);
    my $auth=encode_base64($self->{iceinfo}{login}.':'.$self->{iceinfo}{password});
    my @header=("SOURCE ".$self->{iceinfo}{mountpoint}." ICE/1.0");
    push @header,"Host: ".$self->{host}.':'.$self->{port};
    push @header,"Authorization: Basic $auth";
    push @header,"User-Agent: Domero gclient/$VERSION";
    push @header,"Accept: */*";
    push @header,"Content-Type: audio/mpeg";
    push @header,"ice-public: 1";
    push @header,"ice-name: ".$self->{iceinfo}{name};
    push @header,"ice-bitrate: ".$self->{iceinfo}{bitrate};
    push @header,"ice-description: ".$self->{iceinfo}{desc};
    push @header,"ice-url: ".$self->{iceinfo}{url};
    push @header,"ice-genre: ".$self->{iceinfo}{genre};
    push @header,"ice-audio-info: ice-samplerate=".$self->{iceinfo}{samplerate}.';ice-bitrate='.$self->{iceinfo}{bitrate}.";ice-channels=2";
    my $head=join("\r\n",@header)."\r\n\r\n";
    $self->out($head);
    $self->takeloop();
  } elsif ($command eq 'input') {
    if ($self->{iceinfo}{ready}) {
      $self->icecastloop()
    } else {
      if ($self->{iceinfo}{readhead}) {
        my @ll = split(/\r\n/,$data,-1); my $idx=0;
        for my $line (@ll) {
          $idx++;
          if ($line eq "") {
            $self->{iceinfo}{readhead} = 0;
            $data=join("\r\n",@ll[$idx..$#ll]);
            last
          } else {
            if (!$self->{iceinfo}{response}) {
              $self->{iceinfo}{response}=$line;
              my @ls=split(/ /,$line); $self->{iceinfo}{responsecode}=$ls[1]
            } else {
              my ($k,$v) = split(/\:/,$line);
              $k =~ s/[\s\t]+$//; $v =~ s/^[\s\t]+//;
              $self->{iceinfo}{header}{lc($k)}=$v
            }
          }
        }
      }
      if (!$self->{iceinfo}{readhead}) {
        $self->{iceinfo}{postdata}.=$data;
        my $len = length($self->{iceinfo}{postdata});
        my $clen = $self->{iceinfo}{header}{'content-length'};
        if (!$clen || ($len == $clen)) {
          my $tm=gettimeofday();
          $self->{icetime}=$tm + 0.1;
          $self->{iceinfo}{ready} = 1;
          $tm-=$self->{connecttime};
          &$caller($self,'ready',$tm)
        }
      }
    }
  }
}

sub icecastloop {
  my ($self) = @_;
  my $tm=gettimeofday();
  my $caller=$self->{usercaller};
  if ($tm >= $self->{icetime}) {
    &$caller($self,'icedelay',$tm);
    $self->{icetime} += 0.1
  }
  if ($self->{iceinfo}{meta} && !$self->{iceinfo}{icesong}) {
    &$caller($self,'icesong')
  }

  # initial boost 0.5 sec data
  if (!$self->{iceinfo}{boost}) {
    my $sz = int ($self->{iceinfo}{framesize} * (0.5 / $self->{iceinfo}{frametime}) );
    &$caller($self,'icedata',$sz);
    $self->out($self->{iceinfo}{icedata});
    $self->{iceinfo}{icedata}="";
    $self->{iceinfo}{buffersize}=0;
    $self->{iceinfo}{boost}=1;
    $self->{iceinfo}{datatime}=$tm + $self->{iceinfo}{frametime}
  }

  # feed server framesize bytes, every frametime sec.
  if ($tm >= $self->{iceinfo}{datatime}) {
    &$caller($self,'icedata',$self->{iceinfo}{framesize});
    $self->out(substr($self->{iceinfo}{icedata},0,$self->{iceinfo}{framesize},""));
    $self->{iceinfo}{buffersize} -= $self->{iceinfo}{framesize};
    $self->{iceinfo}{datatime} += $self->{iceinfo}{frametime}
  }
}

sub icesong {
  my ($self,$song) = @_;
  icecast2_metadata($self->{host},$self->{port},$self->{iceinfo}{mountpoint},$self->{iceinfo}{password},$song)
}

sub icedata {
  my ($self,$data) = @_;
  $self->{iceinfo}{icedata}.=$data;
  $self->{iceinfo}{buffersize}+=length($data)
}

sub ice_nometa {
  my ($self) = @_;
  $self->{iceinfo}{meta}=0
}
sub ice_mount {
  my ($self,$mount) = @_;
  if (!$mount) { $self->setice('mountpoint','') }
  else {
    if (substr($mount,0,1) ne '/') { $mount='/'.$mount }
    $self->setice('mountpoint',$mount)
  }
  return $self
}
sub ice_bitrate {
  my ($self,$bitrate) = @_;
  if (!$bitrate) { $bitrate='128000' }
  if ($bitrate < 1000) { $bitrate *= 1000 }
  $self->setice('bitrate',$bitrate);
  return $self
}
sub ice_samplerate {
  my ($self,$samplerate) = @_;
  if (!$samplerate) { $samplerate='44100' }
  if ($samplerate < 1000) { $samplerate *= 1000 }
  $self->setice('samplerate',$samplerate);
  return $self
}
sub ice_password {
  my ($self,$pass) = @_;
  $self->setice('password',$pass);
  return $self
}
sub ice_name {
  my ($self,$name) = @_;
  $self->setice('name',$name);
  return $self
}
sub ice_desc {
  my ($self,$desc) = @_;
  $self->setice('desc',$desc);
  return $self
}
sub ice_genre {
  my ($self,$genre) = @_;
  $self->setice('genre',$genre);
  return $self
}
sub ice_url {
  my ($self,$url) = @_;
  $self->setice('url',$url);
  return $self
}
sub ice_login {
  my ($self,$login) = @_;
  if (!$login) { $login='source' }
  $self->setice('login',$login);
  return $self
}
sub setice {
  my ($self,$tag,$value) = @_;
  $self->{iceinfo}{$tag}=$value;
  return $self
}

sub ice_headers {
  my ($self) = @_;
  return $self->{iceinfo}{header}
}
sub ice_response {
  my ($self) = @_;
  return $self->{iceinfo}{response}
}
sub ice_responsecode {
  my ($self) = @_;
  return $self->{iceinfo}{responsecode}
}
sub ice_postdata {
  my ($self) = @_;
  return $self->{iceinfo}{postdata}
}

sub icecast2_metadata {
  my ($host,$port,$mount,$pass,$song) = @_;
  $mount =~ s/^\///;
  $song=url_encode_utf8($song);
  website("$host:$port/admin/metadata?pass=$pass&mode=updinfo&mount=/$mount&song=$song")
}

###############################################################################
# WebSockets                                                                  #
###############################################################################

sub starthandshake {
  my ($self,$ctm) = @_;
  my $tm=gettimeofday();
  my $hash=sha1("Domero".$tm."Domero");
  my $handshake = encode_base64($hash);
  $self->{handshake}=$handshake;
  my $out=<<EOT;
GET /chat HTTP/1.1
Host: $self->{host}
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: $handshake
Origin: http://$self->{localip}
Sec-WebSocket-Protocol: chat, superchat
Sec-WebSocket-Version: 13

EOT
  $out =~ s/\n/\r\n/g;
  $self->out($out);
  $self->outburst;
  $self->{upgradetime}=gettimeofday();  
}

sub websocket {
  my ($host,$port,$loopmode,$caller,$ssl,$timeout,$sni,$sske) = @_;
  if (!defined $caller || (ref($caller) ne 'CODE')) { error "GClient.websocket: Caller is not a procedure-reference" }
  my $self=openconnection($host,$port,0,$timeout,$ssl,\&starthandshake,$sni);
  if ($self->{error}) { &$caller($self,"quit",$self->{error}); $self->quit; return $self }
  $self->{caller}=$caller;
  $self->{sske} = {
    symkey => createkey(),
    symfunc => createkey(),
    transkey => createkey(),
    transfunc => createkey()
  };
  my $skey = octhex(scramblekey($self->{sske}{symkey},$self->{sske}{transkey},$self->{sske}{transfunc}));
  my $fkey = octhex(scramblekey($self->{sske}{symfunc},$self->{sske}{transkey},$self->{sske}{transfunc}));
  $self->{httpinfo}{header}{'Symmetric-Key'}=$skey;
  $self->{httpinfo}{header}{'Symmetric-Function'}=$fkey;
  $self->{sskeround}=1; $self->{sskeactive}=0;
  &$caller($self,'init');
  $self->{upgradetime}=gettimeofday();  
  $self->{upgrademode}=1;
  if ($loopmode) {
    $self->{loopmode}=1;
    while (!$self->{quit}) {
      $self->takeloop()
    }
  }
  return $self
}

sub wsupgrade {
  # RFC 6455
  my ($self,$data) = @_;
  my $caller=$self->{caller};
  if ($data !~ /\r\n\r\n/) {
    $self->{upgradebuf}.=$data; return
  }
  $data=$self->{upgradebuf}.$data;
  $self->{upgrademode}=0;
  my ($response,@wsd) = split(/\r\n\r\n/,$data);
  my $wsdata=join("\r\n\r\n",@wsd);
  # reactivate writing server -> client
  $self->{ws}={ upgraded => 0 }; $response =~ s/\r//g;
  foreach my $line (split(/\n/,$response)) {
    if ($self->{debug}) { print STDOUT "$line\n" }
    if ($line =~ /^http\/1\.. ([0-9]+)/i) { $self->{ws}{httpstatus}=$1 }
    if ($line =~ /^Sec-WebSocket-Accept: (.+)$/i) { $self->{ws}{key}=$1 }
    if ($line =~ /^upgrade: websocket/i) { $self->{ws}{upgraded}=1 }
  }
  if (!$self->{ws}{upgraded}) { &$caller($self,"error","Could not upgrade protocol to WebSocket"); $self->quit; return }
  if (!$self->{ws}{httpstatus} || $self->{ws}{httpstatus} != 101) { &$caller($self,"error","Could not switch protocols"); $self->quit; return }
  my $handshake=$self->{handshake};
  $handshake.="258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
  $handshake = sha1($handshake);
  $handshake = encode_base64($handshake);
  if ((!$self->{ws}{key}) || ($self->{ws}{key} ne $handshake)) { &$caller($self,"error","Server WebSocket key is invalid"); $self->quit; return }
  $self->{websocket}=1; $self->{ws} = { buffer => "", data => "", type => "" };
  &$caller($self,"connect",gettimeofday." ".$self->{host}.":".$self->{port});
  if ($wsdata) {
    $self->wsinput($wsdata)
  }
}

sub wsinput {
  # RFC 6455
  my ($self,$data,$try) = @_;
  if (!$data) {
    $data=$self->in('websocket');
    if (defined $data) { $self->{ws}{buffer}.=$data }
  } else {
    $self->{ws}{buffer}.=$data
  }
  my $blen=length($self->{ws}{buffer});
  if ($blen < 2) { return }
  if ($self->{debug}) { print STDOUT " << INPUT [$blen] $self->{host}:$self->{port}     \n" }
  my $caller=$self->{caller};
  my $firstchar=ord(substr($self->{ws}{buffer},0,1));
  my $secondchar=ord(substr($self->{ws}{buffer},1,1));
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
    &$caller($self,'error',"Invalid WS frame type: $type"); return
  }
  if (!$continue) { $self->{ws}{type}=$blocktype }
  my $mask=$secondchar & 128;
  if ($mask) {
    # RFC 6455 - Data MAY NOT be masked!
    &$caller($self,'error',"Masked data found in input from server"); return
  }
  my $len=$secondchar & 127; my $offset=2;
  if ($len==126) {
    if ($blen < 4) { return }
    $len=ord(substr($self->{ws}{buffer},2,1));
    $len=($len<<8)+ord(substr($self->{ws}{buffer},3,1));
    $offset=4
  } elsif ($len==127) {
    if ($blen < 10) { return }
    $len=0;
    for (my $p=0;$p<8;$p++) {
      $len=($len<<8)+ord(substr($self->{ws}{buffer},$offset,1));
      $offset++
    }
  }
  if ($blen<$offset+$len) { return }
  # YES! We got a package!
  my $fdata=substr($self->{ws}{buffer},$offset,$len);
  $self->{ws}{data}.=$fdata;
  if ($final) {
    $self->handlews($self->{ws}{type},$self->{ws}{data});
    $self->{ws}{data}=""
  }
  $self->{ws}{buffer}=substr($self->{ws}{buffer},$offset+$len);
  if (length($self->{ws}{buffer}) && !$try) { $self->wsinput(undef,1) }
}

sub handlews {
  my ($self,$type,$msg) = @_;
  if ($self->{debug}) { print STDOUT print " < WS $type $msg      \n" }
  if ($self->{sskeactive}) { $msg=$self->crypt($msg,0) }
  my $caller=$self->{caller};
  if ($type eq 'close') {
    utf8::decode($msg);
    my $code=(ord(substr($msg,0,1))<<8)+ord(substr($msg,1,1));
    $msg=substr($msg,2); if (!$msg) { $msg="Quit" }
    &$caller($self,'quit',"$code $msg");
    if ($self->{verbose}) { print STDOUT "\nWebSocket server has closed the connection: $code $msg\n" }
    $self->quit    
  } elsif ($type eq 'ping') {
    $self->wsout($msg,'pong');
    if ($self->{debug}) { print STDOUT print "> PONG $msg\n" }
  } elsif ($type eq 'pong') {
    # bi-directional ping/pong ? that takes balls !
  } else {
    &$caller($self,'input',$msg)
  }
}

sub wsmsg {
  my ($self,$msg) = @_;
  $self->wsout($msg,'input')
}

sub wsquit {
  my ($self,$msg) = @_;
  $self->wsout($msg,'close');
  $self->outburst();
  $self->{killafteroutput}=1;
}

sub wsout {
  # RFC 6455
  my ($self,$msg,$type) = @_;
  if (!defined $msg) { $msg="" }
  if ($self->{sskeactive}) { $msg=$self->crypt($msg,1) }
  my $len=length($msg);
  if (!$type) { $type = 'text' }
  my $tp=1;
  if ($type eq 'binary') { $tp=2 }
  elsif ($type eq 'close') { $tp=8 }
  elsif ($type eq 'ping') { $tp=9 }
  elsif ($type eq 'pong') { $tp=10 }
  if ((($tp==1) || ($tp==2)) && (length($msg) == 0)) { return } # ignore empty text/binary blocks
  my $out=chr($tp | 128); # 128 = final frame flag
  if ($len<126) {
    $out.=chr($len | 128) # 128 = mask is present
  } elsif ($len<65536) {
    $out.=chr(254);
    $out.=chr($len >> 8).chr($len & 255)
  } else {
    $out.=chr(255);
    $out.=chr(($len >> 56) & 255).chr(($len >> 48) & 255).chr(($len >> 40) & 255).chr(($len >> 32) & 255).chr(($len >> 24) & 255).chr(($len >> 16) & 255).chr(($len >> 8) & 255).chr($len & 255)    
  }
  my $mask=int rand(65536);
  $mask=($mask<<8) + int rand(65536);
  my $mask2=int rand(65536);
  $mask2=($mask2<<8) + int rand(65536);
  $mask = $mask ^ $mask2;
  my @mask=();
  for (my $i=0;$i<4;$i++) {
    push @mask,$mask & 255; $out.=chr($mask & 255); $mask>>=8
  }
  for (my $p=0;$p<$len;$p++) {
    $out.=chr(ord(substr($msg,$p,1)) ^ $mask[$p % 4])
  }
  if ($self->{debug}) { print STDOUT "> OUT: $msg ($type)\n" }
  $self->out($out);
  if ($type eq 'close') { $self->quit }
}

sub quit {
  my ($self) = @_;
  $self->{quitting}=1;
  if ($self->{quit}) { return }
  $self->outburst;
  if (defined $self->{socket}) {
    if ($self->{socket} && IO::Socket::connected($self->{socket})) {
      if ($self->{ssl}) {
        $self->{socket}->close(SSL_no_shutdown => 1)
      } else {
        shutdown($self->{socket},2); close($self->{socket}) 
      }
    }
  }
  $self->{quit}=1
}

###############################################################################
# Global functions                                                            #
###############################################################################

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

sub crypt {
  # EXTREME strong encoding
  my ($client,$data,$forceencode) = @_;
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
  my $sha=sha512($client->{sske}{symkey});
  my $scram; my $kscram;
  if ($datalen > 4096) {
    $scram=sha512($client->{sske}{symfunc});
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
  my $filter = $client->{sske}{symfunc};
  for my $b (1..$nb) {
    if (!$decode && ($ofs+64>$datalen)) {
      my $rest=64+$ofs-$datalen;
      $dat=substr($data,$ofs).substr($data,0,$rest); $ofs=$rest
    } else {
      $dat=substr($data,$ofs,64); $ofs+=64
    }
    $out.=scramblekey($dat,$client->{sske}{symkey},$filter);
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
      for my $f (unpack('N*',$client->{sske}{symfunc})) {
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

sub octhex {
  my ($key) = @_;
  if (!defined $key) { return "" }
  my $hex;
  for (my $i=0;$i<length($key);$i++) {
    my $c=ord(substr($key,$i,1));
    $hex.=sprintf('%02X',$c);
  }
  return $hex  
}

sub hexoct {
  my ($hex) = @_;
  if (!defined $hex) { return "" }
  my $key="";
  for (my $i=0;$i<length($hex);$i+=2) {
    my $h=substr($hex,$i,2);
    $key.=chr(hex($h));
  }
  return $key
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

sub encode {
  my ($data,$encode) = @_;
  if (!$encode) { return $data }
  if (($encode eq 'gzip') || ($encode eq 'x-gzip')) {
    return Compress::Zlib::memGzip($data);
  } elsif ($encode eq 'deflate') {
    my $x = new Compress::Raw::Zlib::Deflate( -WindowBits => -MAX_WBIT );
    my ($output, $status);
    $status = $x->deflate($data,$output);
    $status = $x->flush($output);
    return $output
  } elsif (($encode eq 'compress') || ($encode eq 'x-compress')) {
    my $x = new Compress::Raw::Zlib::Deflate( -WindowBits => WANT_GZIP_OR_ZLIB );
    my ($output, $status);
    $status = $x->deflate($data,$output);
    $status = $x->flush($output);
    return $output
  } elsif ($encode eq 'bzip2') {
    my ($bz, $status) = bzdeflateInit(); my $decoded;
    ($decoded, $status) = $bz->bzdeflate($data);
    return $decoded
  } elsif ($encode eq 'base64') {
    return encode_base64($data)
  } elsif ($encode eq 'quoted-printable') {
    return encode_qp($data)
  } elsif ($encode eq '7bit') {
    my $out=""; 
    for my $line (split(/\n/,$data)) {
      my $len=length($line); my $i=0; my $cl="";
      while ($i<$len) {
        $cl.=chr(ord(substr($line,$i,1)) & 127); $i++
      }
      while (length($cl) > 1000) {
        $out.=substr($cl,0,1000,"")."\n"
      }
      $out.=$cl."\n"
    }
    return $out
  } elsif ($encode eq '8bit') {
    my $out=""; 
    for my $line (split(/\n/,$data)) {
      while (length($line) > 1000) {
        $out.=substr($line,0,1000,"")."\n"
      }
      $out.=$line."\n"
    }
    return $out
  }
  return $data
}

sub localip {
  my $socket = IO::Socket::INET->new(
    Proto       => 'udp',
    PeerAddr    => '198.41.0.4', # a.root-servers.net
    PeerPort    => '53', # DNS
  );
  if (!$socket) { return '0.0.0.0' }
  return $socket->sockhost;
}

# EOF gclient.pm (C) 2019 Chaosje, Domero