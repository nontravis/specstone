import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
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

/// What a project spec doc type changes from the doc type it extends.
final class _ProjectType {
  const new({
    required this.base,
    required this.fields,
    required this.sections,
    required this.added,
  });

  /// The doc type it extends.
  final String base;

  /// The fields it disables.
  final Set<String> fields;

  /// The sections it disables.
  final Set<String> sections;

  /// The fields it adds.
  final List<String> added;
}

/// Each project spec doc type by id.
const _projectTypes = <String, _ProjectType>{
  'project_architecture': _ProjectType(
    base: 'architecture',
    fields: {'overrides'},
    sections: {},
    added: ['covers'],
  ),
  'project_api': _ProjectType(
    base: 'api',
    fields: {'confirmed', 'overrides'},
    sections: {'fr_trace', 'operations', 'errors'},
    added: [],
  ),
  'project_security': _ProjectType(
    base: 'security',
    fields: {'overrides'},
    sections: {},
    added: [],
  ),
};

/// The sections `project_architecture` adds after those of `architecture`.
const _projectArchitectureAdds = [
  SectionSpec('external_systems', 'External systems'),
  SectionSpec('contract_per_system', 'Contract per system'),
  SectionSpec(
    'crosscutting_concepts',
    'Crosscutting concepts',
    prefixId: 'CC-',
  ),
];

const _overridesCarriers = ['api', 'architecture', 'integration', 'security'];

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
      final added = project.added;
      expect(
        [for (final f in type.fields) f.id],
        [
          for (final f in base.fields)
            if (!project.fields.contains(f.id)) f.id,
          ...added,
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
            if (!added.contains(f.id))
              [f.id, f.type, f.list, f.required, f.pointer],
        ],
        kept,
        reason: id,
      );
      if (id == 'project_api') continue;
      expect(
        _sectionShapes(
          type,
          except: {for (final s in _projectArchitectureAdds) s.id},
        ),
        _sectionShapes(base),
        reason: id,
      );
    }
  });

  test('project_architecture adds external systems, contract per system, and '
      'crosscutting concepts, all optional, after the architecture '
      'sections', () {
    final type = prdCoreDocType(set, 'project_architecture');
    final base = prdCoreDocType(set, 'architecture');
    expectSections(type, [
      for (final s in base.sections)
        SectionSpec(s.id, s.header, prefixId: s.prefixId, required: s.required),
      ..._projectArchitectureAdds,
    ]);
  });

  test('project_api holds its surfaces, conventions, and error model in '
      'order and no fr_trace, operations, errors, or confirmed', () {
    final type = prdCoreDocType(set, 'project_api');
    expectSections(type, const [
      SectionSpec('source_of_truth', 'Source-of-truth'),
      SectionSpec('surfaces', 'Surfaces', required: true),
      SectionSpec(
        'conventions',
        'Conventions',
        prefixId: 'API-C',
        required: true,
      ),
      SectionSpec('error_model', 'Error model', prefixId: 'API-E'),
      SectionSpec('compatibility', 'Compatibility'),
    ]);
    expect(type.fields.any((f) => f.id == 'confirmed'), isFalse);
    expect(sectionOf(type, 'surfaces').description, isNotEmpty);
    expect(sectionOf(type, 'conventions').description, isNotEmpty);
    expect(sectionOf(type, 'error_model').description, isNotEmpty);
  });

  test('project_api describes its own compatibility for every feature', () {
    final text = sectionOf(
      prdCoreDocType(set, 'project_api'),
      'compatibility',
    ).description!;

    expect(
      text,
      isNot(
        equals(
          sectionOf(prdCoreDocType(set, 'api'), 'compatibility').description,
        ),
      ),
    );
  });

  test('project_architecture alone adds an optional project-root covers '
      'prefix list after its disabled overrides', () {
    final type = prdCoreDocType(set, 'project_architecture');
    final covers = fieldOf(type, 'covers');
    expect(covers.type, FieldType.outputRef);
    expect(covers.list, isTrue);
    expect(covers.required, isFalse);
    expect(covers.pointer, PointerKind.prefix);
    expect(covers.root, PointerRoot.project);
    expect(covers.description, isNotEmpty);
    expect(type.fields.last.id, 'covers');
    expect(type.fields.any((f) => f.id == 'overrides'), isFalse);
    expect(
      prdCoreDocType(set, 'architecture').fields.any((f) => f.id == 'covers'),
      isFalse,
    );
  });

  test('a write of covers alone to an approved project ARCHITECTURE.md leaves '
      'its approval hash unchanged', () {
    const body =
        '# Login project architecture\n\n## Technical diagram\n\nOne.\n';
    final type = prdCoreDocType(set, 'project_architecture');
    String hashOf(String text) =>
        approvalHashOf(text, type, statusesOutside: true);

    expect(hashOf('---\ncovers:\n  - app/lib/\n---\n\n$body'), hashOf(body));
  });

  test('exactly the four doc types of the overrides row carry overrides, '
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

  test('project architecture prints one more view line than architecture', () {
    List<String> linesOf(String id) => sectionOf(
      prdCoreDocType(set, id),
      'technical_diagram',
    ).description!.split('\n');
    final base = linesOf('architecture');
    final project = linesOf('project_architecture');

    expect(project.length, base.length + 1);
    expect(
      project.where((l) => l.contains('Technical context view')),
      hasLength(1),
    );
    expect([
      for (final l in project)
        if (!l.contains('Technical context view')) l,
    ], base);
  });

  test('project_architecture ships no design references section', () {
    expect([
      for (final s in prdCoreDocType(set, 'project_architecture').sections)
        s.id,
    ], isNot(contains('design_references')));
  });

  test('a project spec doc type inherits the size keys of its base type', () {
    expect(
      sectionOf(
        prdCoreDocType(set, 'project_security'),
        'enforcement',
      ).maxLines,
      1,
    );
    final catalog = sectionOf(
      prdCoreDocType(set, 'project_api'),
      'error_model',
    ).maxSentences!;
    expect(
      [for (final c in catalog) (c.count, c.column)],
      [(1, 'Condition'), (1, 'Client action')],
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

  test('a project layer that disables overrides on security still resolves '
      'the project spec doc type built on it', () async {
    final layered = await _resolveWith(
      templates: {
        'security.yaml': 'fields:\n  - id: overrides\n    disabled: true\n',
      },
    );
    final type = prdCoreDocType(layered, 'project_security');
    expect(type.fields.any((f) => f.id == 'overrides'), isFalse);
    expect(
      prdCoreDocType(
        layered,
        'security',
      ).fields.any((f) => f.id == 'overrides'),
      isFalse,
    );
  });

  test('a project layer over a project spec doc type that changes only its '
      'description resolves', () async {
    final layered = await _resolveWith(
      templates: {'project_security.yaml': 'description: Rules for all.\n'},
    );
    final type = prdCoreDocType(layered, 'project_security');
    expect(type.description, 'Rules for all.');
    expect(type.path, 'specs/SECURITY.md');
    expect(type.parent, isNull);
    expect(type.fields.any((f) => f.id == 'overrides'), isFalse);
  });

  test('a 50001-character project API.md gets chars_over_limit, limit 50000, '
      'the limit it inherits from api', () async {
    const draftMark = 'draft: true\n';
    const draft = '---\n$draftMark---\n\n';
    // The count leaves the draft mark out, so the file holds its length more.
    const counted = 50001 + draftMark.length - draft.length;
    const title = '# Project API\n';
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/API.md':
              '$draft$title${'x' * (counted - title.length - 2)}',
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
}
