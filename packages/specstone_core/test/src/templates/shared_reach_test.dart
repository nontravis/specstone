// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
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

/// Resolves a project that pins prd-core and [packs], over [shipped].
Future<MergedSet> _resolvePacks(
  Map<String, Uint8List> shipped,
  List<String> packs,
) async {
  final project = await writeTree({
    _configPath: [
      'packs:',
      '  prd-core: 1.0.0',
      for (final pack in packs) '  $pack: 1.0.0',
      '',
    ].join('\n'),
  });
  return TemplateResolver(shippedFiles: shipped)
      .resolve(workingDirectory: project, homeDirectory: await writeTree({}));
}

const _patternPack = '''
name: prd-core
version: 1.0.0
shared_banned_patterns:
  - id: history
    pattern: was changed
    message: Drop the history.
    for_doc_types: [fr, nf]
  - id: second_shall
    pattern: shall.*shall
    message: Write one shall.
    for_doc_types: [fr, nf]
    sections: [statement]
shared_required_patterns:
  - id: then_line
    pattern: Then
    message: Name the outcome.
    for_doc_types: [fr, nf]
    sections: [cases]
''';

const _frFile = '''
id: fr
description: Describes one requirement.
path: frs/{slug}.md
sections:
  - id: statement
    header: Statement
  - id: cases
    header: Edge cases
lint:
  banned_patterns:
    - id: own_rule
      pattern: TBD
      message: Settle it.
''';

/// The shipped `prd-core` declaring two shared banned patterns and one shared
/// required pattern: `fr` holds `statement` and `cases`, `nf` holds
/// `statement` alone, and no pattern names `glossary`.
Map<String, Uint8List> _patternShipped({
  String pack = _patternPack,
  String fr = _frFile,
}) => {
  'prd-core/pack.yaml': _bytes(pack),
  'prd-core/fr.yaml': _bytes(fr),
  'prd-core/nf.yaml': _bytes('''
id: nf
description: Describes one quality need.
path: nfs/{slug}.md
sections:
  - id: statement
    header: Statement
'''),
  'prd-core/glossary.yaml': _bytes('''
id: glossary
description: Lists the terms.
path: GLOSSARY.md
'''),
};

/// Resolves a project pinning `prd-core` and the personal packs [home]
/// holds by [personal] name, with [templates] under the project templates
/// folder.
Future<MergedSet> _resolvePatterns(
  Map<String, String> templates, {
  Map<String, Uint8List>? shipped,
  Map<String, String> home = const {},
  List<String> personal = const [],
}) async {
  final project = await writeTree({
    _configPath: [
      'packs:',
      '  prd-core: 1.0.0',
      for (final pack in personal) '  $pack: 1.0.0',
      '',
    ].join('\n'),
    for (final MapEntry(:key, :value) in templates.entries)
      '$_templates/$key': value,
  });
  return TemplateResolver(shippedFiles: shipped ?? _patternShipped())
      .resolve(workingDirectory: project, homeDirectory: await writeTree(home));
}

List<String> _patternIds(List<PatternEntry>? entries) => [
  for (final entry in entries ?? const <PatternEntry>[]) entry.id,
];

PatternEntry _docPattern(MergedDocType type, String id) =>
    type.lint.bannedPatterns!.singleWhere((entry) => entry.id == id);

MergedSection _section(MergedDocType type, String id) =>
    type.sections.singleWhere((section) => section.id == id);

TypeMatcher<TemplateFault> _faultAt(FaultCode code, String file, String key) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', file)
        .having((f) => f.key, 'key', key);

MergedField _field(MergedDocType type, String id) =>
    type.fields.singleWhere((field) => field.id == id);

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
      final shared = _field(_type(set, 'runbook'), 'tasks');
      final overridden = _field(_type(set, 'api'), 'tasks');
      expect(overridden.type, shared.type);
      expect(overridden.list, shared.list);
    });

    for (final (name, ownEntry) in [
      ('partial', '  - id: owner\n    description: Gadget owner.\n'),
      (
        'complete',
        '  - id: owner\n    type: string\n    description: Gadget owner.\n',
      ),
    ]) {
      test('is the field a $name own entry of the declaring pack changes, at '
          'the shared place, for that type alone', () async {
        final set = await _resolvePacks(
          {
            ..._shipped(),
            'software-own/pack.yaml': _bytes('''
name: software-own
version: 1.0.0
shared_fields:
  - id: owner
    type: string
    list: true
    description: Shared owner.
    for_doc_types: [gadget, widget]
'''),
            'software-own/gadget.yaml': _bytes('''
id: gadget
description: Describes one gadget.
path: gadgets/{slug}.md
fields:
  - id: gadget_name
    type: string
$ownEntry  - id: gadget_size
    type: string
'''),
            'software-own/widget.yaml': _bytes('''
id: widget
description: Describes one widget.
path: widgets/{slug}.md
'''),
          },
          ['software-own'],
        );

        final gadget = _type(set, 'gadget');
        expect(_fieldIds(gadget), ['gadget_name', 'gadget_size', 'owner']);
        expect(_description(gadget, 'owner'), 'Gadget owner.');
        expect(_field(gadget, 'owner').list, isTrue);
        expect(_description(_type(set, 'widget'), 'owner'), 'Shared owner.');
      });
    }

    test('of an extending pack naming its own new doc type applies after the '
        'last pack layer', () async {
      final set = await _resolvePacks(
        {
          ..._shipped(),
          'software-over/pack.yaml': _bytes('''
name: software-over
version: 1.0.0
extends: software-tech
shared_fields:
  - id: tasks
    for_doc_types: [gadget]
'''),
          'software-over/gadget.yaml': _bytes('''
id: gadget
description: Describes one gadget.
path: gadgets/{slug}.md
fields:
  - id: gadget_name
    type: string
'''),
        },
        ['software-over', 'software-tech'],
      );

      expect(_fieldIds(_type(set, 'gadget')), ['gadget_name', 'tasks']);
      expect(_field(_type(set, 'gadget'), 'tasks').list, isTrue);
    });

    test('that cannot apply is refused naming the pack file that declares '
        'it', () async {
      final shipped = {
        ..._shipped(),
        'software-bad/pack.yaml': _bytes('''
name: software-bad
version: 1.0.0
shared_fields:
  - id: artifact
    type: output_ref
    pointer: bogus
    for_doc_types: [gizmo]
'''),
        'software-bad/gizmo.yaml': _bytes('''
id: gizmo
description: Describes one gizmo.
path: gizmos/{slug}.md
'''),
      };

      await expectLater(
        _resolvePacks(shipped, ['software-bad']),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.file,
            'file',
            'packs/software-bad/pack.yaml',
          ),
        ),
      );
    });

    for (final key in ['pointer', 'root']) {
      test('changed by a higher pack to an unknown $key is refused at that '
          "pack's shared_fields entry", () async {
        final shipped = {
          ..._shipped(),
          'software-base/pack.yaml': _bytes('''
name: software-base
version: 1.0.0
shared_fields:
  - id: artifact
    type: output_ref
    pointer: exact
    for_doc_types: [gizmo]
'''),
          'software-base/gizmo.yaml': _bytes('''
id: gizmo
description: Describes one gizmo.
path: gizmos/{slug}.md
'''),
          'software-top/pack.yaml': _bytes('''
name: software-top
version: 1.0.0
extends: software-base
shared_fields:
  - id: artifact
    $key: bogus
'''),
        };

        await expectLater(
          _resolvePacks(shipped, ['software-base', 'software-top']),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.unknownValue)
                .having((f) => f.file, 'file', 'packs/software-top/pack.yaml')
                .having((f) => f.key, 'key', 'shared_fields[0].$key'),
          ),
        );
      });
    }

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

  group('a shared pattern reaching a doc type', () {
    test(
      'with no sections joins the doc-level banned list of each reached type',
      () async {
        final set = await _resolvePatterns({});

        expect(_patternIds(_type(set, 'fr').lint.bannedPatterns), [
          'own_rule',
          'history',
        ]);
        expect(_patternIds(_type(set, 'nf').lint.bannedPatterns), ['history']);
        expect(_type(set, 'glossary').lint.bannedPatterns, isNull);
      },
    );

    test(
      'with sections joins only the named sections of reached types',
      () async {
        final set = await _resolvePatterns({});
        final fr = _type(set, 'fr');

        expect(_patternIds(_section(fr, 'statement').bannedPatterns), [
          'second_shall',
        ]);
        expect(
          _patternIds(_section(fr, 'statement').requiredPatterns),
          isEmpty,
        );
        expect(_patternIds(_section(fr, 'cases').bannedPatterns), isEmpty);
        expect(_patternIds(_section(fr, 'cases').requiredPatterns), [
          'then_line',
        ]);
      },
    );

    test('a reached type lacking every named section takes no copy', () async {
      final set = await _resolvePatterns({});
      final nf = _type(set, 'nf');

      expect(_patternIds(_section(nf, 'statement').bannedPatterns), [
        'second_shall',
      ]);
      expect(_patternIds(_section(nf, 'statement').requiredPatterns), isEmpty);
      expect(nf.sections.map((s) => s.id), ['statement']);
    });

    test('sections matching no section of a reached type is unknown_value at that key', () async {
      for (final list in [
        'shared_banned_patterns',
        'shared_required_patterns',
      ]) {
        final shipped = _patternShipped(
          pack:
              '''
name: prd-core
version: 1.0.0
$list:
  - id: lost
    pattern: x
    message: Lost.
    for_doc_types: [nf]
    sections: [cases]
''',
        );

        await expectLater(
          _resolvePatterns({}, shipped: shipped),
          throwsA(
            _faultAt(
              FaultCode.unknownValue,
              'packs/prd-core/pack.yaml',
              '$list[0].sections',
            ),
          ),
        );
      }
    });

    test('sections an upper pack overlay writes that match none is unknown_value at that pack file', () async {
      await expectLater(
        _resolvePatterns(
          {},
          personal: ['nont-prd'],
          home: {
            '.specstone/packs/nont-prd/pack.yaml': '''
name: nont-prd
version: 1.0.0
extends: prd-core
shared_banned_patterns:
  - id: second_shall
    sections: [nope]
''',
          },
        ),
        throwsA(
          _faultAt(
            FaultCode.unknownValue,
            '~/.specstone/packs/nont-prd/pack.yaml',
            'shared_banned_patterns[0].sections',
          ),
        ),
      );
    });

    test('an extending project type takes it through its base', () async {
      final set = await _resolvePatterns({
        'my_fr.yaml': 'id: my_fr\nextends: fr\npath: my_fr/{slug}.md\n',
      });
      final myFr = _type(set, 'my_fr');

      expect(_patternIds(myFr.lint.bannedPatterns), ['own_rule', 'history']);
      expect(_patternIds(_section(myFr, 'statement').bannedPatterns), [
        'second_shall',
      ]);
      expect(_patternIds(_section(myFr, 'cases').requiredPatterns), [
        'then_line',
      ]);
    });

    test("the declaring pack's own doc type entry of its id is unknown_value at that id", () async {
      for (final (statementLint, casesTail, key) in [
        (
          '',
          'lint:\n  banned_patterns:\n'
              '    - {id: own_rule, pattern: TBD, message: Settle it.}\n'
              '    - {id: history, pattern: was, message: Own.}\n',
          'lint.banned_patterns[1].id',
        ),
        (
          '    lint:\n      banned_patterns:\n'
              '        - {id: second_shall, pattern: shall, message: Own.}\n',
          '',
          'sections.statement.lint.banned_patterns[0].id',
        ),
        (
          '',
          '    lint:\n      required_patterns:\n'
              '        - {id: then_line, pattern: Then, message: Own.}\n',
          'sections.cases.lint.required_patterns[0].id',
        ),
      ]) {
        final shipped = _patternShipped(
          fr:
              'id: fr\ndescription: Describes one requirement.\n'
              'path: frs/{slug}.md\nsections:\n'
              '  - id: statement\n    header: Statement\n$statementLint'
              '  - id: cases\n    header: Edge cases\n$casesTail',
        );

        await expectLater(
          _resolvePatterns({}, shipped: shipped),
          throwsA(
            _faultAt(FaultCode.unknownValue, 'packs/prd-core/fr.yaml', key),
          ),
        );
      }
    });
  });

  group('a declaring pack file of an extending type', () {
    test(
      'adding the id of a pattern reaching it is unknown_value at that id',
      () async {
        final shipped = {
          ..._patternShipped(),
          'prd-core/fr_plus.yaml': _bytes('''
id: fr_plus
extends: fr
path: fr_plus/{slug}.md
lint:
  banned_patterns:
    add:
      - id: history
        pattern: was
        message: Own.
'''),
        };

        await expectLater(
          _resolvePatterns({}, shipped: shipped),
          throwsA(
            _faultAt(
              FaultCode.unknownValue,
              'packs/prd-core/fr_plus.yaml',
              'lint.banned_patterns.add[0].id',
            ),
          ),
        );
      },
    );
  });

  group('a layer above a shared pattern', () {
    test('an add of its id replaces it for that type alone', () async {
      final set = await _resolvePatterns({
        'fr.yaml': '''
lint:
  banned_patterns:
    add:
      - id: history
        pattern: was edited
        message: Project history.
''',
      });

      expect(
        _docPattern(_type(set, 'fr'), 'history').message,
        'Project history.',
      );
      expect(_docPattern(_type(set, 'fr'), 'history').pattern, 'was edited');
      expect(
        _docPattern(_type(set, 'nf'), 'history').message,
        'Drop the history.',
      );
      expect(_patternIds(_type(set, 'fr').lint.bannedPatterns), [
        'own_rule',
        'history',
      ]);
    });

    test('a remove of its id drops it for that type alone', () async {
      final set = await _resolvePatterns({
        'fr.yaml': 'lint:\n  banned_patterns:\n    remove: [history]\n',
      });

      expect(_patternIds(_type(set, 'fr').lint.bannedPatterns), ['own_rule']);
      expect(_patternIds(_type(set, 'nf').lint.bannedPatterns), ['history']);
    });

    test(
      'a section add of its id replaces it in that section for that type alone',
      () async {
        final set = await _resolvePatterns({
          'fr.yaml': '''
sections:
  - id: statement
    lint:
      banned_patterns:
        add:
          - id: second_shall
            pattern: shall
            message: Project shall.
''',
        });

        final frStatement = _section(_type(set, 'fr'), 'statement');
        final nfStatement = _section(_type(set, 'nf'), 'statement');
        expect(_patternIds(frStatement.bannedPatterns), ['second_shall']);
        expect(frStatement.bannedPatterns!.single.message, 'Project shall.');
        expect(nfStatement.bannedPatterns!.single.message, 'Write one shall.');
      },
    );

    test('a section remove of its id drops it from that section for that type alone', () async {
      final set = await _resolvePatterns({
        'fr.yaml': '''
sections:
  - id: statement
    lint:
      banned_patterns:
        remove: [second_shall]
''',
      });

      expect(
        _patternIds(_section(_type(set, 'fr'), 'statement').bannedPatterns),
        isEmpty,
      );
      expect(
        _patternIds(_section(_type(set, 'nf'), 'statement').bannedPatterns),
        ['second_shall'],
      );
    });

    test('a personal pack entry of its id replaces it with no fault', () async {
      final set = await _resolvePatterns(
        {},
        personal: ['nont-prd'],
        home: {
          '.specstone/packs/nont-prd/pack.yaml':
              'name: nont-prd\nversion: 1.0.0\nextends: prd-core\n',
          '.specstone/packs/nont-prd/fr.yaml': '''
lint:
  banned_patterns:
    add:
      - id: history
        pattern: was changed
        message: Personal history.
''',
        },
      );

      expect(
        _docPattern(_type(set, 'fr'), 'history').message,
        'Personal history.',
      );
      expect(
        _docPattern(_type(set, 'nf'), 'history').message,
        'Drop the history.',
      );
    });

    test('a project plain list over shared entries alone is list_override_needs_add_remove', () async {
      await expectLater(
        _resolvePatterns({
          'nf.yaml': '''
lint:
  banned_patterns:
    - id: project_rule
      pattern: TODO
      message: Finish it.
''',
        }),
        throwsA(
          _faultAt(
            FaultCode.listOverrideNeedsAddRemove,
            '.specstone/templates/nf.yaml',
            'lint.banned_patterns',
          ),
        ),
      );
    });
  });
}
