import 'package:specstone_core/src/index_query/doc_mentions.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

const _index = 'docs/specs/INDEX.md';

Future<List<int>> _linesNaming(String notes) async {
  final index = await indexWith({
    _index: '# Spec map\n\nThe old INDEX.md names itself.\n',
    'docs/specs/tools/notes.md': notes,
  });
  final target = index.resolve('specs/INDEX.md').single;
  return [for (final mention in mentionsOf(index, target)) mention.line];
}

void main() {
  test('a file name at a line start, after a slash, and closing a sentence is '
      'a mention; the doc itself is not', () async {
    final lines = await _linesNaming(
      '# Notes\n'
      '\n'
      'INDEX.md maps the specs.\n'
      'See ./INDEX.md and ../INDEX.md.\n'
      'It is in INDEX.md.\n',
    );

    expect(lines, [3, 4, 5]);
  });
  test('a longer name, a folder, or another extension is no mention', () async {
    final lines = await _linesNaming(
      '# Notes\n'
      '\n'
      'OLD_INDEX.md is gone.\n'
      'INDEX.md/ is a folder.\n'
      'INDEX.mdx and INDEX.md.bak differ.\n'
      'INDEX.md-old is a copy.\n',
    );

    expect(lines, isEmpty);
  });
  test('a link destination, angle-bracketed or in a reference definition, is '
      'no mention', () async {
    final lines = await _linesNaming(
      '# Notes\n'
      '\n'
      'See [the map](<../gone/INDEX.md>).\n'
      '\n'
      '[map]: ../gone/INDEX.md\n'
      'Read [map].\n',
    );

    expect(lines, isEmpty);
  });
  test(
    'a destination with balanced or escaped parentheses is no mention',
    () async {
      final index = await indexWith({
        'docs/specs/LEDGER.md': '# Ledger\n',
        'docs/specs/f01/B.md':
            '# B\n\nSee [x](a(b)/LEDGER.md).\n\nSee [y](a\\)b/LEDGER.md).\n',
      });
      final target = index.resolve('specs/LEDGER.md').single;

      expect(mentionsOf(index, target), isEmpty);
    },
  );
  test("perf-fix-10: the mentions of several docs are each doc's own, read "
      'in one pass over the docs that hold their file names', () async {
    final index = await indexWith({
      'docs/specs/a/USER.md': '# A\n',
      'docs/specs/b/USER.md': '# B\n',
      'docs/specs/c/NOTE.md': '# C\n',
      'docs/specs/notes.md':
          '# Notes\n\nSee a/USER.md and [b](b/USER.md).\nThen b/USER.md.\n'
          'And c/NOTE.md.\n',
      'docs/specs/plain.md': '# Plain\n\nNo link here: a/USER.md.\n',
    });
    final targets = [
      for (final path in [
        'specs/a/USER.md',
        'specs/b/USER.md',
        'specs/c/NOTE.md',
      ])
        index.resolve(path).single,
    ];
    List<(String, int)> spots(List<Mention> mentions) => [
      for (final (:doc, :line) in mentions) (doc.docPath, line),
    ];

    final each = mentionsOfEach(index, targets);

    expect(each.keys, [for (final target in targets) target.docPath]);
    for (final target in targets) {
      expect(
        spots(each[target.docPath]!),
        spots(mentionsOf(index, target)),
        reason: target.docPath,
      );
    }
    expect(spots(each['specs/a/USER.md']!), [
      ('specs/notes.md', 3),
      ('specs/plain.md', 3),
    ]);
    expect(spots(each['specs/b/USER.md']!), [('specs/notes.md', 4)]);
  });
  test('a frontmatter line naming the DocPath is a mention', () async {
    final lines = await _linesNaming(
      '---\nsource: specs/INDEX.md\n---\n\n# Notes\n',
    );

    expect(lines, [2]);
  });

  group('doc-name mentions', () {
    const notes = 'docs/specs/tools/notes.md';
    const loginName = 'prds/features/f01_login/FEATURE.md';

    Future<List<int>> linesNaming(String text, {String file = notes}) async {
      final index = await indexWith({file: text});
      final target = index.resolve(loginName).single;
      return [for (final mention in mentionsOf(index, target)) mention.line];
    }

    test('E04: a code span of '
        'the name or the typed name is a mention, a bare one-slug name or '
        'plain text is none', () async {
      expect(
        await linesNaming(
          '# Notes\n\n`feature:login` here.\n\nA `login` alone.\n\n'
          'Plain feature:login text.\n\n`feature:login#goal`.\n',
        ),
        [3, 9],
      );
    });

    test(
      'E04: a story is '
      'mentioned by its name and its typed name, not by another type',
      () async {
        final index = await indexWith({
          notes:
              '# Notes\n\n`login/email_login`\n\n`user_story:login/email_login`\n\n'
              '`fr:login/email_login`\n',
        });
        final story = index.resolve('user_story:login/email_login').single;
        expect([for (final m in mentionsOf(index, story)) m.line], [3, 5]);
      },
    );

    test(
      'E13: a name in '
      'fenced code or on a line that links to the doc is no mention',
      () async {
        expect(
          await linesNaming(
            '# Notes\n\n```text\n`feature:login`\n```\n\n'
            '[the feature](../../prds/features/f01_login/FEATURE.md) and '
            '`feature:login`.\n',
          ),
          isEmpty,
        );
      },
    );

    test('E12: a path and a '
        'name on one line give one mention of it', () async {
      expect(
        await linesNaming(
          '# Notes\n\n`feature:login` in '
          'prds/features/f01_login/FEATURE.md.\n',
        ),
        [3],
      );
    });

    test('E04: a name '
        'mention of the doc inside the doc itself is no mention', () async {
      final index = await indexWith({
        'docs/prds/features/f01_login/FEATURE.md':
            '# Login\n\n## Problem\n\nSee `feature:login`.\n',
      });
      final target = index.resolve('feature:login').single;
      expect(mentionsOf(index, target), isEmpty);
    });
  });
}
