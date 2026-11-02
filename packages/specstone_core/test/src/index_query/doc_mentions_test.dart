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
  test('f01/us07/fr01: a file name at a line start, after a slash, and closing a sentence is a mention; the doc itself is not', () async {
    final lines = await _linesNaming(
      '# Notes\n'
      '\n'
      'INDEX.md maps the specs.\n'
      'See ./INDEX.md and ../INDEX.md.\n'
      'It is in INDEX.md.\n',
    );

    expect(lines, [3, 4, 5]);
  });
  test('f01/us07/fr01: a longer name, a folder, or another extension is no mention', () async {
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
  test('f01/us07/fr01: a link destination, angle-bracketed or in a reference definition, is no mention', () async {
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
    'f01/us07/fr01: a frontmatter line naming the DocPath is a mention',
    () async {
      final lines = await _linesNaming(
        '---\nsource: specs/INDEX.md\n---\n\n# Notes\n',
      );

      expect(lines, [2]);
    },
  );
}
