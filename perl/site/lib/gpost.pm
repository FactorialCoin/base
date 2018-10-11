#!/usr/bin/perl

package gpost;

 #############################################################################
 #                                                                           #
 #   Gideon CGI GET POST Engine                                              #
 #   (C) 2018 Domero                                                         #
 #   ALL RIGHTS RESERVED                                                     #
 #                                                                           #
 #############################################################################

use strict;
no strict 'refs';
use warnings;
use gfio;
use gerr qw(error);
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '2.1.2';
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw();

1;

sub init {
  my ($type,$data) = @_;
  my $self={}; bless $self;
  $self->{key}={};
  $self->{upload}={};
  $self->{fileupload}=0;
  $self->{error}=0;
  $self->{errormsg}="";
  $self->{key}={};
  $self->{boundary}="";
  $self->{data}="";
  $self->{len}=0;
  if (defined $type) {
    if ($type eq 'get') { $self->{type}='url' } 
    elsif ($type =~ /application\/x-www-form-urlencoded/i) { $self->{type}='url'}
    elsif ($type =~ /multipart\/form-data.*?boundary=\"?([^\"]+)\"?$/i) {
      $self->{boundary}=$1; $self->{type}='mime'
    }
    elsif ($type =~ /text\/plain/i) {
      $self->{type}='url'
    } else {
      error("GPost.init: Inknown type found '$type'")
    }
  }
  if (defined $data) {
    $self->{data}=$data;
  }
  if (!$self->{type}) {
    $self->{ruri}=[split(/\//,shift(@{[split(/\?/,$ENV{REQUEST_URI})]}))];
    if ($ENV{'REQUEST_METHOD'} =~ /get/i) {
      $self->{data}=$ENV{'QUERY_STRING'};
      $self->{type}='url'
    } else {
      read(STDIN,$self->{data},$ENV{'CONTENT_LENGTH'}) || error("Upload not completed");
      if ($ENV{'CONTENT_TYPE'} =~ /application\/x-www-form-urlencoded/i) {
        $self->{type}='url'
      } elsif ($ENV{'CONTENT_TYPE'} =~ /multipart\/form-data.*?boundary=\"?([^\"]+)\"?$/i) {
        $self->{boundary}=$1; $self->{type}='mime'
      } else {
        $self->{type}='url'
      }
    }
  }
  $self->{len}=length($self->{data});
  if ($self->{error} || (!$self->{len})) { return $self }
  if ($self->{type} eq 'url') {
    $self->decode_url()
  } else {
    $self->decode_mime()
  }
  return $self
}

sub request_uri {
  my ($self,$index)=@_;
  if(defined $index){ return $self->{ruri}[$index] }
  return $self->{ruri}
}

sub ruri { return request_uri(@_) }

sub uploaded {
  my ($self,$formname) = @_;
  if ($self->{upload}{$formname}{length}) {
    return 1
  }
  return 0
}

sub uploadedfile {
  my ($self,$formname) = @_; 
  return $self->{upload}{$formname}{file}
}

sub save {
  my ($self,$formname,$dir,$file) = @_;
  if (!$self->{upload}{$formname}) {
    error("Upload form-field '$formname' does not exist"); return
  }
  if (!$dir) { $dir="." }
  if (substr($dir,length($dir)-1,1) eq '/') { $dir=substr($dir,0,length($dir)-1) }
  my $fnm;
  if (!$file) {
    # save file as given name..
    $fnm="$dir/".$self->{upload}{$formname}{file};
  } else {
    $fnm="$dir/$file";
  }
  gfio::create($fnm,$self->get($formname))
}

sub add {
  my ($self,$key,$val) = @_;
  if (!defined $self->{key}{$key}) {
    $self->{key}{$key}= [ $val ]
  } else {
    push @{$self->{key}{$key}},$val
  }
}

sub set {
  my ($self,$key,$val) = @_;
#  $key=lc($key);
  my $dat=[]; push @{$dat},$val;
  $self->{key}{$key}=$dat
}

sub exist {
  my ($self,$key) = @_;
#  $key=lc($key);
  if (ref($self->{key}{$key})) { return 1 }
  return 0
}

sub exists {
  my $self=shift; return $self->exist(@_)
}

sub get {
  my ($self,$key,$nr) = @_;
  if ($self->{key}{$key}) {
    if ((defined $nr) && ($nr !~ /[^0-9]/)) { return $self->{key}{$key}[$nr] }
    if ($#{$self->{key}{$key}}) {
      return @{$self->{key}{$key}}
    }
    return $self->{key}{$key}[0]
  }
  return undef
}

sub getall {
  my ($self) = @_;
  my $list=[];
  foreach my $key (keys %{$self->{key}}) {
    my $val=$self->{key}{$key};
    if (ref($val) eq 'ARRAY') {
      $val=join(", ",@$val)
    }
    push @$list,{ key => $key, value => $val }
  }
  return $list
}

sub num {
  my ($self,$key) = @_;
#  $key=lc($key);
  return 0+@{$self->{key}{$key}}
}

sub decode_url {
  my ($self) = @_;
  if(defined $self->{data}){
    my @pi=split(/&/,$self->{data});
    foreach my $pe (@pi) {
      my ($ky,$vl)=split(/=/,$pe); # $ky=lc($ky);
      if (defined $vl) { $vl =~ tr/+/ /; $vl=~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg }
      $self->add($ky,$vl);
    }
  }
}

sub decode_mime {
  my ($self) = @_;
  # RFC 1867
  # RFC 1521 + 1522
  # * boundary can be "boundary"; 
  #   valid chars are DIGIT / ALPHA / "'" / "(" / ")" / "+" /"_" / "," / "-" / "." / "/" / ":" / "=" / "?"
  # * delimeter := --boundaryCRLF
  # * end-delimeter := --boundary--CRLF
  # * encapsulation := delimiter body-part CRLF (Data must start with delimeter!)
  # * body = multipart/formdata boundary="?boundary"? delimeter blocks end-delimeter
  # * blocks = (Content-....CRLF)* CRLF data
  # * data = Interpreted by Content-Transfer-Encoding header in block

#  if (!$ENV{'REMOTE_ADDR'}) { return }
  my $bsplit=$self->{boundary};
  $bsplit =~ s/\'/\\\'/g;
  $bsplit =~ s/\(/\\\(/g;
  $bsplit =~ s/\)/\\\)/g;
  $bsplit =~ s/\+/\\\+/g;
  $bsplit =~ s/\_/\\\_/g;
  $bsplit =~ s/\,/\\\,/g;
  $bsplit =~ s/\-/\\\-/g;
  $bsplit =~ s/\//\\\//g;
  $bsplit =~ s/\:/\\\:/g;
  $bsplit =~ s/\=/\\\=/g;
  $bsplit =~ s/\?/\\\?/g;

  my $e="Boundary = $self->{boundary}\n";

  # Find end-marker
  my ($parsetext,$exploit) = split(/\-\-$bsplit\-\-[\r|\n]{2}/s,$self->{data});

  if ($exploit) {
    error("Exploit detected in multipart/form-data! <hr><pre>$exploit</pre>"); return
  }

  # Split on delimeters
  my @datablocks = split(/\-\-$bsplit[\r|\n]{2}/s,$parsetext);

  my $numblocks=0+@datablocks;
  my $curblock=1;

  if (!$numblocks) {
    error("No datablocks found in multipart/form-data"); return
  }
  if ($datablocks[0]) {  
    error("Multipart/form-data did not start with a delimeter; can be a virus.<hr><pre>Boundary=$self->{boundary}<hr>$datablocks[0]</pre>")
  }

  shift @datablocks;

  foreach my $b (@datablocks) {
    my $info={};
    while ($b =~ /^Content-(.+)[\r|\n]{2}/i) {
      $e.="<pre> *** Content found: $1</pre><br>";
      $b=substr($b,length($1)+9);
      my $cont=$1;
      my @items = split(/\;/,$cont);
      foreach my $i (@items) {
        $i =~ s/^[\s]+//;
        $e.="<pre>I=$i</pre><br>";
        if ($i =~ /^name=\"(.+?)\"/i) {
          $info->{name}=$1
        } elsif ($i =~ /^filename=\"(.*?)\"/i) {
          $info->{filename}=$1
        } elsif ($i =~ /^Type:\s?(.+)$/i) {
          $info->{type}=$1
        } elsif ($i =~ /^charset=(.+)$/i) {
          $info->{charset}=$1
        } elsif ($i =~ /^Content-transfer-encoding:\s?(.+)$/i) {
          $info->{encoding}=$1
        }
      }
      $e.="<pre>Info found:<br>";
      foreach my $k (keys %{$info}) {
        $e.="$k=\"$info->{$k}\"<br>"
      }
      $e.="<hr width=200 align=left></pre>"
    }
    if ($b !~ /^[\r\n]/) {
      error("Illegal datablock found in block '$curblock'<br><pre>$b</pre>"); return
    }
    if ($b !~ /[\r\n]$/) {
      error("Illegal datablock found in block '$curblock'<br><pre>$b</pre>"); return
    }

    $b=~s/[\r|\n]{2}(.+)[\r|\n]{2}/$1/gs;

    push @{$self->{key}->{$info->{name}}},$b;
    if ($info->{filename}) {
      $self->{fileupload}=1;
      if ($info->{encoding}) {
        # decode
      }
      my $name=$info->{name};
      $self->{upload}{$name} = {
        length => length($b),
        mime => $info->{type},
      };
      my $path=$info->{filename};
      # Delete illegal characters
      $path =~ s/[*?]//g;
      # Decode URL-encoding
      $path =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
      # Make spaces -> underscores
      $path =~ s/ /_/g;
      # Make backslashes -> slashes
      $path =~ s/\\/\//g;
      $self->{upload}{$name}{dirfile}=$path;
      my @spath=split(/\//,$path); my $file=pop @spath;
      $self->{upload}{$name}{file}=$file;
      $self->{upload}{$name}{dir}=join("/",@spath);
      my ($rf,$ext) = split(/\./,$file);
      $self->{upload}{$name}{filename}=$rf;
      $self->{upload}{$name}{ext}=$ext;
    }
#    $b =~ s/\r\n/\r\n[enter]/g;
#    $e.="<pre>Data=$b</pre>";
    $curblock++
  }
}

# End of file gpost.pm
