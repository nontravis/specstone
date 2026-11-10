import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';
import '../../helpers/prd_core.dart';

const _owned = '''
id: owned
description: A doc type with a required field.
path: prds/o{nn}_{slug}.md
fields:
  - id: owner
    type: string
    required: true
''';

const _keyed = '''
id: keyed
description: A doc type with two declared fields and a section.
path: prds/k{nn}_{slug}.md
fields:
  - id: traced_from
    type: string
    list: true
  - id: verify_method
    type: string
sections:
  - id: statement
    header: Statement
''';

Future<MergedDocType> _feature() async =>
    (await fixtureDocTypes()).lookup('feature')!;

/// Formats [disk] and returns the text, checking a second pass changes nothing
/// and the laid-out sections are those the text parses into.
String _format(String disk, MergedDocType docType) {
  final outcome = formatDoc(Doc.parse(disk), docType);
  expect(outcome, isA<Formatted>());
  final text = (outcome as Formatted).text;
  List<(String, String)> shapeOf(List<Section> sections) => [
    for (final s in sections) (s.headerLine, s.body),
  ];
  expect(
    shapeOf(outcome.sections),
    shapeOf(Doc.parse(text).sections),
    reason: 'laid-out sections',
  );
  final again = formatDoc(Doc.parse(text), docType);
  expect(again, isA<Formatted>());
  expect((again as Formatted).text, text, reason: 'idempotence');
  return text;
}

Refused _refused(String disk, MergedDocType docType) {
  final outcome = formatDoc(Doc.parse(disk), docType);
  expect(outcome, isA<Refused>());
  return outcome as Refused;
}

void main() {
  group('headerKey', () {
    test('f05/us01/fr04/e01, s03/inv5: lowercases, trims, collapses '
        'whitespace', () {
      expect(headerKey('  Feature \t  GOAL '), 'feature goal');
    });

    test('f05/us01/fr04/e01, s03/inv5: keeps words that differ apart', () {
      expect(headerKey('Featuregoal'), isNot(headerKey('Feature goal')));
    });
  });

  group('formatDoc', () {
    test('f05/us01/fr03, s03/inv1, s03/inv2: sections and keys follow the '
        'template, bodies unchanged', () async {
      final feature = await _feature();
      const disk =
          '---\nvision:\n  - PV-01\nstatus: planned\n---\n\n'
          '# F-05 — Rendering\n\n'
          '## Feature goal\n\n- **why:** share docs\n\n'
          '## Feature name\n\n- **Human:** Rendering\n';

      expect(
        _format(disk, feature),
        '---\nstatus: planned\nvision:\n  - PV-01\n---\n\n'
        '# F-05 — Rendering\n\n'
        '## Feature name\n\n- **Human:** Rendering\n\n'
        '## Feature goal\n\n- **why:** share docs\n',
      );
    });

    test('f05/us01/fr03/e01: a subsection moves with its section', () async {
      final feature = await _feature();
      const disk =
          '## Feature goal\n\n- **why:** x\n### Detail\n\nd1\nd2\n\n'
          '## Feature name\n\nn\n';

      expect(
        _format(disk, feature),
        '## Feature name\n\nn\n\n'
        '## Feature goal\n\n- **why:** x\n### Detail\n\nd1\nd2\n',
      );
    });

    test('f05/us01/fr03/e02: defined keys first in field order, the rest '
        'after in file order', () async {
      final feature = await _feature();
      const disk =
          '---\nzeta: 1\nstatus: planned\nalpha: 2\n---\n\n'
          '## Feature name\n\nn\n\n## Feature goal\n\ng\n';

      expect(
        _format(disk, feature),
        '---\nstatus: planned\nzeta: 1\nalpha: 2\n---\n\n'
        '## Feature name\n\nn\n\n## Feature goal\n\ng\n',
      );
    });

    test('f05/us01/fr03/e03, s03/inv2: a key block moves whole, comment and '
        'value bytes unchanged', () async {
      final feature = await _feature();
      const disk =
          '---\n# note\nvision:\n  - PV-01  # c\nstatus: planned\n---\n\n'
          '## Feature name\n\nn\n\n## Feature goal\n\ng\n';

      expect(
        _format(disk, feature),
        '---\nstatus: planned\n# note\nvision:\n  - PV-01  # c\n---\n\n'
        '## Feature name\n\nn\n\n## Feature goal\n\ng\n',
      );
    });

    test('f05/us01/fr03/e04: a doc without frontmatter gets none', () async {
      final feature = await _feature();

      final text = _format(
        '## Feature goal\n\ng\n\n## Feature name\n\nn\n',
        feature,
      );

      expect(text, isNot(contains('---')));
      expect(text, '## Feature name\n\nn\n\n## Feature goal\n\ng\n');
    });

    test('f05/us01/fr03/e05, s03/inv2: a missing required key is not '
        'added', () async {
      final owned = (await fixtureDocTypes(extra: {'owned.yaml': _owned}))
          .lookup('owned')!;

      final text = _format('---\nstatus: planned\n---\n\n# T\n', owned);

      expect(text, isNot(contains('owner')));
      expect(text, '---\nstatus: planned\n---\n\n# T\n');
    });

    test('f05/us01/fr03/e06, s03/inv7: one blank line between sections, one '
        'final line break', () async {
      final feature = await _feature();

      final text = _format(
        '## Feature name\n\nn\n\n\n\n## Feature goal\n\ng',
        feature,
      );

      expect(text, '## Feature name\n\nn\n\n## Feature goal\n\ng\n');
      expect(text.endsWith('\n\n'), isFalse);
    });

    test('f05/us01/fr04/e01, s03/inv5: a header matches apart from case and '
        'whitespace and is written as the template writes it', () async {
      final feature = await _feature();

      expect(
        _format('## feature   goal\n\ng\n\n## FEATURE NAME\n\nn\n', feature),
        '## Feature name\n\nn\n\n## Feature goal\n\ng\n',
      );
    });

    test('f05/us01/fr04/e02, s03/inv6: unknown headers are refused as '
        'written, in file order', () async {
      final feature = await _feature();

      final refused = _refused(
        '## Feature goals\ng\n\n## Feature name\nn\n\n## Notes\nx\n',
        feature,
      );

      expect(refused.unknownHeaders, ['## Feature goals', '## Notes']);
      expect(refused.duplicateHeaders, isEmpty);
    });

    test('f05/us01/fr04/e03, s03/inv6: a duplicate header is refused in '
        'template form', () async {
      final feature = await _feature();

      final refused = _refused(
        '## Feature name\na\n\n## feature  NAME\nb\n',
        feature,
      );

      expect(refused.duplicateHeaders, ['## Feature name']);
      expect(refused.unknownHeaders, isEmpty);
    });

    test('f05/us01/fr04/e03, s03/inv6: a header three times is listed once, '
        'in file order', () async {
      final feature = await _feature();

      final refused = _refused(
        '## Feature goal\n1\n## Feature name\n2\n## Feature goal\n3\n'
        '## Feature name\n4\n## Feature goal\n5\n',
        feature,
      );

      expect(refused.duplicateHeaders, ['## Feature goal', '## Feature name']);
    });

    test('f05/us01/fr04: a doc that ends inside a fence is refused, with no '
        'header fault listed', () async {
      final feature = await _feature();

      final refused = _refused(
        '## Feature name\nx\n```\n## Feature goal\n',
        feature,
      );

      expect(refused.unclosedFence, isTrue);
      expect(refused.unknownHeaders, isEmpty);
      expect(refused.duplicateHeaders, isEmpty);
    });

    test('rendering/format_docs/match_section_headers: a layout that turns a '
        'body line into a frontmatter close is refused, apart from the '
        'header faults', () async {
      final feature = await _feature();

      final refused = _refused('---\n## Feature name\nx\n--- \n', feature);

      expect(refused.changesStructure, isTrue);
      expect(refused.unclosedFence, isFalse);
      expect(refused.unknownHeaders, isEmpty);
      expect(refused.duplicateHeaders, isEmpty);
    });

    test('rendering/format_docs/match_section_headers: declared fields the '
        'layout reorders are formatted, whatever lines trail the last '
        'block', () async {
      final keyed = (await fixtureDocTypes(extra: {'keyed.yaml': _keyed}))
          .lookup('keyed')!;
      const keys = 'verify_method: test\ntraced_from:\n  - S1\n';

      for (final trailing in ['', '\n', '# note\n', '\n# note\n']) {
        final disk = '---\n$keys$trailing---\n# T\n\n## Statement\nx\n';

        final outcome = formatDoc(Doc.parse(disk), keyed);

        expect(outcome, isA<Formatted>(), reason: disk);
        final text = (outcome as Formatted).text;
        expect(
          text.indexOf('traced_from'),
          lessThan(text.indexOf('verify_method')),
          reason: disk,
        );
      }
    });

    test('rendering/format_docs/match_section_headers: a doc the layout '
        'leaves as it is keeps its own parse', () async {
      final feature = await _feature();
      final doc = Doc.parse('# T\n\n## Feature name\n\nx\n');

      final outcome = formatDoc(doc, feature);

      expect(outcome, isA<Formatted>());
      expect(identical((outcome as Formatted).doc, doc), isTrue);
    });

    test('f05/us01/fr04: a header fault is not unclosedFence', () async {
      final feature = await _feature();

      expect(_refused('## Notes\nx\n', feature).unclosedFence, isFalse);
    });

    test('f05/us01/fr04/e02, f05/us01/fr04/e03: a doc with both faults '
        'reports both lists', () async {
      final feature = await _feature();

      final refused = _refused(
        '## Notes\nx\n## Feature name\na\n## Feature name\nb\n',
        feature,
      );

      expect(refused.unknownHeaders, ['## Notes']);
      expect(refused.duplicateHeaders, ['## Feature name']);
    });

    test('rendering/format_docs/leave_missing_sections E01: a missing required '
        'section stays absent', () async {
      final feature = await _feature();

      expect(
        _format('## Feature name\n\nn\n', feature),
        '## Feature name\n\nn\n',
      );
      expect(
        _format('## Feature goal\n\ng\n', feature),
        '## Feature goal\n\ng\n',
      );
    });

    test('rendering/format_docs/leave_missing_sections E02: a missing optional '
        'section stays absent', () async {
      final feature = await _feature();

      final text = _format(
        '## Feature name\n\nn\n\n## Feature goal\n\ng\n',
        feature,
      );

      expect(text, isNot(contains('Feature flow')));
    });

    test('rendering/format_docs/leave_missing_sections E03: draft stays as '
        'written when a section is missing', () async {
      final feature = await _feature();

      final text = _format(
        '---\ndraft: false\n---\n\n## Feature name\n\nn\n',
        feature,
      );

      expect(text, '---\ndraft: false\n---\n\n## Feature name\n\nn\n');
    });

    test('rendering/format_docs/order_sections_and_keys: orders and renames '
        'headers, keeps text, lays out a table and a heading gap', () async {
      final feature = await _feature();

      final text = _format(
        '## feature  goal\ng\n\n## Feature name\n\n'
        '### Sub\ntext\n\n| a   | b    |\n|-----|------|\n| 1   | 22   |\n',
        feature,
      );

      expect(
        text,
        '## Feature name\n\n'
        '### Sub\n\ntext\n\n| a | b |\n|---|---|\n| 1 | 22 |\n\n'
        '## Feature goal\n\ng\n',
      );
    });

    test('rendering/format_docs/normalize_layout_whitespace E07: a laid-out '
        'doc comes back byte-equal', () async {
      final feature = await _feature();
      const disk = '## Feature name\n\nn\n\n## Feature goal\n\ng\n';

      expect(_format(disk, feature), disk);
    });

    test('rendering/format_docs/normalize_layout_whitespace E09: a '
        'frontmatter line starting "# " and a key block line ending in '
        'spaces stay verbatim', () async {
      final feature = await _feature();
      const disk =
          '---\n# comment  \nstatus: planned  \n---\n\n'
          '## Feature name\n\nn\n';

      expect(_format(disk, feature), disk);
    });

    test('doc_model/s03/inv6, s03/inv2: a keyless frontmatter block is '
        'emitted first and verbatim', () async {
      final feature = await _feature();
      const above =
          '---\n  orphan: line\nvision:\n  - PV-01\nstatus: planned\n---\n\n'
          '## Feature name\n\nn\n\n## Feature goal\n\ng\n';

      final keyless = Doc.parse(above).frontmatter!.first;
      expect(keyless.key, isEmpty);
      expect(
        _format(above, feature),
        '---\n  orphan: line\nstatus: planned\nvision:\n  - PV-01\n---\n\n'
        '## Feature name\n\nn\n\n## Feature goal\n\ng\n',
      );
    });

    test('doc_model/s03/inv6: a keyless block in an already formatted doc '
        'survives formatting unchanged', () async {
      final feature = await _feature();
      const disk =
          '---\n  orphan: line\nstatus: planned\n---\n\n'
          '## Feature name\n\nn\n\n## Feature goal\n\ng\n';

      expect(_format(disk, feature), disk);
    });

    test('empty head: a doc with no frontmatter and no head starts with its '
        'first section', () async {
      final feature = await _feature();

      expect(
        _format('## Feature name\n\nx\n\n## Feature goal\n\ng\n', feature),
        '## Feature name\n\nx\n\n## Feature goal\n\ng\n',
      );
    });

    test('empty head: frontmatter and an empty head put exactly one blank '
        'line before the first section', () async {
      final feature = await _feature();

      for (final gap in ['', '\n', '\n\n\n']) {
        expect(
          _format(
            '---\nstatus: planned\n---\n$gap## Feature name\n\nx\n\n'
            '## Feature goal\n\ng\n',
            feature,
          ),
          '---\nstatus: planned\n---\n\n## Feature name\n\nx\n\n'
          '## Feature goal\n\ng\n',
          reason: 'gap ${gap.length}',
        );
      }
    });

    test('s03/inv7: formatting a Formatted text again yields the same '
        'text', () async {
      final feature = await _feature();
      const disk =
          '---\nzeta: 1\nstatus: planned\n---\n\n# T\n\nlead\n\n\n'
          '## Feature goal\n\ng\n```\n## not a header\n```\n\n\n';

      final once = _format(disk, feature);
      final twice = formatDoc(Doc.parse(once), feature) as Formatted;

      expect(twice.text, once);
    });
  });

  group('open generated block', () {
    final open = generatedOpenMarker('journey_flow');
    final unclosed =
        '# J\n\n## Goal\n\nGo.\n\n## Flow\n\n$open\n| a     | b |\n'
        '|---|---|\n';
    final spacedEnd =
        '# J\n\n## Goal\n\nGo.\n\n## Flow\n\n$open\nx\n$generatedEndMarker  \n';

    Future<MergedDocType> journey() async =>
        prdCoreDocType(await resolvePrdCore(), 'journey');

    test('rendering/keep_generated_blocks_current/write_generated_blocks E06: '
        'an opening marker of a listed kind with no end marker is refused, '
        'naming the marker and its kind', () async {
      final docType = await journey();

      for (final text in [unclosed, spacedEnd]) {
        final refused = _refused(text, docType);

        expect(refused.openBlock, open, reason: text);
        expect(refused.openBlockKind, 'journey_flow', reason: text);
        expect(refused.unknownHeaders, isEmpty, reason: text);
        expect(refused.unclosedFence, isFalse, reason: text);
      }
    });

    test('rendering/keep_generated_blocks_current/write_generated_blocks E06: '
        'a doc with an open generated block is written as given and is not '
        'laid out', () async {
      final docType = await journey();

      expect(layOutDoc(unclosed, docType), unclosed);
      expect(isLaidOut(Doc.parse(unclosed), unclosed, docType), isFalse);
    });

    test('rendering/keep_generated_blocks_current/write_generated_blocks '
        'E06: a marker whose line ends in spaces or a tab, with no end '
        'marker, is refused, naming the marker as written', () async {
      final docType = await journey();

      for (final tail in [' ', '\t', '   ']) {
        final text = '# J\n\n## Goal\n\nGo.\n\n## Flow\n\n$open$tail\nx\n';

        final refused = _refused(text, docType);

        expect(refused.openBlock, '$open$tail', reason: 'tail ${tail.length}');
        expect(refused.openBlockKind, 'journey_flow');
      }
    });

    test('rendering/keep_generated_blocks_current/write_generated_blocks E04: '
        'an open marker of a kind the type does not list is text', () async {
      final docType = await journey();
      final other = generatedOpenMarker('note_toc');
      final text = '# J\n\n## Goal\n\n$other\nGo.\n';

      expect(formatDoc(Doc.parse(text), docType), isA<Formatted>());
    });
  });

  group('layOutDoc', () {
    test('rendering/format_docs/normalize_layout_whitespace: a null doc type '
        'returns the text unchanged', () {
      const text = '## A\n\n\n\nx   \n';

      expect(layOutDoc(text, null), text);
      expect(isLaidOut(Doc.parse(text), text, null), isFalse);
    });

    test('rendering/format_docs/match_section_headers: each refusal returns '
        'the text byte-equal', () async {
      final feature = await _feature();

      for (final text in [
        '## Notes\nx   \n',
        '## Feature name\n\nn\n\n\n\n## Feature name\n\nn\n',
        '## Feature name\n\n```\nx   \n',
      ]) {
        expect(layOutDoc(text, feature), text);
        expect(isLaidOut(Doc.parse(text), text, feature), isFalse);
      }
    });

    test('rendering/format_docs/order_sections_and_keys: lays out as '
        'formatDoc does', () async {
      final feature = await _feature();
      const text = '## Feature goal\n\ng\n\n\n## Feature name\n\nn\n';
      const laid = '## Feature name\n\nn\n\n## Feature goal\n\ng\n';

      expect(layOutDoc(text, feature), laid);
      expect(isLaidOut(Doc.parse(text), text, feature), isFalse);
      expect(isLaidOut(Doc.parse(laid), laid, feature), isTrue);
    });
  });
}
