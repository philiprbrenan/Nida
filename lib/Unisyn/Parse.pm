#!/usr/bin/perl -I/home/phil/perl/cpan/DataTableText/lib/ -I/home/phil/perl/cpan/NasmX86/lib/ -I/home/phil/perl/cpan/AsmC/lib/
#-------------------------------------------------------------------------------
# Parse a Unisyn expression.
# Philip R Brenan at appaapps dot com, Appa Apps Ltd Inc., 2021
#-------------------------------------------------------------------------------
# podDocumentation
# Finished in 13.14s, bytes: 2,655,008, execs: 465,858
# Can we remove more Pushr  by doing one big save in parseutf8 ?
package Unisyn::Parse;
our $VERSION = "20211013";
use warnings FATAL => qw(all);
use strict;
use Carp qw(confess cluck);
use Data::Dump qw(dump);
use Data::Table::Text qw(:all !parse);
use Nasm::X86 qw(:all);
use feature qw(say current_sub);
use utf8;

makeDieConfess;

my  $develop    = -e q(/home/phil/);                                            # Developing
our $Parse;                                                                     # One of the advantages of creating a parse tree is that we can perform parse one at a time making it safe to globalize this variable. The alternative is to pass this variable between all the parsing calls which would obscure their workings greatly.
our $ParseUtf8SubDef;                                                           # The definition of the subroutine that does the parsing so that we can reuse its parameters when we call L<new>.
our $debug      = 0;                                                            # Print evolution of stack if true.

#D1 Create                                                                      # Create a Unisyn parse of a utf8 string.

sub create($%)                                                                  # Create a new unisyn parse from a utf8 string.
 {my ($address, %options) = @_;                                                 # Address of a zero terminated utf8 source string to parse as a variable, parse options.
  @_ >= 1 or confess "One or more parameters";

  my $a    = CreateArena;                                                       # Arena to hold parse tree - every parse tree gets its own arena so that we can free parses separately
  my $size = StringLength string => $address;                                   # Length of input utf8

  my $p = $Parse   = genHash(__PACKAGE__,                                       # Description of parse
    arena          => $a,                                                       # Arena containing tree
    size8          => $size,                                                    # Size of source string as utf8
    address8       => $address,                                                 # Address of source string as utf8
    source32       => V(source32),                                              # Source text as utf32
    sourceSize32   => V(sourceSize32),                                          # Size of utf32 allocation
    sourceLength32 => V(sourceLength32),                                        # Length of utf32 string
    parse          => V('parse'),                                               # Offset to the head of the parse tree
    fails          => V('fail'),                                                # Number of failures encountered in this parse
    quarks         => $a->CreateQuarks,                                         # Quarks representing the strings used in this parse
    operators      => undef,                                                    # Methods implementing each lexical operator
    width          => RegisterSize(eax),                                        # Size of entries in exec chain
   );

  if (my $o = $options{operators})                                              # Operator methods for lexical items
   {$p->operators = $a->CreateQuarks;                                           # Create quark set to translate operator names to offsets
    $o->($p);
   }

  $p->parseUtf8;                                                                # Parse utf8 source string

  $p
 }

#D1 Parse                                                                       # Parse Unisyn expressions

our $Lex = &lexicalData;                                                        # Lexical table definitions

our $ses              = RegisterSize rax;                                       # Size of an element on the stack
our ($w1, $w2, $w3)   = (r8, r9, r10);                                          # Work registers
our $prevChar         = r11;                                                    # The previous character parsed
our $index            = r12;                                                    # Index of current element
our $element          = r13;                                                    # Contains the item being parsed
our $start            = r14;                                                    # Start of the parse string
our $size             = r15;                                                    # Length of the input string
our $parseStackBase   = rsi;                                                    # The base of the parsing stack in the stack
#ur $arenaReg         = rax;                                                    # The arena in which we are building the parse tree
our $indexScale       = 4;                                                      # The size of a utf32 character
our $lexCodeOffset    = 3;                                                      # The offset in a classified character to the lexical code.
our $bitsPerByte      = 8;                                                      # The number of bits in a byte

our $Ascii            = $$Lex{lexicals}{Ascii}           {number};              # Ascii
our $assign           = $$Lex{lexicals}{assign}          {number};              # Assign
our $dyad             = $$Lex{lexicals}{dyad}            {number};              # Dyad
our $dyad2            = $$Lex{lexicals}{dyad2}           {number};              # Dyad2
our $CloseBracket     = $$Lex{lexicals}{CloseBracket}    {number};              # Close bracket
our $empty            = $$Lex{lexicals}{empty}           {number};              # Empty element
our $NewLineSemiColon = $$Lex{lexicals}{NewLineSemiColon}{number};              # New line semicolon
our $OpenBracket      = $$Lex{lexicals}{OpenBracket}     {number};              # Open  bracket
our $prefix           = $$Lex{lexicals}{prefix}          {number};              # Prefix operator
our $semiColon        = $$Lex{lexicals}{semiColon}       {number};              # Semicolon
our $suffix           = $$Lex{lexicals}{suffix}          {number};              # Suffix
our $term             = $$Lex{lexicals}{term}            {number};              # Term
our $variable         = $$Lex{lexicals}{variable}        {number};              # Variable
our $WhiteSpace       = $$Lex{lexicals}{WhiteSpace}      {number};              # Variable
our $firstSet         = $$Lex{structure}{first};                                # First symbols allowed
our $lastSet          = $$Lex{structure}{last};                                 # Last symbols allowed
our $bracketsBase     = $$Lex{bracketsBase};                                    # Base lexical item for brackets

our $asciiNewLine     = ord("\n");                                              # New line in ascii
our $asciiSpace       = ord(' ');                                               # Space in ascii

                                                                                # Operator description
our $opType           = 0;                                                      # Operator type field - currently always a term
our $opCount          = 1;                                                      # Number of operands for this operator
our $opSub            = 2;                                                      # Offset of sub associated with this lexical item
our $opChain          = 3;                                                      # The execution chain produced by traversing the parse tree in post order.

                                                                                # Lexical item description
our $lexItemType      = 0;                                                      # Field number of lexical item type in the description of a lexical item
our $lexItemOffset    = 1;                                                      # Field number of the offset in the utf32 source of the lexical item in the description of a lexical item or - if this a term - the offset of the invariant first block of the sub tree
our $lexItemLength    = 2;                                                      # Field number of the length of the lexical item in the utf32 source in the description of a lexical item
our $lexItemQuark     = 3;                                                      # Quark containing the text of this lexical item.
our $lexItemWidth     = 4;                                                      # The number of fields used to describe a lexical item in the parse tree

                                                                                # Execution chain
our $execChainNext    = 0;                                                      # Next block offset
our $execChainTerm    = 1;                                                      # Corresponding term offset
our $execChainSub     = 2;                                                      # Offset of sub associated with term

sub getAlpha($$$)                                                               #P Load the position of a lexical item in its alphabet from the current character.
 {my ($register, $address, $index) = @_;                                        # Register to load, address of start of string, index into string
  Mov $register, "[$address+$indexScale*$index]";                               # Load lexical code
 }

sub getLexicalCode($$$)                                                         #P Load the lexical code of the current character in memory into the specified register.
 {my ($register, $address, $index) = @_;                                        # Register to load, address of start of string, index into string
  Mov $register, "[$address+$indexScale*$index+$lexCodeOffset]";                # Load lexical code
 }

sub putLexicalCode($$$$)                                                        #P Put the specified lexical code into the current character in memory.
 {my ($register, $address, $index, $code) = @_;                                 # Register used to load code, address of string, index into string, code to put
  Mov $register, $code;
  Mov "[$address+$indexScale*$index+$lexCodeOffset]", $register;                # Save lexical code
 }

sub loadCurrentChar()                                                           #P Load the details of the character currently being processed so that we have the index of the character in the upper half of the current character and the lexical type of the character in the lowest byte.
 {my $r = $element."b";                                                         # Classification byte

  Mov $element, $index;                                                         # Load index of character as upper dword
  Shl $element, $indexScale * $bitsPerByte;                                     # Save the index of the character in the upper half of the register so that we know where the character came from.
  getLexicalCode $r, $start, $index;                                            # Load lexical classification as lowest byte

  Cmp $r, $bracketsBase;                                                        # Brackets , due to their frequency, start after 0x10 with open even and close odd
  IfGe                                                                          # Brackets
  Then
   {And $r, 1                                                                   # Bracket: 0 - open, 1 - close
   },
  Else
   {Cmp     $r, $Ascii;                                                         # Ascii is a type of variable
    IfEq
    Then
     {Mov   $r, $variable;
     },
    Else
     {Cmp   $r, $NewLineSemiColon;                                              # New line semicolon is a type of semi colon
      IfEq
      Then
       {Mov $r, $semiColon;
       };
     };
   };
 }

sub checkStackHas($)                                                            #P Check that we have at least the specified number of elements on the stack.
 {my ($depth) = @_;                                                             # Number of elements required on the stack
  Mov $w1, $parseStackBase;
  Sub $w1, rsp;
  Cmp $w1, $ses * $depth;
 }

sub pushElement()                                                               #P Push the current element on to the stack.
 {Push $element;
  if ($debug)
   {PrintErrStringNL "Push Element:";
    PrintErrRegisterInHex $element;
   }
 }

sub pushEmpty()                                                                 #P Push the empty element on to the stack.
 {Mov  $w1, $index;
  Shl  $w1, $indexScale * $bitsPerByte;
  Or   $w1, $empty;
  Push $w1;
  if ($debug)
   {PrintErrStringNL "Push Empty";
   }
 }

sub lexicalNameFromLetter($)                                                    #P Lexical name for a lexical item described by its letter.
 {my ($l) = @_;                                                                 # Letter of the lexical item
  my %l = $Lex->{treeTermLexicals}->%*;
  my $n = $l{$l};
  confess "No such lexical: $l" unless $n;
  $n->{short}
 }

sub lexicalNumberFromLetter($)                                                  #P Lexical number for a lexical item described by its letter.
 {my ($l) = @_;                                                                 # Letter of the lexical item
  my $n = lexicalNameFromLetter $l;
  my $N = $Lex->{lexicals}{$n}{number};
  confess "No such lexical named: $n" unless defined $N;
  $N
 }

sub lexicalItemLength($$)                                                       #P Put the length of a lexical item into variable B<size>.
 {my ($source32, $offset) = @_;                                                 # B<address> of utf32 source representation, B<offset> to lexical item in utf32

  my $s = Subroutine
   {my ($p, $s) = @_;                                                           # Parameters
#   PushR r14, r15;                                                             # We do not need to save the zmm and mask registers because they are only used as temporary work registers and they have been saved in L<parseUtf8>

    $$p{source32}->setReg(r14);
    $$p{offset}  ->setReg(r15);
    Vmovdqu8 zmm0, "[r14+4*r15]";                                               # Load source to examine
    Pextrw r15, xmm0, 1;                                                        # Extract lexical type of first element

    OrBlock                                                                     # The size of a bracket or a semi colon is always 1
     {my ($pass, $end, $start) = @_;
      Cmp r15, $OpenBracket;
      Je  $pass;
      Cmp r15, $CloseBracket;
      Je  $pass;
      Cmp r15, $semiColon;
      Je  $pass;

      Vpbroadcastw zmm1, r15w;                                                  # Broadcast lexical type
      Vpcmpeqw k0, zmm0, zmm1;                                                  # Check extent of first lexical item up to 16
      Mov r15, 0x55555555;                                                      # Set odd positions to one where we know the match will fail
      Kmovq k1, r15;
      Korq k2, k0, k1;                                                          # Fill in odd positions

      Kmovq r15, k2;
      Not r15;                                                                  # Swap zeroes and ones
      Tzcnt r15, r15;                                                           # Trailing zero count is a factor two too big
      Shr r15, 1;                                                               # Normalized count of number of characters in lexical item
      $$p{size}->getReg(r15);                                                   # Save size in supplied variable
     }
    Pass                                                                        # Show unitary length
     {my ($end, $pass, $start) = @_;
      $$p{size}->getConst(1);                                                   # Save size in supplied variable
     };

#   PopR;
   } [qw(offset source32 size)],
  name => q(Unisyn::Parse::lexicalItemLength);

  $s->call(offset => $offset, source32 => $source32, my $size = V(size));

  $size
 }

sub new($$)                                                                     #P Create a new term in the parse tree rooted on the stack.
 {my ($depth, $description) = @_;                                               # Stack depth to be converted, text reason why we are creating a new term

  my $wr = RegisterSize rax;                                                    # Width of general purpose register

  my $s = Subroutine
   {my ($locals) = @_;                                                          # Parameters
    my $a = DescribeArena $$locals{bs};                                         # Address arena

    my $quarks =  $Parse->quarks->reload(arena => $$locals{bs},                 # Reload the quarks because the quarks used to create this subroutine might not be the same as the quarks that are reusing it now.
      array => $$locals{numbersToStringsFirst},
      tree  => $$locals{stringsToNumbersFirst});

    my $operators =  $Parse->operators ? $Parse->operators->reload              # Reload the subQuarks because the subQuarks used to create this subroutine might not be the same as the subQuarks that are reusing it now.
     (arena => $$locals{bs},
      array => $$locals{opNumbersToStringsFirst},
      tree  => $$locals{opStringsToNumbersFirst}) : undef;

    my $t = $a->CreateTree;                                                     # Create a tree in the arena to hold the details of the lexical elements on the stack
    my $o = V(offset);                                                          # Offset into source for lexical item
    $t->insert(V(key, $opType),  K(data, $term));                               # Create a term - we only have terms at the moment in the parse tree - but that might change in the future
    $t->insert(V(key, $opCount), K(data, $depth));                              # The number of elements in the term which is the number of operands for the operator

    my $liOnStack = $w1;                                                        # The lexical item as it appears on the stack
    my $liType    = $w2;                                                        # The lexical item type
    my $liOffset  = $w3;                                                        # The lexical item offset in the source

    PushR zmm0;                                                                 # Put the simulated stack on the stack

    for my $i(1..$depth)                                                        # Each term
     {my $j = $depth + 1 - $i;
      my $k = ($i - 1) * $wr;                                                   # Position in simulated stack
      Mov $liOnStack, "[rsp+$k]";                                               # Copy term out of simulated stack
      PrintErrRegisterInHex $liOnStack if $debug;

      Mov $liOffset, $liOnStack;                                                # Offset of either the text in the source or the offset of the first block of the tree describing a term
      Shr $liOffset, 32;                                                        # Offset in source: either the actual text of the offset of the first block of the tree containing a term shifted over to look as if it were an offset in the source
      $o->getReg($liOffset);                                                    # Offset of lexical item in source or offset of first block in tree describing a term

      ClearRegisters $liType;
      Mov $liType."b", $liOnStack."b";                                          # The lexical item type in the lowest byte, the rest clear.

      Cmp $liType, $term;                                                       # Check whether the lexical item on the stack is a term
      IfEq                                                                      # Insert a sub tree if we are inserting a term
      Then
       {$t->insertTree(K(key, $lexItemWidth * $j + $lexItemOffset), $o);        # Offset of first block in the tree representing the term
       },
      Else                                                                      # Insert the offset in the utf32 source if we are not on a term
       {$t->insert    (K(key, $lexItemWidth * $j + $lexItemOffset), $o);        # Offset in source of non term
       };

      Cmp $liType, $variable;                                                   # Check whether the lexical item is a variable which can also represent ascii
      IfEq                                                                      # Insert a sub tree if we are inserting a term
      Then
       {Mov $liType."b", "[$start+4*$liOffset+3]";                              # Load lexical type from source
       };

      Cmp $liType, $term;                                                       # Length of lexical item that is not a term
      IfNe
      Then                                                                      # Not a term
       {my $size = lexicalItemLength(V(address, $start), $o);                   # Get the size of the lexical item at the offset indicated on the stack
        $t->insert(V(key, $lexItemWidth * $j + $lexItemLength), $size);         # Save size of lexical item in parse tree

        my $s = CreateShortString(1);                                           # Short string to hold text of lexical item so we can load it into a quark
           $s->clear;                                                           # Perhaps not strictly necessary but easier to debug
        PushR r15;                                                              # Probably not needed as saved in L<parseutf8>
        r15 ne $start && r15 ne $liOffset or confess "r15 in use";
        Lea r15, "[$start+4*$liOffset]";                                        # Start address of lexical item
        my $startAddress = V(address, r15);                                     # Save start address of lexical item
        PopR;

        Cmp $liType, $OpenBracket;                                              # Is it a bracket ?
        IfEq
        Then
         {ClearRegisters $liType;                                               # Compute lexical type of bracket by adding bracket number to the start of the bracket range
          Mov $liType."b", "[$start+4*$liOffset+3]";                            # Load bracket number
          Shl $liType, 16;                                                      # Shift bracket base into position
          Add $liType, 2;                                                       # Set length of short string as two = (lexical type, bracket number)
          Pinsrd "xmm1", $liType."d", 0;                                        # Load short string
          Shr $liType, 16;                                                      # Move lexical type back into position for insertion into the parse tree
         },
        Else                                                                    # Not a bracket
         {Cmp $liType, $dyad2;                                                  # Is it a dyad2?
          IfEq
          Then                                                                  # Dyad 2 so load words
           {$s->loadDwordWords(0, $startAddress, $size, 1);                     # Load text of lexical item as words into short string leaving space for lexical type
           },
          Else                                                                  # Not a dyad2 so load bytes
           {$s->loadDwordBytes(0, $startAddress, $size, 1);                     # Load text of lexical item as bytes into short string leaving space for lexical type
           };
          Pinsrb "xmm1", $liType."b", 1;                                        # Set lexical type as the first byte of the short string
         };

        my $q = $quarks->quarkFromShortString($s);                              # Find the quark matching the lexical item if there is such a quark
        $t->insert(V(key, $lexItemWidth * $j + $lexItemQuark), $q);             # Save quark number of lexical item in parse tree
        if ($operators)                                                         # The parse has operator definitions
         {if ($j == 1)                                                          # The operator quark is always first
           {OrBlock                                                             # Like an operator or like a variable?
             {my ($pass, $end, $start) = @_;
              Cmp $liType, $variable;
              Je $pass;                                                         # Process a variable
              Cmp $liType, $Ascii;
              Je $pass;                                                         # Process ascii constant
              Cmp $liType, $semiColon;
              Je $pass;                                                         # Process Semicolon
              Cmp $liType, $NewLineSemiColon;
              Je $pass;                                                         # Process new line semicolon
                                                                                # Process non variable, i.e. operators specifically
              my $N = $operators->subFromQuarkViaQuarks($quarks, $q);           # Look up the subroutine associated with this operator
              If $N >= 0,                                                       # Found a matching operator subroutine
              Then
               {$t->insert(V(key, $opSub), $N);                                 # Save offset to subroutine associated with this lexical item
               };
             }
            Pass                                                                # Process variables in general or items based on variables using a short string of length 1 being the lexical type of the item in question
             {Shl $liType, 8;                                                   # Move lexical type into second byte
              Inc $liType;                                                      # Show length
              Pinsrq "xmm1", $liType, 0;                                        # Load short string
              my $N = $operators->subFromShortString($s);                       # Address of sub to process variable or ascii or semicolon
              Shr $liType, 8;                                                   # Restore lexical type
              If $N >= 0,                                                       # Found a matching operator subroutine
              Then
               {$t->insert(V(key, $opSub), $N);                                 # Save offset to subroutine associated with this lexical item
               };
             };
           }
         }
       };

      $t->insert  (V(key, $lexItemWidth * $j + $lexItemType),                   # Save lexical type in parse tree
                   V(data)->getReg($liType));
     }
                                                                                # Push new term onto the stack in place of the items popped off
    $t->first->setReg($liOffset);                                               # Offset of new term tree
    Shl $liOffset, 32;                                                          # Push offset to term tree into the upper dword to make it look like a source offset
    Or  $liOffset."b", $term;                                                   # Mark as a term tree
    $$locals{new}->getReg($liOffset);                                           # New term comprised of a tree of old terms
    PopR;                                                                       # Restore stack to its position at the start
   }
  [qw(new)], with => $ParseUtf8SubDef,
#  [qw(bs new
#    numbersToStringsFirst stringsToNumbersFirst
#    opNumbersToStringsFirst opStringsToNumbersFirst
#  )],
  name=>"Unisyn::Parse::new_$depth";

  PrintErrStringNL "New: $description" if $debug;

  if    ($depth == 1) {Mov $w1, 1}                                              # Copy the top of the real stack which holds the parse state to zmm0 so that we can adjust the stack to call L<new>
  elsif ($depth == 2) {Mov $w1, 3}
  else                {Mov $w1, 7}
  Kmovq k1, $w1;                                                                # B<k1> is saved in L<parseutf8>
  Vmovdqu64 "zmm0{k1}", "[rsp]";                                                # Copy top lexical items on stack

# $s->call(bs => $Parse->arena->bs, my $new = V('new'),
#   numbersToStringsFirst   => $Parse->quarks->numbersToStrings->first,
#   stringsToNumbersFirst   => $Parse->quarks->stringsToNumbers->first,
#   opNumbersToStringsFirst => $Parse->operators ? $Parse->operators->subQuarks->numbersToStrings->first : 0,
#   opStringsToNumbersFirst => $Parse->operators ? $Parse->operators->subQuarks->stringsToNumbers->first : 0,
#  );

  $s->call(my $new = V('new'));

  $new->setReg($w1);                                                            # Save offset of new term in a work register
  Add rsp, $depth * $wr;                                                        # Remove input terms from stack
  Push $w1;                                                                     # Save new term on stack
 }

sub error($)                                                                    #P Write an error message and stop.
 {my ($message) = @_;                                                           # Error message
  PrintOutStringNL "Error: $message";
  PrintOutString "Element: ";
  PrintOutRegisterInHex $element;
  PrintOutString "Index  : ";
  PrintOutRegisterInHex $index;
  Exit(0);
 }

sub testSet($$)                                                                 #P Test a set of items, setting the Zero Flag is one matches else clear the Zero flag.
 {my ($set, $register) = @_;                                                    # Set of lexical letters, Register to test
  my @n = map {sprintf("0x%x", lexicalNumberFromLetter $_)} split //, $set;     # Each lexical item by number from letter
  my $end = Label;
  for my $n(@n)
   {Cmp $register."b", $n;
    Je $end
   }
  ClearZF;
  SetLabel $end;
 }

sub checkSet($)                                                                 #P Check that one of a set of items is on the top of the stack or complain if it is not.
 {my ($set) = @_;                                                               # Set of lexical letters
  my @n =  map {lexicalNumberFromLetter $_} split //, $set;
  my $end = Label;

  for my $n(@n)
   {Cmp "byte[rsp]", $n;
    Je $end
   }
  error("Expected one of: '$set' on the stack");
  ClearZF;
  SetLabel $end;
 }

sub reduce($)                                                                   #P Convert the longest possible expression on top of the stack into a term  at the specified priority.
 {my ($priority) = @_;                                                          # Priority of the operators to reduce
  $priority =~ m(\A(1|2|3|4)\Z) or confess "Bad priority";                          # Level: 1 - all operators, 2 - priority 2 operators
  my ($success, $end) = map {Label} 1..2;                                       # Exit points

  checkStackHas 3;                                                              # At least three elements on the stack
  IfGe
  Then
   {my ($l, $d, $r) = ($w1, $w2, $w3);
    Mov $l, "[rsp+".(2*$ses)."]";                                               # Top 3 elements on the stack
    Mov $d, "[rsp+".(1*$ses)."]";
    Mov $r, "[rsp+".(0*$ses)."]";

    if ($debug)
     {PrintErrStringNL "Reduce 3 priority $priority: ";
      PrintErrRegisterInHex $l, $d, $r;
     }

    testSet("t",  $l);                                                          # Parse out infix operator expression
    IfEq
    Then
     {testSet("t",  $r);
      IfEq
      Then
       {testSet($priority == 1 ? "ades" :                                       # Reduce infix operators
                $priority == 2 ? "de"   :
                $priority == 3 ? "d"    : "e", $d);
        IfEq
        Then
         {Add rsp, 3 * $ses;                                                    # Reorder into polish notation
          Push $_ for $d, $l, $r;
          new(3, "Term infix term");
          Jmp $success;
         };
       };
     };

    testSet("b",  $l);                                                          # Parse parenthesized term
    IfEq
    Then
     {testSet("B",  $r);
      IfEq
      Then
       {testSet("t",  $d);
        IfEq
        Then
         {Add rsp, $ses;
          new(1, "Bracketed term");
          new(2, "Brackets for term");
          PrintErrStringNL "Reduce by ( term )" if $debug;
          Jmp $success;
         };
       };
     };
   };

  checkStackHas 2;                                                              # At least two elements on the stack
  IfGe                                                                          # Convert an empty pair of parentheses to an empty term
  Then
   {my ($l, $r) = ($w1, $w2);

    if ($debug)
     {PrintErrStringNL "Reduce 2:";
      PrintErrRegisterInHex $l, $r;
     }

#   KeepFree $l, $r;                                                            # Why ?
    Mov $l, "[rsp+".(1*$ses)."]";                                               # Top 3 elements on the stack
    Mov $r, "[rsp+".(0*$ses)."]";
    testSet("b",  $l);                                                          # Empty pair of parentheses
    IfEq
    Then
     {testSet("B",  $r);
      IfEq
      Then
       {Add rsp, 2 * $ses;                                                      # Pop expression
        Push $l;                                                                # Bracket as operator
        new(1, "Empty brackets");
        Jmp $success;
       };
     };
    testSet("s",  $l);                                                          # Semi-colon, close implies remove unneeded semi
    IfEq
    Then
     {testSet("B",  $r);
      IfEq
      Then
       {Add rsp, 2 * $ses;                                                      # Pop expression
        Push $r;
        PrintErrStringNL "Reduce by ;)" if $debug;
        Jmp $success;
       };
     };
    testSet("p", $l);                                                           # Prefix, term
    IfEq
    Then
     {testSet("t",  $r);
      IfEq
      Then
       {new(2, "Prefix term");
        Jmp $success;
       };
     };
#   KeepFree $l, $r;
   };

  ClearZF;                                                                      # Failed to match anything
  Jmp $end;

  SetLabel $success;                                                            # Successfully matched
  SetZF;

  SetLabel $end;                                                                # End
 } # reduce

sub reduceMultiple($)                                                           #P Reduce existing operators on the stack.
 {my ($priority) = @_;                                                          # Priority of the operators to reduce
  K('count',99)->for(sub                                                        # An improbably high but finite number of reductions
   {my ($index, $start, $next, $end) = @_;                                      # Execute body
    reduce($priority);
    Jne $end;                                                                   # Keep going as long as reductions are possible
   });
 }

sub accept_a()                                                                  #P Assign.
 {checkSet("t");
  reduceMultiple 2;
  PrintErrStringNL "accept a" if $debug;
  pushElement;
 }

sub accept_b                                                                    #P Open.
 {checkSet("abdeps");
  PrintErrStringNL "accept b" if $debug;
  pushElement;
 }

sub accept_B                                                                    #P Closing parenthesis.
 {checkSet("bst");
  PrintErrStringNL "accept B" if $debug;
  reduceMultiple 1;
  pushElement;
  reduceMultiple 1;
  checkSet("bst");
 }

sub accept_d                                                                    #P Dyad 3
 {checkSet("t");
  reduceMultiple 3;
  PrintErrStringNL "accept d" if $debug;
  pushElement;
 }

sub accept_e                                                                    #P Dyad 4
 {checkSet("t");
  reduceMultiple 4;
  PrintErrStringNL "accept d" if $debug;
  pushElement;
 }

sub accept_p                                                                    #P Prefix.
 {checkSet("abdeps");
  PrintErrStringNL "accept p" if $debug;
  pushElement;
 }

sub accept_q                                                                    #P Post fix.
 {checkSet("t");
  PrintErrStringNL "accept q" if $debug;
  IfEq                                                                          # Post fix operator applied to a term
  Then
   {Pop $w1;
    pushElement;
    Push $w1;
    new(2, "Postfix");
   }
 }

sub accept_s                                                                    #P Semi colon.
 {checkSet("bst");
  PrintErrStringNL "accept s" if $debug;
  Mov $w1, "[rsp]";
  testSet("s",  $w1);
  IfEq                                                                          # Insert an empty element between two consecutive semicolons
  Then
   {pushEmpty;
   };
  reduceMultiple 1;
  pushElement;
 }

sub accept_v                                                                    #P Variable.
  {checkSet("abdeps");
   PrintErrStringNL "accept v" if $debug;
   pushElement;
   new(1, "Variable");
   V(count,99)->for(sub                                                         # Reduce prefix operators
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

sub parseExpression()                                                           #P Parse the string of classified lexical items addressed by register $start of length $length.  The resulting parse tree (if any) is returned in r15.
 {my $end = Label;
  my $eb  = $element."b";                                                       # Contains a byte from the item being parsed

  Cmp $size, 0;                                                                 # Check for empty expression
  Je $end;

  loadCurrentChar;                                                              # Load current character
## Need test for ignorable white space as first character
  testSet($firstSet, $element);
  IfNe
  Then
   {error(<<END =~ s(\n) ( )gsr);
Expression must start with 'opening parenthesis', 'prefix
operator', 'semi-colon' or 'variable'.
END
   };

  testSet("v", $element);                                                       # Single variable
  IfEq
  Then
   {pushElement;
    new(1, "accept initial variable");
   },
  Else
   {testSet("s", $element);                                                     # Semi
    IfEq
    Then
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

    PrintErrRegisterInHex $element if $debug;

    Cmp $eb, $WhiteSpace;
    Je $next;                                                                   # Ignore white space

    Cmp $eb, 1;                                                                 # Brackets are singular but everything else can potential be a plurality
    IfGt
    Then
     {Cmp $prevChar."b", $eb;                                                   # Compare with previous element known not to be white space or a bracket
      Je $next
     };
    Mov $prevChar, $element;                                                    # Save element to previous element now we know we are on a different element

    for my $l(sort keys $Lex->{lexicals}->%*)                                   # Each possible lexical item after classification
     {my $x = $Lex->{lexicals}{$l}{letter};
      next unless $x and defined &{"accept_$x"};                                # Skip characters that do not have a letter defined for Tree::Term because the lexical items needed to layout a file of lexical items are folded down to the actual lexical items required to represent the language independent of the textual layout with white space.

      my $n = $Lex->{lexicals}{$l}{number};
      Comment "Compare to $n for $l";
      Cmp $eb, $n;

      IfEq
      Then
       {eval "accept_$x";
        say STDERR $@ if $@;
        Jmp $next
       };
     }
    error("Unexpected lexical item");                                           # Not selected
   } $index, $size;

  testSet($lastSet, $prevChar);                                                 # Last lexical  element
  IfNe                                                                          # Incomplete expression
  Then
   {error("Incomplete expression");
   };

  K('count', 99)->for(sub                                                       # Remove trailing semicolons if present
   {my ($index, $start, $next, $end) = @_;                                      # Execute body
    checkStackHas 2;
    Jl $end;                                                                    # Does not have two or more elements
    Pop $w1;
    testSet("s", $w1);                                                          # Check that the top most element is a semi colon
    IfNe                                                                        # Not a semi colon so put it back and finish the loop
    Then
     {Push $w1;
      Jmp $end;
     };
   });

  reduceMultiple 1;                                                             # Final reductions

  checkStackHas 1;
  IfNe                                                                          # Incomplete expression
  Then
   {error("Multiple expressions on stack");
   };

  Pop r15;                                                                      # The resulting parse tree
  Shr r15, 32;                                                                  # The offset of the resulting parse tree
  SetLabel $end;
 } # parseExpression

sub MatchBrackets(@)                                                            #P Replace the low three bytes of a utf32 bracket character with 24 bits of offset to the matching opening or closing bracket. Opening brackets have even codes from 0x10 to 0x4e while the corresponding closing bracket has a code one higher.
 {my (@parameters) = @_;                                                        # Parameters
  @_ >= 1 or confess "One or more parameters";

  my $s = Subroutine
   {my ($p) = @_;                                                               # Parameters
    Comment "Match brackets in utf32 text";

    my $finish = Label;
    PushR xmm0, k7, r10, r11, r12, r13, r14, r15, rsi;                          # R15 current character address. r14 is the current classification. r13 the last classification code. r12 the stack depth. r11 the number of opening brackets found. r10  address of first utf32 character.

    Mov rsi, rsp;                                                               # Save stack location so we can use the stack to record the brackets we have found
    ClearRegisters r11, r12, r15;                                               # Count the number of brackets and track the stack depth, index of each character
    K(three, 3)->setMaskFirst(k7);                                              # These are the number of bytes that we are going to use for the offsets of brackets which limits the size of a program to 24 million utf32 characters
    $$p{fail}   ->getReg(r11);                                                  # Clear failure indicator
    $$p{opens}  ->getReg(r11);                                                  # Clear count of opens
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
    Mov rsp, rsi;                                                               # Restore stack
    $$p{opens}->getReg(r11);                                                    # Number of brackets opened
    PopR;
   } [qw(address size fail opens)],  name => q(Unisyn::Parse::MatchBrackets);

  $s->call(@parameters);
 } # MatchBrackets

sub ClassifyNewLines(@)                                                         #P Scan input string looking for opportunities to convert new lines into semi colons.
 {my (@parameters) = @_;                                                        # Parameters
  @_ >= 1 or confess "One or more parameters";

  my $s = Subroutine
   {my ($p) = @_;                                                               # Parameters
    my $current       = r15;                                                    # Index of the current character
    my $middle        = r14;                                                    # Index of the middle character
    my $first         = r13;                                                    # Index of the first character
    my $address       = r12;                                                    # Address of input string
    my $size          = r11;                                                    # Length of input utf32 string
    my($c1, $c2)      = (r8."b", r9."b");                                       # Lexical codes being tested

    PushR r8, r9, r10, r11, r12, r13, r14, r15;

    $$p{address}->setReg($address);                                             # Address of string
    $$p{size}   ->setReg($size);                                                # Size of string
    Mov $current, 2; Mov $middle, 1; Mov $first, 0;

    For                                                                         # Each character in input string
     {my ($start, $end, $next) = @_;                                            # Start, end and next labels


      getLexicalCode $c1, $address, $middle;                                    # Lexical code of the middle character
      Cmp $c1, $WhiteSpace;
      IfEq
      Then
       {getAlpha $c1, $address, $middle;

        Cmp $c1, $asciiNewLine;
        IfEq                                                                    # Middle character is a insignificant new line and thus could be a semicolon
        Then
         {getLexicalCode $c1, $address, $first;

          my sub makeSemiColon                                                  # Make a new line into a new line semicolon
           {putLexicalCode $c2, $address, $middle, $NewLineSemiColon;
           }

          my sub check_bpv                                                      # Make new line if followed by 'b', 'p' or 'v'
           {getLexicalCode $c1, $address, $current;
            Cmp $c1, $OpenBracket;

            IfEq
            Then
             {makeSemiColon;
             },
            Else
             {Cmp $c1, $prefix;
              IfEq
              Then
               {makeSemiColon;
               },
              Else
               {Cmp $c1, $variable;
                IfEq
                Then
                 {makeSemiColon;
                 };
               };
             };
           }

          Cmp $c1, $CloseBracket;                                               # Check first character of sequence
          IfEq
          Then
           {check_bpv;
           },
          Else
           {Cmp $c1, $suffix;
            IfEq
            Then
             {check_bpv;
             },
            Else
             {Cmp $c1, $variable;
              IfEq
              Then
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

    PopR;
   } [qw(address size)], name => q(Unisyn::Parse::ClassifyNewLines);

  $s->call(@parameters);
 } # ClassifyNewLines

sub ClassifyWhiteSpace(@)                                                       #P Classify white space per: "lib/Unisyn/whiteSpace/whiteSpaceClassification.pl".
 {my (@parameters) = @_;                                                        # Parameters
  @_ >= 1 or confess "One or more parameters";

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

    my sub putLexicalCode($;$)                                                  # Put the specified lexical code into the current character in memory.
     {my ($code, $indexReg) = @_;                                               # Code, optional index register
      putLexicalCode $w1, $address, ($indexReg//$index), $code;
     };

    PushR r8, r9, r10, r11, r12, r13, r14, r15;

    $$p{address}->setReg($address);                                             # Address of string
    Mov $s, -1; Mov $S, -1; Mov $index, 0;                                      # Initial states, position

    $$p{size}->for(sub                                                          # Each character in expression
     {my ($indexVariable, $start, $next, $end) = @_;

      $indexVariable->setReg($index);
      getLexicalCode;                                                           # Current lexical code

      AndBlock                                                                  # Trap space before new line and detect new line after ascii
       {my ($end, $start) = @_;
        Cmp $index, 0;    Je  $end;                                             # Start beyond the first character so we can look back one character.
        Cmp $eb, $Ascii;  Jne $end;                                             # Current is ascii

        Mov $w1, "[$address+$indexScale*$index-$indexScale+$lexCodeOffset]";    # Previous lexical code
        Cmp $w1, $Ascii;  Jne $end;                                             # Previous is ascii

        if (1)                                                                  # Check for 's' followed by 'n' and 'a' followed by 'n'
         {Mov $w1, "[$address+$indexScale*$index-$indexScale]";                 # Previous character
          getAlpha $w2;                                                         # Current character

          Cmp $w1, $asciiSpace;                                                 # Check for space followed by new line
          IfEq
          Then
           {Cmp $w2, $asciiNewLine;
            IfEq                                                                # Disallow 's' followed by 'n'
            Then
             {PrintErrStringNL "Space detected before new line at index:";
              PrintErrRegisterInHex $index;
              PrintErrTraceBack;
              Exit(1);
             };
           };

          Cmp $w1, $asciiSpace;    Je  $end;                                    # Check for  'a' followed by 'n'
          Cmp $w1, $asciiNewLine;  Je  $end;                                    # Current is 'a' but not 'n' or 's'
          Cmp $w2, $asciiNewLine;  Jne $end;                                    # Current is 'n'

          putLexicalCode $WhiteSpace;                                           # Mark new line as significant
         }
       };

      AndBlock                                                                  # Spaces and new lines between other ascii
       {my ($end, $start) = @_;
        Cmp $s, -1;
        IfEq                                                                    # Looking for opening ascii
        Then
         {Cmp $eb, $Ascii;         Jne $end;                                    # Not ascii
          getAlpha $cb;                                                         # Current character
          Cmp $cb, $asciiNewLine;  Je $end;                                     # Skip over new lines
          Cmp $cb, $asciiSpace;    Je $end;                                     # Skip over spaces
          IfEq
          Then
           {Mov $s, $index; Inc $s;                                             # Ascii not space nor new line
           };
          Jmp $end;
         },
        Else                                                                    # Looking for closing ascii
         {Cmp $eb, $Ascii;
          IfNe                                                                  # Not ascii
          Then
           {Mov $s, -1;
            Jmp $end
           };
          getAlpha $cb;                                                         # Current character
          Cmp $cb, $asciiNewLine; Je $end;                                      # Skip over new lines
          Cmp $cb, $asciiSpace;   Je $end;                                      # Skip over spaces

          For                                                                   # Move over spaces and new lines between two ascii characters that are neither of new line or space
           {my ($start, $end, $next) = @_;
            getAlpha $cb, $s;                                                   # Check for 's' or 'n'
            Cmp $cb, $asciiSpace;
            IfEq
            Then
             {putLexicalCode $WhiteSpace, $s;                                   # Mark as significant white space.
             Jmp $next;
             };
            Cmp $cb, $asciiNewLine;
            IfEq
            Then
             {putLexicalCode $WhiteSpace;                                       # Mark as significant new line
              Jmp $next;
             };
           } $s, $index;

          Mov $s, $index; Inc $s;
         };
       };

      AndBlock                                                                  # Note: 's' preceding 'a' are significant
       {my ($end, $start) = @_;
        Cmp $S, -1;
        IfEq                                                                    # Looking for 's'
        Then
         {Cmp $eb, $Ascii;                                                      # Not 'a'
          IfNe
          Then
           {Mov $S, -1;
            Jmp $end
           };
          getAlpha $cb;                                                         # Actual character in alphabet
          Cmp $cb, $asciiSpace;                                                 # Space
          IfEq
          Then
           {Mov $S, $index;
            Jmp $end;
           };
         },
        Else                                                                    # Looking for 'a'
         {Cmp $eb, $Ascii;                                                      # Not 'a'
          IfNe
          Then
           {Mov $S, -1;
            Jmp $end
           };
          getAlpha $cb;                                                         # Actual character in alphabet
          Cmp $cb, $asciiSpace; Je $end;                                        # Skip 's'

          Cmp $cb, $asciiNewLine;
          IfEq                                                                  # New lines prevent 's' from preceding 'a'
          Then
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

      AndBlock                                                                  # Invert non significant white space
       {my ($end, $start) = @_;
        Cmp $eb, $Ascii;
        Jne $end;                                                               # Ascii

        getAlpha $cb;                                                           # Actual character in alphabet
        Cmp $cb, $asciiSpace;
        IfEq
        Then
         {putLexicalCode $WhiteSpace;
          Jmp $next;
         };
        Cmp $cb, $asciiNewLine;
        IfEq
        Then
         {putLexicalCode $WhiteSpace;                                           # Mark new line as not significant
          Jmp $next;
         };
       };

      AndBlock                                                                  # Mark significant white space
       {my ($end, $start) = @_;
        Cmp $eb, $WhiteSpace; Jne $end;                                         # Not significant white space
        putLexicalCode $Ascii;                                                  # Mark as ascii
       };
     });

    PopR;
   } [qw(address size)],  name => q(Unisyn::Parse::ClassifyWhiteSpace);

  $s->call(@parameters);
 } # ClassifyWhiteSpace

sub reload($$)                                                                  #P Reload the variables associated with a parse.
 {my ($parse, $parameters) = @_;                                                # Parse, hash of variable parameters
  @_ >= 1 or confess "One or more parameters";

  $parse->quarks->reload   (arena => $$parameters{bs},                          # Reload the quarks because the quarks used to create this subroutine might not be the same as the quarks that are reusing it now.
    array => $$parameters{numbersToStringsFirst},
    tree  => $$parameters{stringsToNumbersFirst});

  $parse->operators->reload(arena => $$parameters{bs},                          # Reload the subQuarks because the subQuarks used to create this subroutine might not be the same as the subQuarks that are reusing it now.
    array => $$parameters{opNumbersToStringsFirst},
    tree  => $$parameters{opStringsToNumbersFirst}) if $parse->operators;
 }

sub parseUtf8($@)                                                               #P Parse a unisyn expression encoded as utf8 and return the parse tree.
 {my ($parse, @parameters) = @_;                                                # Parse, parameters
  @_ >= 1 or confess "One or more parameters";

  my $s = Subroutine
   {my ($p, $s) = @_;                                                           # Parameters
    $ParseUtf8SubDef = $s;                                                      # Save the sub definition globally so that we can forward its parameter list to L<new>.

    $parse->reload($p);                                                         # Reload the parse description
    PrintErrStringNL "ParseUtf8" if $debug;

    PushR $parseStackBase, map {"r$_"} 8..15;
    PushZmm 0..1; PushMask 0..2;                                                # Used to hold arena and classifiers. Zmm0 is used to as a short string to quark the lexical item strings.

    my $source32       = $$p{source32};
    my $sourceSize32   = $$p{sourceSize32};
    my $sourceLength32 = $$p{sourceLength32};

    ConvertUtf8ToUtf32 u8 => $$p{address}, size8  => $$p{size},                 # Convert to utf32
                      u32 => $source32,    size32 => $sourceSize32,
                    count => $sourceLength32;

    my sub PrintUtf32($$)                                                       # Print a utf32 string in hexadecimal
     {my ($size, $address) = @_;                                                # Variable size, variable address
      $address->printErrMemoryInHexNL($size);
     }

    if ($debug)
     {PrintErrStringNL "After conversion from utf8 to utf32";
      $sourceSize32   ->errNL("Output Length: ");                               # Write output length
      PrintUtf32($sourceSize32, $source32);                                     # Print utf32
     }

    if (1)                                                                      # Classify non dyad2 alphabetic characters.
     {Vmovdqu8 zmm0, "[".Rd(join ', ', $Lex->{lexicalLow} ->@*)."]";            # Each double is [31::24] Classification, [21::0] Utf32 start character
      Vmovdqu8 zmm1, "[".Rd(join ', ', $Lex->{lexicalHigh}->@*)."]";            # Each double is [31::24] Range offset,   [21::0] Utf32 end character
      ClassifyWithInRangeAndSaveOffset                                          # Alphabetic classification
        address=>$source32, size=>$sourceLength32;
      if ($debug)
       {PrintErrStringNL "After classification into alphabet ranges";
        PrintUtf32($sourceSize32, $source32);                                   # Print classified utf32
       }
     }

    if (1)                                                                      # Classify dyad2 characters.
     {my @l = $Lex->{dyad2Low} ->@*;                                            # Start of each range
      my @h = $Lex->{dyad2High}->@*;                                            # End of range
      my @o = $Lex->{dyad2Offset}->@*;                                          # Offset of each range
      my $b = $Lex->{dyad2Blocks};                                              # Dyad 2 blocks
      my $B = $Lex->{dyad2BlockSize};                                           # Offset of each range
      for my $block(1..$b)                                                      # Classify dyad2 characters.
       {my $l = ($block-1) * $B;
        my $h = ($block)   * $B - 1;
        Vmovdqu8 zmm0, "[".Rd(join ', ', @l[$l..$h])."]";                       # Start of each range
        Vmovdqu8 zmm1, "[".Rd(join ', ', @h[$l..$h])."]";                       # End of range
        Vmovdqu8 zmm2, "[".Rd(join ', ', @o[$l..$h])."]";                       # Offset of each range
        ClassifyWithInRangeAndSaveWordOffset $source32, $sourceLength32,        # Dyad2 character classifications
          V('classification', $Lex->{lexicals}{dyad2}{number});
       }
      if ($debug)
       {PrintErrStringNL "After classification into dyad2 ranges";
        PrintUtf32($sourceSize32, $source32);                                   # Print classified utf32
       }
     }

    Vmovdqu8 zmm0, "[".Rd(join ', ', $Lex->{bracketsLow} ->@*)."]";             # Each double is [31::24] Classification, [21::0] Utf32 start character
    Vmovdqu8 zmm1, "[".Rd(join ', ', $Lex->{bracketsHigh}->@*)."]";             # Each double is [31::24] Range offset,   [21::0] Utf32 end character

    ClassifyWithInRange address=>$source32, size=>$sourceLength32;              # Bracket classification
    if ($debug)
     {PrintErrStringNL "After classification into brackets";
      PrintUtf32($sourceSize32, $source32);                                     # Print classified brackets
     }

    my $opens = V(opens, -1);
    MatchBrackets address=>$source32, size=>$sourceLength32, $opens, $$p{fail}; # Match brackets
    if ($debug)
     {PrintErrStringNL "After bracket matching";
      PrintUtf32($sourceSize32, $source32);                                     # Print matched brackets
     }

    ClassifyWhiteSpace address=>$source32, size=>$sourceLength32;               # Classify white space
    if ($debug)
     {PrintErrStringNL "After white space classification";
      PrintUtf32($sourceSize32, $source32);
     }

    ClassifyNewLines address=>$source32, size=>$sourceLength32;                 # Classify new lines
    if ($debug)
     {PrintErrStringNL "After classifying new lines";
      PrintUtf32($sourceSize32, $source32);
     }

    $$p{source32}      ->setReg($start);                                        # Start of expression string after it has been classified
    $$p{sourceLength32}->setReg($size);                                         # Number of characters in the expression
    Mov $parseStackBase, rsp;                                                   # Set base of parse stack

    parseExpression;                                                            # Parse the expression

    $$p{parse}->getReg(r15);                                                    # Number of characters in the expression
    Mov rsp, $parseStackBase;                                                   # Remove parse stack

    $$p{parse}->errNL if $debug;

    PopMask; PopZmm; PopR;

   }
  [qw(bs address size parse fail source32 sourceSize32 sourceLength32),
   qw(numbersToStringsFirst stringsToNumbersFirst),
   qw(opNumbersToStringsFirst opStringsToNumbersFirst)],
  name => q(Unisyn::Parse::parseUtf8);

  my $op = $parse->operators;                                                   # The operator methods if supplied
  my $zero = K(zero, 0);

  $s->call                                                                      # Parameterize the parse
   (bs                      => $parse->arena->bs,
    address                 => $parse->address8,
    fail                    => $parse->fails,
    parse                   => $parse->parse,
    size                    => $parse->size8,
    source32                => $parse->source32,
    sourceLength32          => $parse->sourceLength32,
    sourceSize32            => $parse->sourceSize32,
    numbersToStringsFirst   => $parse->quarks->numbersToStrings->first,
    stringsToNumbersFirst   => $parse->quarks->stringsToNumbers->first,
    opNumbersToStringsFirst => $op ? $op->numbersToStrings->first : $zero,
    opStringsToNumbersFirst => $op ? $op->stringsToNumbers->first : $zero,
   );
 } # parseUtf8

#D1 Traverse                                                                    # Traverse the parse tree

sub traverseParseTree($)                                                        # Traverse the terms in parse tree in post order and call the operator subroutine associated with each term.
 {my ($parse) = @_;                                                             # Parse tree

  my $s = Subroutine                                                            # Print a tree
   {my ($p, $s) = @_;                                                           # Parameters, sub definition
    my $t = Nasm::X86::DescribeTree (arena=>$$p{bs}, first=>$$p{first});        # Tree definition
    $t->find(K(key, $opType));                                                  # The lexical type of the element - normally a term

    If $t->found == 0,                                                          # Not found lexical type of element
    Then
     {PrintOutString "No type for node";
      Exit(1);
     };

    If $t->data != $term,                                                       # Expected a term
    Then
     {PrintOutString "Expected a term";
      Exit(1);
     };

    my $operands = V(operands);                                                 # Number of operands
    $t->find(K(key, $opCount));                                                 # Key 1 tells us the number of operands
    If $t->found > 0,                                                           # Found key 1
    Then
     {$operands->copy($t->data);                                                # Number of operands
     },
    Else
     {PrintOutString "Expected at least one operand";
      Exit(1);
     };

    $operands->for(sub                                                          # Each operand
     {my ($index, $start, $next, $end) = @_;                                    # Execute body
      my $i = (1 + $index) * $lexItemWidth;                                     # Operand detail
      $t->find($i+$lexItemType);   my $lex = V(key) ->copy($t->data);           # Lexical type
      $t->find($i+$lexItemOffset); my $off = V(key) ->copy($t->data);           # Offset of first block of sub tree

      If $lex == $term,                                                         # Term
      Then
       {$s->call($$p{bs}, first => $off);                                       # Traverse sub tree referenced by offset field
        $t->first  ->copy($$p{first});                                          # Re-establish addressability to the tree after the recursive call
       },
     });

    $t->find(K(key, $opSub));                                                   # The subroutine for the term
    If $t->found > 0,                                                           # Found subroutine for term
    Then                                                                        # Call subroutine for this term
     {#PushR r15, zmm0;
      my $p = Subroutine                                                        # Prototype subroutine to establish parameter list
        {} [qw(tree call)], with => $s,
      name => __PACKAGE__."TraverseParseTree::ProcessLexicalItem::prototype";

      my $d = Subroutine                                                        # Dispatcher
       {my ($q, $sub) = @_;
        $p->dispatchV($$q{call}, r15);
       } [], with => $p,
      name => __PACKAGE__."TraverseParseTree::ProcessLexicalItem::dispatch";

      If $t->data > 0,
      Then
       {$d->call(tree => $t->first, call => $t->data)                           # Call sub associated with the lexical item
       };
#     my $p = Subroutine                                                        # Subroutine
#      {my ($parameters) = @_;                                                  # Parameters
#       $$parameters{call}->setReg(r15);
#       Call r15;
#      }  [qw(tree call)], with => $s,
#     name => __PACKAGE__."TraverseParseTree::ProcessLexicalItem";
#
#     my $l = RegisterSize rax;
#     $$p{bs}   ->putQIntoZmm(0, 0*$l, r15);
#     $$p{first}->putQIntoZmm(0, 1*$l, r15);
#     $t->data  ->setReg(r15);
#     Call r15;
#     #PopR;
     };

   } [qw(bs first)], name => "Nasm::X86::Tree::traverseParseTree";

  PushR r15, zmm0;
  $s->call($parse->arena->bs, first => $parse->parse);
  PopR;

  $a
 } # traverseParseTree

sub makeExecutionChain($)                                                       # Traverse the parse tree in post order to create an execution chain.
 {my ($parse) = @_;                                                             # Parse tree
  my $W = $parse->width;                                                        # Width of entries in exec chain blocks

  my $s = Subroutine                                                            # Print a tree
   {my ($p, $s) = @_;                                                           # Parameters, sub definition
    my $t = Nasm::X86::DescribeTree (arena=>$$p{bs}, first=>$$p{first});        # Tree definition
    $t->find(K(key, $opType));                                                  # The lexical type of the element - normally a term

    If $t->found == 0,                                                          # Not found lexical type of element
    Then
     {PrintOutString "No type for node";
      Exit(1);
     };

    If $t->data != $term,                                                       # Expected a term
    Then
     {PrintOutString "Expected a term";
      Exit(1);
     };

    ClearRegisters zmm0;                                                        # Place term on execution chain
    $$p{chain}->putDIntoZmm(0, $execChainNext * $W, r15);                       # Offset of previous block
    $$p{first}->putDIntoZmm(0, $execChainTerm * $W, r15);                       # Save term offset

    $t->find(K(key, $opSub));                                                   # The subroutine for the term
    If $t->found > 0,                                                           # Found subroutine for term
    Then                                                                        # Call subroutine for this term
     {$t->data->putDIntoZmm(0, $execChainSub * $W, r15);                        # Save operator
     };

    my $block = $parse->arena->allocZmmBlock;                                   # Create exec chain element
    $parse->arena->putZmmBlock($block, 0, r14, r15);                            # Save exec chain element
    $$p{chain}->copy($block);                                                   # Save address of block

    my $operands = V(operands);                                                 # Number of operands
    $t->find(K(key, $opCount));                                                 # Key 1 tells us the number of operands
    If $t->found > 0,                                                           # Found key 1
    Then
     {$operands->copy($t->data);                                                # Number of operands
     },
    Else
     {PrintOutString "Expected at least one operand";
      Exit(1);
     };

    $operands->for(sub                                                          # Each operand
     {my ($index, $start, $next, $end) = @_;                                    # Execute body
      my $i = (1 + $index) * $lexItemWidth;                                     # Operand detail
      $t->find($i+$lexItemType);   my $lex = $t->data->clone('key');            # Lexical type
      $t->find($i+$lexItemOffset); my $off = $t->data->clone('key');            # Offset of first block of sub tree

      If $lex == $term,                                                         # Term
      Then
       {$s->call($$p{bs}, first => $off, chain => $$p{chain});                  # Traverse sub tree referenced by offset field
        $t->first->copy($$p{first});                                            # Re-establish addressability to the tree after the recursive call
       },
     });

   } [qw(bs first chain)], name => "Nasm::X86::Tree::makeExecutionChain";

  PushR r14, r15, zmm0;

  $s->call($parse->arena->bs, first => $parse->parse, my $chain = V('chain',0));# Construct execution chain

#  If $chain > 0,                                                               # Reverse execution chain. This was done while listening to Transformers about the time BAN and I were working on partially reversing a list: I got a bit carried away.
#  Then
#   {my $A = $parse->arena;
#    my $a = V('zero', 0);
#    my $b = $chain->clone;
#
#    ForEver                                                                    # Loop through exec chain reversing each link
#     {my ($start, $end) = @_;
#      $A ->getZmmBlock($b, 0, r14, r15);
#      my $c = Nasm::X86::getDFromZmm(0, $execChainNext, r15);
#      $a->putDIntoZmm(0, $execChainNext);
#      $A->putZmmBlock($b, 0, r14, r15);
#
#      If $c == 0, Then {Jmp $end};
#      $a->copy($b);
#      $b->copy($c);
#     };
#    my $t = $parse->arena->DescribeTree(first => $parse->parse);                # Parse tree
#    $t->insert(V('key', $opChain), $b);                                         # Save start of chain
#   };
#
  my $t = $parse->arena->DescribeTree(first => $parse->parse);                  # Parse tree
  $t->insert(V('key', $opChain), $chain);                                       # Save start of chain in parse tree

  PopR;

  $a
 } # makeExecutionChain

sub printExecChain($)                                                           #P Print the execute chain for a parse.
 {my ($parse) = @_;                                                             # Parse tree
  my $t = $parse->arena->DescribeTree(first=>$parse->parse);
  $t->find(V('key', $opChain));                                                 # Start of chain
  my $p = $t->data->clone;
  PushR r14, r15, zmm0;

  ForEver
   {my ($start, $end) = @_;                                                     # Fail block, end of fail block, start of test block
    If $p == 0, Then {Jmp $end};                                                # End of chain
    $parse->arena->getZmmBlock($p, 0, r14, r15);
    $p->out("offset: ", " : ");
    PrintOutRegisterInHex zmm0;
    $p->copy(Nasm::X86::getDFromZmm(0, $execChainNext, r15));
   };

  PopR;
 }

sub execExecChain($)                                                            #P Execute the execute chain for a parse.
 {my ($parse) = @_;                                                             # Parse tree
  my $t = $parse->arena->DescribeTree(first=>$parse->parse);
  $t->find(V('key', $opChain));                                                 # Start of chain
  my $p = $t->data->clone;
  my $W = $parse->width;                                                        # Width of entries in exec chain blocks
  PushR r14, r15, zmm0;

  ForEver
   {my ($start, $end) = @_;                                                     # Fail block, end of fail block, start of test block
    If $p == 0, Then {Jmp $end};                                                # End of chain
    $parse->arena->getZmmBlock($p, 0, r14, r15);
    my $c = Nasm::X86::getDFromZmm (0, $execChainSub * $W, r15);                # Get sub

    my $s = Subroutine
     {my ($p) = @_;
     } [], name => 'ttt';

    If $c > 0,                                                                  # Call any sub attached to this execution chain element
    Then
     {$s->via($c);                                                              # Call Sub
     };
    $p->copy(Nasm::X86::getDFromZmm(0, $execChainNext, r15));                   # Next element on chain
   };

  PopR;
 }

#D1 Print                                                                       # Print a parse tree

sub printLexicalItem($$$$)                                                      #P Print the utf8 string corresponding to a lexical item at a variable offset.
 {my ($parse, $source32, $offset, $size) = @_;                                  # Parse tree, B<address> of utf32 source representation, B<offset> to lexical item in utf32, B<size> in utf32 chars of item
  my $t = $parse->arena->DescribeTree;

  my $s = Subroutine
   {my ($p, $s) = @_;                                                           # Parameters
    PushR r12, r13, r14, r15;

    $$p{source32}->setReg(r14);
    $$p{offset}  ->setReg(r15);
    Lea r13, "[r14+4*r15]";                                                     # Address lexical item
    Mov eax, "[r13]";                                                           # First lexical item clearing rax
    Shr rax, 24;                                                                # First lexical item type in lowest byte and all else cleared

    my $success = Label;
    my $print   = Label;

    Cmp rax, $bracketsBase;                                                     # Test for brackets
    IfGe
    Then
     {my $o = $Lex->{bracketsOpen};                                             # Opening brackets
      my $c = $Lex->{bracketsClose};                                            # Closing brackets
      my $O = Rutf8 map {($_, chr(0))} @$o;                                     # Brackets in 3 bytes of utf8 each, with each bracket followed by a zero to make 4 bytes which is more easily addressed
      my $C = Rutf8 map {($_, chr(0))} @$c;                                     # Brackets in 3 bytes of utf8 each, with each bracket followed by a zero to make 4 bytes which is more easily addressed
      Mov r14, $O;                                                              # Address open bracket
      Mov r15, rax;                                                             # The bracket number
      Lea rax, "[r14+4*r15 - 4*$bracketsBase-4]";                               # Index to bracket
      PrintOutUtf8Char;                                                         # Print opening bracket
      Mov r14, $C;                                                              # Address close bracket
      Lea rax, "[r14+4*r15 - 4*$bracketsBase-4]";                               # Closing brackets occupy 3 bytes
      PrintOutUtf8Char;                                                         # Print closing bracket
      Jmp $success;
     };

    Mov r12, -1;                                                                # Alphabet to use
    Cmp rax, $variable;                                                         # Test for variable
    IfEq
    Then
     {my $b = $Lex->{alphabetChars}{v};                                         # Load variable alphabet in dwords
      Mov r12, Rd map {convertUtf32ToUtf8LE $_} @$b;
      Jmp $print;
     };

    Cmp rax, $assign;                                                           # Assign operator
    IfEq
    Then
     {my $b = $Lex->{alphabetChars}{a};
      Mov r12, Rd map {convertUtf32ToUtf8LE $_} @$b;
      Jmp $print;
     };

    Cmp rax, $dyad;                                                             # Dyad
    IfEq
    Then
     {my $b = $Lex->{alphabetChars}{d};
      Mov r12, Rd map {convertUtf32ToUtf8LE $_} @$b;
      Jmp $print;
     };

    Cmp rax, $dyad2;                                                            # Dyad2
    IfEq
    Then
     {my $b = $Lex->{alphabetChars}{e};
      Mov r12, Rd map {convertUtf32ToUtf8LE $_} @$b;
      Jmp $print;
     };

    Cmp rax, $Ascii;                                                            # Ascii
    IfEq
    Then
     {my $b = $Lex->{alphabetChars}{A};
      Mov r12, Rd map {convertUtf32ToUtf8LE $_} @$b;
      Jmp $print;
     };

    Cmp rax, $prefix;                                                           # Prefix
    IfEq
    Then
     {my $b = $Lex->{alphabetChars}{p};
      Mov r12, Rd map {convertUtf32ToUtf8LE $_} @$b;
      Jmp $print;
     };

    Cmp rax, $suffix;                                                           # Suffix
    IfEq
    Then
     {my $b = $Lex->{alphabetChars}{q};
      Mov r12, Rd map {convertUtf32ToUtf8LE $_} @$b;
      Jmp $print;
     };

    PrintErrTraceBack;                                                          # Unknown lexical type
    PrintErrStringNL "Alphabet not found for unexpected lexical item";
    PrintErrRegisterInHex rax;
    Exit(1);

    SetLabel $print;                                                            # Decoded

    $$p{size}->for(sub                                                          # Write each letter out from its position on the stack
     {my ($index, $start, $next, $end) = @_;                                    # Execute body
      $index->setReg(r14);                                                      # Index stack
      ClearRegisters r15;                                                       # Next instruction does not clear the entire register
      Mov r15w, "[r13+4*r14]";                                                  # Load alphabet offset from stack
      Lea rax, "[r12+4*r15]";                                                   # Address alphabet letter as utf8
      PrintOutUtf8Char;                                                         # Print utf8 character
     });

    SetLabel $success;                                                          # Done

    PopR;
   } [qw(offset source32 size)],
  name => q(Unisyn::Parse::printLexicalItem);

  $s->call(offset => $offset, source32 => $source32, size => $size);
 }

sub print($)                                                                    # Print a parse tree.
 {my ($parse) = @_;                                                             # Parse tree
  my $t = $parse->arena->DescribeTree;

  PushR my ($depthR) = (r12);                                                   # Recursion depth

  my $b = Subroutine                                                            # Print the spacing blanks to offset sub trees
   {V(loop, $depthR)->for(sub
     {PrintOutString "  ";
     });
   } [], name => "Nasm::X86::Tree::dump::spaces";

  my $s = Subroutine                                                            # Print a tree
   {my ($p, $s) = @_;                                                           # Parameters, sub definition

    my $B = $$p{bs};

    $t->address->copy($$p{bs});
    $t->first  ->copy($$p{first});
    $t->find(K(key, 0));                                                        # Key 0 tells us the type of the element - normally a term

    If $t->found == 0,                                                          # Not found key 0
    Then
     {PrintOutString "No type for node";
      Exit(1);
     };

    If $t->data != $term,                                                       # Expected a term
    Then
     {PrintOutString "Expected a term";
      Exit(1);
     };

    my $operands = V(operands);                                                 # Number of operands
    $t->find(K(key, 1));                                                        # Key 1 tells us the number of operands
    If $t->found > 0,                                                           # Found key 1
    Then
     {$operands->copy($t->data);                                                # Number of operands
     },
    Else
     {PrintOutString "Expected at least one operand";
      Exit(1);
     };

    $operands->for(sub                                                          # Each operand
     {my ($index, $start, $next, $end) = @_;                                    # Execute body
      my $i = (1 + $index) * $lexItemWidth;                                     # Operand detail
      $t->find($i+$lexItemType);   my $lex = V(key) ->copy($t->data);           # Lexical type
      $t->find($i+$lexItemOffset); my $off = V(data)->copy($t->data);           # Offset in source
      $t->find($i+$lexItemLength); my $len = V(data)->copy($t->data);           # Length in source

      $b->call;                                                                 # Indent

      If $lex == $term,                                                         # Term
      Then
       {PrintOutStringNL "Term";
        Inc $depthR;                                                            # Increase indentation for sub terms
        $s->call($B, first => $off, $$p{source32});                             # Print sub tree referenced by offset field
        Dec $depthR;                                                            # Restore existing indentation
        $t->first  ->copy($$p{first});                                          # Re-establish addressability to the tree after the recursive call
       },

      Ef {$lex == $semiColon}                                                   # Semicolon
      Then
       {PrintOutStringNL "Semicolon";
       },

      Else
       {If $lex == $variable,                                                   # Variable
        Then
         {PrintOutString "Variable: ";
         },

        Ef {$lex == $assign}                                                    # Assign
        Then
         {PrintOutString "Assign: ";
         },

        Ef {$lex == $prefix}                                                    # Prefix
        Then
         {PrintOutString "Prefix: ";
         },

        Ef {$lex == $suffix}                                                    # Suffix
        Then
         {PrintOutString "Suffix: ";
         },

        Ef {$lex == $dyad}                                                      # Dyad
        Then
         {PrintOutString "Dyad: ";
         },

        Ef {$lex == $dyad2}                                                     # Dyad2
        Then
         {PrintOutString "Dyad2: ";
         },

        Ef {$lex == $Ascii}                                                     # Ascii
        Then
         {PrintOutString "Ascii: ";
         },

        Else                                                                    # Brackets
         {PrintOutString "Brackets: ";
         };

        $parse->printLexicalItem($$p{source32}, $off, $len);                    # Print the variable name
        PrintOutNL;
      };

      If $index == 0,                                                           # Operator followed by indented operands
      Then
       {Inc $depthR;
       };
     });

    Dec $depthR;                                                                # Reset indentation after operands
   } [qw(bs first source32)], name => "Nasm::X86::Tree::print";

  ClearRegisters $depthR;                                                       # Depth starts at zero

  $s->call($parse->arena->bs, first => $parse->parse, $parse->source32);

  PopR;
 } # print

sub dumpParseTree($)                                                            # Dump the parse tree.
 {my ($parse) = @_;                                                             # Parse tree
  my $t = $parse->arena->DescribeTree;
  $t->first->copy($parse->parse);
  $t->dump;
 }

#D1 Execute                                                                     # Associate methods with each operator via a set of quarks describing the method to be called for each lexical operator.

sub lexToSub($$$$)                                                              # Map a lexical item to a processing subroutine.
 {my ($parse, $alphabet, $op, $sub) = @_;                                       # Sub quarks, the alphabet number, the operator name in that alphabet, subroutine definition
  my $a = &lexicalData->{alphabetChars}{$alphabet};                             # Alphabet
  my $n = $$Lex{lexicalsByLetter}{$alphabet}{number};                           # Number of lexical type
  my %i = map {$$a[$_]=>$_} keys @$a;                                           # Translates into offset in alphabet for this lexical item
  my @o = map {ord($_)} split //, $op;                                          # Characters in operator name
  my @b = ($n, map {$i{$_}} @o);                                                # Bytes representing the operator name
     @b = ($n, map {my $c = $i{$_}; ($c % 256, int($c/256))} @o) if @$a > 0xff; # Words representing the operator name as bytes would not be enough in all cases
  my $s = join '', map {chr $_} @b;                                             # String representation
  $parse->operators->putSub($s, $sub);                                          # Add the string, subroutine combination to the sub quarks
 }

sub dyad($$$)                                                                   # Define a method for a dyadic operator.
 {my ($parse, $text, $sub) = @_;                                                # Sub quarks, the name of the operator as a utf8 string, associated subroutine definition
  $parse->lexToSub("d", $text, $sub);
 }

sub dyad2($$$)                                                                  # Define a method for a dyadic 2 operator.
 {my ($parse, $text, $sub) = @_;                                                # Sub quarks, the name of the operator as a utf8 string, associated subroutine definition
  $parse->lexToSub("e", $text, $sub);
 }

sub assign($$$)                                                                 # Define a method for an assign operator.
 {my ($parse, $text, $sub) = @_;                                                # Sub quarks, the name of the operator as a utf8 string, associated subroutine definition
  $parse->lexToSub("a", $text, $sub);                                           # Operator name in operator alphabet preceded by alphabet number
 }

sub prefix($$$)                                                                 # Define a method for a prefix operator.
 {my ($parse, $text, $sub) = @_;                                                # Sub quarks, the name of the operator as a utf8 string, associated subroutine definition
  $parse->lexToSub("p", $text, $sub);                                           # Operator name in operator alphabet preceded by alphabet number
 }

sub suffix($$$)                                                                 # Define a method for a suffix operator.
 {my ($parse, $text, $sub) = @_;                                                # Sub quarks, the name of the operator as a utf8 string, associated subroutine definition
  $parse->lexToSub("q", $text, $sub);                                           # Operator name in operator alphabet preceded by alphabet number
 }

sub ascii($$)                                                                   # Define a method for ascii text.
 {my ($parse, $sub) = @_;                                                       # Sub quarks, associated subroutine definition
  my $n = $$Lex{lexicals}{Ascii}{number};                                       # Lexical number of ascii
  $parse->operators->putSub(chr($n), $sub);                                     # Add the ascii subroutine to the sub quarks
 }

sub semiColon($$)                                                               # Define a method for the semicolon operator which comes in two forms: the explicit semi colon and a new line semicolon.
 {my ($parse, $sub) = @_;                                                       # Sub quarks, associated subroutine definition
  my $n = $$Lex{lexicals}{semiColon}{number};                                   # Lexical number of semicolon
  $parse->operators->putSub(chr($n), $sub);                                     # Add the semicolon subroutine to the sub quarks
  my $N = $$Lex{lexicals}{NewLineSemiColon}{number};                            # New line semi colon
  $parse->operators->putSub(chr($N), $sub);                                     # Add the semicolon subroutine to the sub quarks
 }

sub variable($$)                                                                # Define a method for a variable.
 {my ($parse, $sub) = @_;                                                       # Sub quarks, associated subroutine definition
  my $n = $$Lex{lexicals}{variable}{number};                                    # Lexical number of a variable
  $parse->operators->putSub(chr($n), $sub);                                     # Add the variable subroutine to the sub quarks
 }

sub bracket($$$)                                                                # Define a method for a bracket operator.
 {my ($parse, $open, $sub) = @_;                                                # Sub quarks, opening parenthesis, associated subroutine
  my $l = &lexicalData;
  my $s = join '', sort $l->{bracketsOpen}->@*;#, $l->{bracketsClose}->@*;      # Bracket alphabet
  my $b = index($s, $open);
  $b < 0 and confess "No such bracket: $open";
  my $n = $$Lex{lexicals}{OpenBracket}{number};                                 # Lexical number of open bracket
  $parse->operators->putSub(chr($n).chr($b+1+$l->{bracketsBase}), $sub);        # Why plus one?  # Add the brackets subroutine to the sub quarks
 }

#D1 Alphabets                                                                   # Translate between alphabets.

sub showAlphabet($)                                                             #P Show an alphabet.
 {my ($alphabet) = @_;                                                          # Alphabet name
  my $out;
  my $lex = &lexicalData;
  my $abc = $lex->{alphabetsOrdered}{$alphabet};
  for my $a(@$abc)
   {$out .= chr($a);
   }
  $out
 }

sub asciiToAssignLatin($)                                                       # Translate ascii to the corresponding letters in the assign latin alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz/𝐴𝐵𝐶𝐷𝐸𝐹𝐺𝐻𝐼𝐽𝐾𝐿𝑀𝑁𝑂𝑃𝑄𝑅𝑆𝑇𝑈𝑉𝑊𝑋𝑌𝑍𝑎𝑏𝑐𝑑𝑒𝑓𝑔ℎ𝑖𝑗𝑘𝑙𝑚𝑛𝑜𝑝𝑞𝑟𝑠𝑡𝑢𝑣𝑤𝑥𝑦𝑧/r;
 }

sub asciiToAssignGreek($)                                                       # Translate ascii to the corresponding letters in the assign greek alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABGDEZNHIKLMVXOPRQSTUFCYWabgdeznhiklmvxoprqstufcyw/𝛢𝛣𝛤𝛥𝛦𝛧𝛨𝛩𝛪𝛫𝛬𝛭𝛮𝛯𝛰𝛱𝛲𝛳𝛴𝛵𝛶𝛷𝛸𝛹𝛺𝛼𝛽𝛾𝛿𝜀𝜁𝜂𝜃𝜄𝜅𝜆𝜇𝜈𝜉𝜊𝜋𝜌𝜍𝜎𝜏𝜐𝜑𝜒𝜓𝜔/r;
 }

sub asciiToDyadLatin($)                                                         # Translate ascii to the corresponding letters in the dyad latin alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz/𝐀𝐁𝐂𝐃𝐄𝐅𝐆𝐇𝐈𝐉𝐊𝐋𝐌𝐍𝐎𝐏𝐐𝐑𝐒𝐓𝐔𝐕𝐖𝐗𝐘𝐙𝐚𝐛𝐜𝐝𝐞𝐟𝐠𝐡𝐢𝐣𝐤𝐥𝐦𝐧𝐨𝐩𝐪𝐫𝐬𝐭𝐮𝐯𝐰𝐱𝐲𝐳/r;
 }

sub asciiToDyadGreek($)                                                         # Translate ascii to the corresponding letters in the dyad greek alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABGDEZNHIKLMVXOPRQSTUFCYWabgdeznhiklmvxoprqstufcyw/𝚨𝚩𝚪𝚫𝚬𝚭𝚮𝚯𝚰𝚱𝚲𝚳𝚴𝚵𝚶𝚷𝚸𝚹𝚺𝚻𝚼𝚽𝚾𝚿𝛀𝛂𝛃𝛄𝛅𝛆𝛇𝛈𝛉𝛊𝛋𝛌𝛍𝛎𝛏𝛐𝛑𝛒𝛓𝛔𝛕𝛖𝛗𝛘𝛙𝛚/r;
 }

sub asciiToPrefixLatin($)                                                       # Translate ascii to the corresponding letters in the prefix latin alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz/𝑨𝑩𝑪𝑫𝑬𝑭𝑮𝑯𝑰𝑱𝑲𝑳𝑴𝑵𝑶𝑷𝑸𝑹𝑺𝑻𝑼𝑽𝑾𝑿𝒀𝒁𝒂𝒃𝒄𝒅𝒆𝒇𝒈𝒉𝒊𝒋𝒌𝒍𝒎𝒏𝒐𝒑𝒒𝒓𝒔𝒕𝒖𝒗𝒘𝒙𝒚𝒛/r;
 }

sub asciiToPrefixGreek($)                                                       # Translate ascii to the corresponding letters in the prefix greek alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABGDEZNHIKLMVXOPRQSTUFCYWabgdeznhiklmvxoprqstufcyw/𝜜𝜝𝜞𝜟𝜠𝜡𝜢𝜣𝜤𝜥𝜦𝜧𝜨𝜩𝜪𝜫𝜬𝜭𝜮𝜯𝜰𝜱𝜲𝜳𝜴𝜶𝜷𝜸𝜹𝜺𝜻𝜼𝜽𝜾𝜿𝝀𝝁𝝂𝝃𝝄𝝅𝝆𝝇𝝈𝝉𝝊𝝋𝝌𝝍𝝎/r;
 }

sub asciiToSuffixLatin($)                                                       # Translate ascii to the corresponding letters in the suffix latin alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz/𝘼𝘽𝘾𝘿𝙀𝙁𝙂𝙃𝙄𝙅𝙆𝙇𝙈𝙉𝙊𝙋𝙌𝙍𝙎𝙏𝙐𝙑𝙒𝙓𝙔𝙕𝙖𝙗𝙘𝙙𝙚𝙛𝙜𝙝𝙞𝙟𝙠𝙡𝙢𝙣𝙤𝙥𝙦𝙧𝙨𝙩𝙪𝙫𝙬𝙭𝙮𝙯/r;
 }

sub asciiToSuffixGreek($)                                                       # Translate ascii to the corresponding letters in the suffix greek alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABGDEZNHIKLMVXOPRQSTUFCYWabgdeznhiklmvxoprqstufcyw/𝞐𝞑𝞒𝞓𝞔𝞕𝞖𝞗𝞘𝞙𝞚𝞛𝞜𝞝𝞞𝞟𝞠𝞡𝞢𝞣𝞤𝞥𝞦𝞧𝞨𝞪𝞫𝞬𝞭𝞮𝞯𝞰𝞱𝞲𝞳𝞴𝞵𝞶𝞷𝞸𝞹𝞺𝞻𝞼𝞽𝞾𝞿𝟀𝟁𝟂/r;
 }

sub asciiToVariableLatin($)                                                     # Translate ascii to the corresponding letters in the suffix latin alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz/𝗔𝗕𝗖𝗗𝗘𝗙𝗚𝗛𝗜𝗝𝗞𝗟𝗠𝗡𝗢𝗣𝗤𝗥𝗦𝗧𝗨𝗩𝗪𝗫𝗬𝗭𝗮𝗯𝗰𝗱𝗲𝗳𝗴𝗵𝗶𝗷𝗸𝗹𝗺𝗻𝗼𝗽𝗾𝗿𝘀𝘁𝘂𝘃𝘄𝘅𝘆𝘇/r;
 }

sub asciiToVariableGreek($)                                                     # Translate ascii to the corresponding letters in the suffix greek alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/ABGDEZNHIKLMVXOPRQSTUFCYWabgdeznhiklmvxoprqstufcyw/𝝖𝝗𝝘𝝙𝝚𝝛𝝜𝝝𝝞𝝟𝝠𝝡𝝢𝝣𝝤𝝥𝝦𝝧𝝨𝝩𝝪𝝫𝝬𝝭𝝮𝝰𝝱𝝲𝝳𝝴𝝵𝝶𝝷𝝸𝝹𝝺𝝻𝝼𝝽𝝾𝝿𝞀𝞁𝞂𝞃𝞄𝞅𝞆𝞇𝞈/r;
 }

sub asciiToEscaped($)                                                           # Translate ascii to the corresponding letters in the escaped ascii alphabet.
 {my ($in) = @_;                                                                # A string of ascii
  $in =~ tr/abcdefghijklmnopqrstuvwxyz/🅐🅑🅒🅓🅔🅕🅖🅗🅘🅙🅚🅛🅜🅝🅞🅟🅠🅡🅢🅣🅤🅥🅦🅧🅨🅩/r;
 }

sub semiColonChar()                                                             # Translate ascii to the corresponding letters in the escaped ascii alphabet.
 {chr(10210)
 }

#d
sub lexicalData {do {
  my $a = bless({
    alphabetChars    => {
                          A => [33 .. 126, 9398 .. 9449],
                          a => [
                                 8462,
                                 8592 .. 8702,
                                 119860 .. 119892,
                                 119894 .. 119911,
                                 120546 .. 120603,
                               ],
                          d => [119808 .. 119859, 120488 .. 120545],
                          e => [
                                 172,
                                 177,
                                 215,
                                 247,
                                 1014,
                                 1542,
                                 1543,
                                 1544,
                                 8203 .. 8260,
                                 8263 .. 8289,
                                 8293 .. 8297,
                                 8314,
                                 8315,
                                 8316,
                                 8330,
                                 8331,
                                 8332,
                                 8472,
                                 8512 .. 8516,
                                 8523,
                                 8704 .. 8967,
                                 8972 .. 9000,
                                 9004 .. 9215,
                                 9632 .. 9983,
                                 10176 .. 10209,
                                 10211,
                                 10212,
                                 10213,
                                 10224 .. 10626,
                                 10649 .. 10747,
                                 10750 .. 11096,
                                 11776 .. 11807,
                                 11818 .. 11824,
                                 64297,
                                 65122,
                                 65124,
                                 65125,
                                 65126,
                                 65291,
                                 65308,
                                 65309,
                                 65310,
                                 65372,
                                 65374,
                                 65506,
                                 126704,
                                 126705,
                               ],
                          p => [119912 .. 119963, 120604 .. 120661],
                          q => [120380 .. 120431, 120720 .. 120777],
                          s => [10210],
                          v => [120276 .. 120327, 120662 .. 120719],
                        },
    brackets         => 16,
    bracketsBase     => 16,
    bracketsClose    => [
                          "\x{2309}",
                          "\x{230B}",
                          "\x{232A}",
                          "\x{2769}",
                          "\x{276B}",
                          "\x{276D}",
                          "\x{276F}",
                          "\x{2771}",
                          "\x{2773}",
                          "\x{2775}",
                          "\x{27E7}",
                          "\x{27E9}",
                          "\x{27EB}",
                          "\x{27ED}",
                          "\x{27EF}",
                          "\x{2984}",
                          "\x{2986}",
                          "\x{2988}",
                          "\x{298A}",
                          "\x{298C}",
                          "\x{298E}",
                          "\x{2990}",
                          "\x{2992}",
                          "\x{2994}",
                          "\x{2996}",
                          "\x{2998}",
                          "\x{29FD}",
                          "\x{2E29}",
                          "\x{3009}",
                          "\x{300B}",
                          "\x{3011}",
                          "\x{3015}",
                          "\x{3017}",
                          "\x{3019}",
                          "\x{301B}",
                          "\x{FD3F}",
                          "\x{FF09}",
                          "\x{FF60}",
                        ],
    bracketsHigh     => [
                          "0x1300230b",
                          "0x1500232a",
                          "0x23002775",
                          "0x2d0027ef",
                          "0x43002998",
                          "0x450029fd",
                          "0x47002e29",
                          "0x4b00300b",
                          "0x4d003011",
                          "0x5500301b",
                          "0x5700fd3f",
                          "0x5900ff09",
                          "0x5b00ff60",
                          0,
                          0,
                          0,
                        ],
    bracketsLow      => [
                          "0x10002308",
                          "0x14002329",
                          "0x16002768",
                          "0x240027e6",
                          "0x2e002983",
                          "0x440029fc",
                          "0x46002e28",
                          "0x48003008",
                          "0x4c003010",
                          "0x4e003014",
                          "0x5600fd3e",
                          "0x5800ff08",
                          "0x5a00ff5f",
                          0,
                          0,
                          0,
                        ],
    bracketsOpen     => [
                          "\x{2308}",
                          "\x{230A}",
                          "\x{2329}",
                          "\x{2768}",
                          "\x{276A}",
                          "\x{276C}",
                          "\x{276E}",
                          "\x{2770}",
                          "\x{2772}",
                          "\x{2774}",
                          "\x{27E6}",
                          "\x{27E8}",
                          "\x{27EA}",
                          "\x{27EC}",
                          "\x{27EE}",
                          "\x{2983}",
                          "\x{2985}",
                          "\x{2987}",
                          "\x{2989}",
                          "\x{298B}",
                          "\x{298D}",
                          "\x{298F}",
                          "\x{2991}",
                          "\x{2993}",
                          "\x{2995}",
                          "\x{2997}",
                          "\x{29FC}",
                          "\x{2E28}",
                          "\x{3008}",
                          "\x{300A}",
                          "\x{3010}",
                          "\x{3014}",
                          "\x{3016}",
                          "\x{3018}",
                          "\x{301A}",
                          "\x{FD3E}",
                          "\x{FF08}",
                          "\x{FF5F}",
                        ],
    dyad2Blocks      => 3,
    dyad2BlockSize   => 16,
    dyad2Chars       => [
                          172,
                          177,
                          215,
                          247,
                          1014,
                          1542,
                          1543,
                          1544,
                          8203 .. 8260,
                          8263 .. 8289,
                          8293 .. 8297,
                          8314,
                          8315,
                          8316,
                          8330,
                          8331,
                          8332,
                          8472,
                          8512 .. 8516,
                          8523,
                          8704 .. 8967,
                          8972 .. 9000,
                          9004 .. 9215,
                          9632 .. 9983,
                          10176 .. 10209,
                          10211,
                          10212,
                          10213,
                          10224 .. 10626,
                          10649 .. 10747,
                          10750 .. 11096,
                          11776 .. 11807,
                          11818 .. 11824,
                          64297,
                          65122,
                          65124,
                          65125,
                          65126,
                          65291,
                          65308,
                          65309,
                          65310,
                          65372,
                          65374,
                          65506,
                          126704,
                          126705,
                        ],
    dyad2High        => [
                          172,
                          177,
                          215,
                          247,
                          1014,
                          1544,
                          8260,
                          8289,
                          8297,
                          8316,
                          8332,
                          8472,
                          8516,
                          8523,
                          8967,
                          9000,
                          9215,
                          9983,
                          10209,
                          10213,
                          10626,
                          10747,
                          11096,
                          11807,
                          11824,
                          64297,
                          65122,
                          65126,
                          65291,
                          65310,
                          65372,
                          65374,
                          65506,
                          126705,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                        ],
    dyad2Low         => [
                          172,
                          177,
                          215,
                          247,
                          1014,
                          1542,
                          8203,
                          8263,
                          8293,
                          8314,
                          8330,
                          8472,
                          8512,
                          8523,
                          8704,
                          8972,
                          9004,
                          9632,
                          10176,
                          10211,
                          10224,
                          10649,
                          10750,
                          11776,
                          11818,
                          64297,
                          65122,
                          65124,
                          65291,
                          65308,
                          65372,
                          65374,
                          65506,
                          126704,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0,
                        ],
    dyad2Offset      => [
                          172,
                          176,
                          213,
                          244,
                          1010,
                          1537,
                          8195,
                          8197,
                          8200,
                          8216,
                          8229,
                          8368,
                          8407,
                          8413,
                          8593,
                          8597,
                          8600,
                          9016,
                          9208,
                          9209,
                          9219,
                          9241,
                          9243,
                          9922,
                          9932,
                          62404,
                          63228,
                          63229,
                          63393,
                          63409,
                          63470,
                          63471,
                          63602,
                          124799,
                          -1907,
                          -1908,
                          -1909,
                          -1910,
                          -1911,
                          -1912,
                          -1913,
                          -1914,
                          -1915,
                          -1916,
                          -1917,
                          -1918,
                          -1919,
                          -1920,
                        ],
    lexicalHigh      => [
                          126,
                          8462,
                          16785918,
                          1577067753,
                          10210,
                          119859,
                          1879168084,
                          2432816231,
                          119963,
                          120327,
                          120431,
                          872535777,
                          2734806811,
                          872535893,
                          872535951,
                          872536009,
                        ],
    lexicalLow       => [
                          33554465,
                          83894542,
                          83894672,
                          33563830,
                          134227938,
                          50451456,
                          84005940,
                          84005974,
                          67228776,
                          100783572,
                          117560892,
                          50452136,
                          84006626,
                          67229468,
                          100783958,
                          117561232,
                        ],
    lexicals         => bless({
                          Ascii            => bless({
                                                comment => "Printable ASCII characters not including space, tab or new line. Extended with circled characters to act as escape sequences.",
                                                letter  => "A",
                                                like    => "v",
                                                name    => "Ascii",
                                                number  => 2,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          assign           => bless({
                                                comment => "Assign infix operator with right to left binding at priority 2",
                                                letter  => "a",
                                                like    => "a",
                                                name    => "assign",
                                                number  => 5,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          CloseBracket     => bless({
                                                comment => "The lowest bit of a close bracket code is one ",
                                                letter  => "B",
                                                like    => "B",
                                                name    => "CloseBracket",
                                                number  => 1,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          dyad             => bless({
                                                comment => "Infix operator with left to right binding at priority 3",
                                                letter  => "d",
                                                like    => "d",
                                                name    => "dyad",
                                                number  => 3,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          dyad2            => bless({
                                                comment => "Infix operator with left to right binding at priority 4",
                                                letter  => "e",
                                                like    => "e",
                                                name    => "dyad2",
                                                number  => 13,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          empty            => bless({
                                                comment => "Empty term present between two adjacent semicolons",
                                                letter  => "E",
                                                like    => "E",
                                                name    => "empty",
                                                number  => 10,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          NewLineSemiColon => bless({
                                                comment => "A new line character that is also acting as a semi colon",
                                                letter  => "N",
                                                like    => undef,
                                                name    => "NewLineSemiColon",
                                                number  => 12,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          OpenBracket      => bless({
                                                comment => "The lowest bit of an open bracket code is zero",
                                                letter  => "b",
                                                like    => "b",
                                                name    => "OpenBracket",
                                                number  => 0,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          prefix           => bless({
                                                comment => "Prefix operator - applies only to the following variable or bracketed term",
                                                letter  => "p",
                                                like    => "p",
                                                name    => "prefix",
                                                number  => 4,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          semiColon        => bless({
                                                comment => "Infix operator with left to right binding at priority 1",
                                                letter  => "s",
                                                like    => "s",
                                                name    => "semiColon",
                                                number  => 8,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          suffix           => bless({
                                                comment => "Suffix operator - applies only to the preceding variable or bracketed term",
                                                letter  => "q",
                                                like    => "q",
                                                name    => "suffix",
                                                number  => 7,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          term             => bless({
                                                comment => "Term in the parse tree",
                                                letter  => "t",
                                                like    => "t",
                                                name    => "term",
                                                number  => 9,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          variable         => bless({
                                                comment => "Variable names",
                                                letter  => "v",
                                                like    => "v",
                                                name    => "variable",
                                                number  => 6,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                          WhiteSpace       => bless({
                                                comment => "White space that can be ignored during lexical analysis",
                                                letter  => "W",
                                                like    => undef,
                                                name    => "WhiteSpace",
                                                number  => 11,
                                              }, "Unisyn::Parse::Lexical::Constant"),
                        }, "Unisyn::Parse::Lexicals"),
    lexicalsByLetter => {
                          A => 'fix',
                          a => 'fix',
                          b => 'fix',
                          B => 'fix',
                          d => 'fix',
                          E => 'fix',
                          e => 'fix',
                          N => 'fix',
                          p => 'fix',
                          q => 'fix',
                          s => 'fix',
                          t => 'fix',
                          v => 'fix',
                          W => 'fix',
                        },
    sampleLexicals   => {
                          A             => [
                                             100663296,
                                             83886080,
                                             33554497,
                                             33554464,
                                             33554497,
                                             33554464,
                                             33554464,
                                             33554464,
                                             33554464,
                                           ],
                          add           => [
                                             100663296,
                                             83886080,
                                             100663296,
                                             50331648,
                                             100663296,
                                             50331648,
                                             100663296,
                                           ],
                          ade           => [
                                             100663296,
                                             83886080,
                                             100663296,
                                             50331648,
                                             100663296,
                                             218103808,
                                             100663296,
                                           ],
                          Adv           => [
                                             100663296,
                                             83886080,
                                             33554497,
                                             33554464,
                                             33554497,
                                             33554464,
                                             33554464,
                                             33554464,
                                             33554464,
                                             50331648,
                                             100663296,
                                           ],
                          BB            => [
                                             0,
                                             0,
                                             0,
                                             0,
                                             0,
                                             0,
                                             0,
                                             0,
                                             100663296,
                                             16777216,
                                             16777216,
                                             16777216,
                                             16777216,
                                             16777216,
                                             16777216,
                                             16777216,
                                             16777216,
                                           ],
                          brackets      => [
                                             100663296,
                                             83886080,
                                             0,
                                             0,
                                             0,
                                             100663296,
                                             16777216,
                                             16777216,
                                             50331648,
                                             0,
                                             100663296,
                                             16777216,
                                             16777216,
                                             134217728,
                                           ],
                          bvB           => [0, 100663296, 16777216],
                          e             => [100663296, 218103808, 100663296],
                          nosemi        => [
                                             100663296,
                                             83886080,
                                             0,
                                             0,
                                             0,
                                             100663296,
                                             16777216,
                                             16777216,
                                             50331648,
                                             0,
                                             100663296,
                                             16777216,
                                             16777216,
                                           ],
                          ppppvdvdvqqqq => [
                                             0,
                                             0,
                                             0,
                                             100663296,
                                             83886080,
                                             100663296,
                                             50331648,
                                             0,
                                             100663296,
                                             50331648,
                                             100663296,
                                             16777216,
                                             134217728,
                                             100663296,
                                             83886080,
                                             100663296,
                                             50331648,
                                             100663296,
                                             16777216,
                                             16777216,
                                             16777216,
                                           ],
                          s             => [100663296, 134217728, 100663296],
                          s1            => [
                                             100663296,
                                             83886080,
                                             33554442,
                                             33554464,
                                             33554464,
                                             33554497,
                                             33554442,
                                             33554464,
                                             33554464,
                                             33554464,
                                           ],
                          v             => [100663296],
                          vav           => [100663296, 83886080, 100663296],
                          vavav         => [100663296, 83886080, 100663296, 83886080, 100663296],
                          vnsvs         => [
                                             100663296,
                                             33554442,
                                             33554464,
                                             33554464,
                                             33554464,
                                             100663296,
                                             33554464,
                                             33554464,
                                             33554464,
                                           ],
                          vnv           => [100663296, 33554442, 100663296],
                          vnvs          => [
                                             100663296,
                                             33554442,
                                             100663296,
                                             33554464,
                                             33554464,
                                             33554464,
                                             33554464,
                                           ],
                          ws            => [
                                             100663296,
                                             83886080,
                                             0,
                                             0,
                                             0,
                                             100663296,
                                             16777216,
                                             16777216,
                                             50331648,
                                             0,
                                             100663296,
                                             16777216,
                                             16777216,
                                             134217728,
                                             100663296,
                                             83886080,
                                             0,
                                             100663296,
                                             50331648,
                                             100663296,
                                             16777216,
                                             134217728,
                                           ],
                          wsa           => [
                                             100663296,
                                             83886080,
                                             0,
                                             0,
                                             0,
                                             100663296,
                                             16777216,
                                             16777216,
                                             50331648,
                                             0,
                                             100663296,
                                             16777216,
                                             16777216,
                                             134217728,
                                             100663296,
                                             83886080,
                                             33554497,
                                             50331648,
                                             100663296,
                                             134217728,
                                           ],
                        },
    sampleText       => {
                          A             => "\x{1D5EE}\x{1D5EE}\x{1D452}\x{1D45E}\x{1D462}\x{1D44E}\x{1D459}\x{1D460}abc 123    ",
                          add           => "\x{1D5EE}\x{1D44E}\x{1D460}\x{1D460}\x{1D456}\x{1D454}\x{1D45B}\x{1D5EF}\x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{1D5F0}\x{1D41D}\x{1D422}\x{1D42F}\x{1D422}\x{1D41D}\x{1D41E}\x{1D5F1}",
                          ade           => "\x{1D5EE}\x{1D44E}\x{1D460}\x{1D460}\x{1D456}\x{1D454}\x{1D45B}\x{1D5EF}\x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{1D5F0}\xF7\x{1D5F1}",
                          Adv           => "\x{1D5EE}\x{1D5EE}\x{1D452}\x{1D45E}\x{1D462}\x{1D44E}\x{1D459}\x{1D460}abc 123    \x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{1D603}\x{1D5EE}\x{1D5FF}",
                          BB            => "\x{230A}\x{2329}\x{2768}\x{276A}\x{276C}\x{276E}\x{2770}\x{2772}\x{1D5EE}\x{2773}\x{2771}\x{276F}\x{276D}\x{276B}\x{2769}\x{232A}\x{230B}",
                          brackets      => "\x{1D5EE}\x{1D44E}\x{1D460}\x{1D460}\x{1D456}\x{1D454}\x{1D45B}\x{230A}\x{2329}\x{2768}\x{1D5EF}\x{1D5FD}\x{2769}\x{232A}\x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{276A}\x{1D600}\x{1D5F0}\x{276B}\x{230B}\x{27E2}",
                          bvB           => "\x{2329}\x{1D5EE}\x{1D5EF}\x{1D5F0}\x{232A}",
                          e             => "\x{1D5EE}\xF7\x{1D5EF}",
                          nosemi        => "\x{1D5EE}\x{1D44E}\x{1D460}\x{1D460}\x{1D456}\x{1D454}\x{1D45B}\x{230A}\x{2329}\x{2768}\x{1D5EF}\x{1D5FD}\x{2769}\x{232A}\x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{276A}\x{1D600}\x{1D5F0}\x{276B}\x{230B}",
                          ppppvdvdvqqqq => "\x{1D482}\x{2774}\x{1D483}\x{27E6}\x{1D484}\x{27E8}\x{1D5EE}\x{1D452}\x{1D45E}\x{1D462}\x{1D44E}\x{1D459}\x{1D460}\x{1D485}\x{1D5EF}\x{1D659}\x{1D42D}\x{1D422}\x{1D426}\x{1D41E}\x{1D42C}\x{27EA}\x{1D5F0}\x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{1D5F1}\x{27EB}\x{27E2}\x{1D5F2}\x{1D44E}\x{1D460}\x{1D460}\x{1D456}\x{1D454}\x{1D45B}\x{1D5F3}\x{1D42C}\x{1D42E}\x{1D41B}\x{1D5F4}\x{1D65D}\x{27E9}\x{1D658}\x{27E7}\x{1D657}\x{2775}\x{1D656}",
                          s             => "\x{1D5EE}\x{27E2}\x{1D5EF}",
                          s1            => "\x{1D5EE}\x{1D44E}\n  \n   ",
                          v             => "\x{1D5EE}",
                          vav           => "\x{1D5EE}\x{1D44E}\x{1D5EF}",
                          vavav         => "\x{1D5EE}\x{1D44E}\x{1D5EF}\x{1D44E}\x{1D5F0}",
                          vnsvs         => "\x{1D5EE}\x{1D5EE}\n   \x{1D5EF}\x{1D5EF}   ",
                          vnv           => "\x{1D5EE}\n\x{1D5EF}",
                          vnvs          => "\x{1D5EE}\n\x{1D5EF}    ",
                          ws            => "\x{1D5EE}\x{1D44E}\x{1D460}\x{1D460}\x{1D456}\x{1D454}\x{1D45B}\x{230A}\x{2329}\x{2768}\x{1D5EF}\x{1D5FD}\x{2769}\x{232A}\x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{276A}\x{1D600}\x{1D5F0}\x{276B}\x{230B}\x{27E2}\x{1D5EE}\x{1D5EE}\x{1D44E}\x{1D460}\x{1D460}\x{1D456}\x{1D454}\x{1D45B}\x{276C}\x{1D5EF}\x{1D5EF}\x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{1D5F0}\x{1D5F0}\x{276D}\x{27E2}",
                          wsa           => "\x{1D5EE}\x{1D44E}\x{1D460}\x{1D460}\x{1D456}\x{1D454}\x{1D45B}\x{230A}\x{2329}\x{2768}\x{1D5EF}\x{1D5FD}\x{2769}\x{232A}\x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{276A}\x{1D600}\x{1D5F0}\x{276B}\x{230B}\x{27E2}\x{1D5EE}\x{1D5EE}\x{1D44E}\x{1D460}\x{1D460}\x{1D456}\x{1D454}\x{1D45B}some--ascii--text\x{1D429}\x{1D425}\x{1D42E}\x{1D42C}\x{1D5F0}\x{1D5F0}\x{27E2}",
                        },
    semiColon        => "\x{27E2}",
    separator        => "\x{205F}",
    structure        => bless({
                          codes => bless({
                                     a => bless({
                                            letter => "a",
                                            name   => "assignment operator",
                                            next   => "bpv",
                                            short  => "assign",
                                          }, "Tree::Term::LexicalCode"),
                                     B => bless({
                                            letter => "B",
                                            name   => "closing parenthesis",
                                            next   => "aBdeqs",
                                            short  => "CloseBracket",
                                          }, "Tree::Term::LexicalCode"),
                                     b => bless({
                                            letter => "b",
                                            name   => "opening parenthesis",
                                            next   => "bBpsv",
                                            short  => "OpenBracket",
                                          }, "Tree::Term::LexicalCode"),
                                     d => bless({ letter => "d", name => "dyadic operator", next => "bpv", short => "dyad" }, "Tree::Term::LexicalCode"),
                                     e => bless({ letter => "e", name => "dyad2 operator", next => "bpv", short => "dyad2" }, "Tree::Term::LexicalCode"),
                                     p => bless({ letter => "p", name => "prefix operator", next => "bpv", short => "prefix" }, "Tree::Term::LexicalCode"),
                                     q => bless({
                                            letter => "q",
                                            name   => "suffix operator",
                                            next   => "aBdeqs",
                                            short  => "suffix",
                                          }, "Tree::Term::LexicalCode"),
                                     s => bless({ letter => "s", name => "semi-colon", next => "bBpsv", short => "semiColon" }, "Tree::Term::LexicalCode"),
                                     t => bless({ letter => "t", name => "term", next => "aBdeqs", short => "term" }, "Tree::Term::LexicalCode"),
                                     v => bless({ letter => "v", name => "variable", next => "aBdeqs", short => "variable" }, "Tree::Term::LexicalCode"),
                                   }, "Tree::Term::Codes"),
                          first => "bpsv",
                          last  => "Bqsv",
                        }, "Tree::Term::LexicalStructure"),
    treeTermLexicals => 'fix',
  }, "Unisyn::Parse::Lexical::Tables");
  $a->{lexicalsByLetter}{A} = $a->{lexicals}{Ascii};
  $a->{lexicalsByLetter}{a} = $a->{lexicals}{assign};
  $a->{lexicalsByLetter}{b} = $a->{lexicals}{OpenBracket};
  $a->{lexicalsByLetter}{B} = $a->{lexicals}{CloseBracket};
  $a->{lexicalsByLetter}{d} = $a->{lexicals}{dyad};
  $a->{lexicalsByLetter}{E} = $a->{lexicals}{empty};
  $a->{lexicalsByLetter}{e} = $a->{lexicals}{dyad2};
  $a->{lexicalsByLetter}{N} = $a->{lexicals}{NewLineSemiColon};
  $a->{lexicalsByLetter}{p} = $a->{lexicals}{prefix};
  $a->{lexicalsByLetter}{q} = $a->{lexicals}{suffix};
  $a->{lexicalsByLetter}{s} = $a->{lexicals}{semiColon};
  $a->{lexicalsByLetter}{t} = $a->{lexicals}{term};
  $a->{lexicalsByLetter}{v} = $a->{lexicals}{variable};
  $a->{lexicalsByLetter}{W} = $a->{lexicals}{WhiteSpace};
  $a->{treeTermLexicals} = $a->{structure}{codes};
  $a;
}}

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

Unisyn::Parse - Parse a Unisyn expression.

=head1 Synopsis

Parse the B<Unisyn> expression:

  𝒂 ❴ 𝒃 ⟦𝒄⟨ 𝗮 𝑒𝑞𝑢𝑎𝑙𝑠 𝒅 𝗯 𝙙 𝐭𝐢𝐦𝐞𝐬 ⟪𝗰 𝐩𝐥𝐮𝐬 𝗱⟫⟢  𝗲 𝑎𝑠𝑠𝑖𝑔𝑛 𝗳 𝐬𝐮𝐛 𝗴 𝙝⟩ 𝙘 ⟧ 𝙗 ❵ 𝙖

To get:

  Suffix: 𝙖
    Term
      Prefix: 𝒂
        Term
          Brackets: ⦇⦈
            Term
              Term
                Suffix: 𝙗
                  Term
                    Prefix: 𝒃
                      Term
                        Brackets: ⦋⦌
                          Term
                            Term
                              Suffix: 𝙘
                                Term
                                  Prefix: 𝒄
                                    Term
                                      Brackets: ⦏⦐
                                        Term
                                          Term
                                            Semicolon
                                              Term
                                                Assign: 𝑒𝑞𝑢𝑎𝑙𝑠
                                                  Term
                                                    Variable: 𝗮
                                                  Term
                                                    Dyad: 𝐭𝐢𝐦𝐞𝐬
                                                      Term
                                                        Suffix: 𝙙
                                                          Term
                                                            Prefix: 𝒅
                                                              Term
                                                                Variable: 𝗯
                                                      Term
                                                        Brackets: ⦓⦔
                                                          Term
                                                            Term
                                                              Dyad: 𝐩𝐥𝐮𝐬
                                                                Term
                                                                  Variable: 𝗰
                                                                Term
                                                                  Variable: 𝗱
                                              Term
                                                Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
                                                  Term
                                                    Variable: 𝗲
                                                  Term
                                                    Dyad: 𝐬𝐮𝐛
                                                      Term
                                                        Variable: 𝗳
                                                      Term
                                                        Suffix: 𝙝
                                                          Term
                                                            Variable: 𝗴

Then traverse the parse tree printing the type of each node:

  variable
  variable
  prefix_d
  suffix_d
  variable
  variable
  plus
  times
  equals
  variable
  variable
  variable
  sub
  assign
  semiColon
  brackets_3
  prefix_c
  suffix_c
  brackets_2
  prefix_b
  suffix_b
  brackets_1
  prefix_a
  suffix_a

=head1 Description

Parse a Unisyn expression.


Version "20211013".


The following sections describe the methods in each functional area of this
module.  For an alphabetic listing of all methods by name see L<Index|/Index>.



=head1 Create

Create a Unisyn parse of a utf8 string.

=head2 create($address, %options)

Create a new unisyn parse from a utf8 string.

     Parameter  Description
  1  $address   Address of a zero terminated utf8 source string to parse as a variable
  2  %options   Parse options.

B<Example:>



    create (K(address, Rutf8 $Lex->{sampleText}{vav}))->print;                    # Create parse tree from source terminated with zero  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲


    ok Assemble(debug => 0, eq => <<END);
  Assign: 𝑎
    Term
      Variable: 𝗮
    Term
      Variable: 𝗯
  END


=head1 Parse

Parse Unisyn expressions

=head1 Traverse

Traverse the parse tree

=head2 traverseParseTree($parse)

Traverse the terms in parse tree in post order and call the operator subroutine associated with each term.

     Parameter  Description
  1  $parse     Parse tree

B<Example:>


    my $s = Rutf8 $Lex->{sampleText}{Adv};                                        # Ascii
    my $p = create K(address, $s), operators => \&printOperatorSequence;

    K(address, $s)->printOutZeroString;
    $p->dumpParseTree;
    $p->print;

    $p->traverseParseTree;  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲


    Assemble(debug => 0, eq => <<END)
  𝗮𝗮𝑒𝑞𝑢𝑎𝑙𝑠abc 123    𝐩𝐥𝐮𝐬𝘃𝗮𝗿
  Tree at:  0000 0000 0000 10D8  length: 0000 0000 0000 000B
    Keys: 0000 1118 0500 000B   0000 0000 0000 0000   0000 0000 0000 000D   0000 000C 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 0016   0000 0000 0000 0000   0000 0000 0000 0F18   0000 0009 0000 0AD8   0000 0009 0000 0004   0000 0006 0000 0002   0000 0005 0041 26A4   0000 0003 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 26A4
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0005
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0004
      index: 0000 0000 0000 0007   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0008   key: 0000 0000 0000 0009   data: 0000 0000 0000 0AD8 subTree
      index: 0000 0000 0000 0009   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
      index: 0000 0000 0000 000A   key: 0000 0000 0000 000D   data: 0000 0000 0000 0F18 subTree
    Tree at:  0000 0000 0000 0AD8  length: 0000 0000 0000 0007
      Keys: 0000 0B18 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
      Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0002 0000 0000   0000 0006 0041 176C   0000 0001 0000 0009
      Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
        index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
        index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
        index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 176C
        index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
        index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
        index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0002
        index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
    end
    Tree at:  0000 0000 0000 0F18  length: 0000 0000 0000 000B
      Keys: 0000 0F58 0500 000B   0000 0000 0000 0000   0000 0000 0000 000D   0000 000C 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
      Data: 0000 0000 0000 0016   0000 0000 0000 0000   0000 0000 0000 0DD8   0000 0009 0000 0C18   0000 0009 0000 0003   0000 0004 0000 0013   0000 0003 0041 2E40   0000 0003 0000 0009
      Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
        index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
        index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
        index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 2E40
        index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0003
        index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0013
        index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0004
        index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0003
        index: 0000 0000 0000 0007   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
        index: 0000 0000 0000 0008   key: 0000 0000 0000 0009   data: 0000 0000 0000 0C18 subTree
        index: 0000 0000 0000 0009   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
        index: 0000 0000 0000 000A   key: 0000 0000 0000 000D   data: 0000 0000 0000 0DD8 subTree
      Tree at:  0000 0000 0000 0C18  length: 0000 0000 0000 0007
        Keys: 0000 0C58 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
        Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0007 0000 0008   0000 0002 0041 53FE   0000 0001 0000 0009
        Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
          index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
          index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
          index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 53FE
          index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0002
          index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0008
          index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0007
          index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
      end
      Tree at:  0000 0000 0000 0DD8  length: 0000 0000 0000 0007
        Keys: 0000 0E18 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
        Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0002   0000 0003 0000 0017   0000 0006 0041 176C   0000 0001 0000 0009
        Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
          index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
          index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
          index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 176C
          index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
          index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0017
          index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0003
          index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
      end
    end
  end
  Assign: 𝑒𝑞𝑢𝑎𝑙𝑠
    Term
      Variable: 𝗮𝗮
    Term
      Dyad: 𝐩𝐥𝐮𝐬
        Term
          Ascii: abc 123
        Term
          Variable: 𝘃𝗮𝗿
  variable
  ascii
  variable
  plus
  equals
  END

    my $s = Rutf8 $Lex->{sampleText}{ws};
    my $p = create (K(address, $s), operators => \&printOperatorSequence);

    K(address, $s)->printOutZeroString;                                           # Print input string
    $p->print;                                                                    # Print parse

    $p->traverseParseTree;                                                        # Traverse tree printing terms  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲


    Assemble(debug => 0, eq => <<END)
  𝗮𝑎𝑠𝑠𝑖𝑔𝑛⌊〈❨𝗯𝗽❩〉𝐩𝐥𝐮𝐬❪𝘀𝗰❫⌋⟢𝗮𝗮𝑎𝑠𝑠𝑖𝑔𝑛❬𝗯𝗯𝐩𝐥𝐮𝐬𝗰𝗰❭⟢
  Semicolon
    Term
      Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
        Term
          Variable: 𝗮
        Term
          Brackets: ⌊⌋
            Term
              Term
                Dyad: 𝐩𝐥𝐮𝐬
                  Term
                    Brackets: ❨❩
                      Term
                        Term
                          Brackets: ❬❭
                            Term
                              Term
                                Variable: 𝗯𝗽
                  Term
                    Brackets: ❰❱
                      Term
                        Term
                          Variable: 𝘀𝗰
    Term
      Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
        Term
          Variable: 𝗮𝗮
        Term
          Brackets: ❴❵
            Term
              Term
                Dyad: 𝐩𝐥𝐮𝐬
                  Term
                    Variable: 𝗯𝗯
                  Term
                    Variable: 𝗰𝗰
  variable
  variable
  variable
  plus
  assign
  variable
  variable
  variable
  plus
  assign
  semiColon
  END


=head2 makeExecutionChain($parse)

Traverse the parse tree in post order to create an execution chain.

     Parameter  Description
  1  $parse     Parse tree

=head1 Print

Print a parse tree

=head2 print($parse)

Print a parse tree.

     Parameter  Description
  1  $parse     Parse tree

B<Example:>



    create (K(address, Rutf8 $Lex->{sampleText}{vav}))->print;                    # Create parse tree from source terminated with zero  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲


    ok Assemble(debug => 0, eq => <<END);
  Assign: 𝑎
    Term
      Variable: 𝗮
    Term
      Variable: 𝗯
  END


=head2 dumpParseTree($parse)

Dump the parse tree.

     Parameter  Description
  1  $parse     Parse tree

=head1 Execute

Associate methods with each operator via a set of quarks describing the method to be called for each lexical operator.

=head2 lexToSub($parse, $alphabet, $op, $sub)

Map a lexical item to a processing subroutine.

     Parameter  Description
  1  $parse     Sub quarks
  2  $alphabet  The alphabet number
  3  $op        The operator name in that alphabet
  4  $sub       Subroutine definition

=head2 dyad($parse, $text, $sub)

Define a method for a dyadic operator.

     Parameter  Description
  1  $parse     Sub quarks
  2  $text      The name of the operator as a utf8 string
  3  $sub       Associated subroutine definition

=head2 assign($parse, $text, $sub)

Define a method for an assign operator.

     Parameter  Description
  1  $parse     Sub quarks
  2  $text      The name of the operator as a utf8 string
  3  $sub       Associated subroutine definition

=head2 prefix($parse, $text, $sub)

Define a method for a prefix operator.

     Parameter  Description
  1  $parse     Sub quarks
  2  $text      The name of the operator as a utf8 string
  3  $sub       Associated subroutine definition

=head2 suffix($parse, $text, $sub)

Define a method for a suffix operator.

     Parameter  Description
  1  $parse     Sub quarks
  2  $text      The name of the operator as a utf8 string
  3  $sub       Associated subroutine definition

=head2 ascii($parse, $sub)

Define a method for ascii text.

     Parameter  Description
  1  $parse     Sub quarks
  2  $sub       Associated subroutine definition

=head2 semiColon($parse, $sub)

Define a method for the semicolon operator which comes in two forms: the explicit semi colon and a new line semicolon.

     Parameter  Description
  1  $parse     Sub quarks
  2  $sub       Associated subroutine definition

=head2 variable($parse, $sub)

Define a method for a variable.

     Parameter  Description
  1  $parse     Sub quarks
  2  $sub       Associated subroutine definition

=head2 bracket($parse, $open, $sub)

Define a method for a bracket operator.

     Parameter  Description
  1  $parse     Sub quarks
  2  $open      Opening parenthesis
  3  $sub       Associated subroutine

=head1 Alphabets

Translate between alphabets.

=head2 asciiToAssignLatin($in)

Translate ascii to the corresponding letters in the assign latin alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToAssignGreek($in)

Translate ascii to the corresponding letters in the assign greek alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToDyadLatin($in)

Translate ascii to the corresponding letters in the dyad latin alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToDyadGreek($in)

Translate ascii to the corresponding letters in the dyad greek alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToPrefixLatin($in)

Translate ascii to the corresponding letters in the prefix latin alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToPrefixGreek($in)

Translate ascii to the corresponding letters in the prefix greek alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToSuffixLatin($in)

Translate ascii to the corresponding letters in the suffix latin alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToSuffixGreek($in)

Translate ascii to the corresponding letters in the suffix greek alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToVariableLatin($in)

Translate ascii to the corresponding letters in the suffix latin alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToVariableGreek($in)

Translate ascii to the corresponding letters in the suffix greek alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 asciiToEscaped($in)

Translate ascii to the corresponding letters in the escaped ascii alphabet.

     Parameter  Description
  1  $in        A string of ascii

=head2 semiColonChar()

Translate ascii to the corresponding letters in the escaped ascii alphabet.


=head2 printOperatorSequence($parse)

Print the operator calling sequence.

     Parameter  Description
  1  $parse     Parse

=head2 executeOperator($parse)

Print the operator calling sequence.

     Parameter  Description
  1  $parse     Parse


=head1 Hash Definitions




=head2 Unisyn::Parse Definition


Description of parse




=head3 Output fields


=head4 address8

Address of source string as utf8

=head4 arena

Arena containing tree

=head4 fails

Number of failures encountered in this parse

=head4 operators

Methods implementing each lexical operator

=head4 parse

Offset to the head of the parse tree

=head4 quarks

Quarks representing the strings used in this parse

=head4 size8

Size of source string as utf8

=head4 source32

Source text as utf32

=head4 sourceLength32

Length of utf32 string

=head4 sourceSize32

Size of utf32 allocation

=head4 width

Size of entries in exec chain



=head1 Private Methods

=head2 getAlpha($register, $address, $index)

Load the position of a lexical item in its alphabet from the current character.

     Parameter  Description
  1  $register  Register to load
  2  $address   Address of start of string
  3  $index     Index into string

=head2 getLexicalCode($register, $address, $index)

Load the lexical code of the current character in memory into the specified register.

     Parameter  Description
  1  $register  Register to load
  2  $address   Address of start of string
  3  $index     Index into string

=head2 putLexicalCode($register, $address, $index, $code)

Put the specified lexical code into the current character in memory.

     Parameter  Description
  1  $register  Register used to load code
  2  $address   Address of string
  3  $index     Index into string
  4  $code      Code to put

=head2 loadCurrentChar()

Load the details of the character currently being processed so that we have the index of the character in the upper half of the current character and the lexical type of the character in the lowest byte.


=head2 checkStackHas($depth)

Check that we have at least the specified number of elements on the stack.

     Parameter  Description
  1  $depth     Number of elements required on the stack

=head2 pushElement()

Push the current element on to the stack.


=head2 pushEmpty()

Push the empty element on to the stack.


=head2 lexicalNameFromLetter($l)

Lexical name for a lexical item described by its letter.

     Parameter  Description
  1  $l         Letter of the lexical item

=head2 lexicalNumberFromLetter($l)

Lexical number for a lexical item described by its letter.

     Parameter  Description
  1  $l         Letter of the lexical item

=head2 lexicalItemLength($source32, $offset)

Put the length of a lexical item into variable B<size>.

     Parameter  Description
  1  $source32  B<address> of utf32 source representation
  2  $offset    B<offset> to lexical item in utf32

=head2 new($depth, $description)

Create a new term in the parse tree rooted on the stack.

     Parameter     Description
  1  $depth        Stack depth to be converted
  2  $description  Text reason why we are creating a new term

=head2 error($message)

Write an error message and stop.

     Parameter  Description
  1  $message   Error message

=head2 testSet($set, $register)

Test a set of items, setting the Zero Flag is one matches else clear the Zero flag.

     Parameter  Description
  1  $set       Set of lexical letters
  2  $register  Register to test

=head2 checkSet($set)

Check that one of a set of items is on the top of the stack or complain if it is not.

     Parameter  Description
  1  $set       Set of lexical letters

=head2 reduce($priority)

Convert the longest possible expression on top of the stack into a term  at the specified priority.

     Parameter  Description
  1  $priority  Priority of the operators to reduce

=head2 reduceMultiple($priority)

Reduce existing operators on the stack.

     Parameter  Description
  1  $priority  Priority of the operators to reduce

=head2 accept_a()

Assign.


=head2 accept_b()

Open.


=head2 accept_B()

Closing parenthesis.


=head2 accept_d()

Infix but not assign or semi-colon.


=head2 accept_p()

Prefix.


=head2 accept_q()

Post fix.


=head2 accept_s()

Semi colon.


=head2 accept_v()

Variable.


=head2 parseExpression()

Parse the string of classified lexical items addressed by register $start of length $length.  The resulting parse tree (if any) is returned in r15.


=head2 MatchBrackets(@parameters)

Replace the low three bytes of a utf32 bracket character with 24 bits of offset to the matching opening or closing bracket. Opening brackets have even codes from 0x10 to 0x4e while the corresponding closing bracket has a code one higher.

     Parameter    Description
  1  @parameters  Parameters

=head2 ClassifyNewLines(@parameters)

Scan input string looking for opportunities to convert new lines into semi colons.

     Parameter    Description
  1  @parameters  Parameters

=head2 ClassifyWhiteSpace(@parameters)

Classify white space per: "lib/Unisyn/whiteSpace/whiteSpaceClassification.pl".

     Parameter    Description
  1  @parameters  Parameters

=head2 reload($parse, $parameters)

Reload the variables associated with a parse.

     Parameter    Description
  1  $parse       Parse
  2  $parameters  Hash of variable parameters

=head2 parseUtf8($parse, @parameters)

Parse a unisyn expression encoded as utf8 and return the parse tree.

     Parameter    Description
  1  $parse       Parse
  2  @parameters  Parameters

=head2 printExecChain($parse)

Print the execute chain for a parse

     Parameter  Description
  1  $parse     Parse tree

=head2 printLexicalItem($parse, $source32, $offset, $size)

Print the utf8 string corresponding to a lexical item at a variable offset.

     Parameter  Description
  1  $parse     Parse tree
  2  $source32  B<address> of utf32 source representation
  3  $offset    B<offset> to lexical item in utf32
  4  $size      B<size> in utf32 chars of item

=head2 showAlphabet($alphabet)

Show an alphabet.

     Parameter  Description
  1  $alphabet  Alphabet name

=head2 T($key, $expected, %options)

Parse some text and dump the results.

     Parameter  Description
  1  $key       Key of text to be parsed
  2  $expected  Expected result
  3  %options   Options

=head2 C($key, $expected, %options)

Parse some text and print the results.

     Parameter  Description
  1  $key       Key of text to be parsed
  2  $expected  Expected result
  3  %options   Options


=head1 Index


1 L<accept_a|/accept_a> - Assign.

2 L<accept_B|/accept_B> - Closing parenthesis.

3 L<accept_b|/accept_b> - Open.

4 L<accept_d|/accept_d> - Infix but not assign or semi-colon.

5 L<accept_p|/accept_p> - Prefix.

6 L<accept_q|/accept_q> - Post fix.

7 L<accept_s|/accept_s> - Semi colon.

8 L<accept_v|/accept_v> - Variable.

9 L<ascii|/ascii> - Define a method for ascii text.

10 L<asciiToAssignGreek|/asciiToAssignGreek> - Translate ascii to the corresponding letters in the assign greek alphabet.

11 L<asciiToAssignLatin|/asciiToAssignLatin> - Translate ascii to the corresponding letters in the assign latin alphabet.

12 L<asciiToDyadGreek|/asciiToDyadGreek> - Translate ascii to the corresponding letters in the dyad greek alphabet.

13 L<asciiToDyadLatin|/asciiToDyadLatin> - Translate ascii to the corresponding letters in the dyad latin alphabet.

14 L<asciiToEscaped|/asciiToEscaped> - Translate ascii to the corresponding letters in the escaped ascii alphabet.

15 L<asciiToPrefixGreek|/asciiToPrefixGreek> - Translate ascii to the corresponding letters in the prefix greek alphabet.

16 L<asciiToPrefixLatin|/asciiToPrefixLatin> - Translate ascii to the corresponding letters in the prefix latin alphabet.

17 L<asciiToSuffixGreek|/asciiToSuffixGreek> - Translate ascii to the corresponding letters in the suffix greek alphabet.

18 L<asciiToSuffixLatin|/asciiToSuffixLatin> - Translate ascii to the corresponding letters in the suffix latin alphabet.

19 L<asciiToVariableGreek|/asciiToVariableGreek> - Translate ascii to the corresponding letters in the suffix greek alphabet.

20 L<asciiToVariableLatin|/asciiToVariableLatin> - Translate ascii to the corresponding letters in the suffix latin alphabet.

21 L<assign|/assign> - Define a method for an assign operator.

22 L<bracket|/bracket> - Define a method for a bracket operator.

23 L<C|/C> - Parse some text and print the results.

24 L<checkSet|/checkSet> - Check that one of a set of items is on the top of the stack or complain if it is not.

25 L<checkStackHas|/checkStackHas> - Check that we have at least the specified number of elements on the stack.

26 L<ClassifyNewLines|/ClassifyNewLines> - Scan input string looking for opportunities to convert new lines into semi colons.

27 L<ClassifyWhiteSpace|/ClassifyWhiteSpace> - Classify white space per: "lib/Unisyn/whiteSpace/whiteSpaceClassification.

28 L<create|/create> - Create a new unisyn parse from a utf8 string.

29 L<dumpParseTree|/dumpParseTree> - Dump the parse tree.

30 L<dyad|/dyad> - Define a method for a dyadic operator.

31 L<error|/error> - Write an error message and stop.

32 L<executeOperator|/executeOperator> - Print the operator calling sequence.

33 L<getAlpha|/getAlpha> - Load the position of a lexical item in its alphabet from the current character.

34 L<getLexicalCode|/getLexicalCode> - Load the lexical code of the current character in memory into the specified register.

35 L<lexicalItemLength|/lexicalItemLength> - Put the length of a lexical item into variable B<size>.

36 L<lexicalNameFromLetter|/lexicalNameFromLetter> - Lexical name for a lexical item described by its letter.

37 L<lexicalNumberFromLetter|/lexicalNumberFromLetter> - Lexical number for a lexical item described by its letter.

38 L<lexToSub|/lexToSub> - Map a lexical item to a processing subroutine.

39 L<loadCurrentChar|/loadCurrentChar> - Load the details of the character currently being processed so that we have the index of the character in the upper half of the current character and the lexical type of the character in the lowest byte.

40 L<makeExecutionChain|/makeExecutionChain> - Traverse the parse tree in post order to create an execution chain.

41 L<MatchBrackets|/MatchBrackets> - Replace the low three bytes of a utf32 bracket character with 24 bits of offset to the matching opening or closing bracket.

42 L<new|/new> - Create a new term in the parse tree rooted on the stack.

43 L<parseExpression|/parseExpression> - Parse the string of classified lexical items addressed by register $start of length $length.

44 L<parseUtf8|/parseUtf8> - Parse a unisyn expression encoded as utf8 and return the parse tree.

45 L<prefix|/prefix> - Define a method for a prefix operator.

46 L<print|/print> - Print a parse tree.

47 L<printExecChain|/printExecChain> - Print the execute chain for a parse

48 L<printLexicalItem|/printLexicalItem> - Print the utf8 string corresponding to a lexical item at a variable offset.

49 L<printOperatorSequence|/printOperatorSequence> - Print the operator calling sequence.

50 L<pushElement|/pushElement> - Push the current element on to the stack.

51 L<pushEmpty|/pushEmpty> - Push the empty element on to the stack.

52 L<putLexicalCode|/putLexicalCode> - Put the specified lexical code into the current character in memory.

53 L<reduce|/reduce> - Convert the longest possible expression on top of the stack into a term  at the specified priority.

54 L<reduceMultiple|/reduceMultiple> - Reduce existing operators on the stack.

55 L<reload|/reload> - Reload the variables associated with a parse.

56 L<semiColon|/semiColon> - Define a method for the semicolon operator which comes in two forms: the explicit semi colon and a new line semicolon.

57 L<semiColonChar|/semiColonChar> - Translate ascii to the corresponding letters in the escaped ascii alphabet.

58 L<showAlphabet|/showAlphabet> - Show an alphabet.

59 L<suffix|/suffix> - Define a method for a suffix operator.

60 L<T|/T> - Parse some text and dump the results.

61 L<testSet|/testSet> - Test a set of items, setting the Zero Flag is one matches else clear the Zero flag.

62 L<traverseParseTree|/traverseParseTree> - Traverse the terms in parse tree in post order and call the operator subroutine associated with each term.

63 L<variable|/variable> - Define a method for a variable.

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
   {plan tests => 22;
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

sub T($$%)                                                                      #P Parse some text and dump the results.
 {my ($key, $expected, %options) = @_;                                          # Key of text to be parsed, expected result, options
  my $source  = $$Lex{sampleText}{$key};                                        # String to be parsed in utf8
  defined $source or confess "No such source";
  my $address = Rutf8 $source;
  my $size    = StringLength V(string, $address);

  my $p = create V(address, $address), %options;                                # Parse

  $p->dumpParseTree;                                                            # Dump the parse tree

  Assemble(debug => 0, eq => $expected);
 }

sub C($$%)                                                                      #P Parse some text and print the results.
 {my ($key, $expected, %options) = @_;                                          # Key of text to be parsed, expected result, options
  create (K(address, Rutf8 $Lex->{sampleText}{$key}), %options)->print;

  Assemble(debug => 0, eq => $expected);
 }

#latest:
ok T(q(v), <<END) if 1;
Tree at:  0000 0000 0000 00D8  length: 0000 0000 0000 0006
  Keys: 0000 0118 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
  Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0000 0000 0006   0000 0001 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
end
END

#latest:
ok T(q(brackets), <<END, debug => 0) if 1;
Tree at:  0000 0000 0000 0AD8  length: 0000 0000 0000 000A
  Keys: 0000 0B18 0280 000A   0000 0000 0000 0000   0000 0000 0000 0000   0000 000D 0000 000C   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
  Data: 0000 0000 0000 0014   0000 0000 0000 0000   0000 0000 0000 0000   0000 0A18 0000 0009   0000 00D8 0000 0009   0000 0008 0000 0006   0000 0001 0000 0005   0000 0003 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0005
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0006
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0008
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 00D8 subTree
    index: 0000 0000 0000 0008   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0009   key: 0000 0000 0000 000D   data: 0000 0000 0000 0A18 subTree
  Tree at:  0000 0000 0000 00D8  length: 0000 0000 0000 0006
    Keys: 0000 0118 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
    Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0000 0000 0006   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
  end
  Tree at:  0000 0000 0000 0A18  length: 0000 0000 0000 0008
    Keys: 0000 0A58 0080 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
    Data: 0000 0000 0000 0010   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0998 0000 0009   0000 0007 0000 0001   0000 0007 0000 0012   0000 0002 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0012
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0007
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0007
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 0998 subTree
    Tree at:  0000 0000 0000 0998  length: 0000 0000 0000 0004
      Keys: 0000 09D8 0008 0004   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0005 0000 0004   0000 0001 0000 0000
      Data: 0000 0000 0000 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 07D8 0000 0009   0000 0001 0000 0009
      Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
        index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
        index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
        index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0009
        index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 07D8 subTree
      Tree at:  0000 0000 0000 07D8  length: 0000 0000 0000 000A
        Keys: 0000 0818 0280 000A   0000 0000 0000 0000   0000 0000 0000 0000   0000 000D 0000 000C   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
        Data: 0000 0000 0000 0014   0000 0000 0000 0000   0000 0000 0000 0000   0000 0718 0000 0009   0000 0518 0000 0009   0000 0006 0000 0004   0000 000E 0000 0003   0000 0003 0000 0009
        Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
          index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
          index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
          index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0003
          index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 000E
          index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0004
          index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0006
          index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
          index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 0518 subTree
          index: 0000 0000 0000 0008   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
          index: 0000 0000 0000 0009   key: 0000 0000 0000 000D   data: 0000 0000 0000 0718 subTree
        Tree at:  0000 0000 0000 0518  length: 0000 0000 0000 0008
          Keys: 0000 0558 0080 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
          Data: 0000 0000 0000 0010   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0498 0000 0009   0000 0003 0000 0001   0000 0008 0000 0014   0000 0002 0000 0009
          Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
            index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
            index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0002
            index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0014
            index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0008
            index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
            index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0003
            index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
            index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 0498 subTree
          Tree at:  0000 0000 0000 0498  length: 0000 0000 0000 0004
            Keys: 0000 04D8 0008 0004   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0005 0000 0004   0000 0001 0000 0000
            Data: 0000 0000 0000 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 03D8 0000 0009   0000 0001 0000 0009
            Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
              index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
              index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
              index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0009
              index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 03D8 subTree
            Tree at:  0000 0000 0000 03D8  length: 0000 0000 0000 0008
              Keys: 0000 0418 0080 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
              Data: 0000 0000 0000 0010   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0358 0000 0009   0000 0002 0000 0001   0000 0009 0000 0016   0000 0002 0000 0009
              Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
                index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
                index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0002
                index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0016
                index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0009
                index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
                index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
                index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
                index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 0358 subTree
              Tree at:  0000 0000 0000 0358  length: 0000 0000 0000 0004
                Keys: 0000 0398 0008 0004   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0005 0000 0004   0000 0001 0000 0000
                Data: 0000 0000 0000 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0218 0000 0009   0000 0001 0000 0009
                Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
                  index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
                  index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
                  index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0009
                  index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0218 subTree
                Tree at:  0000 0000 0000 0218  length: 0000 0000 0000 0006
                  Keys: 0000 0258 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
                  Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0001 0000 0002   0000 000A 0000 0006   0000 0001 0000 0009
                  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
                    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
                    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
                    index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
                    index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 000A
                    index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0002
                    index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
                end
              end
            end
          end
        end
        Tree at:  0000 0000 0000 0718  length: 0000 0000 0000 0008
          Keys: 0000 0758 0080 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
          Data: 0000 0000 0000 0010   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0698 0000 0009   0000 0005 0000 0001   0000 0012 0000 0018   0000 0002 0000 0009
          Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
            index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
            index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0002
            index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0018
            index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0012
            index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
            index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0005
            index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
            index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 0698 subTree
          Tree at:  0000 0000 0000 0698  length: 0000 0000 0000 0004
            Keys: 0000 06D8 0008 0004   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0005 0000 0004   0000 0001 0000 0000
            Data: 0000 0000 0000 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 05D8 0000 0009   0000 0001 0000 0009
            Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
              index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
              index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
              index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0009
              index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 05D8 subTree
            Tree at:  0000 0000 0000 05D8  length: 0000 0000 0000 0006
              Keys: 0000 0618 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
              Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0004 0000 0002   0000 0013 0000 0006   0000 0001 0000 0009
              Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
                index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
                index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
                index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
                index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0013
                index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0002
                index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0004
            end
          end
        end
      end
    end
  end
end
END

#latest:
ok T(q(vav), <<END) if 1;
Tree at:  0000 0000 0000 02D8  length: 0000 0000 0000 000A
  Keys: 0000 0318 0280 000A   0000 0000 0000 0000   0000 0000 0000 0000   0000 000D 0000 000C   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
  Data: 0000 0000 0000 0014   0000 0000 0000 0000   0000 0000 0000 0000   0000 0218 0000 0009   0000 00D8 0000 0009   0000 0002 0000 0001   0000 0001 0000 0005   0000 0003 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0005
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 00D8 subTree
    index: 0000 0000 0000 0008   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0009   key: 0000 0000 0000 000D   data: 0000 0000 0000 0218 subTree
  Tree at:  0000 0000 0000 00D8  length: 0000 0000 0000 0006
    Keys: 0000 0118 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
    Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0000 0000 0006   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
  end
  Tree at:  0000 0000 0000 0218  length: 0000 0000 0000 0006
    Keys: 0000 0258 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
    Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0001 0000 0001   0000 0002 0000 0006   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
  end
end
END

#latest:
if (1) {                                                                        #Tcreate #Tprint
  create (K(address, Rutf8 $Lex->{sampleText}{vav}))->print;                    # Create parse tree from source terminated with zero

  ok Assemble(debug => 0, eq => <<END);
Assign: 𝑎
  Term
    Variable: 𝗮
  Term
    Variable: 𝗯
END
 }

#latest:
ok C(q(vavav), <<END);
Assign: 𝑎
  Term
    Variable: 𝗮
  Term
    Assign: 𝑎
      Term
        Variable: 𝗯
      Term
        Variable: 𝗰
END

#latest:
ok T(q(bvB), <<END) if 1;
Tree at:  0000 0000 0000 0298  length: 0000 0000 0000 0008
  Keys: 0000 02D8 0080 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
  Data: 0000 0000 0000 0010   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0218 0000 0009   0000 0001 0000 0001   0000 0000 0000 0014   0000 0002 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0014
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 0218 subTree
  Tree at:  0000 0000 0000 0218  length: 0000 0000 0000 0004
    Keys: 0000 0258 0008 0004   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0005 0000 0004   0000 0001 0000 0000
    Data: 0000 0000 0000 0008   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 00D8 0000 0009   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 00D8 subTree
    Tree at:  0000 0000 0000 00D8  length: 0000 0000 0000 0006
      Keys: 0000 0118 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
      Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0003   0000 0001 0000 0006   0000 0001 0000 0009
      Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
        index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
        index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
        index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
        index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0001
        index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0003
        index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
    end
  end
end
END

#latest:
ok C(q(bvB), <<END);
Brackets: ❨❩
  Term
    Term
      Variable: 𝗮𝗯𝗰
END

#latest:
ok C(q(brackets), <<END);
Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
  Term
    Variable: 𝗮
  Term
    Brackets: ⌊⌋
      Term
        Term
          Dyad: 𝐩𝐥𝐮𝐬
            Term
              Brackets: ❨❩
                Term
                  Term
                    Brackets: ❬❭
                      Term
                        Term
                          Variable: 𝗯𝗽
            Term
              Brackets: ❰❱
                Term
                  Term
                    Variable: 𝘀𝗰
END

#latest:
ok C(q(ws), <<END);
Semicolon
  Term
    Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
      Term
        Variable: 𝗮
      Term
        Brackets: ⌊⌋
          Term
            Term
              Dyad: 𝐩𝐥𝐮𝐬
                Term
                  Brackets: ❨❩
                    Term
                      Term
                        Brackets: ❬❭
                          Term
                            Term
                              Variable: 𝗯𝗽
                Term
                  Brackets: ❰❱
                    Term
                      Term
                        Variable: 𝘀𝗰
  Term
    Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
      Term
        Variable: 𝗮𝗮
      Term
        Brackets: ❴❵
          Term
            Term
              Dyad: 𝐩𝐥𝐮𝐬
                Term
                  Variable: 𝗯𝗯
                Term
                  Variable: 𝗰𝗰
END

#latest:
ok T(q(s), <<END) if 1;
Tree at:  0000 0000 0000 02D8  length: 0000 0000 0000 000A
  Keys: 0000 0318 0280 000A   0000 0000 0000 0000   0000 0000 0000 0000   0000 000D 0000 000C   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
  Data: 0000 0000 0000 0014   0000 0000 0000 0000   0000 0000 0000 0000   0000 0218 0000 0009   0000 00D8 0000 0009   0000 0002 0000 0001   0000 0001 0000 0008   0000 0003 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0008
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 00D8 subTree
    index: 0000 0000 0000 0008   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0009   key: 0000 0000 0000 000D   data: 0000 0000 0000 0218 subTree
  Tree at:  0000 0000 0000 00D8  length: 0000 0000 0000 0006
    Keys: 0000 0118 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
    Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0000 0000 0006   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
  end
  Tree at:  0000 0000 0000 0218  length: 0000 0000 0000 0006
    Keys: 0000 0258 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
    Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0001 0000 0001   0000 0002 0000 0006   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
  end
end
END

#latest:
ok C(q(s), <<END);
Semicolon
  Term
    Variable: 𝗮
  Term
    Variable: 𝗯
END

#latest:
ok T(q(A), <<END) if 0; # Ascii is a problem
Tree at:  0000 0000 0000 03D8  length: 0000 0000 0000 000A
  Keys: 0000 0418 0280 000A   0000 0000 0000 0000   0000 0000 0000 0000   0000 000D 0000 000C   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
  Data: 0000 0000 0000 0014   0000 0000 0000 0000   0000 0000 0000 0000   0000 0218 0000 0009   0000 00D8 0000 0009   0000 0002 0000 0006   0000 0002 0000 0005   0000 0003 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0005
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0006
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0009   data: 0000 0000 0000 00D8 subTree
    index: 0000 0000 0000 0008   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0009   key: 0000 0000 0000 000D   data: 0000 0000 0000 0218 subTree
  Tree at:  0000 0000 0000 00D8  length: 0000 0000 0000 0006
    Keys: 0000 0118 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
    Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0002   0000 0000 0000 0006   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
  end
  Tree at:  0000 0000 0000 0218  length: 0000 0000 0000 0006
    Keys: 0000 0258 0000 0006   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0006   0000 0005 0000 0004   0000 0001 0000 0000
    Data: 0000 0000 0000 000C   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0001 0000 0007   0000 0008 0000 0002   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0004   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0005   data: 0000 0000 0000 0008
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0006   data: 0000 0000 0000 0007
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
  end
end
END

#latest:
ok C(q(A), <<END) if 0; # Ascii is a problem
Assign: 𝑒𝑞𝑢𝑎𝑙𝑠
  Term
    Variable: 𝗮𝗮
  Term
    Ascii: abc 123
END

=pod
# q(𝚨𝚩𝚾𝚫𝚬𝚽𝚪𝚯𝚰J𝚱𝚲𝚳𝚮𝚶𝚷𝚹𝚸𝚺𝚻𝚼𝚴𝛀𝚵𝚿𝚭𝛂𝛃𝛘𝛅𝛆𝛗𝛄𝛉𝛊j𝛋𝛌𝛍𝛈𝛐𝛑𝛓𝛒𝛔𝛕𝛖𝛎𝛚𝛏𝛙𝛇)
# q(𝜜𝜝𝜲𝜟𝜠𝜱𝜞𝜣𝜤J𝜥𝜦𝜧𝜢𝜪𝜫𝜭𝜬𝜮𝜯𝜰𝜨𝜴𝜩𝜳𝜡𝜶𝜷𝝌𝜹𝜺𝝋𝜸𝜽𝜾j𝜿𝝀𝝁𝜼𝝄𝝅𝝇𝝆𝝈𝝉𝝊𝝂𝝎𝝃𝝍𝜻)
# q(𝞐𝞑𝞦𝞓𝞔𝞥𝞒𝞗𝞘J𝞙𝞚𝞛𝞖𝞞𝞟𝞡𝞠𝞢𝞣𝞤𝞜𝞨𝞝𝞧𝞕𝞪𝞫𝟀𝞭𝞮𝞿𝞬𝞱𝞲j𝞳𝞴𝞵𝞰𝞸𝞹𝞻𝞺𝞼𝞽𝞾𝞶𝟂𝞷𝟁𝞯)
# q(𝝖𝝗𝝬𝝙𝝚𝝫𝝘𝝝𝝞J𝝟𝝠𝝡𝝜𝝤𝝥𝝧𝝦𝝨𝝩𝝪𝝢𝝮𝝣𝝭𝝛𝝰𝝱𝞆𝝳𝝴𝞅𝝲𝝷𝝸j𝝹𝝺𝝻𝝶𝝾𝝿𝞁𝞀𝞂𝞃𝞄𝝼𝞈𝝽𝞇𝝵)
=cut
#latest:
is_deeply asciiToDyadLatin    ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"), q(𝐀𝐁𝐂𝐃𝐄𝐅𝐆𝐇𝐈𝐉𝐊𝐋𝐌𝐍𝐎𝐏𝐐𝐑𝐒𝐓𝐔𝐕𝐖𝐗𝐘𝐙𝐚𝐛𝐜𝐝𝐞𝐟𝐠𝐡𝐢𝐣𝐤𝐥𝐦𝐧𝐨𝐩𝐪𝐫𝐬𝐭𝐮𝐯𝐰𝐱𝐲𝐳);
is_deeply asciiToDyadGreek    ("ABGDEZNHIKLMVXOPRQSTUFCYWabgdeznhiklmvxoprqstufcyw"),   q(𝚨𝚩𝚪𝚫𝚬𝚭𝚮𝚯𝚰𝚱𝚲𝚳𝚴𝚵𝚶𝚷𝚸𝚹𝚺𝚻𝚼𝚽𝚾𝚿𝛀𝛂𝛃𝛄𝛅𝛆𝛇𝛈𝛉𝛊𝛋𝛌𝛍𝛎𝛏𝛐𝛑𝛒𝛓𝛔𝛕𝛖𝛗𝛘𝛙𝛚);
is_deeply asciiToPrefixLatin  ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"), q(𝑨𝑩𝑪𝑫𝑬𝑭𝑮𝑯𝑰𝑱𝑲𝑳𝑴𝑵𝑶𝑷𝑸𝑹𝑺𝑻𝑼𝑽𝑾𝑿𝒀𝒁𝒂𝒃𝒄𝒅𝒆𝒇𝒈𝒉𝒊𝒋𝒌𝒍𝒎𝒏𝒐𝒑𝒒𝒓𝒔𝒕𝒖𝒗𝒘𝒙𝒚𝒛);
is_deeply asciiToPrefixGreek  ("ABGDEZNHIKLMVXOPRQSTUFCYWabgdeznhiklmvxoprqstufcyw"),   q(𝜜𝜝𝜞𝜟𝜠𝜡𝜢𝜣𝜤𝜥𝜦𝜧𝜨𝜩𝜪𝜫𝜬𝜭𝜮𝜯𝜰𝜱𝜲𝜳𝜴𝜶𝜷𝜸𝜹𝜺𝜻𝜼𝜽𝜾𝜿𝝀𝝁𝝂𝝃𝝄𝝅𝝆𝝇𝝈𝝉𝝊𝝋𝝌𝝍𝝎);
is_deeply asciiToSuffixLatin  ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"), q(𝘼𝘽𝘾𝘿𝙀𝙁𝙂𝙃𝙄𝙅𝙆𝙇𝙈𝙉𝙊𝙋𝙌𝙍𝙎𝙏𝙐𝙑𝙒𝙓𝙔𝙕𝙖𝙗𝙘𝙙𝙚𝙛𝙜𝙝𝙞𝙟𝙠𝙡𝙢𝙣𝙤𝙥𝙦𝙧𝙨𝙩𝙪𝙫𝙬𝙭𝙮𝙯);
is_deeply asciiToSuffixGreek  ("ABGDEZNHIKLMVXOPRQSTUFCYWabgdeznhiklmvxoprqstufcyw"),   q(𝞐𝞑𝞒𝞓𝞔𝞕𝞖𝞗𝞘𝞙𝞚𝞛𝞜𝞝𝞞𝞟𝞠𝞡𝞢𝞣𝞤𝞥𝞦𝞧𝞨𝞪𝞫𝞬𝞭𝞮𝞯𝞰𝞱𝞲𝞳𝞴𝞵𝞶𝞷𝞸𝞹𝞺𝞻𝞼𝞽𝞾𝞿𝟀𝟁𝟂);
is_deeply asciiToVariableLatin("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"), q(𝗔𝗕𝗖𝗗𝗘𝗙𝗚𝗛𝗜𝗝𝗞𝗟𝗠𝗡𝗢𝗣𝗤𝗥𝗦𝗧𝗨𝗩𝗪𝗫𝗬𝗭𝗮𝗯𝗰𝗱𝗲𝗳𝗴𝗵𝗶𝗷𝗸𝗹𝗺𝗻𝗼𝗽𝗾𝗿𝘀𝘁𝘂𝘃𝘄𝘅𝘆𝘇);
is_deeply asciiToVariableGreek("ABGDEZNHIKLMVXOPRQSTUFCYWabgdeznhiklmvxoprqstufcyw"),   q(𝝖𝝗𝝘𝝙𝝚𝝛𝝜𝝝𝝞𝝟𝝠𝝡𝝢𝝣𝝤𝝥𝝦𝝧𝝨𝝩𝝪𝝫𝝬𝝭𝝮𝝰𝝱𝝲𝝳𝝴𝝵𝝶𝝷𝝸𝝹𝝺𝝻𝝼𝝽𝝾𝝿𝞀𝞁𝞂𝞃𝞄𝞅𝞆𝞇𝞈);
is_deeply asciiToEscaped      ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"), q(ABCDEFGHIJKLMNOPQRSTUVWXYZ🅐🅑🅒🅓🅔🅕🅖🅗🅘🅙🅚🅛🅜🅝🅞🅟🅠🅡🅢🅣🅤🅥🅦🅧🅨🅩);
is_deeply semiColonChar, q(⟢);

sub printOperatorSequence($)                                                    # Print the operator calling sequence.
 {my ($parse) = @_;                                                             # Parse

  if (1)                                                                        # Prefix and suffix operators
   {my $s = 'abcd';
    for my $i(1..length($s))
     {my $c = substr($s, $i-1, 1);
      my $p = Subroutine
       {PrintOutStringNL "prefix_$c";
       } [], name=>"UnisynParse::prefix_$c";
      my $q = Subroutine
       {PrintOutStringNL "suffix_$c";
       } [], name=>"UnisynParse::suffix_$c";
      $parse->prefix(asciiToPrefixLatin($c), $p);
      $parse->suffix(asciiToSuffixLatin($c), $q);
     }
   }

  if (1)                                                                        # Brackets
   {my $s = "⦇⦋⦏";
    for my $i(1..length($s))
     {my $b = Subroutine
       {PrintOutStringNL "brackets_$i";
       } [], name=>"UnisynParse::brackets_$i";
      $parse->bracket(substr($s, $i-1, 1), $b);
     }
   }

  if (1)                                                                        # Variable
   {my $v = Subroutine
     {PrintOutStringNL "variable";
     } [], name=>"UnisynParse::variable";
    $parse->variable($v);
   }

  my $assign = Subroutine
   {PrintOutStringNL "assign";
   } [], name=>"UnisynParse::assign";
  $parse->assign(asciiToAssignLatin("assign"), $assign);

  my $equals = Subroutine
   {PrintOutStringNL "equals";
   } [], name=>"UnisynParse::equals";
  $parse->assign(asciiToAssignLatin("equals"), $equals);

  my $plus   = Subroutine
   {PrintOutStringNL "plus";
   } [], name=>"UnisynParse::plus";
  $parse->dyad(asciiToDyadLatin("plus"), $plus);

  my $sub    = Subroutine
   {PrintOutStringNL "sub";
   } [], name=>"UnisynParse::sub";
  $parse->dyad(asciiToDyadLatin("sub"), $sub);

  my $times  = Subroutine
   {PrintOutStringNL "times";
   } [], name=>"UnisynParse::times";
  $parse->dyad(asciiToDyadLatin("times"), $times);

  my $semiColon = Subroutine
   {PrintOutStringNL "semiColon";
#   PrintErrRegisterInHex xmm0;
   } [], name=>"UnisynParse::semiColon";
  $parse->semiColon($semiColon);

  my $ascii = Subroutine
   {PrintOutStringNL "ascii";
   } [], name=>"UnisynParse::ascii";
  $parse->ascii($ascii);

# $o->dumpSubs;
# $o->subQuarks->stringsToNumbers->dump;
# $ascii->V->d;
 }

#latest:
if (1) {                                                                        # Semicolon
  my $s = Rutf8 $Lex->{sampleText}{s};
  my $p = create K(address, $s), operators => \&printOperatorSequence;

  K(address, $s)->printOutZeroString;
  $p->print;
  $p->dumpParseTree ;
  $p->traverseParseTree;

  Assemble(debug => 0, eq => <<END)
𝗮⟢𝗯
Semicolon
  Term
    Variable: 𝗮
  Term
    Variable: 𝗯
Tree at:  0000 0000 0000 0E18  length: 0000 0000 0000 000B
  Keys: 0000 0E58 0500 000B   0000 0000 0000 0000   0000 0000 0000 000D   0000 000C 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
  Data: 0000 0000 0000 0016   0000 0000 0000 0000   0000 0000 0000 0D58   0000 0009 0000 0C18   0000 0009 0000 0002   0000 0001 0000 0001   0000 0008 0041 4514   0000 0003 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 4514
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0008
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0008   key: 0000 0000 0000 0009   data: 0000 0000 0000 0C18 subTree
    index: 0000 0000 0000 0009   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
    index: 0000 0000 0000 000A   key: 0000 0000 0000 000D   data: 0000 0000 0000 0D58 subTree
  Tree at:  0000 0000 0000 0C18  length: 0000 0000 0000 0007
    Keys: 0000 0C58 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0001 0000 0000   0000 0006 0041 176C   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 176C
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
  end
  Tree at:  0000 0000 0000 0D58  length: 0000 0000 0000 0007
    Keys: 0000 0D98 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0001 0000 0002   0000 0006 0041 176C   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 176C
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
  end
end
variable
variable
semiColon
END
 }

#latest:
if (0) {    ## Ascii                                                                    #TtraverseParseTree
  my $s = Rutf8 $Lex->{sampleText}{Adv};                                        # Ascii
  my $p = create K(address, $s), operators => \&printOperatorSequence;

  K(address, $s)->printOutZeroString;
  $p->dumpParseTree;
  $p->print;
  $p->traverseParseTree;

  Assemble(debug => 0, eq => <<END)
𝗮𝗮𝑒𝑞𝑢𝑎𝑙𝑠abc 123    𝐩𝐥𝐮𝐬𝘃𝗮𝗿
Tree at:  0000 0000 0000 10D8  length: 0000 0000 0000 000B
  Keys: 0000 1118 0500 000B   0000 0000 0000 0000   0000 0000 0000 000D   0000 000C 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
  Data: 0000 0000 0000 0016   0000 0000 0000 0000   0000 0000 0000 0F18   0000 0009 0000 0AD8   0000 0009 0000 0004   0000 0006 0000 0002   0000 0005 0041 26A4   0000 0003 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 26A4
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0005
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0006
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0004
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0008   key: 0000 0000 0000 0009   data: 0000 0000 0000 0AD8 subTree
    index: 0000 0000 0000 0009   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
    index: 0000 0000 0000 000A   key: 0000 0000 0000 000D   data: 0000 0000 0000 0F18 subTree
  Tree at:  0000 0000 0000 0AD8  length: 0000 0000 0000 0007
    Keys: 0000 0B18 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0002 0000 0000   0000 0006 0041 176C   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 176C
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
  end
  Tree at:  0000 0000 0000 0F18  length: 0000 0000 0000 000B
    Keys: 0000 0F58 0500 000B   0000 0000 0000 0000   0000 0000 0000 000D   0000 000C 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 0016   0000 0000 0000 0000   0000 0000 0000 0DD8   0000 0009 0000 0C18   0000 0009 0000 0003   0000 0004 0000 0013   0000 0003 0041 2E40   0000 0003 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 2E40
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0003
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0013
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0004
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0003
      index: 0000 0000 0000 0007   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0008   key: 0000 0000 0000 0009   data: 0000 0000 0000 0C18 subTree
      index: 0000 0000 0000 0009   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
      index: 0000 0000 0000 000A   key: 0000 0000 0000 000D   data: 0000 0000 0000 0DD8 subTree
    Tree at:  0000 0000 0000 0C18  length: 0000 0000 0000 0007
      Keys: 0000 0C58 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
      Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0007 0000 0008   0000 0002 0041 53FE   0000 0001 0000 0009
      Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
        index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
        index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
        index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 53FE
        index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0002
        index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0008
        index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0007
        index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
    end
    Tree at:  0000 0000 0000 0DD8  length: 0000 0000 0000 0007
      Keys: 0000 0E18 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
      Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0002   0000 0003 0000 0017   0000 0006 0041 176C   0000 0001 0000 0009
      Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
        index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
        index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
        index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0041 176C
        index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
        index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0017
        index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0003
        index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
    end
  end
end
Assign: 𝑒𝑞𝑢𝑎𝑙𝑠
  Term
    Variable: 𝗮𝗮
  Term
    Dyad: 𝐩𝐥𝐮𝐬
      Term
        Ascii: abc 123
      Term
        Variable: 𝘃𝗮𝗿
variable
ascii
variable
plus
equals
END
 }

#latest:
if (1) {                                                                        #TtraverseParseTree
  my $s = Rutf8 $Lex->{sampleText}{ws};
  my $p = create (K(address, $s), operators => \&printOperatorSequence);

  K(address, $s)->printOutZeroString;                                           # Print input string
  $p->print;                                                                    # Print parse
  $p->traverseParseTree;                                                        # Traverse tree printing terms

  Assemble(debug => 0, eq => <<END)
𝗮𝑎𝑠𝑠𝑖𝑔𝑛⌊〈❨𝗯𝗽❩〉𝐩𝐥𝐮𝐬❪𝘀𝗰❫⌋⟢𝗮𝗮𝑎𝑠𝑠𝑖𝑔𝑛❬𝗯𝗯𝐩𝐥𝐮𝐬𝗰𝗰❭⟢
Semicolon
  Term
    Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
      Term
        Variable: 𝗮
      Term
        Brackets: ⌊⌋
          Term
            Term
              Dyad: 𝐩𝐥𝐮𝐬
                Term
                  Brackets: ❨❩
                    Term
                      Term
                        Brackets: ❬❭
                          Term
                            Term
                              Variable: 𝗯𝗽
                Term
                  Brackets: ❰❱
                    Term
                      Term
                        Variable: 𝘀𝗰
  Term
    Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
      Term
        Variable: 𝗮𝗮
      Term
        Brackets: ❴❵
          Term
            Term
              Dyad: 𝐩𝐥𝐮𝐬
                Term
                  Variable: 𝗯𝗯
                Term
                  Variable: 𝗰𝗰
variable
variable
variable
plus
assign
variable
variable
variable
plus
assign
semiColon
END
 }

#latest:
if (1) {
  my $s = Rutf8 $Lex->{sampleText}{ppppvdvdvqqqq};
  my $p = create (K(address, $s), operators => \&printOperatorSequence);

# $p->dumpParseTree;
  K(address, $s)->printOutZeroString;                                           # Print input string
  $p->print;                                                                    # Print parse
  $p->traverseParseTree;                                                        # Traverse tree printing terms

  ok Assemble(debug => 0, eq => <<END)
𝒂❴𝒃⟦𝒄⟨𝗮𝑒𝑞𝑢𝑎𝑙𝑠𝒅𝗯𝙙𝐭𝐢𝐦𝐞𝐬⟪𝗰𝐩𝐥𝐮𝐬𝗱⟫⟢𝗲𝑎𝑠𝑠𝑖𝑔𝑛𝗳𝐬𝐮𝐛𝗴𝙝⟩𝙘⟧𝙗❵𝙖
Suffix: 𝙖
  Term
    Prefix: 𝒂
      Term
        Brackets: ⦇⦈
          Term
            Term
              Suffix: 𝙗
                Term
                  Prefix: 𝒃
                    Term
                      Brackets: ⦋⦌
                        Term
                          Term
                            Suffix: 𝙘
                              Term
                                Prefix: 𝒄
                                  Term
                                    Brackets: ⦏⦐
                                      Term
                                        Term
                                          Semicolon
                                            Term
                                              Assign: 𝑒𝑞𝑢𝑎𝑙𝑠
                                                Term
                                                  Variable: 𝗮
                                                Term
                                                  Dyad: 𝐭𝐢𝐦𝐞𝐬
                                                    Term
                                                      Suffix: 𝙙
                                                        Term
                                                          Prefix: 𝒅
                                                            Term
                                                              Variable: 𝗯
                                                    Term
                                                      Brackets: ⦓⦔
                                                        Term
                                                          Term
                                                            Dyad: 𝐩𝐥𝐮𝐬
                                                              Term
                                                                Variable: 𝗰
                                                              Term
                                                                Variable: 𝗱
                                            Term
                                              Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
                                                Term
                                                  Variable: 𝗲
                                                Term
                                                  Dyad: 𝐬𝐮𝐛
                                                    Term
                                                      Variable: 𝗳
                                                    Term
                                                      Suffix: 𝙝
                                                        Term
                                                          Variable: 𝗴
variable
variable
prefix_d
suffix_d
variable
variable
plus
times
equals
variable
variable
variable
sub
assign
semiColon
brackets_3
prefix_c
suffix_c
brackets_2
prefix_b
suffix_b
brackets_1
prefix_a
suffix_a
END
 }

sub executeOperator($)                                                          # Print the operator calling sequence.
 {my ($parse) = @_;                                                             # Parse

# my $o = $parse->operators;

  my $semiColon = Subroutine
   {PrintOutStringNL "semiColon";
   } [], name=>"UnisynParse::semiColon";

  $parse->semiColon($semiColon);
 }

#latest:
if (1) {                                                                        # Semicolon
  my $s = Rutf8 $Lex->{sampleText}{s};
  my $p = create K(address, $s), operators => \&executeOperator;

  K(address, $s)->printOutZeroString;
  $p->print;
  $p->traverseParseTree;
  $p->makeExecutionChain;
  $p->printExecChain;
  $p->dumpParseTree ;

  Assemble(debug => 0, eq => <<END)
𝗮⟢𝗯
Semicolon
  Term
    Variable: 𝗮
  Term
    Variable: 𝗯
semiColon
offset: 0000 0000 0000 05D8 :   zmm0: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 03D8 0000 0598
offset: 0000 0000 0000 0598 :   zmm0: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0298 0000 0558
offset: 0000 0000 0000 0558 :   zmm0: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0040 8578   0000 0498 0000 0000
Tree at:  0000 0000 0000 0498  length: 0000 0000 0000 000C
  Keys: 0000 04D8 0A00 000C   0000 0000 0000 0000   0000 000D 0000 000C   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
  Data: 0000 0000 0000 0018   0000 0000 0000 0000   0000 03D8 0000 0009   0000 0298 0000 0009   0000 0002 0000 0001   0000 0001 0000 0008   0000 05D8 0040 8578   0000 0003 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0040 8578
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0003   data: 0000 0000 0000 05D8
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0004   data: 0000 0000 0000 0008
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0005   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0008   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0009   key: 0000 0000 0000 0009   data: 0000 0000 0000 0298 subTree
    index: 0000 0000 0000 000A   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
    index: 0000 0000 0000 000B   key: 0000 0000 0000 000D   data: 0000 0000 0000 03D8 subTree
  Tree at:  0000 0000 0000 0298  length: 0000 0000 0000 0007
    Keys: 0000 02D8 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0001 0000 0000   0000 0006 0000 0000   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
  end
  Tree at:  0000 0000 0000 03D8  length: 0000 0000 0000 0007
    Keys: 0000 0418 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0001 0000 0002   0000 0006 0000 0000   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
  end
end
END
 }

sub executeChain($)                                                             # Print the execute chain calling sequence.
 {my ($parse) = @_;                                                             # Parse

  my $semiColon = Subroutine
   {PrintOutStringNL "semiColon";
   } [], name=>"UnisynParse::semiColon";

  my $variable = Subroutine
   {PrintOutStringNL "variable";
   } [], name=>"UnisynParse::variable";

  my $assign = Subroutine
   {PrintOutStringNL "assign";
   } [], name=>"UnisynParse::assign";

  my $dyad = Subroutine
   {PrintOutStringNL "dyad";
   } [], name=>"UnisynParse::dyad";

  my $dyad2 = Subroutine
   {PrintOutStringNL "dyad2";
   } [], name=>"UnisynParse::dyad2";

  $parse->semiColon($semiColon);
  $parse->variable ($variable);
  $parse->assign   (asciiToAssignLatin("assign"), $assign);
  $parse->dyad     (asciiToDyadLatin  ("plus"),   $dyad);
  $parse->dyad     (asciiToDyadLatin  ("divide"), $dyad);
  $parse->dyad2    ("÷",                          $dyad2);
 }

#latest:
if (1) {                                                                        # Semicolon
  my $s = Rutf8 $Lex->{sampleText}{s};
  my $p = create K(address, $s), operators => \&executeChain;

  K(address, $s)->printOutZeroString;
  $p->print;
  $p->dumpParseTree ;
  $p->makeExecutionChain;
  $p->execExecChain;

  Assemble(debug => 0, eq => <<END)
𝗮⟢𝗯
Semicolon
  Term
    Variable: 𝗮
  Term
    Variable: 𝗯
Tree at:  0000 0000 0000 08D8  length: 0000 0000 0000 000B
  Keys: 0000 0918 0500 000B   0000 0000 0000 0000   0000 0000 0000 000D   0000 000C 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
  Data: 0000 0000 0000 0016   0000 0000 0000 0000   0000 0000 0000 0818   0000 0009 0000 06D8   0000 0009 0000 0002   0000 0001 0000 0001   0000 0008 0040 8578   0000 0003 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0040 8578
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0008
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0008   key: 0000 0000 0000 0009   data: 0000 0000 0000 06D8 subTree
    index: 0000 0000 0000 0009   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
    index: 0000 0000 0000 000A   key: 0000 0000 0000 000D   data: 0000 0000 0000 0818 subTree
  Tree at:  0000 0000 0000 06D8  length: 0000 0000 0000 0007
    Keys: 0000 0718 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0001 0000 0000   0000 0006 0040 85EC   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0040 85EC
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
  end
  Tree at:  0000 0000 0000 0818  length: 0000 0000 0000 0007
    Keys: 0000 0858 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0001 0000 0002   0000 0006 0040 85EC   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0040 85EC
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
  end
end
variable
variable
semiColon
END
 }

#latest:
if (1) {                                                                        # Dyad2
  my $s = Rutf8 $Lex->{sampleText}{e};
  my $p = create K(address, $s), operators => \&executeChain;

  K(address, $s)->printOutZeroString;
  $p->print;
  $p->dumpParseTree ;
  $p->makeExecutionChain;
  $p->execExecChain;

  Assemble(debug => 0, eq => <<END)                                             # ÷ 0xf7 ascii is character 0x3 in the dyad2 alphabet
𝗮÷𝗯
Dyad2: ÷
  Term
    Variable: 𝗮
  Term
    Variable: 𝗯
Tree at:  0000 0000 0000 08D8  length: 0000 0000 0000 000B
  Keys: 0000 0918 0500 000B   0000 0000 0000 0000   0000 0000 0000 000D   0000 000C 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
  Data: 0000 0000 0000 0016   0000 0000 0000 0000   0000 0000 0000 0818   0000 0009 0000 06D8   0000 0009 0000 0002   0000 0001 0000 0001   0000 000D 0040 86D6   0000 0003 0000 0009
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0003
    index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0040 86D6
    index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 000D
    index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
    index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0002
    index: 0000 0000 0000 0007   key: 0000 0000 0000 0008   data: 0000 0000 0000 0009
    index: 0000 0000 0000 0008   key: 0000 0000 0000 0009   data: 0000 0000 0000 06D8 subTree
    index: 0000 0000 0000 0009   key: 0000 0000 0000 000C   data: 0000 0000 0000 0009
    index: 0000 0000 0000 000A   key: 0000 0000 0000 000D   data: 0000 0000 0000 0818 subTree
  Tree at:  0000 0000 0000 06D8  length: 0000 0000 0000 0007
    Keys: 0000 0718 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0001 0000 0000   0000 0006 0040 85EC   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0040 85EC
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0000
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0000
  end
  Tree at:  0000 0000 0000 0818  length: 0000 0000 0000 0007
    Keys: 0000 0858 0000 0007   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0007   0000 0006 0000 0005   0000 0004 0000 0002   0000 0001 0000 0000
    Data: 0000 0000 0000 000E   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0001 0000 0002   0000 0006 0040 85EC   0000 0001 0000 0009
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0000 0000   data: 0000 0000 0000 0009
      index: 0000 0000 0000 0001   key: 0000 0000 0000 0001   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0002   key: 0000 0000 0000 0002   data: 0000 0000 0040 85EC
      index: 0000 0000 0000 0003   key: 0000 0000 0000 0004   data: 0000 0000 0000 0006
      index: 0000 0000 0000 0004   key: 0000 0000 0000 0005   data: 0000 0000 0000 0002
      index: 0000 0000 0000 0005   key: 0000 0000 0000 0006   data: 0000 0000 0000 0001
      index: 0000 0000 0000 0006   key: 0000 0000 0000 0007   data: 0000 0000 0000 0001
  end
end
variable
variable
dyad2
END
 }

#latest:
if (1) {                                                                        # Dyad dyad
  my $s = Rutf8 $Lex->{sampleText}{add};
  my $p = create K(address, $s), operators => \&executeChain;

  K(address, $s)->printOutZeroString;
  $p->print;
  $p->makeExecutionChain;
  $p->execExecChain;

  Assemble(debug => 0, eq => <<END)
𝗮𝑎𝑠𝑠𝑖𝑔𝑛𝗯𝐩𝐥𝐮𝐬𝗰𝐝𝐢𝐯𝐢𝐝𝐞𝗱
Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
  Term
    Variable: 𝗮
  Term
    Dyad: 𝐝𝐢𝐯𝐢𝐝𝐞
      Term
        Dyad: 𝐩𝐥𝐮𝐬
          Term
            Variable: 𝗯
          Term
            Variable: 𝗰
      Term
        Variable: 𝗱
variable
variable
variable
dyad
dyad
variable
assign
END
 }

#latest:
if (1) {                                                                        # Dyad dyad2
  my $s = Rutf8 $Lex->{sampleText}{ade};
  my $p = create K(address, $s), operators => \&executeChain;

  K(address, $s)->printOutZeroString;
  $p->print;
  $p->makeExecutionChain;
  $p->execExecChain;

  Assemble(debug => 0, eq => <<END)
𝗮𝑎𝑠𝑠𝑖𝑔𝑛𝗯𝐩𝐥𝐮𝐬𝗰÷𝗱
Assign: 𝑎𝑠𝑠𝑖𝑔𝑛
  Term
    Variable: 𝗮
  Term
    Dyad: 𝐩𝐥𝐮𝐬
      Term
        Variable: 𝗯
      Term
        Dyad2: ÷
          Term
            Variable: 𝗰
          Term
            Variable: 𝗱
variable
variable
dyad2
variable
dyad
variable
assign
END
 }

unlink $_ for qw(hash print2 sde-log.txt sde-ptr-check.out.txt z.txt);          # Remove incidental files

say STDERR sprintf("# Finished in %.2fs, bytes: %s, execs: %s ",  time - $startTime,
  map {numberWithCommas $_}
    $Nasm::X86::totalBytesAssembled, $Nasm::X86::instructionsExecuted);
