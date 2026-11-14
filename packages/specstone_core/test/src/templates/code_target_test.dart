import 'package:specstone_core/src/templates/code_target.dart';
import 'package:test/test.dart';

void main() {
  group('doc_model RULE-20: twinNamesOf', () {
    test('two or more names read per-target folders, in config order', () {
      expect(twinNamesOf(['flutter', 'jaspr']), ['flutter', 'jaspr']);
    });

    test('one named target or none reads no target folder', () {
      expect(twinNamesOf(['flutter']), isEmpty);
      expect(twinNamesOf(const []), isEmpty);
    });
  });

  group('nestedPathsOf finds the code roots nested in a '
      'code root', () {
    test(
      'windows paths: a nested root is found under its native separator',
      () {
        expect(
          nestedPathsOf(r'C:\p\ws', [
            r'C:\p\ws\web',
            r'C:\p\ws\a\b',
            r'C:\p\ws2',
            r'C:\p\ws',
          ], isWindows: true),
          ['web', 'a/b'],
        );
      },
    );

    test('windows paths: a drive root holds every root on that drive', () {
      expect(nestedPathsOf(r'C:\', [r'C:\ws\web'], isWindows: true), [
        'ws/web',
      ]);
    });

    test('posix paths: a nested root is found under /', () {
      expect(
        nestedPathsOf('/p/ws', [
          '/p/ws/web',
          '/p/ws/a/b',
          '/p/ws2',
          '/p/ws',
        ], isWindows: false),
        ['web', 'a/b'],
      );
    });

    test(r'posix paths: a \ is a name character, never a separator', () {
      expect(nestedPathsOf('/p/ws', [r'/p/ws\web'], isWindows: false), isEmpty);
    });
  });
}
