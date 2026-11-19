import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _matrixGuideLines = <String>[
  _matrixMapsLine,
  _matrixRowLine,
  _matrixNameLine,
  _matrixLiteralLine,
  _matrixFingerprintLine,
  _matrixSkipLine,
];

const _matrixMapsLine =
    '`## Verification matrix` maps each FR to the tests that prove it, one '
    'line per FR; under `verification_coverage: edge_case`, one line per edge '
    'case and test.';

const _matrixRowLine =
    'Write a test row as ``- <fr>: `<literal>`, `<literal>` ``, one literal '
    'per test, joined by `, `; under `edge_case`, '
    '``- <fr> E<nn>: `<literal>` ``.';

const _matrixNameLine =
    'Name a test by one string literal of its name, in a code span, as the '
    'test file writes it; take its first literal.';

const _matrixLiteralLine =
    "Each literal must occur in a file that one of the item's `tests` lines "
    'names.';

const _matrixFingerprintLine =
    'Copy each fingerprint from `specstone check`; never compute one.';

const _matrixSkipLine =
    'Write a skip row, `- <fr> skipped: <reason>`, for an FR that no test can '
    'prove; under `edge_case`, one per edge case.';

void main() {
  test(
    'the description names neither the line cap nor the character cap',
    () async {
      final record = prdCoreDocType(
        await resolveSoftwareTech(),
        'implementation',
      );

      expect(record.description, isNot(contains('400')));
      expect(record.description, isNot(contains('60,000')));
      expect(
        record.description?.split('\n'),
        contains(
          'The line cap does not count these frontmatter lines, so the '
          'character cap bounds them.',
        ),
      );
    },
  );

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

  test('ships the per-FR matrix guide lines', () async {
    final record = prdCoreDocType(
      await resolveSoftwareTech(),
      'implementation',
    );

    expect(
      verificationMatrixOf(record)!.description?.split('\n'),
      _matrixGuideLines,
    );
  });

  test('adds no migrations entry for the matrix guide lines', () {
    final manifest = PackManifest.parse(
      utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
      file: 'packs/software-tech/pack.yaml',
    );

    expect(manifest.version.toString(), '1.14.0');
    expect(manifest.migrations.map((m) => m.from.toString()), [
      '1.4.0',
      '1.6.0',
      '1.7.0',
      '1.13.0',
    ]);
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

  test('a record of a large feature with 150 tests lines passes check with'
      ' no size finding', () async {
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
    String lines(String key, Iterable<String> entries) =>
        '$key:\n${[for (final e in entries) "  - '$e'\n"].join()}';
    const path = 'app/lib/login.dart';
    final statuses = [for (final i in items) '$i:implemented'];
    final code = [for (final i in items) '$i:$path:checkPassword'];
    final tests = [for (final i in items.take(testLines)) '$i:$path'];
    final record =
        '---\n${lines('statuses', statuses)}${lines('implements', code)}'
        '${lines('tests', tests)}---\n\n# Big implementation\n';
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

    test('says the record is the one home of status and code paths, one'
        ' entry per story and FR', () {
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

    test('says one line per statuses, implements, and tests entry, and names'
        ' no cap number', () {
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
