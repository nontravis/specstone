/// An attribute of a start tag in html: its name in ASCII lower case, the
/// span of its value, and the tag holding it.
typedef HtmlAttribute = ({
  String name,
  int start,
  int end,
  String value,
  String tag,
});

/// Returns the `id`, `href`, and `name` attributes of every start tag in
/// [html], in document order.
///
/// Only real start tags are read: the quotes of an attribute value may be
/// double, single, or absent, attribute names match in any letter case, the
/// first of a repeated name counts, and a comment, declaration, or end tag
/// holds no attribute.
List<HtmlAttribute> scanStartTagAttributes(String html) {
  final found = <HtmlAttribute>[];
  var i = 0;
  while (true) {
    i = html.indexOf('<', i);
    if (i < 0 || i + 1 >= html.length) return found;
    final next = html.codeUnitAt(i + 1);
    if (_isAsciiLetter(next)) {
      i = _scanStartTag(html, i + 1, found);
    } else if (html.startsWith('<!--', i)) {
      final end = _commentEnd(html, i);
      if (end < 0) return found;
      i = end;
    } else if (next == 0x21 || next == 0x3F || next == 0x2F) {
      final close = html.indexOf('>', i + 2);
      if (close < 0) return found;
      i = close + 1;
    } else {
      i += 1;
    }
  }
}

/// Returns [html] with the tags the GFM "disallowed raw html" rule plus
/// `noscript` and `template` writes as text.
///
/// The `markdown` package's own filter only matches a start tag without
/// attributes, so `<title lang=x>` and `</title>` get through it, and an
/// unclosed start tag of these names would swallow the docs after it.
String withTagFilter(String html) => html.replaceAll(_disallowedTag, '&lt;');

/// Tags the GFM "disallowed raw HTML" rule writes as text, plus `noscript` and
/// `template`, whose unclosed start tag also swallows the docs after it.
final _disallowedTag = RegExp(
  '<(?=/?(?:title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext'
  r'|noscript|template)[\s/>])',
  caseSensitive: false,
);

// Returns the index after the comment that opens at [open], or -1 when it is
// unclosed. Per WHATWG, `<!-->` and `<!--->` close at once, and `-->` or
// `--!>` ends any other comment.
int _commentEnd(String html, int open) {
  if (html.startsWith('>', open + 4)) return open + 5;
  if (html.startsWith('->', open + 4)) return open + 6;
  final plain = html.indexOf('-->', open + 4);
  final bang = html.indexOf('--!>', open + 4);
  if (plain < 0 && bang < 0) return -1;
  if (bang < 0 || (plain >= 0 && plain < bang)) return plain + 3;
  return bang + 4;
}

// Scans the start tag whose name begins at [from]; returns the index after it.
int _scanStartTag(String html, int from, List<HtmlAttribute> found) {
  var i = from;
  while (i < html.length && !_isTagNameEnd(html.codeUnitAt(i))) {
    i += 1;
  }
  final tag = html.substring(from, i).toLowerCase();
  final seen = <String>{};
  while (i < html.length) {
    final unit = html.codeUnitAt(i);
    if (_isSpace(unit) || unit == 0x2F) {
      i += 1;
      continue;
    }
    if (unit == 0x3E) return i + 1;
    final nameStart = i;
    i += 1;
    while (i < html.length && !_isNameEnd(html.codeUnitAt(i))) {
      i += 1;
    }
    final name = html.substring(nameStart, i).toLowerCase();
    while (i < html.length && _isSpace(html.codeUnitAt(i))) {
      i += 1;
    }
    if (i >= html.length || html.codeUnitAt(i) != 0x3D) continue;
    i += 1;
    while (i < html.length && _isSpace(html.codeUnitAt(i))) {
      i += 1;
    }
    if (i >= html.length) return i;
    final valueStart = html.codeUnitAt(i);
    final int start;
    final int end;
    if (valueStart == 0x22 || valueStart == 0x27) {
      start = i + 1;
      final close = html.indexOf(String.fromCharCode(valueStart), start);
      end = close < 0 ? html.length : close;
      i = close < 0 ? html.length : close + 1;
    } else {
      start = i;
      while (i < html.length &&
          !_isSpace(html.codeUnitAt(i)) &&
          html.codeUnitAt(i) != 0x3E) {
        i += 1;
      }
      end = i;
    }
    final isFirstOfName = seen.add(name);
    if (isFirstOfName && (name == 'id' || name == 'href' || name == 'name')) {
      found.add((
        name: name,
        start: start,
        end: end,
        value: html.substring(start, end),
        tag: tag,
      ));
    }
  }
  return i;
}

bool _isSpace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0C ||
    unit == 0x0D;

bool _isAsciiLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

bool _isTagNameEnd(int unit) => _isSpace(unit) || unit == 0x2F || unit == 0x3E;

bool _isNameEnd(int unit) => _isTagNameEnd(unit) || unit == 0x3D;
