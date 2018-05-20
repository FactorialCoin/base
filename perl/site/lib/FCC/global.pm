#!/usr/bin/perl

package FCC::global;

#######################################
#                                     #
#     FCC Global functions            #
#                                     #
#    (C) 2018 Domero                  #
#                                     #
#######################################

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.21';
@ISA         = qw(Exporter);
@EXPORT      = qw($COIN $HP setcoin $FCCVERSION $FCCBUILD $FCCTIME $FCCMAGIC $FCCSERVERKEY $TRANSTYPES $RTRANSTYPES
                  $MINIMUMFEE $MINERPAYOUT $MINEBONUS $FCCSERVERIP $FCCSERVERPORT
                  prtm securehash octhex hexoct hexchar dechex hexdec validh64 encode_base64 decode_base64
                  fcctime setfcctime fcctimestring extdec doggy calcfee doggyfee fccstring fccencode zb64 b64z);
@EXPORT_OK   = qw();

use POSIX;
use Digest::SHA qw(sha256_hex sha512_hex);
use gfio 1.08;
use Crypt::Ed25519;
use Gzip::Faster;
use gerr qw(error);

our $COIN = "FCC";
our $FCCVERSION = "0101"; # ledger version
our $FCCBUILD = "1.21a";   # software version
our $FCCTIME = tzoffset();
our $FCCMAGIC = 'FF2F89B12F9A29CAB2E2567A7E1B8A27C8FA9BF7A1ABE76FABA7919FC6B6FF0F';
our $FCCSERVERIP = '149.210.194.88';
our $FCCSERVERPORT = 5151;
our $FCCSERVERKEY = "FCC55202FF7F3AAC9A85E22E6990C5ABA8EFBB73052F6EA1867AF7B96AE23FCC";
our $MINIMUMFEE = 50;
our $MINERPAYOUT = 1000000000;
our $MINEBONUS = 50000000;
our $TRANSTYPES = {
  genesis => '0',
  in => '1',
  out => '2',
  coinbase => '3',
  fee => '4'
};
our $RTRANSTYPES = {};
foreach my $k (keys %$TRANSTYPES) {
  $RTRANSTYPES->{$TRANSTYPES->{$k}}=$k
}
our $HP = {}; for (my $i=0;$i<10;$i++) { $HP->{$i}=$i }
$HP->{'A'}=10; $HP->{'B'}=11; $HP->{'C'}=12; $HP->{'D'}=13; $HP->{'E'}=14; $HP->{'F'}=15; 
1;

sub setcoin {
  $COIN=$_[0];
  if ($COIN eq 'PTTP') {
    $FCCMAGIC = "8BF879BEC8FA9EC6CA3E7A96B26F7AA76F6AA4E78BADCFA1665A8A9CD67ADD0F";
    $FCCSERVERPORT = 9612;
    $FCCSERVERKEY = "1111145AFA4FBB1CF8D406A234C4CC361D797D9F8F561913D479DBC28C7A4F3E";
  }
}

sub tzoffset {
  my $t = time();
  my $utc = mktime(gmtime($t));
  my $local = mktime(localtime($t));
  return ($utc - $local);
}

sub fcctime {
  if (!$_[0]) { $FCCTIME=0; return }
  my $t = time();
  my $local = mktime(localtime($t));
  $FCCTIME = $_[0] - $local
}

sub setfcctime {
  $FCCTIME=$_[0]
}

sub fcctimestring {
  my @t=localtime(time + $FCCTIME);
  my $tm=('Sun','Mon','Tue','Wed','Thu','Fri','Sat')[$t[6]]; $tm.=", ";
  my $yr=$t[5]+1900; my $mon=('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')[$t[4]];
  $tm.="$t[3] $mon $yr ";
  $tm.=join(':',sprintf("%02d",$t[2]),sprintf("%02d",$t[1]),sprintf("%02d",$t[0]));
  $tm.=" GMT";
  return $tm
}

sub securehash {
  my ($code) = @_;
  return uc(sha256_hex(sha512_hex($code)))
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

sub hexchar {
  my ($num) = @_;
  return (0,1,2,3,4,5,6,7,8,9,'A','B','C','D','E','F')[$num]
}

sub dechex {
  my ($dec,$len) = @_;
  if (!defined $dec) { error ("FCC::global::dechex: No decimal given") }
  if (!$len) { error "FCC::global::dechex - No length given" }
  my $out="";
  if ($len==1) { return hexchar($dec & 15) }
  while ($len>0) {
    my $byte=$dec & 255;
    my $hex=hexchar($byte >> 4);
    $hex.=hexchar($byte & 15);
    $out="$hex$out";
    $dec>>=8;
    $len-=2
  }
  return $out
}

sub hexdec {
  my ($hex) = @_;
  if ($hex =~ /[^0-9A-F]/) {
    error "FCC::global::hexdec - Illegal hex given '$hex'"
  }
  my $dec=0;
  for (my $i=0;$i<length($hex);$i++) {
    $dec<<=4; $dec+=hex(substr($hex,$i,1))
  }
  return $dec
}

sub validh64 {
  my ($hex) = @_;
  if (length($hex) != 64) { return 0 }
  if ($hex =~ /[^0-9A-F]/) { return 0 }
  return 1
}

sub extdec {
  my ($dec) = @_;
  $dec=$dec || 0; my $d=int($dec);
  my $v=int(($dec + 0.000000005 - $d)*100000000);
  while (length($v)<8) { $v="0$v" }
  return $d.'.'.$v
}

sub doggy {
  my ($amount) = @_;
  return int(($amount+0.000000005)*100000000)
}

sub feeint {
  my ($fee) = @_;
  return int($fee*100)
}

sub calcfee {
  my ($amount,$fee) = @_;
  if (!$fee) { return 0 }
  $amount=extdec($amount);
  my $feefloat=(feeint($fee)/100);
  my $cfee=extdec($amount*($feefloat/100));
  if ($cfee eq '0.00000000') { $cfee='0.00000001' }
  return $cfee
}

sub doggyfee {
  my ($amount,$fee) = @_;
  if (!$fee) { return 0 }
  my $cfee=int($amount*($fee/10000));
  if (!$cfee) { $cfee=1 }
  return $cfee
}

sub fccstring {
  my ($amount,$fee) = @_;
  return extdec(extdec($amount)+calcfee($amount,$fee))
}

sub fccencode {
  my ($data,$password) = @_;
  my $h1=securehash($password);
  my $h2=securehash(scalar reverse $password);
  my $pos=0; my $offset=0; my $todo=length($data); my $dpos=0; my $coded="";
  while ($dpos<$todo) {
    my $get=$HP->{substr($h2,$pos,1)};
    $pos+=$get; $pos %= 64; if ($pos == 63) { $pos=0 }
    my $code=($HP->{substr($h1,$pos,1)}<<4) + $HP->{substr($h1,$pos+1,1)};
    my $tocode=ord(substr($data,$dpos,1));
    $coded.=chr($code ^ $tocode);
    $dpos++
  }
  return octhex($coded)
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
}

sub encode_base64 {
  # RFC 3548
  my ($data) = @_;
  my $c62='+'; my $c63="/"; my $pad="="; 
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

sub decode_base64 {
 # RFC 3548
 my ($data) = @_;
 my $c62='+'; my $c63="/"; my $pad="="; 
 my $len=length($data);
 my $pos=0; my $val=0; my $br=0; my $end=0; my $out="";
 while ($pos<$len && !$end) {
   my $enc=substr($data,$pos,1);
   if ($enc =~ /([A-Z])/) { $val=($val<<6)+ord($1)-ord('A'); $br+=6 }
   elsif ($enc =~ /([a-z])/) { $val=($val<<6)+26+ord($1)-ord('a'); $br+=6 }
   elsif ($enc =~ /([0-9])/) { $val=($val<<6)+52+ord($1)-ord('0'); $br+=6 }
   elsif ($enc eq $c62) { $val=($val<<6)+62; $br+=6 }
   elsif ($enc eq $c63) { $val=($val<<6)+63; $br+=6 }
   elsif ($enc eq $pad) { $val=($val<<6); $br+=6; $end++ }
   if (!$val && $end) { return $out }
   while ($br>=8) {
     my $c=($val>>($br-8)); $out.=chr($c); $br-=8; $val&=((1<<$br)-1)
   }
   $pos++;
 }
 if ($br) {
   my $c=($val>>(8-$br)); $out.=chr($c)
 }
 return $out
}

sub zb64 {
  my ($data) = @_;
  return encode_base64(gzip($data))
}

sub b64z {
  my ($data) = @_;
  return gunzip(decode_base64($data))
}

sub prtm {
  my ($s,$m,$h) = localtime(time + $FCCTIME);
  if (length($s)<2) { $s="0$s" }
  if (length($m)<2) { $m="0$m" }
  if (length($h)<2) { $h="0$h" }
  print STDOUT "[$h:$m:$s] ";
  return ""
}

# EOF FCC::global (C) 2018 Domero