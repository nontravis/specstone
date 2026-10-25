// The test titles are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
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

  const damagedWarning =
      'the index was damaged and was rebuilt from the markdown files';
  // Zeroes the root page of each table only an answer reads, so the session
  // opens and refreshes, and the answer's first read of them fails.
  void loseAnswerPages(Directory project) {
    final index = File('${project.path}/.specstone/index.sqlite');
    final db = sqlite3.open(index.path);
    final pageSize = db.select('PRAGMA page_size').single.columnAt(0) as int;
    final roots = [
      for (final row in db.select(
        'SELECT rootpage FROM sqlite_master '
        "WHERE name IN ('sections', 'links', 'doc_search_content')",
      ))
        row.columnAt(0) as int,
    ];
    db.close();
    final bytes = index.readAsBytesSync();
    for (final root in roots) {
      bytes.fillRange((root - 1) * pageSize, root * pageSize, 0);
    }
    index.writeAsBytesSync(bytes);
  }

  const answerCommands = <List<String>>[
    ['get', 'login'],
    ['search', 'password'],
    ['refs', 'login'],
    ['context', 'login', '--for', 'implement'],
  ];
  for (final command in answerCommands) {
    test(
      'f01/us01/fr05/e03, s03/inv23: ${command.first} answers as an intact index does, with the damaged warning, when a page only the answer reads is lost',
      () async {
        final project = await writeReadProject();
        final intact = readRunner(project);
        expect(await intact.runner.run(command), 0);
        loseAnswerPages(project);
        final (:runner, :out, :err) = readRunner(project);
        expect(await runner.run(command), 0, reason: err.toString());
        expect(err.toString(), '⚠️ WARNING: $damagedWarning\n${intact.err}');
        expect(out.toString(), intact.out.toString());
      },
    );
    test(
      'f01/us01/fr05/e03, s03/inv23: ${command.first} --json answers as an intact index does, with the damaged warning, when a page only the answer reads is lost',
      () async {
        final project = await writeReadProject();
        final json = [...command, '--json'];
        final intact = readRunner(project);
        expect(await intact.runner.run(json), 0);
        loseAnswerPages(project);
        final (:runner, :out, :err) = readRunner(project);
        expect(await runner.run(json), 0, reason: err.toString());
        expect(err.toString(), isEmpty);
        final expected =
            jsonDecode(intact.out.toString()) as Map<String, Object?>;
        expect(jsonDecode(out.toString()), {
          ...expected,
          'warnings': [
            damagedWarning,
            ...expected['warnings']! as List<Object?>,
          ],
        });
      },
    );
  }
}
