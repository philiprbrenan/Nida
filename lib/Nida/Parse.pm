#!/usr/bin/perl -I/home/phil/perl/cpan/DataTableText/lib/ -I/home/phil/perl/cpan/NasmX86/lib/ -I/h-I/home/phil/perl/cpan/AsmC/lib/
#-------------------------------------------------------------------------------
# Parse the Nida programming language
# Philip R Brenan at appaapps dot com, Appa Apps Ltd Inc., 2021
#-------------------------------------------------------------------------------
# podDocumentation
package Nida::Parse;
our $VERSION = "20210720";
use warnings FATAL => qw(all);
use strict;
use Carp qw(confess cluck);
use Data::Dump qw(dump);
use Data::Table::Text qw(:all);
use Nasm::X86 qw(:all);
use feature qw(say current_sub);

my $develop = -e q(/home/phil/);                                                # Developing

=pod

The stack is used solely for tracking the lexical items still to be placed in
the parse tree.  Each such stacked item description is 8 bytes wide. The irst 4
bytes hold the classification of the lexical item as described by $Lexicals.
The second 4 bytes hold the index of the character in the input stream at which
this lexical items starts.  This index can be used to locate the start of the
lexical item in the input stream and a a unique key to any multi way trees that
are used to store information describing the parse tree.

=cut

#D1 Nida Parsing                                                                # Parse Nida language statements

my $Lexical_Tables = sub                                                        # Lexical table definitions
 {my $f = qq(/home/phil/perl/cpan/NasmX86/lib/Nasm/unicode/lex/lex.data);       # As produced by unicode/lex/lex.pl
     $f = qq(lib/Nida/unicode/lex/lex.data) unless $develop;
  my $l = eval readFile $f;                                                     # Load lexical definitions
  confess "$@\n" if $@;
  $l
 }->();


my $ses      = RegisterSize rax;                                                # Size of an element on the stack
my ($w1, $w2, $w3) = (r8, r9, r10);                                             # Work registers
my $prevChar = r10;                                                             # The previous character parsed
my $index    = r11;                                                             # Index of current element
my $element  = r12;                                                             # Contains the item being parsed
my $lex      = r13;                                                             # The lexical number associated with the current lexical element is placed in the lowest byte, the index at which this item was found inthe utf32 source is placed in the upper dword
my $start    = r14;                                                             # Start of the parse string
my $size     = r15;                                                             # Length of the input string
my $empty    = $Lexical_Tables->{lexicals}{empty}{number};                      # Empty element
my $Ascii            = $Lexical_Tables->{lexicals}{Ascii}           {number};   # Ascii
my $variable         = $Lexical_Tables->{lexicals}{variable}        {number};   # Variable
my $NewLineSemiColon = $Lexical_Tables->{lexicals}{NewLineSemiColon}{number};   # New line semicolon
my $semiColon        = $Lexical_Tables->{lexicals}{semiColon}       {number};   # Semicolon


sub loadCurrentChar()                                                           #P Load the details of the character currently being processed
 {my $r = $element."b";                                                         # Classification byte
  Mov $element, $index;                                                         # Load index of character as upper dword
  Shl $element, 32;
  Mov $element."b", "[$start+4*$index+3]";                                      # Load lexical classification as lowest byte

  Cmp $r, 0x10;                                                                 # Brackets , doe to their numerosioty, start after 0x10 with open even and close odd
  IfGe                                                                          # Brackets
   {And $r, 1                                                                   # 0 - open, 1 - close
   }
  sub
   {Cmp     $r, $Ascii;                                                         # Ascii is a type of variable
    IfEq
     {Mov   $r, $variable;
     }
    sub
     {Cmp   $r, $NewLineSemiColon;                                              # New line semicolon is a type of semi colon
      IfEq
       {Mov $r, $semiColon;
       };
     };
   };
 }

sub checkStackHas($)                                                            #P Check that we have at least the specified number of elements on the stack
 {my ($depth) = @_;                                                             # Number of elements required on the stack
  Mov $w1, rbp;
  Sub $w1, rsp;
PrintErrStringNL "CheckStack has $depth";
PrintErrRegisterInHex $w1;
  Cmp $w1, $ses * $depth;
  KeepFree $w1;
 }

sub pushElement()                                                            #P Push the current element on to the stack
 {Push $lex;
 }

sub pushEmpty()                                                              #P Push the empty element on to the stack
 {Mov $w1, $index;
  Shl $w1, 32;
  Or  $w1, $empty;
  Push $w1;
  KeepFree $w1;
 }

sub ClassifyNewLines(@)                                                         # A new line acts a semi colon if it appears immediately after a variable.
 {my (@parameters) = @_;                                                        # Parameters
  @_ >= 1 or confess;

  my %l = $Lexical_Tables->{lexicals}->%*;                                      # Lexical types
  my $n = genHash(__PACKAGE__.'::Lexical::Numbers',                             # Lexical numbers
    map {$_ => $l{$_}{number}} keys %l
   );

  my $s = Subroutine
   {my ($p) = @_;                                                               # Parameters
    PushR my @save = (r10, r11, r12, r13, r14, r15);

    $$p{size}->for(sub                                                          # Each character in expression
     {my ($index, $start, $next, $end) = @_;
      my $a = $$p{address} + $index * 4;
      $a->setReg(r15);
      Mov r14d, "[r15]";                                                        # Current character
      Mov r13, r14;                                                             # Current character
#      lexType r13;                                                              # Classify lexical type of current character
                                                                                # Convert variable followed by new line to variable white space semi-colon
      Cmp r10,     $n->variable;                                                # Is lexical type of last character a variable ?
      IfEq                                                                      # Lexical character of last character was a variable
       {
        Cmp r13,   $n->NewLine;
        IfEq                                                                    # Current character is new line
         {Mov r12, $n->NewLineSemiColon;
          Mov "[r15+3]", r12b;                                                  # Make the current character a new line semicolon as the new line character immediately follows a variable
         };
       };

      KeepFree r10;
      Mov r10, r13;                                                             # New last lexical type
     });
    PopR @save;
   } in  => {address => 3, size => 3}; #, out => {fail => 3};

  $s->call(@parameters);
 } # ClassIfyNewLines

sub lexicalNameFromLetter($)                                                    # Lexical name for a lexical item described by its letter
 {my ($l) = @_;                                                                 # Letter of the lexical item
  my %l = $Lexical_Tables->{treeTermLexicals}->%*;
  my $n = $l{$l};
  confess "No such lexical: $l" unless $n;
  $n
 }

sub lexicalNumberFromLetter($)                                                  # Lexical number for a lexical item described by its letter
 {my ($l) = @_;                                                                 # Letter of the lexical item
  my $n = lexicalNameFromLetter $l;
  my $N = $Lexical_Tables->{lexicals}{$n}{number};
  confess "No such lexical named: $n" unless defined $N;
  $N
 }

sub new($)                                                                      # Create a new term
 {my ($depth) = @_;                                                             # Stack depth to be converted
  PrintErrString "new start $depth: ";
  for my $i(1..$depth)
   {Pop rax;
    PrintErrRaxInHex;
    PrintErrString "  ";
   }
  PrintErrNL;
  Mov rax, $Lexical_Tables->{lexicals}{term}{number};                           # Term
  Push rax;                                                                     # Place simulated term on stack
PrintErrStringNL "New end $depth";
  Mov rax, rbp;
  Sub rax, rsp;
 }

sub error                                                                       # Die
 {my ($number) = @_;                                                            # Error number
  PrintErrStringNL "die $number:";
  PrintErrRegisterInHex r12;
 }

sub testSet($$)                                                                 # Test a set of items
 {my ($set, $name) = @_;                                                        # String of letters showing lexical items to test, name of test if any
  my @n = map {sprintf("0x%x", lexicalNumberFromLetter $_)} split //, $set;     # Each lexical item by number from letter

  push my @t, <<END;
sub test_$name(\$)                                                              #P Set ZF if have one of $set in the specified register.
 {my (\$register) = \@_;                                                        # Sub defining action to be taken on a match, register to check,
  my \$end = Label;
  Comment("Test: $name");
END
  for my $n(@n)
   {push @t, <<END;
  Cmp \$register."b", $n;
  IfEq {SetZF; Jmp \$end};
END
   }
  push @t, <<END;
  ClearZF;
  SetLabel \$end;
 }
END
  join "\n", @t
 }

sub recognizers()                                                               # Write lexical check routines
 {my @t;

  testSet($$Lexical_Tables{structure}{first}, q(first));                        # First symbols allowed
  testSet($$Lexical_Tables{structure}{last},   q(last));                        # Last symbols allowed

  for my $c(qw(abdps ads b B bdp bdps bpsv bst p pbsv s sb sbt t v))            # Test various sets of items
   {testSet($c, $c);
   }

  for my $c(qw(t bdp bdps bst abdps))                                           # Check the top of the stack and complain if there is something unexpected there
   {my @n = map {sprintf("0x%x", lexicalNumberFromLetter $_)} split //, $c;
    my $n = join ', ', map {lexicalNameFromLetter $_}         split //, $c;

    push @t, <<END;
sub check_$c()                                                                  #P Set ZF if we have one of $c on top of the stack
 {my \$end = Label;
END
    for my $n(@n)
     {push @t, <<END;
  Cmp "byte[rsp]", $n;
  IfEq {SetZF; Jmp \$end};
END
     }
    push @t, <<END;
  PrintErrStringNL "Expected $c on the stack not found";
  ClearZF;
  SetLabel \$end;
 }
END
   }
  join "\n", @t                                                                 # Lexical recognizers code
 } # recognizers

sub reduce()                                                                    #P Convert the longest possible expression on top of the stack into a term
 {#lll "TTTT ", scalar(@s), "\n", dump([@s]);
  my ($success, $end) = map {Label} 1..2;                                       # Exit points

  checkStackHas 3;                                                              # At least three elements on the stack
  IfGe
   {my ($l, $d, $r) = ($w1, $w2, $w3);
    Mov $l, "[rsp+".(2*$ses)."]";                                               # Top 3 elements on the stack
    Mov $d, "[rsp+".(1*$ses)."]";
    Mov $r, "[rsp+".(0*$ses)."]";

    test_t($l);                                                                 # Parse out infix operator expression
    IfEq
     {test_t($r);
      IfEq
       {test_ads($d);
        IfEq
         {Add rsp, 3 * $ses;                                                    # Reorder into polish notation
          Push $_ for $d, $l, $r;
          new(3);
          Jmp $success;
         };
       };
     };

    test_b($l);                                                                 # Parse parenthesized term
    IfEq
     {test_B($r);
      IfEq
       {test_t($d);
        IfEq
         {Add rsp, 3 * $ses;                                                    # Pop expression
          Push $d;
          Jmp $success;
         };
       };
     };
    KeepFree $l, $d, $r;
   };

  checkStackHas 2;                                                              # At least two elements on the stack
  IfGe                                                                          # Convert an empty pair of parentheses to an empty term
   {my ($l, $r) = ($w1, $w2);

    KeepFree $l, $r;                                                            # Why ?
    Mov $l, "[rsp+".(1*$ses)."]";                                               # Top 3 elements on the stack
    Mov $r, "[rsp+".(0*$ses)."]";
    test_b($l);                                                                 # Empty pair of parentheses
    IfEq
     {test_B($r);
      IfEq
       {Add rsp, 2 * $ses;                                                      # Pop expression
        pushEmpty;
        new(1);
        Jmp $success;
       };
     };
    test_s($l);                                                                 # Semi-colon, close implies remove unneeded semi
    IfEq
     {test_B($r);
      IfEq
       {Add rsp, 2 * $ses;                                                      # Pop expression
        Push $r;
        Jmp $success;
       };
     };
    test_p($l);                                                                 # Prefix, term
    IfEq
     {test_t($r);
      IfEq
       {new(2);
        Jmp $success;
       };
     };
    KeepFree $l, $r;
   };

  ClearZF;                                                                      # Failed to match anything
  Jmp $end;

  SetLabel $success;                                                            # Successfully matched
  SetZF;

  SetLabel $end;                                                                # End
 } # reduce

sub accept_a()                                                               #P Assign
 {&check_t;
  pushElement;
 }

sub accept_b                                                                 #P Open
 {&check_bdps;
  pushElement;
 }

sub accept_reduce                                                            #P Accept by reducing
 {Vq('count',99)->for(sub
   {my ($index, $start, $next, $end) = @_;                                      # Execute body
    reduce;
    IfNe {Jmp $end};                                                            # Keep going as long as reductions are possible
   });
 }

sub accept_B                                                                 #P Closing parenthesis
 {&check_bst;
  accept_reduce;
  pushElement;
  accept_reduce;
  &check_bst;
 }

sub accept_d                                                                 #P Infix but not assign or semi-colon
 {&check_t;
  pushElement;
 }

sub accept_p                                                                 #P Prefix
 {&check_bdp;
  pushElement;
 }

sub accept_q                                                                 #P Post fix
 {&check_t;
  IfEq                                                                          # Post fix operator applied to a term
   {Pop $w1;
    pushElement;
    Push $w1;
    new(2);
   }
 }

sub accept_s                                                                 #P Semi colon
 {&check_bst;
  Mov $w1, "[rsp]";
  test_sb($w1);
  KeepFree $w1;
  IfEq                                                                          # Insert an empty element between two consecutive semicolons
   {pushEmpty;
   };
  accept_reduce;
  pushElement;
 }

sub accept_v                                                                    #P Variable
  {&check_abdps;
   pushElement;
   new(1);
   Vq(count,99)->For(sub                                                        # Reduce prefix operators
    {my ($index, $start, $next, $end) = @_;
     checkStackHas 2;
     IfLt {Jmp $end};
     my ($l, $r) = (rax, rdx);
     Mov $l, "[rsp+".(1*$ses)."]";
     Mov $r, "[rsp+".(0*$ses)."]";
     test_p($l);
     IfNe {Jmp $end};
     new(2);
    });
  }

sub parseExpression($)                                                          #P Parse an expression.
 {my ($parameters) = @_;                                                        # Parameters
  my $end          = Label;

  $$parameters{source}->setReg($start);                                         # Start of expression string after it has been classified
  $$parameters{size}  ->setReg($size);                                          # Number of characters in the expression

  Cmp $size, 0;                                                                 # Check for empty expression
  IfEq
   {Jmp $end;
   };

  loadCurrentChar;                                                              # Load current character
  &test_first($element);
  IfNe
   {error(1, <<END =~ s(\n) ( )gsr);
Expression must start with 'opening parenthesis', 'prefix
operator', 'semi-colon' or 'variable'.
END
   };

  &test_v($element);                                                            # Single variable
  IfEq
   {Push $element;
    new(1);
   }
  sub
   {test_s($element);                                                           # Semi
    IfEq
     {pushEmpty;
      new(1);
     };
    pushElement;
   };
  KeepFree $element;

  Inc $index;                                                                   # We have processed the first character above

  For                                                                           # Parse each utf32 character after it has been classified
   {my ($start, $end, $next) = @_;                                              # Start and end of the classification loop
    loadCurrentChar;                                                            # Load current character
    Cmp $element, $Lexical_Tables->{lexicals}{WhiteSpace}{number};
    IfEq {Jmp $next};                                                           # Ignore white space

    Cmp $element, 1;
    IfGt                                                                        # Brackets are singular but everything else can potential be a plurality
     {Cmp $prevChar, $element;                                                  # Compare with previous element known not to be whitespace
      IfEq                                                                      # Ignore white space
       {Jmp $next
       };
     };
    Mov $prevChar, $element;                                                    # Save element to previous element now we know we are on a different element
Mov rax, "[rsp]";
PrintErrRegisterInHex rax, $element;

    for my $l(sort keys $Lexical_Tables->{lexicals}->%*)                        # Each possible lexical item after classification
     {my $n = lexicalNumberFromLetter($l);
      Cmp $element."b", $n;
      IfEq {eval "accept_$l"; Jmp $next};
     }
   } $index, $size;

  test_last($element);                                                          # Last element
  IfNe                                                                          # Incomplete expression
   {error(2, "Incomplete expression");
   };

  Vq('count', 99)->for(sub                                                      # Remove trailing semicolons if present
   {my ($index, $start, $next, $end) = @_;                                      # Execute body
    checkStackHas(2);
    IfLt                                                                        # Does not have two or more elements
     {Mov $w1, 0;
      $$parameters{parse}->getReg($w1);
      KeepFree $w1;
      Jmp $end
     };
    Pop $w1;
    test_s($w1);                                                                # Check that the top most element is a semi colon
    IfNe                                                                        # Not a semi colon so put it back and finish the loop
     {Push $w1;
      Jmp $end;
     };
   });

  accept_reduce;                                                                # Final reductions

  checkStackHas(1);
  IfNe                                                                          # Incomplete expression
   {error(3, "Incomplete expression");
   };

  Pop $w1;                                                                      # The resulting parse tree
  $$parameters{parse}->getReg($w1);
  SetLabel $end;
 } # parseExpression

sub parse(@)                                                                    # Create a parser for an expression described by variables
 {my (@parameters) = @_;                                                        # Parameters describing expression

  my $s = Subroutine
   {my ($p) = @_;                                                               # Parameters
    parseExpression($p);
   } in => {source => 3, size => 3};

  $s->call(@parameters);
 } # parse

#d
#-------------------------------------------------------------------------------
# Export - eeee
#-------------------------------------------------------------------------------

use Exporter qw(import);

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

@ISA          = qw(Exporter);
@EXPORT       = qw();
@EXPORT_OK    = qw();
%EXPORT_TAGS  = (all => [@EXPORT, @EXPORT_OK]);

# podDocumentation
=pod

=encoding utf-8

=head1 Name

Nasm::X86 - Generate X86 assembler code using Perl as a macro pre-processor.

=head1 Synopsis

Parse the Nida programming language

=head1 Description


=cut


# Tests and documentation

sub test
 {my $p = __PACKAGE__;
  binmode($_, ":utf8") for *STDOUT, *STDERR;
  return if eval "eof(${p}::DATA)";
  my $s = eval "join('', <${p}::DATA>)";
  $@ and die $@;
  eval $s;
  $@ and die $@;
  1
 }

test unless caller;

1;
# podDocumentation
#__DATA__
use Time::HiRes qw(time);
use Test::Most;

bail_on_fail;

my $localTest = ((caller(1))[0]//'Nida::Parse') eq "Nida::Parse";               # Local testing mode

Test::More->builder->output("/dev/null") if $localTest;                         # Reduce number of confirmation messages during testing

if ($^O =~ m(bsd|linux|cygwin)i)                                                # Supported systems
 {if (confirmHasCommandLineCommand(q(nasm)) and LocateIntelEmulator)            # Network assembler and Intel Software Development emulator
   {plan tests => 4;
   }
  else
   {plan skip_all => qq(Nasm or Intel 64 emulator not available);
   }
 }
else
 {plan skip_all => qq(Not supported on: $^O);
 }

my $startTime = time;                                                           # Tests

eval {goto latest} if !caller(0) and -e "/home/phil";                           # Go to latest test if specified

if (1) {                                                                        #TPrintOutRegistersInHex #TRs
  my $q = Rb(1..8);
  Mov rax, "[$q];";
  Mov r8, rax;
  Shl r8d, 16;
  PrintOutRegisterInHex rax, r8;

  ok Assemble(debug => 1, eq => <<END);
   rax: 0807 0605 0403 0201
    r8: 0000 0000 0201 0000
END
 }

if (1) {                                                                        # Check conversion of classification to lexical item
  my @o = (Rb(reverse 0x10,              0, 0, 1),                              # Open bracket
           Rb(reverse 0x11,              0, 0, 2),                              # Close bracket
           Rb(reverse $Ascii,            0, 0, 27),                             # Ascii 'a'
           Rb(reverse $variable,         0, 0, 27),                             # Variable 'a'
           Rb(reverse $NewLineSemiColon, 0, 0, 0),                              # New line semicolon
           Rb(reverse $semiColon,        0, 0, 0));                             # Semi colon

  for my $o(@o)                                                                 # Try converting each input element
   {Mov $start, $o;
    Mov $index, 0;
    loadCurrentChar;
    PrintOutRegisterInHex $element;
   }

  ok Assemble(debug => 0, eq => <<END);
   r12: 0000 0000 0000 0000
   r12: 0000 0000 0000 0001
   r12: 0000 0000 0000 0007
   r12: 0000 0000 0000 0007
   r12: 0000 0000 0000 0009
   r12: 0000 0000 0000 0009
END
 }

#latest:
if (0) {                                                                        # Parse some code
  my $lexDataFile = qq(unicode/lex/lex.data);                                   # As produced by unicode/lex/lex.pl
     $lexDataFile = qq(lib/Nasm/$lexDataFile) unless $develop;

  my $lex = $Lexical_Tables;                                               # Load lexical definitions

  my @p = my (  $out,    $size,   $opens,      $fail) =                         # Variables
             (Vq(out), Vq(size), Vq(opens), Vq('fail'));

  my $source = Rutf8 $$lex{sampleText};                                         # String to be parsed in utf8
  my $sourceLength = StringLength Vq(string, $source);
     $sourceLength->outNL("Input  Length: ");

  ConvertUtf8ToUtf32 Vq(u8,$source), size8 => $sourceLength,                    # Convert to utf32
    (my $source32       = Vq(u32)),
    (my $sourceSize32   = Vq(size32)),
    (my $sourceLength32 = Vq(count));

  $sourceSize32   ->outNL("Output Length: ");                                   # Write output length

  PrintOutStringNL "After conversion from utf8 to utf32";
  PrintUtf32($sourceLength32, $source32);                                       # Print utf32

  Vmovdqu8 zmm0, "[".Rd(join ', ', $lex->{lexicalLow} ->@*)."]";                # Each double is [31::24] Classification, [21::0] Utf32 start character
  Vmovdqu8 zmm1, "[".Rd(join ', ', $lex->{lexicalHigh}->@*)."]";                # Each double is [31::24] Range offset,   [21::0] Utf32 end character

  ClassifyWithInRangeAndSaveOffset address=>$source32, size=>$sourceLength32;   # Alphabetic classification

  PrintOutStringNL "After classification into alphabet ranges";
  PrintUtf32($sourceLength32, $source32);                                       # Print classified utf32

  Vmovdqu8 zmm0, "[".Rd(join ', ', $lex->{bracketsLow} ->@*)."]";               # Each double is [31::24] Classification, [21::0] Utf32 start character
  Vmovdqu8 zmm1, "[".Rd(join ', ', $lex->{bracketsHigh}->@*)."]";               # Each double is [31::24] Range offset,   [21::0] Utf32 end character

  ClassifyWithInRange address=>$source32, size=>$sourceLength32;                # Bracket matching

  PrintOutStringNL "After classification into brackets";
  PrintUtf32($sourceLength32, $source32);                                       # Print classified brackets

  MatchBrackets address=>$source32, size=>$sourceLength32, $opens, $fail;       # Match brackets

  PrintOutStringNL "After bracket matching";
  PrintUtf32($sourceLength32, $source32);                                       # Print matched brackets

  ClassifyNewLines address=>$source32, size=>$sourceLength32;                   # Classify white space

  PrintOutStringNL "After converting some new lines to semi colons";
  PrintUtf32($sourceLength32, $source32);                                       # Print matched brackets

  if (0 and $develop)                                                           #
   {parse source=>$source32, size=>$sourceLength32, my $parse = Vq(parse);
   }

  ok Assemble(debug => 1, eq => <<END);
Input  Length: 0000 0000 0000 00DB
Output Length: 0000 0000 0000 036C
After conversion from utf8 to utf32
0001 D5EE 0000 205F  0001 D44E 0001 D460  0001 D460 0001 D456  0001 D454 0001 D45B  0000 205F 0000 230A  0000 205F 0000 2329  0000 205F 0000 2768  0000 205F 0001 D5EF
0001 D5FD 0000 205F  0000 2769 0000 205F  0000 232A 0000 205F  0001 D429 0001 D425  0001 D42E 0001 D42C  0000 205F 0000 276A  0000 205F 0001 D600  0001 D5F0 0000 205F
0000 276B 0000 205F  0000 230B 0000 205F  0000 27E2 0000 000A  0001 D5EE 0001 D5EE  0000 205F 0001 D44E  0001 D460 0001 D460  0001 D456 0001 D454  0001 D45B 0000 000A
0000 0020 0000 0020  0000 0073 0000 006F  0000 006D 0000 0065  0000 000A 0000 000A  0000 0061 0000 0073  0000 0063 0000 0069  0000 0069 0000 000A  0000 000A 0000 0074
0000 0065 0000 0078  0000 0074 0000 205F  0001 D429 0001 D425  0001 D42E 0001 D42C  0000 000A 0000 0020  0000 0020 0001 D5F0  0001 D5F0 0000 205F  0000 27E2 0000 000A

After classification into alphabet ranges
0700 001A 0B00 0000  0600 001A 0600 002C  0600 002C 0600 0022  0600 0020 0600 0027  0B00 0000 0000 230A  0B00 0000 0000 2329  0B00 0000 0000 2768  0B00 0000 0700 001B
0700 0029 0B00 0000  0000 2769 0B00 0000  0000 232A 0B00 0000  0400 0029 0400 0025  0400 002E 0400 002C  0B00 0000 0000 276A  0B00 0000 0700 002C  0700 001C 0B00 0000
0000 276B 0B00 0000  0000 230B 0B00 0000  0900 0000 0300 0000  0700 001A 0700 001A  0B00 0000 0600 001A  0600 002C 0600 002C  0600 0022 0600 0020  0600 0027 0300 0000
0200 0020 0200 0020  0200 0073 0200 006F  0200 006D 0200 0065  0300 0000 0300 0000  0200 0061 0200 0073  0200 0063 0200 0069  0200 0069 0300 0000  0300 0000 0200 0074
0200 0065 0200 0078  0200 0074 0B00 0000  0400 0029 0400 0025  0400 002E 0400 002C  0300 0000 0200 0020  0200 0020 0700 001C  0700 001C 0B00 0000  0900 0000 0300 0000

After classification into brackets
0700 001A 0B00 0000  0600 001A 0600 002C  0600 002C 0600 0022  0600 0020 0600 0027  0B00 0000 1200 230A  0B00 0000 1400 2329  0B00 0000 1600 2768  0B00 0000 0700 001B
0700 0029 0B00 0000  1700 2769 0B00 0000  1500 232A 0B00 0000  0400 0029 0400 0025  0400 002E 0400 002C  0B00 0000 1800 276A  0B00 0000 0700 002C  0700 001C 0B00 0000
1900 276B 0B00 0000  1300 230B 0B00 0000  0900 0000 0300 0000  0700 001A 0700 001A  0B00 0000 0600 001A  0600 002C 0600 002C  0600 0022 0600 0020  0600 0027 0300 0000
0200 0020 0200 0020  0200 0073 0200 006F  0200 006D 0200 0065  0300 0000 0300 0000  0200 0061 0200 0073  0200 0063 0200 0069  0200 0069 0300 0000  0300 0000 0200 0074
0200 0065 0200 0078  0200 0074 0B00 0000  0400 0029 0400 0025  0400 002E 0400 002C  0300 0000 0200 0020  0200 0020 0700 001C  0700 001C 0B00 0000  0900 0000 0300 0000

After bracket matching
0700 001A 0B00 0000  0600 001A 0600 002C  0600 002C 0600 0022  0600 0020 0600 0027  0B00 0000 1200 0022  0B00 0000 1400 0014  0B00 0000 1600 0012  0B00 0000 0700 001B
0700 0029 0B00 0000  1700 000D 0B00 0000  1500 000B 0B00 0000  0400 0029 0400 0025  0400 002E 0400 002C  0B00 0000 1800 0020  0B00 0000 0700 002C  0700 001C 0B00 0000
1900 001B 0B00 0000  1300 0009 0B00 0000  0900 0000 0300 0000  0700 001A 0700 001A  0B00 0000 0600 001A  0600 002C 0600 002C  0600 0022 0600 0020  0600 0027 0300 0000
0200 0020 0200 0020  0200 0073 0200 006F  0200 006D 0200 0065  0300 0000 0300 0000  0200 0061 0200 0073  0200 0063 0200 0069  0200 0069 0300 0000  0300 0000 0200 0074
0200 0065 0200 0078  0200 0074 0B00 0000  0400 0029 0400 0025  0400 002E 0400 002C  0300 0000 0200 0020  0200 0020 0700 001C  0700 001C 0B00 0000  0900 0000 0300 0000

After converting some new lines to semi colons
0700 001A 0B00 0000  0600 001A 0600 002C  0600 002C 0600 0022  0600 0020 0600 0027  0B00 0000 1200 0022  0B00 0000 1400 0014  0B00 0000 1600 0012  0B00 0000 0700 001B
0700 0029 0B00 0000  1700 000D 0B00 0000  1500 000B 0B00 0000  0400 0029 0400 0025  0400 002E 0400 002C  0B00 0000 1800 0020  0B00 0000 0700 002C  0700 001C 0B00 0000
1900 001B 0B00 0000  1300 0009 0B00 0000  0900 0000 0300 0000  0700 001A 0700 001A  0B00 0000 0600 001A  0600 002C 0600 002C  0600 0022 0600 0020  0600 0027 0300 0000
0200 0020 0200 0020  0200 0073 0200 006F  0200 006D 0200 0065  0A00 0000 0300 0000  0200 0061 0200 0073  0200 0063 0200 0069  0200 0069 0A00 0000  0300 0000 0200 0074
0200 0065 0200 0078  0200 0074 0B00 0000  0400 0029 0400 0025  0400 002E 0400 002C  0300 0000 0200 0020  0200 0020 0700 001C  0700 001C 0B00 0000  0900 0000 0300 0000

END
 }

#latest:
if (0) {
  is_deeply Assemble(debug=>1), <<END;
END
 }

ok 1 for 1..2;

unlink $_ for qw(hash print2 sde-log.txt sde-ptr-check.out.txt z.txt);          # Remove incidental files

lll "Finished:", time - $startTime;
