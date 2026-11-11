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

  group('install_update Version: a huge text', () {
    // 1.6M identifiers (about 3.2 MB) overflowed the stack of the repeated
    // group in the form; 3M digits made BigInt.parse take about a minute.
    final identifiers = List.filled(1600000, 'a').join('.');
    final digits = '1' * 3000000;

    test('a pre-release of 1.6M identifiers parses', () {
      final version = ReleaseVersion.tryParse('1.0.0-$identifiers');

      expect(version, isNotNull);
      expect(version!.isPreRelease, isTrue);
      expect(version.compareTo(ReleaseVersion.tryParse('1.0.0')!), isNegative);
    });

    test(
      'a pre-release of 1.6M identifiers with a bad last one is refused',
      () {
        expect(ReleaseVersion.tryParse('1.0.0-$identifiers.!'), isNull);
        expect(ReleaseVersion.tryParse('1.0.0-$identifiers.'), isNull);
      },
    );

    test('a core field of 3M digits parses and orders by value', () {
      final big = ReleaseVersion.tryParse('$digits.0.0')!;
      final bigger = ReleaseVersion.tryParse('${digits}0.0.0')!;

      expect(big.compareTo(ReleaseVersion.tryParse('9.9.9')!), isPositive);
      expect(big.compareTo(bigger), isNegative);
      expect(big.compareTo(ReleaseVersion.tryParse('$digits.0.0')!), 0);
    });

    test('a numeric identifier of 3M digits orders by value', () {
      final big = ReleaseVersion.tryParse('1.0.0-$digits')!;
      final bigger = ReleaseVersion.tryParse('1.0.0-${digits}0')!;

      expect(big.compareTo(bigger), isNegative);
      expect(ReleaseVersion.tryParse('1.0.0-${'1' * 3000000}x'), isNotNull);
      expect(ReleaseVersion.tryParse('1.0.0-0${'1' * 3000000}'), isNull);
    });
  });

  test('install_update Version: no Dart file spells the version form by '
      'hand; readers parse through ReleaseVersion.tryParse', () {
    const spellings = [
      r'\d+\.\d+\.\d+',
      r'[0-9]+\.[0-9]+\.[0-9]+',
      r'(\d+)\.(\d+)\.(\d+)',
    ];
    final core = packageRoot().uri;
    final files = [
      for (final folder in [
        'lib/',
        'tool/',
        '../specstone/lib/',
        '../specstone/bin/',
        '../../tool/',
      ])
        for (final entity in Directory.fromUri(
          core.resolve(folder),
        ).listSync(recursive: true, followLinks: false))
          if (entity is File && entity.path.endsWith('.dart')) entity,
    ];
    final readers = [
      for (final file in files)
        if (spellings.any(file.readAsStringSync().contains)) file.path,
    ];

    expect(
      files.map((file) => file.uri.path),
      contains(endsWith('lib/src/release_version.dart')),
      reason: 'the scan must visit the definition',
    );
    expect(readers, isEmpty);
  });
}

String _show(String text) {
  final escaped = text.replaceAllMapped(RegExp(r'[\x00-\x1f]'), (match) {
    final code = match[0]!.codeUnitAt(0).toRadixString(16).padLeft(2, '0');
    return '\\x$code';
  });
  return "'$escaped'";
}
