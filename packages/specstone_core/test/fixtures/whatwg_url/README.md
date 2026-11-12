# WHATWG URL parser fixture

`urltestdata.json` is a filtered copy of the web-platform-tests URL parser data. `whatwg_url_test.dart` checks
`whatwgParseFails` against every entry in it.

## Source

- File: `url/resources/urltestdata.json` of <https://github.com/web-platform-tests/wpt>
- Commit: `c48d58747e1f211527fb695fd60548a997fae617`
- URL: <https://raw.githubusercontent.com/web-platform-tests/wpt/c48d58747e1f211527fb695fd60548a997fae617/url/resources/urltestdata.json>

## Selection rule

`whatwgParseFails` parses with a `file:` URL as its base, so the fixture keeps only entries whose result holds under
that base. It keeps an object entry when either:

- its `input` opens with a scheme other than `file` (an ASCII letter, then ASCII letters, digits, `+`, `-`, or `.`,
  then `:`), and its `base` is null or has another scheme than the input's, so the result does not depend on the
  base; or
- its `base` opens with `file:`.

The input's scheme is read the way the parser reads it: after leading and trailing C0 controls and spaces are trimmed
and every tab and newline is removed, with the scheme compared lowercased.

Each kept entry is written as `{"input": ..., "failure": true|false}`. `failure` is true when the source entry has
`"failure": true`. Every code unit above U+007E is written as a `\u` escape, so a lone surrogate survives the file.

## The UTS46 gap

`whatwgParseFails` does not run UTS46 domain-to-ASCII, since no Unicode IDNA mapping table ships with Specstone
(`doc_model` RULE-11). The fixture therefore drops each entry whose host, after percent-decoding and UTF-8 decoding,
holds a code point above U+007F or a label opening with `xn--` (ASCII case-insensitive). This is the same test the
parser's domain step applies, so an entry whose host is non-ASCII only after percent-decoding is dropped too.

## Counts

| Entries                                    | Count |
|--------------------------------------------|------:|
| Object entries in the source               |   896 |
| Kept                                       |   590 |
| Kept, `failure: true`                      |   180 |
| Kept, `failure: false`                     |   410 |
| Dropped: result depends on a non-file base |   284 |
| Dropped: the UTS46 gap                     |    22 |

The source's 115 comment strings are not copied.

## License

The web-platform-tests data is used under its license:

> # The 3-Clause BSD License
>
> Copyright © web-platform-tests contributors
>
> Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
> following conditions are met:
>
> 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following
>    disclaimer.
> 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
>    following disclaimer in the documentation and/or other materials provided with the distribution.
> 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
>    products derived from this software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
> INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
> DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
> SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
> SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
> WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
> OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
