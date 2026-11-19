import 'package:specstone_core/src/templates/models/merged_field.dart'
    show FieldType;
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:test/test.dart';

const _file = 'packs/x/pack.yaml';

SharedEntries _parse(String text, {bool allowsFields = true}) =>
    parseSharedEntries(
      readYamlMap(text, file: _file),
      file: _file,
      allowsFields: allowsFields,
    );

TypeMatcher<TemplateFault> _fault(
  FaultCode code, {
  required String key,
  String? message,
}) {
  final matcher = isA<TemplateFault>()
      .having((f) => f.code, 'code', code)
      .having((f) => f.file, 'file', _file)
      .having((f) => f.key, 'key', key);
  return message == null
      ? matcher
      : matcher.having((f) => f.message, 'message', message);
}

void main() {
  group('parseSharedEntries', () {
    test('reads lines and fields in file order with their index', () {
      final shared = _parse('''
shared_lines:
  - id: first
    text: One line.
    for_doc_types: [story]
  - id: second
    disabled: true
shared_fields:
  - id: owner
    type: string
    for_doc_types: [story, fr]
  - id: area
    type: string
''');

      expect(shared.lines.map((l) => l.id), ['first', 'second']);
      expect(shared.lines[0].text, 'One line.');
      expect(shared.lines[0].forDocTypes, ['story']);
      expect(shared.lines[0].disabled, isFalse);
      expect(shared.lines[1].text, isNull);
      expect(shared.lines[1].forDocTypes, isNull);
      expect(shared.lines[1].disabled, isTrue);
      expect(shared.lines[1].index, 1);
      expect(shared.lines[1].file, _file);
      expect(shared.fields.map((f) => f.id), ['owner', 'area']);
      expect(shared.fields[0].entry.type, FieldType.string);
      expect(shared.fields[0].forDocTypes, ['story', 'fr']);
      expect(shared.fields[1].forDocTypes, isNull);
      expect(shared.fields[1].index, 1);
    });

    test('a file with neither key holds no shared entries', () {
      final shared = _parse('name: x\n');

      expect(shared.lines, isEmpty);
      expect(shared.fields, isEmpty);
    });

    test('a file that allows no fields refuses shared_fields', () {
      expect(
        () => _parse(
          'shared_fields:\n  - id: a\n    type: string\n',
          allowsFields: false,
        ),
        throwsA(_fault(FaultCode.unknownKey, key: 'shared_fields')),
      );
    });

    group('for_doc_types', () {
      test('an empty for_doc_types on a line is unknown_value', () {
        expect(
          () => _parse('shared_lines:\n  - id: a\n    for_doc_types: []\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_lines[0].for_doc_types',
              message: 'for_doc_types holds no doc type',
            ),
          ),
        );
      });

      test('an empty for_doc_types on a field is unknown_value', () {
        expect(
          () => _parse(
            'shared_fields:\n'
            '  - id: a\n'
            '    type: string\n'
            '  - id: b\n'
            '    type: string\n'
            '    for_doc_types: []\n',
          ),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_fields[1].for_doc_types',
              message: 'for_doc_types holds no doc type',
            ),
          ),
        );
      });
    });

    group('repeated id', () {
      test('a repeated shared_lines id is refused at the second id', () {
        expect(
          () => _parse(
            'shared_lines:\n  - id: a\n    text: x\n  - id: a\n    text: y\n',
          ),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_lines[1].id',
              message: 'shared entry id repeated: a',
            ),
          ),
        );
      });

      test('a repeated shared_fields id is refused at the second id', () {
        expect(
          () => _parse(
            'shared_fields:\n'
            '  - id: a\n'
            '    type: string\n'
            '  - id: a\n'
            '    type: string\n',
          ),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_fields[1].id',
              message: 'shared entry id repeated: a',
            ),
          ),
        );
      });

      test('a line and a field may share one id', () {
        final shared = _parse(
          'shared_lines:\n  - id: a\n    text: x\n'
          'shared_fields:\n  - id: a\n    type: string\n',
        );

        expect(shared.lines.single.id, 'a');
        expect(shared.fields.single.id, 'a');
      });
    });

    group('line text', () {
      test('an empty line text is unknown_value', () {
        expect(
          () => _parse('shared_lines:\n  - id: a\n    text: ""\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_lines[0].text',
              message: 'a shared line holds one line of text',
            ),
          ),
        );
      });

      test('a two-line line text is unknown_value', () {
        expect(
          () => _parse('shared_lines:\n  - id: a\n    text: "one\\ntwo"\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_lines[0].text',
              message: 'a shared line holds one line of text',
            ),
          ),
        );
      });

      test('a line text ending in a lone CR is unknown_value', () {
        expect(
          () => _parse('shared_lines:\n  - id: a\n    text: "one\\r"\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_lines[0].text',
              message: 'a shared line holds one line of text',
            ),
          ),
        );
      });

      test('a one-line text in a CRLF file is accepted', () {
        final shared = _parse(
          'shared_lines:\r\n  - id: a\r\n    text: |\r\n      One line.\r\n',
        );

        expect(shared.lines.single.text, 'One line.');
      });
    });

    group('unknown key', () {
      test('an unknown key on a line is unknown_key at that key', () {
        expect(
          () => _parse('shared_lines:\n  - id: a\n    colour: red\n'),
          throwsA(_fault(FaultCode.unknownKey, key: 'shared_lines[0].colour')),
        );
      });

      test('an unknown key on a field is unknown_key at that key', () {
        expect(
          () => _parse(
            'shared_fields:\n  - id: a\n    type: string\n    colour: red\n',
          ),
          throwsA(_fault(FaultCode.unknownKey, key: 'shared_fields[0].colour')),
        );
      });
    });

    group('fields the format refuses', () {
      test('a built-in field id is unknown_value at its id', () {
        expect(
          () => _parse('shared_fields:\n  - id: status\n    type: string\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_fields[0].id',
              message: 'a shared field takes no built-in field id: status',
            ),
          ),
        );
      });

      test('the field id patterns is unknown_value at its id', () {
        expect(
          () => _parse('shared_fields:\n  - id: patterns\n    type: string\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_fields[0].id',
              message: 'a shared field takes no id patterns',
            ),
          ),
        );
      });

      test('a record_status type is unknown_value at its type', () {
        expect(
          () => _parse('shared_fields:\n  - id: a\n    type: record_status\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_fields[0].type',
              message: 'a shared field takes no type record_status',
            ),
          ),
        );
      });

      test('a doc_ref field keeps its own doc_types', () {
        final shared = _parse('''
shared_fields:
  - id: parent_story
    type: doc_ref
    doc_types: [story]
    for_doc_types: [fr]
''');

        final field = shared.fields.single;
        expect(field.entry.type, FieldType.docRef);
        expect(field.entry.docTypes, ['story']);
        expect(field.forDocTypes, ['fr']);
      });
    });
  });
}
