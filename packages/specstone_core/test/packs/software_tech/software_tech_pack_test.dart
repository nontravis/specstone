import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/readability_rules.dart';
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

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';

/// The cite line and the four readability lines every description keeps.
const _readabilityLines = <String>[
  _citeLine,
  _oneRuleLine,
  citeNoteGuideLine,
  _exampleLine,
  _conditionLine,
];

const _citeLine =
    'Cite a rule another doc owns by a link to the item that holds it, never '
    'restate it.';

const _oneRuleLine =
    'Keep one rule in each item, and put several conditions in a nested list. '
    'A one-sentence paragraph with no ID moves its detail to the section of '
    'the same doc that owns it, never into a sub-list.';

const _exampleLine =
    'Give a non-obvious rule one example inside its item, as a `such as` '
    'clause or one "For example," sentence, within the sentence\'s cap.';

const _conditionLine =
    'State the condition first, then the rule, one clause chain per sentence; '
    'split a sentence whose clauses nest.';

/// The file rule each doc type keeps on a line of its own, in place of a line
/// target.
const _fileRuleLines = <String, String>{
  'api': 'Keep one file per feature spec folder.',
  'architecture': 'Keep one file per feature spec folder.',
  'auth': 'Keep one file per feature spec folder.',
  'domain': 'Keep one file per feature spec folder.',
  'error': 'Keep one file per feature spec folder.',
  'integration': 'Keep one file per feature spec folder.',
  'project_api': 'Keep one file per spec folder.',
  'project_architecture': 'Keep one file per spec folder.',
  'project_auth': 'Keep one file per spec folder.',
  'project_domain': 'Keep one file per spec folder.',
  'project_error': 'Keep one file per spec folder.',
  'project_integration': 'Keep one file per spec folder.',
  'tech_stack':
      'Keep one fact per table cell and write rows that a reader can check.',
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

    test('the description holds the shared readability lines', () {
      for (final id in softwareTechIds) {
        for (final line in _readabilityLines) {
          expect(
            prdCoreDocType(set, id).description,
            contains(line),
            reason: id,
          );
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
