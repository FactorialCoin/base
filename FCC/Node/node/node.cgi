#!/usr/bin/perl

use FCC::node;

do {
  FCC::node::start();
  if (-e 'update.fcc') {
    unlink('update.fcc');
    print "Restarting Node .. "
  } else {
    exit
  }
} until(0)
