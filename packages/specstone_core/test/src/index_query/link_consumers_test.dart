import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/setup_migration/renumber_pass.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

// Each form of a link reaches every consumer one way (R73, R74): the index
// reads it, a doc move rewrites what the index reads, and the renumber pass
// cites and moves what the index reads.

const _domainPath = 'specs/f01_a/DOMAIN.md';
const _topicPath = 'specs/topics/doc_model.md';
const _movedTopicPath = 'specs/topics/m/doc_model.md';
const _storyPath = 'prds/features/f01_a/us01_b/USER_STORY.md';
const _oldSlug = 'scenario-6a--edge-lettered';
const _newSlug = 'scenario-9--edge-lettered';
const _unparsed = '\n[a]:<b\\';

const _topic = '''
# Doc model

## Rules

- **RULE-1** — One.
- **RULE-7a** — Lettered.
- **RULE-30** — Thirty.
''';

const _story = '''
# B

## Acceptance Criteria

### Scenario 1 — [happy] one

- **Given** g

### Scenario 8 — [error] eight

- **Given** g

### Scenario 6a — [edge] lettered
- **Given** g
''';

const _topicLink = '../topics/doc_model.md';
const _storyLink = '../../prds/features/f01_a/us01_b/USER_STORY.md';

/// A form a link is written in: its name, the doc body citing RULE-7a by a
/// link to the topic and linking the story's lettered scenario, and the
/// anchor the topic link names.
typedef _Form = ({String name, String links, String? topicAnchor});

const _readForms = <_Form>[
  (
    name: 'plain',
    links: '[a]($_topicLink) RULE-7a\n[b]($_storyLink#$_oldSlug)\n',
    topicAnchor: null,
  ),
  (
    name: 'angle brackets',
    links: '[a](<$_topicLink>) RULE-7a\n[b](<$_storyLink#$_oldSlug>)\n',
    topicAnchor: null,
  ),
  (
    name: 'title',
    links: '[a]($_topicLink "t") RULE-7a\n[b]($_storyLink#$_oldSlug "t")\n',
    topicAnchor: null,
  ),
  (
    name: 'backslash escapes',
    links:
        '[a](../topics/doc\\_model.md) RULE-7a\n'
        '[b](../../prds/features/f01\\_a/us01_b/USER_STORY.md#$_oldSlug)\n',
    topicAnchor: null,
  ),
  (
    name: 'character references in the path',
    links:
        '[a](../topics/doc&#95;model.md) RULE-7a\n'
        '[b](../../prds/features/f01&#95;a/us01_b/USER_STORY.md#$_oldSlug)\n',
    topicAnchor: null,
  ),
  (
    name: 'reference links',
    links:
        '[a][t] RULE-7a\n[b][s]\n\n'
        '[t]: $_topicLink\n[s]: $_storyLink#$_oldSlug\n',
    topicAnchor: null,
  ),
  (
    name: 'angle-bracketed definitions',
    links:
        '[a][t] RULE-7a\n[b][s]\n\n'
        '[t]: <$_topicLink>\n[s]: <$_storyLink#$_oldSlug>\n',
    topicAnchor: null,
  ),
  (
    name: 'a # written as a character reference',
    links: '[a]($_topicLink) RULE-7a\n[b]($_storyLink&#35;$_oldSlug)\n',
    topicAnchor: null,
  ),
  (
    name: 'a # written as a character reference in a definition',
    links:
        '[a]($_topicLink) RULE-7a\n[b][s]\n\n'
        '[s]: $_storyLink&#x23;$_oldSlug\n',
    topicAnchor: null,
  ),
  (
    name: 'an anchor written with a character reference',
    links:
        '[a]($_topicLink) RULE-7a\n'
        '[b]($_storyLink#&#115;cenario-6a--edge-lettered)\n',
    topicAnchor: null,
  ),
  (
    name: 'an anchor written with a percent escape',
    links:
        '[a]($_topicLink) RULE-7a\n'
        '[b]($_storyLink#%73cenario-6a--edge-lettered)\n',
    topicAnchor: null,
  ),
  (
    name: 'an anchor written with a backslash escape',
    links:
        '[a]($_topicLink) RULE-7a\n'
        '[b]($_storyLink#scenario\\-6a--edge-lettered)\n',
    topicAnchor: null,
  ),
  (
    name: 'an escaped paren in the fragment',
    links: '[a]($_topicLink#a\\)b) RULE-7a\n[b]($_storyLink#$_oldSlug)\n',
    topicAnchor: 'a)b',
  ),
  (
    name: 'a footnote no reference names',
    links:
        '[a]($_topicLink) RULE-7a\n[b]($_storyLink#$_oldSlug)\n\n'
        '[^1]: Also [c](other.md).\n',
    topicAnchor: null,
  ),
  (
    name: 'a footnote defined before its reference',
    links:
        '[^1]: Also [c](pic.png).\n\n'
        '[a]($_topicLink) note[^1] RULE-7a\n[b]($_storyLink#$_oldSlug)\n',
    topicAnchor: null,
  ),
  (
    name: 'footnotes referenced out of order',
    links:
        '[a]($_topicLink) x[^2] y[^1] RULE-7a\n[b]($_storyLink#$_oldSlug)\n\n'
        '[^1]: [p](p.png)\n[^2]: [q](q.png)\n',
    topicAnchor: null,
  ),
  (
    name: 'a reference label markdown folds in full',
    links:
        '[a]($_topicLink) RULE-7a\n[b][ẞ]\n\n'
        '[ss]: $_storyLink#$_oldSlug\n',
    topicAnchor: null,
  ),
  (
    name: 'a reference label markdown does not fold',
    links:
        '[a]($_topicLink) RULE-7a\n[b]($_storyLink#$_oldSlug) [q][Œuvre]\n\n'
        '[œuvre]: pic.png\n',
    topicAnchor: null,
  ),
  (
    name: 'a footnote that runs on over the links',
    links:
        '[^1]: n [c](pic.png)\nx[^1] [a]($_topicLink) RULE-7a\n'
        '[b]($_storyLink#$_oldSlug)\n',
    topicAnchor: null,
  ),
];

late MergedSet _set;

MergedDocType _typeAt(String docPath) =>
    switch (DocTypeMatcher(_set, targetNames: const []).match(docPath)) {
      MatchedDocType(:final docType) => docType,
      _ => throw StateError('no doc type at $docPath'),
    };

RenumberPass _passOver(String domain) => RenumberPass.plan([
  for (final (docPath, lf) in [
    (_topicPath, _topic),
    (_storyPath, _story),
    (_domainPath, domain),
  ])
    (docPath: docPath, lf: lf, type: _typeAt(docPath)),
]);

String _domainOf(String links) => '# A\n\n## Invariants\n\n$links';

/// The doc links the index reads in [lf], the domain doc's text, as target
/// and anchor; null when markdown fails on it.
List<(String, String?)>? _indexed(String lf) => linkPlacesOf(
  lf,
  docPath: _domainPath,
  firstLine: 1,
)?.docLinks.map((link) => (link.target, link.anchor)).toList();

void main() {
  setUpAll(() {
    _set = TemplateResolver().resolveCarried(
      packNames: const ['prd-core', 'software-tech'],
      homeDirectory: null,
    );
  });

  for (final (:name, :links, :topicAnchor) in _readForms) {
    group('R74, $name:', () {
      final domain = _domainOf(links);

      test('the index reads the topic and story links', () {
        expect(_indexed(domain), [
          (_topicPath, topicAnchor),
          (_storyPath, _oldSlug),
        ]);
      });

      test('a move of the topic moves what the index reads, its fragment '
          'kept', () {
        final moved = rewriteDocLinks(
          domain,
          docPath: _domainPath,
          moves: [(from: _topicPath, to: _movedTopicPath)],
        );

        expect(moved, isNotNull);
        expect(_indexed(moved!), [
          (_movedTopicPath, topicAnchor),
          (_storyPath, _oldSlug),
        ]);
      });

      test('the renumber pass cites the topic and moves the story anchor the '
          'index reads', () {
        final pass = _passOver(domain);

        final renumbered = pass.apply(_domainPath, domain);

        expect(renumbered, contains(' RULE-31\n'));
        expect(renumbered, isNot(contains('RULE-7a')));
        expect(_indexed(renumbered), [
          (_topicPath, topicAnchor),
          (_storyPath, _newSlug),
        ]);
        expect(pass.planLine, isNot(contains('not fully rewritten')));
      });
    });
  }

  group('R74, a link inside an image description:', () {
    final domain = _domainOf(
      '![see [a]($_topicLink)](pic.png) RULE-7a\n'
      '![see [b]($_storyLink#$_oldSlug)](pic.png)\n\n'
      '[t]: $_topicLink\n[s]: $_storyLink#$_oldSlug\n',
    );

    test('the index reads no doc link', () {
      expect(_indexed(domain), isEmpty);
    });

    test('a move of the topic moves only the definition', () {
      expect(
        rewriteDocLinks(
          domain,
          docPath: _domainPath,
          moves: [(from: _topicPath, to: _movedTopicPath)],
        ),
        domain.replaceFirst(
          '[t]: $_topicLink',
          '[t]: ../topics/m/doc_model.md',
        ),
      );
    });

    test('the renumber pass cites nothing and moves only the definition '
        'anchor', () {
      expect(
        _passOver(domain).apply(_domainPath, domain),
        domain.replaceFirst(
          '[s]: $_storyLink#$_oldSlug',
          '[s]: $_storyLink#$_newSlug',
        ),
      );
    });
  });

  group('R74, a doc markdown fails on:', () {
    final domain = _domainOf(
      '[a]($_topicLink) RULE-7a\n[b]($_storyLink#$_oldSlug)\n$_unparsed',
    );

    test('the index reads no links', () {
      expect(_indexed(domain), isNull);
    });

    test('a move of the topic changes nothing', () {
      expect(
        rewriteDocLinks(
          domain,
          docPath: _domainPath,
          moves: [(from: _topicPath, to: _movedTopicPath)],
        ),
        isNull,
      );
    });

    test('the renumber pass keeps it as written and names it on its plan '
        'line', () {
      final pass = _passOver(domain);

      expect(pass.apply(_domainPath, domain), domain);
      expect(pass.planLine, endsWith('; not fully rewritten: $_domainPath'));
    });
  });
}
