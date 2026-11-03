import 'package:specstone_core/src/document_writing/rewrite_mentions.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart';
import 'package:test/test.dart';

bool everything(String path) => true;

void main() {
  const reorderMoves = <PathMove>[
    (
      from: 'prds/features/f01_login/us02_sign_out/',
      to: 'prds/features/f01_login/us03_sign_out/',
    ),
    (
      from: 'prds/features/f01_login/us03_reset_password/',
      to: 'prds/features/f01_login/us01_reset_password/',
    ),
  ];
  const story1 = 'prds/features/f01_login/us01_email_login/USER_STORY.md';

  ({String lfText, int count})? rewrite(
    String text, {
    String docPath = story1,
    List<PathMove> moves = reorderMoves,
    bool Function(String path) exists = everything,
  }) =>
      rewritePathMentions(text, docPath: docPath, moves: moves, exists: exists);

  test(
    'f02/us05/fr02/e10, M2: a backticked mention follows the moved folder',
    () {
      final result = rewrite(
        'See `../us02_sign_out/USER_STORY.md` for the flow.\n',
      );

      expect(
        result?.lfText,
        'See `../us03_sign_out/USER_STORY.md` for the flow.\n',
      );
      expect(result?.count, 1);
    },
  );

  test('f02/us05/fr02/e10, M2: a plain mention follows the moved folder', () {
    expect(
      rewrite('# T\n\nSee ../us02_sign_out/USER_STORY.md now\n')?.lfText,
      '# T\n\nSee ../us03_sign_out/USER_STORY.md now\n',
    );
  });

  test('f02/us05/fr02/e10, RF1: a line suffix, a closing dot, and a fragment stay as written', () {
    expect(
      rewrite(
        'a `../us02_sign_out/s03_domain.md:12`, b ../us02_sign_out/FEATURE.md. c ../us02_sign_out/a.md#use_case\n',
      )?.lfText,
      'a `../us03_sign_out/s03_domain.md:12`, b ../us03_sign_out/FEATURE.md. c ../us03_sign_out/a.md#use_case\n',
    );
  });

  test('f02/us05/fr02/e10, RF1: a line and column suffix stays as written', () {
    expect(
      rewrite('at ../us02_sign_out/a.dart:12:5;\n')?.lfText,
      'at ../us03_sign_out/a.dart:12:5;\n',
    );
  });

  test('f02/us05/fr02/e11, RF2: prose that names no existing file stays through every move', () {
    final seen = <String>[];
    final result = rewrite(
      'Use and/or, or prds/x.md from the docs root, or ../us02_sign_out/gone.md\n',
      exists: (path) {
        seen.add(path);
        return false;
      },
    );

    expect(result, isNull);
    expect(seen, contains('prds/features/f01_login/us02_sign_out/gone.md'));
  });

  test('f02/us05/fr02/e11, M2: exists reads the path before the moves, from the docs root', () {
    final seen = <String>[];
    rewrite(
      'See ../us02_sign_out/USER_STORY.md\n',
      exists: (path) {
        seen.add(path);
        return true;
      },
    );

    expect(seen, ['prds/features/f01_login/us02_sign_out/USER_STORY.md']);
  });

  test(
    'f02/us05/fr02/e11: a mention of a file in the same moved folder stays',
    () {
      expect(
        rewrite(
          'See `FEATURE.md` and ./a.md and sub/c.md\n',
          docPath: 'prds/features/f01_login/us02_sign_out/USER_STORY.md',
        ),
        isNull,
      );
    },
  );

  test('f02/us05/fr02/e10: a mention that leaves its moved folder and re-enters it by name is rewritten', () {
    expect(
      rewrite(
        'See ../us02_sign_out/b.md\n',
        docPath: 'prds/features/f01_login/us02_sign_out/USER_STORY.md',
      )?.lfText,
      'See b.md\n',
    );
  });

  test(
    'f02/us05/fr02/e10: dots alone are no mention even when a doc moved alone',
    () {
      expect(
        rewrite(
          '...\n../..\n',
          docPath: story1,
          moves: [(from: story1, to: 'prds/other/USER_STORY.md')],
        ),
        isNull,
      );
    },
  );

  test('f02/us05/fr02/e10: a mention from a moved doc keeps pointing at the same file', () {
    final result = rewrite(
      'See ../z.md and `FEATURE.md`.\n',
      docPath: 'a/b/x.md',
      moves: [(from: 'a/b/', to: 'a/b/c/')],
    );

    expect(result?.lfText, 'See ../../z.md and `FEATURE.md`.\n');
    expect(result?.count, 1);
  });

  test('f02/us05/fr02/e10: a mention of a moved file name alone changes with a file rename', () {
    final result = rewrite(
      'Read x.md first.\n',
      docPath: 'a/y.md',
      moves: [(from: 'a/x.md', to: 'a/z.md')],
    );

    expect(result?.lfText, 'Read z.md first.\n');
  });

  test(
    'f02/us05/fr02/e10: a mention of a moved folder keeps its trailing slash',
    () {
      expect(
        rewrite('Folder `../us02_sign_out/` and ../us02_sign_out\n')?.lfText,
        'Folder `../us03_sign_out/` and ../us03_sign_out\n',
      );
    },
  );

  test('f02/us05/fr02/e10: fenced code keeps every byte', () {
    const text =
        '# T\n\n```\n../us02_sign_out/USER_STORY.md\n```\n\n~~~md\n../us02_sign_out/a.md\n~~~\n';

    expect(rewrite(text), isNull);
  });

  test(
    'f02/us05/fr02/e10: a link destination keeps every byte, its text does not',
    () {
      final result = rewrite(
        '[../us02_sign_out/USER_STORY.md](../us02_sign_out/USER_STORY.md) and [x](<../us02_sign_out/USER_STORY.md>) and ![i](../us02_sign_out/flow.png)\n'
        '[ref]: ../us02_sign_out/USER_STORY.md\n',
      );

      expect(
        result?.lfText,
        '[../us03_sign_out/USER_STORY.md](../us02_sign_out/USER_STORY.md) and [x](<../us02_sign_out/USER_STORY.md>) and ![i](../us02_sign_out/flow.png)\n'
        '[ref]: ../us02_sign_out/USER_STORY.md\n',
      );
      expect(result?.count, 1);
    },
  );

  test('f02/us05/fr02/e10: a mention next to a link on one line is the only change', () {
    expect(
      rewrite(
        '[a](../us02_sign_out/USER_STORY.md) then ../us02_sign_out/USER_STORY.md\n',
      )?.lfText,
      '[a](../us02_sign_out/USER_STORY.md) then ../us03_sign_out/USER_STORY.md\n',
    );
  });

  test('f02/us05/fr02/e10: the frontmatter keeps every byte', () {
    const text =
        '---\nreference: ../us02_sign_out/USER_STORY.md\n---\n# T\n\nBody.\n';

    expect(rewrite(text), isNull);
  });

  test('f02/us05/fr02/e10: a web address keeps every byte', () {
    expect(
      rewrite(
        'See https://x.dev/us02_sign_out/USER_STORY.md and mailto:a@b.dev\n',
      ),
      isNull,
    );
  });

  test('f02/us05/fr02/e10: a rooted path and a path above the docs root stay when they name no file', () {
    expect(
      rewrite('See /us02_sign_out/USER_STORY.md\n', exists: (path) => false),
      isNull,
    );
  });

  test('f02/us05/fr02/e10: the count is the number of edits', () {
    final result = rewrite(
      'One ../us02_sign_out/a.md and ../us02_sign_out/b.md.\n'
      'Two `../us02_sign_out/c.md:3`\n'
      'None ../us01_email_login/d.md\n',
    );

    expect(result?.count, 3);
    expect(
      result?.lfText,
      'One ../us03_sign_out/a.md and ../us03_sign_out/b.md.\n'
      'Two `../us03_sign_out/c.md:3`\n'
      'None ../us01_email_login/d.md\n',
    );
  });

  test(
    'f02/us05/fr02/e10: a mention with an escape is prose, never decoded',
    () {
      expect(rewrite('See ../us02_sign_out/a%20b.md\n'), isNull);
    },
  );

  test('f02/us05/fr02/e10: a doc with no mention returns null', () {
    expect(rewrite('# T\n\nNothing here.\n'), isNull);
  });

  test(
    'f02/us05/fr02/e11, review 1: a plain word equal to a sibling name stays',
    () {
      const moves = <PathMove>[(from: 'a/b/x.md', to: 'a/y/x.md')];

      expect(
        rewrite(
          'The architecture of the system. See reports for detail.\n',
          docPath: 'a/b/x.md',
          moves: moves,
        ),
        isNull,
      );
    },
  );

  test('f02/us05/fr02/e10, review 1: a folder with a slash and a bare file '
      'name still count', () {
    final result = rewrite(
      'See reports/ and archive.md\n',
      docPath: 'a/b/x.md',
      moves: [(from: 'a/b/x.md', to: 'a/y/x.md')],
    );

    expect(result?.lfText, 'See ../b/reports/ and ../b/archive.md\n');
  });

  test('f02/us05/fr02/e10, review 2: exists runs once per path', () {
    var calls = 0;
    rewrite(
      'See ../us02_sign_out/a.md and ../us02_sign_out/a.md again\n',
      exists: (path) {
        calls++;
        return true;
      },
    );

    expect(calls, 1);
  });

  test('f02/us05/fr02/e10, review 3: a leading ./ stays on a mention', () {
    final result = rewrite(
      'See ./b.md and ./c.md\n',
      docPath: 'a/x.md',
      moves: [(from: 'a/b.md', to: 'a/d.md')],
    );

    expect(result?.lfText, 'See ./d.md and ./c.md\n');
  });

  test('f02/us05/fr02/e10, review 3: a leading ./ goes when the new path starts with ../', () {
    final result = rewrite(
      'See ./b.md\n',
      docPath: 'a/x.md',
      moves: [(from: 'a/b.md', to: 'c/b.md')],
    );

    expect(result?.lfText, 'See ../c/b.md\n');
  });
}
