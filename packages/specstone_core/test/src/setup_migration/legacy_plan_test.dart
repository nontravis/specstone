import 'dart:io';

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/setup_migration/legacy_plan.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/legacy_fixture.dart';
import '../../helpers/temp_tree.dart';

/// The dry-run example of `s02_api_migrate.md`, up to the `left` block.
const _acmePlan = '''
legacy migration: /work/acme (docs/prds/d01_context.md)
commit 1, moves:
  prds/d01_context.md -> prds/PROJECT.md
  prds/d02_features.md -> prds/FEATURES.md
  prds/d03_non_functional.md -> prds/GNFR.md
  prds/features/f01_login/us01_email_login/functional_requirements/fr01_validate_credentials.md -> prds/features/f01_login/us01_email_login/fr01_validate_credentials.md
  specs/api/auth/s01_architecture.md -> specs/f01_login/ARCHITECTURE.md
  specs/api/auth/s02_api_login.md -> specs/f01_login/s02_api_login.md
  specs/api/auth/s02_api_session.md -> specs/f01_login/s02_api_session.md
  specs/shared/s01_architecture.md -> specs/topics/shared/s01_architecture.md
commit 2, rewrites:
  prds/PROJECT.md: title, name, vision labels
  prds/FEATURES.md: title, name
  prds/GNFR.md: title, name; project-layer section Data integrity
  prds/features/f01_login/FEATURE.md: title from Feature name, name, index tables removed, 2 links
  prds/features/f01_login/us01_email_login/USER_STORY.md: title, name
  prds/features/f01_login/us01_email_login/fr01_validate_credentials.md: title, name
  specs/f01_login/ARCHITECTURE.md: title, name, feature_id, Concerns, covers (1 path)
commit 2, creates:
''';

Future<RunPlan> _plan(Map<String, String> files) async {
  final root = await writeTree(files);
  return planLegacyRun(
    Directory(root.resolveSymbolicLinksSync()),
    templates: TemplateResolver(),
    homeDirectory: null,
  );
}

PlannedRewrite _rewrite(RunPlan plan, String docPath) =>
    plan.rewrites.singleWhere((r) => r.path == 'docs/$docPath');

Iterable<String> _createdPaths(RunPlan plan) => plan.creates.map((c) => c.path);

void main() {
  test('f06/us01/fr02/e01, f06/us01/s2: the acme plan is the dry-run '
      'example', () async {
    final root = await writeTree(acmeLegacy);
    final canonical = root.resolveSymbolicLinksSync();

    final plan = planLegacyRun(
      Directory(canonical),
      templates: TemplateResolver(),
      homeDirectory: null,
    );

    final example = _acmePlan.replaceFirst('/work/acme', canonical);
    expect(plan.toText(), startsWith(example));
    expect(
      plan.toText().substring(example.length),
      matches(
        RegExp(
          r'^  \.specstone/config\.yaml: prd-core \S+, software-tech \S+\n'
          r'  \.specstone/\.gitignore\n'
          r'  \.specstone/templates/gnfr\.yaml\n'
          r'  specs/TECH_STACK\.md \(draft\)\n'
          r'left in place for specstone check:\n'
          r'  specs/INDEX\.md\n$',
        ),
      ),
    );
  });

  test(
    'f06/us01/fr04/e11: an untyped file gets only the link rewrite',
    () async {
      final plan = await _plan(specEdgeLegacy);

      final rewrite = _rewrite(
        plan,
        'specs/f02_billing/billing_ui/s01_architecture.md',
      );

      expect(rewrite.changes, ['1 link']);
      expect(rewrite.text, contains('(../DOMAIN.md)'));
      expect(rewrite.text, contains('name: Billing UI architecture\n'));
      expect(rewrite.text, contains('feature_id: f02_billing\n'));
      expect(rewrite.text, contains('# S-01 — Billing UI architecture\n'));
    },
  );

  test('f06/us01/fr05/e02: a topic renamed one to one carries its '
      'applies_to entries as covers', () async {
    final plan = await _plan(specEdgeLegacy);

    final rewrite = _rewrite(plan, 'specs/topics/caching.md');

    expect(rewrite.changes, containsAll(['name', 'covers from applies_to']));
    expect(rewrite.text, contains('covers:'));
    expect(rewrite.text, contains('  - api/auth/'));
    expect(rewrite.text, contains('  - api/billing/'));
    expect(rewrite.text, isNot(contains('applies_to')));
  });

  test('f06/us01/fr05/e05, f06/us01/fr06/e03: a file that keeps its old '
      'name gets no covers and no fingerprint', () async {
    final plan = await _plan(specEdgeLegacy);

    final withCovers = plan.rewrites.where((r) => r.text.contains('covers:'));
    final withFingerprint = plan.rewrites.where(
      (r) => r.text.contains('confirmed:'),
    );

    expect(
      withCovers.map((r) => r.path),
      unorderedEquals([
        'docs/specs/f01_login/ARCHITECTURE.md',
        'docs/specs/topics/caching.md',
      ]),
    );
    expect(withFingerprint, isEmpty);
    expect(
      plan.rewrites.map((r) => r.path),
      isNot(contains('docs/specs/f01_login/s02_api_login.md')),
    );
  });

  test('f06/us01/fr06/e01: a lone API doc renamed to API.md gains a '
      'confirmed entry for the FR its trace names', () async {
    final tree = Map.of(acmeLegacy)
      ..remove('docs/specs/api/auth/s02_api_session.md')
      ..['docs/specs/api/auth/s02_api_login.md'] = '''
---
name: Login API
---

# S-02 — Login API

## FR trace

| FR id | Method |
|-------|--------|
| `us01_email_login/fr01_validate_credentials` | CLI |
''';

    final plan = await _plan(tree);

    final rewrite = _rewrite(plan, 'specs/f01_login/API.md');
    expect(rewrite.changes, contains('confirmed (1)'));
    expect(
      rewrite.text,
      contains('confirmed:\n  - email_login/validate_credentials '),
    );
  });

  test('f06/us01/fr05/e06, f06/us01/s8: a tree with no tech stack doc gets '
      'a draft one', () async {
    final plan = await _plan(acmeLegacy);

    final tech = plan.creates.singleWhere(
      (c) => c.path == 'docs/specs/TECH_STACK.md',
    );

    expect(tech.note, ' (draft)');
    expect(tech.text, startsWith('---\ndraft: true\n'));
  });

  test('f06/us01/fr05/e07: a tree with no d02 gets a FEATURES draft; '
      'PROJECT is never created', () async {
    final tree = Map.of(acmeLegacy)..remove('docs/prds/d02_features.md');

    final plan = await _plan(tree);

    expect(_createdPaths(plan), contains('docs/prds/FEATURES.md'));
    expect(_createdPaths(plan), isNot(contains('docs/prds/PROJECT.md')));
  });

  test('f06/us01/fr05/e08: specs/INDEX.md stays with its rows', () async {
    final plan = await _plan(acmeLegacy);

    expect(plan.left, contains('specs/INDEX.md'));
    expect(
      plan.rewrites.map((r) => r.path),
      isNot(contains('docs/specs/INDEX.md')),
    );
  });

  test(
    'f06/us01/fr05/e09: a tech stack doc already in place is kept',
    () async {
      final plan = await _plan({
        ...acmeLegacy,
        'docs/specs/TECH_STACK.md': '# Tech stack\n',
      });

      expect(_createdPaths(plan), isNot(contains('docs/specs/TECH_STACK.md')));
    },
  );

  test('f06/us01/fr06/e04, f06/us01/s7: a legacy FR gets no traced_from and '
      'no confirmed', () async {
    final plan = await _plan(acmeLegacy);

    final fr = _rewrite(
      plan,
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
    );

    expect(fr.text, isNot(contains('traced_from')));
    expect(fr.text, isNot(contains('confirmed')));
  });

  test('f06/us01/fr06/e05: a legacy nf gets no kind, overrides, or '
      'confirmed', () async {
    final plan = await _plan({
      ...acmeLegacy,
      'docs/prds/features/f01_login/us01_email_login/'
              'non_functional_requirements/nf01_latency.md':
          '---\nname: Latency\n---\n\n# NF-01 — Latency\n',
    });

    final nf = _rewrite(
      plan,
      'prds/features/f01_login/us01_email_login/nf01_latency.md',
    );

    expect(nf.changes, ['title', 'name']);
    expect(nf.text, isNot(contains('kind')));
    expect(nf.text, isNot(contains('overrides')));
    expect(nf.text, isNot(contains('confirmed')));
  });

  test('f06/us01/fr06/e06, f06/us01/fr02/e07: no rewritten doc holds a draft '
      'key; only created docs are drafts', () async {
    final plan = await _plan(specEdgeLegacy);

    for (final rewrite in plan.rewrites) {
      expect(rewrite.text, isNot(contains('draft:')), reason: rewrite.path);
    }
    for (final create in plan.creates.where((c) => c.note == ' (draft)')) {
      expect(create.text, startsWith('---\ndraft: true\n'));
    }
  });

  test('f06/us01/fr07/e08: the run removes no file', () async {
    final plan = await _plan(acmeLegacy);

    final steps = plan.journalSteps(base: 'x');

    expect(steps.whereType<MoveStep>(), hasLength(plan.moves.length));
    expect(
      steps.every(
        (s) =>
            s is MoveStep ||
            s is PruneStep ||
            s is WriteStep ||
            s is CreateStep ||
            s is CommitStep,
      ),
      isTrue,
    );
    expect(steps.map((s) => s.describe()).join('\n'), isNot(contains('trash')));
    expect(plan.left, contains('specs/INDEX.md'));
    expect(
      plan.moves.map((m) => m.to),
      contains('prds/PROJECT.md'),
      reason: 'the context doc moves',
    );
  });

  test(
    'f06/us01/fr07/e08: a container FEATURE.md moves, so it is not left',
    () async {
      final plan = await _plan(containerLegacy);

      expect(
        plan.moves.map((m) => m.from),
        contains('prds/features/components/co01_utilities/FEATURE.md'),
        reason: 'the container doc has a planned path',
      );
      expect(
        plan.left,
        isNot(contains('prds/features/components/co01_utilities/FEATURE.md')),
      );
    },
  );

  test('f06/us01/fr07: the journal commits the moves, then the rewrites and '
      'creates with .specstone/.gitignore', () async {
    final plan = await _plan(acmeLegacy);

    final steps = plan.journalSteps(base: 'abc');
    final commits = steps.whereType<CommitStep>().toList();

    expect(commits, hasLength(2));
    expect(commits.first.message, 'move legacy docs to their new paths');
    expect(commits.first.paths, contains('docs/prds/d01_context.md'));
    expect(commits.first.paths, contains('docs/prds/PROJECT.md'));
    expect(
      commits.last.message,
      'rewrite titles, keys, and links; add project configuration',
    );
    expect(commits.last.paths, contains('.specstone/.gitignore'));
    expect(commits.last.paths, contains('.specstone/config.yaml'));
    expect(commits.last.paths, contains('docs/prds/PROJECT.md'));
    expect(commits.last.paths.toSet(), hasLength(commits.last.paths.length));
    expect(commits.every((c) => c.base == 'abc'), isTrue);
    expect(steps.indexOf(commits.first), lessThan(steps.indexOf(commits.last)));
    expect(
      plan.closingLine,
      'run specstone check to list what is left to fill',
    );
  });

  test('f06/us01/fr03/e13: a binary file in a moved folder moves untouched '
      'and is never read as text', () async {
    final root = await writeTree(acmeLegacy);
    File('${root.path}/docs/specs/shared/logo.png').writeAsBytesSync([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0xff, 0xfe, //
    ]);

    final plan = planLegacyRun(
      Directory(root.resolveSymbolicLinksSync()),
      templates: TemplateResolver(),
      homeDirectory: null,
    );

    expect(
      plan.moves,
      contains((
        from: 'specs/shared/logo.png',
        to: 'specs/topics/shared/logo.png',
      )),
    );
    expect(plan.rewrites.where((r) => r.path.endsWith('.png')), isEmpty);
  });

  test('f06/us01/fr04/e11: a markdown doc left in place gets the link '
      'rewrite only', () async {
    final plan = await _plan({
      ...acmeLegacy,
      'docs/prds/d04_glossary.md': [
        '# Glossary\n\nSee [FR](features/f01_login/us01_email_login/',
        'functional_requirements/fr01_validate_credentials.md).\n',
      ].join(),
    });

    final rewrite = _rewrite(plan, 'prds/d04_glossary.md');

    expect(rewrite.changes, ['1 link']);
    expect(
      rewrite.text,
      contains('(features/f01_login/us01_email_login/fr01_validate'),
    );
    expect(rewrite.text, isNot(contains('functional_requirements')));
    expect(plan.left, contains('prds/d04_glossary.md'));
  });

  test('f06/us01/fr06/e01: the fingerprint hashes the Statement as the run '
      'writes it', () async {
    final plan = await _plan(
      {
        ...acmeLegacy,
        'docs/prds/features/f01_login/us01_email_login/functional_requirements/'
            'fr01_validate_credentials.md': '''
---
name: Validate credentials
status: planned
---

# FR-01 — Validate credentials

## Statement

The system checks the credentials against [the NFRs](../../../../d03_non_functional.md).
''',
        'docs/specs/api/auth/s02_api_login.md': '''
---
name: Login API
---

# S-02 — Login API

## FR trace

| FR id | Method |
|-------|--------|
| `us01_email_login/fr01_validate_credentials` | CLI |
''',
      }..remove('docs/specs/api/auth/s02_api_session.md'),
    );

    final fr = _rewrite(
      plan,
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
    );
    final api = _rewrite(plan, 'specs/f01_login/API.md');

    final statement = Doc.parse(fr.text).sections
        .singleWhere((s) => s.headerText == 'Statement')
        .body;
    expect(statement, contains('(../../../GNFR.md)'));
    expect(
      api.text,
      contains(
        'email_login/validate_credentials ${fingerprintOf(statement)}\n',
      ),
    );
  });

  test('f06/us01/fr05/e04: a legacy header whose id a carried section holds '
      'is added, not merged into it', () async {
    final plan = await _plan({
      ...acmeLegacy,
      'docs/prds/d03_non_functional.md': '''
---
name: NFR
---

# D-03 — Project-wide non-functional requirements

## Safety!

| ID | Requirement |
|----|-------------|
| NFR-01 | Be safe. |
''',
    });

    final override = plan.creates.singleWhere(
      (c) => c.path == '.specstone/templates/gnfr.yaml',
    );

    expect(override.text, contains('id: safety_2\n'));
    expect(override.text, contains("header: 'Safety!'"));
  });

  test('f06/us01/fr01/e03: an existing config is rewritten with the carried '
      'pins and keeps its other pins', () async {
    final versions = shippedPackVersions();
    final plan = await _plan({
      ...acmeLegacy,
      '.specstone/config.yaml': 'packs:\n  prd-core: 0.0.1\n  my-pack: 1.0.0\n',
    });

    final rewrite = plan.rewrites.singleWhere(
      (r) => r.path == '.specstone/config.yaml',
    );

    expect(rewrite.changes, ['pins']);
    expect(
      rewrite.text,
      'packs:\n  my-pack: 1.0.0\n  prd-core: ${versions['prd-core']}\n'
      '  software-tech: ${versions['software-tech']}\n',
    );
    expect(_createdPaths(plan), isNot(contains('.specstone/config.yaml')));
    expect(plan.toText(), contains('  .specstone/config.yaml: pins\n'));
  });

  test(
    'f06/us01/fr03/e09: a plan refusal throws before anything prints',
    () async {
      final root = await writeTree(duplicateGroupLegacy);

      expect(
        () => planLegacyRun(
          Directory(root.resolveSymbolicLinksSync()),
          templates: TemplateResolver(),
          homeDirectory: null,
        ),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.groupSlugDuplicate,
          ),
        ),
      );
    },
  );
}
