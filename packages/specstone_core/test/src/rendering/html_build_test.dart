import 'dart:io';

import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/html_build.dart';
import 'package:specstone_core/src/rendering/html_page.dart';
import 'package:specstone_core/src/rendering/mermaid_script.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

const _zeta = '''
id: zeta
description: A second doc type on the same paths.
path: prds/features/f{nn}_rendering/FEATURE.md
''';

const _featureDir = 'prds/features/f05_rendering';
const _featurePath = '$_featureDir/FEATURE.md';
const _storyPath = '$_featureDir/us01_a/USER_STORY.md';
const _frPath = '$_featureDir/us01_a/functional_requirements/fr02_y.md';

const _frDocPath = '$_featureDir/us01_a/functional_requirements/fr02_y.md';
const _frNoTitlePath = '$_featureDir/us01_a/functional_requirements/fr03_z.md';
const _feature =
    '# F-05 — Rendering\n\n## Feature name\n- **Human:** Rendering\n\n'
    '## Feature goal\n- **why:** share docs\n';
const _story =
    '# Story one\n\n## Summary\nFormat docs.\n\n'
    '## Acceptance Criteria\nDone.\n';
const _statusRow = '<tr><th>status</th><td>planned</td></tr>';

Future<HtmlBuild> _build(
  Map<String, String> docs, {
  String? target,
  Map<String, String> extra = const {},
  void Function(Directory root)? beforeBuild,
}) async {
  final root = await fixtureProject({
    for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
  });
  beforeBuild?.call(root);
  final project = DocsProject.open(
    templates: TemplateResolver(shippedFiles: fixturePackFiles(extra: extra)),
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
  );
}

void main() {
  test('f05/us02/fr02, f05/us02/fr01: a folder renders its docs in tree '
      'order, each in a numbered section the toc links to', () async {
    final build = await _build({
      _featurePath: _feature,
      _storyPath: _story,
    }, target: 'docs/$_featureDir');

    final html = build.html;
    expect(
      html.indexOf('<a href="#doc-1">F-05 — Rendering</a>'),
      isNonNegative,
    );
    expect(
      html.indexOf('<a href="#doc-1">F-05 — Rendering</a>'),
      lessThan(html.indexOf('<a href="#doc-2">Story one</a>')),
    );
    expect(
      html.indexOf('<section class="doc" id="doc-1">'),
      lessThan(html.indexOf('<section class="doc" id="doc-2">')),
    );
    expect(html, contains('<title>$_featureDir</title>'));
    expect(build.warnings, isEmpty);
  });

  test('f05/us02/fr01: the docs root titles the page docs', () async {
    final build = await _build({_featurePath: _feature});

    expect(build.html, contains('<title>docs</title>'));
  });

  test(
    'f05/us02/fr02: shows the frontmatter table right after the h1',
    () async {
      final build = await _build({
        _featurePath: '---\nstatus: planned\n---\n$_feature',
      });

      expect(
        build.html,
        contains(
          '<h1>F-05 — Rendering</h1>\n'
          '<table class="frontmatter">$_statusRow</table>',
        ),
      );
    },
  );

  test('f05/us02/fr02/e01, s03/inv11: renders sections as on disk and '
      'warns the doc does not match its template', () async {
    final build = await _build({
      _featurePath:
          '# F-05\n\n## Feature goal\n- **why:** share docs\n\n'
          '## Feature name\n- **Human:** Rendering\n',
    });

    expect(
      build.html.indexOf('Feature goal'),
      lessThan(build.html.indexOf('Feature name')),
    );
    expect(build.warnings, [
      'docs/$_featurePath does not match its template; run specstone format',
    ]);
  });

  test('f05/us02/fr02/e01, s03/inv11: a doc with an unknown header is '
      'rendered, with the same warning', () async {
    final build = await _build({_storyPath: '$_story\n## Notes\nx\n'});

    expect(build.html, contains('<h2>Notes</h2>'));
    expect(build.warnings, [
      'docs/$_storyPath does not match its template; run specstone format',
    ]);
  });

  test('f05/us02/fr02/e01, s03/inv11: CRLF text that only differs by line '
      'ending is a doc that matches', () async {
    final build = await _build({
      _featurePath: _feature.replaceAll('\n', '\r\n'),
    });

    expect(build.warnings, isEmpty);
    expect(build.html, contains('<h1>F-05 — Rendering</h1>'));
  });

  test('f05/us02/fr02/e02: a draft shows its label after the frontmatter '
      'table and before the body', () async {
    final build = await _build({
      _featurePath: '---\ndraft: true\n---\n$_feature',
    });

    final html = build.html;
    expect(
      html.indexOf('<p class="draft">Draft</p>'),
      greaterThan(html.indexOf('</table>')),
    );
    expect(
      html.indexOf('<p class="draft">Draft</p>'),
      lessThan(html.indexOf('<h2>Feature name</h2>')),
    );
  });

  test('f05/us02/fr02/e03, s03/inv13: a mermaid block is a pre.mermaid and '
      'the script appears once', () async {
    final build = await _build({
      _featurePath: '$_feature\n```mermaid\ngraph TD; A-->B\n```\n',
    });

    final html = build.html;
    expect(html, contains('<pre class="mermaid">graph TD; A--&gt;B</pre>'));
    expect(html.indexOf(mermaidScript), html.lastIndexOf(mermaidScript));
    expect(
      html.indexOf('<!-- $mermaidLicense -->'),
      lessThan(html.indexOf(mermaidScript)),
    );
  });

  test('f05/us02/fr02/e04, s03/inv13, NFR-Pr01: nothing external is '
      'loaded, and the csp denies everything by default', () async {
    final build = await _build({_featurePath: _feature});

    final html = build.html.replaceAll(mermaidScript, '');
    expect(html, isNot(contains('<link')));
    expect(html, isNot(contains('src="http')));
    expect(html, isNot(contains('@import')));
    expect(html, isNot(contains('url(')));
    expect(html, contains("default-src 'none'"));
  });

  test('f05/us02/fr02/e05: a toc entry is the title line, else the path '
      'from the docs root', () async {
    final build = await _build({
      _frPath: '# List doc types\n\n## Statement\nx\n',
      _frNoTitlePath: '## Statement\nx\n',
    }, target: 'docs/$_featureDir');

    expect(build.html, contains('<a href="#doc-1">List doc types</a>'));
    expect(build.html, contains('<a href="#doc-2">$_frNoTitlePath</a>'));
  });

  test('f05/us02/fr01/e04, s03/inv12: a doc no type matches is skipped with '
      'one warning, and a dot file with none', () async {
    final build = await _build({
      _featurePath: _feature,
      '$_featureDir/notes.md': 'notes\n',
      '$_featureDir/.DS_Store': 'x',
    }, target: 'docs/$_featureDir');

    final html = build.html.replaceAll(mermaidScript, '');
    expect(html, isNot(contains('notes')));
    expect(html, isNot(contains('DS_Store')));
    expect(RegExp('<section class="doc"').allMatches(html), hasLength(1));
    expect(build.warnings, [
      'docs/$_featureDir/notes.md: no doc type matches this path; skipped',
    ]);
  });

  test('f05/us02/fr01/e05, s03/inv12: a doc two types match is skipped '
      'with the warning, the rest render', () async {
    final build = await _build(
      {_featurePath: _feature, _storyPath: _story},
      target: 'docs/$_featureDir',
      extra: {'zeta.yaml': _zeta},
    );

    expect(build.html, isNot(contains('F-05 — Rendering')));
    expect(build.html, contains('<a href="#doc-1">Story one</a>'));
    expect(build.warnings, [
      'docs/$_featurePath: doc types feature, zeta match this path; skipped',
    ]);
  });

  test('s03/inv12: a doc that is not UTF-8 is skipped with its warning, '
      'and the next anchor is not used up', () async {
    final build = await _build(
      {_featurePath: _feature, _storyPath: _story},
      target: 'docs/$_featureDir',
      beforeBuild: (root) =>
          File('${root.path}/docs/$_featurePath')
              .writeAsBytesSync([0xFF, 0xFE]),
    );

    expect(build.warnings, ['docs/$_featurePath: not UTF-8 text; skipped']);
    expect(build.html, contains('<a href="#doc-1">Story one</a>'));
    expect(build.html, isNot(contains('doc-2')));
  });

  test('f05/us02/fr01: a file target renders only that doc, titled by its '
      'path', () async {
    final build = await _build({
      _featurePath: _feature,
      _storyPath: _story,
    }, target: 'docs/$_storyPath');

    expect(build.html, contains('<title>$_storyPath</title>'));
    expect(build.html, contains('<a href="#doc-1">Story one</a>'));
    expect(build.html, isNot(contains('F-05 — Rendering')));
  });

  test('f05/us03/fr02: every built page carries the page-break rule', () async {
    final build = await _build({_featurePath: _feature});

    expect(build.html, contains(pageStylesheet));
  });

  test('f05/us02/fr01: a folder where no doc type matches any file builds an '
      'empty table of contents, one warning per file', () async {
    final build = await _build({
      '$_featureDir/notes.md': 'notes\n',
      '$_featureDir/todo.md': 'todo\n',
    }, target: 'docs/$_featureDir');

    final html = build.html.replaceAll(mermaidScript, '');
    expect(html, contains('<nav class="toc">'));
    expect(html, isNot(contains('<li>')));
    expect(html, isNot(contains('<section')));
    expect(build.warnings, [
      'docs/$_featureDir/notes.md: no doc type matches this path; skipped',
      'docs/$_featureDir/todo.md: no doc type matches this path; skipped',
    ]);
  });

  test('f05/us02/fr02/e04, s03/inv13, NFR-Pr01: an external image, an external '
      'script, and an inline script in a doc follow the csp meta, which '
      'blocks them', () async {
    final build = await _build({
      _featurePath:
          '$_feature\n<img src="https://example.com/p.png">\n\n'
          '<script src="https://example.com/a.js"></script>\n\n'
          '<script>alert(1)</script>\n',
    });

    final html = build.html.replaceAll(mermaidScript, '');
    final csp = html.indexOf('Content-Security-Policy');
    expect(html.indexOf('https://example.com/p.png'), greaterThan(csp));
    expect(html.indexOf('https://example.com/a.js'), greaterThan(csp));
    expect(html, contains('img-src data:'));
    expect(html, contains("default-src 'none'"));
    expect(html, contains('&lt;script>alert(1)&lt;/script>'));
    expect(html, contains('&lt;script src="https://example.com/a.js">'));
    expect(html, isNot(contains('<script>alert(1)</script>')));
    expect(RegExp('<script nonce="').allMatches(html), hasLength(2));
  });

  test('f05/us02/fr02: an unclosed <title> in a doc is shown as text and the '
      'next doc still gets its section', () async {
    final build = await _build({
      _featurePath: "# F-05\n\nSet the page's <title> from the doc.\n",
      _storyPath: _story,
    }, target: 'docs/$_featureDir');

    final html = build.html;
    expect(html, contains("Set the page's &lt;title> from the doc."));
    expect(
      RegExp('<title>').allMatches(html.replaceAll(mermaidScript, '')),
      hasLength(1),
    );
    expect(html, contains('<section class="doc" id="doc-2">'));
    expect(html, contains('<h1>Story one</h1>'));
  });

  test('f05/us02/fr02: an unclosed <title lang=x> or <STYLE media=print> in '
      'prose is shown as text and every later doc keeps its section', () async {
    final build = await _build({
      _featurePath:
          '# F-05\n\nSet the <title lang=x> from the doc.\n\n'
          'Then <STYLE media=print> applies.\n\nAnd a <textarea\nrows=2>.\n',
      _storyPath: _story,
      _frPath: '# Req\n\n## Statement\nx\n',
    }, target: 'docs/$_featureDir');

    final html = build.html;
    expect(html, contains('Set the &lt;title lang=x> from the doc.'));
    expect(html, contains('Then &lt;STYLE media=print> applies.'));
    expect(html, contains('And a &lt;textarea\nrows=2>.'));
    final page = html.replaceAll(mermaidScript, '');
    expect(RegExp('<title').allMatches(page), hasLength(1));
    expect(RegExp('<style').allMatches(page), hasLength(1));
    expect(RegExp('<textarea').allMatches(page), isEmpty);
    expect(html, contains('<section class="doc" id="doc-3">'));
    expect(html, contains('<h1>Req</h1>'));
  });

  test('f05/us02/fr02: a fenced code block that shows <script> still renders '
      'as code', () async {
    final build = await _build({
      _featurePath:
          '# F-05\n\n```html\n<script>alert(1)</script>\n<title lang=x>\n```\n',
    }, target: 'docs/$_featurePath');

    expect(
      build.html,
      contains(
        [
          '<pre><code class="language-html">',
          '&lt;script&gt;alert(1)&lt;/script&gt;\n',
          '&lt;title lang=x&gt;\n</code></pre>',
        ].join(),
      ),
    );
  });

  test('f05/us02/fr02/e05: a bare "# " title line is no title, so the toc '
      'entry is the path and the body has no h1', () async {
    final build = await _build({
      _frPath: '# \n\n## Statement\nx\n',
    }, target: 'docs/$_featureDir');

    final html = build.html.replaceAll(mermaidScript, '');
    expect(html, contains('<a href="#doc-1">$_frDocPath</a>'));
    expect(html, isNot(contains('<h1')));
  });
}
