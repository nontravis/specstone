// The test names are behavior sentences kept whole.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show WriteStep;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show planRewrites;
import 'package:specstone_core/src/document_writing/stale_mentions.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/write_fixture.dart';

void main() {
  const renameLogin = <PathMove>[
    PathMove(from: 'prds/features/f01_login/', to: 'prds/features/f01_signin/'),
    PathMove(from: 'specs/f01_login/', to: 'specs/f01_signin/'),
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
      StaleMention(path: path, line: line, mention: mention);

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
        PathMove(
          from: 'prds/features/f01_login/us01_email_login/nf01_sign_in_time.md',
          to: 'prds/features/f01_login/us01_email_login/nf01_speed.md',
        ),
      ];

      expect(staleAfter(root, moveNf), isEmpty);
    });

    test('a lone-word span in an agent file is not listed when its doc is removed; a prefixed one is', () async {
      final root = await writeCheckProject(
        extra: {
          'CLAUDE.md': 'Read `login`, `feature:login`, and `doc_model`.\n',
        },
      );
      const removedFeature = <PathMove>[
        PathMove(from: 'prds/features/f01_login/', to: ''),
        PathMove(from: '.specstone/records/f01_login/', to: ''),
        PathMove(from: 'specs/f01_login/', to: ''),
      ];

      expect(staleAfter(root, removedFeature), [
        at('CLAUDE.md', 1, 'feature:login'),
      ]);
    });

    test('a bare item ID in a code file or an agent file is not listed, a name beside it is', () async {
      final root = await writeCheckProject(
        extra: {
          'app/lib/doc.dart':
              '// E01 and INV-6 and S2 stay\n'
              '// `E01` then `login/email_login`\n',
          'CLAUDE.md':
              'Read `E01`, INV-6, and `S2`.\nSee `login/email_login`.\n',
        },
      );

      expect(staleAfter(root, renameLogin), [
        at('CLAUDE.md', 2, 'login/email_login'),
        at('app/lib/doc.dart', 2, 'login/email_login'),
      ]);
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
        const removed = <PathMove>[PathMove(from: loginFr, to: '')];

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
        PathMove(
          from: 'prds/features/f01_login/',
          to: 'prds/features/f02_login/',
        ),
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

  group('longer code spans', () {
    const note = 'notes/ideas.md';

    List<StaleMention> spansAfter(Directory root) => writeIn(root, (session) {
      final renamed = renamedNamesOf(session, renameLogin);
      final rewrites = planRewrites(
        session,
        renameLogin,
        renamed: renamed,
      ).rewrites;
      return staleMentions(
        session,
        renameLogin,
        namesChange: true,
        docWrites: rewrites,
      );
    });

    Future<Directory> withNote(String text) =>
        writeCheckProject(extra: {'docs/$note': text});

    test('a span holding a renamed name inside longer text is listed at its file line', () async {
      final root = await withNote(
        '---\nnote: x\n---\n\n# Ideas\n\nA span `login/email_login E05`.\n',
      );

      expect(spansAfter(root), [at('docs/$note', 7, 'login/email_login E05')]);
    });

    test(
      'a span that is a whole doc-name mention is not listed as a longer span',
      () async {
        final root = await withNote('# Ideas\n\nA span `login/email_login`.\n');
        const unrewritten = '# Ideas\n\nA span `login/email_login`.\n';

        final stale = writeIn(
          root,
          (session) => staleMentions(
            session,
            renameLogin,
            namesChange: true,
            docWrites: [const WriteStep('docs/$note', unrewritten, before: '')],
          ),
        );

        expect(stale, isEmpty);
      },
    );

    test('spans on one line keep their column order in a long list', () async {
      const lines = 40;
      final root = await withNote(
        '# Ideas\n\n'
        '${[for (var i = 0; i < lines; i++) 'One `login/email_login A$i` and `login/email_login B$i`.'].join('\n')}\n',
      );

      expect(spansAfter(root), [
        for (var i = 0; i < lines; i++) ...[
          at('docs/$note', 3 + i, 'login/email_login A$i'),
          at('docs/$note', 3 + i, 'login/email_login B$i'),
        ],
      ]);
    });

    test('a node in a mermaid block follows the rename and one in another fenced block stays unlisted', () async {
      const node = '  N[login/email_login E06]';
      final root = await withNote(
        '# Ideas\n\n'
        '```mermaid\nflowchart LR\n$node\n```\n\n'
        '```text\n$node\n```\n\n'
        'A span `login/email_login E06`.\n',
      );

      final rewritten = writeIn(
        root,
        (session) => planRewrites(
          session,
          renameLogin,
          renamed: renamedNamesOf(session, renameLogin),
        ),
      ).singleWhere((step) => step.path == 'docs/$note').text;

      expect(
        rewritten,
        contains('```mermaid\nflowchart LR\n  N[signin/email_login E06]\n```'),
      );
      expect(rewritten, contains('```text\n$node\n```'));
      expect(spansAfter(root), [at('docs/$note', 12, 'login/email_login E06')]);
    });

    test('a span naming no renamed doc is not listed', () async {
      final root = await withNote('# Ideas\n\nA span `shop/cart E05`.\n');

      expect(spansAfter(root), isEmpty);
    });

    test('a span inside fenced code is not listed', () async {
      final root = await withNote(
        '# Ideas\n\n```\n`login/email_login E05`\n```\n',
      );

      expect(spansAfter(root), isEmpty);
    });

    test(
      'a span naming two renamed docs, or one twice, is listed once',
      () async {
        final root = await withNote(
          '# Ideas\n\n'
          'One `login/email_login and login/email_login/check_password`.\n'
          'Two `login/email_login or login/email_login`.\n',
        );

        expect(spansAfter(root), [
          at(
            'docs/$note',
            3,
            'login/email_login and login/email_login/check_password',
          ),
          at('docs/$note', 4, 'login/email_login or login/email_login'),
        ]);
      },
    );
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
        // The code lies outside the project, so no link can take a fingerprint.
        unfingerprinted: {loginRecord, 'docs/$loginArchitecture'},
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
