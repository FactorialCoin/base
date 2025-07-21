#!/usr/bin/perl

 #############################################################################
 #                                                                           #
 #   Eureka Error System v1.1.2                                              #
 #   (C) 2020 Domero, Groningen, NL                                          #
 #   ALL RIGHTS RESERVED                                                     #
 #                                                                           #
 #############################################################################

package gerr;

use strict;
use warnings; no warnings qw<uninitialized>;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use utf8;
use gterm::cntrl qw(tc size cols rows pr prat);

$VERSION     = '1.13';
@ISA         = qw(Exporter);
@EXPORT      = qw(error);
@EXPORT_OK   = qw(trace);

1;

sub error {
    my @msg=@_;
    my $return = 0;
    my $reset = 0;
    my $type = "FATAL ERROR";
    my $size = gterm::cntrl::cols()-2;
    my $trace = 2;
    my @lines;
    while ($#msg > -1) {
        if (!defined $msg[0]) { shift(@msg) }
        elsif ($msg[0] =~ /^return\=(.+)$/gs) { $return=$1; shift(@msg) }
        elsif ($msg[0] =~ /^reset\=(.+)$/gs) { $reset=$1; shift(@msg) }
        elsif ($msg[0] =~ /^type\=(.+)$/gs)   { $type=$1; shift(@msg) }
        elsif ($msg[0] =~ /^size\=(.+)$/gs)   { $size=$1; shift(@msg) }
        elsif ($msg[0] =~ /^trace\=(.+)$/gs)   { $trace=$1; shift(@msg) }
        else { push @lines, split(/\n/,shift(@msg)) }
    }
    $type=" $type ";
    my $tsize=length("$type");
    push @lines,"";
    my $ls=($size>>1)-($tsize>>1);
    my $rs=$size-($size>>1)-($tsize>>1)-1;
    my $tit= " ".("#" x $ls) . $type . ("#"x $rs)."\n";
    my $str= "\n\n";
    foreach my $line (@lines) {
        while (length($line)>0) {
            $str .= " # ";
            if (length($line)>$size) {
                $str .= substr($line,0,$size-6)."..." . " #\n";
                $line = "...".substr($line,$size-6)
            } else {
                $str .= $line . (($size-length($line)-3) > 0 ? (" "x($size-length($line)-3)):'') . " #\n";
                $line = ""
            }
        }
    }
    $str = ($reset ? gterm::cntrl::tc('reset_terminal'):"")."\n".gterm::cntrl::tc('reset') . $tit . trace($trace) . $tit . $str . $tit;
    if (!$return) { 
        $|=1;
        gterm::cntrl::pr($str);
        exit 1
    }
    return $str
}

sub trace {
    my $i=$_[0]||1;
    my @out=();
    while (($i>0) && ($i<20)) {
        my ($package,$filename,$line,$subroutine,$hasargs,$wantarray,$evaltext,$is_require,$hints,$bitmask,$hinthash)=caller($i);
        if (!$package) { $i=0 }
        else { push @out, [$line,"$package($filename)","Calling $subroutine".($hasargs ? "@DB::args":""),($subroutine eq '(eval)' && $evaltext ? "[$evaltext]":"")]; $i++ }
    }
    @out=reverse @out;
    if ($#out > -1) {
        for my $i (0..$#out) {
            my $dept="# ".(" " x $i).($i>0?"╰[":"┈[");
            my ($ln,$pk,$cl,$ev)=@{$out[$i]};
            my $ll=(60-length($dept.$cl));
            my $rr=(6-length($ln));
            $out[$i] = "$dept $cl".(" " x ( $ll>0 ? $ll : 0 ))."Line".(" " x ( $rr > 0 ? $rr : 0 ))."$ln : $pk".($ev ? "\n$ev":"");
        }
    }
    return join("\n",@out)."\n"
}

# EOF gerr.pm (C) 2020 Domero