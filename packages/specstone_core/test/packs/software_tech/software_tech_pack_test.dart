// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/merged_field.dart'
    show FieldType;
import 'package:specstone_core/src/templates/pack_manifest.dart';
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

/// The nine doc types the two scope lines reach: all but `implementation`.
const _scopeIds = [
  'api',
  'architecture',
  'decision',
  'integration',
  'project_api',
  'project_architecture',
  'project_security',
  'security',
  'tech_stack',
];

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
  'spec_scope': _scopeIds,
  'code_detail_home': _scopeIds,
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

void main() {
  group('software-tech manifest', () {
    test('software-tech ships at 1.26.0 and extends prd-core', () {
      final bytes = shippedPackFiles['software-tech/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/software-tech/pack.yaml',
      );
      expect(manifest.name, 'software-tech');
      expect(manifest.version.toString(), '1.26.0');
      expect(manifest.extendsPack, 'prd-core');
    });

    test('software-tech ships no migration entry and no migrations key', () {
      expect(_softwareTechManifest().migrations, isEmpty);
      final text = utf8.decode(shippedPackFiles['software-tech/pack.yaml']!);
      expect(text, isNot(contains('migrations:')));
    });

    test(
      'a software-tech pin one minor below its floor is pack_pin_below_floor',
      () async {
        final project = await writeTree({
          '.specstone/config.yaml': shippedPinsBelowFloor(
            pack: 'software-tech',
          ),
        });
        final home = await writeTree({});

        expect(
          () => TemplateResolver().resolve(
            workingDirectory: project,
            homeDirectory: home,
          ),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.packPinBelowFloor)
                .having((f) => f.message, 'message', contains('software-tech')),
          ),
        );
      },
    );

    test('software-tech ships no frozen doc type file', () {
      expect(
        shippedPackFiles.keys.where(
          (k) => k.startsWith('software-tech/frozen/'),
        ),
        isEmpty,
      );
    });

    test('software-tech ships its shared lines in table order with their '
        'reach', () {
      final lines = _softwareTechManifest().shared.lines;
      expect(lines.map((l) => l.id), _lineReach.keys);
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
