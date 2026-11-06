import 'dart:io';

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/legacy_plan.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/legacy_fixture.dart';
import '../../helpers/posix_modes.dart';
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

const _legacySpec = 'docs/specs/shared/s01_architecture.md';

/// Plans [linkedAcme] of [files] from link folder `ws/code`.
Future<RunPlan> _linkedPlan(Map<String, String> files) async =>
    _planFromLink(await writeTree(linkedAcme(files)));

/// Plans the `ws/` folder of [tree] from link folder `ws/<linkName>`.
RunPlan _planFromLink(Directory tree, {String linkName = 'code'}) {
  final separator = Platform.pathSeparator;
  final ws = '${tree.resolveSymbolicLinksSync()}${separator}ws';
  return planLegacyRun(
    Directory(ws),
    templates: TemplateResolver(),
    homeDirectory: null,
    linkFolder: Directory('$ws$separator$linkName'),
  );
}

PlannedCreate _configCreate(RunPlan plan) =>
    plan.creates.singleWhere((c) => c.path == '.specstone/config.yaml');

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
          r'  agent files: \.specstone/AGENT\.md, AGENTS\.md\n'
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

  test('f06/us01/fr06, s03/inv12: an API doc with a flow-list confirmed and '
      'no other legacy label is planned with its FR cells rewritten', () async {
    final tree = Map.of(acmeLegacy)
      ..remove('docs/specs/api/auth/s02_api_session.md')
      ..['docs/specs/api/auth/s02_api_login.md'] = '''
---
confirmed: [x]
---

# Login API

## FR trace

| FR id | Method |
|-------|--------|
| `us01_email_login/fr01_validate_credentials` | CLI |
''';

    final plan = await _plan(tree);

    final rewrite = _rewrite(plan, 'specs/f01_login/API.md');
    expect(rewrite.changes, ['FR trace cells']);
    expect(
      rewrite.text,
      contains('| `email_login/validate_credentials` | CLI |'),
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

    final steps = plan.journalSteps(
      base: 'x',
      projectRoot: Directory.systemTemp,
    );

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

  test('f06/us01/fr03/e04, final I5: a group whose slug is not [a-z0-9_]+ '
      'stays in place with its container and prints under left', () async {
    const toolContainer = 'prds/features/co01_tool-module/FEATURE.md';
    const stripe = 'prds/features/co01_tool-module/tm01_stripe/FEATURE.md';
    const slot = 'prds/features/co02_/cc01_slot/FEATURE.md';
    final plan = await _plan({
      'docs/prds/d01_context.md': '# D-01 — Project context\n',
      'docs/$toolContainer': '# Tool module\n',
      'docs/$stripe': '# F-01 — Stripe\n',
      'docs/$slot': '# F-01 — Slot\n',
      'docs/prds/features/ai_module/ai05_chat/FEATURE.md': '# F-05 — Chat\n',
    });

    expect(
      plan.moves,
      contains((
        from: 'prds/features/ai_module/ai05_chat/FEATURE.md',
        to: 'prds/features/ai_module/f05_chat/FEATURE.md',
      )),
    );
    expect(
      plan.moves.map((m) => m.from),
      isNot(anyOf(contains(toolContainer), contains(stripe), contains(slot))),
    );
    expect(plan.left, containsAll([toolContainer, stripe, slot]));
  });

  test('f06/us01/fr07: the journal commits the moves, then the rewrites and '
      'creates with .specstone/.gitignore', () async {
    final plan = await _plan(acmeLegacy);

    final steps = plan.journalSteps(
      base: 'abc',
      projectRoot: Directory.systemTemp,
    );
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

  group('f06/us01/fr03/e13, final I2: a .md file that is not UTF-8', () {
    // `café` in Windows-1252: 0xe9 is no UTF-8 sequence.
    const latin1 = [0x23, 0x20, 0x4e, 0x6f, 0x74, 0x65, 0x73, 0x0a, 0xe9, 0x0a];

    Future<RunPlan> planWith(Map<String, List<int>> bytes) async {
      final root = await writeTree(acmeLegacy);
      for (final MapEntry(:key, :value) in bytes.entries) {
        File('${root.path}/$key').writeAsBytesSync(value);
      }
      return planLegacyRun(
        Directory(root.resolveSymbolicLinksSync()),
        templates: TemplateResolver(),
        homeDirectory: null,
      );
    }

    test('f06/us01/fr03/e13: moves untouched with no rewrite, and the plan '
        'prints its move; one left in place is skipped too', () async {
      final plan = await planWith({
        'docs/specs/shared/notes.md': latin1,
        'docs/prds/d04_glossary.md': latin1,
      });

      expect(
        plan.moves,
        contains((
          from: 'specs/shared/notes.md',
          to: 'specs/topics/shared/notes.md',
        )),
      );
      expect(
        plan.toText(),
        contains('  specs/shared/notes.md -> specs/topics/shared/notes.md\n'),
      );
      expect(
        plan.rewrites.map((r) => r.path),
        isNot(
          anyOf(
            contains('docs/specs/topics/shared/notes.md'),
            contains('docs/prds/d04_glossary.md'),
          ),
        ),
      );
    });

    test('f06/us01/fr03/e13: a Spec map that is not UTF-8 reads as no Spec '
        'map', () async {
      final plan = await planWith({'docs/specs/INDEX.md': latin1});

      expect(
        plan.rewrites.map((r) => r.path),
        isNot(contains('docs/specs/INDEX.md')),
      );
      expect(plan.left, contains('specs/shared/s01_architecture.md'));
    });

    test('f06/us01/fr03: a .md file that cannot be read refuses '
        'output_not_writable naming it', () async {
      final root = await writeTree(acmeLegacy);
      final glossary = File('${root.path}/docs/prds/d04_glossary.md')
        ..writeAsStringSync('# Glossary\n');
      expect(Process.runSync('chmod', ['000', glossary.path]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['644', glossary.path]));

      expect(
        () => planLegacyRun(
          Directory(root.resolveSymbolicLinksSync()),
          templates: TemplateResolver(),
          homeDirectory: null,
        ),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having(
                (f) => f.message,
                'message',
                startsWith('cannot read prds/d04_glossary.md: '),
              ),
        ),
      );
    }, skip: unreadablePathSkipReason());
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

  test('f06/us01/fr04/e16: a path mention of a moved legacy file follows it, '
      'labelled as mentions', () async {
    const fr =
        'features/f01_login/us01_email_login/functional_requirements/'
        'fr01_validate_credentials.md';
    final plan = await _plan({
      ...acmeLegacy,
      'docs/prds/d04_glossary.md':
          '# Glossary\n\nSee `$fr:85` and\n$fr. Not `and/or` or ghost/$fr.\n',
    });

    final rewrite = _rewrite(plan, 'prds/d04_glossary.md');

    expect(rewrite.changes, ['2 mentions']);
    expect(
      rewrite.text,
      [
        '# Glossary\n\nSee `features/f01_login/us01_email_login/',
        'fr01_validate_credentials.md:85` and\n',
        'features/f01_login/us01_email_login/fr01_validate_credentials.md. ',
        'Not `and/or` or ghost/$fr.\n',
      ].join(),
    );
  });

  test('f06/us01/fr04/e16: one mention is labelled in the singular', () async {
    final plan = await _plan({
      ...acmeLegacy,
      'docs/prds/d04_glossary.md': [
        '# Glossary\n\nSee features/f01_login/us01_email_login/',
        'functional_requirements/fr01_validate_credentials.md:7.\n',
      ].join(),
    });

    expect(_rewrite(plan, 'prds/d04_glossary.md').changes, ['1 mention']);
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

  group('agent files', () {
    test('setup_migration/migrate_legacy_docs/write_project_files E13: a '
        'CLAUDE.md with no block gets the import block', () async {
      final plan = await _plan({...acmeLegacy, 'CLAUDE.md': '# Acme\n'});

      final agents = plan.agentFiles!;
      expect(agents.rootWrites.map((w) => w.path), [
        '.specstone/AGENT.md',
        'CLAUDE.md',
      ]);
      expect(agents.rootWrites.last.text, startsWith('# Acme\n'));
      expect(
        agents.rootWrites.last.text,
        contains('<!-- BEGIN specstone v$specstoneVersion -->'),
      );
      expect(
        plan.toText(),
        contains('  agent files: .specstone/AGENT.md, CLAUDE.md\n'),
      );
    });

    test('setup_migration/migrate_legacy_docs/write_project_files E13: a '
        'root with no instruction file gets AGENTS.md', () async {
      final plan = await _plan(acmeLegacy);

      expect(plan.agentFiles!.rootWrites.map((w) => w.path), [
        '.specstone/AGENT.md',
        'AGENTS.md',
      ]);
      expect(plan.agentFiles!.topWrites, isEmpty);
      expect(
        plan.toText(),
        contains('  agent files: .specstone/AGENT.md, AGENTS.md\n'),
      );
    });

    test('setup_migration/set_up_new_project/write_agent_files E08: a '
        'malformed block refuses before the plan returns', () async {
      final root = await writeTree({
        ...acmeLegacy,
        'AGENTS.md': '<!-- BEGIN specstone v1.2.0 -->\nbody\n',
      });

      expect(
        () => planLegacyRun(
          Directory(root.resolveSymbolicLinksSync()),
          templates: TemplateResolver(),
          homeDirectory: null,
        ),
        throwsA(
          isA<MigrateFault>().having(
            (e) => e.code,
            'code',
            MigrateFaultCode.agentBlockMalformed,
          ),
        ),
      );
    });

    test('setup_migration/migrate_legacy_docs/write_project_files E11, E13: '
        'a code root in another repository takes its files outside the '
        'commits', () async {
      final plan = await _linkedPlan({
        legacyFrPath: implementingDoc('Validate credentials', ['lib/a.dart']),
        'code/lib/a.dart': 'class A {}\n',
        'code/.git/HEAD': 'ref: refs/heads/main\n',
      });

      final agents = plan.agentFiles!;
      expect(agents.topWrites.map((w) => w.path), ['code/AGENTS.md']);
      expect(agents.agentFileRoots, ['code']);
      final config = _configCreate(plan).text;
      expect(config, contains('code_root: code\n'));
      expect(config, contains('agent_file_roots:\n  - code\n'));
      expect(
        plan.toText(),
        contains(
          '  agent files: .specstone/AGENT.md, AGENTS.md, code/AGENTS.md\n',
        ),
      );
    });

    test('an existing config keeps its keys and lists the new top', () async {
      final plan = await _linkedPlan({
        '.specstone/config.yaml':
            'packs:\n  prd-core: 0.0.1\ncode_root: code\n',
        'code/.git/HEAD': 'ref: refs/heads/main\n',
      });

      final rewrite = plan.rewrites.singleWhere(
        (r) => r.path == '.specstone/config.yaml',
      );
      expect(rewrite.text, contains('code_root: code\n'));
      expect(rewrite.text, endsWith('agent_file_roots:\n  - code\n'));
      expect(plan.agentFiles!.topWrites.map((w) => w.path), ['code/AGENTS.md']);
    });

    test(
      'an existing config that already lists the top lists it once',
      () async {
        final plan = await _linkedPlan({
          '.specstone/config.yaml':
              'packs:\n  prd-core: 0.0.1\n'
              'code_root: code\nagent_file_roots:\n  - code\n',
          'code/AGENTS.md':
              '# Stale\n\n<!-- BEGIN specstone v1.2.0 -->\nold\n'
              '<!-- END specstone -->\n',
          'code/.git/HEAD': 'ref: refs/heads/main\n',
        });

        expect(plan.agentFiles!.topWrites.map((w) => w.path), [
          'code/AGENTS.md',
        ]);
        expect(plan.agentFiles!.addedRoots, isEmpty);
        final rewrite = plan.rewrites.singleWhere(
          (r) => r.path == '.specstone/config.yaml',
        );
        expect(rewrite.text, endsWith('agent_file_roots:\n  - code\n'));
        expect('agent_file_roots'.allMatches(rewrite.text), hasLength(1));
        expect('- code\n'.allMatches(rewrite.text), hasLength(1));
        expect(
          plan.toText(),
          contains(
            '  agent files: .specstone/AGENT.md, AGENTS.md, '
            'code/AGENTS.md\n',
          ),
        );
      },
    );
  });

  group('code_root', () {
    test('writes code_root when the legacy paths resolve from the link '
        'folder', () async {
      final plan = await _linkedPlan({
        legacyFrPath: implementingDoc('Validate credentials', [
          'lib/a.dart',
          'lib/a.dart:A',
        ]),
        'code/lib/a.dart': 'class A {}\n',
      });

      final create = _configCreate(plan);
      expect(create.text, startsWith('packs:\n'));
      expect(create.text, endsWith('\ncode_root: code\n'));
      expect(create.note, endsWith('; code_root code'));
      expect(
        plan.toText(),
        matches(
          RegExp(
            r'\n  \.specstone/config\.yaml: prd-core \S+, software-tech \S+; '
            r'code_root code\n',
          ),
        ),
      );
    });

    test('keeps the default when the paths resolve from the root', () async {
      final plan = await _linkedPlan({
        legacyFrPath: implementingDoc('Validate credentials', [
          'code/lib/a.dart',
        ]),
        'code/lib/a.dart': 'class A {}\n',
      });

      final create = _configCreate(plan);
      expect(create.text, isNot(contains('code_root')));
      expect(create.note, isNot(contains('code_root')));
    });

    test('skips implements items that are not strings', () async {
      final plan = await _linkedPlan({
        legacyFrPath: implementingDoc('Validate credentials', [
          '42',
          '{a: b}',
          'lib/a.dart',
        ]),
        // Read as a path, the item 42 would tie the count.
        '42': '',
        'code/lib/a.dart': 'class A {}\n',
      });

      expect(_configCreate(plan).text, endsWith('\ncode_root: code\n'));
    });

    for (final linkName in [r'co\de', 'C:code']) {
      test(
        'keeps the default when the link folder path is no valid code_root: '
        '$linkName',
        () async {
          final tree = await writeTree(
            linkedAcme({
              legacyFrPath: implementingDoc('Validate credentials', [
                'lib/a.dart',
              ]),
            }),
          );
          // writeTree reads its keys as URIs, which turn `\` into `/`.
          File('${tree.path}/ws/$linkName/lib/a.dart')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('class A {}\n');

          final plan = _planFromLink(tree, linkName: linkName);

          expect(_configCreate(plan).text, isNot(contains('code_root')));
        },
        skip: Platform.isWindows
            ? r'a Windows folder name holds no \ or :'
            : false,
      );
    }

    test('keeps the default on a tie or no entries', () async {
      final tie = await _linkedPlan({
        legacyFrPath: implementingDoc('Validate credentials', [
          'lib/a.dart',
          'lib/',
        ]),
        _legacySpec: implementingDoc('Shared architecture', [
          'code/lib/b.dart',
        ]),
        'code/lib/a.dart': 'class A {}\n',
        'code/lib/b.dart': 'class B {}\n',
      });
      final none = await _linkedPlan({'code/lib/a.dart': 'class A {}\n'});

      for (final plan in [tie, none]) {
        expect(_configCreate(plan).text, isNot(contains('code_root')));
      }
    });

    test('an existing config keeps its code_root on rewrite', () async {
      final versions = shippedPackVersions();
      final kept = await _linkedPlan({
        '.specstone/config.yaml':
            'packs:\n  prd-core: 0.0.1\ncode_root: ../code\n',
      });
      final absent = await _linkedPlan({
        '.specstone/config.yaml': 'packs:\n  prd-core: 0.0.1\n',
        legacyFrPath: implementingDoc('Validate credentials', ['lib/a.dart']),
        'code/lib/a.dart': 'class A {}\n',
      });

      expect(
        kept.rewrites
            .singleWhere((r) => r.path == '.specstone/config.yaml')
            .text,
        'packs:\n  prd-core: ${versions['prd-core']}\n'
        '  software-tech: ${versions['software-tech']}\n'
        'code_root: ../code\n',
      );
      expect(
        absent.rewrites
            .singleWhere((r) => r.path == '.specstone/config.yaml')
            .text,
        isNot(contains('code_root')),
      );
    });
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
