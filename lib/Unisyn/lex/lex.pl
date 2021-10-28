#!/usr/bin/perl -I/home/phil/perl/cpan/DataTableText/lib/  -I/home/phil/perl/cpan/TreeTerm/lib/
#!/usr/bin/perl -I/home/phil/perl/cpan/DataTableText/lib/  -I/home/phil/perl/cpan/TreeTerm/lib/
#-------------------------------------------------------------------------------
# Find all 13 Unicode Mathematical Alphabets as used by Erl.
# Philip R Brenan at appaapps dot com, Appa Apps Ltd Inc., 2021
#-------------------------------------------------------------------------------
use warnings FATAL => qw(all);
use strict;
use Carp;
use Data::Dump qw(dump);
use Data::Table::Text qw(:all);
use Tree::Term;
use feature qw(say state current_sub);
use utf8;

my $home    = currentDirectory;                                                 # Home folder
my $parse   = q(/home/phil/perl/cpan/UnisynParse/lib/Unisyn/Parse.pm);          # Parse file
my $unicode = q(https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt); # Unicode specification
my $data    = fpe $home, qw(unicode txt);                                       # Local copy of unicode
my $lexicalsFile = fpe $home, qw(lex data);                                     # Dump of lexicals

makeDieConfess;

# Unicode currently has less than 2**18 characters. The biggest block we have is mather matical operators which is < 1k = 2**12.

sub LexicalConstant($$$;$)                                                      # Lexical constants as opposed to derived values
 {my ($name, $number, $letter, $like) = @_;                                     # Name of the lexical item, numeric code, character code, character code as used Tree::Term, a specialized instance of this Tree::Term which is never the less lexically identical to the Tree::Term
  genHash("Unisyn::Parse::Lexical::Constant",                                   # Description of a lexical item connecting the definition in Tree::Term with that inUnisyn
    name   => $name,                                                            #I Name of the lexical item
    number => $number,                                                          #I Numeric code for lexical item
    letter => $letter,                                                          #I Alphabetic name for lexical item
    like   => $like,                                                            #I Parsed like this element from Tree::Term
   );
 }

my $Lexicals = genHash("Unisyn::Parse::Lexicals",                               # Lexical items in Unisyn
  OpenBracket       => LexicalConstant("OpenBracket",        0, 'b', 'b'),      # The lowest bit of an open bracket code is zero
  CloseBracket      => LexicalConstant("CloseBracket",       1, 'B', 'B'),      # The lowest bit of a close bracket code is one
  Ascii             => LexicalConstant("Ascii",              2, 'a', 'v'),      # Ascii characters
  dyad              => LexicalConstant("dyad",               3, 'd', 'd'),      # Infix operator with left to right binding at priority 3
  prefix            => LexicalConstant("prefix",             4, 'p', 'p'),      # Prefix operator - it applies only to the following variable
  assign            => LexicalConstant("assign",             5, 'a', 'a'),      # Assign infix operator with right to left binding at priority 2.
  variable          => LexicalConstant("variable",           6, 'v', 'v'),      # Variable although it could also be an ascii string or regular expression
  suffix            => LexicalConstant("suffix",             7, 'q', 'q'),      # Suffix operator - it applies only to the preceding variable
  semiColon         => LexicalConstant("semiColon",          8, 's', 's'),      # Infix operator with left to right binding at priority 1
  term              => LexicalConstant("term",               9, 't', 't'),      # Term in the parse tree
  empty             => LexicalConstant("empty",             10, 'e', 'e'),      # Empty term present between two adjacent semicolons
  WhiteSpace        => LexicalConstant("WhiteSpace",        11, 'W'),           # White space that can be ignored during lexical analysis
  NewLineSemiColon  => LexicalConstant("NewLineSemiColon",  12, 'N'),           # A new line character that is also acting as a semi colon
  dyad2             => LexicalConstant("dyad2",             13, 'e', 'e'),      # Infix operator with left to right binding at priority 4
 );

my $TreeTermLexicals = Tree::Term::LexicalStructure->codes;

my $Tables = genHash("Unisyn::Parse::Lexical::Tables",                          # Tables used to parse lexical items
  alphabets        => undef,                                                    # Alphabets selected from uncode database
  alphabetRanges   => undef,                                                    # Number of alphabet ranges
  alphabetsOrdered => undef,                                                    # Alphabets be lexical element name with each alphabet ordered by unicode point
  brackets         => undef,                                                    # Number of brackets
  bracketsBase     => 0x10,                                                     # Start numbering brackets from here
  bracketsHigh     => undef,                                                    # High zmm for closing brackets
  bracketsLow      => undef,                                                    # Low  zmm for opening brackets
  bracketsOpen     => undef,                                                    # Open brackets
  bracketsClose    => undef,                                                    # Close brackets
  lexicalAlpha     => undef,                                                    # The alphabets assigned to each lexical item
  lexicalHigh      => undef,                                                    # High zmm for lexical items
  lexicalLow       => undef,                                                    # Low  zmm for lexical items
  lexicals         => $Lexicals,                                                # The lexical items
  sampleLexicals   => undef,                                                    # Has of sample program as arrays of lexical items
  sampleText       => undef,                                                    # Sample programs in utf8
  treeTermLexicals => $TreeTermLexicals,                                        # Tree term lexicals
  semiColon        => q(⟢),                                                     # Semi colon symbol, left star: U+27E2
  separator        => q( ),                                                      # Space for separating non ascii items: U+205F
  structure        => Tree::Term::LexicalStructure,                             # Lexical structure from Tree::term
  dyad2Low         => undef,                                                    # Array of dyad 2 start of ranges
  dyad2High        => undef,                                                    # Array of dyad 2 end of ranges
  dyad2Offset      => undef,                                                    # Array of dyad 2 offsets at start of each range
  dyad2Chars       => undef,                                                    # Array of all dyad 2 operators
  dyad2Alpha       => undef,                                                    # String of all dyad 2 operators
  dyad2Blocks      => 4,                                                        # Number of dyad2 blocks
  dyad2BlockSize   => 16,                                                       # Size of a dyad2 block
 );

if (!-e $data)                                                                  # Download Unicode specification
 {say STDERR qx(curl -o $data $unicode);
 }

sub convert($)                                                                  # Convert a character from hex to actual
 {my ($c) = @_;                                                                 # Parameters
  eval "chr(0x$c)";                                                             # Character
 }

sub printDyad2($)                                                              # Print dyad 2 operators in an 80 character wide block
 {my ($d) = @_;

  my @d = sort values %$d;
  for(my $i = 0; @d; ++$i)
   {print STDERR shift(@d);
    say STDERR "" if $i and $i % 80 == 0;
   }
  say STDERR "";
 }

sub dyad2                                                                       # Locate the mathematical alphabets
 {my @s = readFile $data;

  my %dyad2;                                                                    # Mathematical operators

  for my $s(@s)                                                                 # Select the letters we want
   {my ($c, $d, $t) = split /;/, $s;
    my $C = convert $c;                                                         # Character

    next unless ord($C) > 127;                                                  # Exclude ascii
    next unless $t =~ m(\ASm\Z);                                                  # Mathematical synmbol
    next  if $d =~ m(CURLY BRACKET LOWER HOOK);
    next  if $d =~ m(CURLY BRACKET MIDDLE PIECE);
    next  if $d =~ m(CURLY BRACKET UPPER HOOK);
    next  if $d =~ m(PARENTHESIS EXTENSION);
    next  if $d =~ m(PARENTHESIS LOWER HOOK);
    next  if $d =~ m(PARENTHESIS UPPER HOOK);
    next  if $d =~ m(SQUARE BRACKET EXTENSION);
    next  if $d =~ m(SQUARE BRACKET LOWER CORNER);
    next  if $d =~ m(SQUARE BRACKET UPPER CORNER);

    $dyad2{$d} = convert $c;                                                    # Character
   }
  for my $d(sort keys %dyad2)                                                   #
   {#say STDERR $dyad2{$d}, " ", $d;
   }

  my @r = divideIntegersIntoRanges(map {ord} values %dyad2);                    # Divide an array of integers into ranges

  push @r, [0] while @r != 64;                                                  # Pad up to 64 ranges

  my @l; my @h; my @o; my $o = 0;                                               # Low high, offset in range
  for my $a(@r)
   {push @l, $$a[0]; push @h, $$a[-1]; push @o, $$a[0] - $o; $o += @$a;
   }
  for my $a(\@l, \@h, \@o)
   {say STDERR join ', ', map {sprintf("0x%04x", $_)} @$a;
   }

  $Tables->dyad2Low    = \@l;                                                   # Record start of each range
  $Tables->dyad2High   = \@h;                                                   # Record end of range
  $Tables->dyad2Offset = \@o;                                                   # Record offset of each range start
  $Tables->dyad2Chars  = my $a = [map {ord $_} sort values %dyad2];             # Record characters comprising the dyad 2 alphabet
  $Tables->dyad2Alpha  = join '', sort values %dyad2;                           # Record characters comprising the dyad 2 alphabet as a string
  printDyad2 \%dyad2; exit;
# say STDERR dump($Tables->dyad2Alpha); exit;

  my $t = $Tables->alphabetsOrdered;
  $Tables->alphabetsOrdered = {$t ? %$t : (), dyad2=>$a};

 }

sub alphabets                                                                   # Locate the mathematical alphabets
 {my @s = readFile $data;

  my %alpha;                                                                    # Alphabet names

  for my $s(@s)                                                                 # Select the letters we want
   {my @w = split /;/, $s;

# 1D49C;MATHEMATICAL SCRIPT CAPITAL A;Lu;0;L;<font> 0041;;;;N;;;;;              # Sample input
# 1D72D;MATHEMATICAL BOLD ITALIC CAPITAL THETA SYMBOL;Lu;0;L;<font> 03F4;;;;N;;;;;
# 1D70D;MATHEMATICAL ITALIC SMALL FINAL SIGMA;Ll;0;L;<font> 03C2;;;;N;;;;;

    my ($c, $d, $t) = @w;                                                       # Parse unicode specification
    my $C = convert $c;                                                         # Character

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

  my %selected = (semiColon => $Tables->semiColon);                             # We cannot use semi colon as it is an ascii character, so we use this character instead  U+27E2

  for my $a(sort keys %alpha)
   {next unless $a =~ m((CIRCLED LATIN LETTER|MATHEMATICAL BOLD|MATHEMATICAL BOLD FRAKTUR|MATHEMATICAL BOLD ITALIC|MATHEMATICAL BOLD SCRIPT|MATHEMATICAL DOUBLE-STRUCK|MATHEMATICAL FRAKTUR|MATHEMATICAL ITALIC|MATHEMATICAL MONOSPACE|MATHEMATICAL SANS-SERIF|MATHEMATICAL SANS-SERIF BOLD|MATHEMATICAL SANS-SERIF|BOLD ITALIC|MATHEMATICAL SANS-SERIF ITALIC|MATHEMATICAL SCRIPT|NEGATIVE|CIRCLED LATIN LETTER|NEGATIVE SQUARED LATIN LETTER|SQUARED LATIN LETTER|PLANCK))i;
                                                                                # Selected alphabets
    my @l;
    for my $l(sort keys $alpha{$a}->%*)                                         # Sort alphabet by point
     {push @l, $alpha{$a}{$l};
     }
    my $l = join '', sort @l;                                                   # Alphabet
    next unless length($l) > 5 or $l eq "\x{210e}";                             # Ignore short sets which are probably not alphabets except for Plancks constant
    my $A = lcfirst join '', map {ucfirst} split /\s+/, lc $a;
    $selected{$A} = $l;                                                         # Selected alphabets
   }

  #lll "AAAA", dump(\%selected); exit;                                          # Alphabets discovered

  my @range;  my @zmm;                                                          # Ranges of characters

  for my $a(sort keys %selected)                                                # Print selected alphabets in ranges
   {my $z = '';
       $z = q(variable) if $a =~ m/mathematicalSans-serifBold\Z/;
       $z = q(dyad)     if $a =~ m/mathematicalBold\Z/;
       $z = q(prefix)   if $a =~ m/mathematicalBoldItalic\Z/;
       $z = q(assign)   if $a =~ m/mathematicalItalic\Z/;
       $z = q(assign)   if $a =~ m/planck/;
       $z = q(suffix)   if $a =~ m/mathematicalSans-serifBoldItalic\Z/;
       $z = q(Ascii)    if $a =~ m/negativeCircledLatinLetter\Z/;               # Control characters as used in regular expressions and quoted strings

    push $Tables->lexicalAlpha->{$z}->@*, $a;                                   # Alphabets assigned to each lexical item

    my $Z = $z ? pad(" = $z", 16) : '';
    if ($z)                                                                     # Alphabet we are going to use for a lexical item
     {say STDERR '-' x 44;
      say STDERR pad("$a$Z", 42), " : ", $selected{$a};
      say STDERR '-' x 44;
     }
    else
     {say STDERR pad("$a$Z", 42), " : ", $selected{$a};
     }

    my @c = split //, $selected{$a};                                            # Divide selected alphabets into contiguous ranges
    push my @r, [shift @c];

    for my $c(@c)
     {my $b = ord($r[-1][-1]);
      if (ord($c) == $b + ($b == 0x1d454 ? 2 : 1))
       {push $r[-1]->@*, $c;
       }
      else
       {push @r, [$c];
       }
     }

    if ($z)                                                                     # Write ranges ready to load into zmm registers
     {for my $i(keys @r)
       {my $r = $r[$i];
        my $j = $i + 1;
        my $s = ord($$r[0]);                                                    # Start of range
        my $l = ord($$r[-1]);                                                   # End of range
        say STDERR "Range $j: ",
          sprintf("0x%x to 0x%x length: %2d", $s, $l, $l - $s + 1);
        push @range, [$z,  $s, $l];
        push @zmm,   [$z, $$Lexicals{$z}->number, $s, $l];
       }
     }
   }

  if (1)                                                                        # Load special ranges
   {my $s = ord $Tables->semiColon;
    my $t = ord $Tables->separator;
    my %l = map {$_ => $Lexicals->{$_}->number}  keys $Lexicals->%*;            # Ennumerate lexical items
    my $nl = ord("\n");

#               0               1                              2    3
#   push @zmm, ["NewLine",      $l{NewLine},                   $nl, $nl];       # New lines are being handled after lexical pass
    push @zmm, ["Ascii",        $l{Ascii},                     0,   127];
    push @zmm, ["semiColon",    $Lexicals->semiColon->number,  $s,  $s];
#   push @zmm, ["WhiteSpace",   $Lexicals->WhiteSpace->number, $t,  $t];        # White space is being handled after the lexical pass
    @zmm = sort {$$a[3] <=> $$b[3]} @zmm;
   }

  $Tables->alphabetRanges = scalar(@zmm);                                       # Alphabet ranges
  lll "Alphabet Ranges: ",  scalar(@zmm);
  say STDERR formatTable(\@zmm, [qw(Alphabet Lex Start End)]);

  if (1)                                                                        # Write zmm load sequence
   {my @l; my @h; my %r;                                                        # Low, high, current start within range
    for my $r(@zmm)
     {my $l = $r{$$r[0]}//0;                                                    # Current start of range

      push @l, (($$r[1]<<24) + $$r[2]);                                         # Start of range in high and lexical item in low at byte 3 allows us to replace the utf32 code with XX....YY where XX is the lexical item type and YY is the position in the range of that lexical item freeing the two central bytes for other purposes.
      push @h, (($l    <<24) + $$r[3]);
      $r{$$r[0]} += ($$r[3] - $$r[2]) + 1;                                      # Extend the base of the current range
     }

    push @l, 0 while @l < 16;                                                   # Clear remaining ranges
    push @h, 0 while @h < 16;
    my $l = join ', ', map {sprintf("0x%08x", $_)} @l;                          # Format zmm load sequence
    my $h = join ', ', map {sprintf("0x%08x", $_)} @h;
    say STDERR "Lexical Low / Lexical High:\n$l\n$h";
    $Tables->lexicalLow  = [@l];
    $Tables->lexicalHigh = [@h];
   }

  $Tables->alphabets = \%selected;

  my %a;                                                                        # Each alphabet in character order by name
  for my $z(@zmm)
   {my ($name, $lex, $start, $end) = @$z;                                       # Current range
    push $a{$name}->@*, $start..$end;
   }

  my $t = $Tables->alphabetsOrdered;
  $Tables->alphabetsOrdered = {$t ? %$t : (), %a};
 }

sub brackets                                                                    # Write brackets
 {my @S;

  my @s = readFile $data;

  for my $s(@s)                                                                 # Select the brackets we want
   {next unless $s =~ m(;P[s|e];)i;                                             # Select brackets
    my @w = split m/;/, $s;

    my ($point, $name) = @w;
    my $u = eval "0x$point";
    $@ and confess "$s\n$@\n";

    next if $u <= 0x208e;
    next if $u >=  9121 and  $u <=  9137;
    next if $u >= 11778 and  $u <= 11815;
    next if $u >= 12300 and  $u <= 12303;
    next if $u >= 65047 and  $u <= 65118 ;
    next if $u >= 65378;

    next if $u >= 0x27C5 and $u <= 0x27C6;                                      # Bag
    next if $u >= 0x29D8 and $u <= 0x29D9;                                      # Wiggly fence
    next if $u >= 0x29DA and $u <= 0x29Db;                                      # Double Wiggly fence
    next if $u == 0x2E42;                                                       # Double Low-Reversed-9 Quotation Mark[1]
    next if $u >= 0x301D and $u <= 0x3020;                                      # Quotation marks

    push @S, [$u, $name, $s];
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
  my %semi; my %possible;                                                          # Pairs between which we could usefully insert a semi colon
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

  my %alphabets;                                                                # Alphabets for each lexical

  for my $l(keys $TreeTermLexicals->%*)
   {my $m = $TreeTermLexicals->{$l}{short};
    my $n = $Tables->lexicalAlpha->{$m}[0];
    next unless $n;
    my $a = $Tables->alphabets->{$n};
    next unless $a;
    $alphabets{$l} = [$n, $a];
   }

  $alphabets{e} = ["dyad2", join '', map {chr $_} $Tables->dyad2Chars->@*];     # Alphabet for dyads 2

  my $T = '';                                                                   # Translated text as characters
  my $normal = join '', 'A'..'Z', 'a'..'z';                                     # The alphabet we can write lexical items

  my sub translate($)                                                           # Translate a string written in normal into the indicated alphabet
   {my ($lexical) = @_;                                                         # Lexical item to translate
    my $a =  $alphabets{substr($lexical, 0, 1)};                                # Alphabet to translate to
    my @a =   split //, $$a[1];                                                 # Alphabet to translate to

    for my $c(split //, substr($lexical, 1))
     {my $i = index $normal, $c;                                                # The long struggle for mathematical italic h as used in physics.
      if ($$a[0] =~ m(\AmathematicalItalic\Z))
       {if ($c eq 'h')
         {$T .= "\x{210e}";
         }
        elsif ($c lt 'h')
         {$T .= $a[$i];
         }
        else
         {$T .= $a[$i-1];
         }
       }
      else
       {$T .= $a[$i];
       }
     }
   }

  for my $w(split /\s+/, $string)                                               # Translate to text
   {if    ($w =~ m(\A(a|d|e|p|q|v))) {translate $w}
    elsif ($w =~ m(\As)) {$T .= $Tables->alphabets->{semiColon}}
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
    elsif ($w =~ m(\AS)) {push @L, ($n{Ascii} << 24) + ord(' ')}
    elsif ($w =~ m(\AN)) {push @L, ($n{Ascii} << 24) + ord("\n")}
    elsif ($w =~ m(\AA)) {push @L, ($n{Ascii} << 24) + ord('A')}
   }
  say STDERR '-' x 32;
  say STDERR $title;
  say STDERR "Sample text length in chars   :", sprintf("0x%x", length($T));
  say STDERR "Sample text length in lexicals:", scalar(@L);

  if (0)                                                                        # Print source code as utf8
   {my @T = split //, $T;
    for my $i(keys @T)
     {my $c = $T[$i];
      say STDERR "$i   $c ", sprintf("%08x   %08x", ord($c), convertUtf32ToUtf8(ord($c)));
     }
   }

  say STDERR "Sample text    :\n$T";
  say STDERR "Sample lexicals:\n", dump(\@L);
  $Tables->sampleText    ->{$title} = $T;                                       # Save sample text
  $Tables->sampleLexicals->{$title} = [map {$_ < 16 ? $_<<24 : $_} @L];         # Boost lexical elements not already boosted
 }

alphabets;                                                                      # Locate alphabets
dyad2;                                                                          # Dyadic operators at priority 4 that is one more urgent than dyads
brackets;                                                                       # Locate brackets
tripleTerms;                                                                    # All invalid transitions that could usefully interpret one intervening new line as a semi colon


lll "Alphabets Ordered:\n", dump($Tables->alphabetsOrdered);


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

translateSomeText 'A', <<END;
vaa aequals Aabc S A123  S S S S
END

translateSomeText 'Adv', <<END;
vaa aequals Aabc S A123  S S S S dplus vvar
END

translateSomeText 'BB', <<END;
b1 b2 b3 b4 b5 b6 b7 b8 va B8 B7 B6 B5 B4 B3 B2 B1
END

translateSomeText 'ppppvdvdvqqqq', <<END;
pa b9 pb b10 pc b11 va aequals pd vb qd dtimes b12 vc dplus vd B12 s ve aassign vf dsub vg  qh B11 qc B10  qb B9 qa
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
