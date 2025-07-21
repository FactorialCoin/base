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

$VERSION     = '2.1.6';
@ISA         = qw(Exporter);
@EXPORT      = qw($WALLETEXISTS $WALLETDIR
                  publichash validatehash 
                  validwallet validwalletpassword
                  createwalletaddress
                  walletexists walletisencoded 
                  loadwallet loadwallets 
                  newwallet 
                  savewallet savewallets);
@EXPORT_OK   = qw();

use gfio 1.11;
use gerr 1.02;
use Crypt::Ed25519;
use glib;
use FCC::global 2.2.1;

our $WALLETDIR=".";
our $WALLETEXISTS=&findwallet();

my @WXOR = ();
createtable();

1;

# Get Wallet Object Address Public Hash
sub publichash {
  my ($wallet) = @_;
  if (ref($wallet) eq "FCC::wallet") { $wallet=$wallet->{wallet} }
  if (validwallet($wallet)) { return substr($wallet,2,64) }
  return ""
}

# Validate Wallet Public Key
sub validatehash {
  my ($wid,$pubkey) = @_;
  if (createwalletaddress($pubkey) eq $wid) {
    return 1
  }
  return 0
}

# Wallet Address structure
#
# offset length  content
#      0      2  '51' - FCC identifier (11 for PTTP)
#      2     64  Public hashkey
#     66      2  Checksum, xor ascii values 0-65 must be 0
#
# Wallet will be converted to uppercase always!

# Validate Wallet Address
sub validwallet {
  my ($wallet) = @_;

  # Atleast give a wallet Address
  if (!$wallet) { return 0 }

  # Always Uppercase
  $wallet=uc($wallet);

  # Incorrect Wallet Address Length
  if (length($wallet) != 68) { return 0 }

  # Coin identifier
  my $xor;
  if ($COIN eq 'PTTP') {
    $xor=ord('1') ^ ord('1');
    if (substr($wallet,0,2) ne '11') { return 0 }
  }
  else {
    $xor=ord('5') ^ ord('1'); # Default FCC
    if (substr($wallet,0,2) ne '51') { return 0 }
  }

  # Address Checksum
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

# Validate Password from Wallet File
sub validwalletpassword {
  my ($password) = @_;
  if (-e "$WALLETDIR/wallet$FCCEXT") {
    my $winfo=dec_json(gfio::content("$WALLETDIR/wallet$FCCEXT"));
    if (ref($winfo) eq 'HASH') {
      if ($winfo->{encoded}) { return validwalletseed($winfo->{encoded},$password) }
    }
  }
  return 1
}

# Wallet Address Checksum Table
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

# Create Wallet Address from Public Key
sub createwalletaddress {
  my ($pubkey) = @_;
  my $pubhash = securehash($pubkey);

  # Identifier
  my $xor = ord('5') ^ ord('1'); # Default FCC
  if ($COIN eq 'PTTP') { $xor=ord('1') ^ ord('1') }

  # PubHash
  for (my $c=0;$c<64;$c++) {
    $xor ^= ord(substr($pubhash,$c,1)); 
  }

  # Checksum
  my $checksum="";
  foreach my $try (@WXOR) {
    if (($try->{value} ^ $xor) == 0) {
      $checksum=$try->{add}; last
    }
  }

  # Wallet Address
  return ($COIN eq 'PTTP' ? '11' : '51').$pubhash.$checksum;
}

# Check if Wallet File Exists on Disk
sub walletexists {
  return (-e "$WALLETDIR/wallet$FCCEXT")
}

# Check if Wallet File is Encrypted
sub walletisencoded {
  if (-e "$WALLETDIR/wallet$FCCEXT") {
    my $winfo=dec_json(gfio::content("$WALLETDIR/wallet$FCCEXT"));
    if (ref($winfo) eq 'HASH') {
      if ($winfo->{encoded}) { return 1 }
    }
  }
  return 0
}

# Load Wallet from File
sub loadwallet {
  my ($wkey,$password) = @_;
  if (defined $wkey) { $wkey=uc($wkey) }
  my $wlist=loadwallets($password);

  # Error
  if (($#{$wlist}==0) && ($wlist->[0]{error})) { return $wlist->[0] }

  # First
  if (!$wkey && ($#{$wlist}>=0)) { return $wlist->[0] }

  # Validated Searched
  elsif (validwallet($wkey)) {
    foreach my $wallet (@$wlist) { return $wallet if ($wallet->{wallet} eq $wkey) }
  }

  # Undefined Wallet
  return undef
}

# Load Wallets from File
sub loadwallets {
  my ($password) = @_;
  my $wlist=[];
  print "Looking for wallet at $WALLETDIR/wallet$FCCEXT\n";
  if (-e "$WALLETDIR/wallet$FCCEXT") {
    
    my $winfo=dec_json(gfio::content("$WALLETDIR/wallet$FCCEXT"));

    # wallet v2+
    if (ref($winfo) eq 'HASH') {
      if ($winfo->{encoded}) {
        if (!validwalletseed($winfo->{encoded},$password)) {
          return [ { error => 'invalid password' } ]
        }
      }
      $wlist = $winfo->{wlist};
      foreach my $wallet (@$wlist) {
        bless($wallet);
        if (!$wallet->{name}) { $wallet->{name}="[ No name ]" }
        if ($winfo->{encoded} && $wallet->{wallet}) {
          $wallet->{pubkey}=cryptwallet($wallet->{pubkey},$password);
          $wallet->{privkey}=cryptwallet($wallet->{privkey},$password);
        }
      }
    }

    # wallet v1      
    elsif (ref($winfo) eq 'ARRAY') {
      foreach my $wallet (@$winfo) {
        bless($wallet);
        if (!$wallet->{name}) { $wallet->{name}="[ No name ]" }
        push @$wlist, $wallet
      }
    }

  }
  return $wlist
}

# Create new Wallet Object Class 
# my $wallet=newwallet('New Wallet Name');
sub newwallet {
  my ($name) = @_;
  if (!$name) { $name = "[ No name ]" }
  my ($pubkey, $privkey) = Crypt::Ed25519::generate_keypair;
  my $pubhex = octhex($pubkey);
  my $wallet = {
    pubkey => $pubhex,
    privkey => octhex($privkey),
    wallet => createwalletaddress($pubhex),
    name => $name
  };
  bless($wallet); return $wallet
}

# Add New Wallet to Wallets File
# $wallet->savewallet();
sub savewallet {
  my ($wallet,$password) = @_;
  # Used on Wallet Object Class
  if (ref($wallet) ne "FCC::wallet") { error "FCC::wallet->savewallet - Wallet given is not a blessed wallet" }

  # Load from File
  my $wlist=loadwallets($password);
  # Loading Error
  if (($#{$wlist}==0) && ($wlist->[0]{error})) {
    error("FCC::wallet->savewallet - Adding wallet with wrong password")
  }
  # Add to wlist
  push @{$wlist},$wallet;

  # Save to File
  savewallets($wlist,$password)
}

# Save to Wallets File
# will overwrite password, be careful
sub savewallets {
  my ($wlist,$password) = @_;
  # Get encoded from given password
  my $enc = $password ? createwalletseed($password) : "";
  # Collect Wallet List
  my $wcl = []; 
  foreach my $w (@$wlist) {
    # 2.1 Default Wallet
    my $wallet = {name => $w->{name}||""};
    if (defined $w->{wallet}) { 
      $wallet->{wallet} = $w->{wallet};
      $wallet->{pubkey} = cryptwallet($w->{pubkey},$password);
      $wallet->{privkey} = cryptwallet($w->{privkey},$password);
    }
    # 2.2 Contacts Addon
    if (defined $w->{contact}){ 
      $wallet->{contact} = $w->{contact} 
    }
    push @$wcl,$wallet
  }
  gfio::create("$WALLETDIR/wallet$FCCEXT",encode_json_pretty({ encoded => $enc, version => '2.2', wlist => $wcl }))
}

# Internal Helpers

# Find the wallet file
sub findwallet {
  # Current Dir
  if (!-f "$WALLETDIR/wallet$FCCEXT") {
    # Sub Dir
    if (-f "$WALLETDIR/wallet/wallet$FCCEXT") {  $WALLETDIR = "$WALLETDIR/wallet" }
    elsif (-d "$WALLETDIR/wallet") {  $WALLETDIR = "$WALLETDIR/wallet" }
    # Parent Dir
    elsif (-f "../wallet$FCCEXT") {  $WALLETDIR = ".." }
    # Parent Sub Dir
    elsif (-f "../wallet/wallet$FCCEXT") { $WALLETDIR = "../wallet" }
    elsif (-d "../wallet") {  $WALLETDIR = "../wallet" }
  }
  return (-e "$WALLETDIR/wallet$FCCEXT")
}

# Encrypt/Decrypt data with password
sub cryptwallet {
  my ($data,$password)=@_;
  return $password ? fccencode(hexoct($data),$password) : $data
}

# Create Wallet Encryption Security Seed and Hash
# - On every Save This Wallet Seed and Hash will change (savewallets)
sub createwalletseed {
  my ($password)=@_;
  my $seed = "";
  for (my $i=0;$i<8;$i++) { $seed .= hexchar(int rand(16)) }
  return $seed . securehash($seed.$COIN.$password)
}

# Validate the Wallet Seed and Hash with the Password
sub validwalletseed {
  my ($encoded,$password)=@_;
  return substr($encoded,8) eq securehash(substr($encoded,0,8).$COIN.$password)
}

# EOF FCC::wallet (C) 2018 Domero