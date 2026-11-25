import 'dart:convert';
import 'dart:math';

import 'package:specstone_core/src/rendering/mermaid_script.dart';
import 'package:specstone_core/src/rendering/page_setup.dart';

/// The page stylesheet: system fonts only, nothing fetched.
///
/// The last two rules act in print: colors stay as drawn, and the body box
/// that frames the screen gives way to the `@page` margin.
const String pageStylesheet = '''
body { font-family: system-ui, -apple-system, "Segoe UI", sans-serif; line-height: 1.5; margin: 2rem auto; max-width: 56rem; padding: 0 1rem; }
nav.toc ul { list-style: none; padding-left: 0; }
section.doc { break-before: page; }
table { border-collapse: collapse; margin: 1rem 0; }
th, td { border: 1px solid #888; padding: 0.25rem 0.6rem; text-align: left; vertical-align: top; }
table.frontmatter td { white-space: pre-wrap; }
pre { background: #f4f4f4; overflow-x: auto; padding: 0.75rem; }
pre.mermaid { background: none; text-align: center; }
.draft { border: 2px solid #b00020; color: #b00020; display: inline-block; font-weight: bold; padding: 0.1rem 0.6rem; text-transform: uppercase; }
.outside-link { color: #555; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
@media print { body { margin: 0; max-width: none; padding: 0; } }
''';

const _escape = HtmlEscape(
  HtmlEscapeMode(escapeLtGt: true, escapeQuot: true, escapeApos: true),
);

/// Returns [text] safe in html text and in a double- or single-quoted
/// attribute; slashes stay as they are.
String escapeText(String text) => _escape.convert(text);

const _nonceBytes = 16;

/// Returns a fresh unguessable nonce for one page's `script-src`.
String _newNonce() {
  final random = Random.secure();
  return base64Url.encode([
    for (var i = 0; i < _nonceBytes; i++) random.nextInt(256),
  ]);
}

String _contentSecurityPolicy(String nonce) =>
    "default-src 'none'; script-src 'nonce-$nonce'; "
    "style-src 'unsafe-inline'; img-src data:; font-src data:";

/// One doc ready for the page: its anchor, toc entry, and body html.
final class RenderedDoc {
  const new({
    required this.anchor,
    required this.tocEntry,
    required this.bodyHtml,
  });

  /// The section id the toc links to.
  final String anchor;

  /// The toc link text, plain text.
  final String tocEntry;

  /// The doc's html, placed inside its section as is.
  final String bodyHtml;
}

/// Returns a self-contained html page: a toc, then each doc in a section.
///
/// The page loads nothing: the CSP meta denies every fetch and the mermaid
/// script is inlined. Only the two page scripts carry the page's nonce, so a
/// script written in a doc body does not run. The stylesheet ends with the
/// `@page` rule of [page].
String renderPage({
  required String title,
  required List<RenderedDoc> docs,
  PageSetup page = PageSetup.defaults,
}) {
  final toc = [for (final doc in docs) _tocItem(doc)].join('\n');
  final sections = [for (final doc in docs) _section(doc)].join('\n');
  final nonce = _newNonce();
  final buffer = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html>')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln(
      '<meta http-equiv="Content-Security-Policy" '
      'content="${_contentSecurityPolicy(nonce)}">',
    )
    ..writeln('<title>${escapeText(title)}</title>')
    ..writeln('<style>$pageStylesheet${page.pageRule}</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<nav class="toc"><ul>')
    ..writeln(toc)
    ..writeln('</ul></nav>')
    ..writeln(sections)
    ..writeln('<!-- $mermaidLicense -->')
    ..writeln(_script(nonce, mermaidScript))
    ..write(_script(nonce, 'mermaid.initialize({startOnLoad: true});'))
    ..writeln('</body></html>');
  return buffer.toString();
}

String _script(String nonce, String code) =>
    '<script nonce="$nonce">$code</script>';

String _tocItem(RenderedDoc doc) {
  final anchor = escapeText(doc.anchor);
  return '<li><a href="#$anchor">${escapeText(doc.tocEntry)}</a></li>';
}

String _section(RenderedDoc doc) =>
    '<section class="doc" id="${escapeText(doc.anchor)}">${doc.bodyHtml}'
    '</section>';
