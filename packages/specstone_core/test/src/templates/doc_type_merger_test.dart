import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/reference_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

const _projectFile = '.specstone/templates/feature.yaml';
const _shippedFile = 'packs/prd-core/feature.yaml';
const _personalFile = '~/.specstone/packs/prd-core/feature.yaml';

const _shippedFeature = '''
description: A feature
path: docs/prds/{slug}/FEATURE.md
sections:
  - id: goal
    header: Feature goal
  - id: scope
    header: Out-of-scope
fields:
  - id: owner
    type: string
''';

final class _NoFiles implements LayerFiles {
  const new();

  @override
  bool exists(String layerRelativePath) => false;
}

const merger = DocTypeMerger();

DocTypeLayer layer(
  String text, {
  LayerKind kind = LayerKind.shipped,
  String docTypeId = 'feature',
}) {
  final file = switch (kind) {
    LayerKind.shipped => _shippedFile,
    LayerKind.personal => _personalFile,
    LayerKind.project => _projectFile,
  };
  return DocTypeLayer.parse(
    text,
    file: file,
    docTypeId: docTypeId,
    kind: kind,
    folder: '/layer',
    files: const _NoFiles(),
  );
}

MergedDocType shipped() =>
    merger.apply(merger.builtInBase('feature'), layer(_shippedFeature));

MergedDocType project(MergedDocType base, String text) =>
    merger.apply(base, layer(text, kind: LayerKind.project));

TypeMatcher<TemplateFault> fault(FaultCode code, String key) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _projectFile)
        .having((f) => f.key, 'key', key);

List<String> ids(Iterable<Object> entries) => [
  for (final e in entries)
    switch (e) {
      MergedField(:final id) => id,
      MergedSection(:final id) => id,
      _ => throw ArgumentError(e),
    },
];

void main() {
  group('DocTypeMerger.builtInBase', () {
    test('f03/us02/fr04, f03/us02/fr04/e07, f03/us03/fr01/e15: a doc type with '
        'no fields still holds the four built-ins in order', () {
      final merged = merger.apply(
        merger.builtInBase('runbook'),
        layer('description: Runbook\n', docTypeId: 'runbook'),
      );

      expect(ids(merged.fields), ['slug', 'status', 'draft', 'reference']);
      expect(merged.fields.map((f) => f.type), [
        FieldType.string,
        FieldType.enumType,
        FieldType.boolean,
        FieldType.docRef,
      ]);
      expect(merged.fields.map((f) => f.list), [true, false, false, true]);
      expect(merged.fields[1].enumValues, [
        'planned',
        'implemented',
        'deprecated',
      ]);
    });
  });

  group('DocTypeMerger.apply', () {
    test('f03/us02/fr01/e01, f03/us02/s7: an incomplete new section is '
        'override_id_not_found', () {
      expect(
        () => project(shipped(), 'sections: [{id: goal_typo, description: x}]'),
        throwsA(fault(FaultCode.overrideIdNotFound, 'sections.goal_typo')),
      );
    });

    test('f03/us02/fr01/e02: a disabled entry for a missing section is '
        'override_id_not_found', () {
      expect(
        () => project(
          shipped(),
          'sections: [{id: nope, header: N, disabled: true}]',
        ),
        throwsA(fault(FaultCode.overrideIdNotFound, 'sections.nope')),
      );
    });

    test('f03/us02/fr01/e02: a disabled entry for a missing field is '
        'override_id_not_found', () {
      expect(
        () => project(shipped(), 'fields: [{id: nope, disabled: true}]'),
        throwsA(fault(FaultCode.overrideIdNotFound, 'fields.nope')),
      );
    });

    test('f03/us03/fr02/e02: a field with no type on a new doc type is '
        'override_id_not_found', () {
      expect(
        () => merger.apply(
          merger.builtInBase('runbook'),
          DocTypeLayer.parse(
            'description: Runbook\nfields: [{id: size}]',
            file: _projectFile,
            docTypeId: 'runbook',
            kind: LayerKind.project,
            folder: '/layer',
            files: const _NoFiles(),
          ),
        ),
        throwsA(fault(FaultCode.overrideIdNotFound, 'fields.size')),
      );
    });

    test('f03/us02/s1, f03/us02/fr01: disabled: true drops a section', () {
      final merged = project(
        shipped(),
        'sections: [{id: scope, disabled: true}]',
      );

      expect(ids(merged.sections), ['goal']);
    });

    test('f03/us02/s2, f03/us02/fr01: a complete new field is added last', () {
      final merged = project(shipped(), 'fields: [{id: size, type: integer}]');

      expect(ids(merged.fields), [
        'slug',
        'status',
        'draft',
        'reference',
        'owner',
        'size',
      ]);
      expect(merged.fields.last.type, FieldType.integer);
    });

    test('f03/us02/fr01: a complete new section is added last', () {
      final merged = project(
        shipped(),
        'sections: [{id: risks, header: Risks, required: true}]',
      );

      expect(ids(merged.sections), ['goal', 'scope', 'risks']);
      expect(merged.sections.last.header, 'Risks');
      expect(merged.sections.last.required, isTrue);
    });

    test('f03/us02/s4, f03/us02/fr01/e03: an override changes only the '
        'properties it writes', () {
      final merged = project(
        shipped(),
        'sections: [{id: goal, description: New}]',
      );

      final goal = merged.sections.first;
      expect(goal.description, 'New');
      expect(goal.header, 'Feature goal');
    });

    test('f03/us02/fr01/e04: the highest layer wins a property three layers '
        'write', () {
      var merged = merger.apply(
        merger.builtInBase('feature'),
        layer('''
sections:
  - id: goal
    header: Feature goal
    description: A
'''),
      );
      merged = merger.apply(
        merged,
        layer(
          'sections: [{id: goal, description: B}]',
          kind: LayerKind.personal,
        ),
      );
      merged = project(merged, 'sections: [{id: goal, description: C}]');

      expect(merged.sections.single.description, 'C');
      expect(merged.files, [_shippedFile, _personalFile, _projectFile]);
    });

    test(
      'f03/us02/fr01/e05: doc-level description and path replace the base',
      () {
        final merged = project(
          shipped(),
          'description: Other\npath: x/{slug}.md',
        );

        expect(merged.description, 'Other');
        expect(merged.path, 'x/{slug}.md');
      },
    );

    test('f03/us02/fr01/e05: doc-level keys a layer leaves out keep the base '
        'value', () {
      final merged = project(
        shipped(),
        'sections: [{id: goal, required: true}]',
      );

      expect(merged.description, 'A feature');
      expect(merged.path, 'docs/prds/{slug}/FEATURE.md');
    });

    for (final id in ['slug', 'status', 'draft', 'reference']) {
      test('f03/us02/s9, f03/us02/fr04/e01: disabling the built-in $id is '
          'locked_field_disabled', () {
        expect(
          () => project(shipped(), 'fields: [{id: $id, disabled: true}]'),
          throwsA(fault(FaultCode.lockedFieldDisabled, 'fields.$id')),
        );
      });
    }

    test('f03/us02/fr04/e06: changing the type of a built-in is '
        'locked_field_disabled', () {
      expect(
        () => project(shipped(), 'fields: [{id: draft, type: string}]'),
        throwsA(fault(FaultCode.lockedFieldDisabled, 'fields.draft')),
      );
    });

    test('f03/us02/fr04/e02: clearing a parent the base has is '
        'locked_field_disabled', () {
      final base = merger.apply(
        merger.builtInBase('feature'),
        layer('parent: project\n'),
      );

      expect(
        () => project(base, 'parent:\n'),
        throwsA(fault(FaultCode.lockedFieldDisabled, 'parent')),
      );
    });

    test('f03/us02/fr04/e04: a layer may change the parent to another doc '
        'type', () {
      final base = merger.apply(
        merger.builtInBase('feature'),
        layer('parent: project\n'),
      );

      expect(project(base, 'parent: epic\n').parent, 'epic');
    });

    test('f03/us02/fr04: a layer that does not write parent keeps the base '
        'parent', () {
      final base = merger.apply(
        merger.builtInBase('feature'),
        layer('parent: project\n'),
      );

      expect(project(base, 'description: Other\n').parent, 'project');
    });

    test('f03/us02/s6, f03/us02/fr04/e03: a layer may change the enum values '
        'of status', () {
      final merged = project(
        shipped(),
        'fields: [{id: status, enum: [planned, implemented]}]',
      );

      final status = merged.fields.firstWhere((f) => f.id == 'status');
      expect(status.enumValues, ['planned', 'implemented']);
      expect(status.type, FieldType.enumType);
    });

    test('f03/us02/fr04/e08: a layer may describe a built-in without '
        'changing its type', () {
      final merged = project(
        shipped(),
        'fields: [{id: slug, description: Search aliases}]',
      );

      final slug = merged.fields.first;
      expect(slug.description, 'Search aliases');
      expect(slug.type, FieldType.string);
      expect(slug.list, isTrue);
    });

    test('f03/us02/fr04: writing the built-in type again is not a change', () {
      final merged = project(
        shipped(),
        'fields: [{id: draft, type: boolean, description: Hidden}]',
      );

      expect(merged.fields[2].description, 'Hidden');
    });
  });
}
