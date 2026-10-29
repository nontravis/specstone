// The test names and file literals are plan text kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/document_writing/approve_drafts.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/write_fixture.dart';

const _prompt = 'approve? [y/n/q] ';

/// Returns the given answers in order, then null.
String? Function() answers(List<String?> list) {
  final queue = [...list];
  return () => queue.isEmpty ? null : queue.removeAt(0);
}

void main() {
  final skipGit = hasGit ? null : 'git is not available';

  test('f02/us03/s7, f02/us03/fr01/e04, dw-s03/inv12: no interactive terminal is owner_terminal_required, exit 77', () {
    expect(
      () => requireOwnerTerminal(interactive: false, message: 'm'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.exitStatus, 'exitStatus', 77)
            .having((f) => f.message, 'message', 'm'),
      ),
    );
    requireOwnerTerminal(interactive: true, message: 'm'); // returns
  });

  test('f02/us03/s1, f02/us03/fr01, f02/us03/fr03, f02/us03/fr03/e01, f02/us03/fr02/e03, dw-s03/inv5: y removes draft and writes approved, text unchanged', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        name: 'signup',
        readLine: answers(['y', 'y']),
        out: out,
      ),
    );
    expect(
      out.toString(),
      startsWith(
        '==> signup (feature) · $signupFeature <==\n---\ndraft: true\n---\n\n# Signup\n',
      ),
    );
    expect(out.toString(), contains(_prompt));
    expect(
      readDoc(root, signupFeature),
      '---\napproved: true\n---\n\n# Signup\n\n## Problem\nUsers create an account.\n',
    );
    expect(readDoc(root, signupArch), startsWith('---\napproved: true\n---\n'));
  });

  test('f02/us03/s6, f02/us03/fr01/e07, f02/us03/fr03/e03, dw-s03/inv3: the prompt holds no lock, and a draft edited meanwhile shows again', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    var calls = 0;
    String? answer() {
      if (calls++ == 0) {
        // another write lands while the Owner reads: it needs the write lock, so none is held
        final base = getDoc(root, 'feature:signup#problem')['base']! as String;
        writeIn(
          root,
          (s) => answerSet(
            s,
            SetRequest.parse('feature:signup#problem', base: base),
            'Users sign up.\n',
          ),
        );
      }
      return calls <= 2 ? 'y' : 'q';
    }

    writeIn(
      root,
      (s) =>
          approveDrafts(s, name: 'feature:signup', readLine: answer, out: out),
    );
    expect('==> signup (feature)'.allMatches(out.toString()), hasLength(2));
    expect(readDoc(root, signupFeature), contains('approved: true'));
    expect(readDoc(root, signupFeature), contains('Users sign up.\n'));
  });

  test('f02/us03/s2, f02/us03/fr02/e01: an edited doc shows only the hunks changed since its approved commit', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$signupFeature': '---\napproved: true\n---\n\n# Signup\n\n## Problem\nUsers create an account.\n',
      },
    );
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(git(root, ['config', 'user.name', 't']).exitCode, 0);
    expect(git(root, ['config', 'user.email', 't@t']).exitCode, 0);
    expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
    commitAll(root, 'approved');
    File('${root.path}/docs/$signupFeature').writeAsStringSync(
      '---\ndraft: true\n---\n\n# Signup\n\n## Problem\nUsers sign up.\n',
    );
    commitAll(root, 'edited as a draft');
    final out = StringBuffer();
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        name: 'feature:signup',
        readLine: answers(['q']),
        out: out,
      ),
    );
    expect(out.toString(), contains('@@ -'));
    expect(out.toString(), contains('-Users create an account.\n'));
    expect(out.toString(), contains('+Users sign up.\n'));
    expect(out.toString(), isNot(contains('# Signup')));
  }, skip: skipGit);

  test(
    'f02/us03/s3: a draft with no approved version in git shows the whole file',
    () async {
      final root = await writeWriteProject();
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'user.name', 't']).exitCode, 0);
      expect(git(root, ['config', 'user.email', 't@t']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'only ever a draft');
      final out = StringBuffer();
      writeIn(
        root,
        (s) => approveDrafts(
          s,
          name: 'feature:signup',
          readLine: answers(['q']),
          out: out,
        ),
      );
      expect(
        out.toString(),
        startsWith(
          '==> signup (feature) · $signupFeature <==\n'
          '---\ndraft: true\n---\n\n# Signup\n\n## Problem\nUsers create an account.\n'
          '$_prompt',
        ),
      );
    },
    skip: skipGit,
  );

  test('f02/us03/s4, f02/us03/fr01/e02: a name walks the drafts under it in tree order', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        name: 'login',
        readLine: answers(List.filled(9, 'n')),
        out: out,
      ),
    );
    final shown = out.toString();
    final positions = [
      for (final path in [story1, fr12, story3, fr31, fr32])
        shown.indexOf('· $path <==\n'),
    ];
    expect(positions, everyElement(isNonNegative));
    expect([...positions]..sort(), positions);
    expect(_prompt.allMatches(shown), hasLength(5));
  });

  test('f02/us03/fr01/e01: no name walks every typed draft', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    writeIn(
      root,
      (s) =>
          approveDrafts(s, readLine: answers(List.filled(12, 'n')), out: out),
    );
    expect(_prompt.allMatches(out.toString()), hasLength(9));
    expect(out.toString(), contains('· $persona <==\n'));
    expect(out.toString(), contains('· $antiPersona <==\n'));
  });

  test(
    'f02/us03/s5, f02/us03/fr01/e05: n keeps a draft, q ends the walk',
    () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      final out = StringBuffer();
      writeIn(
        root,
        (s) => approveDrafts(
          s,
          name: 'login',
          readLine: answers(['n', 'q']),
          out: out,
        ),
      );
      expect(_prompt.allMatches(out.toString()), hasLength(2));
      expect(readDoc(root, story1), before);
      expect(readDoc(root, fr12), contains('draft: true'));
      expect(readDoc(root, story3), contains('draft: true'));
    },
  );

  test('f02/us03/fr01/e06: another answer repeats the prompt', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        name: 'architecture:signup',
        readLine: answers(['x', 'y']),
        out: out,
      ),
    );
    expect(_prompt.allMatches(out.toString()), hasLength(2));
    expect(readDoc(root, signupArch), startsWith('---\napproved: true\n---\n'));
    expect(
      '==> signup (architecture)'.allMatches(out.toString()),
      hasLength(1),
    );
  });

  test('f02/us03/fr01/e03: no draft in scope prints one line', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        name: 'architecture:login',
        readLine: answers([]),
        out: out,
      ),
    );
    expect(out.toString(), 'no draft waits for approval\n');
  });

  test('f02/us03/fr01/e08: a name no doc carries is doc_not_found', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(
        root,
        (s) => approveDrafts(
          s,
          name: 'feature:nosuch',
          readLine: answers([]),
          out: StringBuffer(),
        ),
      ),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.code,
          'code',
          IndexFaultCode.docNotFound,
        ),
      ),
    );
  });

  test('f02/us03/fr01/e09: an untyped draft is not walked', () async {
    final root = await writeWriteProject(
      extra: {'docs/notes.md': '---\ndraft: true\n---\n# N\n'},
    );
    final out = StringBuffer();
    writeIn(
      root,
      (s) =>
          approveDrafts(s, readLine: answers(List.filled(12, 'n')), out: out),
    );
    expect(_prompt.allMatches(out.toString()), hasLength(9));
    expect(out.toString(), isNot(contains('notes.md')));
  });

  test('f02/us03/fr03/e02, f02/us03/fr03/e06: a draft carrying approved: true keeps one approved line', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$signupFeature':
            '---\ndraft: true\napproved: true\n---\n\n# Signup\n',
      },
    );
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        name: 'feature:signup',
        readLine: answers(['y', 'q']),
        out: StringBuffer(),
      ),
    );
    expect(
      readDoc(root, signupFeature),
      '---\napproved: true\n---\n\n# Signup\n',
    );
  });

  test(
    'f02/us03/fr03/e04: a draft deleted while the prompt waits is skipped',
    () async {
      final root = await writeWriteProject();
      final out = StringBuffer();
      var calls = 0;
      String? answer() {
        if (calls++ == 0) docFile(root, signupFeature).deleteSync();
        return calls == 1 ? 'y' : 'q';
      }

      writeIn(
        root,
        (s) => approveDrafts(s, name: 'signup', readLine: answer, out: out),
      );
      expect(hasDoc(root, signupFeature), isFalse);
      expect(readDoc(root, signupArch), contains('draft: true'));
      expect(out.toString(), contains('· $signupArch <==\n'));
    },
  );

  test('f02/us03/fr03/e05: a lock held past the busy timeout is index_busy, and approvals already written stay', () async {
    final root = await writeWriteProject();
    writeIn(root, (_) {}); // creates the index
    final other = sqlite3.open('${root.path}/.specstone/index.sqlite');
    addTearDown(other.close);
    var calls = 0;
    String? answer() {
      if (calls++ == 1) other.execute('BEGIN IMMEDIATE');
      return 'y';
    }

    expect(
      () => writeIn(
        root,
        (s) => approveDrafts(
          s,
          name: 'signup',
          readLine: answer,
          out: StringBuffer(),
        ),
        busyTimeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<IndexFault>().having((f) => f.exitStatus, 'exitStatus', 75)),
    );
    expect(
      readDoc(root, signupFeature),
      startsWith('---\napproved: true\n---\n'),
    );
    expect(readDoc(root, signupArch), contains('draft: true'));
  });

  test(
    'f02/us03/fr01, review focus 5, PD10: the end of input ends the walk',
    () async {
      final root = await writeWriteProject();
      final out = StringBuffer();
      writeIn(root, (s) => approveDrafts(s, readLine: answers([]), out: out));
      expect(_prompt.allMatches(out.toString()), hasLength(1));
      expect(readDoc(root, signupFeature), contains('draft: true'));
      expect(readDoc(root, story1), contains('draft: true'));
    },
  );

  test(
    'f02/us03/fr03, dw-s03/inv5: approval keeps the line endings of the file',
    () async {
      final root = await writeWriteProject();
      File('${root.path}/docs/$signupFeature')
          .writeAsStringSync('---\r\ndraft: true\r\n---\r\n\r\n# Signup\r\n');
      writeIn(
        root,
        (s) => approveDrafts(
          s,
          name: 'feature:signup',
          readLine: answers(['y', 'q']),
          out: StringBuffer(),
        ),
      );
      expect(
        readDoc(root, signupFeature),
        '---\r\napproved: true\r\n---\r\n\r\n# Signup\r\n',
      );
    },
  );

  test('U1, dw-s03/inv5: approve refuses a doc that is not UTF-8 and leaves its bytes unchanged', () async {
    final root = await writeWriteProject();
    final bytes = [
      ...docFile(root, signupFeature).readAsBytesSync(),
      0xFF,
      0x0A,
    ];
    docFile(root, signupFeature).writeAsBytesSync(bytes);
    expect(
      () => writeIn(
        root,
        (s) => approveDrafts(
          s,
          name: 'feature:signup',
          readLine: answers(['y']),
          out: StringBuffer(),
        ),
      ),
      throwsA(
        isA<RenderFault>().having(
          (f) => f.message,
          'message',
          'cannot write $signupFeature: not UTF-8 text',
        ),
      ),
    );
    expect(docFile(root, signupFeature).readAsBytesSync(), bytes);
  });

  test(
    'U1, dw-s03/inv5: approve keeps the BOM of a doc and sees its frontmatter',
    () async {
      final root = await writeWriteProject();
      final file = docFile(root, signupFeature);
      file.writeAsBytesSync([0xEF, 0xBB, 0xBF, ...file.readAsBytesSync()]);
      writeIn(
        root,
        (s) => approveDrafts(
          s,
          name: 'feature:signup',
          readLine: answers(['y', 'q']),
          out: StringBuffer(),
        ),
      );
      final after = file.readAsBytesSync();
      expect(after.take(3), [0xEF, 0xBB, 0xBF]);
      expect(
        String.fromCharCodes(after.skip(3)),
        startsWith('---\napproved: true\n---\n'),
      );
    },
  );
}
