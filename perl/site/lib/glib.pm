#!/usr/bin/perl
################################################################################

package glib;
# Pragmas.

use strict;
use warnings; no warnings qw<uninitialized>;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use gparse;

$VERSION     = '1.2.1';
@ISA         = qw(Exporter);
@EXPORT      = qw(
    enc_entities dec_entities utfans
    toJSON fromJSON 
    toJSONfile fromJSONfile 
    toZJSONfile fromZJSONfile 
    fromXML
    merge_hash flat_hash flat_array flat_value flat_trunc flattenvalue 
    sum
    hex2str str2hex octhex hexoct dechex hexdec hexchar echr xchr nchr xcomment
    deflate inflate 
    enc_zlib dec_zlib 
    zip unzip 
    enc_zip dec_zip 
    encode_base64 decode_base64
    zlb64 b64zl 
    zb64 b64z 
    enc_b64 dec_b64 
    enc_zlb64 dec_zlb64 
    enc_zb64 dec_zb64 
    encode_json_pretty pretty_json
    enc_json dec_json 
    enc_json_b64 dec_json_b64 
    enc_b64_json dec_b64_json 
    deflate_json inflate_json 
    zip_json unzip_json 
    wr_zjs rd_zjs
    enc_zlb64_json dec_zlb64_json 
    enc_json_zlb64 dec_json_zlb64 
    enc_json_zb64 dec_json_zb64 
    enc_zb64_json dec_zb64_json
    xt round floor 
    sl 
    print_decode 
    strchars strcolumns strlength
    strlen strleft strright strcenter strstrp
    numdisplay numstr prcstr unitstr secstr 
    datetime timestring clockstring 
    timeString dateString
    tmstr clockstr utmstr bytes 
    isListed 
    realtime 
    runsyscall
    subbit packbits bzpackbits unpackbits bzunpackbits bzbit bzbits
    packbitmap unpackbitmap isbitmapped setbitmap unsetbitmap
    deepcompare 
    clonecopy ondef
    pack_hash
);
@EXPORT_OK   = qw();


################################################################################
# GLIB (C) 2019 DOMERO
################################################################################

use Compress::Zlib ;
use Gzip::Faster;
use Time::HiRes qw(usleep gettimeofday);
use URI::Encode qw(uri_encode uri_decode);
use HTML::Entities qw(decode_entities encode_entities);
use XML::Simple qw(:strict);
use Unicode::LineBreak;
use Unicode::GCString;
use JSON;
use utf8;

################################################################################
# HTML
sub enc_entities {
    return encode_entities(@_)
}

sub dec_entities {
    return decode_entities(@_)
}

################################################################################

sub utfans {
    my ($line,$len,$idx)=@_; my $strm=[]; my $str=""; my $l=0; my $ix=0;
    #die(pretty_json({line=>$line,len=>$len,idx=>$idx}));
    while (length($line) && $line =~ /^(.+m)([^]+)/gs && $l < $len) {
        my ($col,$chr) = ($1,$2);
        my $color = echr($col);
        if ((!defined $idx || $l>=$idx) && $l < $len) { push @$strm, [$color,$chr] }
        $l+=length($chr); if ($l>=$len) {last}
        $line = substr($line,length($color.$chr));
    }
    for my $i (0..$#$strm) { $str .= join('',@{$strm->[$i]}) }
    return $str
}

################################################################################

sub toJSON { return JSON->new->allow_blessed->convert_blessed->utf8->canonical->pretty->encode($_[0]) }
sub fromJSON { return JSON->new->utf8->decode($_[0]) }

sub toJSONfile { my ($file,$data)=@_; gfio::create($file,toJSON($data)) }
sub fromJSONfile { my ($file)=@_; return fromJSON(gfio::content($file)) }

sub toZJSONfile { my ($file,$data)=@_; gfio::create($file,'ZJS:'.zip(toJSON($data))) }
sub fromZJSONfile { # also raw json compatible
    my ($file)=@_;
    my $content=gfio::content($file);
    if ($content =~ /ZJS\:(.+)$/gs || $content =~ /ZIP\:(.+)$/gs) {
        return fromJSON(unzip($1))
    } else {
        return fromJSON($content)
    }
}

sub fromXML { if ($_[1]) { return XMLin($_[1],forcearray=>0,keyattr=>'') || {error=>$@}} else { return {} }}

################################################################################
# Simple Math 
################################################################################
sub sum {
    my $tot=0;
    for my $n (@_) { $tot += int(defined $n ? $n : 0) }
    return $tot
}
################################################################################

sub str2hex {
    my ($str)=@_;
    my $hex="";
    for my $c (split(//,$str)) { $hex.=dechex(ord($c),2) }
    return $hex
}
sub hex2str {
    my ($hex)=@_; my $str=""; my $b="";
    for my $h (split(//,$hex)) {
        $b.=$h;
        if (length("$b") == 2) {
            $str.=chr(hexdec($b));
            $b="";
        }
    }
    return $str
}

################################################################################
# HEX <-> OCT
sub octhex {
	my ($key) = @_; if (!defined $key) { return "" }
  	my $hex; for my $c (split(//,$key)) { $hex.=sprintf('%02X',ord($c)) }
  	return $hex  
}

sub hexoct {
  	my ($hex) = @_; if (!defined $hex) { return "" }
  	my $key; for (my $i=0;$i<length($hex);$i+=2) { $key.=chr(hex(substr($hex,$i,2))) }
  	return $key
}

################################################################################
# HEX <-> DEC
$::HEXCHAR=[0,1,2,3,4,5,6,7,8,9,'A','B','C','D','E','F'];

sub dechex {
  	my ($dec,$len) = @_; if (!defined $dec || !$len) { return undef }
  	if ($len==1) { return hexchar($dec & 15) }
  	my $out="";
  	while ($len>0) {
		my $byte=$dec & 255;
		$out=$::HEXCHAR->[$byte >> 4].$::HEXCHAR->[$byte & 15].$out;
		$dec>>=8;
		$len-=2
  	}
  	return $out
}

sub hexdec {
	my ($hex) = @_; if ($hex =~ /[^0-9A-F]/) { return undef }
	my $dec=0; for my $c (split(//,$hex)) { $dec<<=4; $dec+=hex($c) }
	return $dec
}

sub hexchar {
  my ($num) = @_;
  return (0,1,2,3,4,5,6,7,8,9,'A','B','C','D','E','F')[$num]
}

################################################################################
# DEC|HEX <-> CHR (UTF-8||ANSI)
sub hexchr {
    my ($hex)=@_; if (!defined $hex || $hex =~ /[^0-9A-F]/) { die ("No(t a) HEX Input") }
    my $chr; if (!eval('$chr="\\x{'.$hex.'}"; return 1') || $@) { die $@ }
    return $chr
}

sub decchr {
    my @dec=@_; if ($#dec == -1) { die ("Not DEC Input") }
    my $hex=""; 
    while ($#dec > -1) {
        if ($dec[0]>255) { die ("Not A Byte Value Input"); last }
        $hex .= dechex(shift(@dec),2)
    }
    return hexchr($hex)
}

################################################################################
sub xchr {
    my ($hex)=@_;
    my $chr="";
    if(!eval ('$chr="\\x{'.$hex.'}"; return 1')) { die $@ }
    return $chr
}
sub echr {
    my ($str)=@_;
    my $chr="";
    if(!eval ('$chr="\\e'.$str.'"; return 1')) { die $@ }
    return $chr
}
sub nchr {
    my @dec=@_;
    my $hex="";
    while ($#dec > -1) { $hex .= dechex(shift(@dec),2) }
    return xchr($hex)
}

sub xcomment {
    my ($str)=@_; if(!defined $str) { return "[???]" }
    return "[". length($str) .";" . join(":",@{[map { octhex($_) } split(//,$str)]}) . "]"
}
################################################################################
# BIN -> Zlib (Best Compression)

sub deflate { my ($str)=@_; return compress($str,Z_BEST_COMPRESSION)||'' }
sub inflate { my ($bin)=@_; return uncompress($bin)||'' }

################################################################################
# BIN <-> zlib:[mime];data,[data]
sub enc_zlib {
	my ($mime,$data)=@_;
	return "zlib:$mime;data,".deflate($data)
}

sub dec_zlib {
	my ($data)=@_;
	my ($header,@bin)=split(/\,/,$data);
	my ($head,$type)=split(/\;/,$header);
	my ($info,$mime)=split(/\:/,$head);
	return ($mime,inflate(join(',',@bin)))
}

################################################################################
# BIN <-> Gzip (Fastest Compression)

sub zip { return ($_[0] ? gzip(@_) : '') }
sub unzip { return ($_[0] ? gunzip(@_) : '') }

################################################################################
# BIN <-> gzip:[mime];data,[data]
sub enc_zip {
	my ($mime,$data)=@_;
	return "gzip:$mime;data,".zip($data)
}

sub dec_zip {
	my ($data)=@_;
	my ($header,@bin)=split(/\,/,$data);
	my ($head,$type)=split(/\;/,$header);
	my ($info,$mime)=split(/\:/,$head);
	return ($mime,unzip(join(',',@bin)))
}

################################################################################
# BIN <-> Base64

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

################################################################################
# BIN <-> Zlib <-> Base64
sub zlb64 {
	my ($data) = @_;
	return encode_base64(deflate($data))
}

sub b64zl {
	my ($data) = @_;
	return inflate(decode_base64($data))
}

################################################################################
# BIN <-> Gzip <-> Base64
sub zb64 {
	my ($data) = @_;
	return encode_base64(zip($data))
}

sub b64z {
	my ($data) = @_;
	return unzip(decode_base64($data))
}

################################################################################
# BIN <-> data:[mime];base64,[data]
sub enc_b64 {
	my ($mime,$data)=@_;
	return "data:$mime;base64,".encode_base64($data)
}

sub dec_b64 {
	my ($data)=@_;
	if ($data =~/^zlib\:/gs) { return dec_zlb64($data) }
	if ($data =~/^gzip\:/gs) { return dec_zb64($data) }
	my ($header,$b64)=split(/\,/,$data);
	my ($head,$type)=split(/\;/,$header);
	my ($info,$mime)=split(/\:/,$head);
	return ($mime,decode_base64($b64))
}

################################################################################
# BIN <-> zlib:[mime];base64,[data]
sub enc_zlb64 {
	my ($mime,$data)=@_;
	return "zlib:$mime;base64,".zlb64($data)
}

sub dec_zlb64 {
	# gzip:[image/png];base64,[data]
	my ($data)=@_;
	my ($header,$b64)=split(/\,/,$data);
	my ($head,$type)=split(/\;/,$header);
	my ($info,$mime)=split(/\:/,$head);
	return ($mime,b64zl($b64))
}

################################################################################
# BIN <-> gzip:[mime];base64,[data]
sub enc_zb64 {
	my ($mime,$data)=@_;
	return "gzip:$mime;base64,".zb64($data)
}

sub dec_zb64 {
	# gzip:[mime];base64,[data]
	my ($data)=@_;
	my ($header,$b64)=split(/\,/,$data);
	my ($head,$type)=split(/\;/,$header);
	my ($info,$mime)=split(/\:/,$head);
	return ($mime,b64z($b64))
}

################################################################################
# HASH|ARRAY <-> JSON

sub encode_json_pretty { return JSON->new->allow_blessed->convert_blessed->utf8->canonical->pretty->encode(@_) }
sub pretty_json { return encode_json_pretty(@_) }

sub enc_json { return JSON->new->utf8->canonical->encode(@_) }
sub dec_json { return JSON->new->utf8->canonical->decode(@_) }

################################################################################
# HASH|ARRAY <-> JSON <-> Base64
sub enc_json_b64 { return b64(enc_json(@_)) }
sub dec_json_b64 { return dec_json(b64(@_)) }

################################################################################
# HASH|ARRAY <-> JSON <-> data:application/json;base64,[b64jsondata]
sub enc_b64_json { return enc_b64('application/json',enc_json(@_)) }
sub dec_b64_json { my ($mime,$dat)=dec_b64(@_); return dec_json($dat) }

################################################################################
# HASH|ARRAY <-> JSON <-> Zlib
sub deflate_json { return deflate(enc_json(@_)) }
sub inflate_json { return dec_json(inflate(@_)) }

################################################################################
# HASH|ARRAY <-> JSON <-> Gzip 
sub zip_json { return zip(enc_json(@_)) }
sub unzip_json { return dec_json(unzip(@_)) }
################################################################################
sub wr_zjs {
    my ($path,$data)=@_;
    gfio::create($path,"ZJS:".zip_json($data))
}

sub rd_zjs {
    my ($path)=@_;
    my $data=(-f $path ? gfio::content($path) : "{}");
    if ($data =~ /^ZJS\:(.+)$/gs) { return unzip_json($1) }
    return dec_json($data || "{}")
}

################################################################################
# HASH|ARRAY <-> JSON <-> zlib:application/json;base64,[b64zlibjsondata]
sub enc_zlb64_json { return enc_zlb64('application/json',enc_json(@_)) }
sub dec_zlb64_json { my ($mime,$dat)=dec_zlb64(@_); return dec_json($dat) }

################################################################################
# HASH|ARRAY <-> JSON <-> Zlib <-> Base64
sub enc_json_zlb64 { return zlb64(enc_json(@_)) }
sub dec_json_zlb64 { return dec_json(b64zl(@_)) }

################################################################################
# HASH|ARRAY <-> JSON <-> Gzip <-> Base64
sub enc_json_zb64 { return zb64(enc_json(@_)) }
sub dec_json_zb64 { return dec_json(b64z(@_)) }

################################################################################
# HASH|ARRAY <-> JSON <-> gzip:application/json;base64,[b64gzipjsondata]
sub enc_zb64_json { return enc_zb64('application/json',enc_json(@_)) }
sub dec_zb64_json { my ($mime,$dat)=dec_zb64(@_); return dec_json($dat) }

################################################################################
# String Tools

# Extend Number to String : Number, front-length, prefix-fill, [back-length, suffix-fill]
sub xt {
    my ($v,$h,$p,$l,$s)=@_;
    my @n=split(/\./,"$v"); if(!$n[1] && $l){ $n[1]=0 }
    return ("$p"x($h-length($n[0])))."$n[0]".($l ? ".$n[1]".("$s"x($l-length("$n[1]"))):"")
}

sub round {
    my ($v,$n)=@_;
    my $m="1".("0"x$n);
    return (((($v)*$m)+0.5)>>0)/$m;
}

sub floor {
    my ($v,$n)=@_;
    my $m="1".("0"x$n);
    return ((($v)*$m)>>0)/$m;
}

sub sl { defined $_[0] ? $_[0] x (defined $_[1] && int($_[1]||0) > 0 ? $_[1]:1) : "" }

sub print_decode {
    my ($msg)=@_;
    print decode_entities($msg);
}

sub strchars { my ($str)=@_; my $gcstr=Unicode::GCString->new($str); $gcstr->chars() }
sub strcolumns { 
    my ($str)=@_; 
    my $gcstr=Unicode::GCString->new($str); 
    return $gcstr->columns() 
}
sub strlength { my ($str)=@_; my $gcstr=Unicode::GCString->new($str); $gcstr->length() }

sub strleft { my ($str,$l,$s)=@_; $l-=strlen($str); return $str . ($l > 0 ? (($s||" ") x $l):"") }
sub strright { my ($str,$l,$s)=@_; $l-=strlen($str); return ($l > 0 ? (($s||" ") x $l):"") . $str }
sub strcenter { my ($str,$l,$s)=@_; $l-=strlen($str); my $ls=($l>>1 > 0 ? (($s||" ") x ($l>>1)):""); $l-=($l>>1); my $rs=($l > 0 ? (($s||" ") x $l):""); return $ls . $str . $rs }

sub numstr {
    my ($num,$fl,$bl,$pf,$sf)=@_;
    my $anum=abs($num);
    for my $i (0..$bl) { $anum*=10 }
    $anum=int($anum);
    for my $i (0..$bl) { $anum/=10 }
    my ($f,$b)=split(/\./,"$anum");
    if (!defined $b) { $b="0" }
    if (!defined $pf) { $pf=" " }
    if (!defined $sf) { $sf="0" }
    my $fll=($fl-length("$f")); if ($fll<0) { $fll=0 }
    my $bll=($bl-length(substr($b,0,$bl)));  if ($bll<0) { $bll=0 }
    return ($num<0?"-":"").($pf x $fll)."$f".($bl>0 ? ".".substr($b,0,$bl).($sf x $bll):"")
}

sub numdisplay {
    my ($num,$round)=@_;
    my ($h,$l)=split(/\./,"$num");
    my $n=[split(//,"$h")];
    my $s=""; my $p=0;
    while ($#{$n}>-1) {
        if ($p && $p % 3 == 0) { $s=",$s" }
        $p++;
        $s=pop(@$n).$s;
    }
    return $s.($l ? ".". ($round ? substr("$l",0,$round):$l):'')
}

sub prcstr { return numstr($_[0],3,$_[1]||3)."%" }

sub unitstr {
    my ($num,$round)=@_;
    my $u="";
    if ($num < 1) {
        $num*=1000; $u="m"; # milli-
        if ($num < 0.01) { 
            $num*=1000; $u="µ"; # micro-
            if ($num < 0.01) { 
                $num*=1000; $u="n"; # nano-
                if ($num < 0.01) { 
                    $num*=1000; $u="p"; # pico-
                    if ($num < 0.01) { 
                        $num*=1000; $u="f"; # femto-
                        if ($num < 0.01) { 
                            $num*=1000; $u="a"; # atto-
                            if ($num < 0.01) { 
                                $num*=1000; $u="z"; # zepto-
                                if ($num < 0.01) { 
                                    $num*=1000; $u="y"; # yocto-
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return numstr($num,0,$round,"","0")." $u";
}

sub secstr {
    my ($sec,$round)=@_;
    return unitstr($sec,$round,)."s";
}

sub strlen {
    my ($str)=@_;
    if (!defined $str || !length($str)) { return length($str) }
    return length(strstrp($str))
}
sub strstrp { my ($str)=@_; $str =~ s/\x{1B}\x{5B}[^m]*m//gsi; return $str }

sub bytes {
    my ($v)=@_; my $s="b";
    if ($v >= 1024) {$s="Kb"; $v/=1024 }
    if ($v >= 1024) {$s="Mb"; $v/=1024 }
    if ($v >= 1024) {$s="Gb"; $v/=1024 }
    if ($v >= 1024) {$s="Tb"; $v/=1024 }
    return xt(round($v,3),3,' ',3,'0')." $s"
}

sub isListed {
    my ($k,@s)=@_; 
    if ($k) {
        for my $o (@s) { if ($o eq $k) { return 1 } }
    }
    return 0
}

################################################################################
# Time Tools

sub datetime { # YYYY-MM-DD HH:MI:SS
    my ($time)=@_; my @t=localtime($time||time());
    return join('-',($t[5]+1900),$t[4],$t[3]) . ' ' . join(':',sprintf("%02d",$t[2]),sprintf("%02d",$t[1]),sprintf("%02d",$t[0]))
}

sub timestring {
    my ($time)=@_; my @t=localtime($time||time);
    my $tm=('Sun','Mon','Tue','Wed','Thu','Fri','Sat')[$t[6]]; $tm.=", ";
    my $yr=$t[5]+1900; my $mon=('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')[$t[4]];
    $tm.="$t[3] $mon $yr ";
    $tm.=join(':',sprintf("%02d",$t[2]),sprintf("%02d",$t[1]),sprintf("%02d",$t[0]));
    $tm.=" GMT";
    return $tm
}


sub dateString {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($_[0]||time);
  return
   @{['Sun','Mon','Tue','Wed','Thu','Fri','Sat']}[$wday]." ".
   @{['Jan','Feb','Mar','Apr','Jun','Jul','Aug','Sep','Okt','Nov','Dec']}[$mon]." ".
   $mday." ".(1900+$year)." ".
   "[".($hour<10?'0':'')."$hour:".($min<10?'0':'')."$min:".($sec<10?'0':'')."$sec] UTC"
}

sub timeString {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($_[0]||time);
  return "[".($hour<10?'0':'')."$hour:".($min<10?'0':'')."$min:".($sec<10?'0':'')."$sec]"
}

sub tmstr { 
    my ($sec)=@_; $sec=$sec||0;
    my $min=($sec/60)>>0; $sec-=($min*60);
    my $hour=($min/60)>>0; $min-=($hour*60);
    my $days=($hour/24)>>0; $hour-=($days*24);
    return ($days ? ($days < 10?"0":"").($days < 100?"0":"")."$days day".($days>1 ? "s":"")." ":"").($hour < 10?"0":"")."$hour:".($min < 10?"0":"")."$min:".($sec < 10?"0":"")."$sec"
}

sub clockstr {
  my ($s,$m,$h) = localtime($_[0]||time);
  return sprintf("%02d",$h).":".sprintf("%02d",$m).":".sprintf("%02d",$s)
}

sub clockstring { return '['.clockstr(@_).']' }

sub utmstr {
    my ($utm)=@_;
    my $ud=($utm/(60*60*24))>>0; $utm-=$ud*60*60*24;
    my $uh=($utm/(60*60))>>0; $utm-=$uh*60*60;
    my $um=($utm/60)>>0; $utm-=$um*60;
    my $us=$utm>>0;
    return ($ud ? "$ud day".($ud > 1 ?"s":"")." ":"").sprintf("%02d",$uh).":".sprintf("%02d",$um).":".sprintf("%02d",$us)
}

sub realtime {
	my $time;
	while (!defined ($time=gettimeofday())) { usleep(1) }
	return $time
}

################################################################################
# System Commands

sub runsyscall {
    my ($proc,@args)=@_; my $out=[]; my $error;
    $::EVALMODE++; 
    eval {
        open my ($output), "-|", $proc, @args or die "Could not run program: $!\n$proc <@args>\n";
        while (my $line = <$output>) { push @$out, $line } 
    };
    $::EVALMODE--;
    if ($@) {
        $error.="EVAL ERROR: $@\n";
        push @$out, $error
    }
    return ($out,$error)
}

################################################################################
# BITS MAPPING

sub subbit { # ($str,$bitpos,$val)
    my $bytepos=$_[1]>>3;
    my $bitpos=$_[1]-($bytepos<<3);
    my @byte = split(//,(length($_[0]) >= ($bytepos+1) ? unpack('B8',substr($_[0],$bytepos,1)) : '00000000'));
    if (defined $_[2]) {
        $byte[$bitpos] = $_[2] ? 1 : 0;
        while (length($_[0]) < $bytepos+1) { $_[0] .= pack('B8','00000000') }
        substr($_[0],$bytepos,1,pack('B8',join('',@byte)))
    } else {
        return $byte[$bitpos]
    }
}

sub packbits {
    my ($str)=@_;
    if ($str =~ /^[0|1]+$/) {
        #print "[PACKBITS][$str]\n";
        my $out="";
        my @bits=split(//,$str);
        my @byte=();
        while ($#bits > -1) {
            push @byte, shift(@bits);
            if ($#byte == 7) {
                $out.=pack('B8',join('',@byte));
                @byte=();
            }
        }
        if ($#byte > -1) {
            while ($#byte < 7) { push @byte, "0" }
            $out.=pack('B8',join('',@byte));
        }
        return $out
    }
    return $str||""
}

sub bzpackbits {
    return encode_base64(zip(packbits(@_)))
}

sub packbitmap {
    my ($map)=@_; my $str=""; 
    if ($#{$map} > -1) {
        $map=[sort {$a<=>$b} @{$map}]; my $high=$map->[$#{$map}];
        if ($high>0) {
            $str = "0" x (1+$high);
            #print "[PACKMAP][@{$map}][$str]\n";
            for my $i (@{$map}) {
                #print "[PACKSTR][$str]";
                substr($str,$i,1)='1';
                #print "[TOSTR][$str]\n";
            }
            #print "[PACKSTR][@{$map}][$str]\n";
            return bzpackbits($str)
        }
    }
    #print "[PACKBZ][$str]\n";
    return $str
}

################################################################################

sub unpackbits {
    my ($str)=@_;
    if (length($str)) {
        my $out="";
        my @bytes=split(//,$str||"");
        for my $i (0..$#bytes) { $out.=unpack('B8',$bytes[$i]) }
        return $out
    }
    return $str||""
}

sub bzunpackbits {
    my ($str)=@_;
    if (!defined $str || !length($str)) { return "" }
    $::EVALMODE++;
    eval { $str=unzip(decode_base64($str)) };
    $::EVALMODE--;
    return unpackbits($str)
}

sub bzbit { # ($str,$bitpos,$val)
    if (defined $_[2]) {
        $::EVALMODE++;
        eval { $_[0]=unzip(decode_base64($_[0])); };
        $::EVALMODE--;
        subbit(@_); 
        $_[0]=encode_base64(zip($_[0])) 
    }
    else { 
        my $bits="";
        $::EVALMODE++;
        eval { $bits=unzip(decode_base64($_[0])); };
        $::EVALMODE--;
        return subbit($bits,$_[1]) 
    }
}

sub bzbits { # $str
  return bzunpackbits(@_)
}

sub unpackbitmap {
   # print "[UNPACKBITMAP][@_]\t";
    my $str=bzbits(@_); my $map=[]; my $len=length($str);
    #print "[UNPACKBITS][$str]\n";
    #print "[UNPACKBITS][$len][$str]\n";
    for my $i (0..($len-1)) { 
        #print STDOUT "[BIT][$i][".substr($str,$i,1)."]";
        if (int(substr($str,$i,1)) == 1) {
            #print STDOUT "[ON]";
            push @{$map}, $i 
        }
        #print STDOUT "\n";
    }
    return $map
}

################################################################################

sub isbitmapped { my ($map,$i)=@_; return isListed($i,@{$map}) ? 1 : 0 }

sub setbitmap {
    my ($map,$i)=@_;
    if (!isbitmapped($map,$i)) { push @{$map}, $i }
    return [sort{$a<=>$b} @{$map}]
}

sub unsetbitmap {
    my ($map,$i)=@_;
    if (isbitmapped($map,$i)) { my @m=(); for my $id (@{$map}){ if($id ne $i) { push @m, $id } }; $map=[sort{$a<=>$b} @m] }
    return $map
}

################################################################################
# HASH/ARRAY COMPARING

sub deepcompare {
    my ($v1,$v2)=@_;
    if (!defined $v1 && !defined $v2) { return 1 }
    elsif (!defined $v1 && defined $v2 || defined $v1 && !defined $v2) { return 0 }
    elsif (ref($v1) eq 'HASH') {
        if (ref($v2) ne 'HASH') { return 0 }
        if ($v1 eq $v2) { return 1 }
        for my $k1 (keys %$v1) { if (!deepcompare($v1->{$k1},$v2->{$k1})) { return 0 } }
        for my $k2 (keys %$v2) { if (!defined $v1->{$k2}) { return 0 } }
    }
    elsif (ref($v1) eq 'ARRAY') {
        if (ref($v2) ne 'ARRAY') { return 0 }
        if ($v1 eq $v2) { return 1 }
        if ($#$v1 ne $#$v2) { return 0 }
        for my $i (0..$#$v1) { if (!deepcompare($v1->[$i],$v2->[$i])) { return 0 } }
    }
    elsif (ref($v1) eq 'SCALAR') {
        if (ref($v2) ne 'SCALAR' && ${$v1} ne $v2) { return 0 }
        if (${$v1} ne ${$v2}) { return 0 }
    }
    elsif (ref($v2) eq 'SCALAR') {
        if ($v1 ne ${$v2}) { return 0 }
    }
    elsif ($v1 ne $v2) { return 0 }
    return 1
}

################################################################################
# HASH/ARRAY/SCALAR Cloning

sub clonecopy {
    my ($v,$ref)=@_;
    if (!defined $v) { return undef }
    elsif (ref($v) =~ /HASH/) {
        my %h=(); for my $k (keys %{$v}) { $h{$k}=clonecopy($v->{$k}) }
        return \%h
    }
    elsif (ref($v) =~ /ARRAY/) {
        my @a=(); for my $i (0..$#$v) { $a[$i]=clonecopy($v->[$i]) }
        return \@a
    }
    elsif (ref($v) =~ /SCALAR/) {
        my $s=${$v};
        return \$s
    }
    elsif (ref($v)) {
        return ref($v)
    }
    return $v
}

################################################################################
# delete recursivally all undefined content references

sub ondef {
    my ($o)=@_;
    #print STDOUT "[ondef]".gparse::str($o)."\n";
    if (ref($o) eq 'HASH') {
        for my $k (keys %{$o}) {
            $o->{$k} //= 'undef';
            if ($k =~ /^\_/) { delete $o->{$k} }
            elsif (ref($o->{$k}) eq 'ARRAY' && $#{$o->{$k}}==-1) { delete $o->{$k} }
            elsif (ref($o->{$k}) eq 'HASH') {
                $o->{$k}=ondef($o->{$k}) // 'undef';
                if (ref($o->{$k}) eq 'HASH' && $#{[keys %{$o->{$k}}]} == -1) { delete $o->{$k} }
            }
            if ($o->{$k} eq 'undef') { delete $o->{$k} }
        }
        if ($#{[keys %{$o}]} == -1) { $o = 'undef' }
    }
    elsif (ref($o) eq 'ARRAY' && $#{$o}>-1) {
        for my $i (0..$#{$o}) { $o->[$i]=ondef($o->[$i]) }
    }
    return $o // 'undef'
}

################################################################################
# Truncate and Flatten Hash Keys
################################################################################

sub merge_hash {
    my ($in1,@in2)=@_;
    for my $i2 ( @in2 ) {
        for my $k (keys %$i2) {
            if ($k !~ /^xmlns/) {
                $in1->{$k}=$i2->{$k}
            }
        }
    }
}

sub flat_hash {
    my ($key,$hash)=@_;
    my $rhash={};
    for my $fkey ( keys %$hash ) { $rhash->{"$key.$fkey"}=flat_value("$key.$fkey",$hash->{$fkey}) }
    return $rhash
}

sub flat_array {
    my ($key,$array)=@_;
    my $rhash={};
    for (my $i=0;$i<=$#{$array};$i++) { $rhash->{"$key.$i"}=flat_value("$key.$i",$array->[$i]) }
    $rhash->{"$key.length"}=1+$#{$array};
    return $rhash
}

sub flat_value {
    my ($key,$value)=@_;
    my $ret={};
    if (ref($value) eq 'HASH') {
        my $fhash=flat_hash($key,$value);
        for my $fkey ( keys %$fhash ) {
            $ret->{"$fkey"}=$fhash->{$fkey};
        }
    }
    elsif (ref($value) eq 'ARRAY') {
        my $fhash = ($#{$value} == 0 ?
            flat_value($key,$value->[0]) : flat_array($key,$value)
        );
        for my $fkey ( keys %$fhash ) {
            $ret->{"$fkey"}=$fhash->{$fkey};
        }
    }
    else {
        return $value
    }
    return $ret
}

sub flat_trunc {
    my ($val)=@_;
    my $truncs=[];
    if (ref($val)) {
        if (ref($val) eq 'HASH') {
            for my $key ( keys %$val ) { 
                my $trunc=flat_trunc($val->{$key});
                if (ref($trunc) eq 'ARRAY') {
                    push @$truncs,@$trunc
                } else {
                    push @$truncs,['value',$key,$val->{$key}]
                }
            }
        }
        elsif (ref($val) eq 'ARRAY') {
            for(my $i=0;$i<=$#{$val};$i++) { 
                my $trunc=flat_trunc($val->[$i]);
                if (ref($trunc) eq 'ARRAY') {
                    push @$truncs,@$trunc
                } else {
                    push @$truncs,['value',$i,$val->[$i]]
                }
            }
        }
        return $truncs
    } else {
        return $val
    }
}

sub flattenvalue {
    my ($key,$value)=@_;
    my $trunced = flat_trunc(flat_value($key,$value));
    my $hash = {}; for my $trunc ( @$trunced ) { $hash->{$trunc->[1]}=$trunc->[2] }
    return $hash
}

sub pack_hash {
    my ($obj)=@_; my $pack={};
    if (ref($obj) eq 'HASH') {
        for my $k (keys %{$obj}) {
            my $f=pack_hash($obj->{$k});
            if (ref($f) eq 'HASH') {
                for my $kk (keys %{$f}) { $pack->{"$k.$kk"}=$f->{$kk} }
            } else {
                $pack->{"$k"}=$f
            }
        }
    }
    elsif (ref($obj) eq 'ARRAY') {
        for (my $i=0; $i <= $#{$obj}; $i++) {
            my $f=pack_hash($obj->[$i]);
            if (ref($f) eq 'HASH') {
                for my $kk (keys %{$f}) { $pack->{"$i.$kk"}=$f->{$kk} }
            } else {
                $pack->{"$i"}=$f
            }
        }
    }
    elsif (!ref($obj)) { $pack = $obj }
    else { $pack = 'null' }
    return $pack
}

################################################################################
# EOF (C) 2019 DOMERO
1