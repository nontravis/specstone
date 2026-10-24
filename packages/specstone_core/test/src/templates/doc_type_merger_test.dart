import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
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
    files: const _NoFiles(),
  );
}

MergedDocType shipped() =>
    merger.apply(merger.builtInBase('feature'), layer(_shippedFeature));

MergedDocType project(MergedDocType base, String text) =>
    merger.apply(base, layer(text, kind: LayerKind.project));

TypeMatcher<TemplateFault> fault(
  FaultCode code,
  String key, {
  String? message,
}) {
  final matcher = isA<TemplateFault>()
      .having((f) => f.code, 'code', code)
      .having((f) => f.file, 'file', _projectFile)
      .having((f) => f.key, 'key', key);
  return message == null
      ? matcher
      : matcher.having((f) => f.message, 'message', message);
}

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
    test('f03/us02/fr04, f03/us02/fr04/e07, f03/us03/fr01/e15, s03/inv12, s03/inv20: a doc type with '
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
    test(
      'f03/us02/fr01/e01, f03/us02/s7, s03/inv2: an incomplete new section is '
      'override_id_not_found',
      () {
        expect(
          () =>
              project(shipped(), 'sections: [{id: goal_typo, description: x}]'),
          throwsA(
            fault(
              FaultCode.overrideIdNotFound,
              'sections.goal_typo',
              message:
                  'no section "goal_typo" in the merged doc type and no '
                  'header to add it',
            ),
          ),
        );
      },
    );

    test(
      'f03/us02/fr01/e02, s03/inv2: a disabled entry for a missing section is '
      'override_id_not_found',
      () {
        expect(
          () => project(
            shipped(),
            'sections: [{id: nope, header: N, disabled: true}]',
          ),
          throwsA(
            fault(
              FaultCode.overrideIdNotFound,
              'sections.nope',
              message: 'no section "nope" in the merged doc type to disable',
            ),
          ),
        );
      },
    );

    test('f03/us02/fr01/e02, s03/inv2: a disabled entry for a missing field is '
        'override_id_not_found', () {
      expect(
        () => project(shipped(), 'fields: [{id: nope, disabled: true}]'),
        throwsA(
          fault(
            FaultCode.overrideIdNotFound,
            'fields.nope',
            message: 'no field "nope" in the merged doc type to disable',
          ),
        ),
      );
    });

    test(
      'f03/us03/fr02/e02, s03/inv2: a field with no type on a new doc type is '
      'override_id_not_found',
      () {
        expect(
          () => merger.apply(
            merger.builtInBase('runbook'),
            DocTypeLayer.parse(
              'description: Runbook\nfields: [{id: size}]',
              file: _projectFile,
              docTypeId: 'runbook',
              kind: LayerKind.project,
              files: const _NoFiles(),
            ),
          ),
          throwsA(
            fault(
              FaultCode.overrideIdNotFound,
              'fields.size',
              message:
                  'no field "size" in the merged doc type and no type to '
                  'add it',
            ),
          ),
        );
      },
    );

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

    test('f03/us02/s3, f03/us02/fr02, s03/inv3: an added section lands right after the '
        'section its after names', () {
      final merged = project(
        shipped(),
        'sections: [{id: risks, header: Risks, after: goal}]',
      );

      expect(ids(merged.sections), ['goal', 'risks', 'scope']);
    });

    test('f03/us02/fr02/e02: an added section with no after goes last', () {
      final merged = project(
        shipped(),
        'sections: [{id: risks, header: Risks}]',
      );

      expect(ids(merged.sections), ['goal', 'scope', 'risks']);
    });

    test(
      'f03/us02/fr02/e03, s03/inv3: after on a held section moves it and keeps '
      'merging its other properties',
      () {
        final merged = project(
          shipped(),
          'sections: [{id: goal, after: scope, description: D}]',
        );

        expect(ids(merged.sections), ['scope', 'goal']);
        final goal = merged.sections.last;
        expect(goal.description, 'D');
        expect(goal.header, 'Feature goal');
      },
    );

    test('f03/us02/fr02/e03: after naming the section itself leaves it in '
        'place', () {
      final merged = project(
        shipped(),
        'sections: [{id: goal, after: goal, description: D}]',
      );

      expect(ids(merged.sections), ['goal', 'scope']);
      expect(merged.sections.first.description, 'D');
    });

    test('f03/us02/s8, f03/us02/fr02/e01, s03/inv3: an added section after a missing '
        'id is after_id_not_found', () {
      expect(
        () => project(
          shipped(),
          'sections: [{id: risks, header: Risks, after: nope}]',
        ),
        throwsA(fault(FaultCode.afterIdNotFound, 'sections.risks.after')),
      );
    });

    test(
      'f03/us02/fr02/e01, s03/inv3: a held section moved after a missing id is '
      'after_id_not_found',
      () {
        expect(
          () => project(shipped(), 'sections: [{id: goal, after: nope}]'),
          throwsA(fault(FaultCode.afterIdNotFound, 'sections.goal.after')),
        );
      },
    );

    test('f03/us02/fr02: entries of one layer place in file order, so a '
        'later entry may follow an earlier one', () {
      final merged = project(shipped(), '''
sections:
  - id: risks
    header: Risks
    after: goal
  - id: notes
    header: Notes
    after: risks
''');

      expect(ids(merged.sections), ['goal', 'risks', 'notes', 'scope']);
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
      test(
        'f03/us02/s9, f03/us02/fr04/e01, s03/inv1, s03/inv20: disabling the built-in $id is '
        'locked_field_disabled',
        () {
          expect(
            () => project(shipped(), 'fields: [{id: $id, disabled: true}]'),
            throwsA(fault(FaultCode.lockedFieldDisabled, 'fields.$id')),
          );
        },
      );
    }

    test('f03/us02/fr04/e06, s03/inv1, s03/inv20: changing the type of a built-in is '
        'locked_field_disabled', () {
      expect(
        () => project(shipped(), 'fields: [{id: draft, type: string}]'),
        throwsA(fault(FaultCode.lockedFieldDisabled, 'fields.draft')),
      );
    });

    test('f03/us02/fr04/e02, s03/inv1: clearing a parent the base has is '
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

    test('f03/us02/fr04/e04, s03/inv1: a layer may change the parent to another doc '
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

    test('f03/us02/s6, f03/us02/fr04/e03, s03/inv1: a layer may change the enum values '
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

    test('f03/us02/fr04: changing enum to string drops the enum list', () {
      final base = merger.apply(
        merger.builtInBase('feature'),
        layer('fields: [{id: kind, type: enum, enum: [a, b]}]'),
      );

      final merged = project(base, 'fields: [{id: kind, type: string}]');

      final kind = merged.fields.singleWhere((f) => f.id == 'kind');
      expect(kind.type, FieldType.string);
      expect(kind.enumValues, isNull);
    });

    test('f03/us02/fr04: changing doc_ref to string drops doc_types', () {
      final base = merger.apply(
        merger.builtInBase('feature'),
        layer('fields: [{id: parent, type: doc_ref, doc_types: [epic]}]'),
      );

      final merged = project(base, 'fields: [{id: parent, type: string}]');

      final parent = merged.fields.singleWhere((f) => f.id == 'parent');
      expect(parent.type, FieldType.string);
      expect(parent.docTypes, isNull);
    });

    test('f03/us02/fr04: changing a type keeps the lists the layer writes', () {
      final base = merger.apply(
        merger.builtInBase('feature'),
        layer('fields: [{id: kind, type: string}]'),
      );

      final merged = project(
        base,
        'fields: [{id: kind, type: enum, enum: [x, y]}]',
      );

      final kind = merged.fields.singleWhere((f) => f.id == 'kind');
      expect(kind.enumValues, ['x', 'y']);
    });

    test(
      'f03/us02/fr04: a layer that leaves the type alone keeps the lists',
      () {
        final base = merger.apply(
          merger.builtInBase('feature'),
          layer('fields: [{id: kind, type: enum, enum: [a, b]}]'),
        );

        final merged = project(base, 'fields: [{id: kind, description: Kind}]');

        final kind = merged.fields.singleWhere((f) => f.id == 'kind');
        expect(kind.enumValues, ['a', 'b']);
        expect(kind.description, 'Kind');
      },
    );

    test('f03/us02/fr04: writing the built-in type again is not a change', () {
      final merged = project(
        shipped(),
        'fields: [{id: draft, type: boolean, description: Hidden}]',
      );

      expect(merged.fields[2].description, 'Hidden');
    });

    test('f03/us02/s2, f03/us03/fr01: a new output_ref field keeps its '
        'pointer', () {
      final merged = project(
        shipped(),
        'fields: [{id: covers, type: output_ref, list: true, pointer: prefix}]',
      );

      expect(merged.fields.last.pointer, PointerKind.prefix);
    });

    test('f03/us02/fr01: an override that writes only pointer changes the '
        'kind', () {
      final base = project(
        shipped(),
        'fields: [{id: covers, type: output_ref, pointer: prefix}]',
      );

      final covers = project(
        base,
        'fields: [{id: covers, pointer: exact}]',
      ).fields.singleWhere((f) => f.id == 'covers');

      expect(covers.type, FieldType.outputRef);
      expect(covers.pointer, PointerKind.exact);
    });

    test('f03/us03/fr01/e17: a typeless override with a pointer other than '
        'exact or prefix over an output_ref field is unknown_value', () {
      final base = project(
        shipped(),
        'fields: [{id: covers, type: output_ref, pointer: prefix}]',
      );

      expect(
        () => project(base, 'fields: [{id: covers, pointer: glob}]'),
        throwsA(fault(FaultCode.unknownValue, 'fields.covers.pointer')),
      );
    });

    test('f03/us03/fr01/e17: a typeless override with a non-string pointer '
        'over an output_ref field is unknown_value', () {
      final base = project(
        shipped(),
        'fields: [{id: covers, type: output_ref, pointer: prefix}]',
      );

      expect(
        () => project(base, 'fields: [{id: covers, pointer: 3}]'),
        throwsA(fault(FaultCode.unknownValue, 'fields.covers.pointer')),
      );
    });

    test('f03/us03/fr01/e18: a pointer on a field of another type has no '
        'effect, whatever its kind', () {
      final added = project(
        shipped(),
        'fields: [{id: size, type: string, pointer: glob}]',
      );
      final overridden = project(
        shipped(),
        'fields: [{id: owner, pointer: glob}]',
      );

      expect(added.fields.last.pointer, isNull);
      expect(
        overridden.fields.singleWhere((f) => f.id == 'owner').pointer,
        isNull,
      );
    });

    test('f03/us03/fr01/e18: a field turned from output_ref to another type '
        'drops its pointer', () {
      final base = project(
        shipped(),
        'fields: [{id: covers, type: output_ref, pointer: prefix}]',
      );

      final covers = project(
        base,
        'fields: [{id: covers, type: string}]',
      ).fields.singleWhere((f) => f.id == 'covers');

      expect(covers.pointer, isNull);
    });
  });

  group('DocTypeMerger.apply lint', () {
    MergedDocType withBannedWords() =>
        project(shipped(), 'lint: {banned_words: [fast, robust]}');

    test('f03/us02/s5, f03/us02/fr03/e03, s03/inv17: add and remove change a lower '
        'word list', () {
      final merged = project(
        withBannedWords(),
        'lint: {banned_words: {add: [simply], remove: [fast]}}',
      );

      expect(merged.lint.bannedWords, ['robust', 'simply']);
    });

    test('f03/us02/fr03/e05, s03/inv17: removing a word the base lacks is '
        'lint_word_not_found', () {
      expect(
        () => project(
          withBannedWords(),
          'lint: {banned_words: {remove: [quick]}}',
        ),
        throwsA(fault(FaultCode.lintWordNotFound, 'lint.banned_words')),
      );
    });

    test('f03/us02/fr03/e05, s03/inv17: removing an allowed word the base lacks names '
        'lint.allowed_words', () {
      expect(
        () => project(shipped(), 'lint: {allowed_words: {remove: [API]}}'),
        throwsA(fault(FaultCode.lintWordNotFound, 'lint.allowed_words')),
      );
    });

    test('f03/us02/fr03/e06, s03/inv17: a plain list over a defined list is '
        'list_override_needs_add_remove', () {
      expect(
        () => project(withBannedWords(), 'lint: {banned_words: [x]}'),
        throwsA(
          fault(FaultCode.listOverrideNeedsAddRemove, 'lint.banned_words'),
        ),
      );
    });

    test('f03/us02/fr03/e06, s03/inv17: a plain allowed_words list over a defined list '
        'names lint.allowed_words', () {
      final base = project(shipped(), 'lint: {allowed_words: [API]}');

      expect(
        () => project(base, 'lint: {allowed_words: [UI]}'),
        throwsA(
          fault(FaultCode.listOverrideNeedsAddRemove, 'lint.allowed_words'),
        ),
      );
    });

    test('f03/us02/fr03/e07, s03/inv17: a plain list is accepted where no lower layer '
        'defines it', () {
      final merged = project(shipped(), 'lint: {allowed_words: [API]}');

      expect(merged.lint.allowedWords, ['API']);
      expect(merged.lint.bannedWords, isNull);
    });

    test('f03/us02/fr03/e07, s03/inv17: add on an undefined list starts from empty', () {
      final merged = project(shipped(), 'lint: {banned_words: {add: [fast]}}');

      expect(merged.lint.bannedWords, ['fast']);
    });

    test('f03/us02/fr03: a layer max_lines replaces the base and keeps the '
        'other limit', () {
      final base = project(
        shipped(),
        'lint: {max_chars: 12000, max_lines: 300}',
      );

      final merged = project(base, 'lint: {max_lines: 200}');

      expect(merged.lint.maxChars, 12000);
      expect(merged.lint.maxLines, 200);
    });

    test('f03/us02/fr03: a layer max_chars replaces the base and keeps the '
        'other limit', () {
      final base = project(
        shipped(),
        'lint: {max_chars: 12000, max_lines: 300}',
      );

      final merged = project(base, 'lint: {max_chars: 8000}');

      expect(merged.lint.maxChars, 8000);
      expect(merged.lint.maxLines, 300);
    });

    test('f03/us02/fr03/e04: a section keeps its own lint and an unwritten '
        'one stays null', () {
      final merged = project(
        shipped(),
        'sections: [{id: goal, lint: {max_lines: 5}}]',
      );

      expect(merged.sections.firstWhere((s) => s.id == 'goal').maxLines, 5);
      expect(
        merged.sections.firstWhere((s) => s.id == 'scope').maxLines,
        isNull,
      );
    });

    test('f03/us02/fr03: a layer with no lint keeps the base lint', () {
      final base = project(withBannedWords(), 'lint: {max_chars: 100}');

      final merged = project(base, 'description: Other\n');

      expect(merged.lint.maxChars, 100);
      expect(merged.lint.bannedWords, ['fast', 'robust']);
    });
  });

  group('DocTypeMerger.apply reference', () {
    MergedDocType withReferences() =>
        project(shipped(), 'reference: [{title: A}, {title: B}]');

    List<String> titles(MergedDocType type) => [
      for (final entry in type.reference!) entry.title,
    ];

    test(
      'f03/us02/s10, f03/us02/fr05, s03/inv14: add and remove change the lower '
      'reference list',
      () {
        final merged = project(
          withReferences(),
          'reference: {add: [{title: C}], remove: [A]}',
        );

        expect(titles(merged), ['B', 'C']);
      },
    );

    test('f03/us02/s11, f03/us02/fr05/e01, s03/inv14: removing a title the base lacks '
        'is reference_title_not_found', () {
      expect(
        () => project(withReferences(), 'reference: {remove: [Z]}'),
        throwsA(fault(FaultCode.referenceTitleNotFound, 'reference')),
      );
    });

    test('f03/us02/fr05/e02: a layer with no reference keeps the base', () {
      final merged = project(withReferences(), 'description: Other\n');

      expect(titles(merged), ['A', 'B']);
    });

    test('f03/us02/fr05/e04, s03/inv14: a plain list over a defined list is '
        'list_override_needs_add_remove', () {
      expect(
        () => project(withReferences(), 'reference: [{title: D}]'),
        throwsA(fault(FaultCode.listOverrideNeedsAddRemove, 'reference')),
      );
    });

    test(
      'f03/us02/fr05, s03/inv14: a plain list is accepted where no lower layer '
      'defines it',
      () {
        expect(titles(withReferences()), ['A', 'B']);
      },
    );

    test('f03/us02/fr05, s03/inv14: add over a base with no reference list gives exactly '
        'the added entries', () {
      final merged = project(shipped(), 'reference: {add: [{title: C}]}');

      expect(titles(merged), ['C']);
    });
  });

  group('DocTypeMerger.apply result lists', () {
    const richLayer = '''
fields:
  - id: kind
    type: enum
    enum: [a, b]
  - id: link
    type: doc_ref
    doc_types: [epic]
sections:
  - id: risks
    header: Risks
lint:
  banned_words: [fast]
  allowed_words: [ok]
reference: [{title: A}]
''';

    void expectFrozen(MergedDocType merged) {
      final kind = merged.fields.firstWhere((f) => f.id == 'kind');
      final link = merged.fields.firstWhere((f) => f.id == 'link');

      expect(() => merged.fields.add(kind), throwsUnsupportedError);
      expect(
        () => merged.sections.add(merged.sections.first),
        throwsUnsupportedError,
      );
      expect(() => merged.files.add('x'), throwsUnsupportedError);
      expect(
        () => merged.reference!.add(merged.reference!.first),
        throwsUnsupportedError,
      );
      expect(() => merged.lint.bannedWords!.add('x'), throwsUnsupportedError);
      expect(() => merged.lint.allowedWords!.add('x'), throwsUnsupportedError);
      expect(() => kind.enumValues!.add('x'), throwsUnsupportedError);
      expect(() => link.docTypes!.add('x'), throwsUnsupportedError);
    }

    test('lists of a doc type built from plain lists are unmodifiable', () {
      expectFrozen(
        merger.apply(merger.builtInBase('feature'), layer(richLayer)),
      );
    });

    test('lists of a doc type built from add and remove are unmodifiable', () {
      final base = merger.apply(
        merger.builtInBase('feature'),
        layer(richLayer),
      );

      expectFrozen(
        project(
          base,
          'lint: {banned_words: {add: [slow]}, allowed_words: {add: [fine]}}\n'
          'reference: {add: [{title: B}]}',
        ),
      );
    });
  });
}
