import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/merged_set_checks.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

const _runbookFile = '.specstone/templates/runbook.yaml';
const _playbookFile = '.specstone/templates/playbook.yaml';
const _epicFile = '.specstone/templates/epic.yaml';
const _storyFile = '.specstone/templates/story.yaml';
const _selfFile = '.specstone/templates/self.yaml';

final class _NoFiles implements LayerFiles {
  const new();

  @override
  bool exists(String layerRelativePath) => false;
}

/// One layer of the doc type [id], writing [text].
({LoadedPack? pack, DocTypeLayer layer}) layerOf(
  String id,
  String text, {
  String file = _runbookFile,
}) => (
  pack: null,
  layer: DocTypeLayer.parse(
    text,
    file: file,
    docTypeId: id,
    kind: LayerKind.project,
    files: const _NoFiles(),
  ),
);

MergedDocType builtIn(String id) => MergedDocType(
  id: id,
  fields: const [],
  sections: const [],
  lint: const MergedLint(),
  files: const [],
);

/// [checkMergedSet] over [docTypes], loading [layers] in map order.
void check(List<MergedDocType> docTypes, Map<String, DocTypeLayers> layers) =>
    checkMergedSet(
      docTypes,
      layers,
      loadIndex: loadIndexOf([
        for (final list in layers.values)
          for (final entry in list) entry.layer,
      ]),
    );

void main() {
  group('checkMergedSet', () {
    test('two doc types with one path are '
        'doc_type_path_conflict', () {
      final layers = {
        'playbook': [
          layerOf(
            'playbook',
            'path: ops/{slug}/RUNBOOK.md\n',
            file: _playbookFile,
          ),
        ],
        'runbook': [layerOf('runbook', 'path: ops/{slug}/RUNBOOK.md\n')],
      };
      expect(
        () => check([
          builtIn('playbook').copyWith(path: 'ops/{slug}/RUNBOOK.md'),
          builtIn('runbook').copyWith(path: 'ops/{slug}/RUNBOOK.md'),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.docTypePathConflict)
              .having((f) => f.key, 'key', 'path')
              .having(
                (f) => f.message,
                'message',
                'doc types playbook and runbook share the path '
                    'ops/{slug}/RUNBOOK.md',
              )
              .having((f) => f.file, 'file', _runbookFile)
              .having((f) => f.relatedFiles, 'relatedFiles', [_playbookFile]),
        ),
      );
    });

    test('three doc types with one path are named in load '
        'order, the last joined by "and"', () {
      final layers = {
        'runbook': [layerOf('runbook', 'path: ops/{slug}/RUNBOOK.md\n')],
        'playbook': [
          layerOf(
            'playbook',
            'path: ops/{slug}/RUNBOOK.md\n',
            file: _playbookFile,
          ),
        ],
        'epic': [
          layerOf('epic', 'path: ops/{slug}/RUNBOOK.md\n', file: _epicFile),
        ],
      };
      expect(
        () => check([
          for (final id in layers.keys)
            builtIn(id).copyWith(path: 'ops/{slug}/RUNBOOK.md'),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.docTypePathConflict)
              .having(
                (f) => f.message,
                'message',
                'doc types runbook, playbook and epic share the path '
                    'ops/{slug}/RUNBOOK.md',
              )
              .having((f) => f.file, 'file', _epicFile)
              .having((f) => f.relatedFiles, 'relatedFiles', [
                _runbookFile,
                _playbookFile,
              ]),
        ),
      );
    });

    test('f03/us03/fr01/e12, f03/us02/fr04/e05: a parent naming no id is '
        'unknown_value', () {
      final layers = {
        'runbook': [layerOf('runbook', 'parent: nope\n')],
      };
      expect(
        () => check([builtIn('runbook').copyWith(parent: 'nope')], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'parent')
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
    });

    test('max_depth on two doc types is unknown_value '
        'naming both', () {
      final layers = {
        'playbook': [
          layerOf('playbook', 'max_depth: 2\n', file: _playbookFile),
        ],
        'runbook': [layerOf('runbook', 'max_depth: 3\n')],
      };
      expect(
        () => check([
          builtIn('playbook')
              .copyWith(path: 'ops/{slug}/PLAYBOOK.md', maxDepth: 2),
          builtIn('runbook')
              .copyWith(path: 'ops/runbooks/{slug}/RUNBOOK.md', maxDepth: 3),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'max_depth')
              .having(
                (f) => f.message,
                'message',
                'only one doc type takes max_depth: '
                    'playbook and runbook write it',
              )
              .having((f) => f.file, 'file', _runbookFile)
              .having((f) => f.relatedFiles, 'relatedFiles', [_playbookFile]),
        ),
      );
    });

    test('max_depth on a doc type with a parent is '
        'unknown_value', () {
      final layers = {
        'epic': [
          layerOf('epic', 'path: epics/{slug}/EPIC.md\n', file: _epicFile),
        ],
        'story': [
          layerOf('story', 'parent: epic\nmax_depth: 1\n', file: _storyFile),
        ],
      };
      expect(
        () => check([
          builtIn('epic').copyWith(path: 'epics/{slug}/EPIC.md'),
          builtIn('story').copyWith(
            parent: 'epic',
            path: 'stories/{slug}/STORY.md',
            maxDepth: 1,
          ),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'max_depth')
              .having(
                (f) => f.message,
                'message',
                'a doc type with a parent takes no max_depth',
              )
              .having((f) => f.file, 'file', _storyFile),
        ),
      );
    });

    test('max_depth above 0 on a path whose last folder '
        'holds no {slug} is unknown_value naming the writer', () {
      final layers = {
        'runbook': [layerOf('runbook', 'max_depth: 3\n')],
      };
      expect(
        () => check([
          builtIn('runbook')
              .copyWith(path: 'prds/features/FEATURE.md', maxDepth: 3),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'max_depth')
              .having(
                (f) => f.message,
                'message',
                'max_depth needs a path whose last folder holds {slug}',
              )
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
    });

    test('max_depth 0 on any path, and one carrier with a '
        'slug folder, pass', () {
      final layers = {
        'runbook': [layerOf('runbook', 'max_depth: 0\n')],
        'playbook': [layerOf('playbook', 'path: x\n', file: _playbookFile)],
      };
      expect(
        () => check([
          builtIn('runbook').copyWith(path: 'ops/FEATURE.md', maxDepth: 0),
          builtIn('playbook').copyWith(path: 'books/{slug}/BOOK.md'),
        ], layers),
        returnsNormally,
      );
      expect(
        () => check(
          [
            builtIn('runbook')
                .copyWith(path: 'ops/f{nn}_{slug}/R.md', maxDepth: 3),
          ],
          {
            'runbook': [layerOf('runbook', 'max_depth: 3\n')],
          },
        ),
        returnsNormally,
      );
    });

    test('a parent loop is parent_cycle', () {
      final layers = {
        'epic': [layerOf('epic', 'parent: story\n', file: _epicFile)],
        'story': [layerOf('story', 'parent: epic\n', file: _storyFile)],
      };
      expect(
        () => check([
          builtIn('epic').copyWith(parent: 'story'),
          builtIn('story').copyWith(parent: 'epic'),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.parentCycle)
              .having((f) => f.key, 'key', 'parent')
              .having((f) => f.file, 'file', _storyFile)
              .having((f) => f.relatedFiles, 'relatedFiles', [_epicFile]),
        ),
      );
    });

    test('a self parent names one file', () {
      final layers = {
        'self': [layerOf('self', 'parent: self\n', file: _selfFile)],
      };
      expect(
        () => check([builtIn('self').copyWith(parent: 'self')], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.parentCycle)
              .having((f) => f.file, 'file', _selfFile)
              .having((f) => f.relatedFiles, 'relatedFiles', isEmpty),
        ),
      );
    });

    test('a doc_types entry naming no id is unknown_value', () {
      final layers = {
        'runbook': [
          layerOf(
            'runbook',
            'fields:\n  - id: up\n    type: doc_ref\n    doc_types: [nope]\n',
          ),
        ],
      };
      expect(
        () => check([
          builtIn('runbook').copyWith(
            fields: [
              const MergedField(
                id: 'up',
                type: FieldType.docRef,
                docTypes: ['nope'],
              ),
            ],
          ),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'fields.up.doc_types')
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
    });

    test('a parent naming an id passes', () {
      final layers = {
        'runbook': [layerOf('runbook', 'parent: feature\n')],
        'feature': [layerOf('feature', 'path: f.md\n')],
      };
      expect(
        () => check([
          builtIn('runbook').copyWith(parent: 'feature'),
          builtIn('feature').copyWith(path: 'f.md'),
        ], layers),
        returnsNormally,
      );
    });

    test('a parent fault names the upper file when a '
        'lower layer also wrote it', () {
      final layers = {
        'runbook': [
          layerOf(
            'runbook',
            'parent: nope\n',
            file: 'packs/prd-core/runbook.yaml',
          ),
          layerOf('runbook', 'parent: nope\n'),
        ],
      };
      expect(
        () => check([builtIn('runbook').copyWith(parent: 'nope')], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
    });

    test('grid at a nested feature pattern is '
        'doc_type_path_conflict', () {
      const nestedPath = 'prds/features/f{nn}_{slug}/f{nn}_{slug}/FEATURE.md';
      final layers = {
        'feature': [
          layerOf(
            'feature',
            'path: prds/features/f{nn}_{slug}/FEATURE.md\nmax_depth: 1\n',
            file: 'packs/prd-core/feature.yaml',
          ),
        ],
        'grid': [layerOf('grid', 'path: $nestedPath\n')],
      };
      expect(
        () => check([
          builtIn('feature').copyWith(
            path: 'prds/features/f{nn}_{slug}/FEATURE.md',
            maxDepth: 1,
          ),
          builtIn('grid').copyWith(path: nestedPath),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.docTypePathConflict)
              .having(
                (f) => f.message,
                'message',
                'doc types feature and grid share the path $nestedPath',
              ),
        ),
      );
    });

    test('E31, INV-31: two '
        'doc types holding a record_status field are unknown_value naming '
        'each holder', () {
      const recordField =
          'fields:\n'
          '  - id: owner\n'
          '    type: string\n'
          '  - id: entries\n'
          '    type: record_status\n';
      final layers = {
        'runbook': [layerOf('runbook', recordField)],
        'playbook': [layerOf('playbook', recordField, file: _playbookFile)],
      };
      expect(
        () => check([
          builtIn('runbook').copyWith(
            fields: [
              const MergedField(id: 'owner', type: FieldType.string),
              const MergedField(id: 'entries', type: FieldType.recordStatus),
            ],
          ),
          builtIn('playbook').copyWith(
            fields: [
              const MergedField(id: 'owner', type: FieldType.string),
              const MergedField(id: 'entries', type: FieldType.recordStatus),
            ],
          ),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'fields[${1}].type')
              .having(
                (f) => f.message,
                'message',
                'only one doc type holds a record_status field: '
                    'playbook and runbook do',
              )
              .having((f) => f.file, 'file', _playbookFile)
              .having((f) => f.relatedFiles, 'relatedFiles', [_runbookFile]),
        ),
      );
    });

    test('E33, INV-31: the '
        'record doc type with a merged per_target that is not true is '
        'unknown_value', () {
      const noKey =
          'fields:\n'
          '  - id: entries\n'
          '    type: record_status\n';
      const falseKey =
          'fields:\n'
          '  - id: entries\n'
          '    type: record_status\n'
          'per_target: false\n';
      expect(
        () => check(
          [
            builtIn('runbook').copyWith(
              fields: [
                const MergedField(id: 'entries', type: FieldType.recordStatus),
              ],
            ),
          ],
          {
            'runbook': [layerOf('runbook', noKey)],
          },
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'per_target')
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
      expect(
        () => check(
          [
            builtIn('runbook').copyWith(
              isPerTarget: false,
              fields: [
                const MergedField(id: 'entries', type: FieldType.recordStatus),
              ],
            ),
          ],
          {
            'runbook': [layerOf('runbook', falseKey)],
          },
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'per_target')
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
    });

    test('E33, INV-31: the '
        'record doc type with per_target: true passes, and one holder names '
        'the record doc type', () {
      const layer =
          'fields:\n'
          '  - id: entries\n'
          '    type: record_status\n'
          'per_target: true\n';
      final docTypes = [
        builtIn('runbook').copyWith(
          isPerTarget: true,
          fields: [
            const MergedField(id: 'entries', type: FieldType.recordStatus),
          ],
        ),
      ];
      expect(
        () => check(docTypes, {
          'runbook': [layerOf('runbook', layer)],
        }),
        returnsNormally,
      );
      expect(MergedSet(docTypes: docTypes).recordDocType?.id, 'runbook');
      expect(MergedSet(docTypes: [builtIn('feature')]).recordDocType, isNull);
    });
  });

  group('checkMergedSet targets', () {
    test('E30, '
        'INV-29: a targets config in a merged set with no record doc type is '
        'unknown_value', () {
      expect(
        () => checkMergedSet(
          [builtIn('feature').copyWith(path: 'prds/features/F.md')],
          {
            'feature': [layerOf('feature', 'path: prds/features/F.md\n')],
          },
          loadIndex: const {},
          targetNames: const ['flutter', 'jaspr'],
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'targets')
              .having((f) => f.file, 'file', '.specstone/config.yaml'),
        ),
      );
    });

    test('E30: one '
        'target and no targets both need a record doc type; one unnamed '
        'target does not', () {
      const recordLayer =
          'fields:\n'
          '  - id: entries\n'
          '    type: record_status\n'
          'per_target: true\n';
      final withRecord = [
        builtIn('implementation').copyWith(
          isPerTarget: true,
          fields: [
            const MergedField(id: 'entries', type: FieldType.recordStatus),
          ],
        ),
      ];

      // A `targets:` config with one name still needs the record doc type.
      expect(
        () => checkMergedSet(
          [builtIn('feature').copyWith(path: 'prds/features/F.md')],
          {
            'feature': [layerOf('feature', 'path: prds/features/F.md\n')],
          },
          loadIndex: const {},
          targetNames: const ['only'],
        ),
        throwsA(isA<TemplateFault>()),
      );

      // With the record doc type the same configs pass.
      expect(
        () => checkMergedSet(
          [...withRecord, builtIn('feature').copyWith(path: 'f.md')],
          {
            'implementation': [
              layerOf('implementation', recordLayer, file: _runbookFile),
            ],
            'feature': [layerOf('feature', 'path: f.md\n')],
          },
          loadIndex: const {},
          targetNames: const ['flutter', 'jaspr'],
        ),
        returnsNormally,
      );

      // A config with no `targets:` key needs no record doc type.
      expect(
        () => checkMergedSet(
          [builtIn('feature').copyWith(path: 'prds/features/F.md')],
          {
            'feature': [layerOf('feature', 'path: prds/features/F.md\n')],
          },
          loadIndex: const {},
          targetNames: const [],
        ),
        returnsNormally,
      );
    });
  });

  group('checkMergedSet required_when', () {
    const lowerFile = '~/.specstone/packs/runbook.yaml';
    const upperFile = '.specstone/templates/runbook.yaml';
    const ruleOnA =
        'path: a.md\nsections: [{id: a, header: A, lint: '
        '{required_when: {section: b, field: Kind, value: api}}}]\n';
    const ruleOnAWithB =
        'path: a.md\nsections: [{id: a, header: A, lint: '
        '{required_when: {section: b, field: Kind, value: api}}}, '
        '{id: b, header: B}]\n';

    /// The runbook merged over [texts], one layer each, lowest first.
    ({MergedDocType type, DocTypeLayers layers}) merged(List<String> texts) {
      final layers = [
        for (final (i, text) in texts.indexed)
          layerOf('runbook', text, file: i == 0 ? lowerFile : upperFile),
      ];
      var type = const DocTypeMerger().builtInBase('runbook');
      for (final entry in layers) {
        type = const DocTypeMerger().apply(type, entry.layer);
      }
      return (type: type, layers: layers);
    }

    void checkRunbook(List<String> texts) {
      final (:type, :layers) = merged(texts);
      check([type], {'runbook': layers});
    }

    test('a lower layer naming a section an upper layer adds is accepted', () {
      expect(
        () => checkRunbook([ruleOnA, 'sections: [{id: b, header: B}]\n']),
        returnsNormally,
      );
    });

    test('a required_when naming no section is unknown_value at the layer '
        'that wrote it', () {
      expect(
        () => checkRunbook([ruleOnA, 'description: Other\n']),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.file, 'file', lowerFile)
              .having(
                (f) => f.key,
                'key',
                'sections.a.lint.required_when.section',
              ),
        ),
      );
    });

    test('a layer that disables the named section is unknown_value', () {
      expect(
        () => checkRunbook([
          ruleOnAWithB,
          'sections: [{id: b, disabled: true}]\n',
        ]),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.key,
            'key',
            'sections.a.lint.required_when.section',
          ),
        ),
      );
    });
  });
}
