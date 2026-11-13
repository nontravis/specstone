import 'package:specstone_core/src/doc_model/name_mentions.dart';
import 'package:test/test.dart';

void main() {
  group('nameMentionsInMarkdown', () {
    test('doc_model RULE-11: a code span of a name or a typed name is a '
        'mention, its section key kept apart', () {
      final mentions = nameMentionsInMarkdown(
        'See `feature:login#goal` and `login/email_login`.\n',
      );
      expect(
        [for (final m in mentions) (m.line, m.column, m.text)],
        [(1, 5, 'feature:login#goal'), (1, 30, 'login/email_login')],
      );
      expect(mentions.first.address.typeId, 'feature');
      expect(mentions.first.address.body, 'login');
      expect(mentions.first.address.sectionKey, 'goal');
    });

    test('doc_model RULE-11: a bare one-slug span is no mention', () {
      expect(nameMentionsInMarkdown('Say `login` or `user_id`.\n'), isEmpty);
    });

    test('doc_model RULE-11: a span inside fenced code is no mention', () {
      expect(
        nameMentionsInMarkdown(
          'Run:\n\n```sh\necho `login/email_login`\n```\n\n'
          '`login/email_login`\n',
        ).map((m) => m.line),
        [7],
      );
    });

    test('doc_model RULE-11: a span of prose text or a plain name is no '
        'mention', () {
      expect(
        nameMentionsInMarkdown(
          '`check architecture:login` and login/email_login\n',
        ),
        isEmpty,
      );
    });

    test('doc_model RULE-11: each line is read alone, so a span split across '
        'two lines is no mention', () {
      expect(nameMentionsInMarkdown('`login/\nemail_login`\n'), isEmpty);
    });

    test('doc_model RULE-11: a double-backtick span is read by its text, its '
        'column after the opening run', () {
      final mentions = nameMentionsInMarkdown('x ``login/email_login`` y\n');
      expect(
        [for (final m in mentions) (m.column, m.text)],
        [(4, 'login/email_login')],
      );
    });

    test('doc_model RULE-11: a backslash-escaped backtick opens no span, so '
        'no mention', () {
      expect(
        nameMentionsInMarkdown('Write \\`login/email_login\\` as is.\n'),
        isEmpty,
      );
    });
  });

  group('isCommentLine', () {
    test('doc_model RULE-11: // marks a comment in .dart, .js, and .ts', () {
      for (final extension in ['.dart', '.js', '.ts']) {
        expect(isCommentLine('// note', extension), isTrue, reason: extension);
        expect(isCommentLine('/// doc', extension), isTrue, reason: extension);
        expect(isCommentLine('# note', extension), isFalse, reason: extension);
      }
    });

    test('doc_model RULE-11: # marks a comment in .sh, .ps1, .yaml, .yml, and '
        '.py', () {
      for (final extension in ['.sh', '.ps1', '.yaml', '.yml', '.py']) {
        expect(isCommentLine('# note', extension), isTrue, reason: extension);
        expect(isCommentLine('// note', extension), isFalse, reason: extension);
      }
    });

    test('doc_model RULE-11: an indented mark is a comment line', () {
      expect(isCommentLine('    // note', '.dart'), isTrue);
      expect(isCommentLine('\t# note', '.sh'), isTrue);
    });

    test('doc_model RULE-11: an end-of-line comment makes no comment line', () {
      expect(isCommentLine('final a = 1; // note', '.dart'), isFalse);
      expect(isCommentLine('run --all # note', '.sh'), isFalse);
    });

    test('doc_model RULE-11: any other extension holds no comment line', () {
      for (final extension in ['.txt', '.json', '.c', '.md', '']) {
        expect(isCommentLine('// note', extension), isFalse);
        expect(isCommentLine('# note', extension), isFalse);
      }
    });
  });

  group('nameMentionsInComments', () {
    test('doc_model RULE-11: only a comment line is read, each line alone', () {
      final mentions = nameMentionsInComments(
        '/// Lays out `login/email_login`.\n'
            'final a = `login/email_login`;\n'
            '  // see `feature:login#goal`\n'
            'x(); // `login/email_login`\n'
            '// `login/\n'
            '// email_login`\n',
        '.dart',
      );
      expect(
        [for (final m in mentions) (m.line, m.column, m.text)],
        [(1, 14, 'login/email_login'), (3, 10, 'feature:login#goal')],
      );
    });

    test('doc_model RULE-11: a bare one-slug span in a comment is no '
        'mention', () {
      expect(nameMentionsInComments('// say `login`\n', '.dart'), isEmpty);
    });

    test(
      'doc_model RULE-11: a file of an extension with no mark holds none',
      () {
        expect(
          nameMentionsInComments('// `login/email_login`\n', '.c'),
          isEmpty,
        );
      },
    );
  });

  group('nameMentionsInFile', () {
    test('doc_model RULE-11: markdown is read after its frontmatter, outside '
        'fenced code, at the lines of the file', () {
      final mentions = nameMentionsInFile(
        '---\ndescription: `login/email_login`\n---\n\n'
            'Use `login/email_login`.\n\n```\n`login/email_login`\n```\n',
        '.md',
      );
      expect([for (final m in mentions) m.line], [5]);
    });

    test('doc_model RULE-11: any other file is read by its comment lines', () {
      final mentions = nameMentionsInFile(
        '# `login/email_login`\nrun `login/email_login`\n',
        '.sh',
      );
      expect([for (final m in mentions) m.line], [1]);
    });

    test('a comment line holds a doc path, plain or in a code span, with its '
        'anchor and closing mark left off', () {
      final mentions = nameMentionsInFile(
        '// See prds/features/f01_login/FEATURE.md.\n'
            '  // And `docs/prds/PROJECT.md#goal`, then prds/d01.md:12 end\n',
        '.dart',
      );
      expect(
        [for (final m in mentions) (m.line, m.column, m.text)],
        [
          (1, 7, 'prds/features/f01_login/FEATURE.md'),
          (2, 10, 'docs/prds/PROJECT.md'),
          (2, 43, 'prds/d01.md'),
        ],
      );
    });

    test('a path mention is no reference without lookup', () {
      final mention = nameMentionsInFile(
        '// prds/PROJECT.md\n',
        '.dart',
      ).single;
      expect(mention.address.isReferenceWithoutLookup, isFalse);
    });

    test('a path in an end-of-line comment or a string line is not read', () {
      expect(
        nameMentionsInFile(
          "final p = 'prds/PROJECT.md'; // prds/PROJECT.md\n",
          '.dart',
        ),
        isEmpty,
      );
    });

    test('markdown holds a path in its text outside fenced code and its '
        'frontmatter', () {
      final mentions = nameMentionsInFile(
        '---\nsee: prds/PROJECT.md\n---\n\nRead prds/PROJECT.md now.\n\n'
            '```\nprds/PROJECT.md\n```\n',
        '.md',
      );
      expect([for (final m in mentions) m.line], [5]);
    });

    test('a path is read from a name mention alongside it, in line order', () {
      final mentions = nameMentionsInFile(
        '// `login/email_login` and prds/PROJECT.md\n',
        '.dart',
      );
      expect(
        [for (final m in mentions) m.text],
        ['login/email_login', 'prds/PROJECT.md'],
      );
    });

    test('a word that is no path is not a mention', () {
      expect(
        nameMentionsInFile('// notes.mdx and x.md.bak and .md\n', '.dart'),
        isEmpty,
      );
    });
  });

  group('bareNameMentionsInFile', () {
    test('a bare one-slug span of a comment line is a mention', () {
      final mentions = bareNameMentionsInFile(
        '// `login`, `user_id#key`, `login/email_login`, `feature:login`\n'
            'x(`login`);\n',
        '.dart',
      );
      expect(
        [for (final m in mentions) (m.line, m.text)],
        [(1, 'login'), (1, 'user_id#key')],
      );
    });

    test('markdown holds them outside fenced code', () {
      final mentions = bareNameMentionsInFile(
        'Use `login`.\n\n```\n`login`\n```\n',
        '.md',
      );
      expect([for (final m in mentions) m.line], [1]);
    });
  });
}
