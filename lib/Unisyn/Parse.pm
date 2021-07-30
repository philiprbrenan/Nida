#!/usr/bin/perl -I/home/phil/perl/cpan/DataTableText/lib/ -I/home/phil/perl/cpan/NasmX86/lib/ -I/h-I/home/phil/perl/cpan/AsmC/lib/ -I/home/phil/perl/cpan/TreeTerm/lib/
#-------------------------------------------------------------------------------
# Parse a Unisyn expression.
# Philip R Brenan at appaapps dot com, Appa Apps Ltd Inc., 2021
#-------------------------------------------------------------------------------
# podDocumentation
package Unisyn::Parse;
our $VERSION = "20210720";
use warnings FATAL => qw(all);
use strict;
use Carp qw(confess cluck);
use Data::Dump qw(dump);
use Data::Table::Text qw(:all !parse);
use Nasm::X86 qw(:all);
use feature qw(say current_sub);

my $develop = -e q(/home/phil/);                                                # Developing

#D1 Parse                                                                       # Parse Unisyn expressions

my $Lex = sub                                                                   # Lexical table definitions
 {my $d = qq(lib/Unisyn/unicode/lex/lex.data);                                  # As produced by unicode/lex/lex.pl
  my $f = $develop ? qq(/home/phil/perl/cpan/UnisynParse/$d) : $d;
  my $l = eval readFile $f;                                                     # Load lexical definitions
  confess "$@\n" if $@;
  $l
 }->();

my $debug             = 0;                                                      # 1 - Trace actions on stack

my $ses               = RegisterSize rax;                                       # Size of an element on the stack
my ($w1, $w2, $w3, $w4) = (r8, r9, r10, r11);                                   # Work registers
my $prevChar          = r11;                                                    # The previous character parsed
my $index             = r12;                                                    # Index of current element
my $element           = r13;                                                    # Contains the item being parsed
my $start             = r14;                                                    # Start of the parse string
my $size              = r15;                                                    # Length of the input string
my $indexScale        = 4;                                                      # The size of a utf32 character
my $lexCodeOffset     = 3;                                                      # The offset in a classified character to the lexical code.
my $bitsPerByte       = 8;                                                      # The number of bits in a byte

my $Ascii             = $$Lex{lexicals}{Ascii}            {number};             # Ascii
my $assign            = $$Lex{lexicals}{assign}           {number};             # Assign
my $CloseBracket      = $$Lex{lexicals}{CloseBracket}     {number};             # Close bracket
my $empty             = $$Lex{lexicals}{empty}            {number};             # Empty element
my $NewLineSemiColon  = $$Lex{lexicals}{NewLineSemiColon} {number};             # New line semicolon
my $OpenBracket       = $$Lex{lexicals}{OpenBracket}      {number};             # Open  bracket
my $prefix            = $$Lex{lexicals}{prefix}           {number};             # Prefix operator
my $semiColon         = $$Lex{lexicals}{semiColon}        {number};             # Semicolon
my $suffix            = $$Lex{lexicals}{suffix}           {number};             # Suffix
my $term              = $$Lex{lexicals}{term}             {number};             # Term
my $variable          = $$Lex{lexicals}{variable}         {number};             # Variable
my $WhiteSpace        = $$Lex{lexicals}{WhiteSpace}       {number};             # Variable
my $firstSet          = $$Lex{structure}{first};                                # First symbols allowed
my $lastSet           = $$Lex{structure}{last};                                 # Last symbols allowed
my $asciiNewLine      = ord("\n");                                              # New line in ascii
my $asciiSpace        = ord(' ');                                               # Space in ascii

sub getAlpha($$$)                                                               # Load the position of a lexical item in its alphabet from the current character
 {my ($register, $address, $index) = @_;                                        # Register to load, address of start of string, index into string
  Mov $register, "[$address+$indexScale*$index]";                               # Load lexical code
 }

sub getLexicalCode($$$)                                                         # Load the lexical code of the current character in memory into the specified register.
 {my ($register, $address, $index) = @_;                                        # Register to load, address of start of string, index into string
  Mov $register, "[$address+$indexScale*$index+$lexCodeOffset]";                # Load lexical code
 }

sub putLexicalCode($$$$)                                                        # Put the specified lexical code into the current character in memory.
 {my ($register, $address, $index, $code) = @_;                                 # Register used to laod code, address of string, index into string, code to put
  defined($code) or confess;
  Mov $register, $code;
  Mov "[$address+$indexScale*$index+$lexCodeOffset]", $register;                # Save lexical code
 }

sub loadCurrentChar()                                                           #P Load the details of the character currently being processed so that we have the index of the character in the upper half of the current character and the lexical type of the character in the lowest byte
 {my $r = $element."b";                                                         # Classification byte

  Mov $element, $index;                                                         # Load index of character as upper dword
  Shl $element, $indexScale * $bitsPerByte;                                     # Save the index of the character in the upper half of the register so that we know where the character came from.
  getLexicalCode $r, $start, $index;                                            # Load lexical classification as lowest byte

  Cmp $r, $$Lex{bracketsBase};                                                  # Brackets , due to their numerosity, start after 0x10 with open even and close odd
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
  Cmp $w1, $ses * $depth;
 }

sub pushElement()                                                               #P Push the current element on to the stack
 {Push $element;
  if ($debug)
   {PrintOutStringNL "Push Element:";
    PrintOutRegisterInHex $element;
   }
 }

sub pushEmpty()                                                                 #P Push the empty element on to the stack
 {Mov  $w1, $index;
  Shl  $w1, $indexScale * $bitsPerByte;
  Or   $w1, $empty;
  Push $w1;
  if ($debug)
   {PrintOutStringNL "Push Empty";
   }
 }

sub lexicalNameFromLetter($)                                                    # Lexical name for a lexical item described by its letter
 {my ($l) = @_;                                                                 # Letter of the lexical item
  my %l = $Lex->{treeTermLexicals}->%*;
  my $n = $l{$l};
  confess "No such lexical: $l" unless $n;
  $n->{short}
 }

sub lexicalNumberFromLetter($)                                                  # Lexical number for a lexical item described by its letter
 {my ($l) = @_;                                                                 # Letter of the lexical item
  my $n = lexicalNameFromLetter $l;
  my $N = $Lex->{lexicals}{$n}{number};
  confess "No such lexical named: $n" unless defined $N;
  $N
 }

sub new($$)                                                                     # Create a new term
 {my ($depth, $description) = @_;                                               # Stack depth to be converted, text reason why we are creating a new term
  PrintOutStringNL "New: $description" if $debug;
  for my $i(1..$depth)
   {Pop $w1;
    PrintOutRegisterInHex $w1 if $debug;
   }
  Mov $w1, $term;                                                               # Term
  Push $w1;                                                                     # Place simulated term on stack
 }

sub error($)                                                                    # Die
 {my ($message) = @_;                                                           # Error message
  PrintOutStringNL "Error: $message";
  PrintOutString "Element: ";
  PrintOutRegisterInHex $element;
  PrintOutString "Index  : ";
  PrintOutRegisterInHex $index;
  Exit(0);
 }

sub testSet($$)                                                                 # Test a set of items, setting the Zero Flag is one matches else clear the Zero flag
 {my ($set, $register) = @_;                                                    # Set of lexical letters, Register to test
  my @n = map {sprintf("0x%x", lexicalNumberFromLetter $_)} split //, $set;     # Each lexical item by number from letter
  my $end = Label;
  for my $n(@n)
   {Cmp $register."b", $n;
    IfEq {SetZF; Jmp $end};
   }
  ClearZF;
  SetLabel $end;
 }

sub checkSet($)                                                                 # Check that one of a set of items is on the top of the stack or complain if it is not
 {my ($set) = @_;                                                               # Set of lexical letters
  my @n =  map {lexicalNumberFromLetter $_} split //, $set;
  my $end = Label;

  for my $n(@n)
   {Cmp "byte[rsp]", $n;
    IfEq {SetZF; Jmp $end};
   }
  error("Expected one of: '$set' on the stack");
  ClearZF;
  SetLabel $end;
 }

sub reduce($)                                                                   # Convert the longest possible expression on top of the stack into a term  at the specified priority
 {my ($priority) = @_;                                                          # Priority of the operators to reduce
  $priority =~ m(\A(1|3)\Z);                                                    # 1 - all operators, 2 - priority 2 operators
  my ($success, $end) = map {Label} 1..2;                                       # Exit points

  checkStackHas 3;                                                              # At least three elements on the stack
  IfGe
   {my ($l, $d, $r) = ($w1, $w2, $w3);
    Mov $l, "[rsp+".(2*$ses)."]";                                               # Top 3 elements on the stack
    Mov $d, "[rsp+".(1*$ses)."]";
    Mov $r, "[rsp+".(0*$ses)."]";

    if ($debug)
     {PrintOutStringNL "Reduce 3:";
      PrintOutRegisterInHex $l, $d, $r;
     }

    testSet("t",  $l);                                                          # Parse out infix operator expression
    IfEq
     {testSet("t",  $r);
      IfEq
       {testSet($priority == 1 ? "ads" : 'd', $d);                              # Reduce all operators or just reduce dyads
        IfEq
         {Add rsp, 3 * $ses;                                                    # Reorder into polish notation
          Push $_ for $d, $l, $r;
          new(3, "Term infix term");
          Jmp $success;
         };
       };
     };

    testSet("b",  $l);                                                          # Parse parenthesized term
    IfEq
     {testSet("B",  $r);
      IfEq
       {testSet("t",  $d);
        IfEq
         {Add rsp, 3 * $ses;                                                    # Pop expression
          Push $d;
          PrintOutStringNL "Reduce by ( term )" if $debug;
          Jmp $success;
         };
       };
     };
    KeepFree $l, $d, $r;
   };

  checkStackHas 2;                                                              # At least two elements on the stack
  IfGe                                                                          # Convert an empty pair of parentheses to an empty term
   {my ($l, $r) = ($w1, $w2);

    if ($debug)
     {PrintOutStringNL "Reduce 2:";
      PrintOutRegisterInHex $l, $r;
     }

    KeepFree $l, $r;                                                            # Why ?
    Mov $l, "[rsp+".(1*$ses)."]";                                               # Top 3 elements on the stack
    Mov $r, "[rsp+".(0*$ses)."]";
    testSet("b",  $l);                                                          # Empty pair of parentheses
    IfEq
     {testSet("B",  $r);
      IfEq
       {Add rsp, 2 * $ses;                                                      # Pop expression
        pushEmpty;
        new(1, "Empty brackets");
        Jmp $success;
       };
     };
    testSet("s",  $l);                                                          # Semi-colon, close implies remove unneeded semi
    IfEq
     {testSet("B",  $r);
      IfEq
       {Add rsp, 2 * $ses;                                                      # Pop expression
        Push $r;
        PrintOutStringNL "Reduce by ;)" if $debug;
        Jmp $success;
       };
     };
    testSet("p", $l);                                                           # Prefix, term
    IfEq
     {testSet("t",  $r);
      IfEq
       {new(2, "Prefix term");
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

sub reduceMultiple($)                                                           #P Reduce existing operators on the stack
 {my ($priority) = @_;                                                          # Priority of the operators to reduce
  Vq('count',99)->for(sub                                                       # An improbably high but finit number of reductions
   {my ($index, $start, $next, $end) = @_;                                      # Execute body
    reduce($priority);
    Jne $end;                                                                   # Keep going as long as reductions are possible
   });
 }

sub accept_a()                                                                  #P Assign
 {checkSet("t");
  reduceMultiple 2;
  PrintOutStringNL "accept a" if $debug;
  pushElement;
 }

sub accept_b                                                                    #P Open
 {checkSet("abdps");
  PrintOutStringNL "accept b" if $debug;
  pushElement;
 }

sub accept_B                                                                    #P Closing parenthesis
 {checkSet("bst");
  PrintOutStringNL "accept B" if $debug;
  reduceMultiple 1;
  pushElement;
  reduceMultiple 1;
  checkSet("bst");
 }

sub accept_d                                                                    #P Infix but not assign or semi-colon
 {checkSet("t");
  PrintOutStringNL "accept d" if $debug;
  pushElement;
 }

sub accept_p                                                                    #P Prefix
 {checkSet("abdps");
  PrintOutStringNL "accept p" if $debug;
  pushElement;
 }

sub accept_q                                                                    #P Post fix
 {checkSet("t");
  PrintOutStringNL "accept q" if $debug;
  IfEq                                                                          # Post fix operator applied to a term
   {Pop $w1;
    pushElement;
    Push $w1;
    new(2, "Postfix");
   }
 }

sub accept_s                                                                    #P Semi colon
 {checkSet("bst");
  PrintOutStringNL "accept s" if $debug;
  Mov $w1, "[rsp]";
  testSet("s",  $w1);
  IfEq                                                                          # Insert an empty element between two consecutive semicolons
   {pushEmpty;
   };
  reduceMultiple 1;
  pushElement;
 }

sub accept_v                                                                    #P Variable
  {checkSet("abdps");
   PrintOutStringNL "accept v" if $debug;
   pushElement;
   new(1, "Variable");
   Vq(count,99)->for(sub                                                        # Reduce prefix operators
    {my ($index, $start, $next, $end) = @_;
     checkStackHas 2;
     Jl $end;
     my ($l, $r) = ($w1, $w2);
     Mov $l, "[rsp+".(1*$ses)."]";
     Mov $r, "[rsp+".(0*$ses)."]";
     testSet("p", $l);
     Jne $end;
     new(2, "Prefixed variable");
    });
  }

sub parseExpressionCode()                                                       #P Parse the string of classified lexicals addressed by register $start of length $length.  The resulting parse tree (if any) is returned in r15.
 {my $end = Label;
  my $eb  = $element."b";                                                       # Contains a byte from the item being parsed

  Cmp $size, 0;                                                                 # Check for empty expression
  Je $end;

  loadCurrentChar;                                                              # Load current character
### Need test for ignorable white space as first character
  testSet($firstSet, $element);
  IfNe
   {error(<<END =~ s(\n) ( )gsr);
Expression must start with 'opening parenthesis', 'prefix
operator', 'semi-colon' or 'variable'.
END
   };

  testSet("v", $element);                                                       # Single variable
  IfEq
   {pushElement;
    new(1, "accept initial variable");
   }
  sub
   {testSet("s", $element);                                                     # Semi
    IfEq
     {pushEmpty;
      new(1, "accept initial semicolon");
     };
    pushElement;
   };

  Inc $index;                                                                   # We have processed the first character above
  Mov $prevChar, $element;                                                      # Initialize the previous lexical item

  For                                                                           # Parse each utf32 character after it has been classified
   {my ($start, $end, $next) = @_;                                              # Start and end of the classification loop
    loadCurrentChar;                                                            # Load current character

    PrintOutRegisterInHex $element if $debug;

    Cmp $eb, $WhiteSpace;
    IfEq {Jmp $next};                                                           # Ignore white space

    Cmp $eb, 1;                                                                 # Brackets are singular but everything else can potential be a plurality
    IfGt
     {Cmp $prevChar."b", $eb;                                                   # Compare with previous element known not to be whitespace or a bracket
      Je $next
     };
    Mov $prevChar, $element;                                                    # Save element to previous element now we know we are on a different element

    for my $l(sort keys $Lex->{lexicals}->%*)                                   # Each possible lexical item after classification
     {my $x = $Lex->{lexicals}{$l}{letter};
      next unless $x;                                                           # Skip chaarcters that do noit have a letter defined for Tree::Term because the lexical items needed to layout a file of lexic al items are folded down to the actual lexicals required to represent the language independent of the textual layout with whitespace.

      my $n = $Lex->{lexicals}{$l}{number};
      Comment "Compare to $n for $l";
      Cmp $eb, $n;

      IfEq
       {eval "accept_$x";
        Jmp $next
       };
     }
    error("Unexpected lexical item");                                           # Not selected
   } $index, $size;

  testSet($lastSet, $prevChar);                                                 # Last lexical  element
  IfNe                                                                          # Incomplete expression
   {error("Incomplete expression");
   };

  Vq('count', 99)->for(sub                                                      # Remove trailing semicolons if present
   {my ($index, $start, $next, $end) = @_;                                      # Execute body
    checkStackHas 2;
    IfLt {Jmp $end};                                                            # Does not have two or more elements
    Pop $w1;
    testSet("s", $w1);                                                          # Check that the top most element is a semi colon
    IfNe                                                                        # Not a semi colon so put it back and finish the loop
     {Push $w1;
      Jmp $end;
     };
   });

  reduceMultiple 1;                                                             # Final reductions

  checkStackHas 1;
  IfNe                                                                          # Incomplete expression
   {error("Multiple expressions on stack");
   };

  Pop r15;                                                                      # The resulting parse tree
  SetLabel $end;
 } # parseExpressionCode

sub parseExpression(@)                                                          # Create a parser for an expression described by variables
 {my (@parameters) = @_;                                                        # Parameters describing expression

  my $s = Subroutine
   {my ($parameters) = @_;                                                      # Parameters
    PushR my @save = map {"r$_"} 8..15;
    $$parameters{source}->setReg($start);                                       # Start of expression string after it has been classified
    $$parameters{size}  ->setReg($size);                                        # Number of characters in the expression

    Push rbp; Mov rbp, rsp;                                                     # New frame

    parseExpressionCode;

    $$parameters{parse}->getReg(r15);                                           # Number of characters in the expression

    Mov rsp, rbp; Pop rbp;
                                                                                # Remove new frame
    PopR @save;
   } in => {source => 3, size => 3}, out => {parse => 3};

  $s->call(@parameters);
 } # parse

sub MatchBrackets(@)                                                            # Replace the low three bytes of a utf32 bracket character with 24 bits of offset to the matching opening or closing bracket. Opening brackets have even codes from 0x10 to 0x4e while the corresponding closing bracket has a code one higher.
 {my (@parameters) = @_;                                                        # Parameters
  @_ >= 1 or confess;

  my $s = Subroutine
   {my ($p) = @_;                                                               # Parameters
    Comment "Match brackets in utf 32 text";
    my $finish = Label;
    PushR my @save = (xmm0, k7, r10, r11, r12, r13, r14, r15, rbp);             # r15 current character address. r14 is the current classification. r13 the last classification code. r12 the stack depth. r11 the number of opening brackets found. r10  address of first utf32 character.
    Mov rbp, rsp;                                                               # Save stack location so we can use the stack to record the brackets we have found
    ClearRegisters r11, r12, r15;                                               # Count the number of brackets and track the stack depth, index of each character
    Cq(three, 3)->setMaskFirst(k7);                                             # These are the number of bytes that we are going to use for the offsets of brackets which limits the size of a program to 24 million utf32 characters
    $$p{fail}   ->getConst(0);                                                  # Clear failure indicator
    $$p{opens}  ->getConst(0);                                                  # Clear count of opens
    $$p{address}->setReg(r10);                                                  # Address of first utf32 character
    my $w = RegisterSize eax;                                                   # Size of a utf32 character

    $$p{size}->for(sub                                                          # Process each utf32 character in the block of memory
     {my ($index, $start, $next, $end) = @_;
      my $continue = Label;

      Mov r14b, "[r10+$w*r15+3]";                                               # Classification character

      Cmp r14, 0x10;                                                            # First bracket
      Jl $continue;                                                             # Less than first bracket
      Cmp r14, 0x4f;                                                            # Last bracket
      Jg $continue;                                                             # Greater than last bracket

      Test r14, 1;                                                              # Zero means that the bracket is an opener
      IfZ sub                                                                   # Save an opener then continue
       {Push r15;                                                               # Save position in input
        Push r14;                                                               # Save opening code
        Inc r11;                                                                # Count number of opening brackets
        Inc r12;                                                                # Number of brackets currently open
        Jmp $continue;
       };
      Cmp r12, 1;                                                               # Check that there is a bracket to match on the stack
      IfLt sub                                                                  # Nothing on stack
       {Not r15;                                                                # Minus the offset at which the error occurred so that we can fail at zero
        $$p{fail}->getReg(r15);                                                 # Position in input that caused the failure
        Jmp $finish;                                                            # Return
       };
      Mov r13, "[rsp]";                                                         # Peek at the opening bracket code which is on top of the stack
      Inc r13;                                                                  # Expected closing bracket
      Cmp r13, r14;                                                             # Check for match
      IfNe sub                                                                  # Mismatch
       {Not r15;                                                                # Minus the offset at which the error occurred so that we can fail at zero
        $$p{fail}->getReg(r15);                                                 # Position in input that caused the failure
        Jmp $finish;                                                            # Return
       };
      Pop r13;                                                                  # The closing bracket matches the opening bracket
      Pop r13;                                                                  # Offset of opener
      Dec r12;                                                                  # Close off bracket sequence
      Vpbroadcastq xmm0, r15;                                                   # Load offset of opener
      Vmovdqu8 "[r10+$w*r13]\{k7}", xmm0;                                       # Save offset of opener in the code for the closer - the classification is left intact so we still know what kind of bracket we have
      Vpbroadcastq xmm0, r13;                                                   # Load offset of opener
      Vmovdqu8 "[r10+$w*r15]\{k7}", xmm0;                                       # Save offset of closer in the code for the openercloser - the classification is left intact so we still know what kind of bracket we have
      SetLabel $continue;                                                       # Continue with next character
      Inc r15;                                                                  # Next character
     });

    SetLabel $finish;
    Mov rsp, rbp;                                                               # Restore stack
    $$p{opens}->getReg(r11);                                                    # Number of brackets opened
    PopR @save;
   } in  => {address => 3, size => 3}, out => {fail => 3, opens => 3};

  $s->call(@parameters);
 } # MatchBrackets

sub ClassifyNewLines(@)                                                         #P Scan input string looking for opportunitiesd to convert new lines into semi colons
 {my (@parameters) = @_;                                                        # Parameters
  @_ >= 1 or confess;

  my $s = Subroutine
   {my ($p) = @_;                                                               # Parameters
    my $current       = r15;                                                    # Index of the current character
    my $middle        = r14;                                                    # Index of the middle character
    my $first         = r13;                                                    # Index of the first character
    my $address       = r12;                                                    # Address of input string
    my $size          = r11;                                                    # Length of input utf32 string
    my($c1, $c2)      = (r8."b", r9."b");                                       # Lexical codes being tested

    PushR my @save = (r8, r9, r10, r11, r12, r13, r14, r15);

    $$p{address}->setReg($address);                                             # Address of string
    $$p{size}   ->setReg($size);                                                # Size of string
    Mov $current, 2; Mov $middle, 1; Mov $first, 0;

    For                                                                         # Each character in input string
     {my ($start, $end, $next) = @_;                                            # Start, end and next labels


      getLexicalCode $c1, $address, $middle;                                    # Lexical code of the middle character
      Cmp $c1, $WhiteSpace;
      IfEq
       {getAlpha $c1, $address, $middle;

        Cmp $c1, $asciiNewLine;
        IfEq                                                                    # Middle character is a insignificant new line and thus could be a semicolon
         {getLexicalCode $c1, $address, $first;

          my sub makeSemiColon                                                  # Make a new line into a new line semicolon
           {putLexicalCode $c2, $address, $middle, $NewLineSemiColon;
           }

          my sub check_bpv                                                      # Make new line if followed by 'b', 'p' or 'v'
           {getLexicalCode $c1, $address, $current;
            Cmp $c1, $OpenBracket;

            IfEq
             {makeSemiColon;
             }
            sub
             {Cmp $c1, $prefix;
              IfEq
               {makeSemiColon;
               }
              sub
               {Cmp $c1, $variable;
                IfEq
                 {makeSemiColon;
                 };
               };
             };
           }

          Cmp $c1, $CloseBracket;                                               # Check first character of sequence
          IfEq
           {check_bpv;
           }
          sub
           {Cmp $c1, $suffix;
            IfEq
             {check_bpv;
             }
            sub
             {Cmp $c1, $variable;
              IfEq
               {check_bpv;
               };
             };
           };
         };
       };

      Mov $first, $middle; Mov $middle, $current;                               # Find next lexical item
      getLexicalCode $c1, $address, $current;                                   # Current lexical code
      Mov $middle, $current;
      Inc $current;                                                             # Next possible character
      For
       {my ($start, $end, $next) = @_;
        getLexicalCode $c2, $address, $current;                                 # Lexical code of  next character
        Cmp $c1, $c2;
        Jne $end;                                                               # Terminate when we are in a different lexical item
       } $current, $size;
     } $current, $size;

    PopR @save;
   } in  => {address => 3, size => 3};

  $s->call(@parameters);
 } # ClassifyNewLines

sub ClassifyWhiteSpace(@)                                                       #P Classify white space per: lib/Unisyn/whiteSpace/whiteSpaceClassification.pl
 {my (@parameters) = @_;                                                        # Parameters
  @_ >= 1 or confess;

  my $s = Subroutine
   {my ($p) = @_;                                                               # Parameters
    my $eb            = r15."b";                                                # Lexical type of current char
    my $s             = r14;                                                    # State of white space between 'a'
    my $S             = r13;                                                    # State of white space before  'a'
    my $cb            = r12."b";                                                # Actual character within alphabet
    my $address       = r11;                                                    # Address of input string
    my $index         = r10;                                                    # Index of current char
    my ($w1, $w2)     = (r8."b", r9."b");                                       # Temporary work registers

    my sub getAlpha($;$)                                                        # Load the position of a lexical item in its alphabet from the current character
     {my ($register, $indexReg) = @_;                                           # Register to load, optional index register
      getAlpha $register, $address,  $index // $indexReg                        # Supplied index or default
     };

    my sub getLexicalCode()                                                     # Load the lexical code of the current character in memory into the current character
     {getLexicalCode $eb, $address,  $index;                                    # Supplied index or default
     };

    my sub putLexicalCode($;$)                                                   # Put the specified lexical code into the current character in memory.
     {my ($code, $indexReg) = @_;                                               # Code, optional index register
      putLexicalCode $w1, $address, ($indexReg//$index), $code;
     };

    PushR my @save = (r8, r9, r10, r11, r12, r13, r14, r15);

    $$p{address}->setReg($address);                                             # Address of string
    Mov $s, -1; Mov $S, -1; Mov $index, 0;                                      # Initial states, position

    $$p{size}->for(sub                                                          # Each character in expression
     {my ($indexVariable, $start, $next, $end) = @_;

      $indexVariable->setReg($index);
      getLexicalCode;                                                           # Current lexical code

      Block                                                                     # Trap space before new line and detect new line after ascii
       {my ($start, $end) = @_;
        Cmp $index, 0;    Je  $end;                                             # Start beyond the first character so we can look back one character.
        Cmp $eb, $Ascii;  Jne $end;                                             # Current is ascii

        Mov $w1, "[$address+$indexScale*$index-$indexScale+$lexCodeOffset]";    # Previous lexical code
        Cmp $w1, $Ascii;  Jne $end;                                             # Previous is ascii

        if (1)                                                                  # Check for 's' followed by 'n' and 'a' followed by 'n'
         {Mov $w1, "[$address+$indexScale*$index-$indexScale]";                 # Previous character
          getAlpha $w2;                                                         # Current character

          Cmp $w1, $asciiSpace;                                                 # Check for space followed by new line
          IfEq
           {Cmp $w2, $asciiNewLine;
            IfEq                                                                # 's' followed by 'n'
             {PrintErrStringNL "Space detected before new line at index:";
              PrintErrRegisterInHex $index;
             };
           };

          Cmp $w1, $asciiSpace;    Je  $end;                                    # Check for  'a' followed by 'n'
          Cmp $w1, $asciiNewLine;  Je  $end;                                    # Current is 'a' but not 'n' or 's'
          Cmp $w2, $asciiNewLine;  Jne $end;                                    # Current is 'n'

          putLexicalCode $WhiteSpace;                                           # Mark new line as significant
         }
       };

      Block                                                                     # Spaces and new lines between other ascii
       {my ($start, $end) = @_;
        Cmp $s, -1;
        IfEq                                                                    # Looking for opening ascii
         {Cmp $eb, $Ascii;         Jne $end;                                    # Not ascii
          getAlpha $cb;                                                         # Current character
          Cmp $cb, $asciiNewLine;  Je $end;                                     # Skip over new lines
          Cmp $cb, $asciiSpace;    Je $end;                                     # Skip over spaces
          IfEq
           {Mov $s, $index; Inc $s;                                             # Ascii not space nor new line
           };
          Jmp $end;
         }

        sub                                                                     # Looking for closing ascii
         {Cmp $eb, $Ascii;
          IfNe                                                                  # Not ascii
           {Mov $s, -1;
            Jmp $end
           };
          getAlpha $cb;                                                         # Current character
          Cmp $cb, $asciiNewLine; Je $end;                                      # Skip over new lines
          Cmp $cb, $asciiSpace;   Je $end;                                      # Skip over spaces

          For                                                                   # Move over spaces and new lines between two ascii characters that are neither of new line or space
           {my ($start, $end, $next) = @_;
            getAlpha $cb, $s;                                                   # 's' or 'n'
            Cmp $cb, $asciiSpace;
            IfEq
             {putLexicalCode $WhiteSpace, $s;                                   # Mark as significant white space.
              Jmp $next;
             };
            Cmp $cb, $asciiNewLine;
            IfEq
             {putLexicalCode $WhiteSpace;                                       # Mark as significant new line
              Jmp $next;
             };
           } $s, $index;

          Mov $s, $index; Inc $s;
         };
       };

      Block                                                                     # 's' preceding 'a' are significant
       {my ($start, $end) = @_;
        Cmp $S, -1;
        IfEq                                                                    # Looking for 's'
         {Cmp $eb, $Ascii;                                                      # Not 'a'
          IfNe
           {Mov $S, -1;
            Jmp $end
           };
          getAlpha $cb;                                                         # Actual character in alphabet
          Cmp $cb, $asciiSpace;                                                 # Space
          IfEq
           {Mov $S, $index;
            Jmp $end;
           };
         }
        sub                                                                     # Looking for 'a'
         {Cmp $eb, $Ascii;                                                      # Not 'a'
          IfNe
           {Mov $S, -1;
            Jmp $end
           };
          getAlpha $cb;                                                         # Actual character in alphabet
          Cmp $cb, $asciiSpace; Je $end;                                        # Skip 's'

          Cmp $cb, $asciiNewLine;
          IfEq                                                                  # New lines prevent 's' from preceeding 'a'
           {Mov $s, -1;
            Jmp $end
           };

          For                                                                   # Move over spaces to non space ascii
           {my ($start, $end, $next) = @_;
            putLexicalCode $WhiteSpace, $S;                                     # Mark new line as significant
           } $S, $index;
          Mov $S, -1;                                                           # Look for next possible space
         }
       };
     });

    $$p{size}->for(sub                                                          # Invert white space so that significant white space becomes ascii and the remainder is ignored
     {my ($indexVariable, $start, $next, $end) = @_;

      $indexVariable->setReg($index);
      getLexicalCode;                                                           # Current lexical code

      Block                                                                     # Invert non significant white space
       {my ($start, $end) = @_;
        Cmp $eb, $Ascii;
        Jne $end;                                                               # Ascii

        getAlpha $cb;                                                           # Actual character in alphabet
        Cmp $cb, $asciiSpace;
        IfEq
         {putLexicalCode $WhiteSpace;
          Jmp $next;
         };
        Cmp $cb, $asciiNewLine;
        IfEq
         {putLexicalCode $WhiteSpace;                                           # Mark new line as not significant
          Jmp $next;
         };
       };

      Block                                                                     # Mark significant white space
       {my ($start, $end) = @_;
        Cmp $eb, $WhiteSpace; Jne $end;                                         # Not significant white space
        putLexicalCode $Ascii;                                                  # Mark as ascii
       };
     });

    PopR @save;
   } in  => {address => 3, size => 3};

  $s->call(@parameters);
 } # ClassifyWhiteSpace

sub parseUtf8(@)                                                                # Parse a unisyn expression encoded as utf8
 {my (@parameters) = @_;                                                        # Parameters
  @_ >= 1 or confess;

  my $s = Subroutine
   {my ($p) = @_;                                                               # Parameters

    PrintOutStringNL "ParseUtf8" if $debug;

    PushR my @save = (zmm0, zmm1);

    ConvertUtf8ToUtf32 u8 => $$p{address}, size8 => $$p{size},                  # Convert to utf32
      (my $source32       = Vq(u32)),
      (my $sourceSize32   = Vq(size32)),
      (my $sourceLength32 = Vq(count));

    if ($debug)
     {PrintOutStringNL "After conversion from utf8 to utf32";
      $sourceSize32   ->outNL("Output Length: ");                               # Write output length
      PrintUtf32($sourceLength32, $source32);                                   # Print utf32
     }

    Vmovdqu8 zmm0, "[".Rd(join ', ', $Lex->{lexicalLow} ->@*)."]";              # Each double is [31::24] Classification, [21::0] Utf32 start character
    Vmovdqu8 zmm1, "[".Rd(join ', ', $Lex->{lexicalHigh}->@*)."]";              # Each double is [31::24] Range offset,   [21::0] Utf32 end character

    ClassifyWithInRangeAndSaveOffset address=>$source32, size=>$sourceLength32; # Alphabetic classification
    if ($debug)
     {PrintOutStringNL "After classification into alphabet ranges";
      PrintUtf32($sourceLength32, $source32);                                   # Print classified utf32
     }

    Vmovdqu8 zmm0, "[".Rd(join ', ', $Lex->{bracketsLow} ->@*)."]";             # Each double is [31::24] Classification, [21::0] Utf32 start character
    Vmovdqu8 zmm1, "[".Rd(join ', ', $Lex->{bracketsHigh}->@*)."]";             # Each double is [31::24] Range offset,   [21::0] Utf32 end character

    ClassifyWithInRange address=>$source32, size=>$sourceLength32;              # Bracket classification
    if ($debug)
     {PrintOutStringNL "After classification into brackets";
      PrintUtf32($sourceLength32, $source32);                                   # Print classified brackets
     }

    my $opens = Vq(opens);
    MatchBrackets address=>$source32, size=>$sourceLength32, $opens, $$p{fail}; # Match brackets
    if ($debug)
     {PrintOutStringNL "After bracket matching";
      PrintUtf32($sourceLength32, $source32);                                   # Print matched brackets
     }

    ClassifyWhiteSpace address=>$source32, size=>$sourceLength32;               # Classify white space
    if ($debug)
     {PrintOutStringNL "After white space classification";
      PrintUtf32($sourceLength32, $source32);
     }

    ClassifyNewLines address=>$source32, size=>$sourceLength32;                 # Classify new lines
    if ($debug)
     {PrintOutStringNL "After classifying new lines";
      PrintUtf32($sourceLength32, $source32);
     }

    parseExpression source=>$source32, size=>$sourceLength32, $$p{parse};

    $$p{parse}->outNL if $debug;

    PopR @save;
   } in  => {address => 3, size => 3}, out => {parse => 3, fail => 3};

  $s->call(@parameters);
 } # parseUtf8

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

Parse a Unisyn expression.

=head1 Description

Generate X86 assembler code using Perl as a macro pre-processor.


Version "20210720".


The following sections describe the methods in each functional area of this
module.  For an alphabetic listing of all methods by name see L<Index|/Index>.



=head1 Parse

Parse Unisyn expressions

=head2 ClassifyNewLines(@parameters)

A new line acts a semi colon if it appears immediately after a variable.

     Parameter    Description
  1  @parameters  Parameters

=head2 ClassifyWhiteSpace(@parameters)

Classify white space per: lib/Unisyn/whiteSpace/whiteSpaceClassification.pl

     Parameter    Description
  1  @parameters  Parameters

=head2 lexicalNameFromLetter($l)

Lexical name for a lexical item described by its letter

     Parameter  Description
  1  $l         Letter of the lexical item

B<Example:>



    is_deeply lexicalNameFromLetter('a'), q(assign);  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    is_deeply lexicalNumberFromLetter('a'), $assign;


=head2 lexicalNumberFromLetter($l)

Lexical number for a lexical item described by its letter

     Parameter  Description
  1  $l         Letter of the lexical item

B<Example:>


    is_deeply lexicalNameFromLetter('a'), q(assign);

    is_deeply lexicalNumberFromLetter('a'), $assign;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲



=head2 new($depth, $description)

Create a new term

     Parameter     Description
  1  $depth        Stack depth to be converted
  2  $description  Text reason why we are creating a new term

B<Example:>


    Mov $index,  1;
    Mov rax,-1; Push rax;
    Mov rax, 3; Push rax;
    Mov rax, 2; Push rax;
    Mov rax, 1; Push rax;

    new 3, 'test';  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    Pop rax;  PrintOutRegisterInHex rax;
    Pop rax;  PrintOutRegisterInHex rax;
    ok Assemble(debug => 0, eq => <<END);
  New: test
      r8: 0000 0000 0000 0001
      r8: 0000 0000 0000 0002
      r8: 0000 0000 0000 0003
     rax: 0000 0000 0000 0009
     rax: FFFF FFFF FFFF FFFF
  END


=head2 error($message)

Die

     Parameter  Description
  1  $message   Error message

B<Example:>



    error "aaa bbbb";  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    ok Assemble(debug => 0, eq => <<END);
  Error: aaa bbbb
  Element:    r13: 0000 0000 0000 0000
  Index  :    r12: 0000 0000 0000 0000
  END


=head2 testSet($set, $register)

Test a set of items, setting the Zero Flag is one matches else clear the Zero flag

     Parameter  Description
  1  $set       Set of lexical letters
  2  $register  Register to test

B<Example:>


    Mov r15,  -1;
    Mov r15b, $term;

    testSet("ast", r15);  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    PrintOutZF;

    testSet("as",  r15);  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    PrintOutZF;
    ok Assemble(debug => 0, eq => <<END);
  ZF=1
  ZF=0
  END


=head2 checkSet($set)

Check that one of a set of items is on the top of the stack or complain if it is not

     Parameter  Description
  1  $set       Set of lexical letters

B<Example:>


    Mov r15,  -1;
    Mov r15b, $term;
    Push r15;

    checkSet("ast");  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    PrintOutZF;

    checkSet("as");  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    PrintOutZF;
    ok Assemble(debug => 0, eq => <<END);
  ZF=1
  Error: Expected one of: 'as' on the stack
  Element:    r13: 0000 0000 0000 0000
  Index  :    r12: 0000 0000 0000 0000
  END


=head2 reduce($priority)

Convert the longest possible expression on top of the stack into a term  at the specified priority

     Parameter  Description
  1  $priority  Priority of the operators to reduce

B<Example:>


    Mov r15,    -1;   Push r15;
    Mov r15, $term;   Push r15;
    Mov r15, $assign; Push r15;
    Mov r15, $term;   Push r15;

    reduce 1;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    Pop r15; PrintOutRegisterInHex r15;
    Pop r14; PrintOutRegisterInHex r14;
    ok Assemble(debug => 0, eq => <<END);
  Reduce 3:
      r8: 0000 0000 0000 0009
      r9: 0000 0000 0000 0005
     r10: 0000 0000 0000 0009
  New: Term infix term
      r8: 0000 0000 0000 0009
      r8: 0000 0000 0000 0009
      r8: 0000 0000 0000 0005
     r15: 0000 0000 0000 0009
     r14: FFFF FFFF FFFF FFFF
  END


=head2 parseExpression(@parameters)

Create a parser for an expression described by variables

     Parameter    Description
  1  @parameters  Parameters describing expression

B<Example:>


    my @p = my (  $out,    $size,   $opens,      $fail) =                         # Variables
               (Vq(out), Vq(size), Vq(opens), Vq('fail'));

    my $source = Rutf8 $$Lex{sampleText}{s1};                                     # String to be parsed in utf8
    my $sourceLength = StringLength Vq(string, $source);
       $sourceLength->outNL("Input  Length: ");

    ConvertUtf8ToUtf32 Vq(u8,$source), size8 => $sourceLength,                    # Convert to utf32
      (my $source32       = Vq(u32)),
      (my $sourceSize32   = Vq(size32)),
      (my $sourceLength32 = Vq(count));

    $sourceSize32   ->outNL("Output Length: ");                                   # Write output length

    PrintOutStringNL "After conversion from utf8 to utf32";
    PrintUtf32($sourceLength32, $source32);                                       # Print utf32

    Vmovdqu8 zmm0, "[".Rd(join ', ', $Lex->{lexicalLow} ->@*)."]";                # Each double is [31::24] Classification, [21::0] Utf32 start character
    Vmovdqu8 zmm1, "[".Rd(join ', ', $Lex->{lexicalHigh}->@*)."]";                # Each double is [31::24] Range offset,   [21::0] Utf32 end character

    ClassifyWithInRangeAndSaveOffset address=>$source32, size=>$sourceLength32;   # Alphabetic classification
    PrintOutStringNL "After classification into alphabet ranges";
    PrintUtf32($sourceLength32, $source32);                                       # Print classified utf32

    Vmovdqu8 zmm0, "[".Rd(join ', ', $Lex->{bracketsLow} ->@*)."]";               # Each double is [31::24] Classification, [21::0] Utf32 start character
    Vmovdqu8 zmm1, "[".Rd(join ', ', $Lex->{bracketsHigh}->@*)."]";               # Each double is [31::24] Range offset,   [21::0] Utf32 end character

    ClassifyWithInRange address=>$source32, size=>$sourceLength32;                # Bracket matching
    PrintOutStringNL "After classification into brackets";
    PrintUtf32($sourceLength32, $source32);                                       # Print classified brackets

    MatchBrackets address=>$source32, size=>$sourceLength32, $opens, $fail;       # Match brackets
    PrintOutStringNL "After bracket matching";
    PrintUtf32($sourceLength32, $source32);                                       # Print matched brackets

    ClassifyWhiteSpace address=>$source32, size=>$sourceLength32;                 # Classify white space
  #  PrintOutStringNL "After classifying white space";
    PrintUtf32($sourceLength32, $source32);                                       # Print matched brackets


    parseExpression source=>$source32, size=>$sourceLength32, my $parse = Vq(parse);  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    $parse->outNL();

    ok Assemble(debug => 0, eq => <<END);
  Input  Length: 0000 0000 0000 0010
  Output Length: 0000 0000 0000 0040
  After conversion from utf8 to utf32
  0001 D5EE 0001 D44E  0000 000A 0000 0020  0000 0020 0000 0041  0000 000A 0000 0020  0000 0020 0000 0020
  After classification into alphabet ranges
  0600 001A 0500 001A  0200 000A 0200 0020  0200 0020 0200 0041  0200 000A 0200 0020  0200 0020 0200 0020
  After classification into brackets
  0600 001A 0500 001A  0200 000A 0200 0020  0200 0020 0200 0041  0200 000A 0200 0020  0200 0020 0200 0020
  After bracket matching
  0600 001A 0500 001A  0200 000A 0200 0020  0200 0020 0200 0041  0200 000A 0200 0020  0200 0020 0200 0020
  0600 001A 0500 001A  0B00 000A 0200 0020  0200 0020 0200 0041  0200 000A 0B00 0020  0B00 0020 0B00 0020
  Push Element:
     r13: 0000 0000 0000 0006
  New: accept initial variable
      r8: 0000 0000 0000 0006
     r13: 0000 0001 0000 0005
  accept a
  Push Element:
     r13: 0000 0001 0000 0005
     r13: 0000 0002 0000 000B
     r13: 0000 0003 0000 0006
  accept v
  Push Element:
     r13: 0000 0003 0000 0006
  New: Variable
      r8: 0000 0003 0000 0006
     r13: 0000 0004 0000 0006
     r13: 0000 0005 0000 0006
     r13: 0000 0006 0000 0006
     r13: 0000 0007 0000 000B
     r13: 0000 0008 0000 000B
     r13: 0000 0009 0000 000B
  Reduce 3:
      r8: 0000 0000 0000 0009
      r9: 0000 0001 0000 0005
     r10: 0000 0000 0000 0009
  New: Term infix term
      r8: 0000 0000 0000 0009
      r8: 0000 0000 0000 0009
      r8: 0000 0001 0000 0005
  parse: 0000 0000 0000 0009
  END



=head1 Private Methods

=head2 loadCurrentChar()

Load the details of the character currently being processed


=head2 checkStackHas($depth)

Check that we have at least the specified number of elements on the stack

     Parameter  Description
  1  $depth     Number of elements required on the stack

B<Example:>


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
     r13: 0000 0000 0000 0000
     r13: 0000 0000 0000 0001
     r13: 0000 0000 0000 0006
     r13: 0000 0000 0000 0006
     r13: 0000 0000 0000 0008
     r13: 0000 0000 0000 0008
  END

    Push rbp;
    Mov rbp, rsp;
    Push rax;
    Push rax;

    checkStackHas 2;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    IfEq {PrintOutStringNL "ok"} sub {PrintOutStringNL "fail"};

    checkStackHas 2;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    IfGe {PrintOutStringNL "ok"} sub {PrintOutStringNL "fail"};

    checkStackHas 2;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    IfGt {PrintOutStringNL "fail"} sub {PrintOutStringNL "ok"};
    Push rax;

    checkStackHas 3;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    IfEq {PrintOutStringNL "ok"} sub {PrintOutStringNL "fail"};

    checkStackHas 3;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    IfGe {PrintOutStringNL "ok"} sub {PrintOutStringNL "fail"};

    checkStackHas 3;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    IfGt {PrintOutStringNL "fail"} sub {PrintOutStringNL "ok"};

    ok Assemble(debug => 0, eq => <<END);
  ok
  ok
  ok
  ok
  ok
  ok
  END


=head2 pushElement()

Push the current element on to the stack


=head2 pushEmpty()

Push the empty element on to the stack


B<Example:>


    Mov $index, 1;

    pushEmpty;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    Mov rax, "[rsp]";
    PrintOutRegisterInHex rax;
    ok Assemble(debug => 0, eq => <<END);
  Push Empty
     rax: 0000 0001 0000 000A
  END


=head2 reduceMultiple($priority)

Reduce existing operators on the stack

     Parameter  Description
  1  $priority  Priority of the operators to reduce

B<Example:>


    Mov r15,           -1;  Push r15;
    Mov r15, $OpenBracket;  Push r15;

    reduceMultiple 1;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    Pop r15; PrintOutRegisterInHex r15;
    Pop r14; PrintOutRegisterInHex r14;
    ok Assemble(debug => 0, eq => <<END);
  Reduce 2:
      r8: 0000 0000 0000 0010
      r9: 0000 0000 0000 0000
     r15: 0000 0000 0000 0000
     r14: FFFF FFFF FFFF FFFF
  END


=head2 accept_a()

Assign


=head2 accept_b()

Open


=head2 accept_B()

Closing parenthesis


=head2 accept_d()

Infix but not assign or semi-colon


=head2 accept_p()

Prefix


=head2 accept_q()

Post fix


=head2 accept_s()

Semi colon


=head2 accept_v()

Variable


=head2 parseExpressionCode()

Parse the string of classified lexicals addressed by register $start of length $length.  The resulting parse tree (if any) is returned in r15.



=head1 Index


1 L<accept_a|/accept_a> - Assign

2 L<accept_B|/accept_B> - Closing parenthesis

3 L<accept_b|/accept_b> - Open

4 L<accept_d|/accept_d> - Infix but not assign or semi-colon

5 L<accept_p|/accept_p> - Prefix

6 L<accept_q|/accept_q> - Post fix

7 L<accept_s|/accept_s> - Semi colon

8 L<accept_v|/accept_v> - Variable

9 L<checkSet|/checkSet> - Check that one of a set of items is on the top of the stack or complain if it is not

10 L<checkStackHas|/checkStackHas> - Check that we have at least the specified number of elements on the stack

11 L<ClassifyNewLines|/ClassifyNewLines> - A new line acts a semi colon if it appears immediately after a variable.

12 L<ClassifyWhiteSpace|/ClassifyWhiteSpace> - Classify white space per: lib/Unisyn/whiteSpace/whiteSpaceClassification.

13 L<error|/error> - Die

14 L<lexicalNameFromLetter|/lexicalNameFromLetter> - Lexical name for a lexical item described by its letter

15 L<lexicalNumberFromLetter|/lexicalNumberFromLetter> - Lexical number for a lexical item described by its letter

16 L<loadCurrentChar|/loadCurrentChar> - Load the details of the character currently being processed

17 L<new|/new> - Create a new term

18 L<parseExpression|/parseExpression> - Create a parser for an expression described by variables

19 L<parseExpressionCode|/parseExpressionCode> - Parse the string of classified lexicals addressed by register $start of length $length.

20 L<pushElement|/pushElement> - Push the current element on to the stack

21 L<pushEmpty|/pushEmpty> - Push the empty element on to the stack

22 L<reduce|/reduce> - Convert the longest possible expression on top of the stack into a term  at the specified priority

23 L<reduceMultiple|/reduceMultiple> - Reduce existing operators on the stack

24 L<testSet|/testSet> - Test a set of items, setting the Zero Flag is one matches else clear the Zero flag

=head1 Installation

This module is written in 100% Pure Perl and, thus, it is easy to read,
comprehend, use, modify and install via B<cpan>:

  sudo cpan install Unisyn::Parse

=head1 Author

L<philiprbrenan@gmail.com|mailto:philiprbrenan@gmail.com>

L<http://www.appaapps.com|http://www.appaapps.com>

=head1 Copyright

Copyright (c) 2016-2021 Philip R Brenan.

This module is free software. It may be used, redistributed and/or modified
under the same terms as Perl itself.

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
__DATA__
use Time::HiRes qw(time);
use Test::More;

my $localTest = ((caller(1))[0]//'Unisyn::Parse') eq "Unisyn::Parse";           # Local testing mode

Test::More->builder->output("/dev/null") if $localTest;                         # Reduce number of confirmation messages during testing

if ($^O =~ m(bsd|linux|cygwin)i)                                                # Supported systems
 {if (confirmHasCommandLineCommand(q(nasm)) and LocateIntelEmulator)            # Network assembler and Intel Software Development emulator
   {plan tests => 99;
   }
  else
   {plan skip_all => qq(Nasm or Intel 64 emulator not available);
   }
 }
else
 {plan skip_all => qq(Not supported on: $^O);
 }

my $startTime = time;                                                           # Tests

   $debug     = 1;                                                              # Debug during testing so we can follow actions on the stack

eval {goto latest} if !caller(0) and -e "/home/phil";                           # Go to latest test if specified

sub T($$)                                                                       # Test a parse
 {my ($key, $expected) = @_;                                                    # Key of text to be parsed, expected result
  my $source  = $$Lex{sampleText}{$key};                                        # String to be parsed in utf8
  defined $source or confess;
  my $address = Rutf8 $source;
  my $size    = StringLength Vq(string, $address);
  my $fail  = Vq('fail');
  my $parse = Vq('parse');

  parseUtf8  Vq(address, $address),  $size, $fail, $parse;                      # Parse

  Assemble(debug => 0, eq => $expected);
 }

if (1) {                                                                        # Double words get expanded to quads
  my $q = Rb(1..8);
  Mov rax, "[$q];";
  Mov r8, rax;
  Shl r8d, 16;
  PrintOutRegisterInHex rax, r8;

  ok Assemble(debug => 0, eq => <<END);
   rax: 0807 0605 0403 0201
    r8: 0000 0000 0201 0000
END
 }

if (1) {                                                                        #TcheckStackHas
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
   r13: 0000 0000 0000 0000
   r13: 0000 0000 0000 0001
   r13: 0000 0000 0000 0006
   r13: 0000 0000 0000 0006
   r13: 0000 0000 0000 0008
   r13: 0000 0000 0000 0008
END
 }

#latest:;
if (1) {                                                                        #TcheckStackHas
  Push rbp;
  Mov rbp, rsp;
  Push rax;
  Push rax;
  checkStackHas 2;
  IfEq {PrintOutStringNL "ok"} sub {PrintOutStringNL "fail"};
  checkStackHas 2;
  IfGe {PrintOutStringNL "ok"} sub {PrintOutStringNL "fail"};
  checkStackHas 2;
  IfGt {PrintOutStringNL "fail"} sub {PrintOutStringNL "ok"};
  Push rax;
  checkStackHas 3;
  IfEq {PrintOutStringNL "ok"} sub {PrintOutStringNL "fail"};
  checkStackHas 3;
  IfGe {PrintOutStringNL "ok"} sub {PrintOutStringNL "fail"};
  checkStackHas 3;
  IfGt {PrintOutStringNL "fail"} sub {PrintOutStringNL "ok"};

  ok Assemble(debug => 0, eq => <<END);
ok
ok
ok
ok
ok
ok
END
 }

#latest:;
if (1) {                                                                        #TpushEmpty
  Mov $index, 1;
  pushEmpty;
  Mov rax, "[rsp]";
  PrintOutRegisterInHex rax;
  ok Assemble(debug => 0, eq => <<END);
Push Empty
   rax: 0000 0001 0000 000A
END
 }

#latest:;
if (1) {                                                                        #TlexicalNameFromLetter #TlexicalNumberFromLetter
  is_deeply lexicalNameFromLetter('a'), q(assign);
  is_deeply lexicalNumberFromLetter('a'), $assign;
 }

#latest:;
if (1) {                                                                        #Tnew
  Mov $index,  1;
  Mov rax,-1; Push rax;
  Mov rax, 3; Push rax;
  Mov rax, 2; Push rax;
  Mov rax, 1; Push rax;
  new 3, 'test';
  Pop rax;  PrintOutRegisterInHex rax;
  Pop rax;  PrintOutRegisterInHex rax;
  ok Assemble(debug => 0, eq => <<END);
New: test
    r8: 0000 0000 0000 0001
    r8: 0000 0000 0000 0002
    r8: 0000 0000 0000 0003
   rax: 0000 0000 0000 0009
   rax: FFFF FFFF FFFF FFFF
END
 }

#latest:;
if (1) {                                                                        #Terror
  error "aaa bbbb";
  ok Assemble(debug => 0, eq => <<END);
Error: aaa bbbb
Element:    r13: 0000 0000 0000 0000
Index  :    r12: 0000 0000 0000 0000
END
 }

#latest:;
if (1) {                                                                        #TtestSet
  Mov r15,  -1;
  Mov r15b, $term;
  testSet("ast", r15);
  PrintOutZF;
  testSet("as",  r15);
  PrintOutZF;
  ok Assemble(debug => 0, eq => <<END);
ZF=1
ZF=0
END
 }

#latest:;
if (1) {                                                                        #TcheckSet
  Mov r15,  -1;
  Mov r15b, $term;
  Push r15;
  checkSet("ast");
  PrintOutZF;
  checkSet("as");
  PrintOutZF;
  ok Assemble(debug => 0, eq => <<END);
ZF=1
Error: Expected one of: 'as' on the stack
Element:    r13: 0000 0000 0000 0000
Index  :    r12: 0000 0000 0000 0000
END
 }

#latest:;
if (1) {                                                                        #Treduce
  Mov r15,    -1;   Push r15;
  Mov r15, $term;   Push r15;
  Mov r15, $assign; Push r15;
  Mov r15, $term;   Push r15;
  reduce 1;
  Pop r15; PrintOutRegisterInHex r15;
  Pop r14; PrintOutRegisterInHex r14;
  ok Assemble(debug => 0, eq => <<END);
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 0000 0000 0005
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0005
   r15: 0000 0000 0000 0009
   r14: FFFF FFFF FFFF FFFF
END
 }

#latest:;
if (1) {                                                                        #TreduceMultiple
  Mov r15,           -1;  Push r15;
  Mov r15, $OpenBracket;  Push r15;
  reduceMultiple 1;
  Pop r15; PrintOutRegisterInHex r15;
  Pop r14; PrintOutRegisterInHex r14;
  ok Assemble(debug => 0, eq => <<END);
Reduce 2:
    r8: 0000 0000 0000 0010
    r9: 0000 0000 0000 0000
   r15: 0000 0000 0000 0000
   r14: FFFF FFFF FFFF FFFF
END
 }

#latest:;
if (1) {
  Mov r15,           -1;  Push r15;
  Mov r15, $OpenBracket;  Push r15;
  Mov r15, $term;         Push r15;
  Mov r15, $CloseBracket; Push r15;
  reduceMultiple 1;
  Pop r15; PrintOutRegisterInHex r15;
  Pop r14; PrintOutRegisterInHex r14;
  ok Assemble(debug => 0, eq => <<END);
Reduce 3:
    r8: 0000 0000 0000 0000
    r9: 0000 0000 0000 0009
   r10: 0000 0000 0000 0001
Reduce by ( term )
Reduce 2:
    r8: 0000 0000 0000 0010
    r9: 0000 0000 0000 0009
   r15: 0000 0000 0000 0009
   r14: FFFF FFFF FFFF FFFF
END
 }

#latest:;
if (1) {
  Mov r15,      -1;  Push r15;
  Mov r15, $prefix;  Push r15;
  Mov r15, $prefix;  Push r15;
  Mov r15, $prefix;  Push r15;
  Mov $element, $variable;
  accept_v;
  Pop r15; PrintOutRegisterInHex r15;
  Pop r14; PrintOutRegisterInHex r14;
  ok Assemble(debug => 0, eq => <<END);
accept v
Push Element:
   r13: 0000 0000 0000 0006
New: Variable
    r8: 0000 0000 0000 0006
New: Prefixed variable
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0004
New: Prefixed variable
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0004
New: Prefixed variable
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0004
   r15: 0000 0000 0000 0009
   r14: FFFF FFFF FFFF FFFF
END
 }

#latest:;
if (1) {
  my $l = $Lex->{sampleLexicals}{v};
  Mov $start,  Rd(@$l);
  Mov $size,   scalar(@$l);
  parseExpressionCode;
  PrintOutStringNL "Result:";
  PrintOutRegisterInHex r15;
  ok Assemble(debug => 0, eq => <<END);
Push Element:
   r13: 0000 0000 0000 0006
New: accept initial variable
    r8: 0000 0000 0000 0006
Result:
   r15: 0000 0000 0000 0009
END
 }

#latest:;
if (1) {
  my $l = $Lex->{sampleLexicals}{vav};
  Mov $start,  Rd(@$l);
  Mov $size,   scalar(@$l);

  parseExpressionCode;
  PrintOutStringNL "Result:";
  PrintOutRegisterInHex r15;
  ok Assemble(debug => 0, eq => <<END);
Push Element:
   r13: 0000 0000 0000 0006
New: accept initial variable
    r8: 0000 0000 0000 0006
   r13: 0000 0001 0000 0005
accept a
Push Element:
   r13: 0000 0001 0000 0005
   r13: 0000 0002 0000 0006
accept v
Push Element:
   r13: 0000 0002 0000 0006
New: Variable
    r8: 0000 0002 0000 0006
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 0001 0000 0005
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 0001 0000 0005
Result:
   r15: 0000 0000 0000 0009
END
 }

#latest:;
if (1) {
  my $l = $Lex->{sampleLexicals}{brackets};

  Mov $start,  Rd(@$l);
  Mov $size,   scalar(@$l);

  parseExpressionCode;
  PrintOutStringNL "Result:";
  PrintOutRegisterInHex r15;
  ok Assemble(debug => 0, eq => <<END);
Push Element:
   r13: 0000 0000 0000 0006
New: accept initial variable
    r8: 0000 0000 0000 0006
   r13: 0000 0001 0000 0005
accept a
Push Element:
   r13: 0000 0001 0000 0005
   r13: 0000 0002 0000 0000
accept b
Push Element:
   r13: 0000 0002 0000 0000
   r13: 0000 0003 0000 0000
accept b
Push Element:
   r13: 0000 0003 0000 0000
   r13: 0000 0004 0000 0000
accept b
Push Element:
   r13: 0000 0004 0000 0000
   r13: 0000 0005 0000 0006
accept v
Push Element:
   r13: 0000 0005 0000 0006
New: Variable
    r8: 0000 0005 0000 0006
   r13: 0000 0006 0000 0001
accept B
Reduce 3:
    r8: 0000 0003 0000 0000
    r9: 0000 0004 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0030
    r9: 0000 0004 0000 0000
Push Element:
   r13: 0000 0006 0000 0001
Reduce 3:
    r8: 0000 0004 0000 0000
    r9: 0000 0000 0000 0009
   r10: 0000 0006 0000 0001
Reduce by ( term )
Reduce 3:
    r8: 0000 0002 0000 0000
    r9: 0000 0003 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0028
    r9: 0000 0003 0000 0000
   r13: 0000 0007 0000 0001
accept B
Reduce 3:
    r8: 0000 0002 0000 0000
    r9: 0000 0003 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0028
    r9: 0000 0003 0000 0000
Push Element:
   r13: 0000 0007 0000 0001
Reduce 3:
    r8: 0000 0003 0000 0000
    r9: 0000 0000 0000 0009
   r10: 0000 0007 0000 0001
Reduce by ( term )
Reduce 3:
    r8: 0000 0001 0000 0005
    r9: 0000 0002 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0020
    r9: 0000 0002 0000 0000
   r13: 0000 0008 0000 0003
accept d
Push Element:
   r13: 0000 0008 0000 0003
   r13: 0000 0009 0000 0000
accept b
Push Element:
   r13: 0000 0009 0000 0000
   r13: 0000 000A 0000 0006
accept v
Push Element:
   r13: 0000 000A 0000 0006
New: Variable
    r8: 0000 000A 0000 0006
   r13: 0000 000B 0000 0001
accept B
Reduce 3:
    r8: 0000 0008 0000 0003
    r9: 0000 0009 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0038
    r9: 0000 0009 0000 0000
Push Element:
   r13: 0000 000B 0000 0001
Reduce 3:
    r8: 0000 0009 0000 0000
    r9: 0000 0000 0000 0009
   r10: 0000 000B 0000 0001
Reduce by ( term )
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 0008 0000 0003
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 0008 0000 0003
Reduce 3:
    r8: 0000 0001 0000 0005
    r9: 0000 0002 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0020
    r9: 0000 0002 0000 0000
   r13: 0000 000C 0000 0001
accept B
Reduce 3:
    r8: 0000 0001 0000 0005
    r9: 0000 0002 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0020
    r9: 0000 0002 0000 0000
Push Element:
   r13: 0000 000C 0000 0001
Reduce 3:
    r8: 0000 0002 0000 0000
    r9: 0000 0000 0000 0009
   r10: 0000 000C 0000 0001
Reduce by ( term )
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 0001 0000 0005
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 0001 0000 0005
   r13: 0000 000D 0000 0008
accept s
Push Element:
   r13: 0000 000D 0000 0008
Result:
   r15: 0000 0000 0000 0009
END
 }

#latest:
ok T(q(s1), <<END);
ParseUtf8
After conversion from utf8 to utf32
Output Length: 0000 0000 0000 0040
0001 D5EE 0001 D44E  0000 000A 0000 0020  0000 0020 0000 0041  0000 000A 0000 0020  0000 0020 0000 0020
After classification into alphabet ranges
0600 001A 0500 001A  0200 000A 0200 0020  0200 0020 0200 0041  0200 000A 0200 0020  0200 0020 0200 0020
After classification into brackets
0600 001A 0500 001A  0200 000A 0200 0020  0200 0020 0200 0041  0200 000A 0200 0020  0200 0020 0200 0020
After bracket matching
0600 001A 0500 001A  0200 000A 0200 0020  0200 0020 0200 0041  0200 000A 0200 0020  0200 0020 0200 0020
After white space classification
0600 001A 0500 001A  0B00 000A 0200 0020  0200 0020 0200 0041  0200 000A 0B00 0020  0B00 0020 0B00 0020
After classifying new lines
0600 001A 0500 001A  0B00 000A 0200 0020  0200 0020 0200 0041  0200 000A 0B00 0020  0B00 0020 0B00 0020
Push Element:
   r13: 0000 0000 0000 0006
New: accept initial variable
    r8: 0000 0000 0000 0006
   r13: 0000 0001 0000 0005
accept a
Push Element:
   r13: 0000 0001 0000 0005
   r13: 0000 0002 0000 000B
   r13: 0000 0003 0000 0006
accept v
Push Element:
   r13: 0000 0003 0000 0006
New: Variable
    r8: 0000 0003 0000 0006
   r13: 0000 0004 0000 0006
   r13: 0000 0005 0000 0006
   r13: 0000 0006 0000 0006
   r13: 0000 0007 0000 000B
   r13: 0000 0008 0000 000B
   r13: 0000 0009 0000 000B
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 0001 0000 0005
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 0001 0000 0005
parse: 0000 0000 0000 0009
END

ok T(q(vnv), <<END);
ParseUtf8
After conversion from utf8 to utf32
Output Length: 0000 0000 0000 0024
0001 D5EE 0000 000A
After classification into alphabet ranges
0600 001A 0200 000A
After classification into brackets
0600 001A 0200 000A
After bracket matching
0600 001A 0200 000A
After white space classification
0600 001A 0B00 000A
After classifying new lines
0600 001A 0C00 000A
Push Element:
   r13: 0000 0000 0000 0006
New: accept initial variable
    r8: 0000 0000 0000 0006
   r13: 0000 0001 0000 0008
accept s
Push Element:
   r13: 0000 0001 0000 0008
   r13: 0000 0002 0000 0006
accept v
Push Element:
   r13: 0000 0002 0000 0006
New: Variable
    r8: 0000 0002 0000 0006
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 0001 0000 0008
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 0001 0000 0008
parse: 0000 0000 0000 0009
END

#latest:
ok T(q(vnvs), <<END);
ParseUtf8
After conversion from utf8 to utf32
Output Length: 0000 0000 0000 0034
0001 D5EE 0000 000A  0001 D5EF 0000 0020  0000 0020 0000 0020
After classification into alphabet ranges
0600 001A 0200 000A  0600 001B 0200 0020  0200 0020 0200 0020
After classification into brackets
0600 001A 0200 000A  0600 001B 0200 0020  0200 0020 0200 0020
After bracket matching
0600 001A 0200 000A  0600 001B 0200 0020  0200 0020 0200 0020
After white space classification
0600 001A 0B00 000A  0600 001B 0B00 0020  0B00 0020 0B00 0020
After classifying new lines
0600 001A 0C00 000A  0600 001B 0B00 0020  0B00 0020 0B00 0020
Push Element:
   r13: 0000 0000 0000 0006
New: accept initial variable
    r8: 0000 0000 0000 0006
   r13: 0000 0001 0000 0008
accept s
Push Element:
   r13: 0000 0001 0000 0008
   r13: 0000 0002 0000 0006
accept v
Push Element:
   r13: 0000 0002 0000 0006
New: Variable
    r8: 0000 0002 0000 0006
   r13: 0000 0003 0000 000B
   r13: 0000 0004 0000 000B
   r13: 0000 0005 0000 000B
   r13: 0000 0006 0000 000B
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 0001 0000 0008
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 0001 0000 0008
parse: 0000 0000 0000 0009
END

#latest:
ok T(q(vnsvs), <<END);
ParseUtf8
After conversion from utf8 to utf32
Output Length: 0000 0000 0000 005C
0001 D5EE 0001 D5EE  0000 000A 0000 0020  0000 0020 0000 0020  0001 D5EF 0001 D5EF  0000 0020 0000 0020
After classification into alphabet ranges
0600 001A 0600 001A  0200 000A 0200 0020  0200 0020 0200 0020  0600 001B 0600 001B  0200 0020 0200 0020
After classification into brackets
0600 001A 0600 001A  0200 000A 0200 0020  0200 0020 0200 0020  0600 001B 0600 001B  0200 0020 0200 0020
After bracket matching
0600 001A 0600 001A  0200 000A 0200 0020  0200 0020 0200 0020  0600 001B 0600 001B  0200 0020 0200 0020
After white space classification
0600 001A 0600 001A  0B00 000A 0B00 0020  0B00 0020 0B00 0020  0600 001B 0600 001B  0B00 0020 0B00 0020
After classifying new lines
0600 001A 0600 001A  0C00 000A 0B00 0020  0B00 0020 0B00 0020  0600 001B 0600 001B  0B00 0020 0B00 0020
Push Element:
   r13: 0000 0000 0000 0006
New: accept initial variable
    r8: 0000 0000 0000 0006
   r13: 0000 0001 0000 0006
   r13: 0000 0002 0000 0008
accept s
Push Element:
   r13: 0000 0002 0000 0008
   r13: 0000 0003 0000 000B
   r13: 0000 0004 0000 000B
   r13: 0000 0005 0000 000B
   r13: 0000 0006 0000 0006
accept v
Push Element:
   r13: 0000 0006 0000 0006
New: Variable
    r8: 0000 0006 0000 0006
   r13: 0000 0007 0000 0006
   r13: 0000 0008 0000 000B
   r13: 0000 0009 0000 000B
   r13: 0000 000A 0000 000B
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 0002 0000 0008
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 0002 0000 0008
parse: 0000 0000 0000 0009
END

#latest:
ok T(q(brackets), <<END);
ParseUtf8
After conversion from utf8 to utf32
Output Length: 0000 0000 0000 015C
0001 D5EE 0001 D44E  0001 D460 0001 D460  0001 D456 0001 D454  0001 D45B 0000 230A  0000 2329 0000 2768  0001 D5EF 0001 D5FD  0000 2769 0000 232A  0001 D429 0001 D425
0001 D42E 0001 D42C  0000 276A 0001 D600  0001 D5F0 0000 276B  0000 230B 0000 27E2
After classification into alphabet ranges
0600 001A 0500 001A  0500 002C 0500 002C  0500 0022 0500 0020  0500 0027 0000 230A  0000 2329 0000 2768  0600 001B 0600 0029  0000 2769 0000 232A  0300 0029 0300 0025
0300 002E 0300 002C  0000 276A 0600 002C  0600 001C 0000 276B  0000 230B 0800 0000
After classification into brackets
0600 001A 0500 001A  0500 002C 0500 002C  0500 0022 0500 0020  0500 0027 1200 230A  1400 2329 1600 2768  0600 001B 0600 0029  1700 2769 1500 232A  0300 0029 0300 0025
0300 002E 0300 002C  1800 276A 0600 002C  0600 001C 1900 276B  1300 230B 0800 0000
After bracket matching
0600 001A 0500 001A  0500 002C 0500 002C  0500 0022 0500 0020  0500 0027 1200 0016  1400 000D 1600 000C  0600 001B 0600 0029  1700 0009 1500 0008  0300 0029 0300 0025
0300 002E 0300 002C  1800 0015 0600 002C  0600 001C 1900 0012  1300 0007 0800 0000
After white space classification
0600 001A 0500 001A  0500 002C 0500 002C  0500 0022 0500 0020  0500 0027 1200 0016  1400 000D 1600 000C  0600 001B 0600 0029  1700 0009 1500 0008  0300 0029 0300 0025
0300 002E 0300 002C  1800 0015 0600 002C  0600 001C 1900 0012  1300 0007 0800 0000
After classifying new lines
0600 001A 0500 001A  0500 002C 0500 002C  0500 0022 0500 0020  0500 0027 1200 0016  1400 000D 1600 000C  0600 001B 0600 0029  1700 0009 1500 0008  0300 0029 0300 0025
0300 002E 0300 002C  1800 0015 0600 002C  0600 001C 1900 0012  1300 0007 0800 0000
Push Element:
   r13: 0000 0000 0000 0006
New: accept initial variable
    r8: 0000 0000 0000 0006
   r13: 0000 0001 0000 0005
accept a
Push Element:
   r13: 0000 0001 0000 0005
   r13: 0000 0002 0000 0005
   r13: 0000 0003 0000 0005
   r13: 0000 0004 0000 0005
   r13: 0000 0005 0000 0005
   r13: 0000 0006 0000 0005
   r13: 0000 0007 0000 0000
accept b
Push Element:
   r13: 0000 0007 0000 0000
   r13: 0000 0008 0000 0000
accept b
Push Element:
   r13: 0000 0008 0000 0000
   r13: 0000 0009 0000 0000
accept b
Push Element:
   r13: 0000 0009 0000 0000
   r13: 0000 000A 0000 0006
accept v
Push Element:
   r13: 0000 000A 0000 0006
New: Variable
    r8: 0000 000A 0000 0006
   r13: 0000 000B 0000 0006
   r13: 0000 000C 0000 0001
accept B
Reduce 3:
    r8: 0000 0008 0000 0000
    r9: 0000 0009 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0030
    r9: 0000 0009 0000 0000
Push Element:
   r13: 0000 000C 0000 0001
Reduce 3:
    r8: 0000 0009 0000 0000
    r9: 0000 0000 0000 0009
   r10: 0000 000C 0000 0001
Reduce by ( term )
Reduce 3:
    r8: 0000 0007 0000 0000
    r9: 0000 0008 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0028
    r9: 0000 0008 0000 0000
   r13: 0000 000D 0000 0001
accept B
Reduce 3:
    r8: 0000 0007 0000 0000
    r9: 0000 0008 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0028
    r9: 0000 0008 0000 0000
Push Element:
   r13: 0000 000D 0000 0001
Reduce 3:
    r8: 0000 0008 0000 0000
    r9: 0000 0000 0000 0009
   r10: 0000 000D 0000 0001
Reduce by ( term )
Reduce 3:
    r8: 0000 0001 0000 0005
    r9: 0000 0007 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0020
    r9: 0000 0007 0000 0000
   r13: 0000 000E 0000 0003
accept d
Push Element:
   r13: 0000 000E 0000 0003
   r13: 0000 000F 0000 0003
   r13: 0000 0010 0000 0003
   r13: 0000 0011 0000 0003
   r13: 0000 0012 0000 0000
accept b
Push Element:
   r13: 0000 0012 0000 0000
   r13: 0000 0013 0000 0006
accept v
Push Element:
   r13: 0000 0013 0000 0006
New: Variable
    r8: 0000 0013 0000 0006
   r13: 0000 0014 0000 0006
   r13: 0000 0015 0000 0001
accept B
Reduce 3:
    r8: 0000 000E 0000 0003
    r9: 0000 0012 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0038
    r9: 0000 0012 0000 0000
Push Element:
   r13: 0000 0015 0000 0001
Reduce 3:
    r8: 0000 0012 0000 0000
    r9: 0000 0000 0000 0009
   r10: 0000 0015 0000 0001
Reduce by ( term )
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 000E 0000 0003
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 000E 0000 0003
Reduce 3:
    r8: 0000 0001 0000 0005
    r9: 0000 0007 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0020
    r9: 0000 0007 0000 0000
   r13: 0000 0016 0000 0001
accept B
Reduce 3:
    r8: 0000 0001 0000 0005
    r9: 0000 0007 0000 0000
   r10: 0000 0000 0000 0009
Reduce 2:
    r8: 0000 0000 0000 0020
    r9: 0000 0007 0000 0000
Push Element:
   r13: 0000 0016 0000 0001
Reduce 3:
    r8: 0000 0007 0000 0000
    r9: 0000 0000 0000 0009
   r10: 0000 0016 0000 0001
Reduce by ( term )
Reduce 3:
    r8: 0000 0000 0000 0009
    r9: 0000 0001 0000 0005
   r10: 0000 0000 0000 0009
New: Term infix term
    r8: 0000 0000 0000 0009
    r8: 0000 0000 0000 0009
    r8: 0000 0001 0000 0005
   r13: 0000 0017 0000 0008
accept s
Push Element:
   r13: 0000 0017 0000 0008
parse: 0000 0000 0000 0009
END

#latest:
ok T(q(brackets), <<END) if 0;
ParseUtf8
END

#latest:
ok T(q(brackets), <<END) if 0;
ParseUtf8
END

ok 1 for 23..99;

unlink $_ for qw(hash print2 sde-log.txt sde-ptr-check.out.txt z.txt);          # Remove incidental files

lll "Finished:", time - $startTime;
