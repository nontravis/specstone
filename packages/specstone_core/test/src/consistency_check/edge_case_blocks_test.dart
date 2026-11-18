import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/edge_case_blocks.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

Future<Map<String, String>> _blocksOf(Map<String, String> extra) async {
  final project = await writeCheckProject(extra: extra);
  final session = openSession(project);
  addTearDown(session.close);
  return edgeCaseBlocksOf(CheckContext(session), session.index.at(loginFr)!);
}

void main() {
  test('each edge case maps to its block, nested items and continuation '
      'lines included', () async {
    final blocks = await _blocksOf(
      fr(
        '1. E01 — An empty password → refused.',
        '1. E01 — An empty password → refused.\n'
            '   It names the field.\n'
            '   - A blank form\n'
            '   - A form of spaces\n'
            '2. E02 — A long password → accepted.\n'
            '3. E03 — Two E01 forms → one reply.',
      ),
    );

    expect(blocks, {
      'E01':
          '1. E01 — An empty password → refused.\n'
          '   It names the field.\n'
          '   - A blank form\n'
          '   - A form of spaces',
      'E02': '2. E02 — A long password → accepted.',
      'E03': '3. E03 — Two E01 forms → one reply.',
    });
  });

  test('the first of a repeated ID wins and an item with no ID keys no '
      'block', () async {
    final blocks = await _blocksOf(
      fr(
        '1. E01 — An empty password → refused.',
        '1. E01 — An empty password → refused.\n'
            '2. E01 — A copy → refused.\n'
            '3. A note with no ID.',
      ),
    );

    expect(blocks, {'E01': '1. E01 — An empty password → refused.'});
  });

  test('a requirement with no edge cases section has no block', () async {
    final blocks = await _blocksOf(
      fr('## Edge cases\n\n1. E01 — An empty password → refused.\n\n', ''),
    );

    expect(blocks, isEmpty);
  });
}
