#!/usr/bin/perl

package gthreads;

########################################################################
#                                                                      #
#    Gideon Multithreads                                               #
#                                                                      #
#    (C) 2019 Domero, Groningen, NL                                    #
#    ALL RIGHTS RESERVED                                               #
#                                                                      #
########################################################################

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.01';
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = ();

use threads;
use threads::shared;
use gsem;
use Time::HiRes qw(usleep gettimeofday);
use gerr qw(error);

my %gtdata :shared = ();
my %gtactive :shared = ();
my $gtrunning :shared = 0;
my $gtid :shared = 0;

my $MAXTHREADS = 0;

1;

sub start {
  my ($set,$proc,@pars) = @_;
  if (!defined $set) {
    error("GThreads.Start: No set given")
  }
  if (ref($proc) ne 'CODE') {
    error("GThreads.Start: No reference to subroutine given, set = '$set")
  }
  if (!$gtdata{$set}) {
    my %data :shared = ();
    $gtdata{$set}=\%data;
  }
  while ($MAXTHREADS && ($gtrunning >= $MAXTHREADS)) {
    usleep(100)
  }
  $gtid++; my $id=$gtid;
  my $thr=threads->new($proc,$id,@pars);
  $gtactive{$id}=gettimeofday();
  $gtrunning++;
  $thr->detach;
  return $id
}

sub existset {
  my ($set) = @_;
  return defined $gtdata{$set}
}

sub createset {
  my ($set) = @_;
  if (!defined $set) {
    error("GThreads.CreateSet: No set given")
  }
  my %data :shared = ();
  $gtdata{$set}=\%data;
}

sub createarray {
  my ($set,$key) = @_;
  if (!defined $set) {
    error("GThreads.CreateArray: No set given")
  }
  if (!defined $key) {
    error("GThreads.CreateArray: No key given for set '$set'")
  }
  my %data :shared = ();
  $gtdata{$set}=\%data;
  my @arr :shared = ();
  $gtdata{$set}{$key}=\@arr
}

sub createhash {
  my ($set,$key) = @_;
  if (!defined $set) {
    error("GThreads.CreateHash: No set given")
  }
  if (!defined $key) {
    error("GThreads.CreateHash: No key given for set '$set'")
  }
  my %data :shared = ();
  $gtdata{$set}=\%data;
  my %hsh :shared = ();
  $gtdata{$set}{$key}=\%hsh
}

sub done {
  my ($id) = @_;
  if (!defined $id) {
    error("GThreads.Done: No key given for process")
  }
  if (!$gtactive{$id}) {
    error("GThreads.Done: Illegal key given for process")
  }
  my $runtime=gettimeofday()-$gtactive{$id};
  delete $gtactive{$id};
  $gtrunning--;
  return $runtime
}

sub lock {
  my ($set,$key) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.Lock: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.Lock: No key given to lock in set '$set'")
  }
  my $sem="_$set\_$key";
  if (!gsem::exists($sem)) {
    gsem::create($sem)
  }
  gsem::wait($sem)
}

sub unlock {
  my ($set,$key) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.UnLock: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.UnLock: No key given to lock in set '$set'")
  }
  my $sem="_$set\_$key";
  gsem::release($sem)
}

sub write {
  my ($set,$key,$data) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.Write: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.Write: No key given to write data to set '$set'")
  }
  if (ref($data) eq 'SCALAR') { $data=${$data} }
  if (!ref($data)) {
    $gtdata{$set}{$key}=$data;
  } elsif (ref($data) eq 'ARRAY') {
    my @arr :shared = @{$data};
    $gtdata{$set}{$key}=\@arr;
  } elsif (ref($data) eq 'HASH') {
    my %hsh :shared = %{$data};
    $gtdata{$set}{$key}=\%hsh
  }
}

sub read {
  my ($set,$key,$index,$length) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.Read: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.Read: No key defined reading from set '$set'")    
  }
  if (defined $index) {
    if (defined $length) {
      if (ref($gtdata{$set}{$key})) {
        error("GThreads.Read: Not a scalar trying to read a slice on index '$index' with length '$length' in set '$set' with key '$key'")
      }
      my $len=length($gtdata{$set}{$key});
      if ($index+$length>$len) {
        error("GThreads.Read: Trying to take a slice outside range, index=$index, length=$length, size=$len in set '$set' with key '$key'")
      }
      gthreads::lock($set,$key);
      my $dat=substr($gtdata{$set}{$key},$index,$length);
      gthreads::unlock($set,$key);
      return $dat
    } else {
      if (ref($gtdata{$set}{$key}) eq 'ARRAY') {
        if ($index =~ /[^0-9]/) {
          error("GThreads.Read: Index '$index' is not a number, reading key '$key' from set '$set'")
        }
        gthreads::lock($set,$key);
        my $dat=$gtdata{$set}{$key}[$index];
        gthreads::unlock($set,$key);
        return $dat
      }
      elsif (ref($gtdata{$set}{$key}) eq 'HASH') {
        gthreads::lock($set,$key);
        my $dat=$gtdata{$set}{$key}{$index};
        gthreads::unlock($set,$key);
        return $dat
      }
      else {
        error("GThreads.Read: Index given on non array/hash reference or length missing, set='$set', $key='$key', index='$index'")
      }
    }
  }
  return $gtdata{$set}{$key}
}

sub inc {
  my ($set,$key,$data) = @_;
  if (!defined($data) || !$data) { return }
  if (!$gtdata{$set}) {
    error("GThreads.Inc: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.Inc: No key given to write data to set '$set'")
  }
  if (ref($data) eq 'SCALAR') { $data=${$data} }
  if (!ref($data)) {
    if ($data =~ /[^0-9\-]/) {
      error("GThreads.Inc: Data to increment ($data) is not a number, Set = '$set', Key = '$key'")
    }
    gthreads::lock($set,$key);
    if (!defined($gtdata{$set}{$key})) {
      $gtdata{$set}{$key}=$data
    } else {
      $gtdata{$set}{$key}+=$data
    }
    gthreads::unlock($set,$key)
  } else {
    my $rf=ref($data);
    error("GThreads.Inc: Data to increment is not a scalar but of type 'rf', Set = '$set', Key = '$key'")
  }
}

sub append {
  my ($set,$key,$data) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.Append: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.Append: No key given to write data to set '$set'")
  } 
  if (ref($gtdata{$set}{$key})) {
    my $rf=ref($gtdata{$set}{$key});
    error("GThreads.Append: Trying to append data to a '$rf' reference, $set = '$set', key = '$key'")
  }  
  if (ref($data) eq 'SCALAR') { $data=${$data} }
  if (!ref($data)) {
    if (!defined $gtdata{$set}{$key}) {
      $gtdata{$set}{$key}=$data
    } else {
      gthreads::lock($set,$key);
      $gtdata{$set}{$key}.=$data;
      gthreads::unlock($set,$key)
    }
  } else {
    my $rf=ref($data);
    error("GThreads.Append: Data tot append is not a scalar but of type 'rf', Set = '$set', Key = '$key'")
  }
}

sub writeindex {
  my ($set,$key,$index,$data) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.WriteIndex: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.WriteIndex: No key given trying to write data to set '$set'")
  } 
  if (!defined $index) {
    error("GThreads.WriteIndex: No index given trying to write data to key '$key' into set '$set'")
  } 
  if (!defined $gtdata{$set}{$key}) {
    error("GThreads.WriteIndex: No data exists trying to write data to key '$key' with index '$index' into set '$set'")
  }
  if (ref($data)) {
    error("GThreads.WriteIndex: Non-scalar detected in data trying to write data to key '$key' with index '$index' into set '$set'")    
  }
  if (ref($gtdata{$set}{$key}) eq 'ARRAY') {
    gthreads::lock($set,$key);
    $gtdata{$set}{$key}[$index]=$data;
    gthreads::unlock($set,$key);    
  } elsif (ref($gtdata{$set}{$key}) eq 'HASH') {
    gthreads::lock($set,$key);
    $gtdata{$set}{$key}{$index}=$data;
    gthreads::unlock($set,$key);    
  } else {
    error("GThreads.WriteIndex: Not an array or hash reference trying to write data to key '$key' with index '$index' into set '$set'")    
  }
}

sub pushdata {
  my ($set,$key,$data) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.Push: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.Push: No key given trying to write data to set '$set'")
  } 
  if (!defined $gtdata{$set}{$key}) {
    error("GThreads.Push: No data exists trying to push data into key '$key' to set '$set'")
  }
  if (ref($data)) {
    error("GThreads.Push: Non-scalar detected in data trying to push data into key '$key' to set '$set'")    
  }
  if (ref($gtdata{$set}{$key}) ne 'ARRAY') {
    error("GThreads.Push: Not an array-var trying to push data into key '$key' in set '$set'")
  }
  gthreads::lock($set,$key);
  if (ref($data) eq 'ARRAY') {
    push @{$gtdata{$set}{$key}},@{$data}
  } elsif (!ref($data)) {
    push @{$gtdata{$set}{$key}},$data    
  } else {
    gthreads::unlock($set,$key);
    error("GThreads.Push: Not a scalar, or array reference trying to push data into key '$key', in set '$set'")
  }
  gthreads::unlock($set,$key)
}

sub insert {
  my ($set,$key,$index,$data) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.Insert: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.Insert: No key given trying to insert data to set '$set'")
  } 
  if (!defined $index) {
    error("GThreads.Insert: No index given trying to insert data to key '$key' into set '$set'")
  }
  if (!defined $gtdata{$set}{$key}) {
    if ($index>0) {
      error("GThreads.Insert: No data exists trying to insert data to key '$key' into set '$set' on index '$index'")
    }
    if (ref($data) eq 'ARRAY') {
      my @arr :shared = @{$data};
      $gtdata{$set}{$key}=\@arr;
      return
    }
    if (ref($data) eq 'HASH') {
      my %hsh :shared = %{$data};
      $gtdata{$set}{$key}=\%hsh;
      return
    }
    $gtdata{$set}{$key}=$data;
    return
  }
  if (!ref($gtdata{$set}{$key})) {
    if (ref($data)) {
      error("GThreads.Insert: Non-scalar detected in data trying to insert data to key '$key' into set '$set'")    
    }
    my $len=length($gtdata{$set}{$key}); my $dlen=length($data);
    if ($index>$len) {
      error("GThreads.Insert: Trying to insert beyond boundry of data (size=$len, index=$index, datalength=$dlen) in set '$set' to key '$key'")
    }
    gthreads::lock($set,$key);
    if ($index==$len) {
      $gtdata{$set}{$key}.=$data
    } else {
      my $newdata :shared = substr($gtdata{$set}{$key},0,$index);
      $newdata.=$data; $newdata.=substr($gtdata{$set}{$key},$index);
      $gtdata{$set}{$key}=$newdata
    }
    gthreads::unlock($set,$key);
  }
  else {
    if (ref($gtdata{$set}{$key}) ne 'ARRAY') {
      error("GThreads.Insert: Not a scalar or array-var trying to insert data into key '$key' to set '$set'")    
    }
    if (ref($data) && (ref($data) ne 'ARRAY')) {
      my $rf=ref($data);
      error("GThreads.Insert: Data is not a scalar of of reference 'ARRAY', but of ref '$rf', inserting into key '$key' to set '$set'")
    }
    # implement own splice, NOT SUPPORTED in shared vars!
    # splice(@{$gtdata{$set}{$key}},$index,0,$data);
    gthreads::lock($set,$key);
    my $numdat=1+$#{$gtdata{$set}{$key}};
    if ($index>$numdat) {
      error("GThreads.Insert: Index '$index' is outside range. NumData='$numdat'")    
    }
    my @arr :shared = ();
    if ($index>0) {
      push @arr,@{$gtdata{$set}{$key}}[0..$index-1]
    }
    if (ref($data)) {
      push @arr,@{$data}
    } else {
      push @arr,$data
    }
    if ($index<=$numdat-1) {
      push @arr,@{$gtdata{$set}{$key}}[$index..$numdat-1]
    }
    $gtdata{$set}{$key}=\@arr;
    gthreads::unlock($set,$key);
  }
}

sub exists {
  my ($set,$key) = @_;
  if (defined $key) {
    if (defined $gtdata{$set}{$key}) {
      return 1
    }
  } elsif ($gtdata{$set}) {
    return 1
  }
  return 0
}

sub getref {
  my ($set,$key) = @_;
  if (defined($set) && defined($key)) {
    return ref($gtdata{$set}{$key})
  }
  return undef
}

sub numdata {
  my ($set,$key) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.NumData: Set '$set' is unknown")
  }
  if (!defined $key) {
    error("GThreads.NumData: No key given with set '$set'")
  } 
  if (!defined $gtdata{$set}{$key}) {
    error("GThreads.NumData: No data exists, key '$key' set '$set'")
  }
  if (!ref($gtdata{$set}{$key})) {
    gthreads::lock($set,$key);
    my $len=length($gtdata{$set}{$key});
    gthreads::unlock($set,$key);
    return $len
  }
  elsif (ref($gtdata{$set}{$key}) eq 'ARRAY') {
    gthreads::lock($set,$key);
    my $num=1+$#{$gtdata{$set}{$key}};
    gthreads::unlock($set,$key);
    return $num
  } else {
    my @kl=keys %{$gtdata{$set}{$key}};
    gthreads::lock($set,$key);
    my $num=0+@kl;
    gthreads::unlock($set,$key);
    return $num
  }
}

sub del {
  my ($set,$key) = @_;
  if (!$gtdata{$set}) {
    error("GThreads.Del: Set '$set' is unknown")
  }
  if (defined $key) {
    undef $gtdata{$set}{$key}
  }
}

sub show {
  my ($set,$key) = @_;
  if (!defined $set) {
    error("GThreads.Show: No set given to show (key='$key')")
  }
  if (!defined $gtdata{$set}) {
    error("GThreads.Show: Set '$set' is unknown")
  }
  if (defined $key) {
    if (defined $gtdata{$set}{$key}) {
      if (ref($gtdata{$set}{$key}) eq 'ARRAY') {
        print "$set,$key = ".join(", ",@{$gtdata{$set}{$key}})."\n";
      } elsif (ref($gtdata{$set}{$key}) eq 'HASH') {
        print "$set,$key = "; my @out=();
        foreach my $k (keys %{$gtdata{$set}{$key}}) {
          push @out,$k." => ".$gtdata{$set}{$key}{$k}
        }
        print join(", ",@out)."\n"
      } else {
        print "$set,$key = ".$gtdata{$set}{$key}."\n"
      }
    }
  } else {
    foreach my $k (sort keys %{$gtdata{$set}}) {
      gthreads::show($set,$k)
    }    
  }    
}

sub active {
  my ($id) = @_;
  if ($gtactive{$id}) { return 1 }
  return 0
}

sub running {
  return $gtrunning
}

sub quitall {
  my ($proc) = @_;
  my $cr=$gtrunning+1;
  while ($gtrunning>0) {
    if ($proc) {
      if ($cr != $gtrunning) {
        &$proc($gtrunning);
        $cr=$gtrunning
      }  
    }    
    usleep(10000)
  }
}

# EOF gthreads.pm (C) 2019 Chaosje, Domero