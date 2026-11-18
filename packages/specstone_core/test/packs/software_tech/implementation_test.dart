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
}
