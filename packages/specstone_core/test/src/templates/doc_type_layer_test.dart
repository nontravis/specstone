import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _file = '.specstone/templates/feature.yaml';

const _areaFile = '.specstone/templates/area_index.yaml';

/// The fault the resolver throws for a project type `area_index` that writes
/// [keys] beside its id and description.
Future<TemplateFault> _resolveNewTypeFault(String keys) async {
  final project = await writeTree({
    '.specstone/config.yaml': 'packs:\n  prd-core: 1.1.0\n',
    _areaFile: 'id: area_index\ndescription: x\n$keys',
  });
  final home = await writeTree({});
  final resolver = TemplateResolver(
    shippedFiles: {
      'prd-core/pack.yaml': Uint8List.fromList(
        utf8.encode('name: prd-core\nversion: 1.1.0\n'),
      ),
    },
  );
  try {
    resolver.resolve(workingDirectory: project, homeDirectory: home);
  } on TemplateFault catch (fault) {
    return fault;
  }
  fail('resolve threw no fault');
}

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

    for (final kind in LayerKind.values) {
      test('a doc type file named shared is unknown_value at id in a '
          '${kind.name} layer', () {
        const file = '.specstone/templates/shared.yaml';
        expect(
          () => DocTypeLayer.parse(
            'description: x\n',
            file: file,
            docTypeId: 'shared',
            kind: kind,
            files: const _FakeFiles({}),
          ),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.unknownValue)
                .having((f) => f.file, 'file', file)
                .having((f) => f.key, 'key', 'id')
                .having(
                  (f) => f.message,
                  'message',
                  'doc type id shared is reserved',
                ),
          ),
        );
      });
    }

    test('per_target reads a boolean', () {
      final readers = <String, bool? Function(DocTypeLayer)>{
        'per_target': (layer) => layer.perTarget,
        'fixed_numbers': (layer) => layer.fixedNumbers,
        'bundle_refs': (layer) => layer.bundleRefs,
      };
      for (final MapEntry(:key, value: read) in readers.entries) {
        expect(read(_parse('$key: true\n')), isTrue, reason: key);
        expect(read(_parse('$key: false\n')), isFalse, reason: key);
        expect(read(_parse('path: a/{slug}.md\n')), isNull, reason: key);
      }
    });

    test('a per_target that is not a boolean is unknown_value', () {
      for (final key in ['per_target', 'fixed_numbers', 'bundle_refs']) {
        expect(
          () => _parse('$key: yes please\n'),
          throwsA(_fault(FaultCode.unknownValue, key: key)),
          reason: key,
        );
      }
    });

    test('record_status is an accepted field type', () {
      for (final (id, wire, type) in [
        ('status_of', 'record_status', FieldType.recordStatus),
        ('tasks', 'task_ref', FieldType.taskRef),
        ('source', 'source_ref', FieldType.sourceRef),
      ]) {
        final layer = _parse('fields: [{id: $id, type: $wire}]');
        expect(layer.fields.single.type, type, reason: wire);
      }
    });

    test('an unknown field type is unknown_value counting ten types', () {
      expect(
        () => _parse('fields: [{id: tasks, type: ticket}]'),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'fields.tasks.type').having(
            (f) => f.message,
            'message',
            'the key type must be one of the ten field types',
          ),
        ),
      );
    });

    test('root: project and root: code load on an output_ref field', () {
      final layer = _parse(
        'fields: [{id: a, type: output_ref, pointer: exact, root: project}, '
        '{id: b, type: output_ref, pointer: exact, root: code}]',
      );
      expect(layer.fields.map((f) => f.root), ['project', 'code']);
    });

    test('a root other than code or project is unknown_value', () {
      expect(
        () => _parse(
          'fields: [{id: a, type: output_ref, pointer: exact, root: repo}]',
        ),
        throwsA(_fault(FaultCode.unknownValue, key: 'fields.a.root')),
      );
      expect(
        () => _parse(
          'fields: [{id: a, type: output_ref, pointer: exact, root: 3}]',
        ),
        throwsA(_fault(FaultCode.unknownValue, key: 'fields.a.root')),
      );
    });

    test('a root on a string field loads', () {
      final layer = _parse('fields: [{id: a, type: string, root: repo}]');
      expect(layer.fields.single.type, FieldType.string);
    });

    test('bundle_with reads as written on a field', () {
      final layer = _parse(
        'fields: [{id: a, type: doc_ref, bundle_with: true}, '
        '{id: b, type: doc_ref, bundle_with: false}, {id: c, type: doc_ref}]',
      );
      expect(layer.fields.map((f) => f.bundleWith), [true, false, null]);
    });

    test('a non-boolean bundle_with on a field is unknown_value at its '
        'index key', () {
      expect(
        () => _parse('fields: [{id: a, type: doc_ref, bundle_with: yes}]'),
        throwsA(_fault(FaultCode.unknownValue, key: 'fields[0].bundle_with')),
      );
    });

    test('an id unlike the file name is doc_type_id_mismatch', () {
      expect(
        () => _parse('id: epic\n'),
        throwsA(_fault(FaultCode.docTypeIdMismatch, key: 'id')),
      );
    });

    test('a top-level unknown key is unknown_key', () {
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

    test('path_from takes feature_groups only', () {
      final layer = _parse('path_from: feature_groups\nfile: AREA.md\n');
      expect(layer.pathFrom, 'feature_groups');
      expect(layer.docFile, 'AREA.md');
      expect(_parse('path: a/{slug}/A.md\n').pathFrom, isNull);
      expect(
        () => _parse('path_from: feature_folders\nfile: AREA.md\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'path_from')),
      );
    });

    test('file takes one portable .md file name', () {
      for (final value in [
        '../x.md',
        'a/b.md',
        r'a\b.md',
        '/abs.md',
        'x.txt',
        '',
        '{slug}.md',
        'a{nn}.md',
        'a}b.md',
        'a*b.md',
        'a?b.md',
        'a<b.md',
        'a>b.md',
        'a|b.md',
        'a"b.md',
        'a:b.md',
        'a b.md',
        'a\u001Bb.md',
        'a\nb.md',
        '.hidden.md',
        'a..md',
        '.md',
        'NUL.md',
        'con.md',
        'Com1.notes.md',
        'LPT9.md',
      ]) {
        expect(
          () =>
              _parse('path_from: feature_groups\nfile: ${jsonEncode(value)}\n'),
          throwsA(_fault(FaultCode.unknownValue, key: 'file')),
          reason: value,
        );
      }
      for (final value in ['FEATURES.md', 'a-b_c.1.md', '_x.md', 'COM10.md']) {
        expect(
          _parse('path_from: feature_groups\nfile: $value\n').docFile,
          value,
        );
      }
    });

    test('a camelCase pathFrom key is unknown_key', () {
      expect(
        () => _parse('pathFrom: feature_groups\n'),
        throwsA(_fault(FaultCode.unknownKey, key: 'pathFrom')),
      );
    });

    test(
      'a new doc type with path_from and no file is missing_key at file',
      () async {
        final fault = await _resolveNewTypeFault('path_from: feature_groups\n');

        expect(fault.code, FaultCode.missingKey);
        expect(fault.key, 'file');
        expect(fault.file, _areaFile);
      },
    );

    test(
      'a new doc type with neither path nor path_from is missing_key at path',
      () async {
        final fault = await _resolveNewTypeFault('');

        expect(fault.code, FaultCode.missingKey);
        expect(fault.key, 'path');
        expect(fault.file, _areaFile);
      },
    );

    test('title reads a fixed title string', () {
      expect(_parse('title: Domain glossary\n').title, 'Domain glossary');
      expect(_parse('path: a/{slug}/A.md\n').title, isNull);
    });

    test('a title that is no string, is empty, or holds a <…> span is '
        'unknown_value at the title key', () {
      for (final value in ['3', '""', '"<Name>"', '"Glossary of <Name>"']) {
        expect(
          () => _parse('title: $value\n'),
          throwsA(_fault(FaultCode.unknownValue, key: 'title')),
          reason: value,
        );
      }
    });

    test('a title that is blank, padded with white space, or holds a line '
        'break is unknown_value at the title key', () {
      for (final value in [
        '"   "',
        '" Domain glossary"',
        '"Domain glossary "',
        r'"Domain\nglossary"',
      ]) {
        expect(
          () => _parse('title: $value\n'),
          throwsA(_fault(FaultCode.unknownValue, key: 'title')),
          reason: value,
        );
      }
    });

    test('a section id starting with _ is unknown_value', () {
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

    test('a field with no id is missing_key at the index', () {
      expect(
        () => _parse('fields: [{type: string}]'),
        throwsA(_fault(FaultCode.missingKey, key: 'fields[0].id')),
      );
    });

    test('a section with no id is missing_key at the index', () {
      expect(
        () => _parse('sections: [{header: Goal}]'),
        throwsA(_fault(FaultCode.missingKey, key: 'sections[0].id')),
      );
    });

    test('an enum field with no enum list is missing_key', () {
      expect(
        () => _parse('fields: [{id: kind, type: enum}]'),
        throwsA(_fault(FaultCode.missingKey, key: 'fields.kind.enum')),
      );
    });

    test('an output_ref field with no pointer is missing_key', () {
      expect(
        () => _parse('fields: [{id: covers, type: output_ref}]'),
        throwsA(_fault(FaultCode.missingKey, key: 'fields.covers.pointer')),
      );
    });

    test(
      'an output_ref pointer other than exact or prefix is unknown_value',
      () {
        expect(
          () =>
              _parse('fields: [{id: covers, type: output_ref, pointer: glob}]'),
          throwsA(_fault(FaultCode.unknownValue, key: 'fields.covers.pointer')),
        );
        expect(
          () => _parse(
            'fields: [{id: covers, type: output_ref, pointer: item_tests}]',
          ),
          throwsA(_fault(FaultCode.unknownValue, key: 'fields.covers.pointer')),
        );
      },
    );

    test('an output_ref pointer that is not a string is unknown_value', () {
      expect(
        () => _parse('fields: [{id: covers, type: output_ref, pointer: 3}]'),
        throwsA(_fault(FaultCode.unknownValue, key: 'fields.covers.pointer')),
      );
    });

    test('an output_ref field reads its pointer kind', () {
      final layer = _parse(
        'fields: [{id: covers, type: output_ref, list: true, pointer: prefix}, '
        '{id: implements, type: output_ref, pointer: exact}, '
        '{id: items, type: output_ref, pointer: item_exact}]',
      );
      expect(layer.fields.map((f) => f.pointer), [
        'prefix',
        'exact',
        'item_exact',
      ]);
    });

    test(
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
        expect(
          _parse('fields: [{id: size, type: string, pointer: 3}]')
              .fields
              .single
              .pointer,
          3,
        );
      },
    );

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

    test('a section lint that writes max_item_chars is unknown_key', () {
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

    test('a section lint holds banned_words, '
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

    test('a reference add map parses entries', () {
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
    });

    test('a link conflict inside parse keeps its index key', () {
      expect(
        () => _parse(
          'reference: [{title: T}, {title: U, url: https://x, doc: d}]',
        ),
        throwsA(_fault(FaultCode.referenceLinkConflict, key: 'reference[1]')),
      );
    });

    test('bundle and a section query are read as written', () {
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

    test('a bundle entry outside the three modes is unknown_value', () {
      expect(
        () => _parse('bundle: [query, deploy]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'bundle')),
      );
      expect(
        () => _parse('bundle: {add: [deploy]}\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'bundle')),
      );
    });

    test('a section summary is read as '
        'written', () {
      expect(
        _parse('sections: [{id: goal, summary: true}]\n')
            .sections
            .single
            .summary,
        isTrue,
      );
    });

    test('a section summary that is not a boolean is unknown_value', () {
      expect(
        () => _parse('sections: [{id: goal, summary: yes please}]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'sections.goal.summary')),
      );
      expect(
        () => _parse('sections: [{id: goal, query: yes please}]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'sections.goal.query')),
      );
    });

    test('a section skeleton is read as written', () {
      final sections = _parse(
        'sections: [{id: goal, skeleton: true}, {id: why}]\n',
      ).sections;
      expect(sections.first.skeleton, isTrue);
      expect(sections.last.skeleton, isNull);

      final matrix = _parse(
        'sections: [{id: matrix, output_ref: true}, {id: goal}]\n',
      ).sections;
      expect(matrix.first.outputRef, isTrue);
      expect(matrix.last.outputRef, isNull);
    });

    test('a section skeleton that is not a boolean is unknown_value', () {
      expect(
        () => _parse('sections: [{id: why}, {id: goal, skeleton: header}]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'sections[1].skeleton')),
      );
      expect(
        () => _parse('sections: [{id: why}, {id: matrix, output_ref: rows}]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'sections[1].output_ref')),
      );
    });

    test('a section summary_rows count is read as that many rows', () {
      final rows = _parse('sections: [{id: goal, summary_rows: 1}]\n')
          .sections
          .single
          .summaryRows;
      expect(rows?.count, 1);
    });

    test('a section summary_rows of false is read as off', () {
      final rows = _parse('sections: [{id: goal, summary_rows: false}]\n')
          .sections
          .single
          .summaryRows;
      expect(rows, isNotNull);
      expect(rows?.count, isNull);
    });

    test('a layer that writes no summary_rows leaves it null', () {
      expect(
        _parse('sections: [{id: goal}]\n').sections.single.summaryRows,
        isNull,
      );
    });

    for (final value in ['0', '-1', 'two', 'true']) {
      test('a section summary_rows of $value is unknown_value', () {
        expect(
          () => _parse('sections: [{id: goal, summary_rows: $value}]\n'),
          throwsA(
            _fault(FaultCode.unknownValue, key: 'sections[0].summary_rows'),
          ),
        );
      });
    }

    test('a summary_for list is read as written', () {
      expect(_parse('summary_for: [project]\n').summaryFor, ['project']);
    });

    test('a layer that writes no summary_for leaves it null', () {
      expect(_parse('path: f.md\n').summaryFor, isNull);
    });

    test('a summary_for holding a non-string is unknown_value', () {
      expect(
        () => _parse('summary_for: [1]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'summary_for')),
      );
    });

    test('a summary_for that is no list is unknown_value', () {
      expect(
        () => _parse('summary_for: project\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'summary_for')),
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

    test('an item_fields entry reads a when of a field and a value', () {
      final entry =
          (lintOf(
                    '{item_fields: [{field: Corrective policy, '
                    'when: {field: Consistency, value: eventual}}]}',
                  ).itemFields!
                  as PlainList<ItemFieldLint>)
              .items
              .single;
      expect(entry.when!.field, 'Consistency');
      expect(entry.when!.value, 'eventual');
      expect(entry.values, isNull);
    });

    test('a when key other than field and value is unknown_key', () {
      expectSectionFault(
        '{item_fields: [{field: P, when: {field: K, value: v, extra: x}}]}',
        FaultCode.unknownKey,
        'item_fields[0].when.extra',
      );
    });

    test('a when without field or value is missing_key', () {
      expectSectionFault(
        '{item_fields: [{field: P, when: {value: v}}]}',
        FaultCode.missingKey,
        'item_fields[0].when.field',
      );
      expectSectionFault(
        '{item_fields: [{field: P, when: {field: K}}]}',
        FaultCode.missingKey,
        'item_fields[0].when.value',
      );
    });

    test('a when that is no mapping, or whose field or value is no string, '
        'is unknown_value', () {
      expectSectionFault(
        '{item_fields: [{field: P, when: eventual}]}',
        FaultCode.unknownValue,
        'item_fields[0].when',
      );
      expectSectionFault(
        '{item_fields: [{field: P, when: {field: K, value: [v]}}]}',
        FaultCode.unknownValue,
        'item_fields[0].when.value',
      );
    });

    test('item field entries in the three accepted shapes load', () {
      final entries =
          (lintOf(
                    '{item_fields: [ '
                    '{field: Corrective policy, when: {field: Consistency, '
                    'value: eventual}, values: [a]}, '
                    '{field: Consistency, values: [eventual], optional: true}, '
                    '{field: Enforcer, default_from: entities}, '
                    '{field: Plain}]}',
                  ).itemFields!
                  as PlainList<ItemFieldLint>)
              .items;
      expect(entries[0].when?.field, 'Consistency');
      expect(entries[0].optional, isFalse);
      expect(entries[0].defaultFrom, isNull);
      expect(entries[1].optional, isTrue);
      expect(entries[1].when, isNull);
      expect(entries[2].defaultFrom, 'entities');
      expect(entries[2].optional, isFalse);
      expect(entries[3].optional, isFalse);
      expect(entries[3].defaultFrom, isNull);
      expect(entries[1].toJson()['optional'], isTrue);
      expect(entries[2].toJson()['default_from'], 'entities');
      expect(entries[3].toJson().keys, ['field']);
    });

    test('a non-boolean optional is refused at its entry key', () {
      expectSectionFault(
        '{item_fields: [{field: A, optional: yes}]}',
        FaultCode.unknownValue,
        'item_fields[0].optional',
      );
    });

    test('a default_from naming another section is refused', () {
      expectSectionFault(
        '{item_fields: [{field: A, default_from: roles}]}',
        FaultCode.unknownValue,
        'item_fields[0].default_from',
      );
    });

    test('an entry writing two exclusive keys is refused with the one-of '
        'message', () {
      const pairs = [
        'when: {field: K, value: v}, optional: true',
        'when: {field: K, value: v}, default_from: entities',
        'optional: false, default_from: entities',
      ];
      for (final pair in pairs) {
        expect(
          () => lintOf('{item_fields: [{field: A, $pair}]}'),
          throwsA(
            sectionFault(FaultCode.unknownValue, 'item_fields[0]').having(
              (f) => f.message,
              'message',
              'an item_fields entry takes one of when, optional, default_from',
            ),
          ),
          reason: pair,
        );
      }
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

    test('a diagram with no key set reads all four as off', () {
      final diagram = lintOf('{diagram: {}}').diagram!;
      expect(diagram.title, isFalse);
      expect(diagram.edgeLabels, isFalse);
      expect(diagram.bannedLabels, isEmpty);
      expect(diagram.names, isFalse);
    });

    test('diagram reads names as a boolean, false when absent', () {
      expect(lintOf('{diagram: {names: true}}').diagram!.names, isTrue);
      expect(lintOf('{diagram: {title: true}}').diagram!.names, isFalse);
    });

    test('diagram names that is not a boolean is unknown_value at its key', () {
      expectSectionFault(
        '{diagram: {names: yes}}',
        FaultCode.unknownValue,
        'diagram.names',
      );
    });

    test('a diagram key other than title, edge_labels, banned_labels, and '
        'names is unknown_key', () {
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

    test('an item_count waits_for of maybe is unknown_value', () {
      for (final value in ['maybe', '""']) {
        expectSectionFault(
          '{item_count: {max: 8, waits_for: $value}}',
          FaultCode.unknownValue,
          'item_count.waits_for',
        );
      }
      expect(
        lintOf('{item_count: {max: 8, waits_for: owner}}')
            .itemCount
            ?.waitsForOwner,
        isTrue,
      );
      expect(
        lintOf('{item_count: {max: 8, waits_for: agent}}')
            .itemCount
            ?.waitsForOwner,
        isFalse,
      );
      expect(
        lintOf('{item_count: {max: 8}}').itemCount?.waitsForOwner,
        isFalse,
      );
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

    test('max_subsections reads a whole number of 1 or more', () {
      expect(lintOf('{max_subsections: 4}').maxSubsections, 4);
      expect(lintOf('{max_chars: 3}').maxSubsections, isNull);
    });

    test('a max_subsections of zero, below zero, or another type is '
        'unknown_value', () {
      for (final value in ['0', '-1', '2.5', 'many', 'true']) {
        expectSectionFault(
          '{max_subsections: $value}',
          FaultCode.unknownValue,
          'max_subsections',
        );
      }
    });

    test('a section max_item_lines loads as an integer', () {
      expect(lintOf('{max_item_lines: 4}').maxItemLines, 4);
      expect(lintOf('{max_chars: 3}').maxItemLines, isNull);
    });

    test('a max_item_lines below one or not a number is refused', () {
      for (final value in ['0', '-1', 'one']) {
        expectSectionFault(
          '{max_item_lines: $value}',
          FaultCode.unknownValue,
          'max_item_lines',
        );
      }
    });

    test('max_code_blocks reads count and per_subsection', () {
      final blocks = lintOf(
        '{max_code_blocks: {count: 2, per_subsection: true}}',
      ).maxCodeBlocks!;
      expect((blocks.count, blocks.perSubsection), (2, true));
      final plain = lintOf('{max_code_blocks: {count: 1}}').maxCodeBlocks!;
      expect((plain.count, plain.perSubsection), (1, false));
      expect(lintOf('{max_chars: 3}').maxCodeBlocks, isNull);
    });

    test('a max_code_blocks count or per_subsection of the wrong value is '
        'unknown_value', () {
      for (final (value, key) in [
        ('{count: 0}', 'count'),
        ('{count: two}', 'count'),
        ('{count: 1, per_subsection: yes}', 'per_subsection'),
      ]) {
        expectSectionFault(
          '{max_code_blocks: $value}',
          FaultCode.unknownValue,
          'max_code_blocks.$key',
        );
      }
    });

    test('a max_code_blocks map with no count is missing_key', () {
      expectSectionFault(
        '{max_code_blocks: {per_subsection: true}}',
        FaultCode.missingKey,
        'max_code_blocks.count',
      );
    });

    test('a required_patterns entry reads per_subsection, off when absent', () {
      final write = lintOf(
        '{required_patterns: [ '
        '{id: a, pattern: x, message: m, per_subsection: true}, '
        '{id: b, pattern: y, message: m} ]}',
      ).requiredPatterns;
      final items = (write! as PlainList<PatternEntry>).items;
      expect(items.map((e) => e.perSubsection), [true, false]);
    });

    test('a required_patterns per_subsection that is no boolean is '
        'unknown_value', () {
      expectSectionFault(
        '{required_patterns: [{id: a, pattern: x, message: m, '
            'per_subsection: sometimes}]}',
        FaultCode.unknownValue,
        'required_patterns[0].per_subsection',
      );
    });

    test('a banned_patterns entry with per_subsection is unknown_key', () {
      expectSectionFault(
        '{banned_patterns: [{id: a, pattern: x, message: m, '
            'per_subsection: true}]}',
        FaultCode.unknownKey,
        'banned_patterns[0].per_subsection',
      );
    });

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

    group('field lint', () {
      FieldCaps? lintOf(String lint) =>
          _parse('fields: [{id: summary, type: string, lint: $lint}]')
              .fields
              .single
              .lint;

      test('a string field loads all three keys', () {
        final caps = lintOf(
          '{max_sentences: 1, max_sentence_words: {default: 20, ko: 12}, '
          'max_sentence_chars: {default: 80, th: 70}}',
        );

        expect(caps?.maxSentences, 1);
        expect(caps?.maxSentenceWords, {'default': 20, 'ko': 12});
        expect(caps?.maxSentenceChars, {'default': 80, 'th': 70});
        expect(caps?.capsLength, isTrue);
      });

      test('max_sentences alone loads and caps no length', () {
        final caps = lintOf('{max_sentences: 1}');

        expect(caps?.maxSentences, 1);
        expect(caps?.maxSentenceWords, isNull);
        expect(caps?.maxSentenceChars, isNull);
        expect(caps?.capsLength, isFalse);
      });

      test('a field with no lint holds none', () {
        expect(
          _parse('fields: [{id: summary, type: string}]').fields.single.lint,
          isNull,
        );
      });

      test('a key other than the three is unknown_key', () {
        for (final key in ['trace_note_last', 'max_lines']) {
          expect(
            () => lintOf('{$key: 1}'),
            throwsA(
              _fault(FaultCode.unknownKey, key: 'fields.summary.lint.$key'),
            ),
            reason: key,
          );
        }
      });

      test('a max_sentences below 1 or no number is unknown_value', () {
        for (final value in ['0', '-1', 'one']) {
          expect(
            () => lintOf('{max_sentences: $value}'),
            throwsA(
              _fault(
                FaultCode.unknownValue,
                key: 'fields.summary.lint.max_sentences',
              ),
            ),
            reason: value,
          );
        }
      });

      test('a bad map is refused with the field key prefix', () {
        expect(
          () => lintOf(
            '{max_sentence_words: {default: 0}, '
            'max_sentence_chars: {default: 9}}',
          ),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'fields.summary.lint.max_sentence_words.default',
            ),
          ),
        );
        expect(
          () => lintOf(
            '{max_sentence_words: {fr: 20}, max_sentence_chars: {default: 9}}',
          ),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'fields.summary.lint.max_sentence_words.fr',
            ),
          ),
        );
        expect(
          () => lintOf(
            '{max_sentence_words: 30, max_sentence_chars: {default: 9}}',
          ),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'fields.summary.lint.max_sentence_words',
            ),
          ),
        );
      });

      test('a map without default is missing_key naming its default', () {
        const cases = {
          'max_sentence_words':
              '{max_sentence_words: {ko: 10}, '
              'max_sentence_chars: {default: 9}}',
          'max_sentence_chars':
              '{max_sentence_words: {default: 9}, '
              'max_sentence_chars: {th: 10}}',
        };
        for (final MapEntry(key: map, value: lint) in cases.entries) {
          expect(
            () => lintOf(lint),
            throwsA(
              _fault(
                FaultCode.missingKey,
                key: 'fields.summary.lint.$map.default',
              ),
            ),
            reason: map,
          );
        }
      });

      test('a map with default and a language entry loads', () {
        final caps = lintOf(
          '{max_sentence_words: {default: 9, ko: 10}, '
          'max_sentence_chars: {default: 9, th: 10}}',
        );

        expect(caps?.maxSentenceWords, {'default': 9, 'ko': 10});
        expect(caps?.maxSentenceChars, {'default': 9, 'th': 10});
      });

      test('one map without its partner is missing_key naming the absent '
          'key', () {
        expect(
          () => lintOf('{max_sentence_words: {default: 20}}'),
          throwsA(
            _fault(
              FaultCode.missingKey,
              key: 'fields.summary.lint.max_sentence_chars',
            ),
          ),
        );
        expect(
          () => lintOf('{max_sentence_chars: {default: 80}}'),
          throwsA(
            _fault(
              FaultCode.missingKey,
              key: 'fields.summary.lint.max_sentence_words',
            ),
          ),
        );
      });
    });

    test('doc lint takes the readability keys', () {
      final lint = _parse(
        'lint: {max_sentence_words: {default: 30, ko: 20, ar: 18, he: 18, '
        'hi: 22, el: 24}, max_sentence_chars: {default: 90, th: 80, lo: 80, '
        'km: 80, my: 80, zh: 40, ja: 50}, trace_note_last: false}',
      ).lint;

      expect(lint?.maxSentenceWords, {
        'default': 30,
        'ko': 20,
        'ar': 18,
        'he': 18,
        'hi': 22,
        'el': 24,
      });
      expect(lint?.maxSentenceChars, {
        'default': 90,
        'th': 80,
        'lo': 80,
        'km': 80,
        'my': 80,
        'zh': 40,
        'ja': 50,
      });
      expect(lint?.traceNoteLast, false);
      final bare = _parse('lint: {max_chars: 3}').lint;
      expect(bare?.maxSentenceWords, isNull);
      expect(bare?.maxSentenceChars, isNull);
      expect(bare?.traceNoteLast, isNull);
    });

    test('section lint refuses readability keys', () {
      for (final key in [
        'max_sentence_words',
        'max_sentence_chars',
        'trace_note_last',
      ]) {
        expect(
          () => _parse(
            'sections: [{id: goal, header: G, lint: {$key: {default: 9}}}]',
          ),
          throwsA(_fault(FaultCode.unknownKey, key: 'sections.goal.lint.$key')),
          reason: key,
        );
      }
    });

    test('bad entry value is unknown_value', () {
      for (final value in ['0', '-1', 'twenty', '2.5']) {
        expect(
          () => _parse('lint: {max_sentence_words: {default: $value}}'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'lint.max_sentence_words.default',
            ),
          ),
          reason: value,
        );
        expect(
          () => _parse('lint: {max_sentence_chars: {th: $value}}'),
          throwsA(
            _fault(FaultCode.unknownValue, key: 'lint.max_sentence_chars.th'),
          ),
          reason: value,
        );
      }
      expect(
        () => _parse('lint: {trace_note_last: yes}'),
        throwsA(_fault(FaultCode.unknownValue, key: 'lint.trace_note_last')),
      );
    });

    test('language key outside its map is unknown_value', () {
      expect(
        () => _parse('lint: {max_sentence_words: {fr: 20}}'),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'lint.max_sentence_words.fr'),
        ),
      );
      expect(
        () => _parse('lint: {max_sentence_words: {th: 20}}'),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'lint.max_sentence_words.th'),
        ),
      );
      expect(
        () => _parse('lint: {max_sentence_chars: {ko: 20}}'),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'lint.max_sentence_chars.ko'),
        ),
      );
    });

    test('scalar map value is unknown_value', () {
      expect(
        () => _parse('lint: {max_sentence_words: 30}'),
        throwsA(_fault(FaultCode.unknownValue, key: 'lint.max_sentence_words')),
      );
      expect(
        () => _parse('lint: {max_sentence_chars: 100}'),
        throwsA(_fault(FaultCode.unknownValue, key: 'lint.max_sentence_chars')),
      );
    });

    test('a section guide-rule key in the doc-level lint is unknown_key', () {
      for (final key in ['catalog', 'min_lines', 'diagram', 'max_item_lines']) {
        expect(
          () => _parse('lint: {$key: {}}'),
          throwsA(_fault(FaultCode.unknownKey, key: 'lint.$key')),
          reason: key,
        );
      }
    });
  });

  group('DocTypeLayer.parse when_field', () {
    SectionEntry sectionOf(String whenField) => _parse(
      'sections: [{id: goal, header: G, required: true, '
      'when_field: $whenField}]',
    ).sections.single;

    void expectFault(String whenField, FaultCode code, String key) {
      expect(
        () => sectionOf(whenField),
        throwsA(_fault(code, key: 'sections.goal.$key')),
      );
    }

    test('reads the field and its values beside the section required', () {
      final section = sectionOf('{field: kind, values: [api, cli]}');
      expect(section.whenField?.field, 'kind');
      expect(section.whenField?.values, ['api', 'cli']);
      expect(section.required, isTrue);
    });

    test('is null when the section writes none', () {
      final section = _parse('sections: [{id: goal, header: G}]').sections;
      expect(section.single.whenField, isNull);
    });

    test('a key other than field and values is unknown_key', () {
      expectFault(
        '{field: kind, values: [api], required: true}',
        FaultCode.unknownKey,
        'when_field.required',
      );
    });

    test('a missing field or values is missing_key', () {
      expectFault('{values: [api]}', FaultCode.missingKey, 'when_field.field');
      expectFault('{field: kind}', FaultCode.missingKey, 'when_field.values');
    });

    test('a wrong type is unknown_value at its key path', () {
      expectFault(
        '{field: 3, values: [api]}',
        FaultCode.unknownValue,
        'when_field.field',
      );
      expectFault(
        '{field: kind, values: api}',
        FaultCode.unknownValue,
        'when_field.values',
      );
      expectFault(
        '{field: kind, values: [1]}',
        FaultCode.unknownValue,
        'when_field.values',
      );
      expectFault('[kind]', FaultCode.unknownValue, 'when_field');
    });

    test('a when_field with an empty values list is refused', () {
      expect(
        () => sectionOf('{field: kind, values: []}'),
        throwsA(
          _fault(
            FaultCode.unknownValue,
            key: 'sections.goal.when_field.values',
          ).having(
            (f) => f.message,
            'message',
            'when_field values holds no value',
          ),
        ),
      );
    });
  });

  group('DocTypeLayer.parse refusals end the load', () {
    TypeMatcher<TemplateFault> refusal(FaultCode code, String key) =>
        _fault(code, key: key).having((f) => f.exitStatus, 'exit status', 78);

    test('a field entry with an unknown key stops the load naming '
        'the file and the key', () {
      expect(
        () => _parse('fields: [{id: size, colour: red}]'),
        throwsA(refusal(FaultCode.unknownKey, 'fields.size.colour')),
      );
    });

    test('a reference add entry holding a doc in a personal layer is '
        'refused at its add key', () {
      expect(
        () => DocTypeLayer.parse(
          'reference: {add: [{title: T, doc: prd/feature}]}',
          file: _file,
          docTypeId: 'feature',
          kind: LayerKind.personal,
          files: const _FakeFiles({}),
        ),
        throwsA(
          refusal(FaultCode.referenceDocOutsideProject, 'reference.add[0]'),
        ),
      );
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

  test('only an implemented or deprecated status is built', () {
    expect(
      {for (final status in RecordStatus.values) status: status.isBuilt},
      {
        RecordStatus.planned: false,
        RecordStatus.implemented: true,
        RecordStatus.deprecated: true,
        RecordStatus.skipped: false,
      },
    );
  });
}
