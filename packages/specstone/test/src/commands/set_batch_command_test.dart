// The expected texts are doc literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/built_cli.dart';

const _story = 'document_writing/edit_one_section_or_field';
const _wb = '$_story/write_a_batch';

typedef _Run = ({int code, String out, String err});

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  /// Runs the built CLI in [root] with [args] and [stdin] on a pipe.
  Future<_Run> specstone(
    Directory root,
    List<String> args, {
    String stdin = '',
  }) async {
    final home = testHome().path;
    final process = await Process.start(
      binary,
      args,
      workingDirectory: root.path,
      environment: {'HOME': home, 'USERPROFILE': home},
    );
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    // A run that refuses before it reads stdin may close the pipe first.
    process.stdin.done.ignore();
    try {
      process.stdin.write(stdin);
      await process.stdin.close();
    } on SocketException {
      // The refusal came first; nothing to write.
    }
    return (code: await process.exitCode, out: await out, err: await err);
  }

  /// Returns what `get` prints for [names], as an Agent reads it.
  Future<String> getText(Directory root, List<String> names) async {
    final result = await specstone(root, ['get', ...names]);
    expect(result.code, 0, reason: result.err);
    return result.out;
  }

  /// Writes [text] to a batch file outside the project and returns its path.
  Future<String> batchFile(String text) async {
    final folder = await Directory.systemTemp.createTemp('specstone_batch_');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/batch.md');
    await file.writeAsString(text);
    return file.path;
  }

  Map<String, Object?> decode(String text) =>
      jsonDecode(text) as Map<String, Object?>;

  String edit(String text, String from, String to) {
    expect(text, contains(from), reason: 'the edit target is in the text');
    return text.replaceFirst(from, to);
  }

  Map<String, List<int>> docBytes(Directory root) =>
      treeBytes(Directory('${root.path}/docs'));

  String journalOf(Directory root) => '${root.path}/${MoveJournal.journalPath}';

  test(
    '$_story S14: three docs read in one call, one unchanged, write each changed doc and print each base, the unchanged doc kept',
    () async {
      final root = await writeWriteProject();
      final untouched = docFile(root, loginArch).readAsBytesSync();
      var text = await getText(root, [story2, fr11, loginArch]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(text, 'check the email', 'check the email twice, then');
      final file = await batchFile(text);

      final result = await specstone(root, ['set', '--batch', file]);

      expect(result.code, 0, reason: result.err);
      expect(result.err, isEmpty);
      expect(readDoc(root, story2), contains('Sign out everywhere.'));
      expect(readDoc(root, story2), contains('draft: true\n'));
      expect(readDoc(root, fr11), contains('check the email twice, then'));
      expect(docFile(root, loginArch).readAsBytesSync(), untouched);
      final lines = result.out.trimRight().split('\n');
      expect(lines, hasLength(3));
      expect(
        lines[0],
        matches(
          RegExp(
            '^==> login/sign_out \\(user_story\\) · ${RegExp.escape(story2)} · base [0-9a-f]{12} <==\$',
          ),
        ),
      );
      expect(lines[1], endsWith(' <=='));
      expect(lines[1], isNot(contains('unchanged')));
      expect(lines[2], endsWith(' · unchanged <=='));
      expect(File(journalOf(root)).existsSync(), isFalse);
    },
  );

  test(
    '$_story S15: one stale doc refuses the whole batch, writes no doc, and prints its current text under its naming line, exit 75',
    () async {
      final root = await writeWriteProject();
      var text = await getText(root, [story2, fr11]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(text, 'check the email', 'check the email twice, then');
      final file = await batchFile(text);
      final changed = readDoc(
        root,
        fr11,
      ).replaceFirst('shall check', 'shall carefully check');
      docFile(root, fr11).writeAsStringSync(changed);
      final before = docBytes(root);

      final result = await specstone(root, ['set', '--batch', file]);

      expect(result.code, 75);
      expect(docBytes(root), before);
      expect(
        result.err,
        matches(
          RegExp(
            '^${RegExp.escape(fr11)}: doc: the doc changed since base [0-9a-f]{12}\n\$',
          ),
        ),
      );
      final heading = RegExp(
        '^==> login/email_login/validate_credentials \\(fr\\) · ${RegExp.escape(fr11)} · base [0-9a-f]{12} <==\n',
      );
      expect(result.out, matches(heading));
      expect(result.out.replaceFirst(heading, ''), changed);
    },
  );

  test(
    '$_wb E02: two stale blocks print each current text under its naming line, in file order, on stdout only',
    () async {
      final root = await writeWriteProject();
      var text = await getText(root, [story2, fr11]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(text, 'check the email', 'check the email twice, then');
      final file = await batchFile(text);
      final signOut = readDoc(
        root,
        story2,
      ).replaceFirst('Sign out.', 'Sign out now.');
      final validate = readDoc(
        root,
        fr11,
      ).replaceFirst('shall check', 'shall carefully check');
      docFile(root, story2).writeAsStringSync(signOut);
      docFile(root, fr11).writeAsStringSync(validate);

      final result = await specstone(root, ['set', '--batch', file]);

      expect(result.code, 75);
      expect(result.err.trimRight().split('\n'), hasLength(2));
      final firstAt = result.out.indexOf(signOut);
      final secondAt = result.out.indexOf(validate);
      expect(firstAt, greaterThan(0));
      expect(secondAt, greaterThan(firstAt + signOut.length));
      expect(
        RegExp('^==> ', multiLine: true).allMatches(result.out),
        hasLength(2),
      );
    },
  );

  test(
    '$_wb E02: --json with only stale blocks exits 75, prints nothing on stdout, and each blocks entry carries its current text',
    () async {
      final root = await writeWriteProject();
      var text = await getText(root, [story2, fr11]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(text, 'check the email', 'check the email twice, then');
      final file = await batchFile(text);
      final signOut = readDoc(
        root,
        story2,
      ).replaceFirst('Sign out.', 'Sign out now.');
      final validate = readDoc(
        root,
        fr11,
      ).replaceFirst('shall check', 'shall carefully check');
      docFile(root, story2).writeAsStringSync(signOut);
      docFile(root, fr11).writeAsStringSync(validate);
      final before = docBytes(root);

      final result = await specstone(root, ['set', '--batch', file, '--json']);

      expect(result.code, 75);
      expect(result.out, isEmpty);
      expect(docBytes(root), before);
      final error = decode(result.err)['error']! as Map<String, Object?>;
      expect(error['code'], 'base_mismatch');
      final blocks = (error['blocks']! as List).cast<Map<String, Object?>>();
      expect(blocks.map((b) => b['file']), [story2, fr11]);
      expect(blocks.map((b) => (b['current']! as Map)['text']), [
        signOut,
        validate,
      ]);
    },
  );

  test(
    '$_wb E04: a stale block beside a block whose doc is gone names both, prints the stale text, exit 64',
    () async {
      final root = await writeWriteProject();
      var text = await getText(root, [story2, fr11]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(text, 'check the email', 'check the email twice, then');
      final file = await batchFile(text);
      final changed = readDoc(
        root,
        story2,
      ).replaceFirst('Sign out.', 'Sign out now.');
      docFile(root, story2).writeAsStringSync(changed);
      docFile(root, fr11).deleteSync();
      final before = docBytes(root);

      final text64 = await specstone(root, ['set', '--batch', file]);

      expect(text64.code, 64);
      expect(docBytes(root), before);
      final lines = text64.err.trimRight().split('\n');
      expect(lines, hasLength(2));
      expect(
        lines[0],
        matches(
          RegExp(
            '^${RegExp.escape(story2)}: doc: the doc changed since base [0-9a-f]{12}\$',
          ),
        ),
      );
      expect(lines[1], startsWith(fr11));
      expect(text64.out, contains(changed));

      final json = await specstone(root, ['set', '--batch', file, '--json']);

      expect(json.code, 64);
      expect(json.out, isEmpty);
      final error = decode(json.err)['error']! as Map<String, Object?>;
      expect(error['code'], 'base_mismatch');
      expect(error['file'], story2);
      expect(error['key'], 'doc');
      final blocks = (error['blocks']! as List).cast<Map<String, Object?>>();
      expect(blocks.map((b) => b['file']), [story2, fr11]);
      expect((blocks[0]['current']! as Map)['text'], changed);
    },
  );

  test(
    '$_wb: --json prints one object holding blocks in file order and an empty warnings array',
    () async {
      final root = await writeWriteProject();
      var text = await getText(root, [story2, fr11, loginArch]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(
        text,
        'Collects the email and the password',
        'Collects the email',
      );
      final file = await batchFile(text);

      final result = await specstone(root, ['set', '--batch', file, '--json']);

      expect(result.code, 0, reason: result.err);
      expect(result.err, isEmpty);
      final printed = decode(result.out);
      expect(printed.keys, unorderedEquals(['blocks', 'warnings']));
      expect(printed['warnings'], isEmpty);
      final blocks = (printed['blocks']! as List).cast<Map<String, Object?>>();
      expect(blocks.map((b) => b['path']), [story2, fr11, loginArch]);
      expect(blocks.map((b) => b['written']), [true, false, true]);
      for (final block in blocks) {
        expect(block.keys, containsAll(['name', 'docType', 'path', 'key']));
        expect(block['key'], 'doc');
        expect(block['base'], matches(RegExp(r'^[0-9a-f]{12}$')));
        expect(block['draft'], isA<bool>());
      }
    },
  );

  group('$_wb E13:', () {
    test('a doc address beside --batch refuses argument_conflict, before the file is read', () async {
      final root = await writeWriteProject();
      final before = docBytes(root);

      final result = await specstone(root, [
        'set',
        'user_story:login/sign_out#use_case',
        '--batch',
        'missing.md',
        '--json',
      ]);

      expect(result.code, 64);
      expect(result.out, isEmpty);
      expect(
        (decode(result.err)['error']! as Map)['code'],
        'argument_conflict',
      );
      expect(docBytes(root), before);
    });

    test('--base beside --batch refuses argument_conflict', () async {
      final root = await writeWriteProject();
      final file = await batchFile(await getText(root, [story2]));

      final result = await specstone(root, [
        'set',
        '--batch',
        file,
        '--base',
        '7e11fc4a24d2',
        '--json',
      ]);

      expect(result.code, 64);
      expect(
        (decode(result.err)['error']! as Map)['code'],
        'argument_conflict',
      );
    });

    test('--field or --title beside --batch refuses argument_conflict and writes nothing', () async {
      final root = await writeWriteProject();
      final text = edit(
        await getText(root, [story2]),
        'Sign out.',
        'Sign out everywhere.',
      );
      final file = await batchFile(text);
      final before = docBytes(root);

      for (final flag in [
        ['--field', 'size'],
        ['--title'],
      ]) {
        final result = await specstone(root, [
          'set',
          '--batch',
          file,
          ...flag,
          '--json',
        ]);

        expect(result.code, 64, reason: '$flag');
        expect(result.out, isEmpty);
        expect(
          (decode(result.err)['error']! as Map)['code'],
          'argument_conflict',
          reason: '$flag',
        );
        expect(docBytes(root), before);
      }
    });

    test('stdin is never read: an open pipe that never closes does not hold the run, and its text is ignored', () async {
      final root = await writeWriteProject();
      final text = edit(
        await getText(root, [story2]),
        'Sign out.',
        'Sign out everywhere.',
      );
      final file = await batchFile(text);
      final home = testHome().path;
      final process = await Process.start(
        binary,
        ['set', '--batch', file],
        workingDirectory: root.path,
        environment: {'HOME': home, 'USERPROFILE': home},
      );
      addTearDown(process.kill);
      process.stdout.drain<void>().ignore();
      process.stderr.drain<void>().ignore();
      process.stdin.done.ignore();
      process.stdin.write('ignored text\n');

      final code = await process.exitCode.timeout(
        const Duration(seconds: 30),
        onTimeout: () => -1,
      );

      expect(code, 0, reason: 'the run finished without stdin closing');
      expect(readDoc(root, story2), contains('Sign out everywhere.'));
      expect(readDoc(root, story2), isNot(contains('ignored text')));
    });
  });

  group('$_wb E17:', () {
    test('a path that cannot be read refuses alone: one stderr line, path as given', () async {
      final root = await writeWriteProject();

      final result = await specstone(root, ['set', '--batch', 'nope.md']);

      expect(result.code, 64);
      expect(result.out, isEmpty);
      expect(result.err, 'nope.md: cannot read nope.md\n');
    });

    test(
      '--json carries code, message, and file, and no blocks array',
      () async {
        final root = await writeWriteProject();

        final result = await specstone(root, [
          'set',
          '--batch',
          'nope.md',
          '--json',
        ]);

        expect(result.code, 64);
        expect(result.out, isEmpty);
        expect(decode(result.err), {
          'error': {
            'code': 'argument_invalid',
            'message': 'cannot read nope.md',
            'file': 'nope.md',
          },
        });
      },
    );

    test('a file of text with no naming line holds no block', () async {
      final root = await writeWriteProject();
      final file = await batchFile('just text\n');

      final result = await specstone(root, ['set', '--batch', file]);

      expect(result.code, 64);
      expect(result.err, '$file: $file holds no block\n');
    });

    test('a file with no block refuses before the project opens, so outside a project it exits 64 and not 78', () async {
      final folder = await Directory.systemTemp.createTemp('specstone_bare_');
      addTearDown(() => folder.delete(recursive: true));
      final file = await batchFile('just text\n');

      final result = await specstone(folder, ['set', '--batch', file]);

      expect(result.code, 64);
      expect(result.err, '$file: $file holds no block\n');
    });
  });

  group('$_wb E18:', () {
    test('a stray line before the first naming line is a line fault beside every other fault, exit 64', () async {
      final root = await writeWriteProject();
      final text = edit(
        await getText(root, [story2]),
        'Sign out.',
        'Sign out everywhere.',
      );
      final file = await batchFile('stray\n$text');
      final before = docBytes(root);

      final plain = await specstone(root, ['set', '--batch', file]);

      expect(plain.code, 64);
      expect(plain.out, isEmpty);
      expect(plain.err, '$file:1: text before the first naming line\n');
      expect(docBytes(root), before);

      final json = await specstone(root, ['set', '--batch', file, '--json']);

      expect(json.code, 64);
      expect(json.out, isEmpty);
      final error = decode(json.err)['error']! as Map<String, Object?>;
      expect(error['code'], 'argument_invalid');
      expect(error['file'], file);
      expect(error['line'], 1);
      expect(error.containsKey('key'), isFalse);
      final blocks = (error['blocks']! as List).cast<Map<String, Object?>>();
      expect(blocks, hasLength(1));
      expect(blocks.single['line'], 1);
    });

    test("a reply's own unchanged line is no naming line with a base, so a batch file holding it refuses", () async {
      final root = await writeWriteProject();
      final text = await getText(root, [story2]);
      final unchanged = await specstone(root, [
        'set',
        '--batch',
        await batchFile(text),
      ]);
      final file = await batchFile('${unchanged.out}\n$text');

      final result = await specstone(root, ['set', '--batch', file]);

      expect(result.code, 64);
      expect(result.err, startsWith('$file:1: '));
    });
  });

  test(
    '$_wb: get a b c written back unedited prints only unchanged lines, exit 0, no write and no journal',
    () async {
      final root = await writeWriteProject();
      final text = await getText(root, [
        story2,
        '$story1#use_case',
        fr11,
        loginArch,
      ]);
      final file = await batchFile(text);
      final before = docBytes(root);

      final result = await specstone(root, ['set', '--batch', file]);

      expect(result.code, 0, reason: result.err);
      expect(result.err, isEmpty);
      final lines = result.out.trimRight().split('\n');
      expect(lines, hasLength(4));
      expect(lines, everyElement(endsWith(' · unchanged <==')));
      expect(docBytes(root), before);
      expect(File(journalOf(root)).existsSync(), isFalse);
    },
  );
}
