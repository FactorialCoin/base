#!/usr/bin/perl

package FCC::wallet;

#######################################
#                                     #
#     FCC Wallet                      #
#                                     #
#    (C) 2019 Domero                  #
#                                     #
#######################################

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '2.1.4';
@ISA         = qw(Exporter);
@EXPORT      = qw($WALLETEXISTS $WALLETDIR
                  publichash validatehash createwalletaddress walletexists walletisencoded validwalletpassword
                  newwallet validwallet loadwallet loadwallets savewallet savewallets);
@EXPORT_OK   = qw();

use gfio 1.11;
use gerr 1.02;
use Crypt::Ed25519;
use JSON qw(decode_json encode_json);
use FCC::global 2.3.1;

our $WALLETDIR=".";
our $WALLETEXISTS=&findwallet();

my @WXOR = ();
createtable();

1;

# Wallet structure
#
# offset length  content
#      0      2  '51' - FCC identifier (11 for PTTP)
#      2     64  Public hashkey
#     66      2  Checksum, xor ascii values 0-65 must be 0
#
# Wallet will be converted to uppercase always!

sub createtable {
  my @l=();
  for (my $c=0; $c<10; $c++) { push @l,ord($c) }
  for (my $c='A'; $c le 'F'; $c++) { push @l,ord($c) }
  foreach my $m (@l) {
    foreach my $n (@l) {
      push @WXOR,{ add => chr($m).chr($n), value => $m ^ $n };
    }
  }
}

sub findwallet {
  if (!-f "$WALLETDIR/wallet$FCCEXT") {
    if (-f "./wallet/wallet$FCCEXT") {  $WALLETDIR="./wallet" }
    elsif (-f "../wallet$FCCEXT") {  $WALLETDIR=".." }
    elsif (-f "../wallet/wallet$FCCEXT") { $WALLETDIR="../wallet" }
    elsif (-d "../wallet") {  $WALLETDIR="../wallet" }
    elsif (-d "./wallet") {  $WALLETDIR="./wallet" }
  }
  return (-e "$WALLETDIR/wallet$FCCEXT")
}

sub publichash {
  my ($wallet) = @_;
  if (ref($wallet) eq "FCC::wallet") { $wallet=$wallet->{wallet} }
  if (validwallet($wallet)) {
    return substr($wallet,2,64)
  }
  return ""
}

sub validatehash {
  my ($wid,$pubkey) = @_;
  if (createwalletaddress($pubkey) eq $wid) {
    return 1
  }
  return 0
}

sub createwalletaddress {
  my ($pubkey) = @_;
  my $pubhash=securehash($pubkey);
  my $xor=ord('5') ^ ord('1'); # 4
  if ($COIN eq 'PTTP') {
    $xor=ord('1') ^ ord('1');
  }
  for (my $c=0;$c<64;$c++) {
    $xor ^= ord(substr($pubhash,$c,1)); 
  }
  my $checksum="";
  foreach my $try (@WXOR) {
    if (($try->{value} ^ $xor) == 0) {
      $checksum=$try->{add}; last
    }
  }
  if ($COIN eq 'PTTP') {
    return '11'.$pubhash.$checksum;
  } else {
    return '51'.$pubhash.$checksum;
  }
}

sub newwallet {
  my ($name) = @_;
  if (!$name) { $name = "[ No name ]" }
  my ($pubkey, $privkey) = Crypt::Ed25519::generate_keypair;
  my $pubhex=octhex($pubkey);
  my $wallet = {
    pubkey => $pubhex,
    privkey => octhex($privkey),
    wallet => createwalletaddress($pubhex),
    name => $name
  };
  bless($wallet); return $wallet
}

sub validwallet {
  my ($wallet) = @_;  
  if (!$wallet) { return 0 }
  $wallet=uc($wallet);
  if (length($wallet) != 68) { return 0 }
  my $xor=ord('5') ^ ord('1'); # 4  
  if ($COIN eq 'PTTP') {
    $xor=ord('1') ^ ord('1');
    if (substr($wallet,0,2) ne '11') { return 0 }
  } else {
    if (substr($wallet,0,2) ne '51') { return 0 }
  }
  for (my $c=2;$c<68;$c++) {
    my $h=substr($wallet,$c,1);
    if ((($h ge '0') && ($h le '9')) || (($h ge 'A') && ($h le 'F'))) {
      $xor ^= ord($h)
    } else {
      return 0
    }
  }
  if ($xor != 0) { return 0 }
  return 1
}

sub walletexists {
  return (-e "$WALLETDIR/wallet$FCCEXT")
}

sub walletisencoded {
  if (-e "$WALLETDIR/wallet$FCCEXT") {
    my $winfo=decode_json(gfio::content("$WALLETDIR/wallet$FCCEXT"));
    if (ref($winfo) eq 'HASH') {
      if ($winfo->{encoded}) { return 1 }
    }
  }
  return 0
}

sub loadwallets {
  my ($password) = @_;
  my $wlist=[];
  if (-e "$WALLETDIR/wallet$FCCEXT") {
    my $winfo=decode_json(gfio::content("$WALLETDIR/wallet$FCCEXT"));
    if (ref($winfo) eq 'HASH') {
      # wallet v2+
      if ($winfo->{encoded}) {
        my $seed=substr($winfo->{encoded},0,8);
        my $hash=substr($winfo->{encoded},8);
        my $phash=securehash($seed.$COIN.$password);
        if ($phash ne $hash) { return [ { error => 'invalid password' } ] }
      }
      $wlist=$winfo->{wlist};
      foreach my $wallet (@$wlist) {
        bless($wallet);
        if (!$wallet->{name}) { $wallet->{name}="[ No name ]" }
        if ($winfo->{encoded}) {
          $wallet->{pubkey}=fccencode(hexoct($wallet->{pubkey}),$password);
          $wallet->{privkey}=fccencode(hexoct($wallet->{privkey}),$password);
        }
      }
    } else {
      # wallet v1      
      foreach my $wallet (@$wlist) {
        if (!$wallet->{name}) { $wallet->{name}="[ No name ]" }
      }
      $wlist=$winfo
    }
  }
  return $wlist
}

sub savewallet {
  my ($wallet,$password) = @_;
  if (ref($wallet) ne "FCC::wallet") { error "FCC::wallet::savewallet - Wallet given is not a FCC blessed wallet" }
  my $wlist=loadwallets($password);
  if (($#{$wlist}==0) && ($wlist->[0]{error})) {
    error("FCC::wallet::savewallet - Adding wallet with wrong password")
  }
  push @{$wlist},$wallet;
  savewallets($wlist,$password)
}

sub savewallets {
  my ($wlist,$password) = @_;
  # will overwrite password, be careful
  my $enc="";
  if ($password) {
    my $seed=""; for (my $i=0;$i<8;$i++) { $seed.=hexchar(int rand(16)) }
    $enc=$seed.securehash($seed.$COIN.$password)
  }
  my $wcl=[]; 
  foreach my $w (@$wlist) {
    my $pub=$w->{pubkey}; my $priv=$w->{privkey};
    my $name=$w->{name}; if (!$w->{name}) { $name="" }
    if ($password) {
      $pub=fccencode(hexoct($pub),$password);
      $priv=fccencode(hexoct($priv),$password);
    }
    push @$wcl,{ wallet => $w->{wallet}, name => $name, pubkey => $pub, privkey => $priv }
  }
  gfio::create("$WALLETDIR/wallet$FCCEXT",encode_json({ encoded => $enc, version => '2.1', wlist => $wcl }))
}

sub loadwallet {
  my ($wkey,$password) = @_;
  if (defined $wkey) { $wkey=uc($wkey) }
  my $wlist=loadwallets($password);
  if (($#{$wlist}==0) && ($wlist->[0]{error})) { return $wlist->[0] }
  if (validwallet($wkey)) {
    foreach my $wallet (@$wlist) {
      if ($wallet->{wallet} eq $wkey) { return $wallet }
    }
  } elsif (!$wkey && ($#{$wlist}>=0)) {
    my $wallet=$wlist->[0]; return $wallet
  }
  return undef
}

sub validwalletpassword {
  my ($password) = @_;
  if (-e "$WALLETDIR/wallet$FCCEXT") {
    my $winfo=decode_json(gfio::content("$WALLETDIR/wallet$FCCEXT"));
    if (ref($winfo) eq 'HASH') {
      if ($winfo->{encoded}) {
        my $seed=substr($winfo->{encoded},0,8);
        my $hash=substr($winfo->{encoded},8);
        my $phash=securehash($seed.$COIN.$password);
        return ($phash eq $hash)
      }
    }
  }
  return 1
}

# EOF FCC::wallet (C) 2018 Domero