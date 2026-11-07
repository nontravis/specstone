import 'dart:io';

// markdown exports no case-folding table, so this reads its source.
import 'package:markdown/src/assets/case_folding.dart';
import 'package:specstone_core/src/index_query/case_folding.g.dart';
import 'package:test/test.dart';

import '../../tool/generate_case_folding.dart';
import '../helpers/package_root.dart';

void main() {
  group('renderCaseFolding', () {
    test('writes each entry in order, escaping what a literal cannot hold', () {
      final text = renderCaseFolding({
        'A': 'a',
        String.fromCharCode(0x1E9E): 'ss',
        String.fromCharCodes([0xD801, 0xDC00]): String.fromCharCodes([
          0xD801,
          0xDC28,
        ]),
        r"'\$": 'x',
      });

      expect(text, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND\n'));
      expect(
        text,
        contains(
          "  'A': 'a',\n"
          r"  '\u{1E9E}': 'ss',"
          '\n'
          r"  '\u{10400}': '\u{10428}',"
          '\n'
          r"  '\u{27}\u{5C}\u{24}': 'x',"
          '\n};\n',
        ),
      );
    });

    test('the rendered text is dart format stable', () {
      final out = File(
        '${Directory.systemTemp.path}/specstone_case_folding_render.dart',
      );
      addTearDown(out.deleteSync);
      out.writeAsStringSync(renderCaseFolding(caseFoldingMap));
      final result = Process.runSync(Platform.resolvedExecutable, [
        'format',
        '--output=none',
        '--set-exit-if-changed',
        out.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}');
    });
  });

  group('committed output', () {
    test(
      "case_folding.g.dart equals renderCaseFolding over markdown's table",
      () {
        final committed = File.fromUri(
          packageRoot().uri.resolve('lib/src/index_query/case_folding.g.dart'),
        );

        expect(committed.readAsStringSync(), renderCaseFolding(caseFoldingMap));
        expect(markdownCaseFolding, caseFoldingMap);
      },
    );
  });
}
