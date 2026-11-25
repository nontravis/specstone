import 'dart:io';

import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/html_build.dart';
import 'package:specstone_core/src/rendering/mermaid_script.dart';
import 'package:specstone_core/src/rendering/page_setup.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';
import '../../helpers/posix_modes.dart';

const _zeta = '''
id: zeta
description: A second doc type on the same paths.
path: prds/features/f{nn}_rendering/FEATURE.md
''';

const _recordType = '''
id: implementation
description: One feature record.
path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md
parent: feature
per_target: true
fields:
  - id: statuses
    type: record_status
    list: true
''';

const _featureDir = 'prds/features/f05_rendering';
const _featurePath = '$_featureDir/FEATURE.md';
const _storyPath = '$_featureDir/us01_a/USER_STORY.md';
const _frPath = '$_featureDir/us01_a/functional_requirements/fr02_y.md';

const _frDocPath = '$_featureDir/us01_a/functional_requirements/fr02_y.md';
const _frNoTitlePath = '$_featureDir/us01_a/functional_requirements/fr03_z.md';
const _feature =
    '# F-05 — Rendering\n\n## Feature name\n\n- **Human:** Rendering\n\n'
    '## Feature goal\n\n- **why:** share docs\n';
const _story =
    '# Story one\n\n## Summary\n\nFormat docs.\n\n'
    '## Acceptance Criteria\n\nDone.\n';

Future<HtmlBuild> _build(
  Map<String, String> docs, {
  String? target,
  Map<String, String> extra = const {},
  PageSetup page = PageSetup.defaults,
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
    page: page,
  );
}

void main() {
  test('buildHtml carries the page it is given', () async {
    final build = await _build({
      _featurePath: _feature,
    }, page: PageSetup.parse(paper: 'legal'));

    expect(
      build.html,
      contains('@page { size: legal portrait; margin: 20mm; }'),
    );
  });

  // ignore: lines_longer_than_80_chars -- the test name stays one literal
  test('a folder renders its docs in tree order, each in a numbered section the toc links to', () async {
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

    final docsRoot = await _build({_featurePath: _feature});
    expect(docsRoot.html, contains('<title>docs</title>'));
  });

  test(
    'renders sections as on disk and warns the doc does not match its template',
    () async {
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

      final cases = [
        (
          reason: 'layout drift',
          path: _featurePath,
          text:
              '# F-05\n\n## Feature name\n- **Human:** Rendering\n\n'
              '## Feature goal\n\n- **why:** share docs\n',
          shown: '<h2 id="doc-1-feature-name">Feature name</h2>',
        ),
        (
          reason: 'padded table cells',
          path: _storyPath,
          text:
              '$_story\n| Name  | Done |\n|-------|------|\n| Alpha | yes  |\n',
          shown: '<td>Alpha</td>',
        ),
        (
          reason: 'unknown header',
          path: _storyPath,
          text: '$_story\n## Notes\nx\n',
          shown: '<h2 id="doc-1-notes">Notes</h2>',
        ),
      ];

      for (final (:reason, :path, :text, :shown) in cases) {
        final drifted = await _build({path: text});

        expect(drifted.html, contains(shown), reason: reason);
        expect(drifted.warnings, [
          'docs/$path does not match its template; run specstone format',
        ], reason: reason);
      }

      final compact = await _build({
        _storyPath: '$_story\n| Name | Done |\n|---|---|\n| Alpha | yes |\n',
      });
      expect(compact.warnings, isEmpty);
    },
  );

  test('a doc lacking a section '
      'raises no template warning', () async {
    final build = await _build({
      _featurePath: '# F-05\n\n## Feature name\n\n- **Human:** Rendering\n',
    });

    expect(build.warnings, isEmpty);
  });

  test('CRLF text that only differs by line '
      'ending is a doc that matches', () async {
    final build = await _build({
      _featurePath: _feature.replaceAll('\n', '\r\n'),
    });

    expect(build.warnings, isEmpty);
    expect(
      build.html,
      contains('<h1 id="doc-1-f-05--rendering">F-05 — Rendering</h1>'),
    );
  });

  test('a toc entry is the title line, else the path '
      'from the docs root', () async {
    final build = await _build({
      _frPath: '# List doc types\n\n## Statement\nx\n',
      _frNoTitlePath: '## Statement\nx\n',
    }, target: 'docs/$_featureDir');

    expect(build.html, contains('<a href="#doc-1">List doc types</a>'));
    expect(build.html, contains('<a href="#doc-2">$_frNoTitlePath</a>'));
  });

  test('a doc no type matches is skipped with '
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

  test('a doc two types match is skipped '
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

  test('a doc that is not UTF-8 is skipped with its warning, '
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

  test('a file target renders only that doc, titled by its '
      'path', () async {
    final build = await _build({
      _featurePath: _feature,
      _storyPath: _story,
    }, target: 'docs/$_storyPath');

    expect(build.html, contains('<title>$_storyPath</title>'));
    expect(build.html, contains('<a href="#doc-1">Story one</a>'));
    expect(build.html, isNot(contains('F-05 — Rendering')));
  });

  test('a folder where no doc type matches any file builds an '
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

  test('an external image, an external '
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

  // ignore: lines_longer_than_80_chars, one literal so check finds the test
  test('an unclosed <title> in a doc is shown as text and the next doc still gets its section', () async {
    const endTags =
        'End &lt;/xmp> and &lt;/iframe> and &lt;/noembed> and &lt;/noframes> '
        'and &lt;/plaintext>.';
    final cases = [
      (
        reason: 'title',
        docs: {
          _featurePath: "# F-05\n\nSet the page's <title> from the doc.\n",
          _storyPath: _story,
        },
        shown: [
          "Set the page's &lt;title> from the doc.",
          '<section class="doc" id="doc-2">',
          '<h1 id="doc-2-story-one">Story one</h1>',
        ],
        counts: {'<title>': 1},
      ),
      (
        reason: 'title with an attribute, style, textarea',
        docs: {
          _featurePath:
              '# F-05\n\nSet the <title lang=x> from the doc.\n\n'
              'Then <STYLE media=print> applies.\n\n'
              'And a <textarea\nrows=2>.\n',
          _storyPath: _story,
          _frPath: '# Req\n\n## Statement\nx\n',
        },
        shown: [
          'Set the &lt;title lang=x> from the doc.',
          'Then &lt;STYLE media=print> applies.',
          'And a &lt;textarea\nrows=2>.',
          '<section class="doc" id="doc-3">',
          '<h1 id="doc-3-req">Req</h1>',
        ],
        counts: {'<title': 1, '<style': 1, '<textarea': 0},
      ),
      (
        reason: 'noscript, template and their end tags',
        docs: {
          _featurePath:
              '# F-05\n\nShow <noscript> as text.\n\n'
              'Then <TEMPLATE id=x> and </template> and </noscript>.\n',
          _storyPath: _story,
        },
        shown: [
          'Show &lt;noscript> as text.',
          'Then &lt;TEMPLATE id=x> and &lt;/template> and &lt;/noscript>.',
          '<section class="doc" id="doc-2">',
        ],
        counts: {'</?noscript': 0, '</?template': 0},
      ),
      (
        reason: 'xmp, iframe, noembed, noframes, plaintext and end tags',
        docs: {
          _featurePath:
              '# F-05\n\nShow <xmp> and <IFRAME src=x> as text.\n\n'
              'Then <noembed> and <NOFRAMES lang=x> and <plaintext>.\n\n'
              'End </xmp> and </iframe> and </noembed> and </noframes> and '
              '</plaintext>.\n',
          _storyPath: _story,
        },
        shown: [
          'Show &lt;xmp> and &lt;IFRAME src=x> as text.',
          'Then &lt;noembed> and &lt;NOFRAMES lang=x> and &lt;plaintext>.',
          endTags,
          '<section class="doc" id="doc-2">',
        ],
        counts: {
          for (final name in ['xmp', 'iframe', 'noembed', 'noframes'])
            '</?$name': 0,
          '</?plaintext': 0,
        },
      ),
    ];

    for (final (:reason, :docs, :shown, :counts) in cases) {
      final build = await _build(docs, target: 'docs/$_featureDir');

      final html = build.html;
      final page = html.replaceAll(mermaidScript, '');
      for (final text in shown) {
        expect(html, contains(text), reason: reason);
      }
      for (final MapEntry(:key, :value) in counts.entries) {
        expect(
          RegExp(key, caseSensitive: false).allMatches(page),
          hasLength(value),
          reason: '$reason: $key',
        );
      }
    }
  });

  test('a fenced code block that shows <script> still renders '
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

  test('a bare "# " title line is no title, so the toc '
      'entry is the path and the body has no h1', () async {
    final build = await _build({
      _frPath: '# \n\n## Statement\nx\n',
    }, target: 'docs/$_featureDir');

    final html = build.html.replaceAll(mermaidScript, '');
    expect(html, contains('<a href="#doc-1">$_frDocPath</a>'));
    expect(html, isNot(contains('<h1')));
  });

  group('a doc the markdown parser fails on', () {
    const message =
        'docs/$_frPath: the markdown parser failed; its body is shown as '
        'plain text';
    const draftRow = '<tr><th>draft</th><td>true</td></tr>';

    test('renders its body as plain text and warns', () async {
      final build = await _build({
        _frPath: '# Req\n\n## A\nx < y [s](b.md)\n\n[a]:<b\\',
      }, target: 'docs/$_featureDir');

      final html = build.html.replaceAll(mermaidScript, '');
      expect(html, contains('<h1>Req</h1>'));
      expect(html, matches(RegExp(r'<pre>[^]*x &lt; y \[s\]\(b\.md\)[^]*')));
      expect(html, matches(RegExp(r'<pre>[^]*\[a\]:&lt;b\\[^]*</pre>')));
      expect(html, isNot(contains('<a href="b.md"')));
      expect(build.warnings, contains(message));

      final nested = await _build({
        _frPath: '# Req\n\n${'> ' * 2000}x',
      }, target: 'docs/$_featureDir');

      final nestedHtml = nested.html.replaceAll(mermaidScript, '');
      expect(nestedHtml, contains('<h1>Req</h1>'));
      expect(nestedHtml, contains('<pre>\n${'&gt; ' * 2000}x</pre>'));
      expect(nested.warnings, contains(message));
    });

    test('keeps the frontmatter table and the draft '
        'label', () async {
      final build = await _build({
        _frPath: '---\ndraft: true\n---\n# Req\n\n[a]:<b\\',
      }, target: 'docs/$_featureDir');

      final html = build.html.replaceAll(mermaidScript, '');
      expect(
        html,
        contains(
          [
            '<h1>Req</h1>',
            '<table class="frontmatter">$draftRow</table>',
            '<p class="draft">Draft</p>',
            '<pre>\n[a]:&lt;b\\</pre>',
          ].join('\n'),
        ),
      );
    });
  });

  group('an unreadable path', () {
    test('a doc that cannot be read is skipped with a warning and '
        'the other docs still render', () async {
      final build = await _build(
        {_featurePath: _feature, _storyPath: _story},
        beforeBuild: (root) {
          final locked = File('${root.path}/docs/$_featurePath');
          Process.runSync('chmod', ['000', locked.path]);
          addTearDown(() => Process.runSync('chmod', ['644', locked.path]));
        },
      );

      expect(build.warnings, ['docs/$_featurePath: cannot be read; skipped']);
      expect(build.html, contains('Story one'));
    }, skip: unreadablePathSkipReason() ?? false);

    test('a folder that cannot be listed is skipped with a '
        'warning whose path ends in a slash', () async {
      final build = await _build(
        {_featurePath: _feature, _storyPath: _story},
        beforeBuild: (root) {
          final locked = Directory('${root.path}/docs/$_featureDir/us01_a');
          Process.runSync('chmod', ['000', locked.path]);
          addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
        },
      );

      expect(build.warnings, [
        'docs/$_featureDir/us01_a/: cannot be read; skipped',
      ]);
    }, skip: unreadablePathSkipReason() ?? false);
  });

  test('a record under the records root gets no page and no warning', () async {
    final build = await _build(
      {_featurePath: _feature, _storyPath: _story},
      beforeBuild: (root) {
        File.fromUri(
            root.uri.resolve('.specstone/templates/implementation.yaml'),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync(_recordType);
        File.fromUri(
            root.uri.resolve(
              '.specstone/records/f05_rendering/IMPLEMENTATION.md',
            ),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('# Rendering record\n');
      },
    );

    expect(build.html, contains('F-05 — Rendering'));
    expect(build.html, isNot(contains('Rendering record')));
    expect(build.html, isNot(contains('IMPLEMENTATION.md')));
    expect(build.warnings, isEmpty);
  });

  for (final target in const [
    '.specstone/records',
    '.specstone/records/f05_rendering/IMPLEMENTATION.md',
  ]) {
    test('a records target $target is outside the docs root', () async {
      await expectLater(
        _build(
          {_featurePath: _feature},
          target: target,
          beforeBuild: (root) {
            File.fromUri(
                root.uri.resolve('.specstone/templates/implementation.yaml'),
              )
              ..createSync(recursive: true)
              ..writeAsStringSync(_recordType);
            File.fromUri(
                root.uri.resolve(
                  '.specstone/records/f05_rendering/IMPLEMENTATION.md',
                ),
              )
              ..createSync(recursive: true)
              ..writeAsStringSync('# Rendering record\n');
          },
        ),
        throwsA(
          isA<RenderFault>().having(
            (fault) => fault.code,
            'code',
            RenderFaultCode.targetOutsideDocsRoot,
          ),
        ),
      );
    });
  }
}
