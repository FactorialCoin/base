#!/use/bin/perl

package FCC::pttp;

#######################################
#                                     #
#     PTTP specific functions         #
#                                     #
#    (C) 2018 Domero                  #
#                                     #
#######################################

use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = '1.01';
@ISA         = qw(Exporter);
@EXPORT      = qw(pttpgenesis);
@EXPORT_OK   = qw();

use FCC::global;
use FCC::wallet;

1;

sub pttpgenesis {
  my $blocks=[];

  # create wallets
  my $wlist=[];
  for (my $wc=0;$wc<62;$wc++) {
    push @$wlist,newwallet();
  }
  for (my $i=1;$i<=33;$i++) {
    $wlist->[$i-1]{name}="Private $i"
  }
  for (my $g=1;$g<=3;$g++) {
    for (my $i=1;$i<=9;$i++) {
      $wlist->[33+($g-1)*9+$i-1]{name}="Sale $g\_$i"
    }
  }
  $wlist->[60]{name}="ICO";
  $wlist->[61]{name}="Reserves";
  savewallets($wlist);

  for (my $i=1;$i<=33;$i++) {
    push @$blocks,{
      type => 'out',
      wallet => $wlist->[$i-1]{wallet},
      amount => "112233445454545"
    }
  }
  for (my $i=1;$i<=27;$i++) {
    my $block = {
      type => 'out',
      wallet => $wlist->[33+$i-1]{wallet}
    };
    if ($i % 9 == 0) {
      $block->{amount} = "987654400000005"
    } else {
      $block->{amount} = "1111111100000000"
    }    
    push @$blocks,$block
  }
  push @$blocks,{
    type => 'out',
    wallet => $wlist->[60]{wallet},
    amount => "51851851800000000"
  };
  push @$blocks,{
    type => 'out',
    wallet => $wlist->[61]{wallet},
    amount => "50720325900000000"
  };
  return ({ type => 'genesis', fcctime => time + $FCCTIME, in => [] },$blocks)
}

# EOF FCC::pttp.pm (C) 2018 Domero/PTTPNederland