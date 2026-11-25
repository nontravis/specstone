import 'dart:io';

import 'package:test/test.dart';

import 'helpers/package_root.dart';

/// A `Process.run` or `Process.runSync` call on a name that holds the built
/// binary; the call text runs to the first closing `);`.
final _builtSpawn = RegExp(
  r'Process\.(?:run|runSync)\(\s*'
  r'(?:binary|bin|exe|builtBin|await buildSpecstone\(\))\s*,[\s\S]*?\);',
);

void main() {
  test('every spawn of the built binary goes through runSpecstone', () {
    final testRoot = Directory.fromUri(packageRoot().uri.resolve('test/'));
    final helper = File.fromUri(testRoot.uri.resolve('helpers/built_cli.dart'));
    final offenders = <String>[];
    for (final file in testRoot.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.uri == helper.uri) continue;
      for (final match in _builtSpawn.allMatches(file.readAsStringSync())) {
        // A call that reads raw bytes cannot take the UTF-8 helper.
        if (match.group(0)!.contains('stdoutEncoding: null')) continue;
        offenders.add(file.uri.path.substring(testRoot.uri.path.length));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'use runSpecstone or runSpecstoneSync from built_cli.dart',
    );
  });
}
