// The test titles are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:test/test.dart';

import '../../helpers/read_fixture.dart';

void main() {
  const commands = <List<String>>[
    ['list', 'feature'],
    ['get', 'login'],
    ['search', 'password'],
    ['refs', 'login'],
    ['structure'],
    ['context', 'login', '--for', 'implement'],
  ];
  for (final command in commands) {
    test(
      'f01/us01/fr05/e03, s03/inv23: ${command.first} answers with the damaged warning when the index lost its later pages',
      () async {
        final project = await writeReadProject();
        expect(await readRunner(project).runner.run(command), 0);
        final index = File('${project.path}/.specstone/index.sqlite');
        final bytes = index.readAsBytesSync();
        // Page 1 and the file size survive, so opening the file succeeds; the
        // first read of a lost page is what fails.
        index.writeAsBytesSync([
          ...bytes.sublist(0, 4096),
          ...List<int>.filled(bytes.length - 4096, 0xAB),
        ]);
        final (:runner, :out, :err) = readRunner(project);
        expect(await runner.run(command), 0, reason: err.toString());
        expect(
          err.toString(),
          '⚠️ WARNING: the index was damaged and was rebuilt from the markdown files\n',
        );
      },
    );
  }
}
