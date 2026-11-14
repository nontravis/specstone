import 'dart:convert';

import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/label_pass.dart';
import 'package:specstone_core/src/setup_migration/legacy_moves.dart';
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:test/test.dart';

import '../../helpers/legacy_fixture.dart';
import '../../helpers/prd_core.dart';

String _acme(String name) => acmeLegacy['docs/prds/$name']!;

void main() {
  late Set<String> gnfrHeaders;
  setUpAll(() async {
    final gnfr = prdCoreDocType(await resolvePrdCore(), 'gnfr');
    gnfrHeaders = {for (final section in gnfr.sections) section.header};
  });

  group('rewriteLegacyDoc', () {
    test('a numbered title loses its number', () {
      const fr = '''
---
name: Check pack pins
status: planned
---

# FR-02 — Check pack pins

## Statement

The system checks the pins.
''';
      const domain = '''
---
name: Check command API
feature_id: f02
---

# S-02 — check command API

## Models

None.
''';

      final frResult = rewriteLegacyDoc(fr, LegacyKind.fr);
      final domainResult = rewriteLegacyDoc(domain, LegacyKind.domain);

      expect(frResult.lf, '''
---
status: planned
---

# Check pack pins

## Statement

The system checks the pins.
''');
      expect(frResult.changes, ['title', 'name']);
      expect(domainResult.lf, '''
---
---

# check command API

## Models

None.
''');
      expect(domainResult.changes, ['title', 'name', 'feature_id']);
    });

    test('a doc with no title line or no number keeps its '
        'title line', () {
      const noTitle = '''
---
status: planned
---

## Statement

The system checks the pins.
''';
      const noNumber = '''
# Check pack pins

Body.
''';

      final noTitleResult = rewriteLegacyDoc(noTitle, LegacyKind.fr);
      final noNumberResult = rewriteLegacyDoc(noNumber, LegacyKind.fr);

      expect(noTitleResult.lf, noTitle);
      expect(noTitleResult.changes, isEmpty);
      expect(noNumberResult.lf, noNumber);
      expect(noNumberResult.changes, isEmpty);
    });

    test('the three project docs take fixed titles', () {
      final project = rewriteLegacyDoc(
        _acme('d01_context.md'),
        LegacyKind.project,
      );
      final features = rewriteLegacyDoc(
        _acme('d02_features.md'),
        LegacyKind.features,
      );
      final gnfr = rewriteLegacyDoc(
        _acme('d03_non_functional.md'),
        LegacyKind.gnfr,
        gnfrHeaders: gnfrHeaders,
      );

      expect(project.lf, contains('\n# Project context\n'));
      expect(features.lf, '---\n---\n\n# System map\n');
      expect(
        gnfr.lf,
        contains('\n# Project-wide non-functional requirements\n'),
      );
      expect(project.changes, ['title', 'name', 'vision labels']);
      expect(features.changes, ['title', 'name']);
      expect(gnfr.changes, ['title', 'name']);
    });

    test('the Feature name folds into the title', () {
      final result = rewriteLegacyDoc(
        _acme('features/f01_login/FEATURE.md'),
        LegacyKind.feature,
      );

      expect(result.lf, '''
---
---

# Login

## Feature goal

Let a user sign in.

## Feature flow

1. Validate the credentials: [FR-01](us01_email_login/functional_requirements/fr01_validate_credentials.md).
2. Meet the limits in [NFRs](../../d03_non_functional.md), last listed in
   `../../d02_features.md`.
''');
      expect(result.changes, [
        'title from Feature name',
        'name',
        'index tables removed',
      ]);
    });

    test('without a Human line the Feature name section '
        'stays and the title only loses its number', () {
      const feature = '''
# F-01 — Login

## Feature name

- **Code:** `login`

## Feature goal

Let a user sign in.
''';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, feature.replaceFirst('F-01 — ', ''));
      expect(result.changes, ['title']);
    });

    test('name goes everywhere, feature_id from spec docs, '
        'applies_to becomes covers', () {
      const topic = '''
---
name: Doc model
feature_id: f02
status: implemented
applies_to:
  - lib/src/doc_model/
---

# Doc model

## Summary

Parsing.
''';
      const feature = '''
---
name: Login
feature_id: keep-me
---

# Login
''';

      final topicResult = rewriteLegacyDoc(topic, LegacyKind.topic);
      final featureResult = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(topicResult.lf, '''
---
status: implemented
covers:
  - lib/src/doc_model/
---

# Doc model

## Summary

Parsing.
''');
      expect(topicResult.changes, [
        'name',
        'feature_id',
        'covers from applies_to',
      ]);
      expect(featureResult.lf, '''
---
feature_id: keep-me
---

# Login
''');
      expect(featureResult.changes, ['name']);
    });

    test('the project vision labels become Why, Problem, '
        'and Audience', () {
      final project = rewriteLegacyDoc(
        _acme('d01_context.md'),
        LegacyKind.project,
      );
      const labelled = '''
# Login

- **เพื่ออะไร (why):** Let owners log in.
''';
      final feature = rewriteLegacyDoc(labelled, LegacyKind.feature);

      expect(project.lf, '''
---
---

# Project context

## Project vision

- **Why:** Let owners log in.
- **Problem:** Sign-in is slow.
- **Audience:** Acme staff.
''');
      expect(feature.lf, labelled);
      expect(feature.changes, isEmpty);
    });

    test('the three index sections of a feature doc go', () {
      const feature = '''
# Login

## Feature goal

Goal.

## User stories index

| Story |
|-------|
| US-01 |

## US ↔ FR rollup

| Story |
|-------|
| US-01 |

## Sub-features index

| Sub |
|-----|
| a   |

## Notes

Kept.
''';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '''
# Login

## Feature goal

Goal.

## Notes

Kept.
''');
      expect(result.changes, ['index tables removed']);
    });

    test('a doc with no title line gets the Feature name '
        'as its title', () {
      const feature = '''
## Feature name

- **Human:** Login

## Feature goal

Goal.
''';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '''
# Login
## Feature goal

Goal.
''');
      expect(result.changes, ['title from Feature name']);
    });

    test('an index section mid-doc keeps a tail with no '
        'final newline', () {
      const feature =
          '# Login\n\n## User stories index\n\n| a |\n\n## Notes\n\nKept';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '# Login\n\n## Notes\n\nKept');
      expect(result.changes, ['index tables removed']);
    });

    test('a doc that ends in a blank line keeps it when an '
        'index section goes', () {
      const feature =
          '# Login\n\n## Notes\n\nKept\n\n## User stories index\n\n| a |\n\n';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '# Login\n\n## Notes\n\nKept\n\n');
      expect(result.changes, ['index tables removed']);
    });

    test('an index section last in the doc leaves one '
        'final newline', () {
      const feature =
          '# Login\n\n## Notes\n\nKept\n\n## User stories index\n\n| a |\n';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '# Login\n\n## Notes\n\nKept\n');
      expect(result.changes, ['index tables removed']);
    });

    test('an index section last in a doc with no final '
        'newline leaves one final newline', () {
      const feature =
          '# Login\n\n## Notes\n\nKept\n\n## User stories index\n\n| a |';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '# Login\n\n## Notes\n\nKept\n');
      expect(result.changes, ['index tables removed']);
    });

    test('Tier-2 decisions becomes Concerns and FR ↔ '
        'endpoint trace becomes FR trace', () {
      const architecture = '''
# Architecture

## Tier-2 decisions

- Decide.
''';
      const api = '''
# API

## FR ↔ endpoint trace

| FR |
|----|
''';

      final architectureResult = rewriteLegacyDoc(
        architecture,
        LegacyKind.architecture,
      );
      final apiResult = rewriteLegacyDoc(api, LegacyKind.api);

      expect(
        architectureResult.lf,
        architecture.replaceFirst('Tier-2 decisions', 'Concerns'),
      );
      expect(architectureResult.changes, ['Concerns']);
      expect(apiResult.lf, api.replaceFirst('FR ↔ endpoint trace', 'FR trace'));
      expect(apiResult.changes, ['FR trace']);
      expect(
        rewriteLegacyDoc(architecture, LegacyKind.domain).lf,
        architecture,
      );
    });

    test('GNFR headers stay and the ones no GNFR section '
        'has are listed', () {
      final result = rewriteLegacyDoc(
        _acme('d03_non_functional.md'),
        LegacyKind.gnfr,
        gnfrHeaders: gnfrHeaders,
      );

      expect(result.gnfrSections, ['Data integrity']);
      expect(result.lf, contains('\n## Performance\n'));
      expect(result.lf, contains('\n## Data integrity\n'));
    });

    test("f06/us01/fr04/e09, f06/us01/s6: a feature doc's implements entries "
        'stay', () {
      const feature = '''
---
name: Login
implements:
  - lib/src/login.dart
  - lib/src/session.dart
---

# F-01 — Login
''';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '''
---
implements:
  - lib/src/login.dart
  - lib/src/session.dart
---

# Login
''');
    });

    test('every line the table does not name stays '
        'byte-equal', () {
      const feature = '''
---
name: Login
---

# F-01 — Login

## Summary

Keep   this  line, trailing space
and tabs\there.

## Feature goal

Let a user sign in.
''';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '''
---
---

# Login

## Summary

Keep   this  line, trailing space
and tabs\there.

## Feature goal

Let a user sign in.
''');
    });
  });

  group('rewriteLinks', () {
    final paths = [
      for (final key in acmeLegacy.keys) key.substring('docs/'.length),
    ];
    final moves = planLegacyMoves(
      paths,
      specMap: readSpecMap(acmeLegacy['docs/specs/INDEX.md']!),
      features: scanLegacyFeatures(paths),
    ).moves;

    test('links to moved files point at the new paths', () {
      final result = rewriteLinks(
        _acme('features/f01_login/FEATURE.md'),
        docPath: 'prds/features/f01_login/FEATURE.md',
        moves: moves,
      );

      expect(
        result.lf,
        contains('[FR-01](us01_email_login/fr01_validate_credentials.md)'),
      );
      expect(result.lf, contains('[NFRs](../../GNFR.md)'));
      expect(result.label, '2 links');
    });

    test('a doc moved one folder deeper keeps its code '
        'link pointing at the same file', () {
      final result = rewriteLinks(
        '[code](../../../lib/a.dart)\n',
        docPath: 'specs/f01/s01.md',
        moves: [(from: 'specs/f01/s01.md', to: 'specs/f01/sub/s01.md')],
      );

      expect(result.lf, '[code](../../../../lib/a.dart)\n');
      expect(result.label, '1 link');
    });

    test('a link to a file that stays keeps its target, '
        "and a moved doc's link is recomputed", () {
      const fr = '''
# FR-01 — Validate credentials

See [story](../USER_STORY.md) and [index](../../../../../specs/INDEX.md).
''';

      final result = rewriteLinks(
        fr,
        docPath:
            'prds/features/f01_login/us01_email_login/'
            'functional_requirements/fr01_validate_credentials.md',
        moves: moves,
      );

      expect(
        result.lf,
        fr
            .replaceFirst('(../USER_STORY.md)', '(USER_STORY.md)')
            .replaceFirst(
              '(../../../../../specs/INDEX.md)',
              '(../../../../specs/INDEX.md)',
            ),
      );
      expect(result.label, '2 links');
    });

    test('no link change gives a null label and the same '
        'text', () {
      const lf = 'See [web](https://x.dev/a.md).\n';

      final result = rewriteLinks(lf, docPath: 'specs/INDEX.md', moves: moves);

      expect(result.lf, lf);
      expect(result.label, isNull);
    });

    test('an untyped moved doc gets the link rewrite '
        'only', () {
      const doc = '''
---
name: login
---

# S-02 — login API

[arch](s01_architecture.md)
''';

      final result = rewriteLinks(
        doc,
        docPath: 'specs/api/auth/s02_api_login.md',
        moves: moves,
      );

      expect(result.lf, doc.replaceFirst('s01_architecture', 'ARCHITECTURE'));
      expect(result.label, '1 link');
    });
  });

  group('readDocText and writtenText', () {
    test('a CRLF doc with a BOM keeps both', () {
      final lfText = _acme('d01_context.md');
      final bytes = [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(LineEnding.crlf.apply(lfText)),
      ];

      final original = readDocText(bytes);
      final rewrite = rewriteLegacyDoc(original.lf, LegacyKind.project);
      final written = writtenText(original, rewrite.lf);

      expect(original.bom, isTrue);
      expect(original.ending, LineEnding.crlf);
      expect(original.lf, lfText);
      expect(written, startsWith('﻿'));
      expect(written.replaceAll('\r\n', '').contains('\n'), isFalse);
      expect(
        toLf(written.substring(1)),
        rewriteLegacyDoc(lfText, LegacyKind.project).lf,
      );
    });

    test('an LF doc without a BOM writes neither', () {
      final original = readDocText(utf8.encode('# D-01 — x\n'));

      expect(original.bom, isFalse);
      expect(original.ending, LineEnding.lf);
      expect(writtenText(original, '# x\n'), '# x\n');
    });
  });

  group('convertLegacyLabels', () {
    const rewrite =
        'setup_migration/migrate_legacy_docs/'
        'rewrite_titles_keys_and_links';
    const base = 'prds/features/ai01_login';
    const frFolder = '$base/us01_email_login/functional_requirements';
    const newBase = 'prds/features/f01_login';
    const frLegacy = '$frFolder/fr01_validate_credentials.md';

    final tree = LabelTree.legacy(
      [
        for (final (legacyPath, docPath) in [
          ('$base/FEATURE.md', '$newBase/FEATURE.md'),
          (
            '$base/us01_email_login/USER_STORY.md',
            '$newBase/us01_email_login/USER_STORY.md',
          ),
          (frLegacy, '$newBase/us01_email_login/fr01_validate_credentials.md'),
          (
            '$frFolder/fr02_lock_account.md',
            '$newBase/us01_email_login/fr02_lock_account.md',
          ),
          (
            'prds/features/ai01_other/us01_x/functional_requirements/'
                'fr01_y.md',
            'prds/features/f01_other/us01_x/fr01_y.md',
          ),
          (
            'prds/features/ai01_02_chat/us01_c/functional_requirements/'
                'fr02_d.md',
            'prds/features/f02_chat/us01_c/fr02_d.md',
          ),
          (
            'prds/features/ai03_2fa_login/us01_e/functional_requirements/'
                'fr01_f.md',
            'prds/features/f03_2fa_login/us01_e/fr01_f.md',
          ),
          (
            'prds/features/ui01_third/us01_z/functional_requirements/'
                'fr05_w.md',
            'prds/features/f01_third/us01_z/fr05_w.md',
          ),
        ])
          (docPath: docPath, legacyPath: legacyPath, lf: ''),
      ],
      featurePaths: {
        '$base/': 'f01_login',
        'prds/features/ai01_other/': 'f01_other',
        'prds/features/ai01_02_chat/': 'f02_chat',
        'prds/features/ai03_2fa_login/': 'f03_2fa_login',
        'prds/features/ui01_third/': 'f01_third',
        'prds/features/g01_payments/ai02_chat/': 'g01_payments/f02_chat',
      },
    );

    ({String lf, int rewrites, List<({int line, String label})> kept}) convert(
      String lf, {
      String citedFrom = '$base/FEATURE.md',
    }) => convertLegacyLabels(tree, legacyPath: citedFrom, lf: lf);

    test('$rewrite E18: a legacy ID the move list maps to one FR becomes its '
        'name, one inside a code span stays as written', () {
      final result = convert(
        'Built by ai01/us02/fr09 and `ai01/us01/fr02`.\n'
        'See ai01/us01/fr02.\n',
      );

      expect(
        result.lf,
        'Built by ai01/us02/fr09 and `ai01/us01/fr02`.\n'
        'See `login/email_login/lock_account`.\n',
      );
      expect(result.kept, [(line: 1, label: 'ai01/us02/fr09')]);
    });

    test('$rewrite E18: a legacy ID whose folders map to no moved doc stays '
        'as written and is listed', () {
      final result = convert('Nothing at ai09/us01/fr01 here.\n');

      expect(result.lf, 'Nothing at ai09/us01/fr01 here.\n');
      expect(result.kept, [(line: 1, label: 'ai09/us01/fr01')]);
    });

    test('$rewrite E18: a legacy ID the move list maps to 2 FRs stays as '
        'written and is listed', () {
      final result = convert('Both ai01/us01/fr01 here.\n');

      expect(result.lf, 'Both ai01/us01/fr01 here.\n');
      expect(result.kept, [(line: 1, label: 'ai01/us01/fr01')]);
    });

    test('$rewrite E18: a legacy ID finds only the folders of its own '
        'prefix, though another feature holds that number', () {
      final result = convert('Is ai01/us01/fr05 there, or ui01/us01/fr05?\n');

      expect(result.lf, 'Is ai01/us01/fr05 there, or `third/z/w`?\n');
      expect(result.kept, [(line: 1, label: 'ai01/us01/fr05')]);
    });

    test('$rewrite E18: a legacy ID names the whole folder ID, so ai01 and '
        'ai01_02 side by side stay apart', () {
      final result = convert('Is ai01/us01/fr02 or ai01_02/us01/fr02?\n');

      expect(result.lf, 'Is `login/email_login/lock_account` or `chat/c/d`?\n');
    });

    test('$rewrite E18: a legacy folder ID ends where the folder name does, '
        'not inside a slug that opens with digits', () {
      final result = convert('See ai03/us01/fr01.\n');

      expect(result.lf, 'See `2fa_login/e/f`.\n');
    });

    test('$rewrite E18: a legacy ID that goes on to another folder names no '
        'doc by its first folders', () {
      final result = convert('Not ai01/us01/nf01 or ai01/us01/fr02/e09.\n');

      expect(
        result.lf,
        'Not ai01/us01/nf01 or `login/email_login/lock_account`/e09.\n',
      );
      expect(result.kept, [(line: 1, label: 'ai01/us01')]);
    });

    test('$rewrite E19: a full label names the story by its legacy folder '
        'numbers; a feature alone names the typed feature', () {
      final result = convert('See F-01 US-01 and F-01 for the feature.\n');

      expect(
        result.lf,
        'See `login/email_login` and `feature:login` for the feature.\n',
      );
      expect(result.kept, isEmpty);
    });

    test("$rewrite E19: a partial label reads against the citing doc's own "
        'story before the move', () {
      final result = convert(
        'After FR-02 and US-01 FR-02, not FR-07.\n',
        citedFrom: frLegacy,
      );

      expect(
        result.lf,
        'After `login/email_login/lock_account` and '
        '`login/email_login/lock_account`, not FR-07.\n',
      );
      expect(result.kept, [(line: 1, label: 'FR-07')]);
    });

    test('$rewrite E19: a partial label in a doc with no feature place '
        'before the move stays as written, though the doc lands in one', () {
      final result = convert(
        'After FR-02.\n',
        citedFrom: 'specs/api/auth/s02_api_login.md',
      );

      expect(result.lf, 'After FR-02.\n');
      expect(result.kept, [(line: 1, label: 'FR-02')]);
    });

    test('$rewrite E19: a label in a link destination or under the '
        'frontmatter is no label to convert', () {
      final result = convert('---\nname: FR-02\n---\n\n[x](FR-02.md)\n');

      expect(result.lf, '---\nname: FR-02\n---\n\n[x](FR-02.md)\n');
      expect(result.kept, isEmpty);
    });

    test('$rewrite E19: a doc of a grouped feature has no place, so a '
        'partial label there stays', () {
      final result = convert(
        'After US-01.\n',
        citedFrom:
            'prds/features/g01_payments/ai02_chat/us13_pay/USER_STORY.md',
      );

      expect(result.lf, 'After US-01.\n');
      expect(result.kept, [(line: 1, label: 'US-01')]);
    });

    test('$rewrite E19: a doc left in place under a feature folder reads '
        'against that place', () {
      final result = convert(
        'After US-01.\n',
        citedFrom: 'specs/f01_login/DOMAIN.md',
      );

      expect(result.lf, 'After `login/email_login`.\n');
    });
  });
}
