import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_chain.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/shared_merge.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';
const _sharedPath = '.specstone/templates/shared.yaml';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// The shared lines `shared.yaml` text [yaml] holds.
List<SharedLine> _project(String yaml) => parseSharedEntries(
  readYamlMap(yaml, file: _sharedPath),
  file: _sharedPath,
  allowsFields: false,
).lines;

/// One pack: the `pack.yaml` keys after `name` and `version`, and the doc type
/// ids the pack defines.
final class _Pack {
  const new(this.yaml, this.types);

  final String yaml;
  final Set<String> types;
}

_Pack _pack(String yaml, {Set<String> types = const {}}) => _Pack(yaml, types);

/// Merges the shared entries of [packs] and [project] in layer order.
SharedSet _merge(
  Map<String, _Pack> packs, {
  String project = '',
  Set<String> projectTypes = const {},
}) {
  final files = <String, Uint8List>{
    for (final MapEntry(:key, :value) in packs.entries)
      '$key/pack.yaml': _bytes('name: $key\nversion: 1.0.0\n${value.yaml}'),
  };
  final ordered = orderPacks([
    for (final name in packs.keys) loadShippedPackManifest(name, files),
  ], configFile: _configPath);
  final types = {
    for (final MapEntry(:key, :value) in packs.entries) key: value.types,
  };
  return mergeSharedEntries(
    ordered: ordered,
    projectLines: project.isEmpty ? const [] : _project(project),
    docTypeIdsByPack: types,
    mergedDocTypeIds: {for (final set in types.values) ...set, ...projectTypes},
  );
}

TemplateFault _fault(
  Map<String, _Pack> packs, {
  String project = '',
  Set<String> projectTypes = const {},
}) {
  try {
    _merge(packs, project: project, projectTypes: projectTypes);
  } on TemplateFault catch (fault) {
    return fault;
  }
  fail('merge threw no fault');
}

TypeMatcher<TemplateFault> _is(
  FaultCode code, {
  required String file,
  required String key,
  required String message,
}) => isA<TemplateFault>()
    .having((f) => f.code, 'code', code)
    .having((f) => f.file, 'file', file)
    .having((f) => f.key, 'key', key)
    .having((f) => f.message, 'message', message);

List<String> _ids(List<MergedSharedLine> lines) => [
  for (final line in lines) line.id,
];

String _text(SharedSet set, String id) =>
    set.lines.singleWhere((line) => line.id == id).text;

void main() {
  group('layers merge by id in layer order', () {
    test('chain, then a personal pack, then shared.yaml, the top wins', () {
      final set = _merge({
        'base': _pack('shared_lines:\n  - id: tone\n    text: base\n'),
        'mid': _pack(
          'extends: base\nshared_lines:\n  - id: tone\n    text: mid\n',
        ),
        'top': _pack(
          'extends: mid\nshared_lines:\n  - id: tone\n    text: top\n',
        ),
      }, project: 'shared_lines:\n  - id: tone\n    text: project\n');

      expect(set.lines.single.text, 'project');
    });

    test('a pack below shared.yaml still shows when shared.yaml is silent', () {
      final set = _merge({
        'base': _pack('shared_lines:\n  - id: tone\n    text: base\n'),
        'top': _pack(
          'extends: base\nshared_lines:\n  - id: tone\n    text: top\n',
        ),
      }, project: 'shared_lines:\n  - id: other\n    text: extra\n');

      expect(_text(set, 'tone'), 'top');
      expect(_ids(set.lines), ['tone', 'other']);
    });

    test('a shared line and a shared field of one id are two entries', () {
      final set = _merge({
        'base': _pack(
          'shared_lines:\n  - id: note\n    text: line\n'
          'shared_fields:\n  - id: note\n    type: string\n'
          '    for_doc_types: [story]\n',
          types: {'story'},
        ),
      });

      expect(set.lines.single.id, 'note');
      expect(set.fields.single.id, 'note');
    });
  });

  group('an upper for_doc_types list replaces the lower one', () {
    test('an upper list replaces the lower list', () {
      final set = _merge({
        'base': _pack(
          'shared_lines:\n  - id: tone\n    text: base\n'
          '    for_doc_types: [a, b]\n',
          types: {'a', 'b', 'c'},
        ),
        'top': _pack(
          'extends: base\nshared_lines:\n  - id: tone\n'
          '    for_doc_types: [c]\n',
        ),
      });

      expect(set.lines.single.forDocTypes, ['c']);
      expect(set.linesNaming('a'), isEmpty);
      expect(_ids(set.linesNaming('c')), ['tone']);
    });
  });

  group('an entry keeps the print place of its first defining layer', () {
    test('an upper change keeps the rank of the first defining layer', () {
      final set = _merge({
        'base': _pack(
          'shared_lines:\n  - id: first\n    text: one\n'
          '  - id: second\n    text: two\n',
        ),
        'top': _pack(
          'extends: base\nshared_lines:\n  - id: first\n    text: changed\n'
          '  - id: third\n    text: three\n',
        ),
      });

      expect(_ids(set.lines), ['first', 'second', 'third']);
      expect(_text(set, 'first'), 'changed');
      final ranks = [for (final line in set.lines) line.printRank];
      expect(ranks, [...ranks]..sort());
      expect(ranks.toSet(), hasLength(3));
    });

    test('a personal pack over software-tech no_status keeps its place', () {
      final set = _merge({
        'software-tech': _pack(
          'shared_lines:\n  - id: before\n    text: a\n'
          '  - id: no_status\n    text: Write no status.\n'
          '    for_doc_types: [architecture]\n'
          '  - id: after\n    text: b\n',
          types: {'architecture'},
        ),
        'mine': _pack(
          'extends: software-tech\nshared_lines:\n  - id: no_status\n'
          '    text: Write no status word.\n',
        ),
      });

      expect(_ids(set.lines), ['before', 'no_status', 'after']);
      expect(_text(set, 'no_status'), 'Write no status word.');
      expect(
        set.lines.singleWhere((line) => line.id == 'no_status').forDocTypes,
        ['architecture'],
      );
    });

    test(
      'a field keeps its declaring pack and order when a pack changes it',
      () {
        final set = _merge({
          'base': _pack(
            'shared_fields:\n  - id: owner\n    type: string\n'
            '    for_doc_types: [story]\n',
            types: {'story'},
          ),
          'top': _pack(
            'extends: base\nshared_fields:\n  - id: owner\n'
            '    description: Who owns it.\n  - id: extra\n    type: string\n'
            '    for_doc_types: [story]\n',
          ),
        });

        final owner = set.fields.first;
        expect(owner.id, 'owner');
        expect(owner.declaringPack, 'base');
        expect(owner.entry.description, 'Who owns it.');
        expect(owner.entry.type?.wire, 'string');
        expect(set.fields.last.declaringPack, 'top');
        expect(owner.order, lessThan(set.fields.last.order));
      },
    );
  });

  group('a disabled entry reaches no doc type', () {
    test('a disabled line reaches no doc type', () {
      final set = _merge({
        'base': _pack('shared_lines:\n  - id: tone\n    text: base\n'),
        'top': _pack(
          'extends: base\nshared_lines:\n  - id: tone\n    disabled: true\n',
        ),
      });

      expect(set.lines, isEmpty);
      expect(set.linesNaming('anything'), isEmpty);
    });

    test('a disabled field reaches no doc type', () {
      final set = _merge({
        'base': _pack(
          'shared_fields:\n  - id: owner\n    type: string\n'
          '    for_doc_types: [story]\n',
          types: {'story'},
        ),
        'top': _pack(
          'extends: base\nshared_fields:\n  - id: owner\n    disabled: true\n',
        ),
      });

      expect(set.fields, isEmpty);
      expect(set.fieldsNaming('story'), isEmpty);
    });
  });

  group('the doc types a shared line reaches', () {
    test(
      'a new line with no for_doc_types names no list, so it reaches all',
      () {
        final set = _merge({
          'base': _pack(
            'shared_lines:\n  - id: tone\n    text: base\n',
            types: {'story'},
          ),
        });

        expect(set.lines.single.forDocTypes, isNull);
        expect(_ids(set.linesNaming('story')), ['tone']);
      },
    );

    test('a line with for_doc_types reaches only the types it names', () {
      final set = _merge({
        'base': _pack(
          'shared_lines:\n  - id: tone\n    text: base\n'
          '    for_doc_types: [story]\n',
          types: {'story', 'fr'},
        ),
      });

      expect(_ids(set.linesNaming('story')), ['tone']);
      expect(set.linesNaming('fr'), isEmpty);
    });

    test('a change with no for_doc_types keeps the lower list', () {
      final set = _merge({
        'base': _pack(
          'shared_lines:\n  - id: tone\n    text: base\n'
          '    for_doc_types: [story]\n',
          types: {'story'},
        ),
        'top': _pack(
          'extends: base\nshared_lines:\n  - id: tone\n    text: top\n',
        ),
      });

      expect(set.lines.single.forDocTypes, ['story']);
    });

    test('a change keeps a lower line that reaches every type', () {
      final set = _merge({
        'base': _pack('shared_lines:\n  - id: tone\n    text: base\n'),
        'top': _pack(
          'extends: base\nshared_lines:\n  - id: tone\n    text: top\n',
        ),
      });

      expect(set.lines.single.forDocTypes, isNull);
    });
  });

  group('two packs outside one extends chain declaring one id', () {
    test('a line id declared twice is refused at the later pack by name', () {
      expect(
        _fault({
          'beta': _pack(
            'shared_lines:\n  - id: other\n    text: x\n'
            '  - id: tone\n    text: b\n',
          ),
          'alpha': _pack('shared_lines:\n  - id: tone\n    text: a\n'),
        }),
        _is(
          FaultCode.unknownValue,
          file: 'packs/beta/pack.yaml',
          key: 'shared_lines[1].id',
          message:
              'shared entry tone is declared by two packs, neither extending '
              'the other',
        ),
      );
    });

    test('a field id declared twice is refused the same way', () {
      expect(
        _fault({
          'alpha': _pack(
            'shared_fields:\n  - id: owner\n    type: string\n'
            '    for_doc_types: [story]\n',
            types: {'story'},
          ),
          'beta': _pack(
            'shared_fields:\n  - id: owner\n    type: string\n'
            '    for_doc_types: [story]\n',
            types: {'story'},
          ),
        }),
        _is(
          FaultCode.unknownValue,
          file: 'packs/beta/pack.yaml',
          key: 'shared_fields[0].id',
          message:
              'shared entry owner is declared by two packs, neither extending '
              'the other',
        ),
      );
    });

    test('packs in one chain declare one id with no fault', () {
      final set = _merge({
        'zeta': _pack('shared_lines:\n  - id: tone\n    text: base\n'),
        'alpha': _pack(
          'extends: zeta\nshared_lines:\n  - id: tone\n    text: top\n',
        ),
      });

      expect(_text(set, 'tone'), 'top');
    });
  });

  group('a shared.yaml line names only doc types of the merged set', () {
    test('a line naming a type the merged set lacks is unknown_value', () {
      expect(
        _fault(
          {
            'base': _pack(
              'shared_lines:\n  - id: tone\n    text: base\n',
              types: {'story'},
            ),
          },
          project:
              'shared_lines:\n  - id: a\n    text: x\n  - id: b\n'
              '    text: y\n    for_doc_types: [story, ghost]\n',
        ),
        _is(
          FaultCode.unknownValue,
          file: _sharedPath,
          key: 'shared_lines[1].for_doc_types',
          message: 'for_doc_types names no doc type of the merged set: ghost',
        ),
      );
    });

    test('a project doc type is a type the line may name', () {
      final set = _merge(
        {
          'base': _pack('', types: {'story'}),
        },
        project:
            'shared_lines:\n  - id: a\n    text: x\n'
            '    for_doc_types: [my_type]\n',
        projectTypes: {'my_type'},
      );

      expect(_ids(set.linesNaming('my_type')), ['a']);
    });
  });

  group('an entry that can neither change nor add', () {
    test('a new line with no text is override_id_not_found', () {
      expect(
        _fault({'base': _pack('shared_lines:\n  - id: tone\n')}),
        _is(
          FaultCode.overrideIdNotFound,
          file: 'packs/base/pack.yaml',
          key: 'shared_lines[0].id',
          message:
              'no shared line "tone" in the merged set and no text to add it',
        ),
      );
    });

    test('a new field with no type is override_id_not_found', () {
      expect(
        _fault({
          'base': _pack(
            'shared_fields:\n  - id: owner\n    for_doc_types: [story]\n',
            types: {'story'},
          ),
        }),
        _is(
          FaultCode.overrideIdNotFound,
          file: 'packs/base/pack.yaml',
          key: 'shared_fields[0].id',
          message:
              'no shared field "owner" in the merged set and no type to add '
              'it',
        ),
      );
    });

    test('a disable of an id no layer defined is override_id_not_found', () {
      expect(
        _fault(
          {},
          project: 'shared_lines:\n  - id: ghost\n    disabled: true\n',
        ),
        _is(
          FaultCode.overrideIdNotFound,
          file: _sharedPath,
          key: 'shared_lines[0].id',
          message: 'no shared line "ghost" in the merged set to disable',
        ),
      );
    });

    test(
      'a repeated disable of an id a lower layer disabled changes nothing',
      () {
        final set = _merge({
          'base': _pack('shared_lines:\n  - id: tone\n    text: base\n'),
          'top': _pack(
            'extends: base\nshared_lines:\n  - id: tone\n    disabled: true\n',
          ),
        }, project: 'shared_lines:\n  - id: tone\n    disabled: true\n');

        expect(set.lines, isEmpty);
      },
    );

    test('a complete line over a disabled id adds it again', () {
      final set = _merge({
        'base': _pack('shared_lines:\n  - id: tone\n    text: base\n'),
        'top': _pack(
          'extends: base\nshared_lines:\n  - id: tone\n    disabled: true\n',
        ),
      }, project: 'shared_lines:\n  - id: tone\n    text: back\n');

      expect(_text(set, 'tone'), 'back');
    });
  });

  group('a pack entry names only doc types of its pack chain', () {
    test('a line naming a type outside its chain is unknown_value', () {
      expect(
        _fault({
          'base': _pack('', types: {'story'}),
          'other': _pack(
            'shared_lines:\n  - id: tone\n    text: x\n'
            '    for_doc_types: [story]\n',
            types: {'fr'},
          ),
        }),
        _is(
          FaultCode.unknownValue,
          file: 'packs/other/pack.yaml',
          key: 'shared_lines[0].for_doc_types',
          message: 'for_doc_types names no doc type of the pack chain: story',
        ),
      );
    });

    test('a field naming a type outside its chain is unknown_value', () {
      expect(
        _fault({
          'base': _pack('', types: {'story'}),
          'other': _pack(
            'shared_fields:\n  - id: owner\n    type: string\n'
            '    for_doc_types: [fr, story]\n',
            types: {'fr'},
          ),
        }),
        _is(
          FaultCode.unknownValue,
          file: 'packs/other/pack.yaml',
          key: 'shared_fields[0].for_doc_types',
          message: 'for_doc_types names no doc type of the pack chain: story',
        ),
      );
    });

    test('a type of a pack the declaring pack extends is in its chain', () {
      final set = _merge({
        'base': _pack('', types: {'story'}),
        'top': _pack(
          'extends: base\nshared_lines:\n  - id: tone\n    text: x\n'
          '    for_doc_types: [story]\n',
        ),
      });

      expect(_ids(set.linesNaming('story')), ['tone']);
    });
  });

  group('a new shared field with no for_doc_types', () {
    test('is missing_key before any doc type merges', () {
      expect(
        _fault({
          'base': _pack('shared_fields:\n  - id: owner\n    type: string\n'),
        }),
        _is(
          FaultCode.missingKey,
          file: 'packs/base/pack.yaml',
          key: 'shared_fields[0].for_doc_types',
          message: 'a new shared field requires for_doc_types',
        ),
      );
    });

    for (final (name, lower) in [
      (
        'two packs declaring one id',
        'shared_lines:\n  - id: tone\n    text: a\n',
      ),
      ('an id the merged base lacks', 'shared_lines:\n  - id: tone\n'),
    ]) {
      test('is reported before a lower layer holding $name', () {
        expect(
          _fault({
            'alpha': _pack(lower),
            'beta': _pack(
              'shared_lines:\n  - id: tone\n    text: b\n'
              'shared_fields:\n  - id: owner\n    type: string\n',
            ),
          }),
          _is(
            FaultCode.missingKey,
            file: 'packs/beta/pack.yaml',
            key: 'shared_fields[0].for_doc_types',
            message: 'a new shared field requires for_doc_types',
          ),
        );
      });
    }

    test('a field a lower layer disabled needs it when added again', () {
      expect(
        _fault({
          'base': _pack(
            'shared_lines:\n  - id: tone\n'
            'shared_fields:\n  - id: owner\n    type: string\n'
            '    for_doc_types: [story]\n',
            types: {'story'},
          ),
          'mid': _pack(
            'extends: base\nshared_fields:\n'
            '  - id: owner\n    disabled: true\n',
          ),
          'top': _pack(
            'extends: mid\nshared_fields:\n  - id: owner\n    type: string\n',
          ),
        }),
        _is(
          FaultCode.missingKey,
          file: 'packs/top/pack.yaml',
          key: 'shared_fields[0].for_doc_types',
          message: 'a new shared field requires for_doc_types',
        ),
      );
    });

    test('a change or disable of a lower field needs none', () {
      final set = _merge({
        'base': _pack(
          'shared_fields:\n  - id: owner\n    type: string\n'
          '    for_doc_types: [story]\n'
          '  - id: gone\n    type: string\n    for_doc_types: [story]\n',
          types: {'story'},
        ),
        'top': _pack(
          'extends: base\nshared_fields:\n  - id: owner\n    required: true\n'
          '  - id: gone\n    disabled: true\n',
        ),
      });

      expect(set.fields.single.id, 'owner');
      expect(set.fields.single.entry.required, isTrue);
      expect(set.fields.single.forDocTypes, ['story']);
    });
  });

  group('TemplateResolver', () {
    Map<String, Uint8List> shipped() => {
      'prd-core/pack.yaml': _bytes(
        'name: prd-core\nversion: 1.0.0\nshared_lines:\n'
        '  - id: tone\n    text: Be brief.\n',
      ),
      'prd-core/feature.yaml': _bytes(
        'id: feature\ndescription: A feature\npath: '
        'features/f{nn}_{slug}/FEATURE.md\n',
      ),
    };

    test('resolve merges pack lines under the project shared.yaml', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.0.0\n',
        _sharedPath:
            'shared_lines:\n  - id: tone\n    text: Be short.\n'
            '  - id: extra\n    text: More.\n    for_doc_types: [feature]\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final set = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(_text(set.shared, 'tone'), 'Be short.');
      expect(_ids(set.shared.linesNaming('feature')), ['tone', 'extra']);
    });

    test('resolve refuses a shared.yaml line naming a missing type', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.0.0\n',
        _sharedPath:
            'shared_lines:\n  - id: extra\n    text: More.\n'
            '    for_doc_types: [ghost]\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'shared_lines[0].for_doc_types'),
        ),
      );
    });

    test('resolveCarried merges the project lines it is given', () {
      final resolver = TemplateResolver(shippedFiles: shipped());

      final set = resolver.resolveCarried(
        packNames: const ['prd-core'],
        homeDirectory: null,
        projectSharedLines: _project(
          'shared_lines:\n  - id: tone\n    text: Hi.\n',
        ),
      );

      expect(_text(set.shared, 'tone'), 'Hi.');
    });

    test('resolveCarriedPinned merges the project lines it is given', () {
      final resolver = TemplateResolver(shippedFiles: shipped());

      final carried = resolver.resolveCarriedPinned(
        packNames: const ['prd-core'],
        homeDirectory: null,
        projectSharedLines: _project(
          'shared_lines:\n  - id: tone\n    text: Hi.\n',
        ),
      );

      expect(_text(carried.set.shared, 'tone'), 'Hi.');
    });

    test('a carried set with no project lines keeps the pack lines', () {
      final resolver = TemplateResolver(shippedFiles: shipped());

      final set = resolver.resolveCarried(
        packNames: const ['prd-core'],
        homeDirectory: null,
      );

      expect(_text(set.shared, 'tone'), 'Be brief.');
    });

    test('a MergedSet built with no shared set holds an empty one', () {
      final set = MergedSet(docTypes: const []);

      expect(set.shared.lines, isEmpty);
      expect(set.shared.fields, isEmpty);
    });
  });
}
