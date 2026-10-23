import 'package:markdown/markdown.dart';
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
}
