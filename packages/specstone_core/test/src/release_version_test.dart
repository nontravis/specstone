import 'dart:io';

import 'package:specstone_core/release_version.dart';
import 'package:test/test.dart';

import '../helpers/package_root.dart';
import '../helpers/version_cases.dart';

void main() {
  final anchored = RegExp('^$releaseVersionPattern\$');

  for (final text in acceptedVersions) {
    test('install_update Version: accepts ${_show(text)}', () {
      expect(ReleaseVersion.tryParse(text)?.toString(), text);
      expect(anchored.hasMatch(text), isTrue);
    });
  }

  for (final text in refusedVersions) {
    test('install_update Version: refuses ${_show(text)}', () {
      expect(ReleaseVersion.tryParse(text), isNull);
      expect(anchored.hasMatch(text), isFalse);
    });
  }

  test('install_update Version: every ascending entry is also accepted', () {
    expect(acceptedVersions, containsAll(ascendingVersions));
  });

  for (var i = 0; i + 1 < ascendingVersions.length; i++) {
    final below = ascendingVersions[i];
    final above = ascendingVersions[i + 1];
    test('install_update Version: $below is below $above', () {
      final a = ReleaseVersion.tryParse(below)!;
      final b = ReleaseVersion.tryParse(above)!;
      expect(a.compareTo(b), isNegative);
      expect(b.compareTo(a), isPositive);
    });
  }

  for (final text in ascendingVersions) {
    test('install_update Version: $text equals a second parse of itself', () {
      final first = ReleaseVersion.tryParse(text)!;
      final second = ReleaseVersion.tryParse(text)!;
      expect(first.compareTo(second), 0);
    });
  }

  for (final text in acceptedVersions) {
    // A leading dash is refused, so a dash in an accepted entry always opens
    // its pre-release part.
    test('install_update Version: isPreRelease of $text follows its dash', () {
      expect(ReleaseVersion.tryParse(text)!.isPreRelease, text.contains('-'));
    });
  }

  test('install_update Version: the definition imports nothing', () {
    final source = File.fromUri(
      packageRoot().uri.resolve('lib/src/release_version.dart'),
    ).readAsLinesSync();
    expect(source.where((line) => line.startsWith('import ')), isEmpty);
  });
}

String _show(String text) {
  final escaped = text.replaceAllMapped(RegExp(r'[\x00-\x1f]'), (match) {
    final code = match[0]!.codeUnitAt(0).toRadixString(16).padLeft(2, '0');
    return '\\x$code';
  });
  return "'$escaped'";
}
