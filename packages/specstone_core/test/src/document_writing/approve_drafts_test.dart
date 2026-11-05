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
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _prompt = 'approve? [y/n/q] ';

/// Returns the given answers in order, then null.
String? Function() answers(List<String?> list) {
  final queue = [...list];
  return () => queue.isEmpty ? null : queue.removeAt(0);
}

void main() {
  final skipGit = hasGit ? null : 'git is not available';

  test('f02/us03/s1, f02/us03/fr01, f02/us03/fr03, f02/us03/fr03/e01, f02/us03/fr02/e03, dw-s03/inv5: y removes draft and writes approved, text unchanged', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        names: ['signup'],
        readLine: answers(['y', 'y']),
        out: out,
      ),
    );
    expect(
      out.toString(),
      startsWith('### Draft 1/2 · Signup\n`docs/$signupFeature`\n'),
    );
    expect(out.toString(), contains('+# Signup\n'));
    expect(out.toString(), contains(_prompt));
    expect(
      readDoc(root, signupFeature),
      '---\napproved: true\n---\n\n# Signup\n\n## Problem\n\nUsers create an account.\n',
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
      (s) => approveDrafts(
        s,
        names: ['feature:signup'],
        readLine: answer,
        out: out,
      ),
    );
    expect('### Draft 1/2 · Signup\n'.allMatches(out.toString()), hasLength(2));
    expect(readDoc(root, signupFeature), contains('approved: true'));
    expect(readDoc(root, signupFeature), contains('Users sign up.\n'));
  });

  test('f02/us03/fr01/e07: a draft at position 2 edited while the prompt waits shows again as Draft 2/2', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    var calls = 0;
    String? answer() {
      calls++;
      if (calls == 1) return 'n';
      if (calls == 2) {
        docFile(
          root,
          signupArch,
        ).writeAsStringSync('${readDoc(root, signupArch)}\nMore.\n');
        return 'y';
      }
      return 'q';
    }

    writeIn(
      root,
      (s) => approveDrafts(
        s,
        names: ['feature:signup'],
        readLine: answer,
        out: out,
      ),
    );
    expect('### Draft 1/2 · Signup\n'.allMatches(out.toString()), hasLength(1));
    expect(
      '### Draft 2/2 · Signup architecture\n'.allMatches(out.toString()),
      hasLength(2),
    );
    expect(out.toString(), isNot(contains('/3')));
    expect(readDoc(root, signupArch), startsWith('---\ndraft: true\n'));
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
        names: ['feature:signup'],
        readLine: answers(['q']),
        out: out,
      ),
    );
    expect(out.toString(), contains('@@ -'));
    expect(out.toString(), contains('-Users create an account.\n'));
    expect(out.toString(), contains('+Users sign up.\n'));
    expect(out.toString(), isNot(contains('# Signup')));
  }, skip: skipGit);

  test('f02/us03/fr02/e01, f02/us03/fr02/e15: a project below the repository top-level shows an edited draft with no rename line', () async {
    final repo = await writeTree({
      for (final MapEntry(:key, :value) in writeProject.entries)
        'sub/$key': value,
      'sub/docs/$signupFeature': '---\napproved: true\n---\n\n# Signup\n\n## Problem\nUsers create an account.\n',
    });
    final root = Directory('${repo.path}/sub');
    expect(git(repo, ['init', '-q']).exitCode, 0);
    expect(git(repo, ['config', 'core.autocrlf', 'false']).exitCode, 0);
    commitAll(repo, 'approved');
    File('${root.path}/docs/$signupFeature').writeAsStringSync(
      '---\ndraft: true\n---\n\n# Signup\n\n## Problem\nUsers sign up.\n',
    );
    commitAll(repo, 'edited as a draft');

    final view = writeIn(
      root,
      (s) => approveDryRun(s, names: ['feature:signup']),
    ).text;

    expect(
      view,
      startsWith('### Draft 1/2 · Signup\n`docs/$signupFeature`\n\n'),
    );
    expect(view, isNot(contains('renamed from')));
    expect(view, contains('| old     | approved copy in commit `'));
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
          names: ['feature:signup'],
          readLine: answers(['q']),
          out: out,
        ),
      );
      expect(
        out.toString(),
        startsWith(
          '### Draft 1/2 · Signup\n'
          '`docs/$signupFeature`\n',
        ),
      );
      expect(out.toString(), contains('| old     | none: never approved |\n'));
      expect(
        out.toString(),
        contains('+## Problem\n+\n+Users create an account.\n```\n$_prompt'),
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
        names: ['login'],
        readLine: answers(List.filled(9, 'n')),
        out: out,
      ),
    );
    final shown = out.toString();
    final positions = [
      for (final path in [story1, fr12, story3, fr31, fr32])
        shown.indexOf('`docs/$path`\n'),
    ];
    expect(positions, everyElement(isNonNegative));
    expect([...positions]..sort(), positions);
    expect(_prompt.allMatches(shown), hasLength(5));
  });

  test('ms-r10: several names walk the union of their drafts in tree order, each once', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        names: ['feature:signup', 'user_story:login/reset_password', 'login'],
        readLine: answers(List.filled(12, 'n')),
        out: out,
      ),
    );
    final shown = out.toString();
    final positions = [
      for (final path in [
        story1,
        fr12,
        story3,
        fr31,
        fr32,
        signupFeature,
        signupArch,
      ])
        shown.indexOf('`docs/$path`\n'),
    ];
    expect(positions, everyElement(isNonNegative));
    expect([...positions]..sort(), positions);
    expect(_prompt.allMatches(shown), hasLength(7));
  });

  test('ms-r10: a name no doc carries among several is doc_not_found, and nothing shows', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    expect(
      () => writeIn(
        root,
        (s) => approveDrafts(
          s,
          names: ['feature:signup', 'feature:nosuch'],
          readLine: answers(['y']),
          out: out,
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
    expect(out.toString(), isEmpty);
    expect(readDoc(root, signupFeature), startsWith('---\ndraft: true\n'));
  });

  test('f02/us03/fr01: the walk prints the view before its prompt', () async {
    final root = await writeWriteProject();
    final out = StringBuffer();
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        names: ['architecture:signup'],
        readLine: answers(['q']),
        out: out,
      ),
    );
    final shown = out.toString();
    expect(shown.indexOf('### Draft 1/1 · '), isNonNegative);
    expect(shown.indexOf('### Draft 1/1 · '), lessThan(shown.indexOf(_prompt)));
    expect(shown, isNot(contains('==> ')));
  });

  group('approveDryRun', () {
    test('f02/us03/fr05/e05: dry run prints each draft in tree order and writes nothing', () async {
      final root = await writeWriteProject();
      final answer = writeIn(
        root,
        (s) => approveDryRun(s, names: ['feature:signup']),
      );
      final shown = answer.text;
      expect(shown.indexOf('### Draft 1/2 · '), isNonNegative);
      expect(
        shown.indexOf('### Draft 1/2 · '),
        lessThan(shown.indexOf('### Draft 2/2 · ')),
      );
      expect(shown, contains('`docs/$signupFeature`'));
      expect(
        shown.indexOf('`docs/$signupFeature`'),
        lessThan(shown.indexOf('`docs/$signupArch`')),
      );
      expect(shown, contains('`\n\n| field   | value |'));
      expect(shown, contains('\n\n### Draft 2/2 · '));
      expect(shown, endsWith('\n'));
      expect(answer.json, isEmpty);
      expect(readDoc(root, signupFeature), startsWith('---\ndraft: true\n'));
      expect(readDoc(root, signupArch), startsWith('---\ndraft: true\n'));
    });

    test('f02/us03/fr05/e05: a draft whose file is gone is not counted in Draft n/m', () async {
      final root = await writeWriteProject();
      final answer = writeIn(root, (s) {
        // the index already holds both drafts; the file goes before selection
        docFile(root, signupFeature).deleteSync();
        return approveDryRun(s, names: ['feature:signup']);
      });
      expect(answer.text, startsWith('### Draft 1/1 · Signup architecture\n'));
      expect(answer.text, isNot(contains('/2')));
      expect('### Draft '.allMatches(answer.text), hasLength(1));
    });

    test('f02/us03/fr01, f02/us03/fr05: the walk prints what the dry run prints, view for view', () async {
      final root = await writeWriteProject();
      for (final (:context, :color) in [
        (context: null, color: false),
        (context: 0, color: true),
      ]) {
        final out = StringBuffer();
        writeIn(
          root,
          (s) => approveDrafts(
            s,
            names: ['login'],
            readLine: answers(List.filled(9, 'n')),
            out: out,
            context: context,
            color: color,
          ),
        );
        final dry = writeIn(
          root,
          (s) => approveDryRun(
            s,
            names: ['login'],
            context: context,
            color: color,
          ),
        );
        expect(_prompt.allMatches(out.toString()), hasLength(5));
        expect(
          out.toString().replaceAll(_prompt, ''),
          dry.text.replaceAll('\n\n### Draft ', '\n### Draft '),
        );
      }
    });

    test('f02/us03/fr05/e04: dry run with no draft says so', () async {
      final root = await writeWriteProject();
      final answer = writeIn(
        root,
        (s) => approveDryRun(s, names: ['architecture:login']),
      );
      expect(answer.text, 'no draft waits for approval\n');
      expect(answer.json, isEmpty);
    });

    test(
      'f02/us03/fr05/e05: a name no doc carries fails before printing',
      () async {
        final root = await writeWriteProject();
        expect(
          () => writeIn(
            root,
            (s) =>
                approveDryRun(s, names: ['feature:signup', 'feature:nosuch']),
          ),
          throwsA(
            isA<IndexFault>().having(
              (f) => f.code,
              'code',
              IndexFaultCode.docNotFound,
            ),
          ),
        );
      },
    );

    test('f02/us03/fr05/e07: colour marks the diff lines', () async {
      final root = await writeWriteProject();
      final answer = writeIn(
        root,
        (s) => approveDryRun(s, names: ['feature:signup'], color: true),
      );
      expect(answer.text, contains('\x1b[32m+# Signup'));
    });

    test(
      'f02/us03/fr05/e07: context sets the lines kept around a change',
      () async {
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
        String viewWith(int? context) => writeIn(
          root,
          (s) => approveDryRun(s, names: ['feature:signup'], context: context),
        ).text;
        final whole = viewWith(null);
        final narrow = viewWith(0);
        expect(
          narrow,
          contains('-Users create an account.\n+Users sign up.\n'),
        );
        expect(whole, contains('-Users create an account.\n+Users sign up.\n'));
        expect(narrow, isNot(equals(whole)));
      },
      skip: skipGit,
    );
  });

  group('approveNamed', () {
    /// The draft at [address] with the hash `get --json` prints as bases.doc.
    SeenDraft seen(Directory root, String address) => (
      name: address,
      hash: (getDoc(root, address)['bases']! as Map)['doc']! as String,
    );

    test('ms-r10: approves each named draft with its hash and no prompt, one line per draft in tree order', () async {
      final root = await writeWriteProject();
      final answer = writeIn(
        root,
        (s) => approveNamed(s, [
          seen(root, 'feature:signup'),
          seen(root, 'fr:login/email_login/lock_after_failures'),
          seen(root, 'user_story:login/email_login'),
        ]),
      );
      expect(
        answer.text,
        'approved user_story:login/email_login\n'
        'approved fr:login/email_login/lock_after_failures\n'
        'approved feature:signup\n',
      );
      expect(answer.json, {
        'approved': [
          'user_story:login/email_login',
          'fr:login/email_login/lock_after_failures',
          'feature:signup',
        ],
      });
      expect(
        readDoc(root, signupFeature),
        '---\napproved: true\n---\n\n# Signup\n\n## Problem\n\nUsers create an account.\n',
      );
      expect(readDoc(root, story1), contains('\napproved: true\n'));
      expect(readDoc(root, story1), isNot(contains('draft: true')));
      expect(readDoc(root, fr12), isNot(contains('draft: true')));
    });

    test('ms-r10: a name approves only the draft it names, never the drafts under it', () async {
      final root = await writeWriteProject();
      writeIn(root, (s) => approveNamed(s, [seen(root, 'feature:signup')]));
      expect(readDoc(root, signupFeature), contains('approved: true'));
      expect(readDoc(root, signupArch), startsWith('---\ndraft: true\n'));
    });

    test("ms-r10: writes the bytes the Owner's y writes, CRLF and BOM kept, and the get hash matches", () async {
      final walked = await writeWriteProject();
      final named = await writeWriteProject();
      for (final root in [walked, named]) {
        final file = docFile(root, signupFeature);
        final crlf = file.readAsStringSync().replaceAll('\n', '\r\n');
        file.writeAsBytesSync([0xEF, 0xBB, 0xBF, ...crlf.codeUnits]);
      }
      writeIn(
        walked,
        (s) => approveDrafts(
          s,
          names: ['feature:signup'],
          readLine: answers(['y', 'n']),
          out: StringBuffer(),
        ),
      );
      writeIn(named, (s) => approveNamed(s, [seen(named, 'feature:signup')]));
      expect(
        docFile(named, signupFeature).readAsBytesSync(),
        docFile(walked, signupFeature).readAsBytesSync(),
      );
      expect(docFile(named, signupFeature).readAsBytesSync().take(3), [
        0xEF,
        0xBB,
        0xBF,
      ]);
    });

    test('ms-r10: a draft changed since the Owner saw it is base_mismatch, exit 75, naming each changed draft, and nothing is approved', () async {
      final root = await writeWriteProject();
      final drafts = [
        seen(root, 'feature:signup'),
        seen(root, 'architecture:signup'),
        seen(root, 'user_story:login/email_login'),
      ];
      final base = getDoc(root, 'feature:signup#problem')['base']! as String;
      writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse('feature:signup#problem', base: base),
          'Users sign up.\n',
        ),
      );
      docFile(
        root,
        story1,
      ).writeAsStringSync('${readDoc(root, story1)}\nMore.\n');
      final signupBefore = readDoc(root, signupFeature);
      final archBefore = readDoc(root, signupArch);
      expect(
        () => writeIn(root, (s) => approveNamed(s, drafts)),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
              .having((f) => f.exitStatus, 'exitStatus', 75)
              .having((f) => f.file, 'file', story1)
              .having((f) => f.key, 'key', 'doc')
              .having((f) => f.relatedFiles, 'relatedFiles', [signupFeature])
              .having(
                (f) => f.message,
                'message',
                'changed since the Owner saw them: '
                    'user_story:login/email_login, feature:signup; show each '
                    'again and ask for a new ok',
              ),
        ),
      );
      expect(readDoc(root, signupFeature), signupBefore);
      expect(readDoc(root, signupArch), archBefore);
    });

    test('ms-r10: a named doc that is no draft is draft_not_found, exit 65, naming it, and nothing is approved', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, signupFeature);
      expect(
        () => writeIn(
          root,
          (s) => approveNamed(s, [
            seen(root, 'feature:signup'),
            seen(root, 'feature:login'),
          ]),
        ),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.draftNotFound)
              .having((f) => f.exitStatus, 'exitStatus', 65)
              .having(
                (f) => f.message,
                'message',
                'feature:login is no draft waiting for approval',
              ),
        ),
      );
      expect(readDoc(root, signupFeature), before);
    });

    test(
      'ms-r10: a name no doc carries is doc_not_found, and nothing is approved',
      () async {
        final root = await writeWriteProject();
        final before = readDoc(root, signupFeature);
        expect(
          () => writeIn(
            root,
            (s) => approveNamed(s, [
              seen(root, 'feature:signup'),
              (name: 'feature:nosuch', hash: '000000000000'),
            ]),
          ),
          throwsA(
            isA<IndexFault>().having(
              (f) => f.code,
              'code',
              IndexFaultCode.docNotFound,
            ),
          ),
        );
        expect(readDoc(root, signupFeature), before);
      },
    );

    test(
      'ms-r10: a bare name is argument_invalid, as every write target is',
      () async {
        final root = await writeWriteProject();
        expect(
          () => writeIn(
            root,
            (s) => approveNamed(s, [(name: 'signup', hash: '000000000000')]),
          ),
          throwsA(
            isA<IndexFault>().having(
              (f) => f.code,
              'code',
              IndexFaultCode.argumentInvalid,
            ),
          ),
        );
      },
    );
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
    expect(out.toString(), contains('`docs/$persona`\n'));
    expect(out.toString(), contains('`docs/$antiPersona`\n'));
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
          names: ['login'],
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
        names: ['architecture:signup'],
        readLine: answers(['x', 'y']),
        out: out,
      ),
    );
    expect(_prompt.allMatches(out.toString()), hasLength(2));
    expect(readDoc(root, signupArch), startsWith('---\napproved: true\n---\n'));
    expect(
      '### Draft 1/1 · Signup architecture\n'.allMatches(out.toString()),
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
        names: ['architecture:login'],
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
          names: ['feature:nosuch'],
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
        names: ['feature:signup'],
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
        (s) => approveDrafts(s, names: ['signup'], readLine: answer, out: out),
      );
      expect(hasDoc(root, signupFeature), isFalse);
      expect(readDoc(root, signupArch), contains('draft: true'));
      expect(out.toString(), contains('`docs/$signupArch`\n'));
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
          names: ['signup'],
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
          names: ['feature:signup'],
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
          names: ['feature:signup'],
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
          names: ['feature:signup'],
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

  test('mark_doc_approved E07: y on a draft with padded table cells writes approved: true and lays the doc out', () async {
    const padded =
        '---\ndraft: true\n---\n\n# Signup architecture\n\n## Components\n'
        '| Component   | Responsibility |\n|-------------|----------------|\n'
        '| Signup form | Collects the email |\n';
    final root = await writeWriteProject(extra: {'docs/$signupArch': padded});
    writeIn(
      root,
      (s) => approveDrafts(
        s,
        names: ['architecture:signup'],
        readLine: answers(['y']),
        out: StringBuffer(),
      ),
    );
    expect(
      readDoc(root, signupArch),
      '---\napproved: true\n---\n\n# Signup architecture\n\n## Components\n\n'
      '| Component | Responsibility |\n|---|---|\n'
      '| Signup form | Collects the email |\n',
    );
  });
}
