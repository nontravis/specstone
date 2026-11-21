import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart'
    show readDocText, writtenText;
import 'package:specstone_core/src/setup_migration/project_files.dart'
    show parseOverrides;
import 'package:specstone_core/src/setup_migration/shared_copies_step.dart';
import 'package:specstone_core/src/templates/layer_source.dart'
    show loadProjectTemplates;
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _templates = '.specstone/templates';
const _personal = '~/.specstone/packs/mine';
const _statusLine = 'Never write a status field.';
const _apiLine = 'Describes one HTTP operation.';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// One pack: three doc types, shared lines of every reach and a text two ids
/// share, and one shared field.
Map<String, Uint8List> _shipped() => {
  'acme/pack.yaml': _bytes('''
name: acme
version: 1.0.0
shared_lines:
  - {id: no_status, text: $_statusLine}
  - {id: api_note, text: Name the status code., for_doc_types: [api]}
  - {id: runbook_owner, text: Name the owner., for_doc_types: [runbook]}
  - {id: any_owner, text: Name the owner.}
  - {id: dup_one, text: Say it once.}
  - {id: dup_two, text: Say it once.}
shared_fields:
  - id: overrides
    type: string
    list: true
    description: Shared overrides.
    for_doc_types: [api, runbook]
'''),
  'acme/api.yaml': _bytes('''
id: api
description: $_apiLine
path: api/{slug}.md
fields:
  - {id: base_url, type: string}
'''),
  'acme/runbook.yaml': _bytes('''
id: runbook
description: Describes one routine.
path: runbooks/{slug}.md
'''),
  'mine/pack.yaml': _bytes('name: mine\nversion: 1.0.0\nextends: acme\n'),
  'mine/api.yaml': _bytes('fields:\n  - {id: overrides, description: Mine.}\n'),
};

/// The merged set of [packs], the project layers [texts] holds by path, and
/// the project shared lines [lines].
MergedSet _resolve(
  Map<String, String> texts,
  List<String> packs,
  List<SharedLine> lines,
) => TemplateResolver(shippedFiles: _shipped()).resolveCarried(
  packNames: packs,
  homeDirectory: null,
  projectLayers: parseOverrides(texts),
  projectSharedLines: lines,
);

SharedCopiesStep _step(
  Map<String, String> project, {
  Map<String, String> personal = const {},
  List<SharedLine> lines = const [],
  List<String> packs = const ['acme'],
}) {
  final texts = {
    for (final MapEntry(:key, :value) in project.entries)
      '$_templates/$key': value,
  };
  return planSharedCopies(
    projectFiles: [
      for (final MapEntry(:key, :value) in texts.entries)
        ProjectLayerFile(path: key, lf: value),
    ],
    target: _resolve(texts, packs, lines),
    personalFiles: [
      for (final MapEntry(:key, :value) in personal.entries)
        PersonalPackFile(path: '$_personal/$key', lf: value),
    ],
    resolveWith: (changed) => _resolve(changed, packs, lines),
  );
}

String _written(SharedCopiesStep step, String file) =>
    step.rewrites['$_templates/$file']!;

void main() {
  group('a description line', () {
    test('equal to a reaching shared line of any pack is removed from a '
        'block scalar and every other line stays', () {
      final step = _step({
        'api.yaml':
            '# Kept comment.\n'
            'description: |-\n'
            '  $_apiLine\n'
            '  $_statusLine\n'
            '  Name the status code.\n'
            'fields:\n'
            '  - {id: owner, type: string}\n',
      });

      expect(
        _written(step, 'api.yaml'),
        '# Kept comment.\n'
        'description: |-\n'
        '  $_apiLine\n'
        'fields:\n'
        '  - {id: owner, type: string}\n',
      );
      expect(step.stripped, [
        '$_templates/api.yaml:4 no_status',
        '$_templates/api.yaml:5 api_note',
      ]);
      expect(step.left, isEmpty);
      expect(step.leftLine, isNull);
    });

    test('is removed from a clip block scalar and the blank line after it '
        'stays', () {
      final step = _step({
        'api.yaml':
            'description: |\n'
            '  $_statusLine\n'
            '  $_apiLine\n'
            '\n'
            'fields:\n'
            '  - {id: owner, type: string}\n',
      });

      expect(
        _written(step, 'api.yaml'),
        'description: |\n'
        '  $_apiLine\n'
        '\n'
        'fields:\n'
        '  - {id: owner, type: string}\n',
      );
      expect(step.stripped, ['$_templates/api.yaml:2 no_status']);
    });

    test('that is the whole scalar of an override drops the key so the '
        'lower layer shows', () {
      final step = _step({
        'api.yaml':
            'description: $_statusLine\n'
            'fields:\n'
            '  - {id: owner, type: string}\n',
        'runbook.yaml':
            'description: |-\n'
            '  $_statusLine\n'
            '  Say it once.\n'
            'sections:\n'
            '  - {id: steps, header: Steps}\n',
      });

      expect(
        _written(step, 'api.yaml'),
        'fields:\n  - {id: owner, type: string}\n',
      );
      expect(
        _written(step, 'runbook.yaml'),
        'sections:\n  - {id: steps, header: Steps}\n',
      );
      expect(step.stripped, [
        '$_templates/api.yaml:1 no_status',
        '$_templates/runbook.yaml:2 no_status',
        '$_templates/runbook.yaml:3 dup_one',
      ]);
      expect(step.left, isEmpty);
    });

    test('that would leave a doc type no lower layer defines with no '
        'description is kept and counts as left', () {
      final step = _step({
        'note.yaml':
            'id: note\n'
            'path: notes/{slug}.md\n'
            'description: |-\n'
            '  $_statusLine\n',
        'memo.yaml':
            'id: memo\n'
            'path: memos/{slug}.md\n'
            'description: |-\n'
            '  $_statusLine\n'
            '  Say it once.\n',
      });

      expect(step.rewrites.keys, ['$_templates/memo.yaml']);
      expect(
        _written(step, 'memo.yaml'),
        'id: memo\n'
        'path: memos/{slug}.md\n'
        'description: |-\n'
        '  Say it once.\n',
      );
      expect(step.stripped, ['$_templates/memo.yaml:4 no_status']);
      expect(step.left, [
        '$_templates/note.yaml:4 no_status',
        '$_templates/memo.yaml:5 dup_one',
      ]);
      expect(step.leftLine, 'shared copies left: 2');
    });

    test('that differs from every shared line, or equals one the doc type '
        'is not reached by, is kept and counts nothing', () {
      final step = _step({
        'api.yaml':
            'description: |-\n'
            '  $_apiLine\n'
            '  never write a status field.\n'
            '  Name the owner. \n'
            '  Name the owner.\n',
        'runbook.yaml':
            'description: |-\n'
            '  Describes one routine.\n'
            '  Name the status code.\n',
      });

      expect(step.rewrites.keys, ['$_templates/api.yaml']);
      expect(
        _written(step, 'api.yaml'),
        'description: |-\n'
        '  $_apiLine\n'
        '  never write a status field.\n'
        '  Name the owner. \n',
      );
      expect(step.stripped, ['$_templates/api.yaml:5 any_owner']);
      expect(step.left, isEmpty);
    });

    test('equal to two entries is one copy under the entry printed first, '
        'whichever of them reaches the doc type', () {
      final step = _step({
        'api.yaml':
            'description: |-\n'
            '  $_apiLine\n'
            '  Say it once.\n'
            '  Name the owner.\n',
        'runbook.yaml':
            'description: |-\n'
            '  Describes one routine.\n'
            '  Name the owner.\n',
      });

      expect(step.stripped, [
        '$_templates/api.yaml:3 dup_one',
        '$_templates/api.yaml:4 any_owner',
        '$_templates/runbook.yaml:3 runbook_owner',
      ]);
    });

    test('equal to a shared.yaml line and a pack line is listed under the '
        'pack line printed first', () {
      final step = _step(
        {'api.yaml': 'description: |-\n  $_apiLine\n  $_statusLine\n'},
        lines: [
          SharedLine(
            id: 'mine',
            text: _statusLine,
            disabled: false,
            file: '$_templates/shared.yaml',
            index: 0,
          ),
        ],
      );

      expect(step.stripped, ['$_templates/api.yaml:3 no_status']);
    });

    test('equal to a line shared.yaml disabled is kept and counts nothing', () {
      final step = _step(
        {'api.yaml': 'description: |-\n  $_apiLine\n  $_statusLine\n'},
        lines: [
          SharedLine(
            id: 'no_status',
            disabled: true,
            file: '$_templates/shared.yaml',
            index: 0,
          ),
        ],
      );

      expect(step.rewrites, isEmpty);
      expect(step.stripped, isEmpty);
      expect(step.left, isEmpty);
    });

    test('whose removal would change the indentation of the line after it '
        'is kept and counts as left', () {
      const text =
          'description: |-\n'
          '  $_statusLine\n'
          '    Indented own text.\n';

      final step = _step({'api.yaml': text});

      expect(step.rewrites, isEmpty);
      expect(step.stripped, isEmpty);
      expect(step.left, ['$_templates/api.yaml:2 no_status']);
    });

    test('in a CRLF project file matches, and the written text keeps CRLF', () {
      final original = readDocText(
        utf8.encode(
          'description: |-\r\n'
          '  $_apiLine\r\n'
          '  $_statusLine\r\n',
        ),
      );

      final step = _step({'api.yaml': original.lf});

      expect(step.stripped, ['$_templates/api.yaml:3 no_status']);
      expect(
        writtenText(original, _written(step, 'api.yaml')),
        'description: |-\r\n  $_apiLine\r\n',
      );
    });
  });

  group('a field entry', () {
    test('equal in every property to a shared field is removed with its '
        'whole block, and the entry reads at its id line', () {
      final step = _step({
        'api.yaml':
            'fields:\n'
            '  - type: string\n'
            '    id: overrides\n'
            '    list: true\n'
            '    description: Shared overrides.\n'
            '  - {id: owner, type: string}\n',
        'runbook.yaml':
            'fields:\n'
            '  - {id: overrides, type: string, list: true, '
            'description: Shared overrides.}\n'
            '  - {id: owner, type: string}\n',
      });

      expect(
        _written(step, 'api.yaml'),
        'fields:\n  - {id: owner, type: string}\n',
      );
      expect(
        _written(step, 'runbook.yaml'),
        'fields:\n  - {id: owner, type: string}\n',
      );
      expect(step.stripped, [
        '$_templates/api.yaml:3 overrides',
        '$_templates/runbook.yaml:2 overrides',
      ]);
      expect(step.left, isEmpty);
    });

    test('that leaves the list empty drops the fields key', () {
      final step = _step({
        'api.yaml':
            'description: Own words.\n'
            'fields:\n'
            '  - {id: overrides, type: string, list: true, '
            'description: Shared overrides.}\n',
      });

      expect(_written(step, 'api.yaml'), 'description: Own words.\n');
    });

    test('that differs in one property, or writes fewer properties than the '
        'shared field, is no copy and stays', () {
      const rest = 'type: string, description: Shared overrides.';
      for (final entry in [
        '{id: overrides, list: true, type: string, description: Mine.}',
        '{id: overrides, description: Shared overrides.}',
        '{id: overrides, list: false, $rest}',
        '{id: overrides, list: true, bundle_with: true, $rest}',
        '{id: overrides, disabled: true}',
      ]) {
        final step = _step({'api.yaml': 'fields:\n  - $entry\n'});

        expect(step.rewrites, isEmpty, reason: entry);
        expect(step.stripped, isEmpty, reason: entry);
        expect(step.left, isEmpty, reason: entry);
      }
    });

    test('whose removal changes the merged field, since a layer between the '
        'shared field and the project writes it, stays and counts as left', () {
      const copy =
          'fields:\n'
          '  - {id: overrides, type: string, list: true, '
          'description: Shared overrides.}\n';

      final step = _step({'api.yaml': copy}, packs: const ['acme', 'mine']);

      expect(step.rewrites, isEmpty);
      expect(step.stripped, isEmpty);
      expect(step.left, ['$_templates/api.yaml:2 overrides']);
      expect(_step({'api.yaml': copy}).stripped, hasLength(1));
    });

    test('equal to a shared field the doc type is not reached by is no '
        'copy and stays', () {
      final step = _step({
        'note.yaml':
            'id: note\n'
            'path: notes/{slug}.md\n'
            'description: Own words.\n'
            'fields:\n'
            '  - {id: overrides, type: string, list: true, '
            'description: Shared overrides.}\n',
      });

      expect(step.rewrites, isEmpty);
      expect(step.left, isEmpty);
    });
  });

  group('a personal pack file', () {
    test('holding a copy is never rewritten and counts as left under its '
        'home path', () {
      final step = _step(
        const {},
        personal: {
          'api.yaml':
              'id: api\n'
              'description: |-\n'
              '  $_apiLine\n'
              '  $_statusLine\n'
              'path: api/{slug}.md\n'
              'fields:\n'
              '  - {id: overrides, type: string, list: true, '
              'description: Shared overrides.}\n',
        },
      );

      expect(step.rewrites, isEmpty);
      expect(step.stripped, isEmpty);
      expect(step.left, [
        '$_personal/api.yaml:4 no_status',
        '$_personal/api.yaml:7 overrides',
      ]);
      expect(step.leftLine, 'shared copies left: 2');
    });
  });

  for (final (name, text, entries) in [
    (
      'a folded description',
      'description: >-\n  A runbook.\n\n  $_statusLine\n',
      ['api.yaml:4 no_status'],
    ),
    (
      'a folded description holding one line twice, each at its own line',
      'description: >-\n  $_statusLine\n\n  $_statusLine\n',
      ['api.yaml:2 no_status', 'api.yaml:4 no_status'],
    ),
    (
      'a multi-line plain description',
      'description: A runbook.\n\n  $_statusLine\n',
      ['api.yaml:3 no_status'],
    ),
    (
      'a multi-line quoted description, at the line holding its closing quote',
      'description: "A runbook.\n\n  $_statusLine"\n',
      ['api.yaml:3 no_status'],
    ),
    (
      'a flow root description',
      '{description: $_statusLine}\n',
      ['api.yaml:1 no_status'],
    ),
    (
      'a flow root field',
      '{fields: [{id: overrides, type: string, list: true, '
          'description: Shared overrides.}]}\n',
      ['api.yaml:1 overrides'],
    ),
  ]) {
    test('a copy in $name is kept and counts as left', () {
      final step = _step({'api.yaml': text});

      expect(step.rewrites, isEmpty);
      expect(step.stripped, isEmpty);
      expect(step.left, [for (final entry in entries) '$_templates/$entry']);
      expect(step.leftLine, 'shared copies left: ${entries.length}');
    });
  }

  test('a project with no copy plans nothing and prints no left line', () {
    final step = _step({'api.yaml': 'description: Own words.\n'});

    expect(step.rewrites, isEmpty);
    expect(step.stripped, isEmpty);
    expect(step.left, isEmpty);
    expect(step.leftLine, isNull);
  });

  test(
    'an entry reads the path the project loader gives, `/`-separated',
    () async {
      const text = 'description: |-\n  $_apiLine\n  $_statusLine\n';
      final root = await writeTree({'$_templates/api.yaml': text});
      final layer = loadProjectTemplates(root).single;

      final step = planSharedCopies(
        projectFiles: [ProjectLayerFile(path: layer.file, lf: text)],
        target: _resolve({layer.file: text}, const ['acme'], const []),
        personalFiles: const [],
        resolveWith: (changed) => _resolve(changed, const ['acme'], const []),
      );

      expect(step.stripped, ['.specstone/templates/api.yaml:3 no_status']);
    },
  );
}
