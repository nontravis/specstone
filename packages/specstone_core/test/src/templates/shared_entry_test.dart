import 'package:specstone_core/src/templates/models/merged_field.dart'
    show FieldType;
import 'package:specstone_core/src/templates/models/pattern_entry.dart'
    show PatternScope;
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:test/test.dart';

const _file = 'packs/x/pack.yaml';

const _sharedFile = '.specstone/templates/shared.yaml';

SharedEntries _parse(
  String text, {
  String file = _file,
  String format = 'pack',
}) => parseSharedEntries(
  readYamlMap(text, file: file),
  file: file,
  format: format,
);

TypeMatcher<TemplateFault> _fault(
  FaultCode code, {
  required String key,
  String? message,
  String file = _file,
}) {
  final matcher = isA<TemplateFault>()
      .having((f) => f.code, 'code', code)
      .having((f) => f.file, 'file', file)
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

    group('line id form', () {
      const message = 'the key id must be a slug: [a-z][a-z0-9_]*';

      test('a non-slug line id is unknown_value at its id', () {
        const ids = ['noStatus', 'no-status', '_no_status', '2nd_line', 'ñame'];
        for (final id in ids) {
          expect(
            () => _parse('shared_lines:\n  - id: $id\n    text: x\n'),
            throwsA(
              _fault(
                FaultCode.unknownValue,
                key: 'shared_lines[0].id',
                message: message,
              ),
            ),
            reason: id,
          );
        }
        expect(
          () => _parse(
            'shared_lines:\n  - id: no-status\n    text: x\n',
            file: _sharedFile,
            format: 'shared',
          ),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_lines[0].id',
              message: message,
              file: _sharedFile,
            ),
          ),
        );
      });

      test('slug line ids with odd underscores or a digit load', () {
        final shared = _parse(
          'shared_lines:\n'
          '  - id: no__status\n'
          '    text: x\n'
          '  - id: no_status_\n'
          '    text: x\n'
          '  - id: step_2\n'
          '    text: x\n',
        );

        expect(shared.lines.map((l) => l.id), [
          'no__status',
          'no_status_',
          'step_2',
        ]);
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

      test('a shared field with the id retrim is refused at its id', () {
        expect(
          () => _parse('shared_fields:\n  - id: retrim\n    type: string\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_fields[0].id',
              message: 'a shared field takes no built-in field id: retrim',
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

    group('shared patterns', () {
      test('a complete banned pattern reads with and without sections', () {
        final shared = _parse(r'''
shared_banned_patterns:
  - id: no_todo
    pattern: TODO
    message: Resolve the TODO.
    in: all
    except: [TODO\(x\)]
    for_doc_types: [story, fr]
    sections: [use_case]
  - id: no_tbd
    pattern: TBD
    message: Resolve the TBD.
    for_doc_types: [fr]
''');

        final [withSections, withoutSections] = shared.patterns;
        expect(withSections.id, 'no_todo');
        expect(withSections.kind, SharedPatternKind.banned);
        expect(withSections.pattern, 'TODO');
        expect(withSections.message, 'Resolve the TODO.');
        expect(withSections.scope, PatternScope.all);
        expect(withSections.except, [r'TODO\(x\)']);
        expect(withSections.forDocTypes, ['story', 'fr']);
        expect(withSections.sections, ['use_case']);
        expect(withSections.disabled, isFalse);
        expect(withSections.file, _file);
        expect(withSections.index, 0);
        expect(withoutSections.sections, isNull);
        expect(withoutSections.scope, isNull);
        expect(withoutSections.except, isNull);
        expect(withoutSections.index, 1);
      });

      test('a shared required pattern reads its in scope', () {
        final shared = _parse(
          'shared_required_patterns:\n'
          '  - {id: a, pattern: y, message: n, in: all, for_doc_types: [fr]}\n',
        );

        expect(shared.patterns.single.scope, PatternScope.all);
      });

      test('a required pattern with no sections parses', () {
        final shared = _parse('''
shared_required_patterns:
  - id: has_owner
    pattern: Owner
    message: Name the Owner.
    per_subsection: true
    for_doc_types: [story]
''');

        final pattern = shared.patterns.single;
        expect(pattern.kind, SharedPatternKind.required);
        expect(pattern.perSubsection, isTrue);
        expect(pattern.sections, isNull);
      });

      test('banned patterns come before required ones, each in file order', () {
        final shared = _parse('''
shared_required_patterns:
  - {id: r_b, pattern: x, message: m}
  - {id: r_a, pattern: x, message: m}
shared_banned_patterns:
  - {id: b_b, pattern: x, message: m}
  - {id: b_a, pattern: x, message: m}
''');

        expect(shared.patterns.map((p) => p.id), ['b_b', 'b_a', 'r_b', 'r_a']);
      });

      test(
        'a pattern entry that writes only disabled carries no other key',
        () {
          final shared = _parse(
            'shared_banned_patterns:\n  - id: no_todo\n    disabled: true\n',
          );

          final pattern = shared.patterns.single;
          expect(pattern.disabled, isTrue);
          expect(pattern.pattern, isNull);
          expect(pattern.message, isNull);
          expect(pattern.forDocTypes, isNull);
          expect(pattern.sections, isNull);
        },
      );

      test('a pattern entry that writes only message keeps the message', () {
        final shared = _parse(
          'shared_required_patterns:\n  - id: has_owner\n    message: New.\n',
        );

        final pattern = shared.patterns.single;
        expect(pattern.message, 'New.');
        expect(pattern.pattern, isNull);
      });

      test('an empty for_doc_types on a pattern is unknown_value', () {
        expect(
          () => _parse(
            'shared_required_patterns:\n'
            '  - {id: a, pattern: x, message: m}\n'
            '  - {id: b, pattern: x, message: m, for_doc_types: []}\n',
          ),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_required_patterns[1].for_doc_types',
              message: 'for_doc_types holds no doc type',
            ),
          ),
        );
      });

      test('a repeated pattern id in one list is refused at the second id', () {
        expect(
          () => _parse(
            'shared_banned_patterns:\n'
            '  - {id: a, pattern: x, message: m}\n'
            '  - {id: a, disabled: true}\n',
          ),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_banned_patterns[1].id',
              message: 'shared entry id repeated: a',
            ),
          ),
        );
      });

      test('a banned and a required pattern may share one id', () {
        final shared = _parse(
          'shared_banned_patterns:\n  - {id: a, pattern: x, message: m}\n'
          'shared_required_patterns:\n  - {id: a, pattern: y, message: n}\n',
        );

        expect(shared.patterns.map((p) => (p.id, p.kind)), [
          ('a', SharedPatternKind.banned),
          ('a', SharedPatternKind.required),
        ]);
      });

      test('an unknown key on a pattern is unknown_key at that key', () {
        for (final (list, key) in [
          ('shared_banned_patterns', 'colour'),
          ('shared_banned_patterns', 'per_subsection'),
          ('shared_required_patterns', 'except'),
        ]) {
          expect(
            () => _parse('$list:\n  - id: a\n    $key: x\n'),
            throwsA(
              _fault(
                FaultCode.unknownKey,
                key: '$list[0].$key',
                message: 'the pack format defines no key $key',
              ),
            ),
            reason: '$list $key',
          );
        }
      });

      test('a pattern id that is no slug loads', () {
        final shared = _parse(
          'shared_banned_patterns:\n'
          '  - {id: No-Todo, pattern: x, message: m}\n',
        );

        expect(shared.patterns.single.id, 'No-Todo');
      });

      test('a pattern that does not compile is unknown_value at pattern', () {
        expect(
          () =>
              _parse('shared_banned_patterns:\n  - id: a\n    pattern: "("\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_banned_patterns[0].pattern',
            ),
          ),
        );
      });

      test('an except that does not compile is unknown_value at except', () {
        expect(
          () =>
              _parse('shared_banned_patterns:\n  - id: a\n    except: ["("]\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_banned_patterns[0].except',
            ),
          ),
        );
      });

      test('an in value outside text, code, and all is unknown_value', () {
        expect(
          () => _parse('shared_banned_patterns:\n  - id: a\n    in: prose\n'),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'shared_banned_patterns[0].in',
              message: 'the key in must be text, code, or all',
            ),
          ),
        );
      });

      test('a null except reads as unwritten', () {
        final shared = _parse(
          'shared_banned_patterns:\n  - id: a\n    except: ~\n',
        );

        expect(shared.patterns.single.except, isNull);
      });

      test('a pattern with no id is missing_key at its id', () {
        expect(
          () => _parse('shared_banned_patterns:\n  - pattern: x\n'),
          throwsA(
            _fault(FaultCode.missingKey, key: 'shared_banned_patterns[0].id'),
          ),
        );
      });
    });
  });
}
