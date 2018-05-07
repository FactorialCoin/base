#!/usr/bin/perl

package gclient;

######################################################################
#                                                                    #
#          TCP/IP client                                             #
#           - websockets, telnet, http, raw                          #
#           - SSL support                                            #
#           - fully bidirectional non-blocking, all systems          #
#                                                                    #
#          (C) 2018 Domero                                           #
#          ALL RIGHTS RESERVED                                       #
#                                                                    #
######################################################################

use strict;
use warnings;
use Socket;
use utf8;
use gfio;
use gerr qw(error);
use IO::Handle;
use IO::Select;
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::SSL;
use URL::Encode qw(url_encode_utf8);
use Exporter;
use Time::HiRes qw(gettimeofday usleep);
use Digest::SHA1 qw(sha1);
use Gzip::Faster;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '7.3.1';
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(openconnection in out websocket tcpip spliturl wsmsg wsquit wsinput localip website);

1;

sub openconnection {
  # Opens a RAW binary non-blocking bi-directional connection, timeout in seconds.
  my ($host,$port,$linemode,$timeout,$ssl) = @_;
  my $self = {}; bless $self;
  if (!$linemode) { $linemode=0 }
  if (!$timeout) { $timeout=10 }

  $self->{host}=$host;
  $self->{port}=$port;
  $self->{ssl}=$ssl;
  $self->{timeout}=$timeout;
  $self->{linemode}=$linemode;
  $self->{upgrademode}=0;
  $self->{upgradebuf}="";
  $self->{upgradetime}=0;
  $self->{connected}=0;
  $self->{loopmode}=0;
  $self->{websocket}=0;
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

  # Connect to server
  my $proto = (getprotobyname('tcp'))[2];
  my $iaddr = inet_aton($self->{host});
  my $err=""; my $sock;

  if ((!defined $iaddr) || (length($iaddr)!=4)) {
    $self->{error}="Unable to resolve IP"; return $self
  } elsif ($ssl) {
    my $sslerr=0;
    $self->{socket}=IO::Socket::SSL->new($self->{host}.":".$self->{port}) or $sslerr=1;
    if ($sslerr) { $self->{error}=$SSL_ERROR; return $self }
    $sock=$self->{socket}
  } else {
    $self->{socket}=undef;
    socket($sock, PF_INET, SOCK_STREAM, $proto) or $err="Cannot create socket on [$host:$port]: $!";
    if ($err) { $self->{error}=$err; return $self }  

    setsockopt($sock,SOL_SOCKET, SO_RCVTIMEO, 1);

    my $paddr = sockaddr_in($self->{port}, $iaddr);

    connect($sock, $paddr) or $err="Could not connect to server [$host:$port]: $!";
    if ($err) {
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
    $self->{socket}=$sock;
  }

  $self->{connected}=gettimeofday();

  # Set non blocking mode
  $sock->blocking(0);                                             # linux
  my $nonblocking = 1; ioctl($sock, 0x8004667E, \$nonblocking);   # windows

  # Set autoflush on socket
  $sock->autoflush(1);
  #select($self->{socket}); 
  binmode($self->{socket}); 
  #$|=1;

  # Set output to console
  select(STDOUT); binmode(STDOUT); $|=1;
  $self->{selector}=IO::Select->new($sock);

  # wait for socket ready
  $self->{servervec} = "";
  $self->connectready;

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
  } else {
    my $tm=gettimeofday()-$self->{connected};
    if ($tm>$self->{timeout}) {
      $self->{error}="Could not establish connection to server [$self->{host}:$self->{port}]";
      $self->quit;
    }
  }
}

sub dummycaller {

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
  my ($self) = @_;
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
      sysread($sock,$buf,16384)
    } else {
      recv($sock,$buf,16384,0)
    }
    #print "READ: $buf\n";
    if ($buf eq "") {
      my $err = $! + 0;
      if ($err) {
        #print "ERR $err\n";
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
            &$caller($self,'error',"Connection terminated by client");
            $self->{error}="Connection terminated by client"; $self->quit; return
          } else {
            # ERROR !
            &$caller($self,'error',"Connection error: [$err] $!");
            $self->{error}="Connection error: [$err] $!"; $self->quit; return
          }
        }   
      } elsif ($self->{dataready} && length($self->{curline})) {
        push @{$self->{buffer}},$self->{curline};
        $self->{curline}="";
      } else {
       # &$caller($self,'noinput')
      }
    } else {
      if ($self->{debug}) { print STDOUT "[INPUT] '$buf' " }
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
  my ($self) = @_;
  if ($self->{quit}) { return }
  $self->readsocket;
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
    my $data=$self->in;
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

sub tcpip {
  my ($host,$port,$loopmode,$caller,$ssl,$linemode,$timeout) = @_;
  if (ref($caller) ne 'CODE') { error "GClient.tcpip: Caller is not a procedure-reference" }
  my $self=openconnection($host,$port,$linemode,$timeout,$ssl);
  $self->{caller}=$caller;
  if ($self->{error}) { &$caller($self,"quit",$self->{error}); $self->quit; return $self }
  $self->{localip}=localip();
  if ($loopmode) { $self->{loopmode}=1 }
  &$caller($self,'connect',gettimeofday." ".$self->{host}.":".$self->{port});
  if ($loopmode) {
    while (!$self->{quit}) { $self->takeloop() }
  }
  return $self
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

sub processheader {
  my ($client,$line) = @_;
  $line =~ s/\r//;
  if ($line =~ /HTTP\/1\.[0-1] ([0-9]+) ?(.*)$/) {
    $client->{header}{response}=$1;
    $client->{header}{responsemessage}=$2;
  } else {
    my ($key,@vl) = split(/\:/,$line); my $val=join(':',@vl);
    if (defined $key && defined $val) {
      $key =~ s/^[\s\t]+//; $val =~ s/^[\s\t]+//; $val =~ s/[\s\t]+$//; # always those damn spaces :P not RFC but people throw garbage
      $client->{header}{$key}=$val;
    }
  }
}

sub website_event {
  my ($client,$command,$data) = @_;
  if (!defined $data) { $data="" }
  if (($command eq 'quit') || ($command eq 'error')) {
    $client->{iquit}=1
  } elsif ($command eq 'input') {
    $client->{hbuffer}.=$data;
    if ($client->{readheader}) {
      if ($client->{hbuffer} =~ /\r\n\r\n/) {
        my ($hdata,@cdata)=split(/\r\n\r\n/,$client->{hbuffer});
        $client->{hbuffer}=join("\r\n\r\n",@cdata);
        foreach my $line (split(/\r\n/,$hdata)) {
          processheader($client,$line)
        }
        $client->{readheader}=0;
        if (defined $client->{header}{'Content-Length'}) {
          $client->{httplength}=$client->{header}{'Content-Length'};
          if (!$client->{httplength}) {
            $client->{iquit}=1; return
          }
        } elsif ((defined $client->{header}{'Transfer-Encoding'}) && ($client->{header}{'Transfer-Encoding'} =~ /chunked/i)) {
          $client->{chunked}=1
        } elsif ((defined $client->{header}{'Content-Encoding'}) && ($client->{header}{'Content-Encoding'} =~ /chunked/i)) {
          $client->{chunked}=1
        }        
      }
    }
    if (!$client->{readheader}) {
      if (length($client->{hbuffer}) >= $client->{httplength}) {
        # prevent exploits
        $client->{hbuffer}=substr($client->{hbuffer},0,$client->{httplength});
        if ($client->{chunked}) {
          my $mode=1; my $pos=0; my $size=0; my $read="";
          while ($pos < length($client->{hbuffer})) {
            if ($mode == 1) {
              if (substr($client->{hbuffer},$pos,2) eq "\r\n") {
                if ($read =~ /[^a-fA-F0-9]/) {
                  $client->{error}="Corrupted chunk-size in content"; $client->{iquit}=1; return
                }
                $size=hex($read); $read=""; $mode=2; $pos+=2
              } else {
                $read.=substr($client->{hbuffer},$pos,1); $pos++
              }
            } else {
              $client->{content}.=substr($client->{hbuffer},$pos,$size);
              $pos+=$size;
              if (substr($client->{hbuffer},$pos,2) ne "\r\n") {
                $client->{error}="Corrupted chunked data in content"; $client->{iquit}=1; return
              }
              $pos+=2; $mode=1
            }
          }
        } else {        
          $client->{content}=$client->{hbuffer};
        }
        $client->{iquit}=1;
      }
    }
  }
}

sub website {
  my ($url,$proxy,$login,$pass) = @_;
  my $info=spliturl($url);
  my @header=(); my $proxyinfo;
  if ($proxy) {
    $proxyinfo=spliturl($proxy);
    my $line="GET ".$info->{scheme}."://".$info->{host}.":".$info->{port};
    $line.="/".$info->{path};
    if ($info->{query}) { $line.='?'.$info->{query} }
    $line.=" HTTP/1.1"; push @header,$line
  } else {
    my $line="GET /$info->{path}";
    if ($info->{query}) { $line.='?'.$info->{query} }
    $line.=" HTTP/1.1"; push @header,$line
  }
  push @header,"Host: $info->{host}"; # in proxies, use the original!
  push @header,"Connection: close";  # request/response and server-quit
  push @header,'User-Agent: Mozilla/5.0 (compatible; Domero Perl Client '.$VERSION.')';
  push @header,"Accept: */*";        # All MIME Types
  push @header,"Accept-Language: *"; # All languages
  push @header,"Accept-Encoding: gzip, deflate, identity, *"; # All codecs
  push @header,"Accept-Charset: utf-8, iso-8859-1;q=0.5";
  if ($login && $pass) {
    my $code = encode_base64($login.":".$pass);
    push @header,"Authorization: Basic $code"
  }
  my $head=join("\r\n",@header)."\r\n\r\n";
  my $client;
  if ($proxy) {
    $client=tcpip($proxyinfo->{host},$proxyinfo->{port},0,\&website_event,$proxyinfo->{ssl},0,5);
  } else {
    $client=tcpip($info->{host},$info->{port},0,\&website_event,$info->{ssl},0,5);
  }
  $client->out($head);
  $client->outburst();
  #$client->{debug}=1;
  $client->{readheader}=1;
  $client->{hbuffer}="";
  $client->{header}={};
  $client->{httplength}=0;
  $client->{chunked}=0;
  $client->{content}="";
  $client->{iquit}=0;
  $client->{timedout}=0;
  my $tm=gettimeofday();
  while (!$client->{iquit}) {
    $client->takeloop();
    if (gettimeofday()-$tm>5) {
      $client->{timedout}=1;
      $client->{iquit}=1
    }
  }
  # print "*** DONE READING ***\n";
  # analyze header
  if (defined $client->{header}{response}) {
    if (($client->{header}{response} >= 301) && ($client->{header}{response} <= 399) && $client->{header}{Location}) {
      if (substr($client->{header}{Location},0,1) eq '/') {
        $client->{header}{Location}=$info->{scheme}.'://'.$info->{host}.$client->{header}{Location}
      }
      if ($client->{header}{Location} ne $url) {
        if ($proxy) {
          return website($url,$client->{header}{Location},$login,$pass)
        } else {
          return website($client->{header}{Location},undef,$login,$pass)
        }
      }
    }
  }
  if ($client->{content} ne "") {
    if (defined $client->{header}{'Content-Encoding'} && ($client->{header}{'Content-Encoding'} =~ /gzip|deflate/i)) {
      eval { $client->{content}=gunzip($client->{content}) };
      $client->{error}=$@
    }
    if (defined $client->{header}{'Transfer-Encoding'} && ($client->{header}{'Transfer-Encoding'} =~ /gzip|deflate/i)) {
      eval { $client->{content}=gunzip($client->{content}) };
      $client->{error}=$@
    }
  }
  $client->quit();
  return $client
}

sub websocket {
  my ($host,$port,$loopmode,$caller,$ssl) = @_;
  if (!defined $caller || (ref($caller) ne 'CODE')) { error "GClient.websocket: Caller is not a procedure-reference" }
  my $self=openconnection($host,$port,0,undef,$ssl);
  if ($self->{error}) { &$caller($self,"quit",$self->{error}); $self->quit; return $self }
  $self->{localip}=localip();
  $self->{caller}=$caller;
  &$caller($self,'init');
  my $hash=sha1("Domero".gettimeofday."Domero");
  my $handshake = encode_base64($hash);
  $self->{handshake}=$handshake;
  my $out=<<EOT;
GET /chat HTTP/1.1
Host: $host
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
  $self->{upgrademode}=1;
  $self->{upgradetime}=gettimeofday();
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
    # print "$line\n";
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
  $self->{websocket}=1; $self->{ws}{buffer}=""; $self->{ws}{readheader}=1;
  if ($wsdata) {
    $self->wsinput($wsdata)
  }
  &$caller($self,"connect",gettimeofday." ".$self->{host}.":".$self->{port});
}

sub wsinput {
  # RFC 6455
  my ($self,$data) = @_;
  if (!$data) {
    $data=$self->in();
    if (defined $data) { $self->{ws}{buffer}.=$data }
  } else {
    $self->{ws}{buffer}.=$data
  }
  if (length($self->{ws}{buffer}) == 0) { return }
  my $caller=$self->{caller};
  if ($self->{ws}{readheader}) {
    my $firstchar=ord(substr($self->{ws}{buffer},0,1));
    my $secondchar=ord(substr($self->{ws}{buffer},1,1));
    my $type=$firstchar & 15;
    my $final=$firstchar & 128;
    my $continue=0;
    my $blocktype;
    my @masking=();
    if ($type == 0) { $continue=1 }
    elsif ($type == 1) { $blocktype='text' }
    elsif ($type == 2) { $blocktype='binary' }
    elsif ($type == 8) { $blocktype='close' }
    elsif ($type == 9) { $blocktype='ping' }
    elsif ($type == 10) { $blocktype='pong' }
    else {
      &$caller($self,'error',"Invalid WS frame type: $type"); return
    }
    my $mask=$secondchar & 128;
    my $len=$secondchar & 127; my $offset=2;
    if ($len==126) {
      $len=ord(substr($self->{ws}{buffer},2,1));
      $len=($len<<8)+ord(substr($self->{ws}{buffer},3,1));
      $offset=4
    } elsif ($len==127) {
      $len=0;
      for (my $p=0;$p<8;$p++) {
        $len=($len<<8)+ord(substr($self->{ws}{buffer},$offset,1));
        $offset++
      }
    }
    # RFC don't mention server=>client masking, but we want it all!
    if ($mask) {
      # non-standard server!
      for (my $m=0;$m<4;$m++) {
        push @masking,ord(substr($self->{ws}{buffer},$offset+$m,1))
      }
      $offset+=4
    }
    my $left=length($self->{ws}{buffer})-$offset;
    if ($left>=$len) {
      # YES! We got a package!
      my $fdata=substr($self->{ws}{buffer},$offset,$len);
      if ($mask) {
        my $out="";
        for (my $i=0;$i<$len;$i++) {
          $out.=chr($masking[ $i & 3 ] ^ ord(substr($fdata,$i,1)))
        }
        $fdata=$out
      }
      if ($continue) {
        $fdata=$self->{ws}{'buf'.$blocktype}.$fdata
      }
      if ($final) {
        $self->handlews($blocktype,$fdata);
        $self->{ws}{'buf'.$blocktype}="";
        $self->{ws}{buffer}=substr($self->{ws}{buffer},$offset+$len);
      } else {
        my $fdata=substr($self->{ws}{buffer},$offset);
        $self->{ws}{'buf'.$blocktype}=$fdata;
      }
    } else {
      # read more data!
      my $fdata=substr($self->{ws}{buffer},$offset);
      $self->{ws}{info}={ data => $fdata, read => length($fdata), wantedlen => $len, type => $blocktype };
      $self->{ws}{readheader}=0;
      $self->{ws}{buffer}=""
    }
  } else {
    # the first run did not complete a block, so continue reading TCP data
    my $flen=length($self->{ws}{buffer});
    if ($self->{ws}{info}{read}+$flen>=$self->{ws}{info}{wantedlen}) {
      # we got a completed package
      $self->{ws}{info}{data}.=substr($self->{ws}{buffer},0);
      $self->handlews($self->{ws}{info}{type},$self->{ws}{info}{data});
      $self->{ws}{'buf'.$self->{ws}{info}{type}}="";
      $self->{ws}{info}={};
      $self->{ws}{buffer}=substr($self->{ws}{buffer},length($data));
      $self->{ws}{readheader}=1;
    } else {
      # still buffering..
      $self->{ws}{info}{data}.=$self->{ws}{buffer};
      $self->{ws}{info}{read}+=length($self->{ws}{buffer}); 
      $self->{ws}{buffer}=""
    }
  }
}

sub handlews {
  my ($self,$type,$msg) = @_;
  my $caller=$self->{caller};
  if ($type eq 'close') {
    utf8::decode($msg);
    my $code=(ord(substr($msg,0,1))<<8)+ord(substr($msg,1,1));
    $msg=substr($msg,2); if (!$msg) { $msg="Quit" }
    &$caller($self,'quit',"$code $msg");
    if ($self->{verbose}) {
      print STDOUT "\nWebSocket server has closed the connection: $code $msg\n"
    }
    $self->quit    
  } elsif ($type eq 'ping') {
    $self->wsout($msg,'pong');
    #print "> PONG $msg\n"
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
  $self->outburst()
}

sub wsout {
  # RFC 6455
  my ($self,$msg,$type) = @_;
  if (!defined $msg) { $msg="" }
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
  #print "> OUT: $out\n       $msg ($type)\n";
  $self->out($out);
  if ($type eq 'close') { $self->quit }
}

sub quit {
  my ($self) = @_;
  $self->{quitting}=1;
  if ($self->{quit}) { return }
  $self->outburst;
  if (defined $self->{socked}) {
    if ($self->{ssl}) {
      $self->{socket}->close(SSL_no_shutdown => 1)
    } else {
      shutdown($self->{socked},2); close($self->{socked}) 
    }
  }
  $self->{quit}=1
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

# EOF gclient.pm (C) 2018 Domero
