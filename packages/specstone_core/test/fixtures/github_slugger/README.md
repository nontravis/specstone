# github-slugger fixture

Source: <https://github.com/Flet/github-slugger/blob/3461c4350868329c8530904d170358bca1d31448/test/fixtures.json>
(commit `3461c4350868329c8530904d170358bca1d31448`), ISC licensed:

> Copyright (c) 2015, Dan Flettre <fletd01@yahoo.com>
>
> Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby
> granted, provided that the above copyright notice and this permission notice appear in all copies.

The 78 entries `{name, input, expected}` are copied unchanged. The test runs them in order through one slugger, so a
repeat's expected slug counts every earlier entry. An entry skipped because a code point's Unicode category or casing
changed between github-slugger's tables (V8's) and Dart's is listed here, never edited in the JSON.

Skipped entries:

- `Cased_Letter`: Dart's `String.toLowerCase` leaves U+01C5-class title-case letters uncased where V8 lower-cases them.
- `Letter`: Dart's `String.toLowerCase` leaves U+A640-class Cyrillic capitals uncased.
- `Uppercase_Letter`: Dart's `String.toLowerCase` leaves U+0524-class Cyrillic and Cherokee capitals uncased, and maps
  U+0130 to `i` where V8 gives `i` + U+0307.
- `Unassigned`: U+3174F is category `Lo` in Dart's Unicode tables and unassigned in github-slugger's, so the keep class
  holds it there while the slugger drops it.

Divergence left in `headingSlugOf`, by code point:

- U+0130 `İ`: Dart lower-cases it to `i`; V8 gives `i` + U+0307.
- U+037F `Ϳ`: Dart leaves it uncased; V8 gives U+03F3.
- U+0524 to U+052E, the even code points: Dart leaves these Cyrillic capitals uncased; V8 lower-cases each to the next
  code point.
- Word-final U+03A3 `Σ` is no divergence: `headingSlugOf` maps it to U+03C2 `ς` by Unicode's Final_Sigma context, the
  one context rule V8's lower-case applies.

The rest is a Unicode-version gap. Dart's `String.toLowerCase` and its RegExp `\p{…}` tables trail V8's: Dart SDK 3.13.5
against Node with Unicode 17.0. A per-code-point differential over U+0020 to U+2FFFF (final review, 2026-11-07) found
468 casing and 373 category differences, none in Thai, CJK, or Hangul. They move with the Dart SDK, not with this
code.
