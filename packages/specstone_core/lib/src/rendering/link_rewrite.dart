import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/rendering/html_page.dart' show escapeText;

/// Rewrites every `a` element under [nodes] in place for the single-file html.
///
/// An `http` or `https` link (any letter case) stays. A link to a doc in
/// [anchors] jumps to that doc's anchor. A bare `#fragment` stays as written
/// for `scopeIds`, which runs on the rendered html. Any other link becomes an
/// `outside-link` span that keeps the link text and shows the path in `code`.
///
/// - [docPath]: the path of the doc holding [nodes], relative to the docs root.
/// - [anchors]: the section anchor of each doc in the build, by docPath. A bare
///   `#fragment` in a doc with no entry becomes an `outside-link` span.
void rewriteLinks(
  List<Node> nodes, {
  required String docPath,
  required Map<String, String> anchors,
}) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is! Element) continue;
    final children = node.children;
    if (children != null) {
      rewriteLinks(children, docPath: docPath, anchors: anchors);
    }
    if (node.tag == 'a') {
      nodes[i] = _rewriteLink(node, docPath: docPath, anchors: anchors);
    }
  }
}

Node _rewriteLink(
  Element link, {
  required String docPath,
  required Map<String, String> anchors,
}) {
  final href = link.attributes['href'] ?? '';
  final target = resolveDocLink(href, docPath);
  switch (target) {
    case WebTarget():
      return link;
    case DocTarget(docPath: final resolved):
      final anchor = anchors[resolved];
      if (anchor == null) return _outsideSpan(link, resolved);
      if (href.startsWith('#')) return link;
      link.attributes['href'] = '#$anchor';
      return link;
    case OutsideTarget(:final shown):
      return _outsideSpan(link, shown);
  }
}

/// Prefixes every `id` in [bodyHtml] with [anchor] and a hyphen, and points
/// each bare `#fragment` link at the result.
///
/// Ids then stay unique across the docs of one page. Only real start tags are
/// read: the quotes of an attribute value may be double, single, or absent,
/// attribute names match in any letter case, the first of a repeated name
/// counts, and a comment, declaration, or end tag holds no attribute. A
/// fragment that is a page anchor in [pageAnchors] is a link `rewriteLinks`
/// already resolved and stays, even when the body holds an id equal to it. Else
/// a fragment that names an id of the body (`fn-1`, `top`) goes to the prefixed
/// id (`doc-3-fn-1`), and any other fragment goes to [anchor]. Run it after the
/// tag filter, so a tag the filter turns into text holds no id.
///
/// - [bodyHtml]: the rendered, tag-filtered html of one doc's body.
/// - [anchor]: the section anchor of that doc.
/// - [pageAnchors]: the section anchor of every doc in the build.
String scopeIds(
  String bodyHtml, {
  required String anchor,
  required Set<String> pageAnchors,
}) {
  final attributes = _scanAttributes(bodyHtml);
  final ids = {
    for (final attribute in attributes)
      if (attribute.name == 'id') attribute.value,
  };
  final out = StringBuffer();
  var copied = 0;
  for (final attribute in attributes) {
    final String? replacement;
    if (attribute.name == 'id') {
      replacement = '$anchor-${attribute.value}';
    } else if (attribute.value.startsWith('#')) {
      final fragment = attribute.value.substring(1);
      if (pageAnchors.contains(fragment)) continue;
      replacement =
          '#${_namesId(fragment, ids) ? '$anchor-$fragment' : anchor}';
    } else {
      continue;
    }
    out
      ..write(bodyHtml.substring(copied, attribute.start))
      ..write(replacement);
    copied = attribute.end;
  }
  return (out..write(bodyHtml.substring(copied))).toString();
}

/// The value of an `id` or `href` attribute and where it sits in the html.
class _Attribute {
  const new(this.name, this.start, this.end, this.value);

  /// The attribute name in ASCII lower case.
  final String name;

  /// The span of the value, quotes excluded.
  final int start;
  final int end;
  final String value;
}

bool _isSpace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0C ||
    unit == 0x0D;

bool _isAsciiLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

// Reads start tags only: `<` then an ASCII letter opens one, and a comment,
// any other `<!…>`, `<?…>`, or end tag is skipped whole.
List<_Attribute> _scanAttributes(String html) {
  final found = <_Attribute>[];
  var i = 0;
  while (true) {
    i = html.indexOf('<', i);
    if (i < 0 || i + 1 >= html.length) return found;
    final next = html.codeUnitAt(i + 1);
    if (_isAsciiLetter(next)) {
      i = _scanStartTag(html, i + 1, found);
    } else if (html.startsWith('<!--', i)) {
      final close = html.indexOf('-->', i + 4);
      if (close < 0) return found;
      i = close + 3;
    } else if (next == 0x21 || next == 0x3F || next == 0x2F) {
      final close = html.indexOf('>', i + 2);
      if (close < 0) return found;
      i = close + 1;
    } else {
      i += 1;
    }
  }
}

// Scans the start tag whose name begins at [from]; returns the index after it.
int _scanStartTag(String html, int from, List<_Attribute> found) {
  final seen = <String>{};
  var i = from;
  while (i < html.length && !_isTagNameEnd(html.codeUnitAt(i))) {
    i += 1;
  }
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
    if (isFirstOfName && (name == 'id' || name == 'href')) {
      found.add(_Attribute(name, start, end, html.substring(start, end)));
    }
  }
  return i;
}

bool _isTagNameEnd(int unit) => _isSpace(unit) || unit == 0x2F || unit == 0x3E;

bool _isNameEnd(int unit) => _isTagNameEnd(unit) || unit == 0x3D;

final _brokenPercent = RegExp('%(?![0-9A-Fa-f]{2})');

// A fragment may be written percent-encoded, an id never is.
bool _namesId(String fragment, Set<String> ids) {
  if (ids.contains(fragment)) return true;
  if (_brokenPercent.hasMatch(fragment)) return false;
  try {
    return ids.contains(Uri.decodeComponent(fragment));
  } on FormatException {
    return false;
  }
}

// The renderer writes a Text as given, so the path is escaped here.
Element _outsideSpan(Element link, String shown) => Element('span', [
  ...?link.children,
  Text(' ('),
  Element('code', [Text(escapeText(shown))]),
  Text(')'),
])..attributes['class'] = 'outside-link';
