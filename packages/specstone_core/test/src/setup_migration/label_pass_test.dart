import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/number_label.dart';
import 'package:specstone_core/src/setup_migration/label_pass.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

const _fr = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';

const _feature = 'prds/features/f01_alpha/FEATURE.md';
const _story = 'prds/features/f01_alpha/us01_beta/USER_STORY.md';
const _gamma = 'prds/features/f01_alpha/us01_beta/fr01_gamma.md';
const _delta = 'prds/features/f01_alpha/us01_beta/fr02_delta.md';
const _story2 = 'prds/features/f01_alpha/us02_eps/USER_STORY.md';
const _zeta = 'prds/features/f01_alpha/us02_eps/fr01_zeta.md';
const _eta = 'prds/features/f01_alpha/us02_eps/fr02_eta.md';
const _theta = 'prds/features/f01_alpha/us02_eps/fr04_theta.md';
const _domain = 'specs/f01_alpha/DOMAIN.md';
const _api = 'specs/f01_alpha/API.md';
const _topic = 'specs/topics/rules.md';
const _otherFeature = 'prds/features/f02_other/FEATURE.md';

const _edgeCases = '# Doc\n\n## Edge cases\n\n1. E01 — one\n';

/// The doc tree every case resolves against: feature 1 with two stories, FR 1
/// under both, and a domain doc holding INV-5.
Map<String, String> _baseDocs() => {
  _feature: '# Alpha\n',
  _story: '# Beta\n',
  _gamma: _edgeCases,
  _delta: _edgeCases.replaceAll('E01', 'E02'),
  _story2: '# Eps\n',
  _zeta: '# Zeta\n\n1. E01 — one\n',
  _eta: '# Eta\n\n1. E02 — two\n',
  _theta: '# Theta\n',
  _domain: '# Domain\n\n- **INV-5** Five.\n',
  _api: '# Api\n',
  _topic: '# Rules\n',
  _otherFeature: '# Other\n',
};

final MergedSet _set = TemplateResolver().resolveCarried(
  packNames: const ['prd-core', 'software-tech'],
  homeDirectory: null,
);

/// The shipped doc type of each of [paths] that has one.
Map<String, MergedDocType> _typesOf(Iterable<String> paths) => {
  for (final path in paths)
    if (DocTypeMatcher(_set).match(path) case MatchedDocType(:final docType))
      path: docType,
};

LabelPass _passOf(
  String citing,
  String text, {
  List<({String path, String text})> code = const [],
  List<({String path, String text})> untracked = const [],
}) {
  final docs = {..._baseDocs(), citing: text};
  return LabelPass.plan(
    [
      for (final MapEntry(:key, :value) in docs.entries)
        (docPath: key, lf: value),
    ],
    code,
    untrackedCodeFiles: untracked,
    docTypes: _typesOf(docs.keys),
  );
}

String _convert(String citing, String text) =>
    _passOf(citing, text).apply(citing, text);

LabelTree _tree() => LabelTree.of([
  for (final MapEntry(:key, :value) in _baseDocs().entries)
    (docPath: key, lf: value),
], docTypes: _typesOf(_baseDocs().keys));

void main() {
  group('$_fr E26 LabelTree.resolve', () {
    test('a full label names the feature, story, or FR doc under it', () {
      final tree = _tree();
      NumberLabel one(String text) => numberLabelsIn(text).single;

      expect(tree.resolve(one('F-01'), citingDocPath: _topic), _feature);
      expect(tree.resolve(one('F-01 US-02'), citingDocPath: _topic), _story2);
      expect(
        tree.resolve(one('F-01 US-01 FR-02'), citingDocPath: _topic),
        _delta,
      );
      expect(
        tree.resolve(one('f01/us01/fr01_gamma'), citingDocPath: _topic),
        _gamma,
      );
    });

    test(
      'a partial label reads against the citing doc story, else feature',
      () {
        final tree = _tree();
        NumberLabel one(String text) => numberLabelsIn(text).single;

        expect(tree.resolve(one('FR-01'), citingDocPath: _delta), _gamma);
        expect(tree.resolve(one('FR-01'), citingDocPath: _zeta), _zeta);
        expect(tree.resolve(one('US-02'), citingDocPath: _delta), _story2);
        expect(tree.resolve(one('US-02 FR-01'), citingDocPath: _api), _zeta);
        expect(tree.resolve(one('us02/fr01_zeta'), citingDocPath: _api), _zeta);
      },
    );

    test('a label that names no doc or two docs resolves to null', () {
      final tree = _tree();
      NumberLabel one(String text) => numberLabelsIn(text).single;

      expect(tree.resolve(one('FR-01'), citingDocPath: _api), isNull);
      expect(tree.resolve(one('FR-01'), citingDocPath: _topic), isNull);
      expect(tree.resolve(one('US-01'), citingDocPath: _topic), isNull);
      expect(tree.resolve(one('F-09'), citingDocPath: _topic), isNull);
      expect(tree.resolve(one('us01/fr01_other'), citingDocPath: _api), isNull);
    });

    test(
      'an item ID after the label picks the one doc under it that holds it',
      () {
        final tree = _tree();
        NumberLabel one(String text) => numberLabelsIn(text).single;

        expect(tree.resolve(one('F-01 INV-5'), citingDocPath: _topic), _domain);
        expect(
          tree.resolve(one('US-01 FR-02 E02'), citingDocPath: _topic),
          isNull,
          reason: 'a partial label in a topic doc has no feature',
        );
        expect(tree.resolve(one('F-01 INV-9'), citingDocPath: _topic), isNull);
      },
    );

    test(
      'a label after another reads against the doc and the label before it',
      () {
        final tree = _tree();
        final named = numberLabelsIn('US-02 FR-01, FR-04');
        final split = numberLabelsIn('US-02 FR-01, FR-02');

        // FR-04 names a doc only against the label before it.
        expect(
          tree.resolve(named[1], citingDocPath: _delta, before: named[0]),
          _theta,
        );
        // FR-02 names two docs, one against each reading.
        expect(
          tree.resolve(split[1], citingDocPath: _delta, before: split[0]),
          isNull,
        );
      },
    );
  });

  group('$_fr E26 LabelPass.apply', () {
    test('the doc name goes in a code span, a one-slug name typed', () {
      expect(
        _convert(_topic, 'See F-01 US-01 FR-01, F-01 US-01, and F-01.\n'),
        'See `alpha/beta/gamma`, `alpha/beta`, and `feature:alpha`.\n',
      );
    });

    test('a folder path converts to the name of its doc', () {
      expect(
        _convert(_topic, 'See f01/us01/fr01_gamma now.\n'),
        'See `alpha/beta/gamma` now.\n',
      );
    });

    test('a partial label reads against the doc that holds it', () {
      expect(
        _convert(_delta, 'Like FR-01 and US-02 FR-01.\n'),
        'Like `alpha/beta/gamma` and `alpha/eps/zeta`.\n',
      );
    });

    test('an item ID that follows stays after the name', () {
      expect(
        _convert(_topic, 'Holds F-01 INV-5 here.\n'),
        'Holds `domain:alpha` INV-5 here.\n',
      );
      expect(
        _convert(_delta, '1. E02 — two\n\nHolds FR-02 E02 here.\n'),
        '1. E02 — two\n\nHolds `alpha/beta/delta` E02 here.\n',
      );
    });

    test(
      'a label in a list or range converts when its readings name one doc',
      () {
        expect(
          _convert(_delta, 'Both (FR-01, FR-02).\n'),
          'Both (`alpha/beta/gamma`, `alpha/beta/delta`).\n',
        );
        expect(
          _convert(_delta, 'Both (US-02 FR-01, FR-04).\n'),
          'Both (`alpha/eps/zeta`, `alpha/eps/theta`).\n',
        );
        expect(
          _convert(_delta, 'Both (US-02 FR-01, FR-02).\n'),
          'Both (`alpha/eps/zeta`, FR-02).\n',
        );
      },
    );

    test('an item ID after a label hides no list: the next label has both '
        'readings', () {
      const text = '1. E02 — x\n\nSee (US-02 FR-01 E01, FR-02 E02).\n';

      expect(
        _convert(_delta, text),
        '1. E02 — x\n\nSee (`alpha/eps/zeta` E01, FR-02 E02).\n',
      );
    });

    test('every item ID in the gap is passed over when reading a list', () {
      const head = '1. E02 — x\n\nSee ';

      expect(
        _convert(_delta, '${head}US-02 FR-01 E01, E06, FR-02 E02.\n'),
        '${head}`alpha/eps/zeta` E01, E06, FR-02 E02.\n',
      );
      expect(
        _convert(_delta, '${head}US-02 FR-01 E01 and E06, FR-02 E02.\n'),
        '${head}`alpha/eps/zeta` E01 and E06, FR-02 E02.\n',
      );
    });

    test('a gap that holds an ID and other words is no list', () {
      const head = '1. E02 — x\n\nSee ';

      expect(
        _convert(_delta, '${head}US-02 FR-01 E01 shows FR-02 E02.\n'),
        '${head}`alpha/eps/zeta` E01 shows `alpha/beta/delta` E02.\n',
      );
    });

    test('a spec doc is named from its doc type, not its file stem', () {
      final tree = LabelTree.of(
        [(docPath: _domain, lf: '# D\n- **INV-5** x\n')],
        docTypes: {
          _domain: _typesOf([_api])[_api]!,
        },
      );
      final label = numberLabelsIn('F-01 INV-5').single;

      expect(tree.nameOf(_domain), 'api:alpha');
      expect(tree.resolve(label, citingDocPath: _topic), _domain);
    });

    test('the name alone goes inside a code span that holds the label', () {
      expect(
        _convert(_topic, 'Cite `F-01 US-01` and `see F-01 here`.\n'),
        'Cite `alpha/beta` and `see feature:alpha here`.\n',
      );
    });

    test('the name alone goes inside a mermaid block, other fences stay', () {
      const text =
          '```mermaid\nflowchart TD\n  A[F-01 CLI] --> B[F-01 US-01]\n```\n\n'
          '```text\nF-01 stays\n```\n';

      expect(
        _convert(_topic, text),
        '```mermaid\nflowchart TD\n'
        '  A[feature:alpha CLI] --> B[alpha/beta]\n```\n\n'
        '```text\nF-01 stays\n```\n',
      );
    });

    test('a link destination stays byte-equal when its text holds a label', () {
      const text =
          '[F-01 US-01](../f01_alpha/us01_beta/USER_STORY.md) and '
          '[x](<../f01_alpha/F-01 US-01.md>)\n';

      expect(
        _convert(_topic, text),
        '[`alpha/beta`](../f01_alpha/us01_beta/USER_STORY.md) and '
        '[x](<../f01_alpha/F-01 US-01.md>)\n',
      );
    });

    test(
      'a label in a code span that runs over two lines gets no nested span',
      () {
        expect(
          _convert(_topic, 'Cite `see\nF-01 here` now.\n'),
          'Cite `see\nfeature:alpha here` now.\n',
        );
      },
    );

    test('frontmatter and every other byte stay', () {
      const text = '---\nnote: F-01\n---\n# T\n\nF-01 x  \n\n- F-01\n';

      expect(
        _convert(_topic, text),
        '---\nnote: F-01\n---\n# T\n\n`feature:alpha` x  \n\n'
        '- `feature:alpha`\n',
      );
    });

    test('a doc with no label comes back as it is', () {
      expect(_convert(_topic, 'UTF-8 and UTF-16.\n'), 'UTF-8 and UTF-16.\n');
    });
  });

  group('$_fr E27 labels the pass keeps', () {
    test('each kept case is listed after left with its line and label', () {
      final pass = _passOf(_api, 'x\nFR-01 and US-01 FR-01.\n\nF-09 y\n');

      expect(
        pass.apply(_api, 'x\nFR-01 and US-01 FR-01.\n\nF-09 y\n'),
        'x\nFR-01 and `alpha/beta/gamma`.\n\nF-09 y\n',
      );
      expect(
        pass.planLine,
        'number labels: $_api; left: $_api:2 FR-01, $_api:4 F-09',
      );
    });

    test('a partial label in a topic doc stays and is listed', () {
      final pass = _passOf(_topic, 'FR-01\n');

      expect(pass.apply(_topic, 'FR-01\n'), 'FR-01\n');
      expect(pass.planLine, 'number labels: ; left: $_topic:1 FR-01');
    });

    test('a label in a fenced block other than mermaid is no label', () {
      final pass = _passOf(_topic, '```\nF-01\n```\n');

      expect(pass.planLine, isNull);
    });

    test('a tree with no label has no plan line', () {
      expect(_passOf(_topic, 'Nothing here.\n').planLine, isNull);
    });
  });

  group('$_fr E26 files under the code roots', () {
    test('a comment line gets a code span, a string gets the name alone', () {
      const text =
          '// see F-01 US-01 and US-01 FR-01\n'
          '  // F-01 INV-5\n'
          "test('F-01 US-01: name', () {});\n"
          "const t = 'US-01 FR-01';\n"
          'int a = 0; // F-01 here\n'
          '// cite `F-01` there\n';
      final pass = _passOf(
        _topic,
        'plain\n',
        code: [(path: 'lib/a.dart', text: text)],
      );

      expect(pass.codeFiles, {
        'lib/a.dart':
            '// see `alpha/beta` and US-01 FR-01\n'
            '  // `domain:alpha` INV-5\n'
            "test('alpha/beta: name', () {});\n"
            "const t = 'US-01 FR-01';\n"
            'int a = 0; // feature:alpha here\n'
            '// cite `feature:alpha` there\n',
      });
      expect(
        pass.planLine,
        'number labels: lib/a.dart; left: lib/a.dart:1 US-01 FR-01, '
        'lib/a.dart:4 US-01 FR-01',
      );
    });

    test('a line end the file wrote stays, a lone line keeps its CR', () {
      final pass = _passOf(
        _topic,
        'plain\n',
        code: [(path: 'lib/m.dart', text: '// F-01\r\n// F-01 US-01\nx\r\n')],
      );

      expect(pass.codeFiles, {
        'lib/m.dart': '// `feature:alpha`\r\n// `alpha/beta`\nx\r\n',
      });
    });

    test('a markdown file is read as a doc, the name in a code span', () {
      final pass = _passOf(
        _topic,
        'plain\n',
        code: [(path: 'notes.md', text: '---\nx: F-01\n---\nSee F-01 here.\n')],
      );

      expect(pass.codeFiles, {
        'notes.md': '---\nx: F-01\n---\nSee `feature:alpha` here.\n',
      });
    });

    test('a file the project git does not track keeps every label, listed', () {
      final pass = _passOf(
        _topic,
        'plain\n',
        untracked: [(path: 'vendor/b.dart', text: '// F-01 US-01\n')],
      );

      expect(pass.codeFiles, isEmpty);
      expect(
        pass.planLine,
        'number labels: ; left: vendor/b.dart:1 F-01 US-01',
      );
    });

    test('a file of any extension is read line by line', () {
      final pass = _passOf(
        _topic,
        'plain\n',
        code: [(path: 'data.json', text: '{"a": "F-01"}\n')],
      );

      expect(pass.codeFiles, {'data.json': '{"a": "feature:alpha"}\n'});
    });

    test('holdsNumberLabel reads a file as the pass does', () {
      expect(holdsNumberLabel('a.dart', '// F-01\n'), isTrue);
      expect(holdsNumberLabel('a.dart', 'x = "F-01";\n'), isTrue);
      expect(holdsNumberLabel('a.md', 'F-01\n'), isTrue);
      expect(holdsNumberLabel('a.dart', 'UTF-8 and US-ASCII\n'), isFalse);
    });
  });

  group('$_fr E26 plan line order', () {
    test('docs come before code files, each in code point order', () {
      final pass = _passOf(
        _topic,
        'F-01\n',
        code: [
          (path: 'z.dart', text: '// F-01\n'),
          (path: 'a.dart', text: '// F-01\n'),
        ],
      );

      expect(pass.planLine, 'number labels: $_topic, a.dart, z.dart');
    });
  });

  group('$_fr E28 E29 api operation headings', () {
    const trace =
        '# Alpha API\n\n## FR trace\n\n| FR | Operation |\n|----|-----------|\n'
        '| `beta/gamma` | `alpha run` |\n| `beta/delta` | `alpha run` |\n'
        '| `eps/zeta` | `alpha run` |\n| `eps/zeta` | `alpha two` |\n'
        '| `beta/gamma` | `alpha two` |\n\n## Operations\n\n';

    String api(String headings) => '$trace$headings\nBody.\n';

    LabelPass pass(String headings, {Map<String, String> others = const {}}) {
      final docs = {..._baseDocs(), _api: api(headings), ...others};
      return LabelPass.plan(
        [
          for (final MapEntry(:key, :value) in docs.entries)
            (docPath: key, lf: value),
        ],
        const [],
        docTypes: _typesOf(docs.keys),
      );
    }

    String linkTo(String slug) =>
        '[x](../f01_alpha/API.md#$slug) [y](../f01_alpha/API.md#zz)\n';

    String heading(String headings) {
      final text = api(headings);
      return pass(headings).apply(_api, text).split('\n')[14];
    }

    test('E28 drops the dash and every label, a range and a list too', () {
      expect(
        heading('### `alpha run` — US-01 FR-01 to FR-02; US-02 FR-01\n'),
        '### `alpha run`',
      );
      expect(
        heading('### `alpha run` — US-01 FR-01, FR-02\n'),
        '### `alpha run`',
      );
    });

    test('E28 reads a trailing of-story as the story of the labels', () {
      expect(heading('### `alpha two` — FR-01 of US-02\n'), '### `alpha two`');
      expect(heading('### `alpha two` — FR-01 of US-01\n'), '### `alpha two`');
    });

    test('E29 keeps a heading whose label names no FR of its rows', () {
      expect(
        heading('### `alpha two` — US-01 FR-02\n'),
        '### `alpha two` — US-01 FR-02',
      );
    });

    test('E29 keeps a heading whose label names two FRs of its rows', () {
      expect(heading('### `alpha run` — FR-01\n'), '### `alpha run` — FR-01');
    });

    test('a kept heading is listed and its labels never become doc names', () {
      final built = pass('### `alpha two` — US-02 FR-04\n');

      expect(
        built.apply(_api, api('### `alpha two` — US-02 FR-04\n')),
        api('### `alpha two` — US-02 FR-04\n'),
      );
      expect(built.planLine, 'number labels: ; left: $_api:15 US-02 FR-04');
    });

    test('the plan line names each heading the step converts', () {
      final built = pass('### `alpha run` — US-01 FR-01\n');

      expect(built.planLine, 'number labels: $_api, $_api:15 `alpha run`');
    });

    test('a link to a converted heading takes the new slug, in any doc', () {
      const old = 'alpha-run--us-01-fr-01';
      final built = pass(
        '### `alpha run` — US-01 FR-01\n\n[self](#$old)\n',
        others: {_topic: linkTo(old)},
      );

      expect(
        built.apply(_topic, linkTo(old)),
        '[x](../f01_alpha/API.md#alpha-run) [y](../f01_alpha/API.md#zz)\n',
      );
      expect(built.apply(_api, ''), contains('[self](#alpha-run)'));
    });

    test(
      'a link to a heading whose label became a doc name takes its slug',
      () {
        final built = pass(
          '### Rule F-01\n',
          others: {_topic: '[x](../f01_alpha/API.md#rule-f-01)\n'},
        );

        expect(
          built.apply(_topic, ''),
          '[x](../f01_alpha/API.md#rule-featurealpha)\n',
        );
      },
    );

    test('E29 keeps a heading below converted ones as written, listed', () {
      const headings =
          '### `alpha run` — US-01 FR-01 to FR-02\n\n'
          '### `alpha run` — US-01 FR-01, FR-02\n\n'
          '### `alpha run` — US-01 FR-01 to FR-02; US-02 FR-01\n\n'
          '### `alpha two` — US-02 FR-04\n';
      final built = pass(headings);
      final text = built.apply(_api, api(headings));

      expect(text, endsWith('### `alpha two` — US-02 FR-04\n\nBody.\n'));
      expect(built.planLine, endsWith('; left: $_api:21 US-02 FR-04'));
    });

    test('a bare Concerns see of an architecture doc takes the new slug', () {
      final set = TemplateResolver().resolveCarried(
        packNames: const ['prd-core', 'software-tech'],
        homeDirectory: null,
      );
      const path = 'specs/f01_alpha/ARCHITECTURE.md';
      final type = switch (DocTypeMatcher(set).match(path)) {
        MatchedDocType(:final docType) => docType,
        _ => throw StateError('no doc type'),
      };
      const concerns = '# A\n\n## Concerns\n\n- Errors — see API.md#';
      final docs = {
        ..._baseDocs(),
        _api: api('### `alpha run` — US-01 FR-01\n'),
        path: '${concerns}alpha-run--us-01-fr-01\n',
      };
      final built = LabelPass.plan(
        [
          for (final MapEntry(:key, :value) in docs.entries)
            (docPath: key, lf: value),
        ],
        const [],
        docTypes: {..._typesOf(docs.keys), path: type},
      );

      expect(built.apply(path, docs[path]!), '${concerns}alpha-run\n');
    });
  });
}
