import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:test/test.dart';

void main() {
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
