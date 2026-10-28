import 'dart:convert';

import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/legacy_moves.dart';
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
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
    test('f06/us01/fr04/e01: a numbered title loses its number', () {
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

    test('f06/us01/fr04/e01: a doc with no title line or no number keeps its '
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

    test('f06/us01/fr04/e02: the three project docs take fixed titles', () {
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

    test('f06/us01/fr04/e03: the Feature name folds into the title', () {
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
2. Meet the limits in [NFRs](../../d03_non_functional.md).
''');
      expect(result.changes, [
        'title from Feature name',
        'name',
        'index tables removed',
      ]);
    });

    test('f06/us01/fr04/e03: without a Human line the Feature name section '
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

    test('f06/us01/fr04/e04: name goes everywhere, feature_id from spec docs, '
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

    test('f06/us01/fr04/e05: the project vision labels become Why, Problem, '
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

    test('f06/us01/fr04/e06: the three index sections of a feature doc go', () {
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

    test('f06/us01/fr04/e03: a doc with no title line gets the Feature name '
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

    test('f06/us01/fr04/e12: an index section mid-doc keeps a tail with no '
        'final newline', () {
      const feature =
          '# Login\n\n## User stories index\n\n| a |\n\n## Notes\n\nKept';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '# Login\n\n## Notes\n\nKept');
      expect(result.changes, ['index tables removed']);
    });

    test('f06/us01/fr04/e12: a doc that ends in a blank line keeps it when an '
        'index section goes', () {
      const feature =
          '# Login\n\n## Notes\n\nKept\n\n## User stories index\n\n| a |\n\n';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '# Login\n\n## Notes\n\nKept\n\n');
      expect(result.changes, ['index tables removed']);
    });

    test('f06/us01/fr04/e12: an index section last in the doc leaves one '
        'final newline', () {
      const feature =
          '# Login\n\n## Notes\n\nKept\n\n## User stories index\n\n| a |\n';

      final result = rewriteLegacyDoc(feature, LegacyKind.feature);

      expect(result.lf, '# Login\n\n## Notes\n\nKept\n');
      expect(result.changes, ['index tables removed']);
    });

    test('f06/us01/fr04/e07: Tier-2 decisions becomes Concerns and FR ↔ '
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

    test('f06/us01/fr04/e08: GNFR headers stay and the ones no GNFR section '
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

    test('f06/us01/fr04/e12: every line the table does not name stays '
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

  group('readDocText and writtenText', () {
    test('f06/us01/fr04: a CRLF doc with a BOM keeps both', () {
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

    test('f06/us01/fr04: an LF doc without a BOM writes neither', () {
      final original = readDocText(utf8.encode('# D-01 — x\n'));

      expect(original.bom, isFalse);
      expect(original.ending, LineEnding.lf);
      expect(writtenText(original, '# x\n'), '# x\n');
    });
  });
}
