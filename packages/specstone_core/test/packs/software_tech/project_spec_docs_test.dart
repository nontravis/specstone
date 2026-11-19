import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';

/// Each project spec doc type, the doc type it extends, and the fields and
/// sections it disables.
const _projectTypes =
    <String, ({String base, Set<String> fields, Set<String> sections})>{
      'project_architecture': (
        base: 'architecture',
        fields: {'covers', 'overrides'},
        sections: {},
      ),
      'project_domain': (base: 'domain', fields: {'overrides'}, sections: {}),
      'project_api': (
        base: 'api',
        fields: {'confirmed', 'overrides'},
        sections: {'fr_trace', 'operations'},
      ),
      'project_integration': (
        base: 'integration',
        fields: {'overrides'},
        sections: {},
      ),
      'project_error': (base: 'error', fields: {'overrides'}, sections: {}),
      'project_auth': (base: 'auth', fields: {'overrides'}, sections: {}),
    };

const _overridesCarriers = [
  'api',
  'architecture',
  'auth',
  'domain',
  'error',
  'integration',
  'topic',
];

Future<MergedSet> _resolveWith({
  Map<String, String> templates = const {},
  String config = '',
}) async {
  final project = await writeTree({
    '.specstone/config.yaml': '${shippedPinsConfig()}$config',
    for (final MapEntry(:key, :value) in templates.entries)
      '.specstone/templates/$key': value,
  });
  final home = await writeTree({});
  return TemplateResolver().resolve(
    workingDirectory: project,
    homeDirectory: home,
  );
}

List<(String, String, String?, bool)> _sectionShapes(
  MergedDocType type, {
  Set<String> except = const {},
}) => [
  for (final s in type.sections)
    if (!except.contains(s.id)) (s.id, s.header, s.prefixId, s.required),
];

void main() {
  late MergedSet set;
  setUpAll(() async {
    set = await resolveSoftwareTech();
  });

  test('each project spec doc type sits at the spec root with no parent, per '
      'target, and joins implement and design bundles', () {
    for (final MapEntry(key: id, value: project) in _projectTypes.entries) {
      final type = prdCoreDocType(set, id);
      final base = prdCoreDocType(set, project.base);
      final file = base.path!.split('/').last;
      expect(type.path, 'specs/$file', reason: id);
      expect(type.parent, isNull, reason: id);
      expect(type.isPerTarget, isTrue, reason: id);
      expect(type.bundle, ['implement', 'design'], reason: id);
      expect(type.extendsId, project.base, reason: id);
      expect(set.isProjectSpecType(type), isTrue, reason: id);
      expect(set.isProjectSpecType(base), isFalse, reason: id);
    }
  });

  test('each project spec doc type keeps its base type fields and sections '
      'less its disables', () {
    for (final MapEntry(key: id, value: project) in _projectTypes.entries) {
      final type = prdCoreDocType(set, id);
      final base = prdCoreDocType(set, project.base);
      expect(
        [for (final f in type.fields) f.id],
        [
          for (final f in base.fields)
            if (!project.fields.contains(f.id)) f.id,
        ],
        reason: id,
      );
      final kept = [
        for (final f in base.fields)
          if (!project.fields.contains(f.id))
            [f.id, f.type, f.list, f.required, f.pointer],
      ];
      expect(
        [
          for (final f in type.fields)
            [f.id, f.type, f.list, f.required, f.pointer],
        ],
        kept,
        reason: id,
      );
      if (id == 'project_api') continue;
      final except = id == 'project_error'
          ? const {'error_envelope'}
          : const <String>{};
      expect(
        _sectionShapes(type, except: except),
        _sectionShapes(base, except: except),
        reason: id,
      );
    }
  });

  test('project_api holds conventions between source_of_truth and '
      'compatibility and no fr_trace, operations, or confirmed', () {
    final type = prdCoreDocType(set, 'project_api');
    expectSections(type, const [
      SectionSpec('source_of_truth', 'Source-of-truth'),
      SectionSpec(
        'conventions',
        'Conventions',
        prefixId: 'API-C',
        required: true,
      ),
      SectionSpec('compatibility', 'Compatibility'),
    ]);
    expect(type.fields.any((f) => f.id == 'confirmed'), isFalse);
    expect(sectionOf(type, 'conventions').description, isNotEmpty);
  });

  test('project error requires its envelope and frees its retry section', () {
    final type = prdCoreDocType(set, 'project_error');
    final base = prdCoreDocType(set, 'error');
    expect(sectionOf(type, 'error_envelope').required, isTrue);
    expect(sectionOf(base, 'error_envelope').required, isFalse);
    expect(sectionOf(type, 'error_envelope').description, isNotEmpty);
    expect(sectionOf(type, 'retry_policy').required, isFalse);
    expect(
      sectionOf(type, 'error_catalog').description,
      isNot(contains('Implemented by')),
    );
    expect(
      [for (final s in type.sections) s.id],
      [for (final s in base.sections) s.id],
    );
  });

  test('project_architecture carries no covers', () {
    final type = prdCoreDocType(set, 'project_architecture');
    expect(type.fields.any((f) => f.id == 'covers'), isFalse);
    expect(type.fields.any((f) => f.id == 'overrides'), isFalse);
  });

  test('exactly the seven doc types of the overrides row carry overrides, '
      'each as an optional string list', () {
    final carriers = [
      for (final type in set.docTypes)
        if (type.pack == 'software-tech' &&
            type.fields.any((f) => f.id == 'overrides'))
          type.id,
    ];
    expect(carriers, _overridesCarriers);
    for (final id in carriers) {
      final field = fieldOf(prdCoreDocType(set, id), 'overrides');
      expect(field.type, FieldType.string, reason: id);
      expect(field.list, isTrue, reason: id);
      expect(field.required, isFalse, reason: id);
      expect(field.description, isNotEmpty, reason: id);
    }
  });

  test('each project spec doc type carries the references of its base '
      'type', () {
    for (final MapEntry(key: id, value: project) in _projectTypes.entries) {
      expect(
        [for (final r in prdCoreDocType(set, id).reference!) r.title],
        [for (final r in prdCoreDocType(set, project.base).reference!) r.title],
        reason: id,
      );
    }
  });

  test('the conventions section carries the one-sentence lint', () {
    final limits = sectionOf(
      prdCoreDocType(set, 'project_api'),
      'conventions',
    ).maxSentences;
    expect(limits, hasLength(1));
    expect(limits!.single.count, 1);
  });

  test('a project spec doc type inherits the size keys of its base type', () {
    for (final (id, section) in [
      ('project_architecture', 'concerns'),
      ('project_architecture', 'design_references'),
    ]) {
      expect(
        sectionOf(prdCoreDocType(set, id), section).maxItemLines,
        1,
        reason: '$id.$section',
      );
    }
    expect(
      sectionOf(prdCoreDocType(set, 'project_auth'), 'enforcement').maxLines,
      1,
    );
    final catalog = sectionOf(
      prdCoreDocType(set, 'project_error'),
      'error_catalog',
    ).maxSentences!;
    expect(
      [for (final c in catalog) (c.count, c.column)],
      [(1, 'Triggered by'), (1, 'Client guidance')],
    );
  });

  test('the convention and invariant forms state no sentence count', () {
    final convention = sectionOf(
      prdCoreDocType(set, 'project_api'),
      'conventions',
    );
    expect(convention.description, isNot(contains('<one sentence>')));
    expect(
      convention.description,
      contains('Write each as `- **API-C<N>** <rule>`'),
    );
    final invariants = sectionOf(
      prdCoreDocType(set, 'project_domain'),
      'invariants',
    );
    expect(invariants.description, isNot(contains('<one sentence>')));
    expect(
      invariants.description,
      contains('Write each invariant as `- **INV-<N>** <rule>`'),
    );
  });

  test('project_domain inherits the invariant entries', () {
    final domain = prdCoreDocType(set, 'domain');
    final projectDomain = prdCoreDocType(set, 'project_domain');
    List<Map<String, Object>> fieldsOf(MergedDocType type) => [
      for (final f
          in type.sections.singleWhere((s) => s.id == 'invariants').itemFields!)
        f.toJson(),
    ];
    expect(fieldsOf(projectDomain), fieldsOf(domain));
    expect(fieldsOf(projectDomain), [
      containsPair('default_from', 'entities'),
      allOf(
        containsPair('optional', true),
        containsPair('values', ['eventual']),
      ),
      containsPair('when', isNotNull),
    ]);
    expect(
      sectionOf(projectDomain, 'invariants').description,
      isNot(contains('- **Consistency:** immediate')),
    );
    expect(
      projectDomain.sections.map((s) => s.id),
      isNot(contains('corrective_policies')),
    );
  });

  test('with two targets each project spec doc type reads the target '
      'folder', () async {
    final twin = await _resolveWith(
      config:
          'targets:\n  flutter:\n    code_root: a\n'
          '  jaspr:\n    code_root: b\n',
    );
    final matcher = DocTypeMatcher(twin, targetNames: ['flutter', 'jaspr']);
    for (final MapEntry(key: id, value: project) in _projectTypes.entries) {
      final file = prdCoreDocType(twin, project.base).path!.split('/').last;
      for (final target in ['flutter', 'jaspr']) {
        final match = matcher.match('specs/$target/$file');
        expect(match, isA<MatchedDocType>(), reason: '$id $target');
        match as MatchedDocType;
        expect(match.docType.id, id, reason: '$id $target');
        expect(match.target, target, reason: '$id $target');
      }
      expect(matcher.match('specs/$file'), isA<NoDocType>(), reason: id);
    }
  });

  test('a project layer that disables overrides on domain still resolves '
      'the project spec doc type built on it', () async {
    final layered = await _resolveWith(
      templates: {
        'domain.yaml': 'fields:\n  - id: overrides\n    disabled: true\n',
      },
    );
    final type = prdCoreDocType(layered, 'project_domain');
    expect(type.fields.any((f) => f.id == 'overrides'), isFalse);
    expect(
      prdCoreDocType(layered, 'domain').fields.any((f) => f.id == 'overrides'),
      isFalse,
    );
  });

  test('a project layer over a project spec doc type that changes only its '
      'description resolves', () async {
    final layered = await _resolveWith(
      templates: {'project_domain.yaml': 'description: Rules for all.\n'},
    );
    final type = prdCoreDocType(layered, 'project_domain');
    expect(type.description, 'Rules for all.');
    expect(type.path, 'specs/DOMAIN.md');
    expect(type.parent, isNull);
    expect(type.fields.any((f) => f.id == 'overrides'), isFalse);
  });

  test('a 50001-character project API.md gets chars_over_limit, limit 50000, '
      'the limit it inherits from api', () async {
    const draft = '---\ndraft: true\n---\n\n';
    const title = '# Project API\n';
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/API.md':
              '$draft$title${'x' * (50001 - draft.length - title.length - 2)}',
        },
      ),
    );

    final json = report.findings
        .singleWhere((f) => f.kind == FindingKind.charsOverLimit)
        .toJson();
    expect(
      json,
      allOf(containsPair('limit', 50000), containsPair('actual', 50001)),
    );
  });

  test('an inherited section whose base description names the feature reads '
      'every feature or the project in each project spec doc type', () {
    var rewritten = 0;
    for (final MapEntry(key: id, value: project) in _projectTypes.entries) {
      final base = prdCoreDocType(set, project.base);
      for (final section in prdCoreDocType(set, id).sections) {
        final text = section.description ?? '';
        expect(text, isNot(contains('the feature')), reason: '$id $section');
        final baseText = [
          for (final b in base.sections)
            if (b.id == section.id) b.description ?? '',
        ].join();
        if (!baseText.contains('the feature')) continue;
        rewritten++;
        expect(
          text.contains('every feature') || text.contains('the project'),
          isTrue,
          reason: '$id ${section.id}',
        );
      }
    }
    expect(rewritten, greaterThan(0));
  });

  test('each project spec doc type disables the shared overrides field its '
      'base holds and keeps the shared tasks field', () {
    final shared = PackManifest.parse(
      utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
      file: 'packs/software-tech/pack.yaml',
    ).shared.fields;
    final overrides = shared.singleWhere((f) => f.id == 'overrides');
    final tasks = shared.singleWhere((f) => f.id == 'tasks');
    for (final MapEntry(key: id, value: project) in _projectTypes.entries) {
      final layer = loadYaml(
        utf8.decode(shippedPackFiles['software-tech/$id.yaml']!),
      ) as YamlMap;
      expect(
        [
          for (final field in layer['fields'] as YamlList)
            if ((field as YamlMap)['id'] == 'overrides') field['disabled'],
        ],
        [true],
        reason: id,
      );
      expect(overrides.forDocTypes, contains(project.base), reason: id);
      expect(overrides.forDocTypes, isNot(contains(id)), reason: id);
      expect(tasks.forDocTypes, isNot(contains(id)), reason: id);
      final fields = prdCoreDocType(set, id).fields;
      expect(fields.any((f) => f.id == 'overrides'), isFalse, reason: id);
      expect(
        fields.singleWhere((f) => f.id == 'tasks').type,
        FieldType.taskRef,
        reason: id,
      );
    }
  });

  test('project, topic, and per-feature descriptions place every-feature, '
      'shared, and one-feature rules', () {
    expect(
      prdCoreDocType(set, 'topic').description,
      contains(
        'two or more features share and none owns, never a rule every '
        'feature uses',
      ),
    );
    for (final project in _projectTypes.values) {
      expect(
        prdCoreDocType(set, project.base).description,
        allOf(
          matches(RegExp(r'^[^\n]*one feature', caseSensitive: false)),
          contains("Put a rule every feature uses in the project's"),
        ),
        reason: project.base,
      );
    }
  });
}
