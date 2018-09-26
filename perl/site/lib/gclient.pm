#!/usr/bin/perl

package gclient;

######################################################################
#                                                                    #
#          TCP/IP client                                             #
#           - websockets, telnet, http, raw, IceCast                 #
#           - SSL support                                            #
#           - fully bidirectional non-blocking, all systems          #
#           - http reader supports chunked, gzip, auto redirect      #
#           - RSS compatible                                         #
#                                                                    #
#          (C) 2018 Chaosje, Domero                                  #
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

$VERSION     = '7.7.2'; # clients are more difficult then servers, the kernel-version-numbers proof it! LIBERTA!
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(openconnection in out websocket tcpip spliturl wsmsg wsquit wsinput localip website zipeval encode_base64 icecast2 icecast2_metadata);

my $ZIPEVAL=0;

1;

sub openconnection {
  # Opens a RAW binary non-blocking bi-directional connection, timeout in seconds.
  my ($host,$port,$linemode,$timeout,$ssl,$connectcallback) = @_;
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
  $self->{connectcallback}=$connectcallback;
  $self->{connected}=gettimeofday();

  # Connect to server
  my $proto = (getprotobyname('tcp'))[2];
  my $iaddr = inet_aton($self->{host});
  my $err=""; my $sock;
  $self->{servervec} = "";

  if ((!defined $iaddr) || (length($iaddr)!=4)) {
    $self->{error}="Unable to resolve IP"; return $self
  } elsif ($ssl) {
    my $sslerr=0;
    $self->{socket}=IO::Socket::SSL->new($self->{host}.":".$self->{port}) or $sslerr=1;
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

    setsockopt($sock,SOL_SOCKET, SO_RCVTIMEO, 3);
  } else {
    $self->{socket}=undef;
    socket($sock, PF_INET, SOCK_STREAM, $proto) or $err="Cannot create socket on [$host:$port]: $!";
    if ($err) { $self->{error}=$err; return $self }  

    select($sock); $|=1; select(STDOUT);
    # Set non blocking mode
    $sock->blocking(0);                                             # linux
    my $nonblocking = 1; ioctl($sock, 0x8004667E, \$nonblocking);   # windows

    # Set autoflush on socket
    $sock->autoflush(1);
    #select($self->{socket}); 
    binmode($sock); 

    setsockopt($sock,SOL_SOCKET, SO_RCVTIMEO, 3);

    my $paddr = sockaddr_in($self->{port}, $iaddr);

    vec($self->{servervec}, fileno($sock), 1) = 1;
    select(undef, $self->{servervec}, undef, $self->{connectlooptime});
    my $vec=vec($self->{servervec}, fileno($sock), 1);
    connect($sock, $paddr) or $err="Could not connect to server [$host:$port]: $! ".(0+$!);
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
  select(STDOUT); binmode(STDOUT); $|=1;

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
    my $tm=gettimeofday()-$self->{connected};
    $self->{connectspeed}=$tm;
    if ($self->{connectcallback}) {
      my $callback=$self->{connectcallback};
      &$callback($self,$tm)
    }
  } elsif ($self->{connected}) {
    my $tm=gettimeofday()-$self->{connected};
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
    # print " >> $self->{host} $sz\n";
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

sub dechunk {
  my ($client,$data) = @_;
  my $out="";
  do {
    my ($len,@rest) = split(/\r\n/,$data);
    $data=join("\r\n",@rest);
    if ($len =~ /[^0-9A-Fa-f]/) {
      $client->{error}="Corrupted chunk-size in content"; return $out
    }
    if (!$len) { return $out }
    $len=hex($len);
    if (length($data) < $len) {
      $client->{error}="Not enough data in chunk"; return $out
    }
    $out.=substr($data,0,$len,"");
  } until (!length($data));
  $client->{error}="Unexpected end of chunked data"; return $out
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
      if ($key =~ /^connection$/i) { $key="Connection" }
      if ($key =~ /^content-type$/i) { $key="Content-Type" }
      if ($key =~ /^content-length$/i) { $key="Content-Length" }
      if ($key =~ /^content-encoding$/i) { $key="Content-Encoding" }
      if ($key =~ /^transfer-encoding$/i) { $key="Transfer-Encoding" }
      $client->{header}{$key}=$val;
    }
  }
}

sub website_event {
  my ($client,$command,$data) = @_;
  if ($::DEBUG) {
    my $dat=substr($data,0,100);
    print " :: $command = '$dat'\n";
  }
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
        } elsif ((defined $client->{header}{'Transfer-Encoding'}) && ($client->{header}{'Transfer-Encoding'} =~ /chunked/i)) {
          $client->{chunked}=1;
        } elsif ((defined $client->{header}{'Content-Encoding'}) && ($client->{header}{'Content-Encoding'} =~ /chunked/i)) {
          $client->{chunked}=1;
        }
        if (defined $client->{header}{'Content-Encoding'} && ($client->{header}{'Content-Encoding'} =~ /gzip|deflate/i)) {
          $client->{gzipped}=1
        } elsif (defined $client->{header}{'Transfer-Encoding'} && ($client->{header}{'Transfer-Encoding'} =~ /gzip|deflate/i)) {
          $client->{gzipped}=1
        }
        if ($client->{'Content-Type'} && (($client->{header}{'Content-Type'} =~ /rss/) || ($client->{header}{'Content-Type'} =~ /text\/xml/))) {
          $client->{rss}=1
        }
      }
    }
    if (!$client->{readheader}) {
      if ($client->{header}{'Connection'} && ($client->{header}{'Connection'} eq 'close')) {
        $client->{iquit}=1; return
      }
      if ($client->{httplength}) {
        if (length($client->{hbuffer}) >= $client->{httplength}) { 
          $client->{ready}=1;
          # prevent expolits
          $client->{hbuffer}=substr($client->{hbuffer},0,$client->{httplength});
        }        
      } else {
        if ($client->{chunked}) {
          my $last=substr($client->{hbuffer},-7);
          if ($last eq "\r\n0\r\n\r\n") { $client->{ready}=1 }
          else { $client->{insecure}=gettimeofday() }
        } else {
          # pff... no indication..
          if (!$client->{gzipped}) {
            if ($client->{hbuffer} =~ /\<\/rss\>/) { $client->{ready}=1 }
            if ($client->{hbuffer} =~ /\<\/html\>/) { $client->{ready}=1 }
            if ($client->{hbuffer} =~ /\<\/xml\>/) { $client->{ready}=1 }
          }
          if (!$client->{ready}) { $client->{insecure}=gettimeofday() }
        }
      }
      if ($client->{ready}) {
        $client->{iquit}=1;
      }
    }
  }
}

sub website {
  my ($url,$proxy,$login,$pass,$nosniff,$recurs) = @_;
  my $info=spliturl($url);
  if ($info->{path}) { $info->{path} =~ s/^\/// }
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
  if ($nosniff) {
    push @header,"Host: $info->{host}:$info->{port}";
    push @header,"Connection: keep-alive";
    push @header,"Accept: text/html,text/xml,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8";
    push @header,"Accept-Encoding: gzip, identity";
    push @header,"Accept-Language: *";
    push @header,"Cache-Control: max-age=0";
    push @header,"DNT: 1";
    push @header,"Upgrade-Insecure-Requests: 1";
    push @header,'User-Agent: Mozilla/5.0 (compatible; Domero Perl Client ('.$VERSION.')';
  } else {
    push @header,"Host: $info->{host}:$info->{port}"; # in proxies, use the original!
    push @header,'User-Agent: Mozilla/5.0 (compatible; Domero Perl Client ('.$VERSION.')';
    push @header,"Accept: */*";        # All MIME Types
    push @header,"Accept-Language: *"; # All languages
    push @header,"Accept-Encoding: gzip, identity"; # All codecs
    push @header,"Accept-Charset: utf-8, iso-8859-1;q=0.5";
  }
  if ($login && $pass) {
    my $code = encode_base64($login.":".$pass);
    push @header,"Authorization: Basic $code"
  }
  my $head=join("\r\n",@header)."\r\n\r\n";
  if ($::DEBUG) {
    print "  >>> SENDING <<<\n$head****************************\n";
  }
  my $client;
  if ($proxy) {
    $client=tcpip($proxyinfo->{host},$proxyinfo->{port},0,\&website_event,$proxyinfo->{ssl},0,5);
  } else {
    $client=tcpip($info->{host},$info->{port},0,\&website_event,$info->{ssl},0,5);
  }
  while ($client->{waitforinput} && !$client->{quit}) {
    $client->takeloop()
  }
  if ($client->{quit}) { return $client }
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
  $client->{nosniff}=$nosniff;
  $client->{gzipped}=0;
  $client->{rss}=0;
  my $tm=gettimeofday();
  $client->{insecure}=0;
  $client->{lastinput}=$tm;
  $client->{ready}=0;
  $client->{recurs}=0;
  while (!$client->{iquit}) {
    $client->takeloop();
    my $tod=gettimeofday();
    if ($tod-$tm>5) {
      $client->{timedout}=1;
      $client->{iquit}=1
    }
    if ($client->{insecure}) {
      if ($tod-$client->{insecure} > 0.5) {
        $client->{iquit}=1
      }
    }
  }
  # print "*** DONE READING ***\n";
  # analyse header
  if ($::DEBUG) {
    print "  **>> READY = $client->{ready} || INSECURE = $client->{insecure}<<**\n";
  }
  if (defined $client->{header}{response}) {
    if ($::DEBUG) {
      print "   >>>> RECEIVED <<<<\n";
      foreach my $k (sort keys %{$client->{header}}) {
        print "  $k => $client->{header}{$k}\n"
      }
      print "***********************\n"
    }
    # redirects
    if (($client->{header}{response} >= 301) && ($client->{header}{response} <= 399) && $client->{header}{Location}) {
      if (substr($client->{header}{Location},0,1) eq '/') {
        $client->{header}{Location}=$info->{scheme}.'://'.$info->{host}.$client->{header}{Location}
      }
      if ($client->{header}{Location} ne $url) {
        if (!$recurs) {
          if ($proxy) {
            return website($url,$client->{header}{Location},$login,$pass,undef,1)
          } else {
            return website($client->{header}{Location},undef,$login,$pass,undef,1)
          }
        }
      }
    }    
    # nosniff
    if (!$client->{ready} && !$client->{nosniff} && $client->{header}{'X-Content-Type-Options'} && ($client->{header}{'X-Content-Type-Options'} eq 'nosniff')) {
      # some servers require nosniff Upgrade-Insecure-Requests set to 1
      if (!$recurs) {
        return website($url,$client->{header}{Location},$login,$pass,$client->{header}{'Content-Type'},1)
      }
    }
  }
  # analyse content
  if ($client->{chunked}) {
    $client->{content}=dechunk($client,$client->{hbuffer})
  } else {
    $client->{content}=$client->{hbuffer}
  }
  if ($client->{content} ne "") {
    if ($client->{gzipped}) {
      $ZIPEVAL=1;
      eval { $client->{content}=gunzip($client->{content}) };
      $ZIPEVAL=0;
      $client->{error}=$@
    }
  }
  $client->quit();
  return $client
}

sub zipeval {
  return $ZIPEVAL
}

sub handle_icecast2_metadata {
  my ($client,$command,$data) = @_;
  # print " ICE > $command $data\n";
  if (($command eq 'quit') || ($command eq 'error') || ($command eq 'input')) {
    $client->{iquit}=1
  }
}

sub icecast2_metadata {
  my ($host,$port,$mount,$pass,$song) = @_;
  $mount =~ s/^\///;
  my $client=tcpip($host,$port,0,\&handle_icecast2_metadata);
  while ($client->{waitforinput} && !$client->{quit}) {
    $client->takeloop()
  }
  if ($client->{quit}) { return }
  my $auth=encode_base64('source:'.$pass);
  $song=url_encode_utf8($song);
  my @header=("GET /admin/metadata?pass=$pass&mode=updinfo&mount=/$mount&song=$song HTTP/1.1");
  push @header,"Authorization: Basic $auth";
  push @header,"User-Agent: Domero gclient/$VERSION (Mozilla Compatible)";
  my $head=join("\r\n",@header)."\r\n\r\n";
  $client->out($head);
  $client->outburst();
  $client->{iquit}=0;
  # print " > OUT\n$head";
  while (!$client->{iquit}) {
    $client->takeloop();
  }
  $client->quit()  
}

sub handle_icecast2 {
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
      }
    }
  }
}

sub icecast2 {
  my ($host,$port,$caller,$mount,$pass,$url,$name,$desc,$genre,$bitrate,$samplerate) = @_;
  $mount =~ s/^\///;
  if (ref $caller ne 'CODE') { error("GClient.IceCast2: Caller must be a procedure-referencee") }
  my $client=tcpip($host,$port,0,\&handle_icecast2);
  while ($client->{waitforinput} && !$client->{quit}) {
    $client->takeloop()
  }
  if ($client->{quit}) { return $client }
  my $auth=encode_base64('source:'.$pass);
  my @header=("SOURCE /$mount ICE/1.0");
  push @header,"Host: $host:$port";
  push @header,"Authorization: Basic $auth";
  push @header,"User-Agent: Domero gclient/$VERSION";
  push @header,"Accept: */*";
  push @header,"Content-Type: audio/mpeg";
  push @header,"ice-public: 1";
  push @header,"ice-name: $name";
  push @header,"ice-bitrate: $bitrate";
  push @header,"ice-description: $desc";
  push @header,"ice-url: $url";
  push @header,"ice-genre: $genre";
  push @header,"ice-audio-info: ice-samplerate=$samplerate;ice-bitrate=$bitrate;ice-channels=2";
  my $head=join("\r\n",@header)."\r\n\r\n";
  $client->out($head);
  $client->outburst();
  $client->{readheader}=1;
  $client->{hbuffer}="";
  $client->{header}={};
  $client->{iquit}=0;
  $client->{getsong}=1;
  $client->{iceburst}=1;
  $client->{bursttime}=0;
  my $tm=gettimeofday();
  while (!$client->{iquit}) {
    $client->takeloop();
    &$caller($client,"icedelay");
    my $tod=gettimeofday();
    if ($tod-$tm>=0.1) {
      $tm=$tod;
      my $resp=&$caller($client,"iceloop");
      if ($resp && ($resp eq 'quit')) {
        $client->quit(); $client->{iquit}=1
      }
    }
    if (!$client->{readheader}) {
      if ($client->{getsong}) {
        $client->{getsong}=0;
        my ($song,$itv)=&$caller($client,'icesong');
        if (!$song || !$itv) {
          $client->{getsong}=1
        } else {
          $client->{itv}=$itv / 1000000; $client->{datatime}=0; $client->{bursttime}=$client->{itv}*30+$tod;
          #icecast2_metadata($host,$port,$mount,$pass,$song)
        }
      } else {
        if ($client->{iceburst}<=60) {
          my $data=&$caller($client,'icedata');
          if (length($data) == 0) {
            $client->{getsong}=1
          } else {
            $client->out($data);
            $client->outburst();
          }
          $client->{iceburst}++
        } elsif ($tod >= $client->{bursttime}) {
          $client->{bursttime}+=$client->{itv};
          my $data=&$caller($client,'icedata');
          if (length($data) == 0) {
            $client->{getsong}=1
          } else {
            $client->out($data);
            $client->outburst();
          }
        }
      }
    }
  }
}

sub starthandshake {
  my ($self,$ctm) = @_;
  my $hash=sha1("Domero".gettimeofday."Domero");
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
  my ($host,$port,$loopmode,$caller,$ssl,$timeout) = @_;
  if (!defined $caller || (ref($caller) ne 'CODE')) { error "GClient.websocket: Caller is not a procedure-reference" }
  my $self=openconnection($host,$port,0,$timeout,$ssl,\&starthandshake);
  if ($self->{error}) { &$caller($self,"quit",$self->{error}); $self->quit; return $self }
  $self->{caller}=$caller;
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
  $self->{websocket}=1; $self->{ws} = { buffer => "", data => "", type => "" };
  &$caller($self,"connect",gettimeofday." ".$self->{host}.":".$self->{port});
  if ($wsdata) {
    $self->wsinput($wsdata)
  }
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
  my $blen=length($self->{ws}{buffer});
  if ($blen < 2) { return }
  #print " << INPUT [$len] $self->{host}:$self->{port}     \n";
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
  if (length($self->{ws}{buffer})) { $self->wsinput() }
}

sub handlews {
  my ($self,$type,$msg) = @_;
  # print " < WS $type $msg      \n";
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
  # print "> OUT: $msg ($type)\n";
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
  return $socket->sockhost || '0.0.0.0';
}

# EOF gclient.pm (C) 2018 Domero
