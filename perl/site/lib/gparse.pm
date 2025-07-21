#!/usr/bin/perl

#################################################################
#                                                               #
#    Generic Parsing v1.0.0                                     #
#                                                               #
#    (C) 2008 Gideon Dynamics, Groningen                        #
#    ALL RIGHTS RESERVERD                                       #
#                                                               #
#################################################################
#
#  Methods
#
#    obj(string):object  # str2boj alias; Parse String to Perl Object data
#    str(object):string  # obj2str alias; Parse Perl Object to String data
#
#  Usage:
#
#  my $d=gparse::str2obj($datastring);         # Create Object
#  print $d->{data}
#################################################################
package gparse;
use strict;
#use warnings;
1;
################################################################################
# Create Object-Data from String-Data
# gparse::str2obj($string):$obj;
sub obj { return str2obj(@_) }
sub str2obj { # $data:string, [from-file:debuginfo], [%{$var}:accessable data object in the string evaluation envirement]
  my $data=shift;
  my $file=shift;
  my %import=@_;
  my $var=\%import;
  my $obj=[]; eval("push \@{\$obj},".($data ? $data : 'undef').";");
  if($@) {
#    error::fatal(undef,"gparse::Str2Obj : $@ \nin ".($file ? "file: '$file'; ":"")."data:\n '$data'");
    return undef
  }
  return shift @{$obj}
}
################################################################################

################################################################################
# parse data TO String
# gparse::obj2str($obj):$string;
sub str { return obj2str(@_) }
sub obj2str { # $@%object:direct printable perl evaluation object string.
  my $obj=shift;
  my $lev=shift; if(defined $lev){ $lev>>=0 } else { $lev=0 }
  my $maxlev=shift; if(defined $maxlev){ $maxlev>>=0 } else { $maxlev=0 }
  my $noclass=shift; if(defined $noclass){ $noclass>>=0 } else { $noclass=0 }
  if(!defined $obj){ return 'undef' }
  my @r=();
  my $isarrayclass=(ref($obj) ne "ARRAY" && "$obj" =~ /^.+\=ARRAY\(.+\)$/ ? ref($obj):''); 
  my $ishashclass=(ref($obj) ne "HASH" && "$obj" =~ /^.+\=HASH\(.+\)$/ ? ref($obj):'');
#  if($ishashclass){ $obj->{__PACKAGE__}=ref($obj) }
  if(
    (!$noclass || (!$isarrayclass && !$ishashclass)) &&
    (!$maxlev || ($maxlev && $lev ne $maxlev))
  ){
    # Array || Package
    if(ref($obj) eq "ARRAY" || $isarrayclass){
      foreach my $a ( @{$obj} ){ push @r,obj2str($a,$lev+1,$maxlev,1) }
      return "[".join(",",@r)."]";
    }
    # Hash || Package
    elsif(ref($obj) eq "HASH" || ref($obj) eq "REF" || $ishashclass){
      foreach my $k ( sort { lc($a) cmp lc($b) } @{[keys %{$obj}]} ){ push @r,'"'.quotemeta($k).'"=>'.obj2str($obj->{$k},$lev+1,$maxlev,1) }
      return "{".(0+@r ? "\n".("  "x($lev+1)) . join(",\n".("  "x($lev+1)),@r) . "\n".("  "x($lev)):'')."}";
    }
    # Scaler Ref
    elsif(ref($obj) eq "SCALAR"){
      return obj2str(${$obj},$lev+1,$maxlev,1);
    }
    # Code Ref
    elsif(ref($obj) eq "CODE"){
    }
    # Global Ref
    elsif(ref($obj) eq "GLOB"){
    }
    # Integer
    elsif(defined $obj && $obj ne "" && int($obj) eq $obj){
      return $obj
    }
    # (Long)Real
    elsif(realv($obj)){
      return "$obj"
    }
  }
  # String
  my $string=quotemeta($obj);
  $string =~ s/\x{001B}/e/g;
  $string =~ s/\x{00}/00/g;
  $string =~ s/\x{1B}/esc/g;
  $string =~ s/\[([^m]+)m/[$1]m/g;
  $string =~ s/\\\n/\n/g;
  $string =~ s/\\\s/ /g;
  $string =~ s/\\\=/=/g;
  $string =~ s/\\\:/:/g;
  $string =~ s/\\\&/&/g;
  $string =~ s/\\\%/%/g;
  $string =~ s|\\\/|/|g;
  $string =~ s|\\\.|.|g;
  $string =~ s|\\\;|;|g;
  $string =~ s/\\\-/-/g; $string =~ s/\\\+/+/g;
  $string =~ s/\\\#/#/g;
  $string =~ s/\\\(/(/g; $string =~ s/\\\)/)/g;
  $string =~ s/\\\[/[/g; $string =~ s/\\\]/]/g;
  if($ishashclass){ $string =~ s/\(.+\)$// }
  return '"'.$string.'"'
}


################################################################################
# parse data TO PHP
sub php { return obj2php(@_) }
sub obj2php { # $@%object:direct printable perl evaluation object string.
  my $obj=shift;
  my $lev=shift>>0;
  my $maxlev=shift>>0;
  my $noclass=shift>>0;
  if(!defined $obj){ return 'undef' }
  my @r=();
  my $isarrayclass=(ref($obj) ne "ARRAY" && "$obj" =~ /^.+\=ARRAY\(.+\)$/ ? ref($obj):''); 
  my $ishashclass=(ref($obj) ne "HASH" && "$obj" =~ /^.+\=HASH\(.+\)$/ ? ref($obj):'');
#  if($ishashclass){ $obj->{__PACKAGE__}=ref($obj) }
  if(
    (!$noclass || (!$isarrayclass && !$ishashclass)) &&
    (!$maxlev || ($maxlev && $lev ne $maxlev))
  ){
    # Array || Package
    if(ref($obj) eq "ARRAY" || $isarrayclass){
      foreach my $a ( @{$obj} ){ push @r,obj2php($a,$lev+1,$maxlev,1) }
      return "Array(".join(",",@r).")";
    }
    # Hash || Package
    elsif(ref($obj) eq "HASH" || ref($obj) eq "REF" || $ishashclass){
      foreach my $k ( sort { lc($a) cmp lc($b) } @{[keys %{$obj}]} ){ push @r,'"'.quotemeta($k).'"=>'.obj2php($obj->{$k},$lev+1,$maxlev,1) }
      return "Array(".(0+@r ? "\n".("  "x($lev+1)) . join(",\n".("  "x($lev+1)),@r) . "\n".("  "x($lev)):'').")";
    }
    # Scaler Ref
    elsif(ref($obj) eq "SCALAR"){
      return obj2php(${$obj},$lev+1,$maxlev,1);
    }
    # Code Ref
    elsif(ref($obj) eq "CODE"){
    }
    # Global Ref
    elsif(ref($obj) eq "GLOB"){
    }
    # Integer
    elsif(defined $obj && $obj ne "" && int($obj) eq $obj){
      return $obj
    }
    # (Long)Real
    elsif(realv($obj)){
      return "$obj"
    }
  }
  # String
  my $string=quotemeta($obj);
  $string =~ s/\\\n/\n/g;
  $string =~ s/\\\s/ /g;
  $string =~ s/\\\=/=/g;
  $string =~ s/\\\:/:/g;
  $string =~ s/\\\&/&/g;
  $string =~ s/\\\%/%/g;
  $string =~ s|\\\/|/|g;
  $string =~ s|\\\.|.|g;
  $string =~ s|\\\;|;|g;
  $string =~ s/\\\-/-/g; $string =~ s/\\\+/+/g;
  $string =~ s/\\\#/#/g;
  $string =~ s/\\\(/(/g; $string =~ s/\\\)/)/g;
  $string =~ s/\\\[/[/g; $string =~ s/\\\]/]/g;
  if($ishashclass){ $string =~ s/\(.+\)$// }
  return '"'.$string.'"'
}


################################################################################
# parse data TO Javascript
# gparse::obj2str($obj):$string;
sub js { return obj2js(@_) }
################################################################################
sub obj2js {# $@%object:direct printable javascript evaluation object string.
  my $obj=shift;
  my $lev=shift>>0;
  my $maxlev=shift>>0;
  my $noclass=shift>>0;
  if(!defined $obj){ return 'undef' }
  my @r=();
  my $isarrayclass=(ref($obj) ne "ARRAY" && "$obj" =~ /^.+\=ARRAY\(.+\)$/ ? ref($obj):''); 
  my $ishashclass=(ref($obj) ne "HASH" && "$obj" =~ /^.+\=HASH\(.+\)$/ ? ref($obj):'');
#  if($ishashclass){ $obj->{__PACKAGE__}=ref($obj) }
  if(
    (!$noclass || (!$isarrayclass && !$ishashclass)) &&
    (!$maxlev || ($maxlev && $lev ne $maxlev))
  ){
    # Array || Package
    if(ref($obj) eq "ARRAY" || $isarrayclass){
      foreach my $a ( @{$obj} ){ push @r,obj2str($a,$lev+1,$maxlev,1) }
      return "[".join(",",@r)."]";
    }
    # Hash || Package
    elsif(ref($obj) eq "HASH" || ref($obj) eq "REF" || $ishashclass){
      foreach my $k ( sort { lc($a) cmp lc($b) } @{[keys %{$obj}]} ){ push @r,'"'.quotemeta($k).'":'.obj2str($obj->{$k},$lev+1,$maxlev,1) }
      return "{".(0+@r ? "\n".("  "x($lev+1)) . join(",\n".("  "x($lev+1)),@r) . "\n".("  "x($lev)):'')."}";
    }
    # Scaler Ref
    elsif(ref($obj) eq "SCALAR"){
      return obj2str(${$obj},$lev+1,$maxlev,1);
    }
    # Code Ref
    elsif(ref($obj) eq "CODE"){
    }
    # Global Ref
    elsif(ref($obj) eq "GLOB"){
    }
    # Integer
    elsif(defined $obj && $obj ne "" && int($obj) eq $obj){
      return $obj
    }
    # (Long)Real
    elsif(realv($obj)){
      return "$obj"
    }
  }
  # String
  my $string=quotemeta($obj);
  $string =~ s/\\\n/\n/g;
  $string =~ s/\\\s/ /g;
  $string =~ s/\\\=/=/g;
  $string =~ s/\\\:/:/g;
  $string =~ s/\\\&/&/g;
  $string =~ s/\\\%/%/g;
  $string =~ s|\\\/|/|g;
  $string =~ s|\\\.|.|g;
  $string =~ s|\\\;|;|g;
  $string =~ s/\\\-/-/g; $string =~ s/\\\+/+/g;
  $string =~ s/\\\#/#/g;
  $string =~ s/\\\(/(/g; $string =~ s/\\\)/)/g;
  $string =~ s/\\\[/[/g; $string =~ s/\\\]/]/g;
  if($ishashclass){ $string =~ s/\(.+\)$// }
  return '"'.$string.'"'
}
################################################################################
sub js2obj {
  my($r,$v)=@_;
  my $q='"';
  my $Q='_q_';
  $r =~ s/$q\:\s$q/$q: $Q/gs;
  $r =~ s/$q([^\"]+)$q\:/$Q$1$Q:/gsi;
  $r =~ s/$q\,(\s*)$Q/$Q,$1$Q/gs;
#  print $r."\n";
  $r =~ s/$q\}/$Q}/gs;
  $r =~ s/([^\\])$q/$1\\$q/gs;
  $r =~ s/([^\\])$q/$1\\$q/gs;
  $r =~ s/$Q/$q/gs;
  $r =~ s/$q\:/$q=>/gsi;
  if($v){ print $r."\n"; }
  eval("\$r=$r;");
  return $r
}
################################################################################

## Real Valid ? # -+0.9(e-+09) == 1
sub realv {
  my $r=shift;
  $r.='';
  if($r =~ /^([\-\+]{1}?[0-9\.]+)[e]{1}?([\-\+]{1}?[0-9\.]+?)$/i ){
    my ($e,$f,$b,@n)=($2,split(/\./,$1));
    if(0+@n){ return 0 };
    if($e){ return ( (int($f) eq $f) && (int($b) eq $b) && (int($e) eq $e) ) }
    return ( (int($f) eq $f) && (int($b) eq $b) )
  }
  return 0
}
################################################################################
