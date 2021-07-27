#!/usr/bin/perl -I/home/phil/perl/cpan/DataTableText/lib/
#-------------------------------------------------------------------------------
# Classify white space in a unisyn expression
# Philip R Brenan at appaapps dot com, Appa Apps Ltd Inc., 2021
#-------------------------------------------------------------------------------
use warnings FATAL => qw(all);
use strict;
use Carp;
use Data::Dump qw(dump);
use Test::More qw(no_plan);

sub ignore(@)                                                                   # Decide which spaces can be ignored and which are actually ascii
 {my (@i) = @_;                                                                 # Array of 'v', 'a', 's', 'n'

  for(my $i = 1; $i < @i; ++$i)                                                 # 'n' immediately after 'a'  is significant
   {confess "n preceded by s at position $i in\n".join('', @i)."\n"
      if $i[$i-1] eq 's' and $i[$i] eq 'n';
     $i[$i] = 'N' if $i[$i-1] eq 'a' and $i[$i] eq 'n';
   }

  for(my ($i, $s, $S) = (0); $i < @i; ++$i)                                     # Whitespace between 'a' is significant
   {my $e = $i[$i];

    if (!defined $s)                                                            # Outside
     {$s = $i + 1 if $e eq 'a';
     }
    elsif ($e eq 'a')                                                           # Terminating on 'a' - mark all interior 's'  and 'n' as significant and then continue from this point
     {$i[$_] = uc $i[$_] for $s..$i-1;
      $s = $i + 1;
     }
    elsif ($i[$i] eq 'v')                                                       # Terminating on 'v' so no action
     {$s = undef;
     }

    if (!defined $S)                                                            # Looking for 's' so we can mark 's' preceding 'a' as significant
     {$S = $i if $e eq 's';
     }
    elsif ($e eq 'a')                                                           # Terminating on 'a' - mark all preceding 's' as significant
     {$i[$_] = uc $i[$_] for $S..$i-1; $S = undef;
     }
    elsif ($e eq 's') {}                                                        # Continue over intervening 's'
    else                                                                        # Terminating on something other than 'a'
     {$S = undef;
     }
   }

  @i
 }

sub T($$)                                                                       # Test white space ignoration
 {my ($i, $o) = @_;                                                             # Input string of lexical items, expected output string
  my $g = join '', ignore split //, $i;
  return 1 if $g eq $o;
  my @n = stringsAreNotEqual($g, $o);
  confess "Got/Expected:\n$g\n$o\n".dump(\@n);
 }

ok T "nan",
     "naN";

ok T "n",
     "n";

ok T "nnnnn",
     "nnnnn";

ok T "vnv",
     "vnv";

ok T "sanvnv",
     "SaNvnv";

ok T "vnav",
     "vnav";

ok T "vnnnav",
     "vnnnav";

ok T "vnananavvvvaaaas",
     "vnaNaNavvvvaaaas";

ok T "vnananasv",
     "vnaNaNasv";

ok T "vnnnnssssssssav",
     "vnnnnSSSSSSSSav";

ok T "vnnnnssssssssassssassv",
     "vnnnnSSSSSSSSaSSSSassv";

ok T "vnnnnssssssssaaassssaaassv",
     "vnnnnSSSSSSSSaaaSSSSaaassv";

ok T "vnnnnssssssssaaassssaaannnnssssssssaaassssaaassv",
     "vnnnnSSSSSSSSaaaSSSSaaaNNNNSSSSSSSSaaaSSSSaaassv";

ok T "vnsssssssansv",
     "vnSSSSSSSaNsv";

ok T "nanssvnsvnnsaasannssanvnsassvnvnsassvnss",
     "naNssvnsvnnSaaSaNNSSaNvnSassvnvnSassvnss";

ok T "nanssvnsvnnsaasannssanvnsassvnvnsassvnnanssvnsvnnsaasannssanvnsassvnvnsassvnss",
     "naNssvnsvnnSaaSaNNSSaNvnSassvnvnSassvnnaNssvnsvnnSaaSaNNSSaNvnSassvnvnSassvnss";
