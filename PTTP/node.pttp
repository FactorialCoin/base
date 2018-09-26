#!/usr/bin/perl

use FCC::node;
use gserv qw(localip);

do {
  my $local=0; if (localip() =~/^192.168/) { $local=1 }
  FCC::node::start('PTTP',undef,0,$local);
  if (-e 'update.pttp') {
    unlink('update.pttp');
    print "Restarting Node .. "
  } else {
    exit
  }
} until(0)

