# Parse a Unisyn expression.

![Test](https://github.com/philiprbrenan/UnisynParse/workflows/Test/badge.svg)

Once there were many different character sets that were unified by [Unicode](https://en.wikipedia.org/wiki/Unicode). 
Today we have many different programming languages, each with a slightly
different syntax from the others. The multiplicity of such syntaxes imposes
unnecessary burdens on users and language designers.  Unisyn is proposed as a
common syntax that can be used by many different programming languages.

Advantages of having one uniform language syntax:

- less of a burden on users to recall which of the many syntax schemes in
current use is the relevant one for the programming language they are currently
programming in.  Rather like having all your electrical appliances work from the
same voltage electricity supply rather than different ones.

- programming effort can be applied globally to optimize the parsing [process](https://en.wikipedia.org/wiki/Process_management_(computing)) to
produce the fastest possible parser with the best diagnostics.

## Special features

- Expressions in Unisyn can be parsed in situ - it is not necessary to reparse
the entire source [file](https://en.wikipedia.org/wiki/Computer_file) to syntax check changes made to the [file](https://en.wikipedia.org/wiki/Computer_file). Instead
changes can be checked locally at the point of modification.

- Expressions in Unisyn can be parsed using [SIMD](https://www.officedaytime.com/simd512e/) instructions making parsing
faster than otherwise.
