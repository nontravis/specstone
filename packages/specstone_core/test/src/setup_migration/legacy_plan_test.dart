import 'dart:io';

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/rewrite_records.dart'
    show newRecordOf;
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/carried_packs.dart';
import 'package:specstone_core/src/setup_migration/legacy_plan.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/legacy_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/record_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

/// The `specstone migrate --dry-run` example of `api:setup_migration`, up to
/// the `left` block.
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
  prds/features/f01_login/FEATURE.md: title from Feature name, name, index tables removed, 2 links, 1 mention
  prds/features/f01_login/us01_email_login/USER_STORY.md: title, name
  prds/features/f01_login/us01_email_login/fr01_validate_credentials.md: title, name
  specs/f01_login/ARCHITECTURE.md: title, name, feature_id, Concerns, covers (1 path)
  number labels: 1 rewrites in 1 files; left: 0
  format layout: 1 docs
  stamps: 8 approval hashes, 0 fingerprints
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

MergedSet _carriedSet() => TemplateResolver().resolveCarried(
  packNames: carriedPacks,
  homeDirectory: null,
);

/// The merged type of the doc at [docPath] in the carried packs, or null.
MergedDocType? _typeOf(String docPath) {
  final set = _carriedSet();
  final match = DocTypeMatcher(set, targetNames: const []).match(docPath);
  return match is MatchedDocType ? match.docType : null;
}

/// A legacy tree whose features carry `ai<nn>` folder numbers and whose docs
/// cite each other by legacy ID and by number label.
const _citingLegacy = <String, String>{
  'docs/prds/d01_context.md': '# D-01 — Project context\n',
  'docs/prds/features/ai01_login/FEATURE.md': '''
# F-01 — Login

Built by ai01/us01/fr02 and `ai01/us01/fr01`; ai09/us01/fr01 names no FR.
The story is F-01 US-01 and the feature F-01.
''',
  'docs/prds/features/ai01_login/us01_email_login/USER_STORY.md':
      '# US-01 — Email login\n',
  'docs/prds/features/ai01_login/us01_email_login/functional_requirements/'
          'fr01_validate_credentials.md':
      '# FR-01 — Validate credentials\n\nAfter FR-02 and not FR-09.\n',
  'docs/prds/features/ai01_login/us01_email_login/functional_requirements/'
          'fr02_lock_account.md':
      '# FR-02 — Lock account\n',
};

const _legacySpec = 'docs/specs/shared/s01_architecture.md';

const _storyKeys = 'status: implemented\nimplements:\n  - lib/a.dart:A\n';

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

/// Plans the `ws/` folder of [tree] with no link folder.
RunPlan _planOf(Directory tree) => planLegacyRun(
  Directory('${tree.resolveSymbolicLinksSync()}${Platform.pathSeparator}ws'),
  templates: TemplateResolver(),
  homeDirectory: null,
);

Iterable<PlannedRewrite> _rewritesOf(RunPlan plan, String path) =>
    plan.rewrites.where((r) => r.path == path);

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
          r'^  \.specstone/config\.yaml: prd-core \S+, software-tech \S+; '
          r'code_root \. \(0 of 1 paths\)\n'
          r'  \.specstone/\.gitignore\n'
          r'  \.specstone/templates/gnfr\.yaml\n'
          r'  specs/TECH_STACK\.md \(draft\)\n'
          r'  agent files: 2 files\n'
          r'left in place for specstone check:\n'
          r'  specs/INDEX\.md\n'
          r'  specs/f01_login/DOMAIN\.md\n$',
        ),
      ),
    );
    expect(
      plan.toText(),
      endsWith(
        'left in place for specstone check:\n'
        '  specs/INDEX.md\n'
        '  specs/f01_login/DOMAIN.md\n',
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

  test('f06/us01/fr04/e11, rewrite_titles_keys_and_links E17: a markdown '
      'doc left in place gets the link rewrite only, its other lines '
      'byte-equal', () async {
    const glossary = '''
# Glossary

See [FR](features/f01_login/us01_email_login/functional_requirements/fr01_validate_credentials.md).

| Term    | Meaning       |
|---------|---------------|
| Session | Signed-in use |
''';
    final plan = await _plan({
      ...acmeLegacy,
      'docs/prds/d04_glossary.md': glossary,
    });

    final rewrite = _rewrite(plan, 'prds/d04_glossary.md');

    expect(rewrite.changes, ['1 link']);
    expect(rewrite.text, isNot(contains('functional_requirements')));
    expect(
      rewrite.text,
      glossary.replaceFirst(
        'functional_requirements/fr01_validate_credentials.md',
        'fr01_validate_credentials.md',
      ),
    );
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

  test('f06/us01/fr04/e16: a mention of a name Windows would trim is left '
      'as written, though a POSIX disk holds the file', () async {
    final plan = await _plan({
      ...acmeLegacy,
      legacyFrPath: '${acmeLegacy[legacyFrPath]}\nSee ../notes./a.md.\n',
      'docs/prds/features/f01_login/us01_email_login/notes./a.md': 'x\n',
    });

    final text = _rewrite(
      plan,
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
    ).text;

    expect(text, contains('See ../notes./a.md.\n'));
  }, skip: Platform.isWindows ? 'Windows cannot hold such a name' : null);

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

  test('f06/us01/fr04/e17, rewrite_titles_keys_and_links E17: a moved doc '
      'that becomes typed is written laid out, its text kept', () async {
    final plan = await _plan({
      ...acmeLegacy,
      'docs/prds/d03_non_functional.md': '''
---
name: Acme non-functional requirements
---

# D-03 — Project-wide non-functional requirements

## Performance

| ID     | Requirement           |
|--------|-----------------------|
| NFR-01 | Login answers in 1 s. |
''',
    });

    final rewrite = _rewrite(plan, 'prds/GNFR.md');

    expect(rewrite.changes.take(2), ['title', 'name']);
    expect(rewrite.text, contains('| ID | Requirement |\n|---|---|\n'));
    expect(rewrite.text, contains('| NFR-01 | Login answers in 1 s. |\n'));
  });

  test('f06/us01/fr04/e17, rewrite_titles_keys_and_links E17: a typed doc '
      'whose only change is its layout joins the shared line, a doc with '
      'rewrites keeps its own line', () async {
    final plan = await _plan(acmeLegacy);

    final domain = _rewrite(plan, 'specs/f01_login/DOMAIN.md');

    expect(domain.changes, isEmpty);
    expect(domain.text, contains('| Entity | Kind | Identity |\n'));
    final lines = plan.toText().split('\n');
    expect(lines, contains('  format layout: 1 docs'));
    expect(plan.lists.formatLayout, ['specs/f01_login/DOMAIN.md']);
    expect(lines.where((line) => line.contains('DOMAIN.md:')), isEmpty);
    expect(lines, contains('  prds/PROJECT.md: title, name, vision labels'));
  });

  test('f06/us01/fr04/e17, rewrite_titles_keys_and_links E17: a doc the '
      'format command refuses is not rewritten', () async {
    final plan = await _plan({
      ...acmeLegacy,
      'docs/specs/f01_login/DOMAIN.md': '''
---
name: Login domain
---

# Login domain

## Entities

| Entity  | Kind           | Identity |
|---------|----------------|----------|
| Session | Aggregate root | token    |

## Not in the template

Text.
''',
    });

    final domain = _rewrite(plan, 'specs/f01_login/DOMAIN.md');
    expect(
      domain.text.replaceFirst(RegExp(r'approved: "[0-9a-f]{12}"\n'), ''),
      contains('name: Login domain\n---\n\n# Login domain\n\n## Entities\n'),
    );
    expect(domain.text, contains('## Not in the template\n\nText.\n'));
    expect(domain.text, contains('| Session | Aggregate root | token    |'));
    expect(plan.toText(), isNot(contains('format layout:')));
    expect(
      plan.toText(),
      contains('stamps: 8 approval hashes, 0 fingerprints'),
    );
  });

  test('f06/us01/fr06/e01, write_first_fingerprints: the fingerprint hashes '
      'the Statement as laid out', () async {
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

| Input       | Rule      |
|-------------|-----------|
| Credentials | Must hold |
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
    expect(statement, contains('| Input | Rule |'));
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
    expect(
      plan.toText(),
      contains('  .specstone/config.yaml: pins; code_root . (0 of 1 paths)\n'),
    );
  });

  group('mentions line', () {
    test('a path mention in a code file of a moved doc prints one count line '
        'after the stamps line, and the file stays as it is', () async {
      const code = 'void f() {}\n// See prds/d01_context.md\n';
      final root = await writeTree({
        ...acmeLegacy,
        'docs/specs/TECH_STACK.md': '---\ncode:\n  - lib/\n---\n# Tech stack\n',
        'lib/a.dart': code,
      });

      final plan = planLegacyRun(
        Directory(root.resolveSymbolicLinksSync()),
        templates: TemplateResolver(),
        homeDirectory: null,
      );

      expect(
        plan.toText(),
        matches(
          RegExp(r'  stamps: [^\n]*\n  mentions: 1\ncommit 2, creates:\n'),
        ),
      );
      expect(plan.lists.mentions, [
        (path: 'lib/a.dart', line: 2, mention: 'prds/d01_context.md'),
      ]);
      expect(File('${root.path}/lib/a.dart').readAsStringSync(), code);
    });

    test(
      'a legacy tree with no code entry reads the whole code root',
      () async {
        final root = await writeTree({
          ...acmeLegacy,
          'lib/a.dart': 'void f() {}\n// See prds/d01_context.md\n',
        });

        final plan = planLegacyRun(
          Directory(root.resolveSymbolicLinksSync()),
          templates: TemplateResolver(),
          homeDirectory: null,
        );

        expect(plan.lists.mentions, [
          (path: 'lib/a.dart', line: 2, mention: 'prds/d01_context.md'),
        ]);
      },
    );

    test('a code file that names no moved doc adds no line', () async {
      final plan = await _plan({
        ...acmeLegacy,
        'docs/specs/TECH_STACK.md': '---\ncode:\n  - lib/\n---\n# Tech stack\n',
        'lib/a.dart': 'void f() {}\n// See prds/other.md\n',
      });

      expect(plan.toText(), isNot(contains('mentions:')));
      expect(plan.lists.mentions, isEmpty);
    });
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
      expect(plan.toText(), contains('  agent files: 2 files\n'));
      expect(plan.lists.agentFiles, ['.specstone/AGENT.md', 'CLAUDE.md']);
    });

    test('setup_migration/migrate_legacy_docs/write_project_files E13: a '
        'root with no instruction file gets AGENTS.md', () async {
      final plan = await _plan(acmeLegacy);

      expect(plan.agentFiles!.rootWrites.map((w) => w.path), [
        '.specstone/AGENT.md',
        'AGENTS.md',
      ]);
      expect(plan.agentFiles!.topWrites, isEmpty);
      expect(plan.toText(), contains('  agent files: 2 files\n'));
      expect(plan.lists.agentFiles, ['.specstone/AGENT.md', 'AGENTS.md']);
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
      expect(plan.toText(), contains('  agent files: 3 files\n'));
      expect(plan.lists.agentFiles, [
        '.specstone/AGENT.md',
        'AGENTS.md',
        'code/AGENTS.md',
      ]);
    });

    test('setup_migration/set_up_new_project/write_agent_files E35: a kept '
        'targets: config takes the files at each target repository top, and '
        'lists both', () async {
      final plan = await _plan({
        ...acmeLegacy,
        '.specstone/config.yaml':
            'packs:\n  prd-core: 0.0.1\ntargets:\n  flutter:\n'
            '    code_root: flutter_ws\n  jaspr:\n    code_root: jaspr_ws\n',
        'flutter_ws/.git/HEAD': 'ref: refs/heads/main\n',
        'jaspr_ws/.git/HEAD': 'ref: refs/heads/main\n',
      });

      final agents = plan.agentFiles!;
      expect(agents.topWrites.map((w) => w.path), [
        'flutter_ws/AGENTS.md',
        'jaspr_ws/AGENTS.md',
      ]);
      expect(agents.agentFileRoots, ['flutter_ws', 'jaspr_ws']);
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
        expect(plan.toText(), contains('  agent files: 3 files\n'));
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
      expect(create.note, endsWith('; code_root code (2 of 3 paths)'));
      expect(
        plan.toText(),
        matches(
          RegExp(
            r'\n  \.specstone/config\.yaml: prd-core \S+, software-tech \S+; '
            r'code_root code \(2 of 3 paths\)\n',
          ),
        ),
      );
    });

    test('g8-r9: writes code_root for a child folder that is its own '
        'repository', () async {
      final plan = await _plan({
        legacyFrPath: implementingDoc('Validate credentials', [
          'lib/a.dart',
          'lib/b.dart',
        ]),
        'code/.git/HEAD': '',
        'code/lib/a.dart': 'class A {}\n',
        'code/lib/b.dart': 'class B {}\n',
      });

      final create = _configCreate(plan);
      expect(create.text, contains('\ncode_root: code\n'));
      expect(create.note, endsWith('; code_root code (2 of 2 paths)'));
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
      expect(create.note, endsWith('; code_root . (1 of 2 paths)'));
    });

    test('skips implements items that are not strings', () async {
      final plan = await _linkedPlan({
        _legacySpec: implementingDoc('Shared architecture', [
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

    test(
      'a tie goes to the deeper folder; no entry keeps the default',
      () async {
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

        expect(_configCreate(tie).text, endsWith('\ncode_root: code\n'));
        expect(
          _configCreate(tie).note,
          endsWith('; code_root code (1 of 4 paths)'),
        );
        expect(_configCreate(none).text, isNot(contains('code_root')));
        expect(
          _configCreate(none).note,
          endsWith('; code_root . (0 of 1 paths)'),
        );
      },
    );

    test('f06/us01/fr05/e12: no cited entry leaves the config line with no '
        'code_root part', () async {
      final plan = await _plan(_citingLegacy);

      expect(_configCreate(plan).text, isNot(contains('code_root')));
      expect(_configCreate(plan).note, isNot(contains('code_root')));
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
        endsWith('\ncode_root: code\n'),
      );
    });

    test('f06/us01/fr05/e11: the create line names the count of the folder '
        'above the root', () async {
      final tree = await writeTree({
        ...linkedAcme({
          legacyFrPath: implementingDoc('Validate credentials', [
            for (var i = 1; i <= 39; i++) 'lib/f$i.dart',
          ]),
        }),
        '.git/HEAD': '',
        for (var i = 1; i <= 39; i++) 'lib/f$i.dart': '',
      });

      final plan = _planOf(tree);

      final create = _configCreate(plan);
      expect(create.text, contains('\ncode_root: ..\n'));
      expect(create.note, endsWith('; code_root .. (39 of 40 paths)'));
    });

    test('f06/us01/fr05/e10: a config with no code_root key gains the key '
        'in its rewrite, and the line names it', () async {
      final tree = await writeTree({
        ...linkedAcme({
          '.specstone/config.yaml': 'packs:\n  prd-core: 0.0.1\n',
          legacyFrPath: implementingDoc('Validate credentials', ['lib/a.dart']),
        }),
        '.git/HEAD': '',
        'lib/a.dart': 'class A {}\n',
      });

      final plan = _planOf(tree);

      final rewrite = plan.rewrites.singleWhere(
        (r) => r.path == '.specstone/config.yaml',
      );
      expect(rewrite.text, contains('\ncode_root: ..\n'));
      expect(
        plan.rewriteLines,
        contains('.specstone/config.yaml: pins; code_root .. (1 of 2 paths)'),
      );
    });

    test('f06/us01/fr05/e10: a config with a code_root key keeps it and its '
        'line has no code_root part', () async {
      final tree = await writeTree({
        ...linkedAcme({
          '.specstone/config.yaml':
              'packs:\n  prd-core: 0.0.1\ncode_root: ../code\n',
          legacyFrPath: implementingDoc('Validate credentials', ['lib/a.dart']),
        }),
        '.git/HEAD': '',
        'lib/a.dart': 'class A {}\n',
      });

      final plan = _planOf(tree);

      final rewrite = plan.rewrites.singleWhere(
        (r) => r.path == '.specstone/config.yaml',
      );
      expect(rewrite.text, contains('\ncode_root: ../code\n'));
      expect(plan.rewriteLines, contains('.specstone/config.yaml: pins'));
    });

    for (final (:label, :config) in [
      (
        label: 'code_root: .',
        config: 'packs:\n  prd-core: 0.0.1\ncode_root: .\n',
      ),
      (
        label: 'code_root: with no value',
        config: 'packs:\n  prd-core: 0.0.1\ncode_root:\n',
      ),
    ]) {
      test('f06/us01/fr05/e10: a config with $label keeps the key, infers '
          'none, and its line has no code_root part', () async {
        final plan = await _linkedPlan({
          '.specstone/config.yaml': config,
          legacyFrPath: implementingDoc('Validate credentials', ['lib/a.dart']),
          'code/lib/a.dart': 'class A {}\n',
        });

        final rewrite = plan.rewrites.singleWhere(
          (r) => r.path == '.specstone/config.yaml',
        );
        expect(rewrite.text, contains('\ncode_root: .\n'));
        expect(plan.rewriteLines, contains('.specstone/config.yaml: pins'));
      });
    }

    test('f06/us01/fr05/e10: a config whose rewrite text stays unchanged is '
        'not written and has no plan line', () async {
      final versions = shippedPackVersions();
      final pins =
          'packs:\n  prd-core: ${versions['prd-core']}\n'
          '  software-tech: ${versions['software-tech']}\n';
      final keyed = await _plan({
        ...acmeLegacy,
        '.specstone/config.yaml': '${pins}code_root: .\n',
      });
      final inferred = await _plan({
        ...acmeLegacy,
        '.specstone/config.yaml': pins,
      });

      for (final plan in [keyed, inferred]) {
        expect(_rewritesOf(plan, '.specstone/config.yaml'), isEmpty);
        expect(plan.toText(), isNot(contains('.specstone/config.yaml:')));
      }
    });

    test('f06/us01/fr05/e11: a topic applies_to entry is a cited path of the '
        'plan', () async {
      final plan = await _linkedPlan({
        'docs/specs/architecture/caching.md': '---\nname: Caching\napplies_to:\n  - lib/a.dart\n---\n\n# Caching\n',
        'code/lib/a.dart': 'class A {}\n',
      });

      final create = _configCreate(plan);
      expect(create.text, endsWith('\ncode_root: code\n'));
      expect(create.note, endsWith('; code_root code (1 of 2 paths)'));
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

  group(
    'setup_migration/migrate_legacy_docs/rewrite_titles_keys_and_links',
    () {
      const featurePath = 'prds/features/f01_login/FEATURE.md';
      const frPath =
          'prds/features/f01_login/us01_email_login/'
          'fr01_validate_credentials.md';

      test('E19: a link to a heading whose label became a name follows the '
          "heading's new slug", () async {
        final plan = await _plan({
          ..._citingLegacy,
          'docs/prds/features/ai01_login/us01_email_login/USER_STORY.md':
              '# US-01 — Email login\n\n### Scenario 2 — FR-02 lockout\n',
          'docs/prds/features/ai01_login/us01_email_login/functional_requirements/'
                  'fr01_validate_credentials.md':
              '# FR-01 — Validate credentials\n\n'
              'See [lockout](../USER_STORY.md#scenario-2--fr-02-lockout).\n',
        });

        final story = _rewrite(
          plan,
          'prds/features/f01_login/us01_email_login/USER_STORY.md',
        ).text;
        final fr = _rewrite(plan, frPath).text;

        expect(story, contains('`login/email_login/lock_account` lockout'));
        expect(fr, isNot(contains('#scenario-2--fr-02-lockout')));
        expect(
          fr,
          contains(
            '(USER_STORY.md#scenario-2--loginemail_loginlock_account-lockout)',
          ),
        );
      });

      test(
        'E18: a legacy ID the move list maps to one FR becomes its name, '
        'one in a code span stays uncounted, another is kept and listed',
        () async {
          final plan = await _plan(_citingLegacy);

          final text = _rewrite(plan, featurePath).text;

          expect(
            text,
            contains(
              'Built by `login/email_login/lock_account` and '
              '`ai01/us01/fr01`; ai09/us01/fr01 names',
            ),
          );
          expect(
            plan.lists.numberLabelsLeft,
            contains('prds/features/f01_login/FEATURE.md:7 ai09/us01/fr01'),
          );
          expect(
            plan.toText(),
            contains(
              RegExp(
                r'^  number labels: \d+ rewrites in \d+ files; '
                r'left: [1-9]\d*$',
                multiLine: true,
              ),
            ),
          );
        },
      );

      test('E19: a full label and a feature label name their doc; a partial '
          "label reads against the citing doc's story", () async {
        final plan = await _plan(_citingLegacy);

        expect(
          _rewrite(plan, featurePath).text,
          contains(
            'The story is `login/email_login` and the feature '
            '`feature:login`.',
          ),
        );
        expect(
          _rewrite(plan, frPath).text,
          contains('After `login/email_login/lock_account` and not FR-09.'),
        );
        expect(plan.lists.numberLabelsLeft, contains('$frPath:7 FR-09'));
      });

      test(
        'E19: the plan names each doc a label became a name in, as the '
        'upgrade plan does, and an untyped one is no layout rewrite',
        () async {
          final plan = await _plan({
            ..._citingLegacy,
            'docs/prds/d04_glossary.md': 'See F-01.\n',
          });

          final lines = plan.toText().split('\n');

          expect(
            lines.singleWhere((l) => l.startsWith('  number labels: ')),
            matches(
              RegExp(
                r'^  number labels: \d+ rewrites in \d+ files; left: \d+$',
              ),
            ),
          );
          expect(plan.lists.numberLabelsRewritten.take(2), [
            'prds/d04_glossary.md',
            'prds/features/f01_login/FEATURE.md',
          ]);
          expect(lines.any((l) => l.contains('format layout:')), isFalse);
          expect(
            _rewrite(plan, 'prds/d04_glossary.md').text,
            'See `feature:login`.\n',
          );
        },
      );

      test('E19: a tree with no label to keep prints a left count of 0 and '
          'lists none', () async {
        final plan = await _plan(acmeLegacy);

        expect(plan.toText(), contains('; left: 0\n'));
        expect(plan.lists.numberLabelsLeft, isEmpty);
      });
    },
  );

  group('setup_migration/migrate_legacy_docs/show_plan_and_apply_on_yes', () {
    test('E07: each typed doc the run leaves carries the hash of its final '
        'text and no draft key; a created draft keeps draft: true', () async {
      final plan = await _plan(acmeLegacy);

      final typed = [
        for (final rewrite in plan.rewrites)
          if (rewrite.path.startsWith('docs/'))
            (
              path: rewrite.path,
              text: rewrite.text,
              type: _typeOf(rewrite.path.substring('docs/'.length)),
            ),
      ].where((doc) => doc.type != null).toList();

      expect(typed, isNotEmpty);
      for (final (:path, :text, :type) in typed) {
        expect(text, contains('approved: "'), reason: path);
        expect(text, isNot(contains('draft:')), reason: path);
        expect(withApprovalHash(text, type), text, reason: path);
      }
      final tech = plan.creates.singleWhere(
        (c) => c.path == 'docs/specs/TECH_STACK.md',
      );
      expect(tech.text, startsWith('---\ndraft: true\n'));
    });

    test('E07: the stamps line counts only the docs whose approved value '
        'the run changes', () async {
      final first = await _plan(acmeLegacy);
      final stamped = _rewrite(first, 'specs/f01_login/DOMAIN.md').text;

      final second = await _plan({
        ...acmeLegacy,
        'docs/specs/f01_login/DOMAIN.md': stamped,
      });

      expect(
        second.rewrites.map((r) => r.path),
        isNot(contains('docs/specs/f01_login/DOMAIN.md')),
      );
      expect(second.toText(), contains('stamps: 7 approval hashes'));
    });

    test('E07: the stamps line counts a typed doc whose frontmatter is no '
        'valid YAML, since the run writes its stamp', () async {
      final plan = await _plan({
        ...acmeLegacy,
        'docs/specs/f01_login/DOMAIN.md':
            '---\nname: "Login\n---\n\n# Login domain\n',
      });

      expect(
        _rewrite(plan, 'specs/f01_login/DOMAIN.md').text,
        contains('approved: "'),
      );
      expect(plan.toText(), contains('stamps: 8 approval hashes'));
    });

    test('E07: a typed doc the run neither moves nor edits is stamped and '
        'written, and an untyped doc stays as it is', () async {
      final plan = await _plan(acmeLegacy);

      final domain = _rewrite(plan, 'specs/f01_login/DOMAIN.md');

      expect(domain.text, contains('approved: "'));
      expect(plan.toText(), contains('stamps: 8 approval hashes'));
      expect(
        plan.rewrites.map((r) => r.path),
        isNot(contains('docs/specs/INDEX.md')),
      );
    });

    test(
      'E07: the stamp comes after the confirmed entries the run writes',
      () async {
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

        final api = _rewrite(plan, 'specs/f01_login/API.md');
        expect(plan.toText(), contains(', 1 fingerprints\n'));
        expect(api.text, contains('confirmed:\n  - email_login/'));
        expect(
          withApprovalHash(api.text, _typeOf('specs/f01_login/API.md')),
          api.text,
        );
      },
    );
  });
  group('setup_migration/migrate_legacy_docs/write_project_files E14, E15', () {
    const storyPath = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
    const frPath =
        'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
    const recordPath = 'specs/f01_login/IMPLEMENTATION.md';
    const config = 'packs:\n  prd-core: 0.0.1\n';
    const twin =
        '${config}targets:\n  flutter:\n    code_root: flutter_ws\n'
        '  jaspr:\n    code_root: jaspr_ws\n';

    String story(String keys) =>
        '---\nname: Email login\n$keys---\n\n# US-01 — Email login\n';
    String fr(String keys) =>
        '---\nname: Validate credentials\n$keys---\n\n# FR-01 — Validate '
        'credentials\n\n## Statement\n\nThe system checks the credentials.\n';
    Map<String, String> recorded({String storyKeys = _storyKeys}) => {
      ...acmeLegacy,
      'docs/$storyPath': story(storyKeys),
      legacyFrPath: fr('status: planned\n'),
    };
    List<String> keysOf(PlannedRewrite rewrite) => [
      for (final block in Doc.parse(rewrite.text).frontmatter ?? <KeyBlock>[])
        block.name,
    ];

    test('E14: a story and an FR with a status and code paths move into the '
        "feature's draft record, byte for byte as the one record builder "
        'writes it', () async {
      final plan = await _plan(recorded());

      final record = plan.creates.singleWhere(
        (c) => c.path == 'docs/$recordPath',
      );
      final set = _carriedSet();
      final expected = newRecordOf(
        set,
        set.recordDocType!,
        featureType: set.lookup('feature')!,
        featureDocPath: 'prds/features/f01_login/FEATURE.md',
        featureName: 'login',
        lines: (
          statuses: [
            'email_login:implemented',
            'email_login/validate_credentials:planned',
          ],
          code: ['email_login:lib/a.dart:A'],
          tests: const [],
        ),
      )!;
      expect(record.text, expected.text);
      expect(record.text, contains('draft: true\n'));
      expect(record.note, ' (draft)');
      expect(plan.toText(), contains('  $recordPath (draft)\n'));
    });

    test('E14: the story and the FR lose both keys, and the run still '
        'approves them', () async {
      final plan = await _plan(recorded());

      final storyRewrite = _rewrite(plan, storyPath);
      final frRewrite = _rewrite(plan, frPath);

      for (final rewrite in [storyRewrite, frRewrite]) {
        expect(keysOf(rewrite), isNot(contains('status')));
        expect(keysOf(rewrite), isNot(contains('implements')));
        expect(keysOf(rewrite), contains('approved'));
        expect(keysOf(rewrite), isNot(contains('draft')));
      }
      expect(storyRewrite.changes, contains('status, implements to record'));
      expect(frRewrite.changes, contains('status to record'));
    });

    test(
      'E14: a tree with no status and no code path writes no record',
      () async {
        final plan = await _plan({...acmeLegacy, legacyFrPath: fr('')});

        expect(_createdPaths(plan), isNot(contains('docs/$recordPath')));
      },
    );

    test(
      'E14: a value with no place refuses the run with value_unplaced',
      () async {
        await expectLater(
          _plan(recorded(storyKeys: 'status: wip\n')),
          throwsA(
            isA<MigrateFault>()
                .having((f) => f.code, 'code', MigrateFaultCode.valueUnplaced)
                .having((f) => f.file, 'file', storyPath)
                .having((f) => f.key, 'key', 'status'),
          ),
        );
      },
    );

    test('E14: a file at the record path the run cannot read as a record '
        'refuses with value_unplaced instead of losing the values', () async {
      final root = await writeTree(recorded());
      File('${root.path}/docs/$recordPath')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([0xff, 0xfe, 0x00]);

      expect(
        () => planLegacyRun(
          Directory(root.resolveSymbolicLinksSync()),
          templates: TemplateResolver(),
          homeDirectory: null,
        ),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.valueUnplaced)
              .having((f) => f.file, 'file', storyPath)
              .having((f) => f.message, 'message', contains(recordPath)),
        ),
      );
    });

    test('E14: a record the tree already holds gains the entry as an edit, '
        'never a second create', () async {
      final plan = await _plan({
        ...recorded(),
        'docs/$recordPath': recordText(statuses: ['email_login:implemented']),
      });

      expect(_createdPaths(plan), isNot(contains('docs/$recordPath')));
      final record = _rewrite(plan, recordPath);
      expect(
        record.text,
        contains("  - 'email_login/validate_credentials:planned'\n"),
      );
    });

    test('E14, E03: a grouped tree writes the record beside its feature in '
        'the group folder, by the implementation path override', () async {
      final plan = await _plan({
        'docs/prds/d01_context.md': '# D-01 — Project context\n',
        'docs/prds/features/ai_module/ai05_chat/FEATURE.md': '# F-05 — Chat\n',
        'docs/prds/features/ai_module/ai05_chat/us01_talk/USER_STORY.md': story(
          'status: planned\n',
        ),
      });

      expect(
        _createdPaths(plan),
        containsAll([
          '.specstone/templates/implementation.yaml',
          'docs/specs/ai_module/f05_chat/IMPLEMENTATION.md',
        ]),
      );
    });

    test('E15: a config that holds targets: keeps the map, infers no '
        'code_root, and the first target takes the record', () async {
      final plan = await _plan({
        ...recorded(),
        '.specstone/config.yaml':
            '${config}targets:\n  flutter:\n    code_root: flutter_ws\n'
            '  jaspr:\n    code_root: jaspr_ws\n',
      });

      expect(
        _rewritesOf(plan, '.specstone/config.yaml').single.text,
        '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: '
        'flutter_ws\n  jaspr:\n    code_root: jaspr_ws\n',
      );
      expect(plan.rewriteLines, contains('.specstone/config.yaml: pins'));
      expect(
        _createdPaths(plan),
        contains('docs/specs/flutter/f01_login/IMPLEMENTATION.md'),
      );
      expect(_createdPaths(plan), isNot(contains('docs/$recordPath')));
    });

    test('E15: with two targets the spec docs the run places sit in the '
        "first target's folder, typed and approved, and a missing "
        'per-target singular doc is created there', () async {
      final plan = await _plan({...recorded(), '.specstone/config.yaml': twin});

      final matcher = DocTypeMatcher(
        _carriedSet(),
        targetNames: const ['flutter', 'jaspr'],
      );
      final moved = {for (final m in plan.moves) m.from: m.to};
      expect(
        moved['specs/api/auth/s01_architecture.md'],
        'specs/flutter/f01_login/ARCHITECTURE.md',
      );
      expect(
        moved['specs/f01_login/DOMAIN.md'],
        'specs/flutter/f01_login/DOMAIN.md',
      );
      expect(plan.left, isNot(contains('specs/f01_login/DOMAIN.md')));
      for (final path in [
        'specs/flutter/f01_login/ARCHITECTURE.md',
        'specs/flutter/f01_login/DOMAIN.md',
      ]) {
        expect(matcher.match(path), isA<MatchedDocType>(), reason: path);
        expect(_rewrite(plan, path).text, contains('approved: "'));
      }
      expect(_createdPaths(plan), contains('docs/specs/flutter/TECH_STACK.md'));
      expect(_createdPaths(plan), isNot(contains('docs/specs/TECH_STACK.md')));
    });

    test('E15: with two targets a doc that already holds the first target '
        'path refuses legacy_collision, and nothing is lost', () async {
      await expectLater(
        _plan({
          ...recorded(),
          '.specstone/config.yaml': twin,
          'docs/specs/flutter/f01_login/ARCHITECTURE.md': '# Held\n',
        }),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.legacyCollision,
          ),
        ),
      );
    });

    test('E15: with two targets the first fingerprints still find the FRs of '
        'an API doc placed in the first target folder', () async {
      final plan = await _plan(
        {
          ...recorded(),
          '.specstone/config.yaml': twin,
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

      final api = _rewrite(plan, 'specs/flutter/f01_login/API.md');

      expect(api.text, contains('confirmed:\n  - email_login/'));
    });

    test('E15: one named target keeps its map and its record stays in the '
        'spec folder', () async {
      final plan = await _plan({
        ...recorded(),
        '.specstone/config.yaml':
            '${config}targets:\n  flutter:\n    code_root: flutter_ws\n',
      });

      expect(
        _rewritesOf(plan, '.specstone/config.yaml').single.text,
        '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: '
        'flutter_ws\n',
      );
      expect(_createdPaths(plan), contains('docs/$recordPath'));
    });
  });
}
