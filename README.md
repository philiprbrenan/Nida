# Unisyn expressions.

![Test](https://github.com/philiprbrenan/UnisynParse/workflows/Test/badge.svg)

Once there were many different character sets that were unified by [Unicode](https://en.wikipedia.org/wiki/Unicode). 
Today we have many different programming languages, each with a slightly
different syntax from all the others. The multiplicity of such syntaxes imposes
unnecessary burdens on users and language designers.  [UniSyn](https://github.com/philiprbrenan/UnisynParse) is proposed as a
common syntax that is easy to understand yet general enough to be used by many
different programming languages.

## The advantages of having one uniform language syntax:

- less of a burden on users to recall which of the many syntax schemes in
current use is the relevant one for the programming language they are currently
programming in.  Rather like having all your electrical appliances work from
the same voltage electricity rather than different voltages.

- programming effort can be applied globally to optimize the parsing [process](https://en.wikipedia.org/wiki/Process_management_(computing)) to
produce the fastest possible parser with the best diagnostics.

## Special features

- Expressions in Unisyn can be parsed in situ - it is not necessary to reparse
the entire source [file](https://en.wikipedia.org/wiki/Computer_file) to syntax check changes made to the [file](https://en.wikipedia.org/wiki/Computer_file). Instead
changes can be checked locally at the point of modification which should make
writing a syntax checking editor for Unisyn easier.

- Expressions in [UniSyn](https://github.com/philiprbrenan/UnisynParse) can be parsed using [SIMD](https://www.officedaytime.com/simd512e/) instructions to make parsing
faster than otherwise.

## Dyadic operator priorities
 [UniSyn](https://github.com/philiprbrenan/UnisynParse) has only four levels of dyadic operator priority which makes it easier
to learn. Conversely: [Perl](http://www.perl.org/) has 25 levels of operator priority.  Can we really
expect users to learn such a long list?

```
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
```

The priority of a dyadic operator is determined by the [Unicode Mathematical Alphanumeric Symbols](https://en.wikipedia.org/wiki/Mathematical_Alphanumeric_Symbols) that is used to
encode it.

The new operators provided by the [Unicode](https://en.wikipedia.org/wiki/Unicode) standard allows us to offer users a
wider range of operators and brackets with which to express their intentions
clearly within the three levels of operator precedence provided.

## Lexical elements

### Ascii.

Printable ASCII characters not including space, [tab](https://en.wikipedia.org/wiki/Tab_key) or new line.

Contains: 146 characters.


 |  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
 | 0 | ! | " | # | $ | % | & | ' | ( | ) | * | + | , |  | . | / | 0 |
 | 1 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | : | ; | < | = | > | ? | @ |
 | 2 | A | B | C | D | E | F | G | H | I | J | K | L | M | N | O | P |
 | 3 | Q | R | S | T | U | V | W | X | Y | Z | [ | \ | ] | ^ | _ |  |
 | 4 | a | b | c | d | e | f | g | h | i | j | k | l | m | n | o | p |
 | 5 | q | r | s | t | u | v | w | x | y | z | { |  | } | ~ | Ⓐ | Ⓑ |
 | 6 | Ⓒ | Ⓓ | Ⓔ | Ⓕ | Ⓖ | Ⓗ | Ⓘ | Ⓙ | Ⓚ | Ⓛ | Ⓜ | Ⓝ | Ⓞ | Ⓟ | Ⓠ | Ⓡ |
 | 7 | Ⓢ | Ⓣ | Ⓤ | Ⓥ | Ⓦ | Ⓧ | Ⓨ | Ⓩ | ⓐ | ⓑ | ⓒ | ⓓ | ⓔ | ⓕ | ⓖ | ⓗ |
 | 8 | ⓘ | ⓙ | ⓚ | ⓛ | ⓜ | ⓝ | ⓞ | ⓟ | ⓠ | ⓡ | ⓢ | ⓣ | ⓤ | ⓥ | ⓦ | ⓧ |
 | 9 | ⓨ | ⓩ |


### Assign.

Assign [infix](https://en.wikipedia.org/wiki/Infix_notation) operator with right to left binding at priority 2.

Contains: 221 characters.


 |  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
 | 0 | ℎ | ← | ↑ | → | ↓ | ↔ | ↕ | ↖ | ↗ | ↘ | ↙ | ↚ | ↛ | ↜ | ↝ | ↞ |
 | 1 | ↟ | ↠ | ↡ | ↢ | ↣ | ↤ | ↥ | ↦ | ↧ | ↨ | ↩ | ↪ | ↫ | ↬ | ↭ | ↮ |
 | 2 | ↯ | ↰ | ↱ | ↲ | ↳ | ↴ | ↵ | ↶ | ↷ | ↸ | ↹ | ↺ | ↻ | ↼ | ↽ | ↾ |
 | 3 | ↿ | ⇀ | ⇁ | ⇂ | ⇃ | ⇄ | ⇅ | ⇆ | ⇇ | ⇈ | ⇉ | ⇊ | ⇋ | ⇌ | ⇍ | ⇎ |
 | 4 | ⇏ | ⇐ | ⇑ | ⇒ | ⇓ | ⇔ | ⇕ | ⇖ | ⇗ | ⇘ | ⇙ | ⇚ | ⇛ | ⇜ | ⇝ | ⇞ |
 | 5 | ⇟ | ⇠ | ⇡ | ⇢ | ⇣ | ⇤ | ⇥ | ⇦ | ⇧ | ⇨ | ⇩ | ⇪ | ⇫ | ⇬ | ⇭ | ⇮ |
 | 6 | ⇯ | ⇰ | ⇱ | ⇲ | ⇳ | ⇴ | ⇵ | ⇶ | ⇷ | ⇸ | ⇹ | ⇺ | ⇻ | ⇼ | ⇽ | ⇾ |
 | 7 | 𝐴 | 𝐵 | 𝐶 | 𝐷 | 𝐸 | 𝐹 | 𝐺 | 𝐻 | 𝐼 | 𝐽 | 𝐾 | 𝐿 | 𝑀 | 𝑁 | 𝑂 | 𝑃 |
 | 8 | 𝑄 | 𝑅 | 𝑆 | 𝑇 | 𝑈 | 𝑉 | 𝑊 | 𝑋 | 𝑌 | 𝑍 | 𝑎 | 𝑏 | 𝑐 | 𝑑 | 𝑒 | 𝑓 |
 | 9 | 𝑔 | 𝑖 | 𝑗 | 𝑘 | 𝑙 | 𝑚 | 𝑛 | 𝑜 | 𝑝 | 𝑞 | 𝑟 | 𝑠 | 𝑡 | 𝑢 | 𝑣 | 𝑤 |
 | a | 𝑥 | 𝑦 | 𝑧 | 𝛢 | 𝛣 | 𝛤 | 𝛥 | 𝛦 | 𝛧 | 𝛨 | 𝛩 | 𝛪 | 𝛫 | 𝛬 | 𝛭 | 𝛮 |
 | b | 𝛯 | 𝛰 | 𝛱 | 𝛲 | 𝛳 | 𝛴 | 𝛵 | 𝛶 | 𝛷 | 𝛸 | 𝛹 | 𝛺 | 𝛻 | 𝛼 | 𝛽 | 𝛾 |
 | c | 𝛿 | 𝜀 | 𝜁 | 𝜂 | 𝜃 | 𝜄 | 𝜅 | 𝜆 | 𝜇 | 𝜈 | 𝜉 | 𝜊 | 𝜋 | 𝜌 | 𝜍 | 𝜎 |
 | d | 𝜏 | 𝜐 | 𝜑 | 𝜒 | 𝜓 | 𝜔 | 𝜕 | 𝜖 | 𝜗 | 𝜘 | 𝜙 | 𝜚 | 𝜛 |


### Dyad.

Infix operator with left to right binding at priority 3.

Contains: 110 characters.


 |  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
 | 0 | 𝐀 | 𝐁 | 𝐂 | 𝐃 | 𝐄 | 𝐅 | 𝐆 | 𝐇 | 𝐈 | 𝐉 | 𝐊 | 𝐋 | 𝐌 | 𝐍 | 𝐎 | 𝐏 |
 | 1 | 𝐐 | 𝐑 | 𝐒 | 𝐓 | 𝐔 | 𝐕 | 𝐖 | 𝐗 | 𝐘 | 𝐙 | 𝐚 | 𝐛 | 𝐜 | 𝐝 | 𝐞 | 𝐟 |
 | 2 | 𝐠 | 𝐡 | 𝐢 | 𝐣 | 𝐤 | 𝐥 | 𝐦 | 𝐧 | 𝐨 | 𝐩 | 𝐪 | 𝐫 | 𝐬 | 𝐭 | 𝐮 | 𝐯 |
 | 3 | 𝐰 | 𝐱 | 𝐲 | 𝐳 | 𝚨 | 𝚩 | 𝚪 | 𝚫 | 𝚬 | 𝚭 | 𝚮 | 𝚯 | 𝚰 | 𝚱 | 𝚲 | 𝚳 |
 | 4 | 𝚴 | 𝚵 | 𝚶 | 𝚷 | 𝚸 | 𝚹 | 𝚺 | 𝚻 | 𝚼 | 𝚽 | 𝚾 | 𝚿 | 𝛀 | 𝛁 | 𝛂 | 𝛃 |
 | 5 | 𝛄 | 𝛅 | 𝛆 | 𝛇 | 𝛈 | 𝛉 | 𝛊 | 𝛋 | 𝛌 | 𝛍 | 𝛎 | 𝛏 | 𝛐 | 𝛑 | 𝛒 | 𝛓 |
 | 6 | 𝛔 | 𝛕 | 𝛖 | 𝛗 | 𝛘 | 𝛙 | 𝛚 | 𝛛 | 𝛜 | 𝛝 | 𝛞 | 𝛟 | 𝛠 | 𝛡 |


### Dyad2.

Infix operator with left to right binding at priority 4.

Contains: 1907 characters.


 |  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
 | 0 | ϶ | ⟀ | ⟁ | ⟂ | ⟃ | ⟄ | ⟅ | ⟆ | ⟇ | ⟈ | ⟉ | ⟊ | ⟋ | ⟌ | ⟍ | ⟎ |
 | 1 | ⟏ | ⟐ | ⟑ | ⟒ | ⟓ | ⟔ | ⟕ | ⟖ | ⟗ | ⟘ | ⟙ | ⟚ | ⟛ | ⟜ | ⟝ | ⟞ |
 | 2 | ⟟ | ⟠ | ⟡ | ⟣ | ⟤ | ⟥ | ⟰ | ⟱ | ⟲ | ⟳ | ⟴ | ⟵ | ⟶ | ⟷ | ⟸ | ⟹ |
 | 3 | ⟺ | ⟻ | ⟼ | ⟽ | ⟾ | ⟿ | ⠀ | ⠁ | ⠂ | ⠃ | ⠄ | ⠅ | ⠆ | ⠇ | ⠈ | ⠉ |
 | 4 | ⠊ | ⠋ | ⠌ | ⠍ | ⠎ | ⠏ | ⠐ | ⠑ | ⠒ | ⠓ | ⠔ | ⠕ | ⠖ | ⠗ | ⠘ | ⠙ |
 | 5 | ⠚ | ⠛ | ⠜ | ⠝ | ⠞ | ⠟ | ⠠ | ⠡ | ⠢ | ⠣ | ⠤ | ⠥ | ⠦ | ⠧ | ⠨ | ⠩ |
 | 6 | ⠪ | ⠫ | ⠬ | ⠭ | ⠮ | ⠯ | ⠰ | ⠱ | ⠲ | ⠳ | ⠴ | ⠵ | ⠶ | ⠷ | ⠸ | ⠹ |
 | 7 | ⠺ | ⠻ | ⠼ | ⠽ | ⠾ | ⠿ | ⡀ | ⡁ | ⡂ | ⡃ | ⡄ | ⡅ | ⡆ | ⡇ | ⡈ | ⡉ |
 | 8 | ⡊ | ⡋ | ⡌ | ⡍ | ⡎ | ⡏ | ⡐ | ⡑ | ⡒ | ⡓ | ⡔ | ⡕ | ⡖ | ⡗ | ⡘ | ⡙ |
 | 9 | ⡚ | ⡛ | ⡜ | ⡝ | ⡞ | ⡟ | ⡠ | ⡡ | ⡢ | ⡣ | ⡤ | ⡥ | ⡦ | ⡧ | ⡨ | ⡩ |
 | a | ⡪ | ⡫ | ⡬ | ⡭ | ⡮ | ⡯ | ⡰ | ⡱ | ⡲ | ⡳ | ⡴ | ⡵ | ⡶ | ⡷ | ⡸ | ⡹ |
 | b | ⡺ | ⡻ | ⡼ | ⡽ | ⡾ | ⡿ | ⢀ | ⢁ | ⢂ | ⢃ | ⢄ | ⢅ | ⢆ | ⢇ | ⢈ | ⢉ |
 | c | ⢊ | ⢋ | ⢌ | ⢍ | ⢎ | ⢏ | ⢐ | ⢑ | ⢒ | ⢓ | ⢔ | ⢕ | ⢖ | ⢗ | ⢘ | ⢙ |
 | d | ⢚ | ⢛ | ⢜ | ⢝ | ⢞ | ⢟ | ⢠ | ⢡ | ⢢ | ⢣ | ⢤ | ⢥ | ⢦ | ⢧ | ⢨ | ⢩ |
 | e | ⢪ | ⢫ | ⢬ | ⢭ | ⢮ | ⢯ | ⢰ | ⢱ | ⢲ | ⢳ | ⢴ | ⢵ | ⢶ | ⢷ | ⢸ | ⢹ |
 | f | ⢺ | ⢻ | ⢼ | ⢽ | ⢾ | ⢿ | ⣀ | ⣁ | ⣂ | ⣃ | ⣄ | ⣅ | ⣆ | ⣇ | ⣈ | ⣉ |
 | 10 | ⣊ | ⣋ | ⣌ | ⣍ | ⣎ | ⣏ | ⣐ | ⣑ | ⣒ | ⣓ | ⣔ | ⣕ | ⣖ | ⣗ | ⣘ | ⣙ |
 | 11 | ⣚ | ⣛ | ⣜ | ⣝ | ⣞ | ⣟ | ⣠ | ⣡ | ⣢ | ⣣ | ⣤ | ⣥ | ⣦ | ⣧ | ⣨ | ⣩ |
 | 12 | ⣪ | ⣫ | ⣬ | ⣭ | ⣮ | ⣯ | ⣰ | ⣱ | ⣲ | ⣳ | ⣴ | ⣵ | ⣶ | ⣷ | ⣸ | ⣹ |
 | 13 | ⣺ | ⣻ | ⣼ | ⣽ | ⣾ | ⣿ | ⤀ | ⤁ | ⤂ | ⤃ | ⤄ | ⤅ | ⤆ | ⤇ | ⤈ | ⤉ |
 | 14 | ⤊ | ⤋ | ⤌ | ⤍ | ⤎ | ⤏ | ⤐ | ⤑ | ⤒ | ⤓ | ⤔ | ⤕ | ⤖ | ⤗ | ⤘ | ⤙ |
 | 15 | ⤚ | ⤛ | ⤜ | ⤝ | ⤞ | ⤟ | ⤠ | ⤡ | ⤢ | ⤣ | ⤤ | ⤥ | ⤦ | ⤧ | ⤨ | ⤩ |
 | 16 | ⤪ | ⤫ | ⤬ | ⤭ | ⤮ | ⤯ | ⤰ | ⤱ | ⤲ | ⤳ | ⤴ | ⤵ | ⤶ | ⤷ | ⤸ | ⤹ |
 | 17 | ⤺ | ⤻ | ⤼ | ⤽ | ⤾ | ⤿ | ⥀ | ⥁ | ⥂ | ⥃ | ⥄ | ⥅ | ⥆ | ⥇ | ⥈ | ⥉ |
 | 18 | ⥊ | ⥋ | ⥌ | ⥍ | ⥎ | ⥏ | ⥐ | ⥑ | ⥒ | ⥓ | ⥔ | ⥕ | ⥖ | ⥗ | ⥘ | ⥙ |
 | 19 | ⥚ | ⥛ | ⥜ | ⥝ | ⥞ | ⥟ | ⥠ | ⥡ | ⥢ | ⥣ | ⥤ | ⥥ | ⥦ | ⥧ | ⥨ | ⥩ |
 | 1a | ⥪ | ⥫ | ⥬ | ⥭ | ⥮ | ⥯ | ⥰ | ⥱ | ⥲ | ⥳ | ⥴ | ⥵ | ⥶ | ⥷ | ⥸ | ⥹ |
 | 1b | ⥺ | ⥻ | ⥼ | ⥽ | ⥾ | ⥿ | ⦀ | ⦁ | ⦂ | ⦙ | ⦚ | ⦛ | ⦜ | ⦝ | ⦞ | ⦟ |
 | 1c | ⦠ | ⦡ | ⦢ | ⦣ | ⦤ | ⦥ | ⦦ | ⦧ | ⦨ | ⦩ | ⦪ | ⦫ | ⦬ | ⦭ | ⦮ | ⦯ |
 | 1d | ⦰ | ⦱ | ⦲ | ⦳ | ⦴ | ⦵ | ⦶ | ⦷ | ⦸ | ⦹ | ⦺ | ⦻ | ⦼ | ⦽ | ⦾ | ⦿ |
 | 1e | ⧀ | ⧁ | ⧂ | ⧃ | ⧄ | ⧅ | ⧆ | ⧇ | ⧈ | ⧉ | ⧊ | ⧋ | ⧌ | ⧍ | ⧎ | ⧏ |
 | 1f | ⧐ | ⧑ | ⧒ | ⧓ | ⧔ | ⧕ | ⧖ | ⧗ | ⧘ | ⧙ | ⧚ | ⧛ | ⧜ | ⧝ | ⧞ | ⧟ |
 | 20 | ⧠ | ⧡ | ⧢ | ⧣ | ⧤ | ⧥ | ⧦ | ⧧ | ⧨ | ⧩ | ⧪ | ⧫ | ⧬ | ⧭ | ⧮ | ⧯ |
 | 21 | ⧰ | ⧱ | ⧲ | ⧳ | ⧴ | ⧵ | ⧶ | ⧷ | ⧸ | ⧹ | ⧺ | ⧻ | ⧾ | ⧿ | ⨀ | ⨁ |
 | 22 | ⨂ | ⨃ | ⨄ | ⨅ | ⨆ | ⨇ | ⨈ | ⨉ | ⨊ | ⨋ | ⨌ | ⨍ | ⨎ | ⨏ | ⨐ | ⨑ |
 | 23 | ⨒ | ⨓ | ⨔ | ⨕ | ⨖ | ⨗ | ⨘ | ⨙ | ⨚ | ⨛ | ⨜ | ⨝ | ⨞ | ⨟ | ⨠ | ⨡ |
 | 24 | ⨢ | ⨣ | ⨤ | ⨥ | ⨦ | ⨧ | ⨨ | ⨩ | ⨪ | ⨫ | ⨬ | ⨭ | ⨮ | ⨯ | ⨰ | ⨱ |
 | 25 | ⨲ | ⨳ | ⨴ | ⨵ | ⨶ | ⨷ | ⨸ | ⨹ | ⨺ | ⨻ | ⨼ | ⨽ | ⨾ | ⨿ | ⩀ | ⩁ |
 | 26 | ⩂ | ⩃ | ⩄ | ⩅ | ⩆ | ⩇ | ⩈ | ⩉ | ⩊ | ⩋ | ⩌ | ⩍ | ⩎ | ⩏ | ⩐ | ⩑ |
 | 27 | ⩒ | ⩓ | ⩔ | ⩕ | ⩖ | ⩗ | ⩘ | ⩙ | ⩚ | ⩛ | ⩜ | ⩝ | ⩞ | ⩟ | ⩠ | ⩡ |
 | 28 | ⩢ | ⩣ | ⩤ | ⩥ | ⩦ | ⩧ | ⩨ | ⩩ | ⩪ | ⩫ | ⩬ | ⩭ | ⩮ | ⩯ | ⩰ | ⩱ |
 | 29 | ⩲ | ⩳ | ⩴ | ⩵ | ⩶ | ⩷ | ⩸ | ⩹ | ⩺ | ⩻ | ⩼ | ⩽ | ⩾ | ⩿ | ⪀ | ⪁ |
 | 2a | ⪂ | ⪃ | ⪄ | ⪅ | ⪆ | ⪇ | ⪈ | ⪉ | ⪊ | ⪋ | ⪌ | ⪍ | ⪎ | ⪏ | ⪐ | ⪑ |
 | 2b | ⪒ | ⪓ | ⪔ | ⪕ | ⪖ | ⪗ | ⪘ | ⪙ | ⪚ | ⪛ | ⪜ | ⪝ | ⪞ | ⪟ | ⪠ | ⪡ |
 | 2c | ⪢ | ⪣ | ⪤ | ⪥ | ⪦ | ⪧ | ⪨ | ⪩ | ⪪ | ⪫ | ⪬ | ⪭ | ⪮ | ⪯ | ⪰ | ⪱ |
 | 2d | ⪲ | ⪳ | ⪴ | ⪵ | ⪶ | ⪷ | ⪸ | ⪹ | ⪺ | ⪻ | ⪼ | ⪽ | ⪾ | ⪿ | ⫀ | ⫁ |
 | 2e | ⫂ | ⫃ | ⫄ | ⫅ | ⫆ | ⫇ | ⫈ | ⫉ | ⫊ | ⫋ | ⫌ | ⫍ | ⫎ | ⫏ | ⫐ | ⫑ |
 | 2f | ⫒ | ⫓ | ⫔ | ⫕ | ⫖ | ⫗ | ⫘ | ⫙ | ⫚ | ⫛ | ⫝̸ | ⫝ | ⫞ | ⫟ | ⫠ | ⫡ |
 | 30 | ⫢ | ⫣ | ⫤ | ⫥ | ⫦ | ⫧ | ⫨ | ⫩ | ⫪ | ⫫ | ⫬ | ⫭ | ⫮ | ⫯ | ⫰ | ⫱ |
 | 31 | ⫲ | ⫳ | ⫴ | ⫵ | ⫶ | ⫷ | ⫸ | ⫹ | ⫺ | ⫻ | ⫼ | ⫽ | ⫾ | ⫿ | ⬀ | ⬁ |
 | 32 | ⬂ | ⬃ | ⬄ | ⬅ | ⬆ | ⬇ | ⬈ | ⬉ | ⬊ | ⬋ | ⬌ | ⬍ | ⬎ | ⬏ | ⬐ | ⬑ |
 | 33 | ⬒ | ⬓ | ⬔ | ⬕ | ⬖ | ⬗ | ⬘ | ⬙ | ⬚ | ⬛ | ⬜ | ⬝ | ⬞ | ⬟ | ⬠ | ⬡ |
 | 34 | ⬢ | ⬣ | ⬤ | ⬥ | ⬦ | ⬧ | ⬨ | ⬩ | ⬪ | ⬫ | ⬬ | ⬭ | ⬮ | ⬯ | ⬰ | ⬱ |
 | 35 | ⬲ | ⬳ | ⬴ | ⬵ | ⬶ | ⬷ | ⬸ | ⬹ | ⬺ | ⬻ | ⬼ | ⬽ | ⬾ | ⬿ | ⭀ | ⭁ |
 | 36 | ⭂ | ⭃ | ⭄ | ⭅ | ⭆ | ⭇ | ⭈ | ⭉ | ⭊ | ⭋ | ⭌ | ⭍ | ⭎ | ⭏ | ⭐ | ⭑ |
 | 37 | ⭒ | ⭓ | ⭔ | ⭕ | ⭖ | ⭗ | ⭘ | ⸀ | ⸁ | ⸂ | ⸃ | ⸄ | ⸅ | ⸆ | ⸇ | ⸈ |
 | 38 | ⸉ | ⸊ | ⸋ | ⸌ | ⸍ | ⸎ | ⸏ | ⸐ | ⸑ | ⸒ | ⸓ | ⸔ | ⸕ | ⸖ | ⸗ | ⸘ |
 | 39 | ⸙ | ⸚ | ⸛ | ⸜ | ⸝ | ⸞ | ⸟ | ⸪ | ⸫ | ⸬ | ⸭ | ⸮ | ⸯ | ⸰ | 𞻰 | 𞻱 |
 | 3a | ؆ | ؇ | ؈ | ¬ | ± | × | ÷ | ﬩ | ﹢ | ﹤ | ﹥ | ﹦ | ＋ | ＜ | ＝ | ＞ |
 | 3b | ｜ | ～ | ￢ | ​ | ‌ | ‍ | ‎ | ‏ | ‐ | ‑ | ‒ | – | — | ― | ‖ | ‗ |
 | 3c | ‘ | ’ | ‚ | ‛ | “ | ” | „ | ‟ | † | ‡ | • | ‣ | ․ | ‥ | … | ‧ |
 | 3d |   |   | ‪ | ‫ | ‬ | ‭ | ‮ |   | ‰ | ‱ | ′ | ″ | ‴ | ‵ | ‶ | ‷ |
 | 3e | ‸ | ‹ | › | ※ | ‼ | ‽ | ‾ | ‿ | ⁀ | ⁁ | ⁂ | ⁃ | ⁄ | ⁇ | ⁈ | ⁉ |
 | 3f | ⁊ | ⁋ | ⁌ | ⁍ | ⁎ | ⁏ | ⁐ | ⁑ | ⁒ | ⁓ | ⁔ | ⁕ | ⁖ | ⁗ | ⁘ | ⁙ |
 | 40 | ⁚ | ⁛ | ⁜ | ⁝ | ⁞ |   | ⁠ | ⁡ | ⁥ | ⁦ | ⁧ | ⁨ | ⁩ | ⁺ | ⁻ | ⁼ |
 | 41 | ₊ | ₋ | ₌ | ℘ | ⅀ | ⅁ | ⅂ | ⅃ | ⅄ | ⅋ | ∀ | ∁ | ∂ | ∃ | ∄ | ∅ |
 | 42 | ∆ | ∇ | ∈ | ∉ | ∊ | ∋ | ∌ | ∍ | ∎ | ∏ | ∐ | ∑ | − | ∓ | ∔ | ∕ |
 | 43 | ∖ | ∗ | ∘ | ∙ | √ | ∛ | ∜ | ∝ | ∞ | ∟ | ∠ | ∡ | ∢ | ∣ | ∤ | ∥ |
 | 44 | ∦ | ∧ | ∨ | ∩ | ∪ | ∫ | ∬ | ∭ | ∮ | ∯ | ∰ | ∱ | ∲ | ∳ | ∴ | ∵ |
 | 45 | ∶ | ∷ | ∸ | ∹ | ∺ | ∻ | ∼ | ∽ | ∾ | ∿ | ≀ | ≁ | ≂ | ≃ | ≄ | ≅ |
 | 46 | ≆ | ≇ | ≈ | ≉ | ≊ | ≋ | ≌ | ≍ | ≎ | ≏ | ≐ | ≑ | ≒ | ≓ | ≔ | ≕ |
 | 47 | ≖ | ≗ | ≘ | ≙ | ≚ | ≛ | ≜ | ≝ | ≞ | ≟ | ≠ | ≡ | ≢ | ≣ | ≤ | ≥ |
 | 48 | ≦ | ≧ | ≨ | ≩ | ≪ | ≫ | ≬ | ≭ | ≮ | ≯ | ≰ | ≱ | ≲ | ≳ | ≴ | ≵ |
 | 49 | ≶ | ≷ | ≸ | ≹ | ≺ | ≻ | ≼ | ≽ | ≾ | ≿ | ⊀ | ⊁ | ⊂ | ⊃ | ⊄ | ⊅ |
 | 4a | ⊆ | ⊇ | ⊈ | ⊉ | ⊊ | ⊋ | ⊌ | ⊍ | ⊎ | ⊏ | ⊐ | ⊑ | ⊒ | ⊓ | ⊔ | ⊕ |
 | 4b | ⊖ | ⊗ | ⊘ | ⊙ | ⊚ | ⊛ | ⊜ | ⊝ | ⊞ | ⊟ | ⊠ | ⊡ | ⊢ | ⊣ | ⊤ | ⊥ |
 | 4c | ⊦ | ⊧ | ⊨ | ⊩ | ⊪ | ⊫ | ⊬ | ⊭ | ⊮ | ⊯ | ⊰ | ⊱ | ⊲ | ⊳ | ⊴ | ⊵ |
 | 4d | ⊶ | ⊷ | ⊸ | ⊹ | ⊺ | ⊻ | ⊼ | ⊽ | ⊾ | ⊿ | ⋀ | ⋁ | ⋂ | ⋃ | ⋄ | ⋅ |
 | 4e | ⋆ | ⋇ | ⋈ | ⋉ | ⋊ | ⋋ | ⋌ | ⋍ | ⋎ | ⋏ | ⋐ | ⋑ | ⋒ | ⋓ | ⋔ | ⋕ |
 | 4f | ⋖ | ⋗ | ⋘ | ⋙ | ⋚ | ⋛ | ⋜ | ⋝ | ⋞ | ⋟ | ⋠ | ⋡ | ⋢ | ⋣ | ⋤ | ⋥ |
 | 50 | ⋦ | ⋧ | ⋨ | ⋩ | ⋪ | ⋫ | ⋬ | ⋭ | ⋮ | ⋯ | ⋰ | ⋱ | ⋲ | ⋳ | ⋴ | ⋵ |
 | 51 | ⋶ | ⋷ | ⋸ | ⋹ | ⋺ | ⋻ | ⋼ | ⋽ | ⋾ | ⋿ | ⌀ | ⌁ | ⌂ | ⌃ | ⌄ | ⌅ |
 | 52 | ⌆ | ⌇ | ⌌ | ⌍ | ⌎ | ⌏ | ⌐ | ⌑ | ⌒ | ⌓ | ⌔ | ⌕ | ⌖ | ⌗ | ⌘ | ⌙ |
 | 53 | ⌚ | ⌛ | ⌜ | ⌝ | ⌞ | ⌟ | ⌠ | ⌡ | ⌢ | ⌣ | ⌤ | ⌥ | ⌦ | ⌧ | ⌨ | ⌬ |
 | 54 | ⌭ | ⌮ | ⌯ | ⌰ | ⌱ | ⌲ | ⌳ | ⌴ | ⌵ | ⌶ | ⌷ | ⌸ | ⌹ | ⌺ | ⌻ | ⌼ |
 | 55 | ⌽ | ⌾ | ⌿ | ⍀ | ⍁ | ⍂ | ⍃ | ⍄ | ⍅ | ⍆ | ⍇ | ⍈ | ⍉ | ⍊ | ⍋ | ⍌ |
 | 56 | ⍍ | ⍎ | ⍏ | ⍐ | ⍑ | ⍒ | ⍓ | ⍔ | ⍕ | ⍖ | ⍗ | ⍘ | ⍙ | ⍚ | ⍛ | ⍜ |
 | 57 | ⍝ | ⍞ | ⍟ | ⍠ | ⍡ | ⍢ | ⍣ | ⍤ | ⍥ | ⍦ | ⍧ | ⍨ | ⍩ | ⍪ | ⍫ | ⍬ |
 | 58 | ⍭ | ⍮ | ⍯ | ⍰ | ⍱ | ⍲ | ⍳ | ⍴ | ⍵ | ⍶ | ⍷ | ⍸ | ⍹ | ⍺ | ⍻ | ⍼ |
 | 59 | ⍽ | ⍾ | ⍿ | ⎀ | ⎁ | ⎂ | ⎃ | ⎄ | ⎅ | ⎆ | ⎇ | ⎈ | ⎉ | ⎊ | ⎋ | ⎌ |
 | 5a | ⎍ | ⎎ | ⎏ | ⎐ | ⎑ | ⎒ | ⎓ | ⎔ | ⎕ | ⎖ | ⎗ | ⎘ | ⎙ | ⎚ | ⎛ | ⎜ |
 | 5b | ⎝ | ⎞ | ⎟ | ⎠ | ⎡ | ⎢ | ⎣ | ⎤ | ⎥ | ⎦ | ⎧ | ⎨ | ⎩ | ⎪ | ⎫ | ⎬ |
 | 5c | ⎭ | ⎮ | ⎯ | ⎰ | ⎱ | ⎲ | ⎳ | ⎴ | ⎵ | ⎶ | ⎷ | ⎸ | ⎹ | ⎺ | ⎻ | ⎼ |
 | 5d | ⎽ | ⎾ | ⎿ | ⏀ | ⏁ | ⏂ | ⏃ | ⏄ | ⏅ | ⏆ | ⏇ | ⏈ | ⏉ | ⏊ | ⏋ | ⏌ |
 | 5e | ⏍ | ⏎ | ⏏ | ⏐ | ⏑ | ⏒ | ⏓ | ⏔ | ⏕ | ⏖ | ⏗ | ⏘ | ⏙ | ⏚ | ⏛ | ⏜ |
 | 5f | ⏝ | ⏞ | ⏟ | ⏠ | ⏡ | ⏢ | ⏣ | ⏤ | ⏥ | ⏦ | ⏧ | ⏨ | ⏩ | ⏪ | ⏫ | ⏬ |
 | 60 | ⏭ | ⏮ | ⏯ | ⏰ | ⏱ | ⏲ | ⏳ | ⏴ | ⏵ | ⏶ | ⏷ | ⏸ | ⏹ | ⏺ | ⏻ | ⏼ |
 | 61 | ⏽ | ⏾ | ⏿ | ■ | □ | ▢ | ▣ | ▤ | ▥ | ▦ | ▧ | ▨ | ▩ | ▪ | ▫ | ▬ |
 | 62 | ▭ | ▮ | ▯ | ▰ | ▱ | ▲ | △ | ▴ | ▵ | ▶ | ▷ | ▸ | ▹ | ► | ▻ | ▼ |
 | 63 | ▽ | ▾ | ▿ | ◀ | ◁ | ◂ | ◃ | ◄ | ◅ | ◆ | ◇ | ◈ | ◉ | ◊ | ○ | ◌ |
 | 64 | ◍ | ◎ | ● | ◐ | ◑ | ◒ | ◓ | ◔ | ◕ | ◖ | ◗ | ◘ | ◙ | ◚ | ◛ | ◜ |
 | 65 | ◝ | ◞ | ◟ | ◠ | ◡ | ◢ | ◣ | ◤ | ◥ | ◦ | ◧ | ◨ | ◩ | ◪ | ◫ | ◬ |
 | 66 | ◭ | ◮ | ◯ | ◰ | ◱ | ◲ | ◳ | ◴ | ◵ | ◶ | ◷ | ◸ | ◹ | ◺ | ◻ | ◼ |
 | 67 | ◽ | ◾ | ◿ | ☀ | ☁ | ☂ | ☃ | ☄ | ★ | ☆ | ☇ | ☈ | ☉ | ☊ | ☋ | ☌ |
 | 68 | ☍ | ☎ | ☏ | ☐ | ☑ | ☒ | ☓ | ☔ | ☕ | ☖ | ☗ | ☘ | ☙ | ☚ | ☛ | ☜ |
 | 69 | ☝ | ☞ | ☟ | ☠ | ☡ | ☢ | ☣ | ☤ | ☥ | ☦ | ☧ | ☨ | ☩ | ☪ | ☫ | ☬ |
 | 6a | ☭ | ☮ | ☯ | ☰ | ☱ | ☲ | ☳ | ☴ | ☵ | ☶ | ☷ | ☸ | ☹ | ☺ | ☻ | ☼ |
 | 6b | ☽ | ☾ | ☿ | ♀ | ♁ | ♂ | ♃ | ♄ | ♅ | ♆ | ♇ | ♈ | ♉ | ♊ | ♋ | ♌ |
 | 6c | ♍ | ♎ | ♏ | ♐ | ♑ | ♒ | ♓ | ♔ | ♕ | ♖ | ♗ | ♘ | ♙ | ♚ | ♛ | ♜ |
 | 6d | ♝ | ♞ | ♟ | ♠ | ♡ | ♢ | ♣ | ♤ | ♥ | ♦ | ♧ | ♨ | ♩ | ♪ | ♫ | ♬ |
 | 6e | ♭ | ♮ | ♯ | ♰ | ♱ | ♲ | ♳ | ♴ | ♵ | ♶ | ♷ | ♸ | ♹ | ♺ | ♻ | ♼ |
 | 6f | ♽ | ♾ | ♿ | ⚀ | ⚁ | ⚂ | ⚃ | ⚄ | ⚅ | ⚆ | ⚇ | ⚈ | ⚉ | ⚊ | ⚋ | ⚌ |
 | 70 | ⚍ | ⚎ | ⚏ | ⚐ | ⚑ | ⚒ | ⚓ | ⚔ | ⚕ | ⚖ | ⚗ | ⚘ | ⚙ | ⚚ | ⚛ | ⚜ |
 | 71 | ⚝ | ⚞ | ⚟ | ⚠ | ⚡ | ⚢ | ⚣ | ⚤ | ⚥ | ⚦ | ⚧ | ⚨ | ⚩ | ⚪ | ⚫ | ⚬ |
 | 72 | ⚭ | ⚮ | ⚯ | ⚰ | ⚱ | ⚲ | ⚳ | ⚴ | ⚵ | ⚶ | ⚷ | ⚸ | ⚹ | ⚺ | ⚻ | ⚼ |
 | 73 | ⚽ | ⚾ | ⚿ | ⛀ | ⛁ | ⛂ | ⛃ | ⛄ | ⛅ | ⛆ | ⛇ | ⛈ | ⛉ | ⛊ | ⛋ | ⛌ |
 | 74 | ⛍ | ⛎ | ⛏ | ⛐ | ⛑ | ⛒ | ⛓ | ⛔ | ⛕ | ⛖ | ⛗ | ⛘ | ⛙ | ⛚ | ⛛ | ⛜ |
 | 75 | ⛝ | ⛞ | ⛟ | ⛠ | ⛡ | ⛢ | ⛣ | ⛤ | ⛥ | ⛦ | ⛧ | ⛨ | ⛩ | ⛪ | ⛫ | ⛬ |
 | 76 | ⛭ | ⛮ | ⛯ | ⛰ | ⛱ | ⛲ | ⛳ | ⛴ | ⛵ | ⛶ | ⛷ | ⛸ | ⛹ | ⛺ | ⛻ | ⛼ |
 | 77 | ⛽ | ⛾ | ⛿ |


### Prefix.

Prefix operator - applies only to the following variable or bracketed term.

Contains: 110 characters.


 |  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
 | 0 | 𝑨 | 𝑩 | 𝑪 | 𝑫 | 𝑬 | 𝑭 | 𝑮 | 𝑯 | 𝑰 | 𝑱 | 𝑲 | 𝑳 | 𝑴 | 𝑵 | 𝑶 | 𝑷 |
 | 1 | 𝑸 | 𝑹 | 𝑺 | 𝑻 | 𝑼 | 𝑽 | 𝑾 | 𝑿 | 𝒀 | 𝒁 | 𝒂 | 𝒃 | 𝒄 | 𝒅 | 𝒆 | 𝒇 |
 | 2 | 𝒈 | 𝒉 | 𝒊 | 𝒋 | 𝒌 | 𝒍 | 𝒎 | 𝒏 | 𝒐 | 𝒑 | 𝒒 | 𝒓 | 𝒔 | 𝒕 | 𝒖 | 𝒗 |
 | 3 | 𝒘 | 𝒙 | 𝒚 | 𝒛 | 𝜜 | 𝜝 | 𝜞 | 𝜟 | 𝜠 | 𝜡 | 𝜢 | 𝜣 | 𝜤 | 𝜥 | 𝜦 | 𝜧 |
 | 4 | 𝜨 | 𝜩 | 𝜪 | 𝜫 | 𝜬 | 𝜭 | 𝜮 | 𝜯 | 𝜰 | 𝜱 | 𝜲 | 𝜳 | 𝜴 | 𝜵 | 𝜶 | 𝜷 |
 | 5 | 𝜸 | 𝜹 | 𝜺 | 𝜻 | 𝜼 | 𝜽 | 𝜾 | 𝜿 | 𝝀 | 𝝁 | 𝝂 | 𝝃 | 𝝄 | 𝝅 | 𝝆 | 𝝇 |
 | 6 | 𝝈 | 𝝉 | 𝝊 | 𝝋 | 𝝌 | 𝝍 | 𝝎 | 𝝏 | 𝝐 | 𝝑 | 𝝒 | 𝝓 | 𝝔 | 𝝕 |


### Suffix.

Suffix operator - applies only to the preceding variable or bracketed term.

Contains: 110 characters.


 |  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
 | 0 | 𝘼 | 𝘽 | 𝘾 | 𝘿 | 𝙀 | 𝙁 | 𝙂 | 𝙃 | 𝙄 | 𝙅 | 𝙆 | 𝙇 | 𝙈 | 𝙉 | 𝙊 | 𝙋 |
 | 1 | 𝙌 | 𝙍 | 𝙎 | 𝙏 | 𝙐 | 𝙑 | 𝙒 | 𝙓 | 𝙔 | 𝙕 | 𝙖 | 𝙗 | 𝙘 | 𝙙 | 𝙚 | 𝙛 |
 | 2 | 𝙜 | 𝙝 | 𝙞 | 𝙟 | 𝙠 | 𝙡 | 𝙢 | 𝙣 | 𝙤 | 𝙥 | 𝙦 | 𝙧 | 𝙨 | 𝙩 | 𝙪 | 𝙫 |
 | 3 | 𝙬 | 𝙭 | 𝙮 | 𝙯 | 𝞐 | 𝞑 | 𝞒 | 𝞓 | 𝞔 | 𝞕 | 𝞖 | 𝞗 | 𝞘 | 𝞙 | 𝞚 | 𝞛 |
 | 4 | 𝞜 | 𝞝 | 𝞞 | 𝞟 | 𝞠 | 𝞡 | 𝞢 | 𝞣 | 𝞤 | 𝞥 | 𝞦 | 𝞧 | 𝞨 | 𝞩 | 𝞪 | 𝞫 |
 | 5 | 𝞬 | 𝞭 | 𝞮 | 𝞯 | 𝞰 | 𝞱 | 𝞲 | 𝞳 | 𝞴 | 𝞵 | 𝞶 | 𝞷 | 𝞸 | 𝞹 | 𝞺 | 𝞻 |
 | 6 | 𝞼 | 𝞽 | 𝞾 | 𝞿 | 𝟀 | 𝟁 | 𝟂 | 𝟃 | 𝟄 | 𝟅 | 𝟆 | 𝟇 | 𝟈 | 𝟉 |


### SemiColon.

Infix operator with left to right binding at priority 1.

Contains: 1 characters.


 |  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
 | 0 | ⟢ |


### Variable.

Variable names.

Contains: 110 characters.


 |  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
 | 0 | 𝗔 | 𝗕 | 𝗖 | 𝗗 | 𝗘 | 𝗙 | 𝗚 | 𝗛 | 𝗜 | 𝗝 | 𝗞 | 𝗟 | 𝗠 | 𝗡 | 𝗢 | 𝗣 |
 | 1 | 𝗤 | 𝗥 | 𝗦 | 𝗧 | 𝗨 | 𝗩 | 𝗪 | 𝗫 | 𝗬 | 𝗭 | 𝗮 | 𝗯 | 𝗰 | 𝗱 | 𝗲 | 𝗳 |
 | 2 | 𝗴 | 𝗵 | 𝗶 | 𝗷 | 𝗸 | 𝗹 | 𝗺 | 𝗻 | 𝗼 | 𝗽 | 𝗾 | 𝗿 | 𝘀 | 𝘁 | 𝘂 | 𝘃 |
 | 3 | 𝘄 | 𝘅 | 𝘆 | 𝘇 | 𝝖 | 𝝗 | 𝝘 | 𝝙 | 𝝚 | 𝝛 | 𝝜 | 𝝝 | 𝝞 | 𝝟 | 𝝠 | 𝝡 |
 | 4 | 𝝢 | 𝝣 | 𝝤 | 𝝥 | 𝝦 | 𝝧 | 𝝨 | 𝝩 | 𝝪 | 𝝫 | 𝝬 | 𝝭 | 𝝮 | 𝝯 | 𝝰 | 𝝱 |
 | 5 | 𝝲 | 𝝳 | 𝝴 | 𝝵 | 𝝶 | 𝝷 | 𝝸 | 𝝹 | 𝝺 | 𝝻 | 𝝼 | 𝝽 | 𝝾 | 𝝿 | 𝞀 | 𝞁 |
 | 6 | 𝞂 | 𝞃 | 𝞄 | 𝞅 | 𝞆 | 𝞇 | 𝞈 | 𝞉 | 𝞊 | 𝞋 | 𝞌 | 𝞍 | 𝞎 | 𝞏 |




## Minimalism through Unicode

This [module](https://en.wikipedia.org/wiki/Modular_programming) is part of the Earl Zero project: using Perl 5 to create a minimal,
modern [Unicode](https://en.wikipedia.org/wiki/Unicode) based programming language: Earl Zero. Earl Zero generates x86 [assembler](https://en.wikipedia.org/wiki/Assembly_language#Assembler) [code](https://en.wikipedia.org/wiki/Computer_program) directly from a [program](https://en.wikipedia.org/wiki/Computer_program) consisting of a single Unisyn expression
with no keywords; only expressions constructed from [user](https://en.wikipedia.org/wiki/User_(computing)) defined
[unary](https://en.wikipedia.org/wiki/Unary_operation) and
[binary](https://en.wikipedia.org/wiki/Binary_operation)
[operators](https://en.wikipedia.org/wiki/Operator_(mathematics)) are used to
construct Unisyn [programs](https://en.wikipedia.org/wiki/Computer_program). 
Minimalism is an important part of Earl Zero; for example, the "Hello World" [program](https://en.wikipedia.org/wiki/Computer_program) is:

```
Hello World
```

Earl Zero leverages Perl 5 as its [macro
assembler](https://en.wikipedia.org/wiki/Assembly_language#Macros) and
[CPAN](https://metacpan.org/author/PRBRENAN) as its [module](https://en.wikipedia.org/wiki/Modular_programming) repository.

## Other languages
 [Lisp](https://en.wikipedia.org/wiki/Lisp), [Bash](https://en.wikipedia.org/wiki/Bash_(Unix_shell)), [Tcl](https://en.wikipedia.org/wiki/Tcl) are well known, successful languages that use generic syntaxes.

## Join in!

Please feel free to join in with this interesting project - we need all the [help](https://en.wikipedia.org/wiki/Online_help) we can get.
