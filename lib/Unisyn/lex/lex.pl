#!/usr/bin/perl -I/home/phil/perl/cpan/DataTableText/lib/  -I/home/phil/perl/cpan/TreeTerm/lib/
#-------------------------------------------------------------------------------
# Assign unicode characters to lexical items in Earl Zero.
# Philip R Brenan at appaapps dot com, Appa Apps Ltd Inc., 2021
#-------------------------------------------------------------------------------
use warnings FATAL => qw(all);
use strict;
use Carp;
use Data::Dump qw(dump);
use Data::Table::Text qw(:all);
use Tree::Term;
use Test::More qw(no_plan);
use feature qw(say state current_sub);
use utf8;

my $home    = currentDirectory;                                                 # Home folder
my $parse   = q(/home/phil/perl/cpan/UnisynParse/lib/Unisyn/Parse.pm);          # Parse file
my $unicode = q(https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt); # Unicode specification
my $data    = fpe $home, qw(unicode txt);                                       # Local copy of unicode
my $lexicalsFile = fpe $home, qw(lex data);                                     # Dump of lexicals

makeDieConfess;
binModeAllUtf8;

# Unicode currently has less than 2**18 characters. The biggest block we have is mathematical operators which is < 2k = 2**13.

sub LexicalConstant($$$$$)                                                      # Lexical constants as opposed to derived values
 {my ($name, $number, $letter, $like, $comment) = @_;                           # Name of the lexical item, numeric code, character code, character code as used Tree::Term, a specialized instance of this Tree::Term which is never the less lexically identical to the Tree::Term
  genHash("Unisyn::Parse::Lexical::Constant",                                   # Description of a lexical item connecting the definition in Tree::Term with that inUnisyn
    name    => $name,                                                           #I Name of the lexical item
    number  => $number,                                                         #I Numeric code for lexical item
    letter  => $letter,                                                         #I Alphabetic name for lexical item
    like    => $like,                                                           #I Parsed like this element from Tree::Term
    comment => $comment,                                                        #I Comment describing lexical item
   );
 }

my %Usage;                                                                      # Maps unicode point to lexical item

my $Lexicals = genHash("Unisyn::Parse::Lexicals",                               # Lexical items in Unisyn
  OpenBracket       => LexicalConstant("OpenBracket",        0, 'b', 'b',       'The lowest bit of an open bracket code is zero'                               ),
  CloseBracket      => LexicalConstant("CloseBracket",       1, 'B', 'B',       'The lowest bit of a close bracket code is one '                               ),
  Ascii             => LexicalConstant("Ascii",              2, 'A', 'v',       'ASCII characters extended with circled characters to act as escape sequences.'),
  dyad              => LexicalConstant("dyad",               3, 'd', 'd',       'Infix operator with left to right binding at priority 3'                      ),
  prefix            => LexicalConstant("prefix",             4, 'p', 'p',       'Prefix operator - applies only to the following variable or bracketed term'   ),
  assign            => LexicalConstant("assign",             5, 'a', 'a',       'Assign infix operator with right to left binding at priority 2'               ),
  variable          => LexicalConstant("variable",           6, 'v', 'v',       'Variable names'                                                               ),
  suffix            => LexicalConstant("suffix",             7, 'q', 'q',       'Suffix operator - applies only to the preceding variable or bracketed term'   ),
  semiColon         => LexicalConstant("semiColon",          8, 's', 's',       'Infix operator with left to right binding at priority 1'                      ),
  term              => LexicalConstant("term",               9, 't', 't',       'Term in the parse tree'                                                       ),
  empty             => LexicalConstant("empty",             10, 'E', 'E',       'Empty term present between two adjacent semicolons'                           ),
  WhiteSpace        => LexicalConstant("WhiteSpace",        11, 'W', undef,     'White space that can be ignored during lexical analysis'                      ),
  NewLineSemiColon  => LexicalConstant("NewLineSemiColon",  12, 'N', undef,     'A new line character that is also acting as a semi colon'                     ),
  dyad2             => LexicalConstant("dyad2",             13, 'e', 'e',       'Infix operator with left to right binding at priority 4'                      ),
 );

my $TreeTermLexicals = Tree::Term::LexicalStructure->codes;

my $Tables = genHash("Unisyn::Parse::Lexical::Tables",                          # Tables used to parse lexical items
  alphabetChars    => undef,                                                    # Sorted arrays of characters for each lexical item by lexical item letter
  brackets         => undef,                                                    # Number of brackets
  bracketsBase     => 0x10,                                                     # Start numbering brackets from here
  bracketsHigh     => undef,                                                    # High zmm for closing brackets
  bracketsLow      => undef,                                                    # Low  zmm for opening brackets
  bracketsOpen     => undef,                                                    # Open brackets
  bracketsClose    => undef,                                                    # Close brackets
  lexicalHigh      => undef,                                                    # High zmm for lexical items
  lexicalLow       => undef,                                                    # Low  zmm for lexical items
  lexicals         => $Lexicals,                                                # The lexical items by lexical long name
  lexicalsByLetter => {map {$Lexicals->{$_}->letter => $Lexicals->{$_}}  keys %$Lexicals},   # The lexical items by lexical letter
  sampleLexicals   => undef,                                                    # Has of sample program as arrays of lexical items
  sampleText       => undef,                                                    # Sample programs in utf8
  treeTermLexicals => $TreeTermLexicals,                                        # Tree term lexicals
  semiColon        => q(⟢),                                                     # Semi colon symbol, left star: U+27E2
  separator        => chr(0x205F),                                              # Space for separating non ascii items allowing us to have spaces inside variable names
  structure        => Tree::Term::LexicalStructure,                             # Lexical structure from Tree::term
  dyad2Low         => undef,                                                    # Array of dyad 2 start of ranges
  dyad2High        => undef,                                                    # Array of dyad 2 end of ranges
  dyad2Offset      => undef,                                                    # Array of dyad 2 offsets at start of each range
  dyad2Chars       => undef,                                                    # Array of all dyad 2 characters
  dyad2Blocks      => undef,                                                    # Number of dyad2 blocks
  dyad2BlockSize   => 16,                                                       # Size of a dyad2 block
 );

sub Hex($)                                                                      # Print a number as hexadecimal
 {my ($n) = @_;                                                                 # Number
  sprintf("%x", $n)
 }

ok Hex(13) eq 'd';

sub printAlphabetInBlocks($)                                                    # Print an alphabet in blocks
 {my ($a) = @_;                                                                 # Characters in alphabet as an array reference
  my $N = 16;
  push my @t, join ' | ', '', '', 0..9, 'A'..'F', '';
  push    @t, join  '|',  '', ('---') x ($N+1), '';
  my @a = @$a;
  for my $i(0..$#a/$N)
   {my @r;
    for my $j(0..$N-1)
     {last unless my $C = shift @a;
      my $c = chr $C;
      $c =~ s([-`|]) ()g;
      push @r, $c;
     }
    push @t, join ' | ', '', Hex($i), @r, '';
   }
  @t
 }

sub printLexicalItemsMD()                                                       # Print lexical items as a table in mark down ## auto add to README.md2
 {my @t;
  push @t, "## Lexical elements\n";                                             # Title

  for my $l(sort {$a->letter cmp $b->letter} values %$Lexicals)                 # Each lexical letter
   {next unless my $a = $Tables->alphabetChars->{$l->letter};
    push @t, join '', "### ", ucfirst($l->name), ".",  "\n\n", $l->comment, ".\n";
    push @t, join '', "Contains: ", scalar(@$a), " characters.\n\n";

    push @t, printAlphabetInBlocks($Tables->alphabetChars->{$l->letter});
    push @t, "\n";
   }
  my $f = owf("LexicalItemsDescription.md", join "\n", @t);                     # Write to the named file
  say STDERR "Lexical items described in file: $f";
 }

if (!-e $data)                                                                  # Download Unicode specification if not present
 {say STDERR qx(curl -o $data $unicode);
 }

sub lexNameToLetter(*)                                                          # Get the letter for a lexical item from its name
 {my ($lexName) = @_;                                                           # Name of lexical item
  $Tables->lexicals->{$lexName}->letter                                         # The letter code for each lexical item type
 }

sub lexLetterToName(*)                                                          # Get the name of a lexical item from its letter
 {my ($lexLetter) = @_;                                                         # Letter of lexical item
  $Tables->lexicalsByLetter->{$lexLetter}->name
 }

ok lexLetterToName(a) eq 'assign';
ok lexLetterToName(e) eq 'dyad2';

sub lexNameToNumber(*)                                                          # Get the number for a lexical item from its name
 {my ($lexName) = @_;                                                           # Name of lexical item
  $Tables->lexicals->{$lexName}->number                                         # The letter code for each lexical item type
 }

ok lexNameToLetter(dyad)  eq 'd';
ok lexNameToLetter(dyad2) eq 'e';
ok lexNameToNumber(dyad)  ==  3;
ok lexNameToNumber(dyad2) == 13;

sub unicodePoint($)                                                             # Print a number as a Unicode code point
 {my ($n) = @_;                                                                 # Number
  "U+".Hex($n)
 }

ok unicodePoint(13) eq 'U+d';

sub getUsageOfChar($)                                                           # Get the lexical item associated with a character
 {my ($c) = @_;                                                                 # Character
  my $h = Hex(ord($c));
  $Usage{$h}
 }

sub setUsage($$)                                                                # Mark a character represented by its unicode point in hex as being in the specified alphabet for a lexical item
 {my ($c, $l) = @_;                                                             # Character, lexical type
  my $h = Hex(ord($c));
  !$Usage{$h} or $Usage{$h} eq $l or confess "\\U+$h assigned to both $l and ".$Usage{$h};
   $Usage{$h} = $l;
 }

sub setUsageForString($$)                                                       # Mark each character in a string as being in the specified alphabet for a lexical item
 {my ($s, $l) = @_;                                                             # Character, lexical type
  setUsage($_, $l) for split //, $s;
 }

sub convert($)                                                                  # Convert the hex representation of a character to a number
 {my ($c) = @_;                                                                 # Hexadecimal representation of character as in "2a00"
  eval "chr(0x$c)";                                                             # Character as number
 }

ok convert('27E2') eq $Tables->semiColon;

sub dyad2                                                                       # Locate symnbols to use as dyad2 operators
 {my @s = readFile $data;

  my %dyad2;                                                                    # Mathematical operators

  for my $s(@s)                                                                 # Select the letters we want
   {my ($c, $d, $t, $b) = split /;/, $s;
    my $C = convert $c;                                                         # Character
    next if $C eq $Tables->semiColon;

    next if $b =~ m(AL|R);                                                      # Remove right to left characters

    next unless ord($C) > 127;                                                  # Exclude ascii
    next unless $t =~ m(\ASm\Z);                                                # Mathematical symbol
    next if $d =~ m(CURLY BRACKET LOWER HOOK);
    next if $d =~ m(CURLY BRACKET MIDDLE PIECE);
    next if $d =~ m(CURLY BRACKET UPPER HOOK);
    next if $d =~ m(PARENTHESIS EXTENSION);
    next if $d =~ m(PARENTHESIS LOWER HOOK);
    next if $d =~ m(PARENTHESIS UPPER HOOK);
    next if $d =~ m(SQUARE BRACKET EXTENSION);
    next if $d =~ m(SQUARE BRACKET LOWER CORNER);
    next if $d =~ m(SQUARE BRACKET UPPER CORNER);

    next if $d =~ m(MATHEMATICAL SANS-SERIF BOLD ITALIC PARTIAL DIFFERENTIAL);
    next if $d =~ m(MATHEMATICAL SANS-SERIF BOLD NABLA);
    next if $d =~ m(MATHEMATICAL BOLD ITALIC PARTIAL DIFFERENTIAL);
    next if $d =~ m(MATHEMATICAL ITALIC PARTIAL DIFFERENTIAL);
    next if $d =~ m(MATHEMATICAL SANS-SERIF BOLD PARTIAL DIFFERENTIAL);
    next if $d =~ m(MATHEMATICAL SANS-SERIF BOLD ITALIC NABLA);
    next if $d =~ m(MATHEMATICAL BOLD ITALIC NABLA);
    next if $d =~ m(MATHEMATICAL ITALIC NABLA);
    next if $d =~ m(MATHEMATICAL BOLD PARTIAL DIFFERENTIAL);
    next if $d =~ m(MATHEMATICAL BOLD NABLA);
    next if $d =~ m(ARROW);

    $dyad2{unicodePoint ord($C)} = $C;
   }

  for my $c(0x200b..0x2069)                                                     # https://www.unicodepedia.com/groups/general-punctuation/
   {next if sprintf("%x", $c) =~ m(\A(2045|2046|2062|2063|2064||)\Z);
    $dyad2{unicodePoint($c)}  = chr($c);
   }

  my $range = sub                                                               # Add characters in range
   {for my $c(@_)
     {$dyad2{unicodePoint($c)} = chr($c);
     }
   };

  &$range(0x2200..0x22ff);                                                      # https://www.unicodepedia.com/groups/mathematical-operators/
  &$range(0x2300..0x2307);                                                      # https://www.unicodepedia.com/groups/mathematical-operators/
  &$range(0x230C..0x2328);                                                      # https://www.unicodepedia.com/groups/mathematical-operators/
  &$range(0x232C..0x23ff);                                                      # https://www.unicodepedia.com/groups/mathematical-operators/
  &$range(0x25A0..0x25ff);                                                      # https://www.unicodepedia.com/groups/geometric-shapes/
  &$range(0x2600..0x26ff);                                                      # https://www.unicodepedia.com/groups/miscellaneous-symbols/
  &$range(0x27c0..0x27e1);                                                      # https://www.unicodepedia.com/groups/miscellaneous-mathematical-symbols-a/
  &$range(0x27e3..0x27e5);                                                      # https://www.unicodepedia.com/groups/miscellaneous-mathematical-symbols-a/
  &$range(0x27f0..0x27ff);                                                      # https://www.unicodepedia.com/groups/supplemental-arrows-a/
  &$range(0x2800..0x28ff);                                                      # https://www.unicodepedia.com/groups/braille-patterns/
  &$range(0x2900..0x297f);                                                      # https://www.unicodepedia.com/groups/supplemental-arrows-b/
  &$range(0x2980..0x2982);                                                      # https://www.unicodepedia.com/groups/miscellaneous-mathematical-symbols-b/
  &$range(0x2999..0x29FB);                                                      # https://www.unicodepedia.com/groups/miscellaneous-mathematical-symbols-b/
  &$range(0x29FE..0x29FE);                                                      # https://www.unicodepedia.com/groups/miscellaneous-mathematical-symbols-b/
  &$range(0x2a00..0x2aff);                                                      # https://www.unicodepedia.com/groups/supplemental-mathematical-operators/
  &$range(0x2b00..0x2b58);                                                      # https://www.unicodepedia.com/groups/supplemental-punctuation/
  &$range(0x2e00..0x2e1f);                                                      # https://www.compart.com/en/unicode/block/U+2E00
  &$range(0x2e2a..0x2e30);                                                      # https://www.compart.com/en/unicode/block/U+2E00

  if (0)                                                                        # Print dyad2 operators chosen
   {for my $d(sort keys %dyad2)
     {say STDERR $dyad2{$d}, " ", $d;
     }
   }

  my @r = divideIntegersIntoRanges(map {ord} values %dyad2);                    # Divide an array of integers into ranges

  push @r, [0] while @r % $Tables->dyad2BlockSize;                              # Pad into blocks
  $Tables->dyad2Blocks = @r / $Tables->dyad2BlockSize;                          # Number of blocks

  say STDERR "Dyad 2 blocks: ", $Tables->dyad2Blocks, " block size: ", $Tables->dyad2BlockSize;

  my @l; my @h; my @o; my $o = 0;                                               # Low high, offset in range of dyad2
  for my $a(@r)
   {push @l, $$a[0]; push @h, $$a[-1]; push @o, $$a[0] - $o; $o += @$a;
   }
  for my $a(\@l, \@h, \@o)
   {say STDERR join ', ', map {sprintf("0x%04x", $_)} @$a;
   }

  setUsage($_, "dyad2") for values %dyad2;                                      # Mark usage

  $Tables->dyad2Low    = \@l;                                                   # Record start of each range
  $Tables->dyad2High   = \@h;                                                   # Record end of range
  $Tables->dyad2Offset = \@o;                                                   # Record offset of each range start
  $Tables->dyad2Chars  = [map {ord $_} sort values %dyad2];                     # Record characters comprising the dyad 2 alphabet
  $Tables->alphabetChars->{e} = [sort {$a <=> $b} map {ord $_} values %dyad2];
 }

sub alphabets                                                                   # Locate the mathematical alphabets used to represent lexical items.
 {my @s = readFile $data;                                                       # Read unicode

  my %alpha;                                                                    # Alphabet names

  for my $s(@s)                                                                 # Select the letters we want
   {my ($c, $d, $t, $b) = split /;/, $s;                                        # Parse unicode specification
    my $C = convert $c;                                                         # Character

# 1D49C;MATHEMATICAL SCRIPT CAPITAL A;Lu;0;L;<font> 0041;;;;N;;;;;              # Sample input - the particlular alphabet name is encoded in the character name
# 1D72D;MATHEMATICAL BOLD ITALIC CAPITAL THETA SYMBOL;Lu;0;L;<font> 03F4;;;;N;;;;;
# 1D70D;MATHEMATICAL ITALIC SMALL FINAL SIGMA;Ll;0;L;<font> 03C2;;;;N;;;;;

    next if $b =~ m(AL|R);                                                      # Remove right to left characters

    next if     $d =~ m(DIGAMMA)i;                                              # Select family of letters
    next if     $d =~ m(PLANCK CONSTANT OVER TWO)i;
    next unless $d =~ m(\A(Mathematical|Squared|Circled|Negative|PLANCK CONSTANT))i;
    next unless $t =~ m(\A(L|So|Sm));                                           # Letter or other symbol

    my $D = $d;
       $D =~ s(PARTIAL DIFFERENTIAL) ( )igs;
       $D =~ s(NABLA)                ( )igs;
       $D =~ s(\w+ SYMBOL\Z)         ( )ig;
       $D =~ s(FINAL \w+\Z)          ( )ig;
       $D =~ s(\w+\Z)                ( )gs;
       $D =~ s(Capital)              ( )igs;
       $D =~ s(Small)                ( )igs;
       $D =~ s(\s+)                  ( )igs;

    $alpha{$D}{$c} = $C;                                                        # Place into alphabets
   }

  my %selected;                                                                 # The selected alphabets to the characters in that alphabet

  for my $a(sort keys %alpha)                                                   # Each alphabet
   {next unless $a =~ m((CIRCLED LATIN LETTER|MATHEMATICAL BOLD|MATHEMATICAL BOLD FRAKTUR|MATHEMATICAL BOLD ITALIC|MATHEMATICAL BOLD SCRIPT|MATHEMATICAL DOUBLE-STRUCK|MATHEMATICAL FRAKTUR|MATHEMATICAL ITALIC|MATHEMATICAL MONOSPACE|MATHEMATICAL SANS-SERIF|MATHEMATICAL SANS-SERIF BOLD|MATHEMATICAL SANS-SERIF|BOLD ITALIC|MATHEMATICAL SANS-SERIF ITALIC|MATHEMATICAL SCRIPT|NEGATIVE|CIRCLED LATIN LETTER|NEGATIVE SQUARED LATIN LETTER|SQUARED LATIN LETTER|PLANCK))i;
                                                                                # Selected alphabets
    my @l;
    for my $l(sort keys $alpha{$a}->%*)                                         # Sort by point in each alphabet
     {push @l, $alpha{$a}{$l};
     }
    my $l = join '', sort @l;                                                   # Alphabet in point order
    next unless length($l) > 5 or $l eq "\x{210e}";                             # Ignore short sets which are probably not alphabets except for Plancks constant
    my $A = lcfirst join '', map {ucfirst} split /\s+/, lc $a;                  # Alphabet name
    $selected{$A} = $l;                                                         # Selected alphabets
   }

  $selected{semiColon} = $Tables->semiColon;                                    # We cannot use semi colon as the statement separator because it is an ascii character, so we use U+27E2 instead
  $selected{arrows}    = join '', map {chr $_} 0x2190..0x21FE;                  # Arrows are used for assignment regardless of the direction they point in.
  $selected{Ascii}     = join '', map {chr $_} 0x0..0x7f;                       # Ascii alphabet

  my %lexAlphas;                                                                # The alphabets used by each lexical item

  for my $a(sort keys %selected)                                                # Print selected alphabets in ranges
   {my $l = '';                                                                 # Lexical item long name
       $l = q(variable)  if $a =~ m/mathematicalSans-serifBold\Z/i;
       $l = q(dyad)      if $a =~ m/mathematicalBold\Z/i;
       $l = q(prefix)    if $a =~ m/mathematicalBoldItalic\Z/i;
       $l = q(assign)    if $a =~ m/mathematicalItalic\Z/i;
       $l = q(assign)    if $a =~ m/planck/i;                                   # Fills a gap in mathematicalItalic
       $l = q(assign)    if $a =~ m/arrows/i;
       $l = q(suffix)    if $a =~ m/mathematicalSans-serifBoldItalic\Z/i;
       $l = q(Ascii)     if $a =~ m/\AcircledLatinLetter\Z/i;                   # Control characters as used in regular expressions and quoted strings
       $l = q(Ascii)     if $a =~ m/Ascii\Z/i;                                  # Ascii
       $l = q(semiColon) if $a =~ m/semiColon\Z/i;                              # Semicolon

    next unless $l;
    my $ll = lexNameToLetter($l);                                               # The letter code for each lexical item type
    $lexAlphas{$l}{$a}++;                                                       # This lexical item uses this alphabet

    for my $c(split //, $selected{$a})                                          # Check for duplicate usage
     {setUsage($c, $l);                                                         # Detect duplicate point usage
     }
   }

  my %lexAlphabet;                                                              # Consolidated sorted alphabet associated with each lexical item
  for my $l(sort keys %lexAlphas)                                               # Print the alphabets used by each lexical item
   {for my $a(sort keys $lexAlphas{$l}->%*)                                     # Print the alphabets used by each lexical item
     {$lexAlphabet{$l} .= $selected{$a};
     }
    $lexAlphabet{$l} = join '', sort split //, $lexAlphabet{$l};                # Sort each alphabet
   }

  for my $l(sort keys %lexAlphas)                                               # Print the alphabets used by each lexical item
   {say STDERR '-' x 44;
    say STDERR $l;
    for my $a(sort keys $lexAlphas{$l}->%*)                                     # Print the alphabets used by each lexical item
     {say STDERR "  ", pad($a, 42), " : ", $selected{$a};
     }
    say STDERR pad("Consolidated", 44), " : ", $lexAlphabet{$l};
    length($lexAlphabet{$l}) > 255 and confess "Alphabet too big for $l";
    $Tables->alphabetChars->{lexNameToLetter($l)} =                             # So we can translate some text
     [map {ord $_} split //, $lexAlphabet{$l}];

   }

  my $lexAlphabet = '';                                                         # Consolidated sorted alphabet over all lexical items
  for my $l(sort keys %lexAlphabet)
   {$lexAlphabet .= $lexAlphabet{$l};
   }

  $lexAlphabet = join '', sort split //, $lexAlphabet;                          # Sorted lexical lphabet

  my @range = divideCharactersIntoRanges $lexAlphabet;                          # Ranges of characters

  if (1)                                                                        # Split ranges that span lexical items
   {my @r;                                                                      # New ranges
    while(@range)                                                               # Each range
     {my $r = shift @range;                                                     # Remove next range
      my $commonUsage = sub                                                     # Extract common usage from a string and return remainder
       {my ($string) = @_;                                                      # String
        my $l = substr $string, 0, 1;
        my $L = getUsageOfChar $l;
        for my $i(1..length($string)-1)
         {my $h = substr $string, $i, 1;
          my $H = getUsageOfChar $h;
          if ($H ne $L)
           {push @r, substr($string, 0, $i);
            return   substr($string, $i);
            }
          }
         push @r, $string;
         return '';
       };

      for(1..10)                                                                # Extract sub blocks with same lexical item
       {if (length($r) > 0)
         {$r = &$commonUsage($r);
         }
       }
     }

    @r >= @range or confess "Missing range";
    @r >  16    and confess "Too many ranges for one zmm register: ", scalar(@r);
    @range = @r;
   }

  if (1)                                                                        # Print each range
   {my @t;
    for my $i(0..$#range)                                                       # Each range
     {my $r = $range[$i];                                                       # Points used in range
      my $l = substr $r, 0, 1;
      my $h = substr $r, -1;
      my $L = getUsageOfChar $l;
      my $H = getUsageOfChar $h;
      push @t, [ord($l),  ord($h), $L, $H, lexNameToNumber $L];
      $L eq $H or confess "Range with differinging lexicals: $L $H";
     }
    say STDERR formatTable(\@t, [qw(Start End Lex1 Lex2 Number)],
      title=> "Lexical Ranges");
   }

  if (1)                                                                        # Zmm load sequence
   {my @l;                                                                      # Low end of range
    my @h;                                                                      # High end of range

    for my $i(0..$#range)                                                       # Each range
     {my $r = $range[$i];                                                       # Points used in range
      my $l = substr $r, 0, 1;
      my $h = substr $r, -1;
      my $L = getUsageOfChar $l;
      my $H = getUsageOfChar $h;
      my $n = lexNameToNumber $L;                                               # Lexical number of range
      my $o = index($lexAlphabet{$L}, $l);                                      # Offset of this range in alphabet of lexical item
      $o < 0 and confess "No start for $l in $L : $lexAlphabet{$L}";

      push @l, (($n<<24) + ord($l));                                            # Start of range in zmm
      push @h, (($o<<24) + ord($h));                                            # End of range in zmm
     }

    push @l, 0 while @l < 16;                                                   # Clear remaining ranges
    push @h, 0 while @h < 16;
    my $l = join ', ', map {sprintf("0x%08x", $_)} @l;                          # Format zmm load sequence
    my $h = join ', ', map {sprintf("0x%08x", $_)} @h;
    say STDERR "Lexical Low / Lexical High:\n$l\n$h";
    $Tables->lexicalLow  = [@l];
    $Tables->lexicalHigh = [@h];
   }
 }

sub brackets                                                                    # Locate bracket characters
 {my @S;

  my @s = readFile $data;

  for my $s(@s)                                                                 # Select the brackets we want
   {next unless $s =~ m(;P[s|e];)i;                                             # Select brackets
    my @w = split m/;/, $s;

    my ($point, $name) = @w;
    my $u = eval "0x$point";
    $@ and confess "$s\n$@\n";

    next if $u <= 0x208e;
    next if $u >= 0x23A1 and $u <= 0x23B1;
    next if $u >= 0x27C5 and $u <= 0x27C6;                                      # Bag
    next if $u >= 0x29D8 and $u <= 0x29D9;                                      # Wiggly fence
    next if $u >= 0x29DA and $u <= 0x29Db;                                      # Double Wiggly fence
    next if $u >= 0x2E02 and $u <= 0x2E27;
    next if $u == 0x2E42;                                                       # Double Low-Reversed-9 Quotation Mark[1]
    next if $u >= 0x300C and $u <= 0x300F;
    next if $u >= 0x301D and $u <= 0x3020;                                      # Quotation marks
    next if $u >= 0xFE17 and $u <= 0xFE5E ;
    next if $u >= 0xFF62;

    push @S, [$u, $name, $s];

    setUsage(chr($u), "bracket");
   }

  @S % 2 and confess "Mismatched bracket pairs";
  lll "Bracket Pairs: ", scalar(@S) / 2;

  my ($T, @T) = @S;                                                             # Divide into ranges
  push my @t, [$T];
  for my $t(@T)
   {my ($u, $point, $name) = @$t;
    if ($$T[0] + 1 == $u)
     {push $t[-1]->@*, $T = $t;
      next;
     }
    push @t, [$T = $t];
   }

  @t = grep {@$_ > 1} @t;                                                       # Remove small blocks so we can fit into one zmm

  if (1)                                                                        # Bracket strings
   {my @o; my @c;
    my $i = 0;
    for   my $r(@t)
     {for my $t(@$r)
       {push @o, chr $$t[0] unless $i % 2;
        push @c, chr $$t[0] if     $i % 2;
        ++$i;
       }
     }

    if (0)                                                                      # Print every bracket pair
     {for my $i(keys @o)
       {lll "Bracket pair $i", $o[$i], $c[$i], ord($o[$i]), ord($c[$i]);
       }
     }

    $Tables->bracketsOpen  = [@o];                                              # Brackets list
    $Tables->bracketsClose = [@c];
   }

  my @l; my @h;
  my $index = $Tables->bracketsBase;                                            # Brackets are numbered from here

  for my $t(@t)                                                                 # Load zmm0, zmm1
   {if (@$t > 1)
     {push @l, sprintf("0x%08x", $$t[0] [0] + ($index<<24));
      $index += scalar(@$t) - 1;
      push @h, sprintf("0x%08x", $$t[-1][0] + ($index<<24));
     }
    elsif ($$t[-1][-1] =~ m(LEFT))                                              # Single range left
     {++$index if $index % 2;
      push @l, sprintf("0x%08x", $$t[0] [0] + ($index<<24));
      push @h, sprintf("0x%08x", $$t[0] [0] + ($index<<24));
     }
    else                                                                        # Single range right
     {++$index unless $index % 2;
      push @l, sprintf("0x%08x", $$t[0] [0] + ($index<<24));
      push @h, sprintf("0x%08x", $$t[0] [0] + ($index<<24));
     }
    $index += 1;
   }

  push @l, 0 while @l < 16;
  push @h, 0 while @h < 16;
  $Tables->brackets = @l;                                                       # Number of brackets
  lll "Bracket ranges: ", scalar(@l);

  my $L = join '', join(', ',  @l);
  my $H = join '', join(', ',  @h);
  say STDERR "$L\n$H";

  $Tables->bracketsLow  = [@l];
  $Tables->bracketsHigh = [@h];
 }

sub tripleTerms                                                                 # All invalid transitions that could usefully interpret one intervening new line as a semi colon
 {my %C = Tree::Term::LexicalStructure->codes->%*;
  my @d = qw(a B b d p q v);                                                    # Ignoring semi colon as intervening space is specially treated as empty.
  my %semi; my %possible;                                                       # Pairs between which we could usefully insert a semi colon
  for   my $a(@d)
   {for my $b(@d)
     {if (!Tree::Term::validPair($a, $b))
       {my $as = Tree::Term::validPair($a, 's');
        my $sb = Tree::Term::validPair('s', $b);
        if    ($as && $sb)
         {$semi{$a}{$b}++;
          $possible{$a}++; $possible{$b}++;                                     # Lexicals relevant to new line insertion
         }
       }
     }
   }
  lll "New line insertions points\n", dump(\%semi, \%possible);
 }

sub translateSomeText($$)                                                       # Translate some text
 {my ($title, $string) = @_;                                                    # Name of text, string to translate

  my %alphabets = ($Tables->alphabetChars->%*, e => $Tables->dyad2Chars);       # Alphabets for each lexical

  my $T = '';                                                                   # Translated text as characters
  my $normal = join '', 'A'..'Z', 'a'..'z';                                     # The alphabet we can write lexical items

  my sub translate($)                                                           # Translate a string written in normal into the indicated alphabet
   {my ($lexical) = @_;                                                         # Lexical item to translate
    my $l = substr $lexical, 0, 1;                                              # Lexical letter
    my $a = $alphabets{$l};                                                     # Alphabet to translate to

    for my $c(split //, substr($lexical, 1))
     {my $i = index $normal, $c;
      my $t;
      if ($l eq 'a')                                                            # The long struggle for mathematical italic h as used in physics.
       {if ($c eq 'h')
         {$t = "\x{210e}";
         }
        elsif ($c lt 'h')
         {$t = $$a[$i+112];
         }
        else
         {$t = $$a[$i+111];
         }
       }
      else
       {$t = $$a[$i];
       }
      $T .= chr($t);
     }
   }

  for my $w(split /\s+/, $string)                                               # Translate to text
   {if    ($w =~ m(\A(a|d|e|p|q|v))) {translate $w}
    elsif ($w =~ m(\As)) {$T .= $Tables->semiColon}
    elsif ($w =~ m(\Ab)) {$T .= $Tables->bracketsOpen ->[substr($w, 1)||0]}
    elsif ($w =~ m(\AB)) {$T .= $Tables->bracketsClose->[substr($w, 1)||0]}
    elsif ($w =~ m(\AS)) {$T .= ' '}
    elsif ($w =~ m(\AN)) {$T .= "\n"}
    elsif ($w =~ m(\AA)) {$T .= substr($w, 1)}
    else {confess "Invalid lexical item $w in $string"}
   }

  my @L;                                                                        # Translated text as lexical elements
  my %l = $Tables->lexicals->%*;                                                # Flatten lexical items
  my %n = map {$_=>$l{$_}->number} sort keys %l;                                # Numeric code for each lexical
  for my $w(split /\s+/, $string)                                               # Translate to lexical elements
   {my $t = substr($w, 0, 1);
       if ($w =~ m(\Aa)) {push @L, $n{assign}}
    elsif ($w =~ m(\Ad)) {push @L, $n{dyad}}
    elsif ($w =~ m(\Ae)) {push @L, $n{dyad2}}
    elsif ($w =~ m(\Av)) {push @L, $n{variable}}
    elsif ($w =~ m(\As)) {push @L, $n{semiColon}}
    elsif ($w =~ m(\Ab)) {push @L, $n{OpenBracket}}
    elsif ($w =~ m(\AB)) {push @L, $n{CloseBracket}}
    elsif ($w =~ m(\AS)) {push @L, ($n{Ascii} << 24) + ord(' ')}                # Expected classification
    elsif ($w =~ m(\AN)) {push @L, ($n{Ascii} << 24) + ord("\n")}
    elsif ($w =~ m(\AA)) {push @L, ($n{Ascii} << 24) + ord('A')}
   }
  say STDERR '-' x 32;
  say STDERR $title;
  say STDERR "Sample text length in chars   : ", sprintf("0x%x", length($T));
  say STDERR "Sample text length in lexicals: ", scalar(@L);

  if (0)                                                                        # Print source code as utf8
   {my @T = split //, $T;
    for my $i(keys @T)
     {my $c = $T[$i];
      say STDERR "$i   $c ", sprintf("%08x   %08x", ord($c), convertUtf32ToUtf8(ord($c)));
     }
   }

  say STDERR "Sample text                   :\n$T";
  say STDERR "Sample lexicals               :\n", dump(\@L);

  $Tables->sampleText    ->{$title} = $T;                                       # Save sample text
  $Tables->sampleLexicals->{$title} = [map {$_ < 16 ? $_<<24 : $_} @L];         # Boost lexical elements not already boosted
 }

alphabets;                                                                      # Locate alphabets
dyad2;                                                                          # Dyadic operators at priority 4 that is one more urgent than dyads
brackets;                                                                       # Locate brackets
tripleTerms;                                                                    # All invalid transitions that could usefully interpret one intervening new line as a semi colon
printLexicalItemsMD;                                                            # Print the lexical items as mark down

translateSomeText 'v', <<END;                                                   # Translate some text
va
END

translateSomeText 's', <<END;
va s vb
END

translateSomeText 'vav', <<END;
va aa vb
END

translateSomeText 'vavav', <<END;
va aa vb aa vc
END

translateSomeText 'bvB', <<END;
b2 vabc B2
END

translateSomeText 'ws', <<END;
va aassign b1 b2 b3 vbp B3 B2 dplus b4 vsc B4 B1 s
vaa aassign b5 vbb dplus vcc B5 s
END

translateSomeText 'wsa', <<END;
va aassign b1 b2 b3 vbp B3 B2 dplus b4 vsc B4 B1 s
vaa aassign
  Asome--ascii--text dplus
  vcc s
END

translateSomeText 'brackets', <<END;
va aassign b1 b2 b3 vbp B3 B2 dplus b4 vsc B4 B1 s
END

translateSomeText 'nosemi', <<END;
va aassign b1 b2 b3 vbp B3 B2 dplus b4 vsc B4 B1
END

translateSomeText 's1', <<END;
va aa N S S A N S S S
END

translateSomeText 'vnv', <<END;
va N vb
END

translateSomeText 'vnvs', <<END;
va N vb S S S S
END

translateSomeText 'vnsvs', <<END;
vaa N S S S vbb S S S
END

translateSomeText 'vaA', <<END;
vaa aassign Aabc S A123
END

translateSomeText 'vaAdv', <<END;
vaa aassign Aabc S A123  S S S S dplus vvar
END

translateSomeText 'BB', <<END;
b1 b2 b3 b4 b5 b6 b7 b8 va B8 B7 B6 B5 B4 B3 B2 B1
END

translateSomeText 'ppppvdvdvqqqq', <<END;
pa b9 pb b10 pc b11 va aassign pd vb qd dtimes b12 vc dplus vd B12 s ve aassign vf dsub vg  qh B11 qc B10  qb B9 qa
END

translateSomeText 'e', <<END;
va eD vb
END

translateSomeText 'add', <<END;
va aassign vb dplus vc ddivide vd
END

translateSomeText 'ade', <<END;
va aassign vb dplus vc eD vd
END

translateSomeText 'A3', <<END;
Aabc
END

translateSomeText 'Adv', <<END;
Aabc S A123  S S S S dplus vvar
END

translateSomeText 'vav', <<END;
va aassign vb
END

say STDERR owf $lexicalsFile, dump($Tables);                                    # Write results

if (1)                                                                          # Update Parse.pm
 {my $S = q(DDDD);                                                              # Data body
  my $s = readFile $parse;
  my $d = dump $Tables;
     $s =~ s(\n#d\n.*?#-) (\n#d\nsub lexicalData \{$S\}\n\n#-)gs;
  my $i = index($s, $S);
  $i == -1 and confess;
  $s = substr($s, 0, $i) . $d . substr($s, $i+length($S));
  owf($parse, $s);
 }

__DATA__
CIRCLED LATIN LETTER  : ⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩ
MATHEMATICAL BOLD  : 𝐀𝐁𝐂𝐃𝐄𝐅𝐆𝐇𝐈𝐉𝐊𝐋𝐌𝐍𝐎𝐏𝐐𝐑𝐒𝐓𝐔𝐕𝐖𝐗𝐘𝐙𝐚𝐛𝐜𝐝𝐞𝐟𝐠𝐡𝐢𝐣𝐤𝐥𝐦𝐧𝐨𝐩𝐪𝐫𝐬𝐭𝐮𝐯𝐰𝐱𝐲𝐳𝚨𝚩𝚪𝚫𝚬𝚭𝚮𝚯𝚰𝚱𝚲𝚳𝚴𝚵𝚶𝚷𝚸𝚺𝚻𝚼𝚽𝚾𝚿𝛀𝛂𝛃𝛄𝛅𝛆𝛇𝛈𝛉𝛊𝛋𝛌𝛍𝛎𝛏𝛐𝛑𝛒𝛔𝛕𝛖𝛗𝛘𝛙𝛚𝟊𝟋
MATHEMATICAL BOLD FRAKTUR  : 𝕬𝕭𝕮𝕯𝕰𝕱𝕲𝕳𝕴𝕵𝕶𝕷𝕸𝕹𝕺𝕻𝕼𝕽𝕾𝕿𝖀𝖁𝖂𝖃𝖄𝖅𝖆𝖇𝖈𝖉𝖊𝖋𝖌𝖍𝖎𝖏𝖐𝖑𝖒𝖓𝖔𝖕𝖖𝖗𝖘𝖙𝖚𝖛𝖜𝖝𝖞𝖟
MATHEMATICAL BOLD ITALIC  : 𝑨𝑩𝑪𝑫𝑬𝑭𝑮𝑯𝑰𝑱𝑲𝑳𝑴𝑵𝑶𝑷𝑸𝑹𝑺𝑻𝑼𝑽𝑾𝑿𝒀𝒁𝒂𝒃𝒄𝒅𝒆𝒇𝒈𝒉𝒊𝒋𝒌𝒍𝒎𝒏𝒐𝒑𝒒𝒓𝒔𝒕𝒖𝒗𝒘𝒙𝒚𝒛𝜜𝜝𝜞𝜟𝜠𝜡𝜢𝜣𝜤𝜥𝜦𝜧𝜨𝜩𝜪𝜫𝜬𝜮𝜯𝜰𝜱𝜲𝜳𝜴𝜶𝜷𝜸𝜹𝜺𝜻𝜼𝜽𝜾𝜿𝝀𝝁𝝂𝝃𝝄𝝅𝝆𝝈𝝉𝝊𝝋𝝌𝝍𝝎
MATHEMATICAL BOLD SCRIPT  : 𝓐𝓑𝓒𝓓𝓔𝓕𝓖𝓗𝓘𝓙𝓚𝓛𝓜𝓝𝓞𝓟𝓠𝓡𝓢𝓣𝓤𝓥𝓦𝓧𝓨𝓩𝓪𝓫𝓬𝓭𝓮𝓯𝓰𝓱𝓲𝓳𝓴𝓵𝓶𝓷𝓸𝓹𝓺𝓻𝓼𝓽𝓾𝓿𝔀𝔁𝔂𝔃
MATHEMATICAL DOUBLE-STRUCK  : 𝔸𝔹𝔻𝔼𝔽𝔾𝕀𝕁𝕂𝕃𝕄𝕆𝕊𝕋𝕌𝕍𝕎𝕏𝕐𝕒𝕓𝕔𝕕𝕖𝕗𝕘𝕙𝕚𝕛𝕜𝕝𝕞𝕟𝕠𝕡𝕢𝕣𝕤𝕥𝕦𝕧𝕨𝕩𝕪𝕫
MATHEMATICAL FRAKTUR  : 𝔄𝔅𝔇𝔈𝔉𝔊𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔𝔖𝔗𝔘𝔙𝔚𝔛𝔜𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔴𝔵𝔶𝔷
MATHEMATICAL ITALIC  : 𝐴𝐵𝐶𝐷𝐸𝐹𝐺𝐻𝐼𝐽𝐾𝐿𝑀𝑁𝑂𝑃𝑄𝑅𝑆𝑇𝑈𝑉𝑊𝑋𝑌𝑍𝑎𝑏𝑐𝑑𝑒𝑓𝑔𝑖𝑗𝑘𝑙𝑚𝑛𝑜𝑝𝑞𝑟𝑠𝑡𝑢𝑣𝑤𝑥𝑦𝑧𝛢𝛣𝛤𝛥𝛦𝛧𝛨𝛩𝛪𝛫𝛬𝛭𝛮𝛯𝛰𝛱𝛲𝛴𝛵𝛶𝛷𝛸𝛹𝛺𝛼𝛽𝛾𝛿𝜀𝜁𝜂𝜃𝜄𝜅𝜆𝜇𝜈𝜉𝜊𝜋𝜌𝜎𝜏𝜐𝜑𝜒𝜓𝜔
MATHEMATICAL MONOSPACE  : 𝙰𝙱𝙲𝙳𝙴𝙵𝙶𝙷𝙸𝙹𝙺𝙻𝙼𝙽𝙾𝙿𝚀𝚁𝚂𝚃𝚄𝚅𝚆𝚇𝚈𝚉𝚊𝚋𝚌𝚍𝚎𝚏𝚐𝚑𝚒𝚓𝚔𝚕𝚖𝚗𝚘𝚙𝚚𝚛𝚜𝚝𝚞𝚟𝚠𝚡𝚢𝚣
MATHEMATICAL SANS-SERIF  : 𝖠𝖡𝖢𝖣𝖤𝖥𝖦𝖧𝖨𝖩𝖪𝖫𝖬𝖭𝖮𝖯𝖰𝖱𝖲𝖳𝖴𝖵𝖶𝖷𝖸𝖹𝖺𝖻𝖼𝖽𝖾𝖿𝗀𝗁𝗂𝗃𝗄𝗅𝗆𝗇𝗈𝗉𝗊𝗋𝗌𝗍𝗎𝗏𝗐𝗑𝗒𝗓
MATHEMATICAL SANS-SERIF BOLD  : 𝗔𝗕𝗖𝗗𝗘𝗙𝗚𝗛𝗜𝗝𝗞𝗟𝗠𝗡𝗢𝗣𝗤𝗥𝗦𝗧𝗨𝗩𝗪𝗫𝗬𝗭𝗮𝗯𝗰𝗱𝗲𝗳𝗴𝗵𝗶𝗷𝗸𝗹𝗺𝗻𝗼𝗽𝗾𝗿𝘀𝘁𝘂𝘃𝘄𝘅𝘆𝘇𝝖𝝗𝝘𝝙𝝚𝝛𝝜𝝝𝝞𝝟𝝠𝝡𝝢𝝣𝝤𝝥𝝦𝝨𝝩𝝪𝝫𝝬𝝭𝝮𝝰𝝱𝝲𝝳𝝴𝝵𝝶𝝷𝝸𝝹𝝺𝝻𝝼𝝽𝝾𝝿𝞀𝞂𝞃𝞄𝞅𝞆𝞇𝞈
MATHEMATICAL SANS-SERIF BOLD ITALIC  : 𝘼𝘽𝘾𝘿𝙀𝙁𝙂𝙃𝙄𝙅𝙆𝙇𝙈𝙉𝙊𝙋𝙌𝙍𝙎𝙏𝙐𝙑𝙒𝙓𝙔𝙕𝙖𝙗𝙘𝙙𝙚𝙛𝙜𝙝𝙞𝙟𝙠𝙡𝙢𝙣𝙤𝙥𝙦𝙧𝙨𝙩𝙪𝙫𝙬𝙭𝙮𝙯𝞐𝞑𝞒𝞓𝞔𝞕𝞖𝞗𝞘𝞙𝞚𝞛𝞜𝞝𝞞𝞟𝞠𝞢𝞣𝞤𝞥𝞦𝞧𝞨𝞪𝞫𝞬𝞭𝞮𝞯𝞰𝞱𝞲𝞳𝞴𝞵𝞶𝞷𝞸𝞹𝞺𝞼𝞽𝞾𝞿𝟀𝟁𝟂
MATHEMATICAL SANS-SERIF ITALIC  : 𝘈𝘉𝘊𝘋𝘌𝘍𝘎𝘏𝘐𝘑𝘒𝘓𝘔𝘕𝘖𝘗𝘘𝘙𝘚𝘛𝘜𝘝𝘞𝘟𝘠𝘡𝘢𝘣𝘤𝘥𝘦𝘧𝘨𝘩𝘪𝘫𝘬𝘭𝘮𝘯𝘰𝘱𝘲𝘳𝘴𝘵𝘶𝘷𝘸𝘹𝘺𝘻
MATHEMATICAL SCRIPT  : 𝒜𝒞𝒟𝒢𝒥𝒦𝒩𝒪𝒫𝒬𝒮𝒯𝒰𝒱𝒲𝒳𝒴𝒵𝒶𝒷𝒸𝒹𝒻𝒽𝒾𝒿𝓀𝓁𝓂𝓃𝓅𝓆𝓇𝓈𝓉𝓊𝓋𝓌𝓍𝓎𝓏
NEGATIVE CIRCLED LATIN LETTER  : 🅐🅑🅒🅓🅔🅕🅖🅗🅘🅙🅚🅛🅜🅝🅞🅟🅠🅡🅢🅣🅤🅥🅦🅧🅨🅩
NEGATIVE SQUARED LATIN LETTER  : 🅰🅱🅲🅳🅴🅵🅶🅷🅸🅹🅺🅻🅼🅽🅾🅿🆀🆁🆂🆃🆄🆅🆆🆇🆈🆉
SQUARED LATIN LETTER  : 🄰🄱🄲🄳🄴🄵🄶🄷🄸🄹🄺🄻🄼🄽🄾🄿🅀🅁🅂🅃🅄🅅🅆🅇🅈🅉🆥
