import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/html_attributes.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';

/// The anchors of one doc body (doc_model RULE-13).
final class DocAnchors {
  /// Makes [headingSlugs] and [htmlIds] the doc's anchor set.
  const new({required this.headingSlugs, required this.htmlIds});

  /// One slug per heading, in file order, a repeat suffixed `-1`, `-2`.
  final List<String> headingSlugs;

  /// Each body start tag's `id` and each `<a>`'s `name`, footnote ids
  /// excluded.
  final Set<String> htmlIds;

  /// Whether [anchor] names a heading slug or an html id of this doc.
  bool holds(String anchor) =>
      headingSlugs.contains(anchor) || htmlIds.contains(anchor);

  /// Returns the anchors as JSON values, as `LineFacts.toJson` stores them.
  Map<String, Object> toJson() => {
    'headings': headingSlugs,
    'ids': htmlIds.toList(),
  };
}

/// Returns the anchors of [body], the nodes `parseMarkdown` gave.
DocAnchors anchorsOf(List<Node> body) {
  final headings = <String>[];
  final htmlIds = <String>{};
  _collect(body, headings: headings, htmlIds: htmlIds);
  return DocAnchors(
    headingSlugs: _suffixed([
      for (final heading in headings) headingSlugOf(heading),
    ]),
    htmlIds: htmlIds,
  );
}

/// Returns the anchors of the body text [body], or null when the anchor parse
/// fails (P11).
DocAnchors? anchorsOfBody(String body) {
  final nodes = parseBodyForAnchors(body);
  return nodes == null ? null : anchorsOf(nodes);
}

/// Returns the GitHub slug of a heading's rendered text, before any suffix.
///
/// Follows github-slugger (RULE-13): lower-case the text, remove every
/// character outside `\p{Alphabetic}`, `\p{M}`, `\p{Nd}`, `\p{Pc}`, space, and
/// `-`, then turn each space into `-`.
String headingSlugOf(String renderedText) => renderedText
    .toLowerCase()
    .replaceAll(_nonSlugCharacter, '')
    .replaceAll(' ', '-');

// The characters github-slugger's generated regex removes: everything its
// keep class (`\p{Alphabetic}`, `\p{M}`, `\p{Nd}`, `\p{Pc}`) does not hold,
// bar space and `-`, which stay.
final _nonSlugCharacter = RegExp(
  r'[^\p{Alphabetic}\p{M}\p{Nd}\p{Pc} -]',
  unicode: true,
);

/// Returns [slugs] with each repeat suffixed `-1`, `-2`, and so on, by that
/// base slug's count of repeats so far, tried again until free.
List<String> _suffixed(List<String> slugs) {
  final taken = <String>{};
  final counts = <String, int>{};
  return [
    for (final slug in slugs) _freeSlug(slug, taken: taken, counts: counts),
  ];
}

String _freeSlug(
  String slug, {
  required Set<String> taken,
  required Map<String, int> counts,
}) {
  var result = slug;
  while (taken.contains(result)) {
    final count = (counts[slug] ?? 0) + 1;
    counts[slug] = count;
    result = '$slug-$count';
  }
  taken.add(result);
  return result;
}

// Walks [nodes] once: each h1-h6 element's text gives a heading, and each
// Text node outside `code` and `pre` holds raw html whose start tags may
// carry an id or an a's name. Footnote elements carry their ids as element
// attributes, never as raw text, so they stay out.
void _collect(
  List<Node> nodes, {
  required List<String> headings,
  required Set<String> htmlIds,
}) {
  for (final node in nodes) {
    if (node is! Element) {
      final text = node is Text ? node.text : '';
      if (text.isNotEmpty) _collectHtmlIds(text, htmlIds);
      continue;
    }
    if (node.tag == 'code' || node.tag == 'pre') continue;
    if (_isHeading(node.tag)) headings.add(_renderedText(node));
    final children = node.children;
    if (children != null) {
      _collect(children, headings: headings, htmlIds: htmlIds);
    }
  }
}

// A heading's rendered text: the text nodes under it, raw tags dropped and
// html entities decoded, as the renderer would emit them.
String _renderedText(Element heading) =>
    _decodeEntities(_stripTags(_rawText(heading.children)));

String _rawText(List<Node>? nodes) {
  if (nodes == null) return '';
  final parts = <String>[];
  for (final node in nodes) {
    if (node is Text) {
      parts.add(node.text);
    } else if (node is Element) {
      parts.add(_rawText(node.children));
    }
  }
  return parts.join();
}

// Drops raw tags from heading text: markdown keeps them inside Text nodes.
// A quoted attribute value may hold `>`, so quotes are skipped, as the
// scanner in html_attributes.dart reads them.
String _stripTags(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final open = text.indexOf('<', i);
    if (open < 0) {
      out.write(text.substring(i));
      break;
    }
    out.write(text.substring(i, open));
    var end = open + 1;
    var quoted = 0;
    while (end < text.length) {
      final unit = text.codeUnitAt(end);
      if (quoted != 0) {
        if (unit == quoted) quoted = 0;
      } else if (unit == 0x22 || unit == 0x27) {
        quoted = unit;
      } else if (unit == 0x3E) {
        break;
      }
      end += 1;
    }
    i = end < text.length ? end + 1 : text.length;
  }
  return out.toString();
}

final _entity = RegExp(
  '&(?:[a-zA-Z][a-zA-Z0-9]*|#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6});',
);

// Decodes the entity references the markdown package decodes: named, decimal,
// and hex. Mirrors markdown 7.3.1's `decodeHtmlCharacters`, which is not
// exported.
String _decodeEntities(String text) => text.replaceAllMapped(_entity, _decode);

String _decode(Match match) {
  final body = match[0]!;
  final name = body.substring(1, body.length - 1);
  if (name.startsWith('#')) {
    final hex = name.startsWith('#x') || name.startsWith('#X');
    final digits = hex ? name.substring(2) : name.substring(1);
    final value = int.tryParse(digits, radix: hex ? 16 : 10);
    if (value == null || value == 0 || value > 0x10FFFF) {
      return String.fromCharCode(0xFFFD);
    }
    return String.fromCharCode(value);
  }
  return _namedEntities[name] ?? body;
}

// The named entities markdown 7.3.1 decodes; only those with slug-relevant
// characters matter, so the rest stay as written, as github-slugger would
// receive them from the rendered html anyway.
const _namedEntities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
};

bool _isHeading(String tag) =>
    tag.length == 2 &&
    tag.codeUnitAt(0) == 0x68 /* h */ &&
    tag.codeUnitAt(1) >= 0x31 &&
    tag.codeUnitAt(1) <= 0x36;

void _collectHtmlIds(String rawHtml, Set<String> htmlIds) {
  // A start tag needs a `<`; text without one holds none.
  if (!rawHtml.contains('<')) return;
  final filtered = withTagFilter(rawHtml.replaceAll(_rawTextElement, ''));
  for (final attribute in scanStartTagAttributes(filtered)) {
    if (attribute.name == 'id' ||
        (attribute.tag == 'a' && attribute.name == 'name')) {
      htmlIds.add(attribute.value);
    }
  }
}

// The html raw-text elements: their content is text, never markup, so a tag
// written inside one (the filter escapes its start tag) holds no id.
final _rawTextElement = RegExp(
  r'<(script|style|textarea|title|xmp|plaintext)\b[^>]*>[\s\S]*?'
  r'(?:</\1\s*>|$)',
  caseSensitive: false,
);
