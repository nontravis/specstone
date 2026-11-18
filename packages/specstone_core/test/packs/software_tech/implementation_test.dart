import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  test('the record carries the optional matrix section, with no template '
      'text, that holds an output reference', () async {
    final record = prdCoreDocType(
      await resolveSoftwareTech(),
      'implementation',
    );

    final matrix = verificationMatrixOf(record);

    expect(matrix, isNotNull);
    expect(matrix!.header, 'Verification matrix');
    expect(matrix.required, isFalse);
    expect(matrix.template, isNull);
    expect(matrix.isOutputRef, isTrue);
    expect(record.sections.map((s) => s.id), ['verification_matrix']);
  });

  test(
    'a record holding an entry for every '
    'story and FR of a large feature passes check with no size finding',
    () async {
      const stories = 40;
      const frsPerStory = 3;
      String two(int n) => n.toString().padLeft(2, '0');
      final statuses = <String>[];
      final code = <String>[];
      final docs = <String, String>{
        'docs/prds/features/f09_big/FEATURE.md': '# Big\n',
      };
      for (var s = 1; s <= stories; s++) {
        final story = 'story_${two(s)}';
        docs['docs/prds/features/f09_big/us${two(s)}_$story/USER_STORY.md'] =
            '# Story $s\n';
        statuses.add("  - '$story:implemented'");
        code.add("  - '$story:app/lib/login.dart:SignInPage'");
        for (var f = 1; f <= frsPerStory; f++) {
          final fr = 'fr_${two(f)}';
          docs['docs/prds/features/f09_big/us${two(s)}_$story/'
                  'fr${two(f)}_$fr.md'] =
              '# Fr $f\n';
          statuses.add("  - '$story/$fr:implemented'");
          code.add("  - '$story/$fr:app/lib/login.dart:checkPassword'");
        }
      }
      const recordPath = '.specstone/records/f09_big/IMPLEMENTATION.md';
      docs[recordPath] =
          '---\nstatuses:\n${statuses.join('\n')}\nimplements:\n'
          '${code.join('\n')}\n---\n\n# Big implementation\n';
      expect(
        statuses.length,
        stories * (1 + frsPerStory),
        reason: 'an entry for every story and FR',
      );

      final report = await checkOf(
        await writeCheckProject(extra: docs, unstamped: {recordPath}),
      );

      final sizeFindings = report.findings.where(
        (f) =>
            f.path == '.specstone/records/f09_big/IMPLEMENTATION.md' &&
            (f.kind == FindingKind.linesOverLimit ||
                f.kind == FindingKind.itemOverLimit),
      );
      expect(sizeFindings, isEmpty);
      expect(
        report.findings.where(
          (f) =>
              f.path == '.specstone/records/f09_big/IMPLEMENTATION.md' &&
              f.kind == FindingKind.untypedDoc,
        ),
        isEmpty,
        reason: 'the record is typed, so the size rules read it',
      );
    },
  );

  test('a record of a large feature with 150 tests lines passes check with '
      'no size finding', () async {
    const stories = 40;
    const frsPerStory = 3;
    const testLines = 150;
    String two(int n) => n.toString().padLeft(2, '0');
    final items = <String>[];
    final docs = <String, String>{
      'docs/prds/features/f09_big/FEATURE.md': '# Big\n',
    };
    for (var s = 1; s <= stories; s++) {
      final story = 'story_${two(s)}';
      docs['docs/prds/features/f09_big/us${two(s)}_$story/USER_STORY.md'] =
          '# Story $s\n';
      items.add(story);
      for (var f = 1; f <= frsPerStory; f++) {
        final fr = 'fr_${two(f)}';
        docs['docs/prds/features/f09_big/us${two(s)}_$story/'
                'fr${two(f)}_$fr.md'] =
            '# Fr $f\n';
        items.add('$story/$fr');
      }
    }
    const recordPath = '.specstone/records/f09_big/IMPLEMENTATION.md';
    final record =
        '---\nstatuses:\n'
        '${[for (final item in items) "  - '$item:implemented'"].join('\n')}\n'
        'implements:\n'
        '${[for (final item in items) "  - '$item:app/lib/login.dart:checkPassword'"].join('\n')}\n'
        'tests:\n'
        '${[for (final item in items.take(testLines)) "  - '$item:app/lib/login.dart'"].join('\n')}\n'
        '---\n\n# Big implementation\n';
    docs[recordPath] = record;
    expect(items.length, greaterThan(testLines));
    expect(record.length, lessThan(60000));

    final report = await checkOf(
      await writeCheckProject(extra: docs, unstamped: {recordPath}),
    );

    expect(
      report.findings.where(
        (f) =>
            f.path == recordPath &&
            (f.kind == FindingKind.charsOverLimit ||
                f.kind == FindingKind.linesOverLimit ||
                f.kind == FindingKind.itemOverLimit),
      ),
      isEmpty,
    );
  });

  group('the implementation description', () {
    late String description;
    setUpAll(() async {
      description = prdCoreDocType(
        await resolveSoftwareTech(),
        'implementation',
      ).description!;
    });

    test('says the record is the one home of status and code paths, one '
        'entry per story and FR', () {
      expect(
        description,
        contains(
          "the one home of each story's and FR's status and code paths in "
          'its target',
        ),
      );
      expect(
        description,
        contains(
          'an item with no `statuses` line, outside every skip, is '
          '`planned`, code paths or not',
        ),
      );
      expect(
        description,
        contains(
          'A `skipped` entry carries a one-line reason and no code path',
        ),
      );
      expect(
        description,
        contains(
          'a skip on the feature or on a story covers everything below it',
        ),
      );
      expect(description, contains('one entry per story and FR'));
    });

    test('names the tests field, its line shape, and its quoting rule', () {
      expect(
        description,
        contains(
          '`tests` names one `<item>:<test file path>` line per item and '
          'test file that proves it',
        ),
      );
      expect(
        description,
        contains(
          'Add `:<test or group name>` after the path only to pin one test',
        ),
      );
      expect(
        description,
        contains(
          'written as a quoted YAML string when the name holds `: ` or ` #`',
        ),
      );
      expect(description, contains('Code and tests never name this doc.'));
    });

    test('says one line per statuses, implements, and tests entry, and names '
        'no cap number', () {
      expect(
        description,
        contains(
          'one line per entry in `statuses`, one per code path in '
          '`implements`, and one per test file in `tests`',
        ),
      );
      expect(description, contains('frontmatter lines'));
      expect(description, isNot(contains('400')));
      expect(description, isNot(contains('60,000')));
      expect(description, isNot(contains('60000')));
    });
  });
}
