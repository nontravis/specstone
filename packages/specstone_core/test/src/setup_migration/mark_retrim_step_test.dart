import 'package:specstone_core/src/setup_migration/mark_retrim_step.dart';
import 'package:specstone_core/src/templates/models/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/merged_field.dart';
import 'package:specstone_core/src/templates/models/merged_lint.dart';
import 'package:specstone_core/src/templates/models/merged_section.dart';
import 'package:test/test.dart';

const _sections = [
  MergedSection(id: 'statement', header: 'Statement'),
  MergedSection(id: 'edge_cases', header: 'Edge cases'),
  MergedSection(id: 'rationale', header: 'Rationale'),
  MergedSection(id: 'verification', header: 'Verification'),
];

MergedDocType _type({Set<String> disabled = const {}}) => MergedDocType(
  id: 'fr',
  fields: builtInFields,
  sections: _sections,
  lint: const MergedLint(),
  files: const [],
  disabledSectionIds: disabled,
);

String _marked(
  String lf, {
  List<String> sections = const ['edge_cases', 'verification'],
  Set<String> disabled = const {},
}) => withRetrimMarked(
  lf,
  docType: _type(disabled: disabled),
  sections: sections,
);

const _doc =
    '# Validate\n\n## Statement\n\nThe system shall refuse.\n\n'
    '## Edge cases\n\n1. E01 — Empty → refused.\n\n'
    '## Rationale\n\nBecause.\n\n'
    '## Verification\n\nTest: a wrong password is refused.\n';

void main() {
  test('each listed section with content joins retrim once, in list order', () {
    final marked = _marked(_doc);

    expect(
      marked,
      '---\nretrim:\n  - edge_cases\n  - verification\n---\n\n$_doc',
    );
    expect(_marked(marked), marked, reason: 'a listed id joins once');
  });

  final absentCase = _doc.replaceFirst(
    '## Edge cases\n\n1. E01 — Empty → refused.\n',
    '',
  );
  final emptyCase = _doc.replaceFirst(
    '## Edge cases\n\n1. E01 — Empty → refused.\n',
    '## Edge cases\n',
  );
  for (final (label, lf, disabled, sections) in [
    ('absent', absentCase, const <String>{}, const ['edge_cases']),
    ('empty', emptyCase, const <String>{}, const ['edge_cases']),
    ('disabled', _doc, const {'edge_cases'}, const ['edge_cases']),
    (
      'already marked',
      '---\nretrim:\n  - edge_cases\n---\n$_doc',
      const <String>{},
      const ['edge_cases'],
    ),
  ]) {
    test('a listed section that is absent, empty, disabled, or already marked '
        'adds no id', () {
      final marked = withRetrimMarked(
        lf,
        docType: _type(disabled: disabled),
        sections: sections,
      );

      expect(marked, lf, reason: label);
    });
  }

  test('a second run returns the text unchanged', () {
    final once = _marked(_doc);

    expect(_marked(once), once);
  });

  test('a held flow or quoted retrim list keeps its entries byte for byte', () {
    for (final (held, marked) in [
      ('retrim: [edge_cases]', 'retrim:\n  - edge_cases\n  - verification'),
      (
        'retrim:\n  - "edge_cases"',
        'retrim:\n  - "edge_cases"\n  - "verification"',
      ),
      (
        "retrim:\n  - 'edge_cases'",
        "retrim:\n  - 'edge_cases'\n  - 'verification'",
      ),
    ]) {
      final lf = '---\n$held\n---\n$_doc';

      expect(_marked(lf), '---\n$marked\n---\n$_doc', reason: held);
    }
  });

  test('a non-list retrim value is left as written', () {
    const lf = '---\nretrim: edge_cases\n---\n$_doc';

    expect(_marked(lf), lf);
  });

  test('no section text changes', () {
    final marked = _marked(_doc);

    expect(
      marked,
      '---\nretrim:\n  - edge_cases\n  - verification\n---\n\n$_doc',
    );
    expect(marked.substring(marked.indexOf('# Validate')), _doc);
  });
}
