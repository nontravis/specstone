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
        () => checkMergedSet([
          builtIn('playbook').copyWith(path: 'ops/{slug}/RUNBOOK.md'),
          builtIn('runbook').copyWith(path: 'ops/{slug}/RUNBOOK.md'),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.docTypePathConflict)
              .having((f) => f.key, 'key', 'path')
              .having((f) => f.file, 'file', _runbookFile)
              .having((f) => f.relatedFiles, 'relatedFiles', [_playbookFile]),
        ),
      );
    });

    test('f03/us03/fr01/e12, f03/us02/fr04/e05: a parent naming no id is '
        'unknown_value', () {
      final layers = {
        'runbook': [layerOf('runbook', 'parent: nope\n')],
      };
      expect(
        () => checkMergedSet([
          builtIn('runbook').copyWith(parent: 'nope'),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'parent')
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
    });

    test('f03/us03/fr01/e13: a parent loop is parent_cycle', () {
      final layers = {
        'epic': [layerOf('epic', 'parent: story\n', file: _epicFile)],
        'story': [layerOf('story', 'parent: epic\n', file: _storyFile)],
      };
      expect(
        () => checkMergedSet([
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
        () =>
            checkMergedSet([builtIn('self').copyWith(parent: 'self')], layers),
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
          () => checkMergedSet([
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
        () => checkMergedSet([
          builtIn('runbook').copyWith(parent: 'feature'),
          builtIn('feature').copyWith(path: 'f.md'),
        ], layers),
        returnsNormally,
      );
    });

    test('ruling 2026-10-22: a parent fault names the upper file when a '
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
        () => checkMergedSet([
          builtIn('runbook').copyWith(parent: 'nope'),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
    });
  });
}
