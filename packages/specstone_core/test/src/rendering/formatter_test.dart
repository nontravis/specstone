import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

const _owned = '''
id: owned
description: A doc type with a required field.
path: prds/o{nn}_{slug}.md
fields:
  - id: owner
    type: string
    required: true
''';

Future<MergedDocType> _feature() async =>
    (await fixtureDocTypes()).lookup('feature')!;

/// Formats [disk] and returns the text, checking a second pass changes nothing.
String _format(String disk, MergedDocType docType) {
  final outcome = formatDoc(Doc.parse(disk), docType);
  expect(outcome, isA<Formatted>());
  final text = (outcome as Formatted).text;
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
          '## Feature goal\n- **why:** share docs  \n\n'
          '## Feature name\n- **Human:** Rendering\n';

      expect(
        _format(disk, feature),
        '---\nstatus: planned\nvision:\n  - PV-01\n---\n\n'
        '# F-05 — Rendering\n\n'
        '## Feature name\n- **Human:** Rendering\n\n'
        '## Feature goal\n- **why:** share docs  \n',
      );
    });

    test('f05/us01/fr03/e01: a subsection moves with its section', () async {
      final feature = await _feature();
      const disk =
          '## Feature goal\n- **why:** x\n### Detail\nd1\nd2\n\n'
          '## Feature name\nn\n';

      expect(
        _format(disk, feature),
        '## Feature name\nn\n\n'
        '## Feature goal\n- **why:** x\n### Detail\nd1\nd2\n',
      );
    });

    test('f05/us01/fr03/e02: defined keys first in field order, the rest '
        'after in file order', () async {
      final feature = await _feature();
      const disk =
          '---\nzeta: 1\nstatus: planned\nalpha: 2\n---\n\n'
          '## Feature name\nn\n\n## Feature goal\ng\n';

      expect(
        _format(disk, feature),
        '---\nstatus: planned\nzeta: 1\nalpha: 2\n---\n\n'
        '## Feature name\nn\n\n## Feature goal\ng\n',
      );
    });

    test('f05/us01/fr03/e03, s03/inv2: a key block moves whole, comment and '
        'value bytes unchanged', () async {
      final feature = await _feature();
      const disk =
          '---\n# note\nvision:\n  - PV-01  # c\nstatus: planned\n---\n\n'
          '## Feature name\nn\n\n## Feature goal\ng\n';

      expect(
        _format(disk, feature),
        '---\nstatus: planned\n# note\nvision:\n  - PV-01  # c\n---\n\n'
        '## Feature name\nn\n\n## Feature goal\ng\n',
      );
    });

    test('f05/us01/fr03/e04: a doc without frontmatter gets none', () async {
      final feature = await _feature();

      final text = _format(
        '## Feature goal\ng\n\n## Feature name\nn\n',
        feature,
      );

      expect(text, isNot(contains('---')));
      expect(text, '## Feature name\nn\n\n## Feature goal\ng\n');
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
        '## Feature name\nn\n\n\n\n## Feature goal\ng',
        feature,
      );

      expect(text, '## Feature name\nn\n\n## Feature goal\ng\n');
      expect(text.endsWith('\n\n'), isFalse);
    });

    test('f05/us01/fr04/e01, s03/inv5: a header matches apart from case and '
        'whitespace and is written as the template writes it', () async {
      final feature = await _feature();

      expect(
        _format('## feature   goal\ng\n\n## FEATURE NAME\nn\n', feature),
        '## Feature name\nn\n\n## Feature goal\ng\n',
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

    test('f05/us01/fr05, s03/inv3: a missing required section is added from '
        'its template after the section before it', () async {
      final feature = await _feature();

      expect(
        _format('## Feature name\nn\n', feature),
        '## Feature name\nn\n\n## Feature goal\n- **why:**\n',
      );
    });

    test('f05/us01/fr05, s03/inv3: a required section without a template is '
        'added as its header alone', () async {
      final feature = await _feature();

      expect(
        _format('## Feature goal\ng\n', feature),
        '## Feature name\n\n## Feature goal\ng\n',
      );
    });

    test('f05/us01/fr05/e01, s03/inv3: a missing optional section stays '
        'absent', () async {
      final feature = await _feature();

      final text = _format(
        '## Feature name\nn\n\n## Feature goal\ng\n',
        feature,
      );

      expect(text, isNot(contains('Feature flow')));
    });

    test('f05/us01/fr05/e02, s03/inv4: an added section leaves every key '
        'block as written', () async {
      final feature = await _feature();

      final text = _format(
        '---\ndraft: false\n---\n\n## Feature name\nn\n',
        feature,
      );

      expect(
        text,
        '---\ndraft: false\n---\n\n## Feature name\nn\n\n'
        '## Feature goal\n- **why:**\n',
      );
    });

    test('doc_model/s03/inv6, s03/inv2: a keyless frontmatter block is '
        'emitted first and verbatim', () async {
      final feature = await _feature();
      const above =
          '---\n  orphan: line\nvision:\n  - PV-01\nstatus: planned\n---\n\n'
          '## Feature name\nn\n\n## Feature goal\ng\n';

      final keyless = Doc.parse(above).frontmatter!.first;
      expect(keyless.key, isEmpty);
      expect(
        _format(above, feature),
        '---\n  orphan: line\nstatus: planned\nvision:\n  - PV-01\n---\n\n'
        '## Feature name\nn\n\n## Feature goal\ng\n',
      );
    });

    test('doc_model/s03/inv6: a keyless block in an already formatted doc '
        'survives formatting unchanged', () async {
      final feature = await _feature();
      const disk =
          '---\n  orphan: line\nstatus: planned\n---\n\n'
          '## Feature name\nn\n\n## Feature goal\ng\n';

      expect(_format(disk, feature), disk);
    });

    test('empty head: a doc with no frontmatter and no head starts with its '
        'first section', () async {
      final feature = await _feature();

      expect(
        _format('## Feature name\nx\n\n## Feature goal\ng\n', feature),
        '## Feature name\nx\n\n## Feature goal\ng\n',
      );
    });

    test('empty head: frontmatter and an empty head put exactly one blank '
        'line before the first section', () async {
      final feature = await _feature();

      for (final gap in ['', '\n', '\n\n\n']) {
        expect(
          _format(
            '---\nstatus: planned\n---\n$gap## Feature name\nx\n\n'
            '## Feature goal\ng\n',
            feature,
          ),
          '---\nstatus: planned\n---\n\n## Feature name\nx\n\n'
          '## Feature goal\ng\n',
          reason: 'gap ${gap.length}',
        );
      }
    });

    test('s03/inv7: formatting a Formatted text again yields the same '
        'text', () async {
      final feature = await _feature();
      const disk =
          '---\nzeta: 1\nstatus: planned\n---\n\n# T\n\nlead\n\n\n'
          '## Feature goal\ng\n```\n## not a header\n```\n\n\n';

      final once = _format(disk, feature);
      final twice = formatDoc(Doc.parse(once), feature) as Formatted;

      expect(twice.text, once);
    });
  });
}
