import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';
const _templates = '.specstone/templates';
const _apiText = 'Describes one HTTP operation.';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// The shipped packs: an empty one the config must pin, and the pack under
/// test with two doc types, three shared lines, and two shared fields.
Map<String, Uint8List> _shipped() => {
  'prd-core/pack.yaml': _bytes('name: prd-core\nversion: 1.0.0\n'),
  'software-tech/pack.yaml': _bytes('''
name: software-tech
version: 1.0.0
shared_lines:
  - id: everywhere
    text: Say each thing once.
  - id: api_only
    text: Name the status code.
    for_doc_types: [api]
  - id: runbook_only
    text: List the steps.
    for_doc_types: [runbook]
shared_fields:
  - id: overrides
    type: string
    list: true
    description: Shared overrides.
    for_doc_types: [api, runbook]
  - id: tasks
    type: task_ref
    list: true
    description: Shared tasks.
    for_doc_types: [api, runbook]
'''),
  'software-tech/api.yaml': _bytes('''
id: api
description: $_apiText
path: api/{slug}.md
fields:
  - id: base_url
    type: string
'''),
  'software-tech/runbook.yaml': _bytes('''
id: runbook
description: Describes one operating routine.
path: runbooks/{slug}.md
'''),
};

/// Resolves a project holding [templates], keyed by file name under the
/// project templates folder.
Future<MergedSet> _resolve(Map<String, String> templates) async {
  final project = await writeTree({
    _configPath: 'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n',
    for (final MapEntry(:key, :value) in templates.entries)
      '$_templates/$key': value,
  });
  return TemplateResolver(shippedFiles: _shipped())
      .resolve(workingDirectory: project, homeDirectory: await writeTree({}));
}

/// The pack that extends the pack under test: it adds a field to the first
/// doc type and declares a shared field for it, and holds no layer of the
/// second doc type.
Map<String, Uint8List> _extendingShipped() => {
  ..._shipped(),
  'software-plus/pack.yaml': _bytes('''
name: software-plus
version: 1.0.0
extends: software-tech
shared_fields:
  - id: plus_shared
    type: string
    for_doc_types: [api, runbook]
'''),
  'software-plus/api.yaml': _bytes('''
fields:
  - id: plus_field
    type: string
'''),
};

MergedDocType _type(MergedSet set, String id) => set.lookup(id)!;

/// The ids of the fields of [type] that are not built in, in order.
List<String> _fieldIds(MergedDocType type) => [
  for (final field in type.fields)
    if (!field.isBuiltIn) field.id,
];

List<String> _lineIds(MergedDocType type) => [
  for (final line in type.sharedLines) line.id,
];

String _description(MergedDocType type, String fieldId) =>
    type.fields.singleWhere((field) => field.id == fieldId).description!;

void main() {
  group('a shared field in the field order', () {
    test(
      'sits after its pack layer fields and before a project field',
      () async {
        final set = await _resolve({
          'api.yaml': 'fields:\n  - id: project_added\n    type: string\n',
        });

        expect(_fieldIds(_type(set, 'api')), [
          'base_url',
          'overrides',
          'tasks',
          'project_added',
        ]);
      },
    );

    test('is the same field a project layer of one type changes, for that '
        'type alone', () async {
      final set = await _resolve({
        'api.yaml': 'fields:\n  - id: tasks\n    description: Project tasks.\n',
      });

      expect(_fieldIds(_type(set, 'api')), ['base_url', 'overrides', 'tasks']);
      expect(_description(_type(set, 'api'), 'tasks'), 'Project tasks.');
      expect(_description(_type(set, 'runbook'), 'tasks'), 'Shared tasks.');
    });

    test(
      'is dropped from an extending project type that disables it',
      () async {
        final set = await _resolve({
          'project_api.yaml': '''
id: project_api
extends: api
path: project_api/{slug}.md
description: A project operation.
fields:
  - id: overrides
    disabled: true
''',
        });

        expect(_fieldIds(_type(set, 'project_api')), ['base_url', 'tasks']);
        expect(_fieldIds(_type(set, 'api')), [
          'base_url',
          'overrides',
          'tasks',
        ]);
      },
    );

    test('of a higher pack follows that pack layer, and follows the lower '
        'layer when the pack holds none', () async {
      final project = await writeTree({
        _configPath:
            'packs:\n  prd-core: 1.0.0\n  software-plus: 1.0.0\n'
            '  software-tech: 1.0.0\n',
      });
      final set = TemplateResolver(
        shippedFiles: _extendingShipped(),
      ).resolve(workingDirectory: project, homeDirectory: await writeTree({}));

      expect(_fieldIds(_type(set, 'api')), [
        'base_url',
        'overrides',
        'tasks',
        'plus_field',
        'plus_shared',
      ]);
      expect(_fieldIds(_type(set, 'runbook')), [
        'overrides',
        'tasks',
        'plus_shared',
      ]);
    });

    test('reaches an extending type through its base', () async {
      final set = await _resolve({
        'my_api.yaml': 'id: my_api\nextends: api\npath: my_api/{slug}.md\n',
      });

      expect(_fieldIds(_type(set, 'my_api')), [
        'base_url',
        'overrides',
        'tasks',
      ]);
    });
  });

  group('shared lines reaching a doc type', () {
    test('an extending type with no description keeps its base text and '
        'each reaching line once', () async {
      final set = await _resolve({
        'my_api.yaml': 'id: my_api\nextends: api\npath: my_api/{slug}.md\n',
        'shared.yaml': '''
shared_lines:
  - id: extension_only
    text: Name the caller.
    for_doc_types: [my_api]
  - id: everywhere_again
    text: Cut every filler word.
''',
      });

      expect(_type(set, 'my_api').description, _apiText);
      expect(_lineIds(_type(set, 'my_api')), [
        'everywhere',
        'api_only',
        'extension_only',
        'everywhere_again',
      ]);
      expect(_lineIds(_type(set, 'api')), [
        'everywhere',
        'api_only',
        'everywhere_again',
      ]);
    });

    test('an extending type with its own description takes only the lines '
        'naming it or naming no type', () async {
      final set = await _resolve({
        'my_api.yaml': '''
id: my_api
extends: api
path: my_api/{slug}.md
description: A project operation.
''',
        'shared.yaml': '''
shared_lines:
  - id: extension_only
    text: Name the caller.
    for_doc_types: [my_api]
''',
      });

      expect(_type(set, 'my_api').description, 'A project operation.');
      expect(_lineIds(_type(set, 'my_api')), ['everywhere', 'extension_only']);
    });

    test('a type that extends nothing takes only the lines naming it or '
        'naming no type', () async {
      final set = await _resolve({});

      expect(_lineIds(_type(set, 'runbook')), ['everywhere', 'runbook_only']);
    });

    test('an extending type reaches a line through a chain of bases', () async {
      final set = await _resolve({
        'my_api.yaml': 'id: my_api\nextends: api\npath: my_api/{slug}.md\n',
        'deep_api.yaml':
            'id: deep_api\nextends: my_api\npath: deep_api/{slug}.md\n',
      });

      expect(_lineIds(_type(set, 'deep_api')), ['everywhere', 'api_only']);
    });
  });
}
