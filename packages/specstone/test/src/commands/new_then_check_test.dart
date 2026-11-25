import 'dart:convert';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test('a doc created from text that lacks a required section and holds an '
      'undeclared field is reported by check for both', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        input:
            '---\nextra_key: kept\n---\n\n# send_again\n\n'
            '## Statement\n\nThe system shall send the link again.\n',
      ),
    );
    expect(
      await runner.run([
        'new',
        'fr',
        '--parent',
        'login/reset_password',
        '--slug',
        'send_again',
      ]),
      0,
    );
    const docPath =
        'prds/features/f01_login/us03_reset_password/fr03_send_again.md';
    expect(readDoc(root, docPath), contains('extra_key: kept'));

    final (runner: checker, out: checkOut, err: checkErr) = writeRunner(root);
    expect(await checker.run(['check', '--json']), 1, reason: '$checkErr');
    final findings =
        ((jsonDecode(checkOut.toString()) as Map<String, Object?>)['findings']!
                as List<Object?>)
            .cast<Map<String, Object?>>()
            .where((finding) => finding['path'] == docPath);
    expect(
      findings.map((finding) => finding['kind']),
      containsAll(['required_section_missing', 'field_undeclared']),
    );
  });

  test(
    'a domain skeleton lists its blank required sections in check',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['new', 'rulebook', '--parent', 'login']),
        0,
        reason: '$err',
      );
      const docPath = 'specs/f01_login/DOMAIN.md';
      final entitiesLine =
          readDoc(root, docPath).split('\n').indexOf('## Entities') + 1;
      expect(entitiesLine, greaterThan(0));

      final (runner: checker, out: checkOut, err: checkErr) = writeRunner(root);
      await checker.run(['check', '--json']);
      final findings =
          ((jsonDecode(checkOut.toString())
                      as Map<String, Object?>)['findings']!
                  as List<Object?>)
              .cast<Map<String, Object?>>()
              .where((finding) => finding['path'] == docPath);
      expect(
        findings,
        contains(
          allOf(
            containsPair('kind', 'required_section_missing'),
            containsPair('section', 'entities'),
            containsPair('line', entitiesLine),
          ),
        ),
        reason: '$checkOut $checkErr',
      );
    },
  );

  test('check lists each placeholder line a new fr skeleton keeps', () async {
    final root = await writeWriteProject(
      extra: {
        '.specstone/templates/fr.yaml':
            'sections:\n'
            '  - id: statement\n'
            '    template: |-\n'
            '      The <product> shall <verb> it.\n'
            '  - id: edge_cases\n'
            '    template: |-\n'
            '      1. E01 — <trigger> → <response>\n'
            '      2. E02 — <lead> → <response>\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'new',
        'fr',
        '--parent',
        'login/reset_password',
        '--slug',
        'send_again',
      ]),
      0,
      reason: '$err',
    );
    const docPath =
        'prds/features/f01_login/us03_reset_password/fr03_send_again.md';

    final (runner: checker, out: checkOut, err: checkErr) = writeRunner(root);
    await checker.run(['check', '--json']);
    const layerSections = {'statement', 'edge_cases', '_title'};
    final left =
        ((jsonDecode(checkOut.toString()) as Map<String, Object?>)['findings']!
                as List<Object?>)
            .cast<Map<String, Object?>>()
            .where(
              (finding) =>
                  finding['path'] == docPath &&
                  finding['kind'] == 'template_text_left' &&
                  layerSections.contains(finding['section']),
            )
            .map((finding) => finding['section'])
            .toList();
    expect(
      left,
      unorderedEquals(['statement', 'edge_cases', 'edge_cases', '_title']),
      reason: '$checkOut $checkErr',
    );
  });
}
