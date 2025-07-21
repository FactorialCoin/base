#!/usr/bin/perl

 #############################################################################
 #                                                                           #
 #   Eureka File System                                                      #
 #   (C) 2017 Domero, Groningen, NL                                          #
 #   ALL RIGHTS RESERVED                                                     #
 #                                                                           #
 #############################################################################

# Exported
#
# $handle=newfile(filename,content,[no_read])
#  * creates a file with content, and returns the handle for further processing.
# $handle=open(filename,[r|w|a])
#  * append will overrule write, use write or append to create
# $handle->close
#  * unlocks, flushes and closes a file
# $position=$handle->tell
#  * returns the current position to write to or read from in a file
# $handle->seek($position)
#  * jumps to position in a file, position may not be larger than filesize
# $length=$handle->filesize
#  * returns the length in bytes of a file.
# $handle->truncate(length)
#  * if the size of a file is larger than length, will truncate the file to length, and apply changes to size and position if necessary.
# $data=$handle->read(length,stopatend)
#  * returns length bytes read from a file.
# $datapointer=$handle->readptr(length)
#  * returns a SCALAR-reference to length bytes read from a file.
# $handle->write(data)
#  * writes data to a file. data may be a SCALAR-reference.
# $handle->insert(data,[append])
#  * inserts data into a file at the current position, and increases the filesize accordingly. data may be a SCALAR-reference. 
#  * if append is set, the data will be appended in stead of inserted.
# $handle->appenddata(data)
#  * Appends data to the end of the open file-handle (for closed files use append).
# $handle->extract(length)
#  * removes length bytes from a file at the current position and truncates the file. returns the extracted data.
# $handle->lock
#  * exclusively increases the lock on a file.
# $handle->unlock
#  * decreases a lock on a file, if no locks remain, will unlock the file. Always use the same number of locks and unlocks!
#
# closeall
#  * closes all cureently open files
# makedir(dirname,[mode])
#  * default mode = 0700 (rwx)
# create(filename,[content],[not_empty],[mode])
#  * creates a file with content. if not_empty is set, will not create empty files. default mode = 0600 (rw)
# changeowner(filename,user,group)
#  * changes ownership of a file
# content(filename,[offset],[length])
#  * returns the content of a file, or a part of it, without it staying opened.
# append(file,content)
#  * appends content to file.
# crapp(file,content,nonil,mode)
#  * if file exists, appends content to file, otherwise create file.
# copy(source_filename,destination_filename,[no_overwrite])
#  * copies a file, will not overwrite is flag is set.
# $handle=readfiles(directory,extlist,recursive,verbose)
#  * read all files in a directory. extlist may be "ext,ext,..", empty or '*'.
# $handle=readdirs(directory,recursive,verbose)
#  * reads a directory-tree.
# total=$handle->numfiles
#  * returns the number of files read by readfiles or readdirs.
# \%infohash=$handle->getfile(number)
#  * returns information on file number read by readfiles or readdirs, number must be between 1 and $handle->numfiles.
#    The list contains (hash): barename, ext, name, dir, fullname, level, mode, size, atime, mtime, ctime

package gfio;

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.12';
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(open close seek tell read write insert extract readlines filesize truncate create crapp newfile lock unlock locked changeowner content append copy makedir closeall readfiles readdirs numfiles getfile);

use Fcntl qw (:DEFAULT :flock);
use gerr qw(error);

my %OPENED=();

1;

sub open {
  my ($file,$mode) = @_;
  my $self = {}; bless $self;
  $self->{file}=$file;
  $self->{openmode}=$mode;
  $self->{read}=0; if (!defined $mode || ($mode =~ /r/i)) { $self->{read}=1 }
  $self->{write}=0; if (defined $mode && $mode =~ /w/i) { $self->{write}=1 }
  $self->{append}=0; if (defined $mode && $mode =~ /a/i) { $self->{append}=1 }
  if (!-e $file) {
    if (!$self->{write} && !$self->{append}) {
      error("GFIO.Open: File '$file' does not exist")
    } else {
      $self->makepath;
      if ($self->{read}) {
        sysopen($self->{handle},$file,O_CREAT | O_RDWR | O_BINARY)
      } else {
        sysopen($self->{handle},$file,O_CREAT | O_WRONLY | O_BINARY)
      }
    }
  } else {
    if (!-f $file) {
      if (-d $file) {
        error("GFIO.Open: Cannot overwrite directory '$file' as a file")
      } elsif (-s $file) {
        error("GFIO.Open: Cannot overwrite symlink '$file' as a file")       
      } else {
        error("GFIO.Open: Cannot overwrite '$file' as a file")
      }
    }
  }
  if ($self->{append}) {
    if ($self->{read}) {
      sysopen($self->{handle},$file,O_APPEND | O_RDWR  | O_BINARY) || error("GFIO.Open: Cannot open '$file' in mode 'ar': $!")
    } else {
      sysopen($self->{handle},$file,O_APPEND | O_WRONLY | O_BINARY) || error("GFIO.Open: Cannot open '$file' in mode 'a': $!")
    }
  } elsif ($self->{write}) {                                                                                      
    if ($self->{read}) {
      sysopen($self->{handle},$file,O_RDWR | O_BINARY) || error("GFIO.Open: Cannot open '$file' in mode 'rw': $!")
    } else {
      sysopen($self->{handle},$file,O_WRONLY | O_BINARY) || error("GFIO.Open: Cannot open '$file' in mode 'w': $!")
    }
  } else {
    sysopen($self->{handle},$file,O_RDONLY | O_BINARY) || error("GFIO.Open: Cannot open '$file' in mode 'r': $!")
  }
  my @st=stat($self->{file}); $self->{size}=$st[7];
  if ($self->{append}) {
    $self->{position}=$self->{size}
  } else {
    $self->{position}=0
  }
  $self->{opened}=1;
  $self->{locked}=0;
  $OPENED{$file}=$self;
  return $self    
}

sub closeall {
  foreach my $file (keys %OPENED) { $OPENED{$file}->close }
}

sub makepath {
  my ($self) = @_;
  my @dir=split(/\//,$self->{file}); pop @dir;
  my $path="";
  foreach my $d (@dir) {
    $path.=$d;
    if ($path ne "" && $path ne '.' && $path ne '..' && !-e $path) {
      mkdir($path,0700)
    }
    $path.="/"
  }
}

sub filesize {
  my ($self) = @_; return $self->{size}
}
 
sub makedir {
  my ($newdir,$mode) = @_;
  if (!$newdir) { return }
  if(!$mode){ $mode=0700 }
  my @dir=split(/\//,$newdir);
  my $path="";
  foreach my $d (@dir) {
    $path.=$d;
    if ($path && ($path ne '.') && ($path ne '..') && (!-e $path)) {
      mkdir($path,$mode)
    }
    $path.="/"
  }
}

sub create {
  # WILL OVERWRITE!!!
  my ($filename,$content,$nonil,$mode) = @_;
  if (!$filename) { return }
  if ($nonil) {
    if(!defined $content) { return }
    if (ref($content) eq 'SCALAR') {
      if (length(${$content})==0) { return }
    } elsif (length($content)==0) { return }
  }
  if (-e $filename && -f $filename) {
    unlink($filename)
  } 
  my $fh=gfio::open($filename,'w');
  if ((defined $content) && (length($content))) {
    if (ref($content) eq 'SCALAR') { $fh->write($content) } else { $fh->write(\$content) }
  }
  $fh->close;
  if ($mode) { chmod $mode,$filename }
}

sub newfile {
  my ($filename,$content,$noread) = @_;
  if (!$filename) { return }
  my $mode='rw'; if ($noread) { $mode='w' }
  my $fh=gfio::open($filename,$mode);
  if (ref($content) eq 'SCALAR') { $fh->write($content) } else { $fh->write(\$content) }
  return $fh
}

sub append {
  my ($filename,$content) = @_;
  if (!-e $filename) {
    error("GFIO.Append: File '$filename' does not exist")
  }
  my $fh=gfio::open($filename,'a'); 
  if (ref($content) eq 'SCALAR') { $fh->write($content) } else { $fh->write(\$content) }
  $fh->close
}

sub crapp {
  if (!-e $_[0]) { gfio::create(@_) } else { gfio::append(@_) }
}

sub content {
  my ($filename,$offset,$length) = @_;
  if (!$filename) {
    error("GFIO.Content: No filename given")    
  }
  if (!-e $filename) {
    error("GFIO.Content: File '$filename' does not exist")
  }
  if (!-f $filename) {
    error("GFIO.Content: '$filename' is not a plain file")
  }
  my $fh=gfio::open($filename,'r');
  if (!defined $offset) { $offset=0 }
  if (!defined $length) { $length=$fh->{size} }
  if ($offset>$fh->{size}) {
    error("GFIO.Content: Read beyond boundries of '$filename', offset=$offset, size=$fh->{size}")
  }
  if ($offset+$length>$fh->{size}) {
    error("GFIO.Content: Read beyond boundries of '$filename', offset=$offset, reading $length bytes, size=$fh->{size}")
  }
  $fh->seek($offset);
  my $txt=$fh->readptr($length); $fh->close;
  return ${$txt}
}

sub changeowner {
  if ($^O =~ /win/i) { return }
  my ($filename,$user,$group) = @_;
  my ($login,$pass,$uid,$gid) = getpwnam($user);
  my ($glogin,$gpass,$guid,$ggid) = getpwnam($group);
  if ($uid && $ggid && $filename) {
    chown $uid, $ggid, $filename
  }
}

sub copy {
  my ($src,$des,$nooverwrite)=@_;
  if (!$src || !$des) { return }
  if (!-e $src) {
    error("GFIO.Copy: Source file '$src' does not exist")
  }
  if (!-f $src) {
    error("GFIO.Copy: Source '$src' is not a file!")
  }
  if (!$nooverwrite || !-e $des) {
    if (-e $des) { unlink $des }
    my $s=gfio::open($src,'r'); my $d=gfio::open($des,'w');
    my $eof=0; my $b=1<<20; my $p=0; my $l=$s->{size};
    while(!$eof){
      if($p+$b>$l){ $b=$l-$p }
      $d->write($s->readptr($b));
      $p+=$b; if($p>=$l){ $eof=1 }
    }
    $s->close; $d->close;
  }
}

sub close {
  my ($self) = @_; 
  if ($self->{opened}) {
    my $oldh = select $self->{handle}; $| = 1; select($oldh); # flush
    while ($self->{locked}) { $self->unlock }
    close($self->{handle}); $self->{opened}=0;
    delete $OPENED{$self->{file}}
  }
}

sub tell {
  my ($self) = @_; return $self->{position}
}

sub seek {
  my ($self,$pos) = @_;
  if ($pos<0) {
    error("GFIO.Seek: Trying to seek before beginning of file '$self->{file}'","Seek=$pos EOF=$self->{size}")
  }  
  if ($pos>$self->{size}) {
    error("GFIO.Seek: Seek beyond end of file '$self->{file}'","Seek=$pos EOF=$self->{size}")
  }
  sysseek($self->{handle},$pos,0); $self->{position}=$pos;
  return $self
}

sub read {
  my ($self,$len,$stopatend) = @_;
  if (!$len) { return "" }
  if (!$self->{opened}) { error("GFIO.Read: File '$self->{file}' is closed") }
  if (!$self->{read}) { error("GFIO.Read: File '$self->{file}' is read-protected") }
  if ($self->{position}+$len>$self->{size}) {
    if ($self->{position}>$self->{size}) {
      error("GFIO.Read: Trying to read beyond the end of file '$self->{file}', position=$self->{position} len=$len size=$self->{size}")
    } elsif ($stopatend) {
      my $mlen=$self->{size}-$self->{position};
      if ($len>$mlen) { $len=$mlen }
    } else {
      error("GFIO.Read: Trying to read beyond the end of file '$self->{file}', position=$self->{position} len=$len size=$self->{size}")
    }
  }
  sysseek($self->{handle},$self->{position},0) || error("GFIO.Read: Error seeking in file '$self->{file}' pos=$self->{position}: $!");
  my $data;
  if ($len<0) {
    error("GFIO.Read: Neagtive length '$len' reading on position '$self->{position}' in file '$self->{file}', size=$self->{size}")
  }
  sysread($self->{handle},$data,$len) || error("GFIO.Read: Error reading from file '$self->{file}', len=$len: $!");
  $self->{position}+=$len;
  return $data;
}

sub readptr {
  my ($self,$len,$errormode) = @_; 
  if (!$len) { my $dat=""; return \$dat }
  if (!$self->{opened}) { error("GFIO.ReadPtr: File '$self->{file}' is closed") }
  if (!$self->{read}) { error("GFIO.ReadPtr: File '$self->{file}' is read-protected") }
  if ($self->{position}>$self->{size}) {
    $self->{position}=$self->{size}
  }
  if ($self->{position}+$len>$self->{size}) {
    if ($errormode) {
      error("GFIO.ReadPtr: Trying to read beyong boundries of file '$self->{file}', position=$self->{position} len=$len size=$self->{size}")
    } else {
      $len=$self->{size}-$self->{position};
    }  
  }
  sysseek($self->{handle},$self->{position},0) || error("GFIO.ReadPtr: Error seeking in file '$self->{file}' pos=$self->{position}: $!");
  my $data;
  sysread($self->{handle},$data,$len) || error("GFIO.ReadPtr: Error reading from file '$self->{file}', len=$len: $!");
  $self->{position}+=$len;
  return \$data;
}

sub readlines {
  my ($filename) = @_;
  if (!$filename) {
    error("GFIO.Content: No filename given")    
  }
  if (!-e $filename) {
    error("GFIO.Content: File '$filename' does not exist")
  }
  if (!-f $filename) {
    error("GFIO.Content: '$filename' is not a plain file")
  }
  my $size=0; my $txt;
  my $fh=gfio::open($filename,'r'); $size=$fh->{size}; $txt=$fh->read($size); $fh->close;
  my $lines=[]; my $i=0; my $curline="";
  while ($i<$size) {
    my $c=substr($txt,$i,1); my $cc=ord($c);
    if ($cc!=13) {
      if ($cc==10) {
        push @{$lines},$curline; $curline=""
      } else {
        $curline.=$c
      }
    }
    $i++
  }
  return $lines
}

sub write {
  my ($self,$data,$nonil) = @_;
  if (ref($data) eq 'SCALAR') { $data=${$data} }
  if (!defined $data) { 
    if ($nonil) { error("GFIO.Write: Trying to write empty data, while prohibited") }
    return $self
  }
  if (!$self->{opened}) { error("GFIO.Write: File '$self->{file}' is closed") }
  if (!$self->{write} && !$self->{append}) { error("GFIO.Write: File '$self->{file}' is write-protected") }
  sysseek($self->{handle},$self->{position},0) || error("GFIO.Write: Error seeking in file '$self->{file}' pos=$self->{position}: $!");
  syswrite($self->{handle},$data) || error("GFIO.Write: Error writing to file '$self->{file}', len=".length($data).": $!");
  $self->{position}+=length($data);
  if ($self->{position}>$self->{size}) { $self->{size}=$self->{position} }
  return $self
}


sub truncate {
  my ($self,$length) = @_;
  if ($self->{size}<=$length) { return }
  truncate($self->{handle},$length);
  if ($self->{position}>$length) { $self->{position}=$length }
  $self->{size}=$length;
  return $self
}

sub lock {
  my ($self) = @_;
  if (!$self->{locked}) {
    flock($self->{handle},LOCK_EX)
  }  
  $self->{locked}++;
  return $self
}

sub unlock {
  my ($self) = @_;
  if ($self->{locked}) {
    $self->{locked}--;
    if (!$self->{locked}) {
      flock($self->{handle},LOCK_UN)
    }
  } else {
    error("GFIO.Unlock: File '$self->{file}' was not locked!")
  }
  return $self
}

sub locked {
  my ($self) = @_;
  return $self->{locked}
}

sub insert {
  my ($self,$content,$append) = @_;
  if ($append) { $self->seek($self->{size}) }
  my $start=$self->{position};
  if (!$self->{write} && !$self->{append}) { error("GFIO.Insert: File '$self->{file}' is write-protected") }
  my $movelen=$self->{size}-$start;
  my $dat=$self->readptr($movelen);
  $self->seek($start); $self->write($content); 
  my $pos=$self->tell; $self->write($dat); $self->seek($pos)
}

sub appenddata {
  my ($self,$content) = @_;
  if (!$self->{write} && !$self->{append}) { error("GFIO.Appenddata: File '$self->{file}' is write-protected") }
  $self->seek($self->{size});
  $self->write($content)
}

sub extract {
  my ($self,$len) = @_;
  my $start=$self->{position};
  my $pos=$self->{position}+$len;
  my $dat;
  if ($pos>$self->{size}) {
    $dat=$self->readptr($self->{size}-$start);
    $self->truncate($start)
  } else {
    $self->seek($pos); $dat=$self->readptr($self->{size}-$pos);
    $self->seek($start); $self->write($dat); $self->truncate($self->{size}-$pos); $self->seek($start)
  }
  return ${$dat}
}

############################## DIRECTORY LISTINGS #####################################

sub verbosefile {
  my ($self,$txt) = @_;
  print "\rReading: ";
  if (length($txt)>70) {
    print "...".substr($txt,length($txt)-67)
  } else {
    print $txt; print " "x(70-length($txt))
  }
}

sub doreadfiles {
  my ($self,$dir,$verbose,$num) = @_;
  my $fl; my $handle;
  opendir($handle,$dir) or error("GFIO.Readfiles: Error opening directory '$dir': $!");
  my $slash=(substr($dir,length($dir)-1,1) eq '/');
  do {
    my $ff;
    $fl=readdir($handle);
    if ($fl && ($fl ne ".") && ($fl ne '..')) {
      my @ss=split(/\//,$fl); my $fname=pop @ss;
      if ((lc($fname) ne 'system volume information') && (lc($fname) ne 'recycler')) {
        my @ps=split(/\./,$fname); my $fext=pop @ps; my $fsname;
        if ($fname =~ /\./) { $fsname=join(".",@ps) } else { $fsname=$fext; $fext="" }
        if ($slash || !$dir) { $ff=$dir.$fname } else { $ff=$dir."/".$fname }
        if ((!-l $ff) && (-r $ff)) {
          if (-d $ff) {
            if ($self->{recursive}) {
              if ($verbose) { $self->verbosefile("[$ff]") }
              $self->doreadfiles($ff,$verbose,$num)
            }
          } elsif ($self->{allext} || $self->{extlist}{lc($fext)}) {
            if ($verbose) { $self->verbosefile("${$num}. $fname") }
            ${$num}++;
            my @data=($fsname,$fext,$fname,$dir,$ff,'file');
            push @{$self->{list}},\@data;
          }
        }
      }
    }
  } until (!$fl);
  closedir($handle)
}

sub readfiles {
# INPUT    dir,"ext,ext,..",subdirs also (recursively), verbose (if 1 prints info to the <STDOUT>)
# Usage: $files->{list}[num][ 0=name, 1=extension, 2=name+ext, 3=directory, 4=dir+name+ext ]
  my ($dir,$extlist,$subdirs,$verbose) = @_;
  $dir =~ s/\\/\//g;
  my $self={}; bless($self);
  $self->{dir}=$dir; $self->{exist}=1;
  $self->{list}=[]; $self->{recursive}=$subdirs;
  if (defined($extlist)) {
    $extlist =~ s/ //g; $self->{extlist}={};
    foreach my $ext (split(/\,/,$extlist)) {
      $self->{extlist}{lc($ext)}=1
    }
  }  
  if (!-e $dir) {
    $self->{exist}=0; return $self
  }
  $self->{allext}=(!defined($extlist) || ($extlist eq '*') || !$extlist);
  my $num=1;
  $self->doreadfiles($dir,$verbose,\$num);
  if ($verbose) { print "\r"; print " "x79; print "\r" }
  return $self
}

sub doreaddirs {
  my ($self,$dir,$lev,$verbose) = @_;
  my $fl; my $handle;
  opendir($handle,$dir) or error("Error opening directory '$dir': $!");
  my $slash=(substr($dir,length($dir)-1,1) eq '/');
  do {
    my $ff;
    $fl=readdir($handle);
    if ($fl && ($fl ne ".") && ($fl ne '..')) {
      my @ss=split(/\//,$fl); my $fname=pop @ss;
      if ((lc($fname) ne 'system volume information') && (lc($fname) ne 'recycler')) {
        my @ps=split(/\./,$fname); my $fext=pop @ps; my $fsname;
        if ($fname =~ /\./) { $fsname=join(".",@ps) } else { $fsname=$fext; $fext="" }
        if ($slash || !$dir) { $ff=$dir.$fname } else { $ff=$dir."/".$fname }
        if ((!-l $ff) && (-d $ff) && (-r $ff)) {
          if ($verbose) { $self->verbosefile("[$ff]") }
          my @data=($fsname,$fext,$fname,$dir,$ff,$lev);
          push @{$self->{list}},\@data;
          if ($self->{recursive}) {
            $self->doreaddirs($ff,$lev+1)
          }
        }
      }
    }
  } until (!$fl);
  closedir($handle)
}

sub readdirs {
# INPUT    dir,subdirs also (recursively)
# Only read directories
  my ($dir,$subdirs,$verbose) = @_;
  $dir =~ s/\\/\//g;
  my $self={}; bless($self);
  $self->{dir}=$dir; $self->{exist}=1;
  $self->{list}=[]; $self->{recursive}=$subdirs;
  if (!-e $dir) {
    $self->{exist}=0; return $self
  }
  $self->doreaddirs($dir,0,$verbose);
  if ($verbose) { print "\r"; print " "x79; print "\r" }
  return $self
}

sub numfiles {
  my ($self) = @_;
  return 0+@{$self->{list}}
}

sub getfile {
  my ($self,$num) = @_;
  if (!$num) { $num=0 }
  if (($num<1) || ($num>$self->numfiles)) {
    error("GFIO.GetFile: File '$num' is invalid (must be between 1 and ".$self->numfiles.", reading '".$self->{dir}."')")
  }
  my $fi=$self->{list}[$num-1];
  my @stat=stat($fi->[4]) || (0)x11;
  my $info={
    barename => $fi->[0],
    ext => $fi->[1],
    name => $fi->[2],
    dir => $fi->[3],
    fullname => $fi->[4],
    level => $fi->[5],
    mode => $stat[2],
    size => $stat[7],
    atime => $stat[8],
    mtime => $stat[9],
    ctime => $stat[10]
  };
  $info->{isdir}=0; if ($fi->[5] =~ /[0-9]/) { $info->{isdir}=1 }
  return $info
}

################################################################################

# Flag    Description
#
# O_RDONLY   Read only.
# O_WRONLY   Write only.
# O_RDWR   Read and write.
# O_CREAT  Create the file if it doesn.t already exist.
# O_EXCL   Fail if the file already exists.
# O_APPEND   Append to an existing file.
# O_TRUNC   Truncate the file before opening.
# O_NONBLOCK   Non-blocking mode.
# O_NDELAY   Equivalent of O_NONBLOCK.
# O_EXLOCK   Lock using flock and LOCK_EX.
# O_SHLOCK   Lock using flock and LOCK_SH.
# O_DIRECTOPRY   Fail if the file is not a directory.
# O_NOFOLLOW   Fail if the last path component is a symbolic link.
# O_BINARY   Open in binary mode (implies a call to binmode).
# O_LARGEFILE   Open with large (>2GB) file support.
# O_SYNC   Write data physically to the disk, instead of write buffer.
# O_NOCTTY   Don't make the terminal file being opened the processescontrolling terminal, even if you don.t have one yet.

# EOF gfio.pm