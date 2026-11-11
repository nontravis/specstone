import 'package:specstone_core/release_version.dart';
import 'package:test/test.dart';

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

  for (final text in {...acceptedVersions, ...ascendingVersions}) {
    test('install_update Version: isPreRelease of $text follows its dash', () {
      expect(ReleaseVersion.tryParse(text)!.isPreRelease, text.contains('-'));
    });
  }
}

String _show(String text) =>
    "'${text.replaceAll('\n', r'\n').replaceAll('\r', r'\r')}'";
