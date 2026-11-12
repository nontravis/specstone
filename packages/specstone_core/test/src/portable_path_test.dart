import 'package:specstone_core/src/portable_path.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show isPortableCodeEntry;
import 'package:test/test.dart';

void main() {
  group('hasWindowsDroppedEnd', () {
    test('a name ending in a space or a dot is dropped', () {
      expect(hasWindowsDroppedEnd(['docs', 'API.md ']), isTrue);
      expect(hasWindowsDroppedEnd(['docs', 'API.']), isTrue);
      expect(hasWindowsDroppedEnd(['lib ', 'a.dart']), isTrue);
      expect(hasWindowsDroppedEnd(['...']), isTrue);
    });

    test('a plain name, an inner dot, `.` and `..` are not', () {
      expect(hasWindowsDroppedEnd(['docs', 'API.md']), isFalse);
      expect(hasWindowsDroppedEnd(['.hidden', 'a b.md']), isFalse);
      expect(hasWindowsDroppedEnd(['..', '.', 'lib', '']), isFalse);
    });
  });

  group('isPortablePath', () {
    test('a backslash or a trimmed name makes a path non-portable', () {
      for (final path in [r'a\b.md', r'..\x', 'a./b', 'lib ', 'a/b.']) {
        expect(isPortablePath(path), isFalse, reason: path);
      }
    });

    test('a plain path, `.` and `..` segments, and an empty one are', () {
      for (final path in ['a/b.md', '../x/./y', '', '/abs', '.hidden/a b']) {
        expect(isPortablePath(path), isTrue, reason: path);
      }
    });
  });

  group('isPortableCodeEntry', () {
    test('a relative / path is portable', () {
      for (final entry in ['lib/', 'lib', './app/lib/', '../shared/lib']) {
        expect(isPortableCodeEntry(entry), isTrue, reason: entry);
      }
    });

    test('a drive letter, a rooted path, a backslash, or empty is not', () {
      for (final entry in ['C:/x/', '/abs/', r'..\shared\', '']) {
        expect(isPortableCodeEntry(entry), isFalse, reason: entry);
      }
    });

    test('a name Windows would trim is not', () {
      for (final entry in ['lib ', 'lib./a', 'app/lib. /x']) {
        expect(isPortableCodeEntry(entry), isFalse, reason: entry);
      }
    });
  });
}
