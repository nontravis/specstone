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
            .where((finding) => finding['docPath'] == docPath);
    expect(
      findings.map((finding) => finding['kind']),
      containsAll(['required_section_missing', 'field_undeclared']),
    );
  });
}
