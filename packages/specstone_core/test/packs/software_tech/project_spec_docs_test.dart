import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

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

/// The Overrides carriers whose items include table rows.
const _tableRowCarriers = ['architecture', 'auth', 'error'];

/// Each project spec doc type's title form and its own example title.
const _projectTitles = <String, ({String form, String example})>{
  'project_architecture': (
    form: '# <Project name> architecture',
    example: '# Specstone architecture',
  ),
  'project_domain': (
    form: '# <Project name> domain',
    example: '# Specstone domain',
  ),
  'project_api': (form: '# <Project name> API', example: '# Specstone API'),
  'project_integration': (
    form: '# <Project name> integrations',
    example: '# Specstone integrations',
  ),
  'project_error': (
    form: '# <Project name> errors',
    example: '# Specstone errors',
  ),
  'project_auth': (form: '# <Project name> auth', example: '# Specstone auth'),
};

/// The item shape each project spec doc type's guide states.
const _projectItemShapes = <String, String>{
  'project_architecture': 'one Components row per component',
  'project_domain': 'one bullet per invariant',
  'project_api': 'one bullet per convention',
  'project_integration': 'one `###` per system',
  'project_error': 'one catalog row per code',
  'project_auth': 'one matrix row per resource and operation',
};

const _domainCitesArchitecture =
    "The project's DOMAIN cites the project's ARCHITECTURE by a section link, "
    'such as `[architecture](ARCHITECTURE.md#components)`.';

/// Names one feature: "the feature", "each feature", "per feature", and so on.
///
/// "a feature" stays out: "A feature's `error_envelope` departs from it" names
/// every feature alike.
final _namesOneFeature = RegExp(
  r'\b(?:the|this|that|one|its|each|per)\s+feature\b',
  caseSensitive: false,
);

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

  test('project_domain invariants allow a closing note', () {
    expectSectionsSay(prdCoreDocType(set, 'project_domain'), const {
      'invariants': [
        'no trace tag',
        '`reference` field',
        'a cite or ownership note may close',
      ],
    });
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

  test('project_error requires error_envelope', () {
    final type = prdCoreDocType(set, 'project_error');
    final base = prdCoreDocType(set, 'error');
    expect(sectionOf(type, 'error_envelope').required, isTrue);
    expect(sectionOf(base, 'error_envelope').required, isFalse);
    expect(sectionOf(type, 'error_envelope').description, isNotEmpty);
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

  test('each project spec doc type carries the four references of its base '
      'type', () {
    for (final MapEntry(key: id, value: project) in _projectTypes.entries) {
      expectSpecLint(
        prdCoreDocType(set, id),
        maxLines: specCaps.maxLines,
        maxChars: specCaps.maxChars,
      );
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

  test("each project spec doc type guide titles its doc with the project's "
      "name and states its base type's line target", () {
    for (final MapEntry(key: id, value: title) in _projectTitles.entries) {
      final type = prdCoreDocType(set, id);
      expectSpecGuide(
        type,
        title: title.form,
        says: [
          'such as `${title.example}`',
          "lives in that target's record, its `implementation` docs, only",
        ],
      );
    }
  });

  test('each project spec doc type guide states where its rules belong', () {
    for (final id in _projectTypes.keys) {
      expectDescriptionSays(prdCoreDocType(set, id), const [
        'only rules every feature uses',
        'a per-feature spec doc',
        'a `topic` when two or more features share it',
      ]);
    }
  });

  test('project_integration and project_auth guides say when the doc is '
      'written', () {
    expectDescriptionSays(prdCoreDocType(set, 'project_integration'), const [
      'only when every feature follows one rule for outside calls',
    ]);
    expectDescriptionSays(prdCoreDocType(set, 'project_auth'), const [
      'only when every feature follows one access rule',
    ]);
  });

  test('project_api guide states its item shape', () {
    expectItemShape(
      prdCoreDocType(set, 'project_api'),
      'Write one rule per ID: one bullet per convention, each rule one '
      'sentence.',
    );
  });

  test("each other project spec doc type guide states its base type's item "
      'shape', () {
    for (final MapEntry(key: id, value: shape) in _projectItemShapes.entries) {
      expectItemShape(
        prdCoreDocType(set, id),
        'Write one rule per ID: $shape, each rule one sentence.',
      );
    }
  });

  test('project_domain and project_architecture guides carry the '
      'domain-to-architecture cite line', () {
    for (final id in ['project_domain', 'project_architecture']) {
      expectItemShape(prdCoreDocType(set, id), _domainCitesArchitecture);
    }
  });

  test('each project spec doc type guide extends the cite rule to project and '
      'ancestor rules', () {
    for (final id in _projectTypes.keys) {
      expectDescriptionSays(prdCoreDocType(set, id), const [
        'by a link to the item that holds it, never restate it',
        "a rule of a project spec doc or of an ancestor feature's spec doc",
      ]);
    }
  });

  test('each Overrides carrier guide extends the cite rule to project and '
      'ancestor rules', () {
    for (final id in _overridesCarriers) {
      expectDescriptionSays(prdCoreDocType(set, id), const [
        'by a link to the item that holds it, never restate it',
        "a rule of a project spec doc or of an ancestor feature's spec doc",
      ]);
    }
  });

  test('each Overrides carrier guide asks an Overrides line and its entry', () {
    for (final id in _overridesCarriers) {
      expectDescriptionSays(prdCoreDocType(set, id), const [
        '`Overrides:` line',
        '`overrides` entry',
      ]);
    }
  });

  test('a carrier whose items include table rows places the Overrides line '
      'under the table and names the row', () {
    for (final id in _tableRowCarriers) {
      expectDescriptionSays(prdCoreDocType(set, id), const [
        'right under the table when that item is a table row',
        'its how-clause naming the row',
      ]);
    }
  });

  test('no project spec doc type guide names one feature', () {
    for (final id in _projectTypes.keys) {
      final type = prdCoreDocType(set, id);
      expect(type.description, isNot(contains(_namesOneFeature)), reason: id);
      for (final section in type.sections) {
        expect(
          section.description ?? '',
          isNot(contains(_namesOneFeature)),
          reason: '$id.${section.id}',
        );
      }
    }
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
}
