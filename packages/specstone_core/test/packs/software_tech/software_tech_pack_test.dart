import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
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

/// The six per-feature spec doc types the one-file line reaches.
const _perFeatureIds = [
  'api',
  'architecture',
  'auth',
  'domain',
  'error',
  'integration',
];

/// The six project spec doc types, in code point order.
const _projectIds = [
  'project_api',
  'project_architecture',
  'project_auth',
  'project_domain',
  'project_error',
  'project_integration',
];

/// The shared lines `software-tech` ships, by id, in file order.
const _sharedLines = <String, String>{
  'cite_spec_docs':
      "Cite a project or ancestor-feature spec doc's rule by a link to its "
      'item, never restate it.',
  'no_status':
      "Never write `status:`; only a target's `implementation` record says "
      'whether its code exists.',
  'project_rules_only':
      'Hold only rules every feature uses; write any other rule in a '
      'per-feature spec doc, or in a `topic` when two or more features share '
      'it.',
  'one_file_per_feature_folder': 'Keep one file per feature spec folder.',
  'one_file_per_spec_folder': 'Keep one file per spec folder.',
  'overrides_line':
      'Right after an item departing from a rule above, write '
      '`Overrides: [<ID>](<doc>#<section>) — <how it differs>, because '
      '<why>` and record its `overrides` entry.',
  'overrides_line_table':
      'Right after an item departing from a rule above, or right under its '
      'table for a table row, write '
      '`Overrides: [<ID>](<doc>#<section>) — <how it differs>, because '
      '<why>`, naming the row in the how-clause, and record its `overrides` '
      'entry.',
};

/// The doc types each shared line names.
const _lineReach = <String, List<String>>{
  'cite_spec_docs': softwareTechIds,
  'no_status': softwareTechIds,
  'project_rules_only': _projectIds,
  'one_file_per_feature_folder': _perFeatureIds,
  'one_file_per_spec_folder': _projectIds,
  'overrides_line': ['api', 'domain', 'integration'],
  'overrides_line_table': ['architecture', 'auth', 'error'],
};

/// The doc types each shared field names, in file order.
const _fieldReach = <String, List<String>>{
  'overrides': [..._perFeatureIds, 'topic'],
  'tasks': [..._perFeatureIds, 'tech_stack', 'topic'],
};

/// The merged field ids of each doc type the shared fields reach, as they
/// stood before the fields moved into `pack.yaml`.
const _fieldIds = <String, List<String>>{
  'api': [..._builtIns, 'confirmed', 'overrides', 'tasks'],
  'architecture': [..._builtIns, 'covers', 'overrides', 'tasks'],
  'auth': [..._builtIns, 'overrides', 'tasks'],
  'domain': [..._builtIns, 'overrides', 'tasks'],
  'error': [..._builtIns, 'overrides', 'tasks'],
  'integration': [..._builtIns, 'overrides', 'tasks'],
  'project_api': [..._builtIns, 'tasks'],
  'project_architecture': [..._builtIns, 'tasks'],
  'project_auth': [..._builtIns, 'tasks'],
  'project_domain': [..._builtIns, 'tasks'],
  'project_error': [..._builtIns, 'tasks'],
  'project_integration': [..._builtIns, 'tasks'],
  'tech_stack': [..._builtIns, 'code', 'tasks'],
  'topic': [..._builtIns, 'covers', 'overrides', 'tasks'],
};

const _builtIns = ['slug', 'status', 'draft', 'approved', 'reference'];

/// The file rule a doc type no shared one-file line reaches keeps on a line of
/// its own, in place of a line target.
const _fileRuleLines = <String, String>{
  'tech_stack': 'Keep one fact per table cell and write checkable rows.',
  'topic': 'Keep one topic per file, named for the topic.',
};

/// The item shape line of each doc type whose sentence cap sits in lint.
const _itemShapeLines = <String, String>{
  'architecture': 'Write one rule per ID: one Components row per component.',
  'domain': 'Write one rule per ID: one bullet per invariant.',
  'error': 'Write one rule per ID: one catalog row per code.',
  'project_api': 'Write one rule per ID: one bullet per convention.',
  'project_architecture':
      'Write one rule per ID: one Components row per component.',
  'project_domain': 'Write one rule per ID: one bullet per invariant.',
  'project_error': 'Write one rule per ID: one catalog row per code.',
  'tech_stack': 'Write one rule per ID: one Stack row per slot.',
  'topic': 'Write one rule per ID: one bullet per rule.',
};

void main() {
  group('software-tech manifest', () {
    test('software-tech ships at 1.13.0 and extends prd-core', () {
      final bytes = shippedPackFiles['software-tech/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/software-tech/pack.yaml',
      );
      expect(manifest.name, 'software-tech');
      expect(manifest.version.toString(), '1.13.0');
      expect(manifest.extendsPack, 'prd-core');
    });

    test('software-tech ships its shared lines in table order with their '
        'reach', () {
      final lines = _softwareTechManifest().shared.lines;
      expect({for (final l in lines) l.id: l.text}, _sharedLines);
      expect(lines.map((l) => l.id), _sharedLines.keys);
      expect({for (final l in lines) l.id: l.forDocTypes}, _lineReach);
      expect(lines.where((l) => l.disabled), isEmpty);
    });

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

    test('software-tech keeps its three migration entries and adds none for '
        'the shared entries', () {
      final migrations = _softwareTechManifest().migrations;
      expect(
        [
          for (final m in migrations)
            '${m.from}: ${[for (final s in m.steps) s.kind].join(', ')}',
        ],
        [
          '1.4.0: move_to_record',
          '1.6.0: stamp_code_fingerprints',
          '1.7.0: move_file, restamp_code_fingerprints',
        ],
      );
    });

    test('an upgrade to the shipped version carries the ten feature patterns '
        'and runs no migration step for them', () {
      final manifest = PackManifest.parse(
        utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
        file: 'packs/software-tech/pack.yaml',
      );
      final shipped = manifest.version;
      final below = PackVersion.parse(
        '${shipped.major}.${shipped.minor - 1}.0',
        file: 'test',
        key: 'software-tech',
      );

      final upgrades = selectUpgrades(
        {'software-tech': below},
        {'software-tech': manifest},
      );

      expect(upgrades.single.target, shipped);
      expect(upgrades.single.steps, isEmpty);
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

    test('the set holds the fourteen prd-core and the fifteen '
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

    test('every spec doc path starts specs/, the record lies under '
        '.specstone/records/, and the seven per-feature doc types take '
        'parent feature', () {
      const perFeature = <String, String>{
        'architecture': 'ARCHITECTURE',
        'domain': 'DOMAIN',
        'api': 'API',
        'integration': 'INTEGRATION',
        'error': 'ERROR',
        'auth': 'AUTH',
        'implementation': 'IMPLEMENTATION',
      };
      for (final MapEntry(:key, :value) in perFeature.entries) {
        final docType = prdCoreDocType(set, key);
        final folder = key == 'implementation' ? '.specstone/records' : 'specs';
        expect(docType.path, '$folder/f{nn}_{slug}/$value.md', reason: key);
        expect(docType.parent, 'feature', reason: key);
      }
      for (final id in softwareTechIds) {
        expect(
          prdCoreDocType(set, id).path,
          startsWith(id == 'implementation' ? '.specstone/records/' : 'specs/'),
          reason: id,
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

    test('only architecture and topic carry covers', () {
      for (final docType in set.docTypes) {
        expect(
          docType.fields.any((f) => f.id == 'covers'),
          docType.id == 'architecture' || docType.id == 'topic',
          reason: docType.id,
        );
      }
    });

    test('eight doc types carry an optional tasks list of task refs, and '
        'implementation carries none', () {
      const withTasks = [
        'api',
        'architecture',
        'auth',
        'domain',
        'error',
        'integration',
        'tech_stack',
        'topic',
      ];
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
        prdCoreDocType(
          set,
          'domain',
        ).sections.singleWhere((s) => s.id == 'invariants').description,
        contains('timeout 10 s'),
      );
      expect(
        prdCoreDocType(
          set,
          'topic',
        ).sections.singleWhere((s) => s.id == 'rules').description,
        allOf(
          contains('numbers and checkable conditions'),
          contains('timeout 10 s'),
        ),
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
          'project_auth',
          'project_domain',
          'project_error',
          'project_integration',
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

    test('code path fields sit on architecture, implementation, tech_stack, '
        'and topic only', () {
      final codePathFields = [
        for (final docType in set.docTypes)
          for (final field in docType.fields)
            if (field.type == FieldType.outputRef || field.id == 'code')
              (docType.id, field),
      ];

      expect(codePathFields.map((e) => '${e.$1}.${e.$2.id}'), [
        'architecture.covers',
        'implementation.implements',
        'implementation.tests',
        'tech_stack.code',
        'topic.covers',
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
