import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
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
    'the record carries an optional prefix covers list after tests',
    () async {
      final record = prdCoreDocType(
        await resolveSoftwareTech(),
        'implementation',
      );

      expectOwnFields(record, const [
        FieldSpec('statuses', FieldType.recordStatus, list: true),
        FieldSpec(
          'implements',
          FieldType.outputRef,
          list: true,
          pointer: PointerKind.itemExact,
        ),
        FieldSpec(
          'tests',
          FieldType.outputRef,
          list: true,
          pointer: PointerKind.itemTest,
        ),
        FieldSpec(
          'covers',
          FieldType.outputRef,
          list: true,
          pointer: PointerKind.prefix,
        ),
      ]);
    },
  );

  test('adds no migrations entry for the matrix guide lines', () {
    final manifest = PackManifest.parse(
      utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
      file: 'packs/software-tech/pack.yaml',
    );

    expect(manifest.migrations, isEmpty);
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
}
