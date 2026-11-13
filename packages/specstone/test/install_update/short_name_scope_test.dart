import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

void main() {
  // `\b` leaves words such as `stnd` and `stn_x` alone only at a letter edge;
  // an underscore counts as a word character, so `stn_x` is not a match.
  final stn = RegExp(r'\bstn\b');

  // The folders whose files teach, run, or write for agents: they name
  // `specstone`, never `stn`.
  const scannedFolders = [
    'plugin/',
    'packages/specstone/lib/',
    'packages/specstone_core/lib/',
    'packages/specstone_core/assets/agent/',
  ];

  List<String> trackedFiles() {
    final result = Process.runSync('git', [
      'ls-files',
      '-z',
    ], workingDirectory: repoRoot().path);
    if (result.exitCode != 0) {
      throw StateError('git ls-files failed: ${result.stderr}');
    }
    return (result.stdout as String)
        .split('\x00')
        .where((path) => path.isNotEmpty)
        .toList();
  }

  List<int> stnLines(String path) {
    final lines = const LineSplitter().convert(
      const Utf8Decoder(allowMalformed: true)
          .convert(File('${repoRoot().path}/$path').readAsBytesSync()),
    );
    return [
      for (var i = 0; i < lines.length; i++)
        if (stn.hasMatch(lines[i])) i + 1,
    ];
  }

  test('run_by_short_name BR-04: the README names stn on exactly one line', () {
    expect(stnLines('README.md'), hasLength(1));
  });

  test('run_by_short_name BR-04: no tracked file the CLI writes for agents, '
      'the plugin, or the CLI messages names stn', () {
    final offenders = [
      for (final path in trackedFiles())
        if (scannedFolders.any(path.startsWith) && File(path).existsSync())
          for (final line in stnLines(path)) '$path:$line',
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'name specstone, not stn, in: $offenders',
    );
  });
}
