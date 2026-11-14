import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
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
    for (final kind in LayerKind.values) {
      test('a ${kind.name} '
          'file name that is no slug is unknown_value before '
          'doc_type_id_mismatch', () {
        for (final name in ['Grid', 'api-v2']) {
          final file = '.specstone/templates/$name.yaml';
          expect(
            () => DocTypeLayer.parse(
              'id: epic\n',
              file: file,
              docTypeId: name,
              kind: kind,
              files: const _FakeFiles({}),
            ),
            throwsA(
              isA<TemplateFault>()
                  .having((f) => f.code, 'code', FaultCode.unknownValue)
                  .having((f) => f.file, 'file', file)
                  .having((f) => f.key, 'key', 'id'),
            ),
            reason: name,
          );
        }
      });
    }

    test('a slug file name '
        'loads', () {
      expect(_parse('max_depth: 1\n').docTypeId, 'feature');
    });

    test('E32, INV-30: '
        'per_target reads a boolean', () {
      expect(_parse('per_target: true\n').perTarget, isTrue);
      expect(_parse('per_target: false\n').perTarget, isFalse);
      expect(_parse('path: a/{slug}.md\n').perTarget, isNull);
    });

    test('E32, INV-30: '
        'a per_target that is not a boolean is unknown_value', () {
      expect(
        () => _parse('per_target: yes please\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'per_target')),
      );
    });

    test('template_packs/add_doc_type/read_doc_type_file, INV-13: '
        'record_status is an accepted field type', () {
      final layer = _parse('fields: [{id: status_of, type: record_status}]');
      expect(layer.fields.single.type, FieldType.recordStatus);
    });

    test('E17, INV-13: '
        'item_exact is an accepted pointer kind', () {
      final layer = _parse(
        'fields: [{id: implements, type: output_ref, pointer: item_exact}]',
      );
      expect(layer.fields.single.pointer, 'item_exact');
    });

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

    test('max_depth reads an integer from 0 and refuses -1 '
        'and three', () {
      expect(_parse('max_depth: 3\n').maxDepth, 3);
      expect(_parse('max_depth: 0\n').maxDepth, 0);
      expect(_parse('path: a/{slug}/A.md\n').maxDepth, isNull);
      for (final value in ['-1', 'three']) {
        expect(
          () => _parse('max_depth: $value\n'),
          throwsA(
            _fault(FaultCode.unknownValue, key: 'max_depth').having(
              (f) => f.message,
              'message',
              'max_depth takes an integer from 0',
            ),
          ),
        );
      }
    });

    test('f03/us03/fr01/e28, is-s03/inv4: a section id starting with _ is unknown_value', () {
      expect(
        () => _parse('sections: [{id: _notes}]'),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'sections[0].id').having(
            (f) => f.message,
            'message',
            'a section id must not start with _, '
                'which marks a reserved key such as _lead',
          ),
        ),
      );
    });

    test('an unknown section key is unknown_key with the id path', () {
      expect(
        () => _parse('sections: [{id: goal, colour: x}]'),
        throwsA(_fault(FaultCode.unknownKey, key: 'sections.goal.colour')),
      );
    });

    test('a camelCase section key is unknown_key by its name', () {
      expect(
        () => _parse('sections: [{id: goal, prefixId: PV-}]'),
        throwsA(_fault(FaultCode.unknownKey, key: 'sections.goal.prefixId')),
      );
    });

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

    test('an output_ref field reads its pointer kind', () {
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

    test('an override entry may write pointer with no type; '
        'its kind is checked at merge', () {
      final layer = _parse('fields: [{id: covers, pointer: glob}]');
      expect(layer.fields.single.type, isNull);
      expect(layer.fields.single.pointer, 'glob');
    });

    test('an unknown doc lint key is unknown_key', () {
      expect(
        () => _parse('lint: {max_words: 3}'),
        throwsA(_fault(FaultCode.unknownKey, key: 'lint.max_words')),
      );
    });

    test('an unknown section lint key is unknown_key', () {
      expect(
        () => _parse('sections: [{id: goal, header: G, lint: {max_words: 3}}]'),
        throwsA(
          _fault(FaultCode.unknownKey, key: 'sections.goal.lint.max_words'),
        ),
      );
    });

    test('Override lint settings '
        'Input: a doc-level lint.max_item_chars reads as written', () {
      expect(_parse('lint: {max_item_chars: 900}').lint?.maxItemChars, 900);
      expect(_parse('lint: {max_chars: 400}').lint?.maxItemChars, isNull);
    });

    test('Override lint settings '
        'E16: a section lint that writes max_item_chars is unknown_key', () {
      expect(
        () => _parse(
          'sections: [{id: goal, header: G, lint: {max_item_chars: 900}}]',
        ),
        throwsA(
          _fault(
            FaultCode.unknownKey,
            key: 'sections.goal.lint.max_item_chars',
          ),
        ),
      );
    });

    test('Override lint settings '
        'Input: a non-integer lint.max_item_chars is unknown_value like '
        'max_chars', () {
      expect(
        () => _parse('lint: {max_item_chars: many}'),
        throwsA(_fault(FaultCode.unknownValue, key: 'lint.max_item_chars')),
      );
      expect(
        () => _parse('lint: {max_chars: many}'),
        throwsA(_fault(FaultCode.unknownValue, key: 'lint.max_chars')),
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

    test('a section line_prefix that is not a string is '
        'unknown_value', () {
      expect(
        () =>
            _parse('sections: [{id: goal, header: G, lint: {line_prefix: 3}}]'),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'sections.goal.lint.line_prefix'),
        ),
      );
    });

    test('an override file with no id is accepted', () {
      final layer = _parse('sections: [{id: goal, description: New}]');
      expect(layer.id, isNull);
      expect(layer.docTypeId, 'feature');
    });

    test('a full file reads back every value', () {
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

    test('an add/remove map reads as a ListChange', () {
      final layer = _parse('lint: {banned_words: {add: [x], remove: [y]}}');
      final change = switch (layer.lint?.bannedWords) {
        final ListChange<String> listChange => listChange,
        _ => fail('banned_words is not a ListChange'),
      };
      expect(change.add, ['x']);
      expect(change.remove, ['y']);
    });

    test('an add-only map reads as a ListChange with no remove', () {
      final layer = _parse('lint: {allowed_words: {add: [x]}}');
      final change = switch (layer.lint?.allowedWords) {
        final ListChange<String> listChange => listChange,
        _ => fail('allowed_words is not a ListChange'),
      };
      expect(change.add, ['x']);
      expect(change.remove, isEmpty);
    });

    test('a remove-only map reads as a ListChange with no add', () {
      final layer = _parse('lint: {allowed_words: {remove: [y]}}');
      final change = switch (layer.lint?.allowedWords) {
        final ListChange<String> listChange => listChange,
        _ => fail('allowed_words is not a ListChange'),
      };
      expect(change.add, isEmpty);
      expect(change.remove, ['y']);
    });

    test('an unknown key in an add/remove map is unknown_key', () {
      expect(
        () => _parse('lint: {banned_words: {add: [x], drop: [y]}}'),
        throwsA(_fault(FaultCode.unknownKey, key: 'lint.banned_words.drop')),
      );
    });

    test('a scalar word list is unknown_value', () {
      expect(
        () => _parse('lint: {banned_words: loud}'),
        throwsA(_fault(FaultCode.unknownValue, key: 'lint.banned_words')),
      );
    });

    test('a non-string entry in a word list is unknown_value', () {
      expect(
        () => _parse('lint: {banned_words: [[loud]]}'),
        throwsA(_fault(FaultCode.unknownValue, key: 'lint.banned_words')),
      );
    });

    test('a scalar field entry is unknown_value at the index', () {
      expect(
        () => _parse('fields: [free]'),
        throwsA(_fault(FaultCode.unknownValue, key: 'fields[0]')),
      );
    });

    test('parent with no value marks a cleared parent', () {
      final layer = _parse('parent:\n');
      expect(layer.writesParent, isTrue);
      expect(layer.parent, isNull);
    });

    test('reference is read past as a top-level key', () {
      final layer = _parse('reference: [{title: Specstone}]');
      expect(layer.id, isNull);
    });

    test('a plain reference list parses into entries', () {
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

    test('a link conflict inside parse keeps its index key', () {
      expect(
        () => _parse(
          'reference: [{title: T}, {title: U, url: https://x, doc: d}]',
        ),
        throwsA(_fault(FaultCode.referenceLinkConflict, key: 'reference[1]')),
      );
    });

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

    test('a bundle add and remove mapping is a ListChange', () {
      final change =
          _parse('bundle: {add: [design], remove: [query]}\n').bundle!
              as ListChange<String>;
      expect(change.add, ['design']);
      expect(change.remove, ['query']);
    });

    test('generators reads a plain list and add and remove '
        'lists', () {
      final plain = _parse('generators: [note_toc]\n').generators!;
      expect(plain, isA<PlainList<String>>());
      expect((plain as PlainList<String>).items, ['note_toc']);

      final change =
          _parse('generators: {add: [b], remove: [a]}\n').generators!
              as ListChange<String>;
      expect(change.add, ['b']);
      expect(change.remove, ['a']);

      expect(_parse('sections: [{id: goal}]\n').generators, isNull);
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

    test('f03/us03/fr01, tpl-s03/inv23, db-r7: a section summary is read as '
        'written', () {
      expect(
        _parse('sections: [{id: goal, summary: true}]\n')
            .sections
            .single
            .summary,
        isTrue,
      );
    });

    test('f03/us03/fr01/e19, tpl-s03/inv23, db-r7: a section summary that is '
        'not a boolean is unknown_value', () {
      expect(
        () => _parse('sections: [{id: goal, summary: yes please}]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'sections.goal.summary')),
      );
    });

    test('f03/us03/fr01/e19, tpl-s03/inv23: a section query that is not a boolean is unknown_value', () {
      expect(
        () => _parse('sections: [{id: goal, query: yes please}]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'sections.goal.query')),
      );
    });

    test('a layer that writes neither key leaves both null', () {
      final layer = _parse('sections: [{id: goal}]\n');
      expect(layer.bundle, isNull);
      expect(layer.sections.single.query, isNull);
    });

    test('an output_ref pointer of item_test is accepted and names the '
        'item_test kind', () {
      final layer = _parse(
        'fields: [{id: tests, type: output_ref, pointer: item_test}]',
      );
      expect(layer.fields.single.pointer, 'item_test');
      expect(
        PointerKind.byWire('item_test', file: _file, prefix: ''),
        PointerKind.itemTest,
      );
      expect(PointerKind.itemTest.wire, 'item_test');
    });

    test('an output_ref pointer of item_tests is unknown_value', () {
      expect(
        () => _parse(
          'fields: [{id: tests, type: output_ref, pointer: item_tests}]',
        ),
        throwsA(_fault(FaultCode.unknownValue, key: 'fields.tests.pointer')),
      );
    });
  });

  group('DocTypeLayer.parse guide-rule keys', () {
    SectionLint lintOf(String lint) =>
        _parse('sections: [{id: goal, header: G, lint: $lint}]')
            .sections
            .single
            .lint!;

    TypeMatcher<TemplateFault> sectionFault(FaultCode code, String key) =>
        _fault(code, key: 'sections.goal.lint.$key');

    void expectSectionFault(String lint, FaultCode code, String key) {
      expect(() => lintOf(lint), throwsA(sectionFault(code, key)));
    }

    test('catalog reads its column', () {
      expect(lintOf('{catalog: {column: Code}}').catalog?.column, 'Code');
    });

    test('a catalog with no column is missing_key', () {
      expectSectionFault(
        '{catalog: {}}',
        FaultCode.missingKey,
        'catalog.column',
      );
    });

    test('a catalog key other than column is unknown_key', () {
      expectSectionFault(
        '{catalog: {column: Code, width: 3}}',
        FaultCode.unknownKey,
        'catalog.width',
      );
    });

    test('names_codes reads a boolean and refuses another value', () {
      expect(lintOf('{names_codes: true}').namesCodes, isTrue);
      expect(lintOf('{max_chars: 3}').namesCodes, isNull);
      expectSectionFault(
        '{names_codes: yes please}',
        FaultCode.unknownValue,
        'names_codes',
      );
    });

    test('item_fields reads a plain list of fields with optional values', () {
      final write = lintOf(
        '{item_fields: [{field: Enforcer, values: [a, b]}, '
        '{field: Consistency}]}',
      ).itemFields;
      final items = (write! as PlainList<ItemFieldLint>).items;
      expect(items.map((i) => i.field), ['Enforcer', 'Consistency']);
      expect(items.first.values, ['a', 'b']);
      expect(items.last.values, isNull);
    });

    test('item_fields reads add and remove as a change', () {
      final write = lintOf(
        '{item_fields: {add: [{field: Enforcer}], remove: [Consistency]}}',
      ).itemFields;
      final change = write! as ListChange<ItemFieldLint>;
      expect(change.add.single.field, 'Enforcer');
      expect(change.remove, ['Consistency']);
    });

    test('an item_fields entry with no field is missing_key', () {
      expectSectionFault(
        '{item_fields: [{values: [a]}]}',
        FaultCode.missingKey,
        'item_fields[0].field',
      );
      expectSectionFault(
        '{item_fields: {add: [{values: [a]}]}}',
        FaultCode.missingKey,
        'item_fields.add[0].field',
      );
    });

    test('an item_fields entry key other than field and values is '
        'unknown_key', () {
      expectSectionFault(
        '{item_fields: [{field: A, kind: b}]}',
        FaultCode.unknownKey,
        'item_fields[0].kind',
      );
    });

    test('required_when reads section, field, and value', () {
      final rule = lintOf(
        '{required_when: {section: scope, field: Kind, value: api}}',
      ).requiredWhen!;
      expect((rule.section, rule.field, rule.value), ('scope', 'Kind', 'api'));
    });

    test('a required_when missing one of its three keys is missing_key', () {
      for (final key in ['section', 'field', 'value']) {
        final all = {'section': 's', 'field': 'f', 'value': 'v'}..remove(key);
        final body = all.entries.map((e) => '${e.key}: ${e.value}').join(', ');
        expectSectionFault(
          '{required_when: {$body}}',
          FaultCode.missingKey,
          'required_when.$key',
        );
      }
    });

    test('diagram reads its booleans and banned labels', () {
      final diagram = lintOf(
        '{diagram: {title: true, edge_labels: true, banned_labels: [x, y]}}',
      ).diagram!;
      expect(diagram.title, isTrue);
      expect(diagram.edgeLabels, isTrue);
      expect(diagram.bannedLabels, ['x', 'y']);
    });

    test('a diagram with no key set reads all three as off', () {
      final diagram = lintOf('{diagram: {}}').diagram!;
      expect(diagram.title, isFalse);
      expect(diagram.edgeLabels, isFalse);
      expect(diagram.bannedLabels, isEmpty);
    });

    test('a diagram key other than title, edge_labels, and banned_labels is '
        'unknown_key', () {
      expectSectionFault(
        '{diagram: {title: true, colour: red}}',
        FaultCode.unknownKey,
        'diagram.colour',
      );
    });

    test('max_sentences reads count with optional line_prefix and column', () {
      final limits = lintOf(
        '{max_sentences: [{count: 1, line_prefix: "- **Why:**"}, '
        '{count: 2, column: Notes}, {count: 3}]}',
      ).maxSentences!;
      expect(limits.map((l) => l.count), [1, 2, 3]);
      expect(limits.map((l) => l.linePrefix), ['- **Why:**', null, null]);
      expect(limits.map((l) => l.column), [null, 'Notes', null]);
    });

    test('a max_sentences entry with no count is missing_key', () {
      expectSectionFault(
        '{max_sentences: [{column: Notes}]}',
        FaultCode.missingKey,
        'max_sentences[0].count',
      );
    });

    test('item_count reads min, max, per_subsection, and prefixes', () {
      final count = lintOf(
        '{item_count: {min: 1, max: 5, per_subsection: true, '
        'prefixes: [{line_prefix: "- **Why:**", count: 1}]}}',
      ).itemCount!;
      expect((count.min, count.max, count.perSubsection), (1, 5, true));
      expect(count.prefixes.single.linePrefix, '- **Why:**');
      expect(count.prefixes.single.count, 1);
    });

    test('an item_count with no key set has no bounds and no prefixes', () {
      final count = lintOf('{item_count: {}}').itemCount!;
      expect(count.min, isNull);
      expect(count.max, isNull);
      expect(count.perSubsection, isFalse);
      expect(count.prefixes, isEmpty);
    });

    test('an item_count whose min exceeds its max is unknown_value', () {
      expectSectionFault(
        '{item_count: {min: 4, max: 3}}',
        FaultCode.unknownValue,
        'item_count.min',
      );
      expect(lintOf('{item_count: {min: 3, max: 3}}').itemCount?.min, 3);
    });

    test(
      'an item_count prefix with no line_prefix or count is missing_key',
      () {
        expectSectionFault(
          '{item_count: {prefixes: [{count: 1}]}}',
          FaultCode.missingKey,
          'item_count.prefixes[0].line_prefix',
        );
        expectSectionFault(
          '{item_count: {prefixes: [{line_prefix: "-"}]}}',
          FaultCode.missingKey,
          'item_count.prefixes[0].count',
        );
      },
    );

    test('min_lines reads a whole number and refuses another value', () {
      expect(lintOf('{min_lines: 2}').minLines, 2);
      expectSectionFault(
        '{min_lines: three}',
        FaultCode.unknownValue,
        'min_lines',
      );
      expectSectionFault(
        '{min_lines: 2.5}',
        FaultCode.unknownValue,
        'min_lines',
      );
    });

    test('title_no_number reads a doc-level boolean and refuses another '
        'value', () {
      expect(_parse('lint: {title_no_number: true}').lint?.titleNoNumber, true);
      expect(_parse('lint: {max_chars: 3}').lint?.titleNoNumber, isNull);
      expect(
        () => _parse('lint: {title_no_number: yes please}'),
        throwsA(_fault(FaultCode.unknownValue, key: 'lint.title_no_number')),
      );
    });

    test('title_no_number in a section lint is unknown_key', () {
      expectSectionFault(
        '{title_no_number: true}',
        FaultCode.unknownKey,
        'title_no_number',
      );
    });

    test('a section guide-rule key in the doc-level lint is unknown_key', () {
      for (final key in ['catalog', 'min_lines', 'diagram']) {
        expect(
          () => _parse('lint: {$key: {}}'),
          throwsA(_fault(FaultCode.unknownKey, key: 'lint.$key')),
          reason: key,
        );
      }
    });
  });

  group('isDocTypeFileName', () {
    test('a top-level id yaml file is a doc type', () {
      expect(isDocTypeFileName('feature.yaml'), isTrue);
    });

    test('pack.yaml is not a doc type', () {
      expect(isDocTypeFileName('pack.yaml'), isFalse);
    });

    test('a non-yaml file is not a doc type', () {
      expect(isDocTypeFileName('notes.md'), isFalse);
    });

    test('a nested file is not a doc type', () {
      expect(isDocTypeFileName('refs/x.yaml'), isFalse);
    });
  });
}
