import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/doc_html.dart';
import 'package:specstone_core/src/rendering/html_page.dart';
import 'package:specstone_core/src/rendering/mermaid_script.dart';
import 'package:test/test.dart';

String _page(List<RenderedDoc> docs, {String title = 'docs'}) =>
    renderPage(title: title, docs: docs);

const _statusRow = '<tr><th>status</th><td>planned</td></tr>';

const _start = 'mermaid.initialize({startOnLoad: true});</script>';

final _nonceAttribute = RegExp('<script nonce="([^"]+)">');
final _cspNonce = RegExp("script-src 'nonce-([^']+)'");

const _inlineScript = '<script>alert(1)</script>';
const _externalImage = '<img src="https://example.com/p.png">';
const _externalScript = '<script src="https://example.com/a.js"></script>';
const _hostileBody = '$_inlineScript$_externalImage$_externalScript';

const _oneDoc = RenderedDoc(
  anchor: 'doc-1',
  tocEntry: 'One',
  bodyHtml: '<h1>One</h1>',
);

String _body(Doc doc) => renderDocBody(
  doc,
  docPath: 'doc.md',
  anchors: const {'doc.md': 'doc-1'},
).html;

void main() {
  group('pageStylesheet', () {
    test('f05/us02/fr05: starts each doc on a new page', () {
      expect(pageStylesheet, contains('section.doc { break-before: page; }'));
    });

    test('f05/us02/fr02/e04, s03/inv13, NFR-Pr01: loads nothing and uses '
        'system fonts only', () {
      expect(pageStylesheet, isNot(contains('@import')));
      expect(pageStylesheet, isNot(contains('url(')));
      expect(
        pageStylesheet,
        contains(
          'font-family: system-ui, -apple-system, "Segoe UI", sans-serif',
        ),
      );
    });

    test('f05/us02/fr02/e02: labels a draft visibly and borders tables', () {
      expect(pageStylesheet, contains('.draft'));
      expect(pageStylesheet, contains('border:'));
    });
  });

  group('renderPage', () {
    test('f05/us02/fr02: lays out the head, the toc, and one section per '
        'doc in order', () {
      final html = _page(const [
        _oneDoc,
        RenderedDoc(anchor: 'doc-2', tocEntry: 'Two', bodyHtml: '<p>two</p>'),
      ], title: 'prds/features');

      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<meta charset="utf-8">'));
      expect(html, contains('<title>prds/features</title>'));
      expect(html, contains('<style>$pageStylesheet</style>'));
      expect(html, contains('<nav class="toc">'));
      expect(
        html.indexOf('<a href="#doc-1">One</a>'),
        lessThan(html.indexOf('<a href="#doc-2">Two</a>')),
      );
      expect(
        html.indexOf('<section class="doc" id="doc-1"><h1>One</h1></section>'),
        lessThan(
          html.indexOf('<section class="doc" id="doc-2"><p>two</p></section>'),
        ),
      );
      expect(
        html.indexOf('</nav>'),
        lessThan(html.indexOf('<section class="doc" id="doc-1">')),
      );
    });

    test('f05/us02/fr02/e05: escapes a toc entry and the title', () {
      final html = _page(const [
        RenderedDoc(anchor: 'doc-1', tocEntry: 'A <b> & "c"', bodyHtml: ''),
      ], title: '<x>');

      expect(
        html,
        contains('<a href="#doc-1">A &lt;b&gt; &amp; &quot;c&quot;'),
      );
      expect(html, contains('<title>&lt;x&gt;</title>'));
    });

    test('f05/us02/fr02/e03, s03/inv13: inlines mermaid once, the license '
        'comment first, then starts it', () {
      final html = _page(const [_oneDoc]);

      final license = html.indexOf('<!-- $mermaidLicense -->');
      final nonce = _cspNonce.firstMatch(html)!.group(1);
      final script = html.indexOf('<script nonce="$nonce">$mermaidScript');
      expect(license, isNonNegative);
      expect(script, greaterThan(license));
      expect(html.indexOf(mermaidScript), html.lastIndexOf(mermaidScript));
      expect(html, endsWith('$_start</body></html>\n'));
    });

    test('f05/us02/fr02/e04, s03/inv13, NFR-Pr01: the csp meta denies every '
        'fetch', () {
      final html = _page(const [_oneDoc]);

      final nonce = _cspNonce.firstMatch(html)!.group(1);
      expect(
        html,
        contains(
          '<meta http-equiv="Content-Security-Policy" '
          '''content="default-src 'none'; script-src 'nonce-$nonce'; '''
          '''style-src 'unsafe-inline'; img-src data:; font-src data:">''',
        ),
      );
      expect(html, isNot(contains("script-src 'unsafe-inline'")));
    });

    test('f05/us02/fr02/e04, s03/inv13, NFR-Pr01: a doc body with an inline '
        'script, an external image, and an external script follows the csp '
        'meta; only the two page scripts carry the csp nonce', () {
      final html = _page(const [
        RenderedDoc(anchor: 'doc-1', tocEntry: 'One', bodyHtml: _hostileBody),
      ]);

      final nonce = _cspNonce.firstMatch(html)!.group(1);
      final withoutMermaid = html.replaceAll(mermaidScript, '');
      final csp = withoutMermaid.indexOf('Content-Security-Policy');
      expect(csp, isNonNegative);
      expect(withoutMermaid.indexOf('<nav'), greaterThan(csp));
      expect(withoutMermaid.indexOf('<section'), greaterThan(csp));
      expect(withoutMermaid.indexOf(_hostileBody), greaterThan(csp));
      expect(withoutMermaid, contains('<script>alert(1)</script>'));
      expect(_nonceAttribute.allMatches(withoutMermaid), hasLength(2));
      expect(
        _nonceAttribute.allMatches(withoutMermaid).map((m) => m.group(1)),
        everyElement(nonce),
      );
      expect(withoutMermaid, contains('img-src data:'));
      expect(withoutMermaid, contains("default-src 'none'"));
    });

    test('f05/us02/fr02/e04, s03/inv13: every page gets a fresh nonce', () {
      final first = _cspNonce.firstMatch(_page(const [_oneDoc]))!.group(1);
      final second = _cspNonce.firstMatch(_page(const [_oneDoc]))!.group(1);

      expect(first, isNot(second));
      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{22}==$')));
    });

    test('f05/us02/fr02/e04, s03/inv13, NFR-Pr01: without the mermaid script '
        'nothing external is loaded', () {
      final html = _page(const [_oneDoc]).replaceAll(mermaidScript, '');

      expect(html, isNot(contains('<link')));
      expect(html, isNot(contains('src="http')));
      expect(html, isNot(contains('@import')));
      expect(html, isNot(contains('url(')));
    });
  });

  group('renderDocBody', () {
    test('f05/us02/fr02: shows the title, then the frontmatter table, then '
        'the body without its title line', () {
      final html = _body(
        Doc.parse('---\nstatus: planned\n---\n# F-05 — Rendering\n\nBody.\n'),
      );

      expect(html, startsWith('<h1>F-05 — Rendering</h1>'));
      expect(html, contains('<table class="frontmatter">$_statusRow</table>'));
      expect(
        html.indexOf('</h1>'),
        lessThan(html.indexOf('<table class="frontmatter">')),
      );
      expect(html, contains('<p>Body.</p>'));
      expect(html, isNot(contains('<h1>F-05 — Rendering</h1>\n<h1>')));
      expect(RegExp('<h1>').allMatches(html), hasLength(1));
    });

    test('f05/us02/fr02: escapes a key, a value, and the title', () {
      final html = _body(Doc.parse('---\n"a<b": x & y\n---\n# T <i>\n'));

      expect(html, contains('<h1>T &lt;i&gt;</h1>'));
      expect(html, contains('<tr><th>&quot;a&lt;b&quot;</th><td>x &amp; y'));
    });

    test('f05/us02/fr02: a keyless block is one row with an empty th and its '
        'whole text escaped, line breaks kept', () {
      final html = _body(
        Doc.parse('---\n  stray: <line>\nstatus: planned\n---\n# T\n'),
      );

      expect(
        html,
        contains(
          '<tr><th></th><td>  stray: &lt;line&gt;\n</td></tr>$_statusRow',
        ),
      );
    });

    test('f05/us02/fr02: a bare "# " title line is no title: no h1, and the '
        'line is not in the body', () {
      final html = _body(Doc.parse('# \n\nBody.\n'));

      expect(html, isNot(contains('<h1')));
      expect(html, contains('<p>Body.</p>'));
    });

    test('f05/us02/fr02: only the real title line leaves the body, not a '
        'fenced line equal to it', () {
      final html = _body(Doc.parse('```\n# T\n```\n# T\n\nBody.\n'));

      expect(html, startsWith('<h1>T</h1>'));
      expect(html, contains('<code># T\n</code>'));
      expect(RegExp('<h1>').allMatches(html), hasLength(1));
    });

    test('f05/us02/fr02: a doc without frontmatter has no table', () {
      final html = _body(Doc.parse('# T\n\nBody.\n'));

      expect(html, isNot(contains('<table')));
      expect(html, startsWith('<h1>T</h1>'));
    });

    test('f05/us02/fr02: a doc without a title line has no h1 and keeps its '
        'body', () {
      final html = _body(Doc.parse('Intro.\n\n## Section\ntext\n'));

      expect(html, isNot(contains('<h1>')));
      expect(html, contains('<p>Intro.</p>'));
      expect(html, contains('<h2>Section</h2>'));
    });

    test('f05/us02/fr02/e02: a draft shows its label after the table and '
        'before the body', () {
      final html = _body(Doc.parse('---\ndraft: true\n---\n# T\n\nBody.\n'));

      final table = html.indexOf('</table>');
      final label = html.indexOf('<p class="draft">Draft</p>');
      expect(label, greaterThan(table));
      expect(html.indexOf('<p>Body.</p>'), greaterThan(label));
    });

    test('f05/us02/fr02/e02: a doc that is not a draft has no label', () {
      final html = _body(Doc.parse('---\ndraft: false\n---\n# T\n\nBody.\n'));

      expect(html, isNot(contains('class="draft"')));
    });

    test('f05/us02/fr02/e03, s03/inv13: a mermaid fence becomes a '
        'pre.mermaid with its source escaped', () {
      final html = _body(
        Doc.parse('# T\n\n```mermaid\ngraph TD; A-->B\n```\n'),
      );

      expect(html, contains('<pre class="mermaid">graph TD; A--&gt;B</pre>'));
      expect(html, isNot(contains('language-mermaid')));
    });

    test('f05/us02/fr02: another fence stays a code block, and github '
        'flavored tables render', () {
      final html = _body(
        Doc.parse(
          '# T\n\n```dart\nvar a = 1;\n```\n\n| a | b |\n|---|---|\n'
          '| 1 | 2 |\n',
        ),
      );

      expect(html, contains('<pre><code class="language-dart">var a = 1;'));
      expect(html, contains('<table>'));
      expect(html, isNot(contains('class="mermaid"')));
    });
  });
}
