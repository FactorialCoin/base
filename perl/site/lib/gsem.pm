#!/usr/bin/perl

package gsem;

########################################################################
#                                                                      #
#    Gideon Semaphores                                                 #
#    Semaphores in Linux & Windows, without compiler issues            #        
#                                                                      #
#    (C) 2016 Domero.nl, Groningen, NL                                 #
#    Email: chaosje@gmail.com                                          #
#                                                                      #
########################################################################

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use threads;
use threads::shared;
use Thread::Semaphore;
use Time::HiRes qw(gettimeofday usleep);
use gerr qw(error);

$VERSION     = '1.01';
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = ();

my %semlist :shared = ();

1;

sub create {
  my ($name) = @_;
  if (!defined $name) { error("GSem.Create: No name given for semaphore") }
  if ($semlist{$name}) {
    error("GSem.Create: Semaphore '$name' already exists")
  }
  $semlist{$name}=Thread::Semaphore->new()
}

sub exists {
  my ($name) = @_;
  if (!defined $name) { error("GSem.Exists: No name given for semaphore") }
  if ($semlist{$name}) { return 1 }
  return 0
}

sub wait {
  my ($name,$usec,$sleep) = @_;
  if (!defined $name) { error("GSem.Wait: No name given for semaphore") }
  if (!defined $usec) { $usec=0 }
  if (!defined $sleep) { $sleep=1000 }
  if (!$semlist{$name}) {
    error("GSem.Wait: Semaphore '$name' does not exist")
  }
  if (!$usec) {
    $semlist{$name}->down(); return
  }
  my $ctm=gettimeofday();
  while ((!$semlist{$name}->down_nb()) && (gettimeofday()-$ctm<$usec)) {
    usleep($sleep)
  }  
}

sub release {
  my ($name) = @_;
  if (!defined $name) { error("GSem.Release: No name given for semaphore") }
  if (!$semlist{$name}) {
    error("GSem.Release: Semaphore '$name' does not exist")
  }
  $semlist{$name}->up();
}

# EOF gsem.pm (C) 2016 Domero.nl