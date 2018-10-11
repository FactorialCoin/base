#!/usr/bin/perl

package gsem;

########################################################################
#                                                                      #
#    Gideon Semaphores                                                 #
#                                                                      #
#    (C) 2016 Domero, Groningen, NL                                    #
#                                                                      #
########################################################################

use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.01';
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = ();

use gerr qw(error);

if ($^O =~ /win/i) {
  use if $^O =~ /win/i, Win32::Semaphore
} else {
  use if $^O !~ /win/i, IPC::SysV => qw(SEM_UNDO IPC_CREAT ftok);
  use if $^O !~ /win/i, IPC::Semaphore;
}

my %semlist = ();

1;

sub create {
  my ($name) = @_;
  if ($semlist{$name}) {
    error("GSem.Create: Semaphore '$name' already exists")
  }
  if ($^O =~ /win/i) {
    $semlist{$name}=Win32::Semaphore->new(1,1,$name);
    return
  }
  my $flags = PERMISSIONS;
  my $sem = new IPC::Semaphore(ftok($0, 0), 1, $flags);
  unless($sem) {
    # we must be the first one
    $sem = new IPC::Semaphore($name, 1, $flags | IPC_CREAT);
    $sem->setval(0, 1);
  }
  $semlist{$name}=$sem
}

sub exists {
  my ($name) = @_;
  if (!defined $name) { error("GSem.Exists: No name given for semaphore") }
  if ($semlist{$name}) { return 1 }
  return 0
}

sub wait {
  my ($name,$msec) = @_;
  if (!$msec) { $msec=0 }
  if (!$semlist{$name}) {
    error("GSem.Wait: Semaphore '$name' does not exist")
  }
  if ($^O =~ /win/i) {
    $semlist{$name}->wait($msec); return
  }
  $semlist{$name}->op(0,-1,SEM_UNDO)
}

sub release {
  my ($name) = @_;
  if (!$semlist{$name}) {
    error("GSem.Release: Semaphore '$name' does not exist")
  }
  if ($^O =~/win/i) {
    $semlist{$name}->release(1); return
  }
  $semlist{$name}->op(0,1,SEM_UNDO);
}

# EOF gsem.pm (C) 2016 Domero