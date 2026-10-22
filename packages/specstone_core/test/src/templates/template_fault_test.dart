import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

void main() {
  const catalog = [
    'yaml_syntax',
    'unknown_key',
    'unknown_value',
    'missing_key',
    'doc_type_id_mismatch',
    'doc_type_path_conflict',
    'override_id_not_found',
    'lint_word_not_found',
    'list_override_needs_add_remove',
    'after_id_not_found',
    'extends_cycle',
    'parent_cycle',
    'extends_target_unknown',
    'doc_type_duplicate',
    'locked_field_disabled',
    'reference_link_conflict',
    'reference_file_missing',
    'reference_file_outside',
    'reference_doc_outside_project',
    'reference_title_not_found',
    'pack_not_found',
    'pack_version_invalid',
    'pack_name_mismatch',
    'personal_pack_conflict',
    'personal_pack_version_differs',
    'pack_pin_older',
    'pack_pin_newer',
    'prd_core_missing',
    'doc_type_unknown',
  ];

  group('FaultCode', () {
    test('f03/s05/catalog: wire codes equal the 29 catalog codes in order', () {
      expect(FaultCode.values.map((c) => c.wire), catalog);
      expect(FaultCode.values, hasLength(29));
    });

    test('f03/s05/catalog: only docTypeUnknown exits 64, the rest 78', () {
      for (final code in FaultCode.values) {
        expect(
          code.exitStatus,
          code == FaultCode.docTypeUnknown ? 64 : 78,
          reason: code.wire,
        );
      }
    });

    test('f03/s05/catalog: value names are the camelCase of the wire code', () {
      for (final code in FaultCode.values) {
        final camel = code.wire.replaceAllMapped(
          RegExp('_([a-z])'),
          (m) => m[1]!.toUpperCase(),
        );
        expect(code.name, camel);
      }
    });
  });

  group('TemplateFault', () {
    test('f03/us01/fr01/e04, f03/us01/fr03/e04: yaml fault JSON has a line '
        'and no key or relatedFiles', () {
      final fault = TemplateFault(
        FaultCode.yamlSyntax,
        'mapping values are not allowed here',
        file: '.specstone/templates/feature.yaml',
        line: 12,
      );

      expect(fault.toJson(), {
        'error': {
          'code': 'yaml_syntax',
          'message': 'mapping values are not allowed here',
          'file': '.specstone/templates/feature.yaml',
          'line': 12,
        },
      });
    });

    test('f03/us01/fr01/e04, f03/us01/fr03/e04: parent_cycle JSON keeps '
        'relatedFiles', () {
      final fault = TemplateFault(
        FaultCode.parentCycle,
        'parent chain returns to its start: epic, story, epic',
        file: '.specstone/templates/story.yaml',
        key: 'parent',
        relatedFiles: ['.specstone/templates/epic.yaml'],
      );

      expect(fault.toJson(), {
        'error': {
          'code': 'parent_cycle',
          'message': 'parent chain returns to its start: epic, story, epic',
          'file': '.specstone/templates/story.yaml',
          'key': 'parent',
          'relatedFiles': ['.specstone/templates/epic.yaml'],
        },
      });
    });

    test('f03/us01/fr01/e04: JSON of a fault with no file has only code and '
        'message', () {
      final fault = TemplateFault(
        FaultCode.docTypeUnknown,
        'no doc type named widget',
      );

      expect(fault.toJson(), {
        'error': {
          'code': 'doc_type_unknown',
          'message': 'no doc type named widget',
        },
      });
    });

    test('f03/us01/fr01/e04: getters expose every constructor argument', () {
      final fault = TemplateFault(
        FaultCode.unknownKey,
        'the doc-type format defines no key prefixId',
        file: 'a.yaml',
        key: 'prefixId',
        line: 3,
        relatedFiles: ['b.yaml'],
      );

      expect(fault.code, FaultCode.unknownKey);
      expect(fault.message, 'the doc-type format defines no key prefixId');
      expect(fault.file, 'a.yaml');
      expect(fault.key, 'prefixId');
      expect(fault.line, 3);
      expect(fault.relatedFiles, ['b.yaml']);
      expect(fault.exitStatus, 78);
      expect(fault, isA<Exception>());
    });

    test('f03/us01/fr01/e04: toText of a yaml fault is file:line: message', () {
      final fault = TemplateFault(
        FaultCode.yamlSyntax,
        'mapping values are not allowed here',
        file: '.specstone/templates/feature.yaml',
        line: 12,
      );

      expect(
        fault.toText(),
        '.specstone/templates/feature.yaml:12: '
        'mapping values are not allowed here',
      );
    });

    test('f03/us01/fr01/e04: toText with a key is file: key: message', () {
      final fault = TemplateFault(
        FaultCode.unknownKey,
        'the doc-type format defines no key prefixId',
        file: '.specstone/templates/feature.yaml',
        key: 'sections.goal.prefixId',
      );

      expect(
        fault.toText(),
        '.specstone/templates/feature.yaml: sections.goal.prefixId: '
        'the doc-type format defines no key prefixId',
      );
    });

    test('f03/us01/fr01/e04: toText names related files after "also"', () {
      final fault = TemplateFault(
        FaultCode.parentCycle,
        'parent chain returns to its start: epic, story, epic',
        file: '.specstone/templates/story.yaml',
        key: 'parent',
        relatedFiles: [
          '.specstone/templates/epic.yaml',
          '.specstone/templates/task.yaml',
        ],
      );

      expect(
        fault.toText(),
        '.specstone/templates/story.yaml: parent: parent chain returns to '
        'its start: epic, story, epic; also '
        '.specstone/templates/epic.yaml, .specstone/templates/task.yaml',
      );
    });

    test('f03/us01/fr01/e04: toText with no file is the message alone', () {
      final fault = TemplateFault(
        FaultCode.docTypeUnknown,
        'no doc type named widget',
      );

      expect(fault.toText(), 'no doc type named widget');
    });

    test('f03/us01/fr01/e04: toString is the text form', () {
      final fault = TemplateFault(
        FaultCode.yamlSyntax,
        'bad',
        file: 'a.yaml',
        line: 2,
      );

      expect(fault.toString(), fault.toText());
    });
  });
}
