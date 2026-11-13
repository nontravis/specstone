// The test names are behavior sentences kept whole.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/stale_mentions.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/write_fixture.dart';

void main() {
  const renameLogin = <PathMove>[
    (from: 'prds/features/f01_login/', to: 'prds/features/f01_signin/'),
    (from: 'specs/f01_login/', to: 'specs/f01_signin/'),
  ];

  List<StaleMention> staleAfter(
    Directory root,
    List<PathMove> moves, {
    bool namesChange = true,
  }) => writeIn(
    root,
    (session) => staleMentions(session, moves, namesChange: namesChange),
  );

  StaleMention at(String path, int line, String mention) =>
      (path: path, line: line, mention: mention);

  group('a name mention', () {
    test(
      'in a comment line is listed with its line and the file keeps every byte',
      () async {
        const code =
            'final a = 1;\n'
            '/// Lays out `login/email_login`.\n';
        final root = await writeCheckProject(extra: {'app/lib/doc.dart': code});

        expect(staleAfter(root, renameLogin), [
          at('app/lib/doc.dart', 2, 'login/email_login'),
        ]);
        expect(File('${root.path}/app/lib/doc.dart').readAsStringSync(), code);
      },
    );

    test('keeps its type prefix and section key as written', () async {
      final root = await writeCheckProject(
        extra: {
          'app/lib/doc.dart':
              '// `user_story:login/email_login#acceptance_criteria`\n',
        },
      );

      expect(staleAfter(root, renameLogin), [
        at(
          'app/lib/doc.dart',
          1,
          'user_story:login/email_login#acceptance_criteria',
        ),
      ]);
    });

    test('of a doc that moves with its parent is listed', () async {
      final root = await writeCheckProject(
        extra: {'app/lib/doc.dart': '// `login/email_login/check_password`\n'},
      );

      expect(staleAfter(root, renameLogin), [
        at('app/lib/doc.dart', 1, 'login/email_login/check_password'),
      ]);
    });

    test('in a string, an end-of-line comment, or a name no doc carries is not listed', () async {
      final root = await writeCheckProject(
        extra: {
          'app/lib/doc.dart':
              'const tag = "`login/email_login`";\n'
              'void f() {} // `login/email_login`\n'
              '// `login/missing_story`\n',
        },
      );

      expect(staleAfter(root, renameLogin), isEmpty);
    });

    test('of a doc the change leaves is not listed', () async {
      final root = await writeCheckProject(
        extra: {'app/lib/doc.dart': '// `login/email_login` stays\n'},
      );
      const moveNf = <PathMove>[
        (
          from: 'prds/features/f01_login/us01_email_login/nf01_sign_in_time.md',
          to: 'prds/features/f01_login/us01_email_login/nf01_speed.md',
        ),
      ];

      expect(staleAfter(root, moveNf), isEmpty);
    });

    test('a bare one-slug name of the sole doc that carries it is listed when that doc is removed', () async {
      final root = await writeCheckProject(
        extra: {'CLAUDE.md': 'Read `login` and `doc_model`.\n'},
      );
      const removedFeature = <PathMove>[
        (from: 'prds/features/f01_login/', to: ''),
        (from: 'specs/f01_login/', to: ''),
      ];

      expect(staleAfter(root, removedFeature), [at('CLAUDE.md', 1, 'login')]);
    });

    test('is not listed when the names do not change', () async {
      final root = await writeCheckProject(
        extra: {'app/lib/doc.dart': '// `login/email_login`\n'},
      );

      expect(staleAfter(root, renameLogin, namesChange: false), isEmpty);
    });

    test(
      'is listed for a removed doc, the removal as a move to no path',
      () async {
        final root = await writeCheckProject(
          extra: {
            'app/lib/doc.dart':
                '// `login/email_login`\n'
                '// `login`\n'
                '// `login/email_login/check_password`\n',
          },
        );
        const removed = <PathMove>[(from: loginFr, to: '')];

        expect(staleAfter(root, removed), [
          at('app/lib/doc.dart', 3, 'login/email_login/check_password'),
        ]);
      },
    );
  });

  group('a path mention', () {
    test(
      'read from the project root or the docs root is listed as written',
      () async {
        final root = await writeCheckProject(
          extra: {
            'app/lib/doc.dart':
                '// see docs/prds/features/f01_login/FEATURE.md:3\n'
                '// and prds/features/f01_login/FEATURE.md.\n'
                '// but ../prds/features/f01_login/FEATURE.md names none\n',
          },
        );

        expect(staleAfter(root, renameLogin), [
          at('app/lib/doc.dart', 1, 'docs/prds/features/f01_login/FEATURE.md'),
          at('app/lib/doc.dart', 2, 'prds/features/f01_login/FEATURE.md'),
        ]);
      },
    );

    test('is listed when the names do not change', () async {
      const reorderLogin = <PathMove>[
        (from: 'prds/features/f01_login/', to: 'prds/features/f02_login/'),
      ];
      final root = await writeCheckProject(
        extra: {
          'app/lib/doc.dart':
              '// `login/email_login`\n'
              '// docs/prds/features/f01_login/FEATURE.md\n',
        },
      );

      expect(staleAfter(root, reorderLogin, namesChange: false), [
        at('app/lib/doc.dart', 2, 'docs/prds/features/f01_login/FEATURE.md'),
      ]);
    });

    test('of a doc the change leaves, or of no doc, is not listed', () async {
      final root = await writeCheckProject(
        extra: {
          'app/lib/doc.dart':
              '// docs/prds/PROJECT.md\n'
              '// docs/prds/features/f01_login/nothing.md\n',
        },
      );

      expect(staleAfter(root, renameLogin), isEmpty);
    });
  });

  group('the files read', () {
    test(
      'a markdown file under a code root is read outside fenced code',
      () async {
        final root = await writeCheckProject(
          extra: {
            'app/lib/SKILL.md':
                '---\nname: x\n---\n\nRun `login/email_login`.\n\n'
                '```\n`login/email_login`\n```\n\nPlain login/email_login.\n',
          },
        );

        expect(staleAfter(root, renameLogin), [
          at('app/lib/SKILL.md', 5, 'login/email_login'),
        ]);
      },
    );

    test('an agent file at the project root is read', () async {
      final root = await writeCheckProject(
        extra: {
          'CLAUDE.md': 'Read `feature:login` first.\n',
          'AGENTS.md': 'See docs/prds/features/f01_login/FEATURE.md.\n',
        },
      );

      expect(staleAfter(root, renameLogin), [
        at('AGENTS.md', 1, 'docs/prds/features/f01_login/FEATURE.md'),
        at('CLAUDE.md', 1, 'feature:login'),
      ]);
    });

    test(
      'a file with a CRLF line end or a byte-order mark is read at its line',
      () async {
        final root = await writeCheckProject();
        File('${root.path}/app/lib/crlf.dart')
            .writeAsBytesSync('// one\r\n// `login/email_login`\r\n'.codeUnits);
        File('${root.path}/app/lib/bom.dart').writeAsBytesSync([
          0xEF,
          0xBB,
          0xBF,
          ...'// `login/email_login`\n'.codeUnits,
        ]);

        expect(staleAfter(root, renameLogin), [
          at('app/lib/bom.dart', 1, 'login/email_login'),
          at('app/lib/crlf.dart', 2, 'login/email_login'),
        ]);
      },
    );

    test('a file of invalid text, a picture, and a file outside the code entries are skipped', () async {
      final root = await writeCheckProject();
      File(
        '${root.path}/app/lib/bad.dart',
      ).writeAsBytesSync([...'// `login/email_login`\n'.codeUnits, 0xFF, 0xFE]);
      File('${root.path}/app/lib/logo.png').writeAsBytesSync([0x89, 0x50]);
      File('${root.path}/other.dart')
        ..createSync()
        ..writeAsStringSync('// `login/email_login`\n');

      expect(staleAfter(root, renameLogin), isEmpty);
    });

    test(
      'a file lists its mentions in line order and files in path order',
      () async {
        final root = await writeCheckProject(
          extra: {
            'app/lib/b.dart': '// `login/email_login`\n',
            'app/lib/a.dart':
                '// `feature:login#problem` and `login/email_login`\n'
                '// `login/email_login`\n',
          },
        );

        expect(staleAfter(root, renameLogin), [
          at('app/lib/a.dart', 1, 'feature:login#problem'),
          at('app/lib/a.dart', 1, 'login/email_login'),
          at('app/lib/a.dart', 2, 'login/email_login'),
          at('app/lib/b.dart', 1, 'login/email_login'),
        ]);
      },
    );

    test('a code file outside the project root is listed by its path from the project root', () async {
      final outside = Directory.systemTemp.createTempSync('specstone_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final folder = outside.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      File('${outside.path}/app/lib/doc.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// `login/email_login`\n');
      final root = await writeCheckProject(
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}code_root: ../$folder\n',
        },
      );

      expect(staleAfter(root, renameLogin), [
        at('../$folder/app/lib/doc.dart', 1, 'login/email_login'),
      ]);
    });

    test(
      'a file in the docs root is read by the doc rewrite, never listed',
      () async {
        final root = await writeCheckProject(
          extra: {
            'docs/specs/TECH_STACK.md':
                '---\ncode:\n  - ./\n---\n\n# Tech stack\n\n## Stack\n\n'
                '| Slot | Choice |\n|---|---|\n| Language | Dart |\n\n'
                '## Naming\n\n- snake_case file names\n\n'
                'Mentions `login/email_login`.\n',
          },
        );

        expect(staleAfter(root, renameLogin), isEmpty);
      },
    );
  });
}
