import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _fr =
    'template_packs/write_spec_docs_from_software_tech/'
    'write_spec_writing_guides';

void main() {
  late MergedDocType record;
  setUpAll(() async {
    record = prdCoreDocType(await resolveSoftwareTech(), 'implementation');
  });

  test('$_fr E01, E03, E04, E14: the implementation guide titles its doc, '
      'never writes status, and names the record as the one home', () {
    expectSpecGuide(
      record,
      title: '# <Feature name> implementation',
      says: [
        'one home of each story',
        '`planned`, code paths or not',
        'skipped',
        'one-line reason',
      ],
      maxChars: 60000,
    );
    expectItemShape(
      record,
      'Write one rule per ID: one entry per story and FR, each rule one '
      'sentence.',
    );
  });

  test('template_packs/write_spec_docs_from_software_tech/'
      'set_spec_lint_and_sources: the implementation type caps 400 lines, '
      'bans no word, and cites its four sources', () {
    expectSpecLint(record, maxChars: 60000);
  });

  test(
    'template_packs/write_spec_docs_from_software_tech/'
    'set_spec_lint_and_sources E04: a record holding an entry for every '
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
      const recordPath = 'docs/specs/f09_big/IMPLEMENTATION.md';
      docs[recordPath] =
          '---\nstatuses:\n${statuses.join('\n')}\nimplements:\n'
          '${code.join('\n')}\n---\n\n# Big implementation\n';
      expect(
        statuses.length,
        stories * (1 + frsPerStory),
        reason: 'an entry for every story and FR',
      );

      final report = checkOf(
        await writeCheckProject(extra: docs, unstamped: {recordPath}),
      );

      final sizeFindings = report.findings.where(
        (f) =>
            f.path == 'specs/f09_big/IMPLEMENTATION.md' &&
            (f.kind == FindingKind.linesOverLimit ||
                f.kind == FindingKind.itemOverLimit),
      );
      expect(sizeFindings, isEmpty);
      expect(
        report.findings.where(
          (f) =>
              f.path == 'specs/f09_big/IMPLEMENTATION.md' &&
              f.kind == FindingKind.untypedDoc,
        ),
        isEmpty,
        reason: 'the record is typed, so the size rules read it',
      );
    },
  );
}
