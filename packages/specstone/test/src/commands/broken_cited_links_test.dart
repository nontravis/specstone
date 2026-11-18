import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../helpers/read_fixture.dart';

const _story = 'us01_email_login/USER_STORY.md';

Map<String, String> _featureLinking(String text) => doc(
  loginFeature,
  'Users forget passwords.',
  'Users forget passwords; $text',
);

/// Returns the `==>` header lines of the `context` bundle of the login feature.
Future<List<String>> _headersOf(Directory project) async {
  final (:runner, :out, :err) = readRunner(project);
  expect(
    await runner.run(['context', 'login', '--for', 'implement']),
    0,
    reason: '$err',
  );
  return [
    for (final line in out.toString().split('\n'))
      if (line.startsWith('==>')) line,
  ];
}

void main() {
  test(
    'a link to a doc the bundle lacks is followed when it resolves',
    () async {
      final project = await writeCheckProject(
        extra: _featureLinking('[story]($_story#acceptance-criteria).'),
      );

      expect(await _headersOf(project), contains(contains('USER_STORY.md')));
    },
  );

  test('a link to no doc, a missing anchor, or a missing item is not followed '
      'by context and is reported by check', () async {
    final project = await writeCheckProject(
      extra: _featureLinking(
        '[gone](missing.md), [nope]($_story#nope), and '
        '[S9]($_story#acceptance-criteria).',
      ),
    );

    expect(
      await _headersOf(project),
      isNot(contains(contains('USER_STORY.md'))),
    );

    final (:runner, :out, :err) = readRunner(project);
    expect(await runner.run(['check', '--json']), 1, reason: '$err');
    final kinds = [
      for (final finding
          in (jsonDecode(out.toString()) as Map)['findings']! as List)
        (finding as Map)['kind'],
    ];
    expect(kinds, [
      'link_anchor_missing',
      'link_item_missing',
      'link_unresolved',
    ]);
  });
}
