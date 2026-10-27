import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/reference_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

const _file = '.specstone/templates/feature.yaml';

final class _FakeFiles implements LayerFiles {
  const new(this.paths);

  final Set<String> paths;

  @override
  bool exists(String layerRelativePath) => paths.contains(layerRelativePath);
}

DocTypeLayer _parse(String text) => DocTypeLayer.parse(
  text,
  file: _file,
  docTypeId: 'feature',
  kind: LayerKind.project,
  files: const _FakeFiles({'refs/handbook.md'}),
);

TypeMatcher<TemplateFault> _fault(FaultCode code, {String? key}) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _file)
        .having((f) => f.key, 'key', key);

void main() {
  group('DocTypeLayer.parse', () {
    test('f03/us03/fr01/e09, s03/inv15: an id unlike the file name is doc_type_id_mismatch', () {
      expect(
        () => _parse('id: epic\n'),
        throwsA(_fault(FaultCode.docTypeIdMismatch, key: 'id')),
      );
    });

    test('f03/us03/s4, f03/us03/fr01/e02, s03/inv10: a top-level unknown key is unknown_key', () {
      expect(
        () => _parse('color: red\n'),
        throwsA(_fault(FaultCode.unknownKey, key: 'color')),
      );
    });

    test('f03/us03/fr01/e02: an unknown section key is unknown_key with the id path', () {
      expect(
        () => _parse('sections: [{id: goal, colour: x}]'),
        throwsA(_fault(FaultCode.unknownKey, key: 'sections.goal.colour')),
      );
    });

    test(
      'f03/us03/fr01/e04: a camelCase section key is unknown_key by its name',
      () {
        expect(
          () => _parse('sections: [{id: goal, prefixId: PV-}]'),
          throwsA(_fault(FaultCode.unknownKey, key: 'sections.goal.prefixId')),
        );
      },
    );

    test('f03/us03/fr01/e03, s03/inv10: a field with no id is missing_key at the index', () {
      expect(
        () => _parse('fields: [{type: string}]'),
        throwsA(_fault(FaultCode.missingKey, key: 'fields[0].id')),
      );
    });

    test('f03/us03/s5, f03/us03/fr01/e03: a section with no id is missing_key at the index', () {
      expect(
        () => _parse('sections: [{header: Goal}]'),
        throwsA(_fault(FaultCode.missingKey, key: 'sections[0].id')),
      );
    });

    test('f03/us03/s10, f03/us03/fr01/e05, s03/inv13: a field type outside the seven is unknown_value', () {
      expect(
        () => _parse('fields: [{id: size, type: float}]'),
        throwsA(_fault(FaultCode.unknownValue, key: 'fields.size.type')),
      );
    });

    test('f03/us03/fr01/e06, s03/inv13: an enum field with no enum list is missing_key', () {
      expect(
        () => _parse('fields: [{id: kind, type: enum}]'),
        throwsA(_fault(FaultCode.missingKey, key: 'fields.kind.enum')),
      );
    });

    test('f03/us03/fr01/e16, s03/inv13: '
        'an output_ref field with no pointer is missing_key', () {
      expect(
        () => _parse('fields: [{id: covers, type: output_ref}]'),
        throwsA(_fault(FaultCode.missingKey, key: 'fields.covers.pointer')),
      );
    });

    test(
      'f03/us03/fr01/e17, s03/inv13: '
      'an output_ref pointer other than exact or prefix is unknown_value',
      () {
        expect(
          () =>
              _parse('fields: [{id: covers, type: output_ref, pointer: glob}]'),
          throwsA(_fault(FaultCode.unknownValue, key: 'fields.covers.pointer')),
        );
      },
    );

    test('f03/us03/fr01/e17, s03/inv13: '
        'an output_ref pointer that is not a string is unknown_value', () {
      expect(
        () => _parse('fields: [{id: covers, type: output_ref, pointer: 3}]'),
        throwsA(_fault(FaultCode.unknownValue, key: 'fields.covers.pointer')),
      );
    });

    test('f03/us03/fr01: an output_ref field reads its pointer kind', () {
      final layer = _parse(
        'fields: [{id: covers, type: output_ref, list: true, pointer: prefix}, '
        '{id: implements, type: output_ref, pointer: exact}]',
      );
      expect(layer.fields.map((f) => f.pointer), ['prefix', 'exact']);
    });

    test(
      'f03/us03/fr01/e18, s03/inv13: '
      'a pointer on a field of another type is accepted, whatever its kind',
      () {
        expect(
          _parse('fields: [{id: size, type: string, pointer: exact}]')
              .fields
              .single
              .pointer,
          'exact',
        );
        expect(
          _parse('fields: [{id: size, type: string, pointer: glob}]')
              .fields
              .single
              .pointer,
          'glob',
        );
      },
    );

    test('f03/us03/fr01/e18, s03/inv13: '
        'a pointer that is not a string on a field of another type '
        'is accepted', () {
      expect(
        _parse('fields: [{id: size, type: string, pointer: 3}]')
            .fields
            .single
            .pointer,
        3,
      );
    });

    test('f03/us02/fr01: an override entry may write pointer with no type; '
        'its kind is checked at merge', () {
      final layer = _parse('fields: [{id: covers, pointer: glob}]');
      expect(layer.fields.single.type, isNull);
      expect(layer.fields.single.pointer, 'glob');
    });

    test('f03/us02/fr03/e01: an unknown doc lint key is unknown_key', () {
      expect(
        () => _parse('lint: {max_words: 3}'),
        throwsA(_fault(FaultCode.unknownKey, key: 'lint.max_words')),
      );
    });

    test('f03/us02/fr03/e02: an unknown section lint key is unknown_key', () {
      expect(
        () => _parse('sections: [{id: goal, header: G, lint: {max_words: 3}}]'),
        throwsA(
          _fault(FaultCode.unknownKey, key: 'sections.goal.lint.max_words'),
        ),
      );
    });

    test('f03/us02/fr03, f03/us03/fr01: a section lint holds banned_words, '
        'allowed_words, and line_prefix', () {
      final lint = _parse(
        'sections: [{id: goal, header: G, lint: {banned_words: [fast], '
        'allowed_words: {add: [API]}, line_prefix: "- **Statement:**"}}]',
      ).sections.single.lint!;
      expect((lint.bannedWords! as PlainList<String>).items, ['fast']);
      expect((lint.allowedWords! as ListChange<String>).add, ['API']);
      expect(lint.linePrefix, '- **Statement:**');
    });

    test('f03/us02/fr03/e09: a section line_prefix that is not a string is '
        'unknown_value', () {
      expect(
        () =>
            _parse('sections: [{id: goal, header: G, lint: {line_prefix: 3}}]'),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'sections.goal.lint.line_prefix'),
        ),
      );
    });

    test('f03/us03/fr01/e10: an override file with no id is accepted', () {
      final layer = _parse('sections: [{id: goal, description: New}]');
      expect(layer.id, isNull);
      expect(layer.docTypeId, 'feature');
    });

    test('f03/us03/fr01: a full file reads back every value', () {
      final layer = _parse('''
id: feature
description: A feature spec
path: docs/features/{nn}-{slug}.md
parent: epic
extends: task
fields:
  - id: impact
    type: string
    list: true
    required: false
    enum: [low, high]
    doc_types: [feature]
    description: Who feels it
    disabled: false
sections:
  - id: goal
    prefix_id: goal-
    required: false
    header: Goal
    description: What winning looks like
    template: The goal is {slug}
    lint: {max_chars: 400, max_lines: 5}
    after: context
    disabled: false
lint:
  max_chars: 500
  max_lines: 6
  banned_words: [very, really]
  allowed_words: [crisp]
''');
      expect(layer.id, 'feature');
      expect(layer.description, 'A feature spec');
      expect(layer.path, 'docs/features/{nn}-{slug}.md');
      expect(layer.writesParent, isTrue);
      expect(layer.parent, 'epic');
      expect(layer.extendsId, 'task');
      expect(layer.file, _file);
      expect(layer.kind, LayerKind.project);

      final field = layer.fields.single;
      expect(field.id, 'impact');
      expect(field.type, FieldType.string);
      expect(field.list, isTrue);
      expect(field.required, isFalse);
      expect(field.enumValues, ['low', 'high']);
      expect(field.docTypes, ['feature']);
      expect(field.description, 'Who feels it');
      expect(field.disabled, isFalse);

      final section = layer.sections.single;
      expect(section.id, 'goal');
      expect(section.prefixId, 'goal-');
      expect(section.required, isFalse);
      expect(section.header, 'Goal');
      expect(section.description, 'What winning looks like');
      expect(section.template, 'The goal is {slug}');
      expect(section.lint?.maxChars, 400);
      expect(section.lint?.maxLines, 5);
      expect(section.after, 'context');
      expect(section.disabled, isFalse);

      final lint = layer.lint!;
      expect(lint.maxChars, 500);
      expect(lint.maxLines, 6);
      final banned = switch (lint.bannedWords) {
        final PlainList<String> plain => plain,
        _ => fail('banned_words is not a PlainList'),
      };
      final allowed = switch (lint.allowedWords) {
        final PlainList<String> plain => plain,
        _ => fail('allowed_words is not a PlainList'),
      };
      expect(banned.items, ['very', 'really']);
      expect(allowed.items, ['crisp']);
    });

    test('f03/us03/fr01: an add/remove map reads as a ListChange', () {
      final layer = _parse('lint: {banned_words: {add: [x], remove: [y]}}');
      final change = switch (layer.lint?.bannedWords) {
        final ListChange<String> listChange => listChange,
        _ => fail('banned_words is not a ListChange'),
      };
      expect(change.add, ['x']);
      expect(change.remove, ['y']);
    });

    test(
      'f03/us03/fr01: an add-only map reads as a ListChange with no remove',
      () {
        final layer = _parse('lint: {allowed_words: {add: [x]}}');
        final change = switch (layer.lint?.allowedWords) {
          final ListChange<String> listChange => listChange,
          _ => fail('allowed_words is not a ListChange'),
        };
        expect(change.add, ['x']);
        expect(change.remove, isEmpty);
      },
    );

    test(
      'f03/us03/fr01: a remove-only map reads as a ListChange with no add',
      () {
        final layer = _parse('lint: {allowed_words: {remove: [y]}}');
        final change = switch (layer.lint?.allowedWords) {
          final ListChange<String> listChange => listChange,
          _ => fail('allowed_words is not a ListChange'),
        };
        expect(change.add, isEmpty);
        expect(change.remove, ['y']);
      },
    );

    test(
      'f03/us03/fr01/e02: an unknown key in an add/remove map is unknown_key',
      () {
        expect(
          () => _parse('lint: {banned_words: {add: [x], drop: [y]}}'),
          throwsA(_fault(FaultCode.unknownKey, key: 'lint.banned_words.drop')),
        );
      },
    );

    test('f03/us03/fr01/e05: a scalar word list is unknown_value', () {
      expect(
        () => _parse('lint: {banned_words: loud}'),
        throwsA(_fault(FaultCode.unknownValue, key: 'lint.banned_words')),
      );
    });

    test(
      'f03/us03/fr01/e05: a non-string entry in a word list is unknown_value',
      () {
        expect(
          () => _parse('lint: {banned_words: [[loud]]}'),
          throwsA(_fault(FaultCode.unknownValue, key: 'lint.banned_words')),
        );
      },
    );

    test(
      'f03/us03/fr01/e05: a scalar field entry is unknown_value at the index',
      () {
        expect(
          () => _parse('fields: [free]'),
          throwsA(_fault(FaultCode.unknownValue, key: 'fields[0]')),
        );
      },
    );

    test('f03/us03/fr01: parent with no value marks a cleared parent', () {
      final layer = _parse('parent:\n');
      expect(layer.writesParent, isTrue);
      expect(layer.parent, isNull);
    });

    test('f03/us03/fr01: reference is read past as a top-level key', () {
      final layer = _parse('reference: [{title: Specstone}]');
      expect(layer.id, isNull);
    });

    test('f03/us03/fr03: a plain reference list parses into entries', () {
      final layer = _parse(
        'reference: [{title: T, url: https://example.com/a}, '
        '{title: Book}]',
      );
      final plain = switch (layer.reference) {
        final PlainList<ReferenceEntry> list => list,
        _ => fail('reference is not a PlainList'),
      };
      expect(plain.items, hasLength(2));
      expect(plain.items.first.url, 'https://example.com/a');
      expect(plain.items.last.toJson(), {'title': 'Book'});
    });

    test(
      'f03/us02/fr05, f03/us03/fr03/e09: a reference add map parses entries',
      () {
        final layer = _parse(
          'reference: {add: [{title: T, file: refs/handbook.md}], '
          'remove: [Book]}',
        );
        final change = switch (layer.reference) {
          final ListChange<ReferenceEntry> listChange => listChange,
          _ => fail('reference is not a ListChange'),
        };
        expect(change.add.single.file, 'refs/handbook.md');
        expect(change.remove, ['Book']);
      },
    );

    test(
      'f03/us03/fr03/e02: a link conflict inside parse keeps its index key',
      () {
        expect(
          () => _parse(
            'reference: [{title: T}, {title: U, url: https://x, doc: d}]',
          ),
          throwsA(_fault(FaultCode.referenceLinkConflict, key: 'reference[1]')),
        );
      },
    );

    test('f03/us03/fr01, tpl-s03/inv23: bundle and a section query are read as written', () {
      final layer = _parse(
        'bundle: [query, implement]\nsections: [{id: goal, query: true}]\n',
      );
      expect((layer.bundle! as PlainList<String>).items, [
        'query',
        'implement',
      ]);
      expect(layer.sections.single.query, isTrue);
    });

    test('f03/us03/fr01: a bundle add and remove mapping is a ListChange', () {
      final change =
          _parse('bundle: {add: [design], remove: [query]}\n').bundle!
              as ListChange<String>;
      expect(change.add, ['design']);
      expect(change.remove, ['query']);
    });

    test('f03/us03/fr01/e19, tpl-s03/inv23: a bundle entry outside the three modes is unknown_value', () {
      expect(
        () => _parse('bundle: [query, deploy]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'bundle')),
      );
      expect(
        () => _parse('bundle: {add: [deploy]}\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'bundle')),
      );
    });

    test('f03/us03/fr01/e19, tpl-s03/inv23: a section query that is not a boolean is unknown_value', () {
      expect(
        () => _parse('sections: [{id: goal, query: yes please}]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'sections.goal.query')),
      );
    });

    test('f03/us03/fr01: a layer that writes neither key leaves both null', () {
      final layer = _parse('sections: [{id: goal}]\n');
      expect(layer.bundle, isNull);
      expect(layer.sections.single.query, isNull);
    });
  });

  group('isDocTypeFileName', () {
    test('f03/us03/fr01: a top-level id yaml file is a doc type', () {
      expect(isDocTypeFileName('feature.yaml'), isTrue);
    });

    test('f03/us03/fr01: pack.yaml is not a doc type', () {
      expect(isDocTypeFileName('pack.yaml'), isFalse);
    });

    test('f03/us03/fr01: a non-yaml file is not a doc type', () {
      expect(isDocTypeFileName('notes.md'), isFalse);
    });

    test('f03/us03/fr01: a nested file is not a doc type', () {
      expect(isDocTypeFileName('refs/x.yaml'), isFalse);
    });
  });
}
