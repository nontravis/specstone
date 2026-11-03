import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
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
    test('f03/us03/fr02/e06: two doc types with one path are '
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

    test('f03/us03/fr02/e06: three doc types with one path are named in load '
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

    test('f03/us03/fr05/e04: max_depth on two doc types is unknown_value '
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

    test('f03/us03/fr05/e04: max_depth on a doc type with a parent is '
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

    test('f03/us03/fr05/e05: max_depth above 0 on a path whose last folder '
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

    test('f03/us03/fr05/e02: max_depth 0 on any path, and one carrier with a '
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

    test('f03/us03/fr01/e13: a parent loop is parent_cycle', () {
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

    test('f03/us03/fr01/e13: a self parent names one file', () {
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

    test(
      'f03/us03/fr01/e14: a doc_types entry naming no id is unknown_value',
      () {
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
      },
    );

    test('f03/us02/fr04/e04: a parent naming an id passes', () {
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

    test('f03/us03/fr01/e12: a parent fault names the upper file when a '
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
  });
}
