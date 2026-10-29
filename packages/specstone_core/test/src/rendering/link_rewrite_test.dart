import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/doc_html.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/html_build.dart';
import 'package:specstone_core/src/rendering/link_rewrite.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

const _featureDir = 'prds/features/f05_rendering';
const _storyA = '$_featureDir/us01_a/USER_STORY.md';
const _storyB = '$_featureDir/us02_b/USER_STORY.md';
const _frX = '$_featureDir/us01_a/functional_requirements/fr01_x.md';

String _story(String title, [String body = '']) =>
    '# $title\n\n## Summary\n$body\n\n## Acceptance Criteria\nDone.\n';

Future<String> _build(
  Map<String, String> docs, {
  required String target,
}) async {
  final root = await fixtureProject({
    for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
  });
  final project = DocsProject.open(
    templates: TemplateResolver(shippedFiles: fixturePackFiles()),
    workingDirectory: root,
    homeDirectory: null,
  );
  return buildHtml(
    project,
    project.resolveTarget(
      target,
      workingDirectory: root,
      defaultsToDocsRoot: true,
    ),
  ).html;
}

/// Returns the anchor of the section whose body starts with `<h1>[title]`.
String _anchorOf(String html, String title) {
  final match = RegExp(
    '<section class="doc" id="(doc-\\d+)"><h1>${RegExp.escape(title)}</h1>',
  ).firstMatch(html);
  expect(match, isNotNull, reason: 'no section titled "$title"');
  return match!.group(1)!;
}

String _rewritten(
  String markdown, {
  String docPath = 'a/b/c.md',
  Map<String, String> anchors = const {'a/b/c.md': 'doc-1', 'a/d.md': 'doc-2'},
}) {
  final nodes = Document(extensionSet: ExtensionSet.gitHubFlavored)
      .parse(markdown);
  rewriteLinks(nodes, docPath: docPath, anchors: anchors);
  return renderToHtml(nodes).trim();
}

void main() {
  test('f05/us02/fr03/e01: a relative link to a doc in the build, with or '
      'without a fragment, jumps to that doc', () async {
    final html = await _build({
      _storyA: _story('Story one'),
      _storyB: _story(
        'Story two',
        '[a](../us01_a/USER_STORY.md) [b](../us01_a/USER_STORY.md#s1)',
      ),
    }, target: 'docs/$_featureDir');

    final anchor = _anchorOf(html, 'Story one');
    expect(html, contains('<a href="#$anchor">a</a>'));
    expect(html, contains('<a href="#$anchor">b</a>'));
    expect(html, isNot(contains('USER_STORY.md#s1')));
  });

  test('f05/us02/fr03/e02: a link to a doc outside the build becomes an '
      'outside-link span with its docs-root path', () async {
    final html = await _build({
      _storyA: _story('Story one'),
      _frX:
          '# FR one\n\n## Statement\n[**Story**](../../us01_a/USER_STORY.md)\n',
    }, target: 'docs/$_frX');

    expect(
      html,
      contains(
        '<span class="outside-link"><strong>Story</strong> '
        '(<code>$_storyA</code>)</span>',
      ),
    );
    expect(html, isNot(contains('<a href="../../us01_a')));
  });

  test('f05/us02/fr03/e03, NFR-Pr01: http and https links stay, in any '
      'letter case', () async {
    final html = await _build({
      _storyA: _story(
        'Story one',
        '[one](https://example.com/spec) [two](HTTP://example.com)',
      ),
    }, target: 'docs/$_storyA');

    expect(html, contains('<a href="https://example.com/spec">one</a>'));
    expect(html, contains('<a href="HTTP://example.com">two</a>'));
    expect(html, isNot(contains('<span class="outside-link"')));
  });

  test('f05/us02/fr03: a bare #fragment names the doc itself', () async {
    final html = await _build({
      _storyA: _story('Story one'),
      _storyB: _story('Story two', 'See [scenario](#scenario-1).'),
    }, target: 'docs/$_featureDir');

    final anchor = _anchorOf(html, 'Story two');
    expect(html, contains('<a href="#$anchor">scenario</a>'));
  });

  test('f05/us02/fr03: a scheme other than http or https and a pop past the '
      'docs root become spans with the href as written', () async {
    final html = await _build({
      _storyA: _story(
        'Story one',
        '[mail](mailto:a@b.c) [up](../../../../../README.md)',
      ),
    }, target: 'docs/$_storyA');

    expect(
      html,
      contains(
        '<span class="outside-link">mail (<code>mailto:a@b.c</code>)</span>',
      ),
    );
    expect(
      html,
      contains(
        '<span class="outside-link">up '
        '(<code>../../../../../README.md</code>)</span>',
      ),
    );
  });

  group('rewriteLinks', () {
    test('f05/us02/fr03: a query is dropped and a percent escape decoded', () {
      expect(
        _rewritten('[x](../d.md?v=1#top)', docPath: 'a/b/c.md'),
        '<p><a href="#doc-2">x</a></p>',
      );
      expect(
        _rewritten(
          '[x](my%20doc.md)',
          docPath: 'a/b/c.md',
          anchors: {'a/b/my doc.md': 'doc-3'},
        ),
        '<p><a href="#doc-3">x</a></p>',
      );
    });

    test('f05/us02/fr03: an encoded slash never separates segments, so the '
        'link stays an outside-link span with the href as written', () {
      const anchors = {'x/c.md': 'doc-1', 'x/a/b.md': 'doc-2', 'd.md': 'doc-3'};

      for (final href in ['..%2Fd.md', 'a%2Fb.md', 'a%2fb.md']) {
        expect(
          _rewritten('[x]($href)', docPath: 'x/c.md', anchors: anchors),
          '<p><span class="outside-link">x (<code>$href</code>)</span></p>',
        );
      }
      expect(
        _rewritten('[x](a/b.md)', docPath: 'x/c.md', anchors: anchors),
        '<p><a href="#doc-2">x</a></p>',
      );
    });

    test('f05/us02/fr03: "." and empty segments resolve away', () {
      expect(_rewritten('[x](./../d.md)'), '<p><a href="#doc-2">x</a></p>');
      expect(_rewritten('[x](c.md)'), '<p><a href="#doc-1">x</a></p>');
    });

    test('f05/us02/fr03/e10, LP1: a link whose escape is not UTF-8 shows its '
        'path', () {
      expect(
        _rewritten('[x](%DB.md)', docPath: 'a/b/c.md'),
        '<p><span class="outside-link">x '
        '(<code>a/b/\u{FFFD}.md</code>)</span></p>',
      );
    });

    test('f05/us02/fr03: an unknown doc shows the resolved path, escaped', () {
      expect(
        _rewritten('[x](../e&f.md)'),
        '<p><span class="outside-link">x (<code>a/e&amp;f.md</code>)</span></p>',
      );
    });

    test('f05/us02/fr03: an absolute path and a network path stay as '
        'written in a span', () {
      expect(
        _rewritten('[x](/etc/hosts)'),
        contains('(<code>/etc/hosts</code>)'),
      );
      expect(_rewritten('[x](//host/p)'), contains('(<code>//host/p</code>)'));
    });

    test('f05/us02/fr03: links inside lists and tables are rewritten', () {
      final html = _rewritten('- [x](../d.md)\n- [y](https://e.com)');
      expect(html, contains('<a href="#doc-2">x</a>'));
      expect(html, contains('<a href="https://e.com">y</a>'));

      final table = _rewritten('| h |\n|---|\n| [x](../d.md) |');
      expect(table, contains('<a href="#doc-2">x</a>'));
    });
  });

  group('ids inside a doc', () {
    const footnote = 'text[^1]\n\n[^1]: note\n';
    const rawTop = '<a id="top"></a>\n\n[up](#top)\n';

    String body(String markdown, {Map<String, String>? anchors}) =>
        renderDocBody(
          Doc.parse(markdown),
          docPath: 'a/b/c.md',
          anchors: anchors ?? const {'a/b/c.md': 'doc-1', 'a/d.md': 'doc-2'},
        ).html;

    test('f05/us02/fr03: every id is prefixed with the doc anchor, and the '
        'footnote links follow', () {
      final html = body(footnote);

      expect(html, contains('<a href="#doc-1-fn-1" id="doc-1-fnref-1">'));
      expect(html, contains('<li id="doc-1-fn-1">'));
      expect(
        html,
        contains('<a href="#doc-1-fnref-1" class="footnote-backref">'),
      );
      expect(html, isNot(contains('id="fn-1"')));
      expect(html, isNot(contains('id="fnref-1"')));
    });

    test('f05/us02/fr03: a raw html id is prefixed and a bare fragment naming '
        'it points at the prefixed id', () {
      final html = body('<div id="box">x</div>\n\n$rawTop');

      expect(html, contains('<div id="doc-1-box">'));
      expect(html, contains('<a id="doc-1-top"></a>'));
      expect(html, contains('<a href="#doc-1-top">up</a>'));
    });

    test('f05/us02/fr03: a bare fragment that names no id stays on the doc '
        'anchor', () {
      final html = body('$footnote\n[a](#fn-1) [b](#nope) [c](#)');

      expect(html, contains('<a href="#doc-1-fn-1">a</a>'));
      expect(html, contains('<a href="#doc-1">b</a>'));
      expect(html, contains('<a href="#doc-1">c</a>'));
    });

    test('f05/us02/fr03: a percent-encoded fragment names the id it decodes '
        'to', () {
      final html = body('<a id="caf\u00e9"></a>\n\n[a](#caf%C3%A9)\n');

      expect(html, contains('<a id="doc-1-caf\u00e9"></a>'));
      expect(html, contains('<a href="#doc-1-caf%C3%A9">a</a>'));
    });

    test('f05/us02/fr03: a fragment with broken percent-encoding names no id '
        'and goes to the doc anchor', () {
      final html = body('<a id="x"></a>\n\n[a](#x%zz) [b](#%FF) [c](#x%)\n');

      expect(html, isNot(contains('href="#doc-1-')));
      expect('href="#doc-1"'.allMatches(html), hasLength(3));
    });

    test('f05/us02/fr03: a link to another doc drops its fragment even when '
        'it names an id', () {
      final html = body('$footnote\n[a](../d.md#fn-1) [b](c.md#fn-1)');

      expect(html, contains('<a href="#doc-2">a</a>'));
      expect(html, contains('<a href="#doc-1">b</a>'));
    });

    test('f05/us02/fr03: an id written in code or inline code is shown as '
        'written and no link follows it', () {
      final html = body(
        '<a id="top"></a>\n\n```html\n<a id="x" href="#top">\n```\n\n'
        '`<a id="y" href="#top">` [up](#top)\n',
      );

      expect(html, contains('<a id="doc-1-top"></a>'));
      expect(
        html,
        contains('&lt;a id=&quot;x&quot; href=&quot;#top&quot;&gt;'),
      );
      expect(
        html,
        contains('&lt;a id=&quot;y&quot; href=&quot;#top&quot;&gt;'),
      );
      expect(html, contains('<a href="#doc-1-top">up</a>'));
      expect(html, isNot(contains('doc-1-x')));
      expect(html, isNot(contains('doc-1-y')));
    });

    test('f05/us02/fr03: a doc with no anchor keeps its ids and its bare '
        'fragment becomes an outside-link span', () {
      final html = body(
        '<a id="top"></a>\n\n[up](#top)\n',
        anchors: const {'a/d.md': 'doc-2'},
      );

      expect(html, contains('<a id="top"></a>'));
      expect(
        html,
        contains(
          '<span class="outside-link">up (<code>a/b/c.md</code>)</span>',
        ),
      );
    });

    test('f05/us02/fr03/e04, s03/inv23, FM8: single-quoted, unquoted, and '
        'upper-case ids are prefixed and their fragments follow', () {
      final html = body(
        "<div id='a'>x</div>\n<div id=b>y</div>\n<div ID=\"c\">z</div>\n\n"
        '[1](#a) [2](#b) [3](#c)\n',
      );

      expect(html, contains("<div id='doc-1-a'>"));
      expect(html, contains('<div id=doc-1-b>'));
      expect(html, contains('<div ID="doc-1-c">'));
      expect(html, contains('<a href="#doc-1-a">1</a>'));
      expect(html, contains('<a href="#doc-1-b">2</a>'));
      expect(html, contains('<a href="#doc-1-c">3</a>'));
    });

    test('f05/us02/fr03/e08, s03/inv23, FM8: a link to another doc keeps its '
        'anchor when the body holds a raw id equal to it', () {
      final html = body('<a id="doc-2"></a>\n\n[d](../d.md)\n');

      expect(html, contains('<a href="#doc-2">d</a>'));
      expect(html, contains('<a id="doc-1-doc-2"></a>'));
    });

    test('f05/us02/fr03/e07, s03/inv18, s03/inv23, FM8: an id in a tag the tag '
        'filter escapes is text, not an id', () {
      final html = body('x <textarea id="t"> y\n\n[go](#t)\n');

      expect(html, contains('&lt;textarea id="t">'));
      expect(html, contains('<a href="#doc-1">go</a>'));
      expect(html, isNot(contains('doc-1-t')));
    });

    test('f05/us02/fr03/e07, s03/inv23, FM8: an id inside an html comment is '
        'no id', () {
      final html = body('<!-- <a id="c"></a> -->\n\n[go](#c)\n');

      expect(html, contains('<!-- <a id="c"></a> -->'));
      expect(html, contains('<a href="#doc-1">go</a>'));
    });

    test('f05/us02/fr03/e07, s03/inv23, FM8: <!--> is a comment closed at '
        'once, so an id after it is scoped', () {
      final html = body('<!-->\n\n<a id="c"></a>\n\n[go](#c)\n');

      expect(html, contains('id="doc-1-c"'));
      expect(html, contains('<a href="#doc-1-c">go</a>'));
    });

    test('f05/us02/fr03/e07, s03/inv23, FM8: <!---> is a comment closed at '
        'once, so an id after it is scoped', () {
      final html = body('<!--->\n\n<a id="c"></a>\n\n[go](#c)\n');

      expect(html, contains('id="doc-1-c"'));
      expect(html, contains('<a href="#doc-1-c">go</a>'));
    });

    test('f05/us02/fr03/e07, s03/inv23, FM8: a comment ends at --!>, so an '
        'id after it is scoped', () {
      final html = body('<!-- note --!>\n<a id="c"></a>\n-->\n\n[go](#c)\n');

      expect(html, contains('id="doc-1-c"'));
      expect(html, contains('<a href="#doc-1-c">go</a>'));
    });

    test('f05/us02/fr03/e04, s03/inv23, FM8: a quoted > before the id does '
        'not end the tag', () {
      final html = body('<div title="a>b" id="q"></div>\n\n[go](#q)\n');

      expect(html, contains('id="doc-1-q"'));
      expect(html, contains('<a href="#doc-1-q">go</a>'));
    });

    test('f05/us02/fr03/e04, s03/inv23, FM8: of a repeated attribute name the '
        'first wins', () {
      final html = body('<div id="a" id="b">x</div>\n\n[1](#a) [2](#b)\n');

      expect(html, contains('<div id="doc-1-a" id="b">'));
      expect(html, contains('<a href="#doc-1-a">1</a>'));
      expect(html, contains('<a href="#doc-1">2</a>'));
    });

    test('f05/us02/fr03/e07, s03/inv23, FM8: an end tag, a declaration, and a '
        'processing instruction hold no id', () {
      final html = body(
        '<div id="a">x</div>\n\n</p id="e">\n\n<!DOCTYPE html id="d">\n\n'
        '<?pi id="p"?>\n\n[1](#e) [2](#d) [3](#p)\n',
      );

      expect(html, contains('<div id="doc-1-a">'));
      expect(html, contains('id="e"'));
      expect(html, contains('id="d"'));
      expect(html, contains('id="p"'));
      expect(html, isNot(contains('doc-1-e')));
      expect(html, isNot(contains('doc-1-d')));
      expect(html, isNot(contains('doc-1-p')));
      expect('href="#doc-1"'.allMatches(html), hasLength(3));
    });

    test('f05/us02/fr03/e04, s03/inv23, FM8: a single-quoted and an upper-case '
        'href reach the scoped fragment', () {
      final html = body(
        '<div id="a">x</div>\n\n<a href=\'#a\'>1</a> <a HREF="#a">2</a>\n',
      );

      expect(html, contains("<a href='#doc-1-a'>1</a>"));
      expect(html, contains('<a HREF="#doc-1-a">2</a>'));
    });

    test('f05/us02/fr03/e07, s03/inv23, FM8: an unterminated comment leaves '
        'the rest of the text unchanged', () {
      final html = body('<div id="a">x</div>\n\n<!-- <a id="c"></a>\n');

      expect(html, contains('<div id="doc-1-a">'));
      expect(html, contains('<!-- <a id="c"></a>'));
      expect(html, isNot(contains('doc-1-c')));
    });

    test('f05/us02/fr03/e04, s03/inv23, FM8: an unterminated quoted value '
        'leaves the rest of the text unchanged', () {
      final html = body('<div id="a">x</div>\n\n<div title="oops id="b">\n');

      expect(html, contains('<div id="doc-1-a">'));
      expect(html, contains('<div title="oops id="b">'));
      expect(html, isNot(contains('doc-1-b')));
    });

    test(
      'f05/us02/fr03: two docs with a footnote [^1] and a raw id get '
      'distinct ids and every in-page link lands on an id of the page',
      () async {
        const both = '$footnote\n$rawTop';
        final html = await _build({
          _storyA: _story('Story one', both),
          _storyB: _story('Story two', both),
        }, target: 'docs/$_featureDir');

        final ids = [
          for (final m in RegExp(' id="([^"]+)"').allMatches(html)) m.group(1)!,
        ];
        expect(ids.toSet().length, ids.length, reason: 'ids are unique');
        final one = _anchorOf(html, 'Story one');
        final two = _anchorOf(html, 'Story two');
        for (final anchor in [one, two]) {
          expect(
            ids,
            containsAll(['$anchor-fn-1', '$anchor-fnref-1', '$anchor-top']),
          );
          expect(html, contains('href="#$anchor-fn-1"'));
          expect(html, contains('href="#$anchor-fnref-1"'));
          expect(html, contains('href="#$anchor-top"'));
        }
        final links = [
          for (final m in RegExp('href="#([^"]+)"').allMatches(html))
            m.group(1)!,
        ];
        expect(links.where((link) => !ids.contains(link)), isEmpty);
      },
    );
  });
}
