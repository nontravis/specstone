// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/merged_field.dart'
    show FieldType;
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/yaml_key_line.dart';

/// The four per-feature spec doc types the one-file line reaches.
const _perFeatureIds = ['api', 'architecture', 'integration', 'security'];

/// The three project spec doc types, in code point order.
const _projectIds = ['project_api', 'project_architecture', 'project_security'];

/// Each doc type of the Output table: its path, its parent, and whether it
/// sets the per-target key.
const _outputRows = <String, List<Object?>>{
  'tech_stack': ['specs/TECH_STACK.md', null, true],
  'architecture': ['specs/f{nn}_{slug}/ARCHITECTURE.md', 'feature', true],
  'api': ['specs/f{nn}_{slug}/API.md', 'feature', true],
  'integration': ['specs/f{nn}_{slug}/INTEGRATION.md', 'feature', true],
  'security': ['specs/f{nn}_{slug}/SECURITY.md', 'feature', true],
  'decision': ['specs/decisions/d{nn}_{slug}.md', null, false],
  'implementation': [
    '.specstone/records/f{nn}_{slug}/IMPLEMENTATION.md',
    'feature',
    true,
  ],
  'project_architecture': ['specs/ARCHITECTURE.md', null, true],
  'project_api': ['specs/API.md', null, true],
  'project_security': ['specs/SECURITY.md', null, true],
};

/// The shared lines `software-tech` ships, by id, in file order.
const _sharedLines = <String, String>{
  'cite_spec_docs':
      "Link to the item of a project or ancestor-feature spec doc's rule; "
      'never restate it.',
  'no_status':
      "Never write `status:`; only a target's `implementation` record says "
      'if its code exists.',
  'project_rules_only':
      'Hold only rules every feature uses; write a rule two or more features '
      'share as a `project_architecture` concept naming them, and any other '
      'rule in a per-feature spec doc.',
  'one_file_per_feature_folder':
      'Keep one file per doc type per feature spec folder.',
  'one_file_per_spec_folder': 'Keep one file per doc type in each spec folder.',
  'overrides_line':
      'Under an item departing from a rule above, write '
      '`Overrides: [<ID>](<doc>#<section>) — <how it differs>, because '
      '<why>` and record its `overrides` entry.',
  'overrides_line_table':
      'Under an item departing from a rule above, or under its '
      'table for a table row, write '
      '`Overrides: [<ID>](<doc>#<section>) — <how it differs>, because '
      '<why>`, naming the row in the how-clause, and record its `overrides` '
      'entry.',
  'wire_fact_home':
      'A wire-contract fact lives in the `api` operation that traces the FR; '
      'the FR keeps its product words.',
  'mechanism_home':
      "A lock, retry, or parser mechanism lives in the feature's "
      '`architecture` doc, never in the FR.',
};

/// The doc types each shared line names.
const _lineReach = <String, List<String>>{
  'cite_spec_docs': softwareTechIds,
  'no_status': softwareTechIds,
  'project_rules_only': _projectIds,
  'one_file_per_feature_folder': _perFeatureIds,
  'one_file_per_spec_folder': _projectIds,
  'overrides_line': ['api', 'integration'],
  'overrides_line_table': ['architecture', 'security'],
  'wire_fact_home': ['fr'],
  'mechanism_home': ['fr'],
};

/// The `leftover_homes:` entries in the order of the Leftover homes table:
/// the doc types, the section id or the path, and the `to` types of each.
const _leftoverEntries = <(List<String>, String?, String?, List<String>)>[
  (['architecture', 'project_architecture'], 'value_objects', null, ['fr']),
  (
    ['architecture', 'project_architecture'],
    'invariants',
    null,
    ['user_story', 'fr'],
  ),
  (['architecture', 'project_architecture'], 'known_limits', null, ['feature']),
  (
    ['architecture', 'project_architecture'],
    'lifecycle',
    null,
    ['fr', 'architecture'],
  ),
  (
    ['architecture', 'project_architecture'],
    'commands_and_events',
    null,
    ['api', 'integration'],
  ),
  (['architecture', 'project_architecture'], 'terms', null, ['glossary']),
  (
    ['security', 'project_security'],
    'roles',
    null,
    ['user_story', 'fr', 'gnfr'],
  ),
  (
    ['security', 'project_security'],
    'resource_matrix',
    null,
    ['user_story', 'fr', 'gnfr'],
  ),
  (
    ['security', 'project_security'],
    'conditions',
    null,
    ['user_story', 'fr', 'gnfr'],
  ),
  (
    ['security', 'project_security'],
    'field_rules',
    null,
    ['user_story', 'fr', 'gnfr'],
  ),
  (
    ['security', 'project_security'],
    'authentication_and_sessions',
    null,
    ['decision', 'gnfr', 'nf'],
  ),
  (['security', 'project_security'], 'scopes', null, ['api']),
  (
    ['architecture', 'project_architecture'],
    'component_details',
    null,
    ['architecture', 'decision'],
  ),
  (
    ['architecture', 'project_architecture'],
    'interaction',
    null,
    ['architecture', 'fr', 'decision'],
  ),
  (['api', 'project_api'], 'fallback', null, ['fr']),
  (['api'], 'error_envelope', null, ['project_api', 'api']),
  (['api'], 'retry_policy', null, ['project_api', 'api']),
  (['project_architecture'], 'translation', null, ['integration', 'api']),
  (['project_architecture'], 'events', null, ['integration', 'api']),
  (
    <String>[],
    null,
    'specs/topics/{slug}.md',
    ['project_architecture', 'user_story', 'fr'],
  ),
  (
    <String>[],
    null,
    'specs/INDEX.md',
    ['implementation', 'tech_stack', 'api', 'project_architecture'],
  ),
  (['project'], 'tech_stack', null, ['tech_stack']),
  (['project'], 'naming_canonicalization', null, ['tech_stack']),
];

/// The doc types each shared field names, in file order.
const _fieldReach = <String, List<String>>{
  'overrides': _perFeatureIds,
  'tasks': [
    'api',
    'architecture',
    'decision',
    'integration',
    'security',
    'tech_stack',
  ],
};

/// The merged field ids of each doc type.
const _fieldIds = <String, List<String>>{
  'api': [..._builtIns, 'confirmed', 'overrides', 'tasks'],
  'architecture': [..._builtIns, 'overrides', 'tasks'],
  'decision': [..._builtIns, 'superseded_by', 'tasks'],
  'integration': [..._builtIns, 'overrides', 'tasks'],
  'security': [..._builtIns, 'overrides', 'tasks'],
  'project_api': [..._builtIns, 'tasks'],
  'project_architecture': [..._builtIns, 'tasks', 'covers'],
  'project_security': [..._builtIns, 'tasks'],
  'tech_stack': [..._builtIns, 'code', 'tasks'],
};

const _builtIns = [
  'slug',
  'status',
  'draft',
  'approved',
  'reference',
  'retrim',
  'retired_ids',
];

/// The file rule a doc type no shared one-file line reaches keeps on a line of
/// its own, in place of a line target.
const _fileRuleLines = <String, String>{
  'tech_stack': 'Keep one fact per table cell and write checkable rows.',
};

/// The item shape line of each doc type whose sentence cap sits in lint.
const _itemShapeLines = <String, String>{
  'architecture': 'Write one rule per ID: one Components row per component.',
  'project_api': 'Write one rule per ID: one bullet per convention.',
  'project_architecture':
      'Write one rule per ID: one Components row per component.',
  'tech_stack': 'Write one rule per ID: one Stack row per slot.',
};

void main() {
  group('software-tech manifest', () {
    test('software-tech ships at 1.25.0 and extends prd-core', () {
      final bytes = shippedPackFiles['software-tech/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/software-tech/pack.yaml',
      );
      expect(manifest.name, 'software-tech');
      expect(manifest.version.toString(), '1.25.0');
      expect(manifest.extendsPack, 'prd-core');
    });

    test('the 1.23.0 entry holds one relink_merged_docs step', () {
      final entry = _softwareTechManifest().migrations.singleWhere(
        (m) => m.from.toString() == '1.23.0',
      );

      expect(entry.steps.single, isA<RelinkMergedDocs>());
    });

    test('the 1.20.0 entry moves architecture covers into the record, folds '
        'five doc types, drops concerns, then drops topic, in order', () {
      final entry = _softwareTechManifest().migrations.singleWhere(
        (m) => m.from.toString() == '1.20.0',
      );

      expect(entry.steps.map((s) => s.kind), [
        'move_to_record',
        'merge_doc',
        'merge_doc',
        'merge_doc',
        'merge_doc',
        'merge_doc',
        'drop_section',
        'drop_doc_type',
      ]);
      final move = entry.steps[0] as MoveToRecord;
      expect(move.docTypes, ['architecture']);
      expect(move.fields, ['covers']);
      expect(move.to, 'implementation');
      const data = 'entities Entities -> data, data_touch Data touch -> data';
      const authSections =
          'enforcement Enforcement -> enforcement, audit Audit -> audit';
      const integrationFrom =
          'project_integration specs/INTEGRATION.md -> project_architecture:';
      const integration =
          'external_systems External systems -> external_systems, '
          'contract_per_system Contract per system -> contract_per_system';
      String moves(MergeDoc step) => [
        for (final m in step.sections)
          '${m.fromId} ${m.fromHeader} -> ${m.toId}',
      ].join(', ');
      expect(
        [
          for (final step in entry.steps.whereType<MergeDoc>())
            '${step.fromId} ${step.fromPath} -> ${step.toId}: ${moves(step)}',
        ],
        [
          'domain specs/f{nn}_{slug}/DOMAIN.md -> architecture: $data',
          'project_domain specs/DOMAIN.md -> project_architecture: $data',
          '$integrationFrom $integration',
          'auth specs/f{nn}_{slug}/AUTH.md -> security: $authSections',
          'project_auth specs/AUTH.md -> project_security: $authSections',
        ],
      );
      final drop = entry.steps[6] as DropSection;
      expect(drop.docTypes, ['architecture', 'project_architecture']);
      expect((drop.sectionId, drop.sectionHeader), ('concerns', 'Concerns'));
      final topic = entry.steps[7] as DropDocType;
      expect((topic.id, topic.path), ('topic', 'specs/topics/{slug}.md'));
    });

    test('the 1.13.0 entry holds one drop_default_lines step for the '
        'domain doc types', () {
      final manifest = PackManifest.parse(
        utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
        file: 'packs/software-tech/pack.yaml',
      );

      final entry = manifest.migrations.singleWhere(
        (m) => m.from.toString() == '1.13.0',
      );

      expect(entry.steps, hasLength(1));
      final step = entry.steps.single as DropDefaultLines;
      expect(step.docTypes, ['domain', 'project_domain']);
    });

    test('software-tech ships its shared lines in table order with their '
        'reach', () {
      final lines = _softwareTechManifest().shared.lines;
      expect({for (final l in lines) l.id: l.text}, _sharedLines);
      expect(lines.map((l) => l.id), _sharedLines.keys);
      expect({for (final l in lines) l.id: l.forDocTypes}, _lineReach);
      expect(lines.where((l) => l.disabled), isEmpty);
    });

    test('software-tech declares the leftover_homes entries of its table in table order', () {
      final entries = _softwareTechManifest().leftoverHomes;

      String show(
        List<String> docTypes,
        String? id,
        String? path,
        List<String> to,
      ) => '${docTypes.join(',')} | ${id ?? path} | ${to.join(',')}';
      expect(
        [for (final e in entries) show(e.docTypes, e.sectionId, e.path, e.to)],
        [for (final (d, i, p, t) in _leftoverEntries) show(d, i, p, t)],
      );
      expect(entries.every((e) => e.home.isNotEmpty), isTrue);
    });

    test(
      'every software-tech leftover entry resolves against the merged set',
      () async {
        final set = await resolveSoftwareTech();

        expect(set.leftoverHomes, hasLength(_leftoverEntries.length));
      },
    );

    test('software-tech ships the shared fields overrides then tasks, each '
        'naming the doc types of its Fields row', () {
      final fields = _softwareTechManifest().shared.fields;
      expect(fields.map((f) => f.id), ['overrides', 'tasks']);
      expect({for (final f in fields) f.id: f.forDocTypes}, _fieldReach);
      expect(
        [
          for (final f in fields)
            (f.entry.type, f.entry.list, f.entry.required ?? false),
        ],
        [(FieldType.string, true, false), (FieldType.taskRef, true, false)],
      );
    });

    test('the 1.16.0 entry holds one drop_section step for architecture and '
        'project_architecture', () {
      final entry = _softwareTechManifest().migrations.singleWhere(
        (m) => m.from.toString() == '1.16.0',
      );

      expect(entry.steps, hasLength(1));
      final step = entry.steps.single as DropSection;
      expect(step.docTypes, ['architecture', 'project_architecture']);
      expect(step.sectionId, 'design_references');
      expect(step.sectionHeader, 'Design references');
    });

    test('the 1.17.0 entry holds two rename_section steps for the architecture types', () {
      final entry = _softwareTechManifest().migrations.singleWhere(
        (m) => m.from.toString() == '1.17.0',
      );

      expect(entry.steps.map((s) => s.kind), [
        'rename_section',
        'rename_section',
      ]);
      final steps = entry.steps.cast<RenameSection>();
      expect(steps.map((s) => s.docType), [
        'architecture',
        'project_architecture',
      ]);
      for (final step in steps) {
        expect(step.fromId, 'component_diagram');
        expect(step.fromHeader, 'Component diagram');
        expect(step.toId, 'technical_diagram');
        expect(step.toHeader, 'Technical diagram');
      }
    });

    test('the 1.19.0 entry holds two merge_doc steps, then two mark_retrim '
        'steps, in order', () {
      final entry = _softwareTechManifest().migrations.singleWhere(
        (m) => m.from.toString() == '1.19.0',
      );

      expect(entry.steps.map((s) => s.kind), [
        'merge_doc',
        'merge_doc',
        'mark_retrim',
        'mark_retrim',
      ]);
      final error = entry.steps[0] as MergeDoc;
      expect(error.fromId, 'error');
      expect(error.fromPath, 'specs/f{nn}_{slug}/ERROR.md');
      expect(error.toId, 'api');
      expect(
        [for (final m in error.sections) (m.fromId, m.fromHeader, m.toId)],
        [('error_catalog', 'Error catalog', 'errors')],
      );
      final projectError = entry.steps[1] as MergeDoc;
      expect(projectError.fromId, 'project_error');
      expect(projectError.fromPath, 'specs/ERROR.md');
      expect(projectError.toId, 'project_api');
      expect(
        [
          for (final m in projectError.sections)
            (m.fromId, m.fromHeader, m.toId),
        ],
        [
          ('error_envelope', 'Error envelope', 'error_model'),
          ('error_catalog', 'Error catalog', 'error_model'),
          ('retry_policy', 'Retry policy', 'error_model'),
        ],
      );
      final apiRetrim = entry.steps[2] as MarkRetrim;
      expect(apiRetrim.docTypes, ['api', 'project_api']);
      expect(apiRetrim.sections, ['errors', 'error_model']);
      final frRetrim = entry.steps[3] as MarkRetrim;
      expect(frRetrim.docTypes, ['fr']);
      expect(frRetrim.sections, ['input_output']);
    });

    test('software-tech keeps its ten migration entries and adds none for '
        'the shared entries', () {
      final migrations = _softwareTechManifest().migrations;
      const merges = 'merge_doc, merge_doc, merge_doc, merge_doc, merge_doc';
      expect(
        [
          for (final m in migrations)
            '${m.from}: ${[for (final s in m.steps) s.kind].join(', ')}',
        ],
        [
          '1.4.0: move_to_record',
          '1.6.0: stamp_code_fingerprints',
          '1.7.0: move_file, restamp_code_fingerprints',
          '1.13.0: drop_default_lines',
          '1.14.0: mark_retrim',
          '1.16.0: drop_section',
          '1.17.0: rename_section, rename_section',
          '1.19.0: merge_doc, merge_doc, mark_retrim, mark_retrim',
          '1.20.0: move_to_record, $merges, drop_section, drop_doc_type',
          '1.23.0: relink_merged_docs',
        ],
      );
    });

    test('the 1.14.0 entry holds one mark_retrim step for domain invariants '
        'and value objects', () async {
      final migrations = _softwareTechManifest().migrations;
      expect(migrations.map((m) => m.from.toString()), [
        '1.4.0',
        '1.6.0',
        '1.7.0',
        '1.13.0',
        '1.14.0',
        '1.16.0',
        '1.17.0',
        '1.19.0',
        '1.20.0',
        '1.23.0',
      ]);
      final entry = migrations.singleWhere(
        (m) => m.from.toString() == '1.14.0',
      );
      final mark = entry.steps.single as MarkRetrim;
      expect(mark.docTypes, ['domain', 'project_domain']);
      expect(mark.sections, ['invariants', 'value_objects']);

      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig().replaceFirst(
          'software-tech: ${shippedPackVersions()['software-tech']}',
          'software-tech: ${entry.from}',
        ),
        'docs/specs/DOMAIN.md':
            '# Project domain\n\n## Invariants\n\n'
            '- **INV-1** An email is unique.\n\n## Value objects\n\n'
            '| VO | Backed by | Validation |\n|---|---|---|\n'
            '| Email | String | an inbox and a host |\n',
      });
      final home = await writeTree({});
      final plan = planUpgradeRun(
        project,
        templates: TemplateResolver(),
        homeDirectory: home,
      );

      expect(plan.lists.toJson()['steps'], [
        {
          'from': '1.14.0',
          'step': 'mark_retrim',
          'paths': ['specs/DOMAIN.md'],
        },
        {
          'from': '1.16.0',
          'step':
              'drop_section architecture, project_architecture '
              'design_references',
          'paths': <String>[],
        },
        {
          'from': '1.17.0',
          'step':
              'rename_section architecture component_diagram -> '
              'technical_diagram',
          'paths': <String>[],
        },
        {
          'from': '1.17.0',
          'step':
              'rename_section project_architecture component_diagram -> '
              'technical_diagram',
          'paths': <String>[],
        },
        {
          'from': '1.19.0',
          'step': 'merge_doc error -> api',
          'paths': <String>[],
        },
        {
          'from': '1.19.0',
          'step': 'merge_doc project_error -> project_api',
          'paths': <String>[],
        },
        {'from': '1.19.0', 'step': 'mark_retrim', 'paths': <String>[]},
        {'from': '1.19.0', 'step': 'mark_retrim', 'paths': <String>[]},
        {
          'from': '1.20.0',
          'step': 'move_to_record architecture covers -> implementation',
          'paths': <String>[],
        },
        {
          'from': '1.20.0',
          'step': 'merge_doc domain -> architecture',
          'paths': <String>[],
        },
        {
          'from': '1.20.0',
          'step': 'merge_doc project_domain -> project_architecture',
          'paths': ['specs/ARCHITECTURE.md'],
        },
        {
          'from': '1.20.0',
          'step': 'merge_doc project_integration -> project_architecture',
          'paths': <String>[],
        },
        {
          'from': '1.20.0',
          'step': 'merge_doc auth -> security',
          'paths': <String>[],
        },
        {
          'from': '1.20.0',
          'step': 'merge_doc project_auth -> project_security',
          'paths': <String>[],
        },
        {
          'from': '1.20.0',
          'step': 'drop_section architecture, project_architecture concerns',
          'paths': <String>[],
        },
        {'from': '1.20.0', 'step': 'drop_doc_type topic', 'paths': <String>[]},
        {'from': '1.23.0', 'step': 'relink_merged_docs', 'paths': <String>[]},
      ]);
      expect(
        plan.creates
            .singleWhere(
              (create) => create.path == 'docs/specs/ARCHITECTURE.md',
            )
            .text,
        contains('retrim:\n  - invariants\n  - value_objects\n'),
      );
    });

    test('a frozen doc type loads only for the migration steps, never into '
        'the merged set', () {
      final names = shippedPackVersions().keys;
      final templates = TemplateResolver();

      final frozen = templates.frozenDocTypes(
        packNames: names,
        homeDirectory: null,
      );

      expect(frozen.keys, unorderedEquals(['domain', 'project_domain']));
      expect(frozen['project_domain']!.sections.map((s) => s.id), [
        'entities',
        'value_objects',
        'invariants',
        'known_limits',
        'lifecycle',
        'data_touch',
        'commands_and_events',
        'terms',
      ]);
      final set = templates.resolveCarried(
        packNames: names,
        homeDirectory: null,
      );
      expect(set.lookup('domain'), isNull);
      expect(set.lookup('project_domain'), isNull);
    });

    test('an upgrade to the shipped version carries the ten feature patterns '
        'and runs no migration step that touches them', () {
      final manifest = PackManifest.parse(
        utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
        file: 'packs/software-tech/pack.yaml',
      );
      final shipped = manifest.version;
      final below = PackVersion.parse(
        '1.14.0',
        file: 'test',
        key: 'software-tech',
      );

      final upgrades = selectUpgrades(
        {'software-tech': below},
        {'software-tech': manifest},
      );

      expect(upgrades.single.target, shipped);
      expect(
        [for (final s in upgrades.single.steps) s.step.kind],
        [
          'mark_retrim',
          'drop_section',
          'rename_section',
          'rename_section',
          'merge_doc',
          'merge_doc',
          'mark_retrim',
          'mark_retrim',
          'move_to_record',
          'merge_doc',
          'merge_doc',
          'merge_doc',
          'merge_doc',
          'merge_doc',
          'drop_section',
          'drop_doc_type',
          'relink_merged_docs',
        ],
      );
      expect(
        shippedPackFiles.keys.where(
          (k) => k.startsWith('software-tech/patterns/'),
        ),
        hasLength(10),
      );
      final patternMoves = [
        for (final migration in manifest.migrations)
          for (final step in migration.steps)
            if (step is MoveFile &&
                (step.from.contains('patterns/') ||
                    step.to.contains('patterns/')))
              step,
      ];
      expect(patternMoves, isEmpty);
    });

    test('a project pinning both packs resolves with no fault', () {
      expect(resolveSoftwareTech(), completes);
    });

    test('software-tech listed without prd-core is '
        'prd_core_missing', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(['software-tech']),
      });
      final home = await writeTree({});
      expect(
        () => TemplateResolver().resolve(
          workingDirectory: project,
          homeDirectory: home,
        ),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.prdCoreMissing,
          ),
        ),
      );
    });
  });

  group('software-tech set', () {
    late MergedSet set;

    setUpAll(() async {
      set = await resolveSoftwareTech();
    });

    test('the set holds the fifteen prd-core and the ten '
        'software-tech doc types', () {
      expect(
        set.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, ...softwareTechIds]..sort(),
      );
      for (final id in softwareTechIds) {
        expect(prdCoreDocType(set, id).pack, 'software-tech', reason: id);
      }
      for (final id in prdCoreIds) {
        expect(prdCoreDocType(set, id).pack, 'prd-core', reason: id);
      }
    });

    test('the ten doc types of the Output table take their path, parent, '
        'and per-target key', () {
      expect(_outputRows.keys, unorderedEquals(softwareTechIds));
      for (final MapEntry(:key, :value) in _outputRows.entries) {
        final docType = prdCoreDocType(set, key);
        expect(
          [docType.path, docType.parent, docType.isPerTarget],
          value,
          reason: key,
        );
      }
    });

    test('no doc type is a spec index', () {
      expect(set.lookup('index'), isNull);
      for (final docType in set.docTypes) {
        expect(
          docType.path ?? '',
          isNot(endsWith('INDEX.md')),
          reason: docType.id,
        );
      }
    });

    test('rollout, observability, and events are optional '
        'sections, not doc types', () {
      for (final id in ['rollout', 'observability', 'events']) {
        expect(set.lookup(id), isNull, reason: id);
      }
      final architecture = prdCoreDocType(set, 'architecture');
      final integration = prdCoreDocType(set, 'integration');
      expect(sectionOf(architecture, 'rollout').required, isFalse);
      expect(sectionOf(architecture, 'observability').required, isFalse);
      expect(sectionOf(integration, 'events').required, isFalse);
    });

    test('only the implementation record and the project architecture carry '
        'covers', () {
      for (final docType in set.docTypes) {
        expect(
          docType.fields.any((f) => f.id == 'covers'),
          {'implementation', 'project_architecture'}.contains(docType.id),
          reason: docType.id,
        );
      }
    });

    test('six doc types carry an optional tasks list of task refs, and '
        'implementation carries none', () {
      final withTasks = _fieldReach['tasks']!;
      for (final id in withTasks) {
        final tasks = prdCoreDocType(
          set,
          id,
        ).fields.singleWhere((f) => f.id == 'tasks');
        expect(tasks.type, FieldType.taskRef, reason: id);
        expect(tasks.list, isTrue, reason: id);
        expect(tasks.required, isFalse, reason: id);
      }
      expect(
        prdCoreDocType(
          set,
          'implementation',
        ).fields.where((f) => f.type == FieldType.taskRef),
        isEmpty,
      );
    });

    test(
      'each of the ten doc types, the project spec types through '
      'extends, titles with no number, so each sets lint.title_no_number',
      () {
        for (final id in softwareTechIds) {
          expect(
            prdCoreDocType(set, id).lint.titleNoNumber,
            isTrue,
            reason: id,
          );
        }
      },
    );

    test('no description states a line target or a sentence length', () {
      final target = RegExp(
        r'Aim for (?:about|under)|\d[\d,]*-(?:line|character) cap|Each sentence holds',
      );
      for (final id in softwareTechIds) {
        expect(
          prdCoreDocType(set, id).description,
          isNot(contains(target)),
          reason: id,
        );
      }
    });

    test('a description keeps its file rule on a line of its own', () {
      for (final MapEntry(:key, :value) in _fileRuleLines.entries) {
        expect(
          prdCoreDocType(set, key).description?.split('\n'),
          contains(value),
          reason: key,
        );
      }
    });

    test('a description states its item shape with no sentence count', () {
      for (final MapEntry(:key, :value) in _itemShapeLines.entries) {
        final lines = prdCoreDocType(set, key).description?.split('\n') ?? [];
        expect(lines, contains(value), reason: key);
        expect(
          lines.where((l) => l.endsWith('each rule one sentence.')),
          isEmpty,
          reason: key,
        );
      }
    });

    test('each doc type a shared field reaches keeps its field ids in their '
        'order before the move', () {
      for (final MapEntry(:key, :value) in _fieldIds.entries) {
        expect(
          [for (final f in prdCoreDocType(set, key).fields) f.id],
          value,
          reason: key,
        );
      }
    });

    test('no description in the pack files holds a YAML key line', () {
      for (final MapEntry(:key, :value) in shippedPackFiles.entries) {
        if (!key.startsWith('software-tech/') || key.contains('/patterns/')) {
          continue;
        }
        for (final text in _descriptionsIn(loadYaml(utf8.decode(value)))) {
          expectNoYamlKeyLine(text, reason: key);
        }
      }
    });

    test('no spec doc type carries a word '
        'list at either level', () {
      for (final id in softwareTechIds) {
        final docType = prdCoreDocType(set, id);
        expect(docType.lint.bannedWords, isNull, reason: id);
        for (final section in docType.sections) {
          expect(section.bannedWords, isNull, reason: '$id.${section.id}');
        }
      }
    });

    test('a check run on spec tables of ordinary words raises no banned '
        'word, and the guides ask for numbers instead', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'docs/specs/f01_login/ARCHITECTURE.md':
                '---\ndraft: true\n---\n\n# Login architecture\n\n'
                '## Components\n| Component | Responsibility |\n|---|---|\n'
                '| Gate | Flexible, easy, safe, and user-friendly sign-in |\n',
          },
        ),
      );

      expect(
        report.findings.where((f) => f.kind == FindingKind.bannedWord),
        isEmpty,
      );
      expect(
        sectionOf(
          prdCoreDocType(set, 'project_architecture'),
          'crosscutting_concepts',
        ).description,
        contains('with numbers, not adjectives'),
      );
    });

    test('no other doc type sets bundle, and no '
        'other section sets query', () {
      expect(
        [
          for (final t in set.docTypes)
            if (t.bundle != null) t.id,
        ],
        [
          'glossary',
          'gnfr',
          'goal',
          'project',
          'project_api',
          'project_architecture',
          'project_security',
          'tech_stack',
        ],
      );
      expect(
        {
          for (final t in set.docTypes)
            for (final s in t.sections)
              if (s.query != null) t.id,
        },
        {'feature', 'glossary', 'project'},
      );
    });

    test('code path fields sit on implementation, project_architecture, and '
        'tech_stack only', () {
      final codePathFields = [
        for (final docType in set.docTypes)
          for (final field in docType.fields)
            if (field.type == FieldType.outputRef || field.id == 'code')
              (docType.id, field),
      ];

      expect(codePathFields.map((e) => '${e.$1}.${e.$2.id}'), [
        'implementation.implements',
        'implementation.tests',
        'implementation.covers',
        'project_architecture.covers',
        'tech_stack.code',
      ]);
    });
  });
}

PackManifest _softwareTechManifest() => PackManifest.parse(
  utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
  file: 'packs/software-tech/pack.yaml',
);

/// Every `description` string anywhere in the YAML [node].
Iterable<String> _descriptionsIn(Object? node) sync* {
  if (node is YamlMap) {
    for (final MapEntry(:key, :value) in node.entries) {
      if (key == 'description' && value is String) yield value;
      yield* _descriptionsIn(value);
    }
  } else if (node is YamlList) {
    for (final item in node) {
      yield* _descriptionsIn(item);
    }
  }
}
