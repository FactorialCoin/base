#!/usr/bin/perl

package FCC::feehistory;

################################################
#                                              #
#   FCC Node Transaction Fee Payout & History  #
#                                              #
#      (C) 2018 Domero                         #
#                                              #
################################################

use strict;
no strict 'refs';
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.01';
@ISA         = qw(Exporter);
@EXPORT      = qw(feehistory_takeloop c_ledgerstatus c_calculatefee);
@EXPORT_OK   = qw();

use JSON;
use gfio 1.10;
use Crypt::Ed25519;
use FCC::global;
use gparse;

################################################################################
# FEE History Globals
my $FEEMODE    = 0;
my $FEEHISTORY;         # History
my $FEETIMEOUT = 5;     # Sec Timeout 
#my $FEEGRAN    = 60;    # 1 Min
#my $DAYGRAN    = 60;    # Day 7 minute week ;)
my $FEEGRAN    = 3600;  # Hour
my $DAYGRAN    = 86400; # Day
my $FEETIME    = 0;     # Fee Timer
my $FEEWEEK;            # Current Fee Week
my $FEESTATUS;          # Fee Status HASH
my $FEESTATUSTIME;      # Fee Status Timeout Timer
my $FEECHECKTIME;       # TimeCheck Point
my $FEECALCMIN = 5;     # Minimal Nodes to call for CalculateFee Totals
my $FEENODES;           # Active Nodes used for CalculateFee Totals
my $FEETOTALS;          # CalulateFee Totals
my $FEETOTALSTIME;      # Fee Totals Timeout Timer
################################################################################
# used from FCC::coinbase
my $CBKEY;              # CoinbaseKey
my $GETNODE;            # getnode
my $GETINIT;            # getinitlist
my $BJSON;              # bjson
my $OUTJSON;            # outjson
################################################################################

1;

################################################################################
# Initialize FCC::coinbase Globals & Methods
sub init {
  ($CBKEY,$GETNODE,$GETINIT,$BJSON,$OUTJSON)=@_
}

################################################################################

sub feehistory_takeloop {
  ##############################################################################
  # Init Startup Loading
  if (!defined $FEEHISTORY) {
    print "[%] Loading Fee History [%]\n";
    load_currentfeehistory()
  }
  # Fee History & Payout Timer
  my $curtime = int(($FCCTIME+time)/$FEEGRAN);
  if ($curtime != $FEETIME) {
    print "[|] Starting Fee History Payout Task [|]\n";
    $FEETIME = $curtime;
    # Initialize Ledger Status Call
    $FEEMODE = call_ledgerstatus()
  }
  # Waiting for LedgerStatus or TIMEOUT to retry ###############################
  elsif ($FEEMODE == 1) {
    if (time-$FEESTATUSTIME > $FEETIMEOUT) {
      print "[!] Ledger Status Call Timed Out, Trying again [!]\n";
      $FEEMODE = call_ledgerstatus()
    }
  }
  # Ledger Status Call Completed ###############################################
  elsif ($FEEMODE == 2) {
    $FEEMODE = (ref($FEESTATUS) eq 'HASH' ? update_ledgerstatus() : 0)
  }
  # Wait for all Fee Totals or Timeout #########################################
  elsif ($FEEMODE == 3) {
    $FEEMODE = wait_calculatefee()
  }
  # Finalize Fee Transaction Blocks ############################################
  elsif ($FEEMODE == 4) {
    $FEEMODE = finalize_feepayout();
    if(!$FEEMODE){
      # When Finished Save Current Updated History
      save_currentfeehistory()
    }
  }
  # Transfer Fee Transaction Payout ############################################
  elsif ($FEEMODE == 5) {
    $FEEMODE = tranfser_feepayout();
    print "[|] Timely Fee Payout Done [|]\n";
    # Save Current Updated History
    save_currentfeehistory()
  }
  ##############################################################################
}



################################################################################
#
#   FEE HISTORY 
#
################################################################################
# Load & Save FEEHISTORY

sub load_currentfeehistory {
  $FEEHISTORY = (-e "history.fee" ? decode_json(gfio::content("history.fee")) : [] );
  $FEEWEEK = (-e "history.week" ? gfio::content("history.week") : getweek() )
}

sub save_currentfeehistory {
  if(-e "history.bk"){ unlink("history.bk") }
  if(-e "history.fee"){ gfio::copy("history.fee","history.bk") }
  gfio::create("history.fee",encode_json($FEEHISTORY));
  gfio::create("history.week",$FEEWEEK);
}

################################################################################
# FEE MODE 0
sub call_ledgerstatus {
  my $nodes=&$GETINIT(1);
  if (0+@$nodes) {
#    print "[#] Calling Ledger Status on (".gparse::str($nodes).") :  [#]\n";
    $FEESTATUSTIME = time;
    $FEESTATUS = undef;
    $nodes->[0]{client}{ledgerstatusCalled}=$FEEMODE;
    &$OUTJSON($nodes->[0]{client},{command=>'ledgerstatus'});
    return 1
  }
  print "[!] Can't Start Fee History Task, for a lack of Initialized Nodes [!]\n";
  return 0
}

################################################################################
# FEE MODE 1
################################################################################
# Node Function :
#
# sub fcc_ledgerstatus {
#   my($FCCSERV,$k)=@_;
#   outjson($FCCSERV,{command=>'ledgerstatus',blockheight=>..,ledgerlength=>..});
# }
#
################################################################################
sub c_ledgerstatus {
  my ($client,$k) = @_;
  if (defined $client->{ledgerstatusCalled}) {
    delete $client->{ledgerstatusCalled};
    if ($FEEMODE==1 && defined $k->{blockheight} && defined $k->{ledgerlength}) {
      $FEEMODE = 2;
      $FEESTATUS = {
        time         => ($FEETIME*$FEEGRAN),
        blockheight  => $k->{blockheight},
        ledgerlength => $k->{ledgerlength},
        wallets      => []
      }
    }
  } else {
    print prtm(),"Illegal command call received from $client->{ip}:$client->{port}: ledgerstatus\n";
    &$OUTJSON($client,{ command=>'error', error=>"Unknown command given in input" });
    $client->{killafteroutput}=1;
  }
}

################################################################################
# FEE MODE 2
sub update_ledgerstatus {
  print "[#] Update Ledger Status [#]\n";
  my $len = $#$FEEHISTORY;
  # make Fee transfer hour block
  if ($len == -1 || $FEEHISTORY->[$len]{blockheight} != $FEESTATUS->{blockheight}) {
    # if exists keep last spare in the last block 
    $FEESTATUS->{spare} = $FEEHISTORY->[$len] ? $FEEHISTORY->[$len]{spare} : 0;
    # Add to FeeHistory
    push @$FEEHISTORY, $FEESTATUS;
    $len = $#$FEEHISTORY;
    my ($position,$length);
    # First History Event
    if ($len == 0) {
      $FEECHECKTIME = $FEEHISTORY->[$len]{time};
      $position = 0;
      $length = $FEEHISTORY->[$len]{ledgerlength}-4
    }
    # All Next Events
    else {
      $FEECHECKTIME = $FEEHISTORY->[$len-1]{time};
      $position = $FEEHISTORY->[$len-1]{ledgerlength}-4;
      $length = ($FEEHISTORY->[$len]{ledgerlength}-$FEEHISTORY->[$len-1]{ledgerlength})-4
    }
    # fee calculation command
    $FEEHISTORY->[$len]{calculatefee} = { command => 'calculatefee', position => $position, length => $length };
    $FEENODES      = &$GETINIT($FEECALCMIN);
    $FEETOTALS     = [];
    $FEETOTALSTIME = time;
    for my $node (@$FEENODES) {
      $node->{client}{calculatefeeCalled}=$FEEMODE;
      &$OUTJSON($node->{client},$FEEHISTORY->[$len]{calculatefee})
    }
    return 3
  }
  # Skip the Last Hour for unchanged BlockHeight
  else {
    print "[!] Last blockheight is the same, Skipping this Hour for a lack of Updates [!]\n";
    return 0
  }
}

################################################################################
# FEE MODE 3
################################################################################
# Node Function :
# sub fcc_calculatefee {
#   my($FCCSERV,$k)=@_;
#   outjson($FCCSERV,{command=>'calculatedfee',totfee=>calculatefee($k->{position},$k->{length})});
# }
#
################################################################################
sub c_calculatefee {
  my ($client,$k) = @_;
  if ($client->{fccinit} && defined $client->{calculatefeeCalled}){
    print " ** Command call received from $client->{ip}:$client->{port}: calculatefee\n";
    delete $client->{calculatefeeCalled};
    push @$FEETOTALS, {
      feetotal => $k->{totfee},
      key      => $client->{host} . ':' . $client->{port}
    };
    return
  }
  print " *!*!* Illegal or Uninitialized command call received from $client->{ip}:$client->{port}: calculatefee\n";
  &$OUTJSON($client,{ command=>'error', error=>"Unknown command given in input" });
  $client->{killafteroutput}=1;
}

sub wait_calculatefee {
  if (
    time-$FEETOTALSTIME > $FEETIMEOUT ||
    $#$FEENODES == $#$FEETOTALS
  ) {
    print "FEETOTALS : ".gparse::str($FEETOTALS)."\n";
    # Gather the same TotalFee values
    my $feetotals = {};
    for my $node ( @$FEETOTALS ) {
      my $tot = $node->{feetotal};
      if (!defined $feetotals->{$tot}) {
        $feetotals->{$tot} = [ $node->{key} ]
      } else {
        push @{$feetotals->{$tot}}, $node->{key}
      }
    }
    # Check for Multiles
    my $feetotal=0; my $totals = [ keys %$feetotals ];
    # Multiple Totals, Take the longest node list, and Fault the Other one(s)
    print "feetotals : ".gparse::str($feetotals)."\n";
    if ($#$totals > 0) {
      my $most=0; my $totfee=0;
      for my $tot ( @$totals ) {
        my $cnt = $#{$totals->{$tot}};
        if ($cnt>$most) { $most=$cnt; $feetotal=$tot }
      }
      # Faulting the wrong Node(s)
      for my $tot ( @$totals ) {
        if($tot ne $feetotal){
          for my $key ( @{$totals->{$tot}} ){
            my $node=&$GETNODE($key);
            if($node){
              print prtm(),"Total Fee Error received from $key: wait_calculatefee\n";
              &$OUTJSON($node->{client},{ command=>'error', error=>"CalculateFee should be '$feetotal' instead of '$tot'." });
              $node->{client}{killafteroutput}=1
            }
          }
        }
      }
    }
    # only one Total Value, as it should be
    else {
      $feetotal = defined $totals->[0] ? $totals->[0] : 0;
    }
    print "[#] Fee Total Consensus : $feetotal Doggies [#]\n";
    $FEEHISTORY->[$#$FEEHISTORY]{feetotal} = $feetotal;
    return 4
  }
  return 3
}

################################################################################
# FEE MODE 4
sub finalize_feepayout {
  print "[#] Finalize Fee Payout [#]\n";
  # Add Current Online Node Wallets in the Timeblock
  my $nodes = &$GETINIT();
  for my $node ( @$nodes ) {
    if ($node->{connected} <= $FEECHECKTIME) {
      push @{$FEEHISTORY->[$#$FEEHISTORY]{wallets}}, $node->{wallet}
    }
  }
  # Check for Timely Payout
  my $week = getweek();
  if ($week != $FEEWEEK) {
    $FEEWEEK = $week;
    return 5
  }
  # Finalized Current Round
  print "[|] Fee History Update Done [|]\n";
  return 0
}

################################################################################
# FEE MODE 5
sub tranfser_feepayout {
  print "[#] Transfer Fee Payout [#]\n";
  my $transactions=[];
  # Drop the now useless first in the list if more than one listed
  if ($#$FEEHISTORY > 0) {
    shift(@$FEEHISTORY)
  }
  # Shift everything in between until the last in the list
  while ( $#$FEEHISTORY > 0 ) {
    push @$transactions, shift(@$FEEHISTORY)
  }
  # Now add the last of the list, to keep it for the next round as the previouse time block
  push @$transactions, $FEEHISTORY->[0];
  # Log the Transfered FeeHistory Blocks
  if (!-e "history.log") {
    gfio::create("history.log",encode_json($transactions))
  } else {
    gfio::append("history.log","\n//".("#"x80)."//\n".encode_json($transactions))
  }
  # Gather Total Wallet Amounts
  my $total   = $transactions->[$#$transactions]{spare} || 0; # Get Last spare on 0 outblocks
  my $amount  = {};
  for my $transblock ( @$transactions ) {
    $total += $transblock->{feetotal};
    my $longdoggies = ( $#{$transblock->{wallets}} > -1 ? $transblock->{feetotal}/( 1 + $#{$transblock->{wallets}} ) : 0);
    # Transfer Average to Nodes
    for my $wallet ( @{$transblock->{wallets}} ) {
      if (!defined $amount->{$wallet}) {
        $amount->{$wallet} = $longdoggies
      } else {
        $amount->{$wallet} += $longdoggies
      }
    }
  }
  my $outblocks = [];
  my $sign      = "";
  my $payed     = 0;
  # Gather spare Amounts and Create the Payable Outblocks and signable data
  for my $wallet ( keys %$amount ) {
    my $doggies = int($amount->{$wallet});
    if ($doggies) {
      $payed += $doggies;
      $sign .= $wallet . dechex($doggies,16) . dechex(0,4);
      push @$outblocks, { type => 'out', wallet => $wallet, amount => $doggies, fee => 0 }
    }
  }
  # total spare
  my $spare = $total - $payed;
  # Sign and Send
  if ($sign) {
    # Create Fee-Transaction-Seal
    my $blockheight = $transactions->[$#{$transactions}]{blockheight};
    my $feepayout = {
      command     => 'feepayout',
      fcctime     => time + $FCCTIME,
      spare       => $spare,
      blockheight => $blockheight,
      signature   => octhex(Crypt::Ed25519::sign( dechex($spare,8) . dechex($blockheight,12) . $sign, hexoct($FCCSERVERKEY), hexoct($CBKEY) )),
      outblocks   => $outblocks
    };
    print "[#] Fee Payout Transfer: $payed payed + $spare spare = $total FCC [#]\n";
    # Broadcast to all initialized Nodes
    print "\n ## Broadcasting ## ".gparse::str($feepayout)."\n\n";
    &$BJSON($feepayout);
    print "[#] Broadcast Completed [#]\n";
  }
  # Or Save the spare Amount because of a lack of Outblocks
  else {
    print "[#] No Outblocks for Fee Payout Transfer: $spare spare = $total FCC [#]\n";
    $transactions->[$#{$transactions}]{spare} = $spare
  }
  return 0
}

################################################################################

sub getweek {
  my $TIME=$FCCTIME+time-($DAYGRAN*4); # Thursay + 4 * $DAYGRAN = Monday 00:00:00 FCC TIME
  int($TIME/($DAYGRAN*7))              # weeks since  Monday, 5 Jan 1970 00:00:00 FCC TIME
}

# EOF FCC::feehistory (C) 2018 Domero
