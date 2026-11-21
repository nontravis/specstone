import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

void main() {
  group('the per-FR rows of a record matrix', () {
    const recordFile = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const validateRow =
        '- email_login/validate_credentials: `a wrong password`, '
        '`an empty password`\n';
    const lockRow = '- email_login/lock_after_failures: `five failures lock`\n';
    const resetRow = '- reset_password/send_reset_link: `a link is mailed`\n';

    String bundleText(DocIndex index, String target, BundleMode mode) =>
        answerContext(
          index,
          pickBundle(index, [target], mode, noProject: false),
          targets: [target],
        ).text;

    Future<DocIndex> recordWith(String rows) => indexWith({
      recordFile:
          "---\nstatuses:\n  - 'email_login:planned'\n---\n\n"
          '# Login implementation\n\n## Verification matrix\n\n$rows',
    });

    test(
      'drops the per-FR row of an FR the bundle does not print whole',
      () async {
        final text = bundleText(
          await recordWith('$validateRow$lockRow$resetRow'),
          'login/email_login',
          BundleMode.implement,
        );

        expect(text, contains(validateRow.trimRight()));
        expect(text, contains(lockRow.trimRight()));
        expect(text, isNot(contains('a link is mailed')));
      },
    );

    test('keeps every row of a record query target', () async {
      final text = bundleText(
        await recordWith('$validateRow$lockRow$resetRow'),
        'implementation:login',
        BundleMode.query,
      );

      for (final row in [validateRow, lockRow, resetRow]) {
        expect(text, contains(row.trimRight()));
      }
    });
  });

  group('SectionLine', () {
    test('shiftedBy moves the section lower by the given lines', () {
      final shifted = const SectionLine(key: 'goals', line: 3).shiftedBy(1);
      expect(shifted.key, 'goals');
      expect(shifted.line, 4);
    });
    test('equals another SectionLine with the same key and line', () {
      expect(
        const SectionLine(key: 'goals', line: 3),
        const SectionLine(key: 'goals', line: 3),
      );
      expect(
        const SectionLine(key: 'goals', line: 3),
        isNot(const SectionLine(key: 'goals', line: 4)),
      );
    });
  });

  group('DocPrint.afterLine', () {
    test('puts the line first and shifts every section by 1', () {
      const print = DocPrint(
        text: '# Title\n\n## Goals\nbody',
        cited: [],
        sections: [SectionLine(key: 'goals', line: 2)],
      );
      final named = print.afterLine('- doc (summary)');
      expect(named.text, '- doc (summary)\n# Title\n\n## Goals\nbody');
      expect(named.sections, [const SectionLine(key: 'goals', line: 3)]);
      expect(named.cited, isEmpty);
    });
    test('keeps an empty section list empty', () {
      const print = DocPrint(text: '# Title', cited: [], sections: []);
      expect(print.afterLine('- doc').sections, isEmpty);
    });
  });
}
