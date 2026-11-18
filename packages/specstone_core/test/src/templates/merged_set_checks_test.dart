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

/// [base] with each of [layers] applied through the merger, lowest first.
MergedDocType mergeLayers(MergedDocType base, DocTypeLayers layers) {
  var type = base;
  for (final entry in layers) {
    type = const DocTypeMerger().apply(type, entry.layer);
  }
  return type;
}

/// [checkMergedSet] over [docTypes], loading [layers] in map order.
void check(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layers, {
  bool verificationCoverage = false,
}) => checkMergedSet(
  docTypes,
  layers,
  loadIndex: loadIndexOf([
    for (final list in layers.values)
      for (final entry in list) entry.layer,
  ]),
  verificationCoverage: verificationCoverage,
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

    test('a parent naming no id is '
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

    test('a summary_for entry naming no id is unknown_value', () {
      final layers = {
        'runbook': [layerOf('runbook', 'summary_for: [projet]\n')],
        'project': [layerOf('project', 'path: p.md\n', file: _storyFile)],
      };
      expect(
        () => check([
          builtIn('runbook').copyWith(summaryFor: ['projet']),
          builtIn('project'),
        ], layers),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'summary_for')
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
    });

    test('a summary_for entry naming an id passes', () {
      final layers = {
        'runbook': [layerOf('runbook', 'summary_for: [project]\n')],
        'project': [layerOf('project', 'path: p.md\n', file: _storyFile)],
      };
      expect(
        () => check([
          builtIn('runbook').copyWith(summaryFor: ['project']),
          builtIn('project'),
        ], layers),
        returnsNormally,
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

    test('a non-record doc type with a path under .specstone/ is unknown_value '
        'naming the writer', () {
      const path = '.specstone/records/f{nn}_{slug}/NOTE.md';
      expect(
        () => check(
          [builtIn('runbook').copyWith(path: path)],
          {
            'runbook': [layerOf('runbook', 'path: $path\n')],
          },
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'path')
              .having((f) => f.file, 'file', _runbookFile),
        ),
      );
    });

    test(
      'the record doc type may hold a path below .specstone/records/ only',
      () {
        const recordField =
            'fields:\n'
            '  - id: entries\n'
            '    type: record_status\n'
            'per_target: true\n';
        MergedDocType record(String path) => builtIn('runbook').copyWith(
          path: path,
          isPerTarget: true,
          fields: [
            const MergedField(id: 'entries', type: FieldType.recordStatus),
          ],
        );
        void checkAt(String path) => check(
          [record(path)],
          {
            'runbook': [layerOf('runbook', 'path: $path\n$recordField')],
          },
        );
        expect(
          () => checkAt('.specstone/records/f{nn}_{slug}/IMPLEMENTATION.md'),
          returnsNormally,
        );
        expect(
          () => checkAt('.specstone/other/f{nn}_{slug}/IMPLEMENTATION.md'),
          throwsA(
            isA<TemplateFault>().having(
              (f) => f.code,
              'code',
              FaultCode.unknownValue,
            ),
          ),
        );
      },
    );

    test('two '
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

    test('the '
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

    test('the '
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

  group('checkMergedSet record matrix section', () {
    const recordKeys =
        'per_target: true\n'
        'fields:\n'
        '  - id: entries\n'
        '    type: record_status\n';
    const matrixOn =
        '$recordKeys'
        'sections:\n'
        '  - {id: verification_matrix, header: Matrix, output_ref: true}\n';
    const matrixKey = 'verification_matrix';

    MergedSection matrix({required bool outputRef}) =>
        MergedSection(id: matrixKey, header: 'Matrix', isOutputRef: outputRef);

    MergedDocType record({List<MergedSection> sections = const []}) =>
        builtIn('runbook').copyWith(
          isPerTarget: true,
          fields: [
            const MergedField(id: 'entries', type: FieldType.recordStatus),
          ],
          sections: sections,
        );

    TypeMatcher<TemplateFault> refusedAt(String file, String key) =>
        isA<TemplateFault>()
            .having((f) => f.code, 'code', FaultCode.unknownValue)
            .having((f) => f.file, 'file', file)
            .having((f) => f.key, 'key', key);

    test('output_ref on the record matrix section is accepted', () {
      final docType = record(sections: [matrix(outputRef: true)]);
      expect(
        () => check(
          [docType],
          {
            'runbook': [layerOf('runbook', matrixOn)],
          },
        ),
        returnsNormally,
      );
      expect(verificationMatrixOf(docType)?.isOutputRef, isTrue);
    });

    test('output_ref on any other section is refused', () {
      const otherSection =
          'sections:\n'
          '  - {id: goal, header: Goal}\n'
          '  - {id: notes, header: Notes, output_ref: true}\n';
      expect(
        () => check(
          [record()],
          {
            'runbook': [layerOf('runbook', '$recordKeys$otherSection')],
          },
        ),
        throwsA(refusedAt(_runbookFile, 'sections[1].output_ref')),
      );
      expect(
        () => check(
          [record(), builtIn('playbook')],
          {
            'runbook': [layerOf('runbook', matrixOn)],
            'playbook': [
              layerOf('playbook', otherSection, file: _playbookFile),
            ],
          },
        ),
        throwsA(refusedAt(_playbookFile, 'sections[1].output_ref')),
      );
    });

    test('output_ref on a matrix section of a doc type that holds no '
        'record_status field is accepted and inert', () {
      final playbook = builtIn('playbook')
          .copyWith(sections: [matrix(outputRef: true)]);
      expect(
        () => check(
          [record(), playbook],
          {
            'runbook': [layerOf('runbook', matrixOn)],
            'playbook': [
              layerOf(
                'playbook',
                'sections:\n'
                    '  - {id: verification_matrix, header: Matrix, '
                    'output_ref: true}\n',
                file: _playbookFile,
              ),
            ],
          },
        ),
        returnsNormally,
      );
      expect(verificationMatrixOf(playbook), isNull);
    });

    test('a record matrix section without output_ref true is refused', () {
      const absent =
          '$recordKeys'
          'sections:\n'
          '  - {id: verification_matrix, header: Matrix}\n';
      expect(
        () => check(
          [
            record(sections: [matrix(outputRef: false)]),
          ],
          {
            'runbook': [layerOf('runbook', absent)],
          },
        ),
        throwsA(refusedAt(_runbookFile, 'sections[0].output_ref')),
      );
      const lowered =
          'sections:\n'
          '  - {id: goal, header: Goal}\n'
          '  - {id: verification_matrix, output_ref: false}\n';
      expect(
        () => check(
          [
            record(sections: [matrix(outputRef: false)]),
          ],
          {
            'runbook': [
              layerOf('runbook', matrixOn, file: _epicFile),
              layerOf('runbook', lowered),
            ],
          },
        ),
        throwsA(refusedAt(_runbookFile, 'sections[1].output_ref')),
      );
    });

    test('a disabled record matrix section is accepted', () {
      expect(
        () => check(
          [record()],
          {
            'runbook': [
              layerOf('runbook', matrixOn, file: _epicFile),
              layerOf(
                'runbook',
                'sections:\n  - {id: $matrixKey, disabled: true}\n',
              ),
            ],
          },
        ),
        returnsNormally,
      );
    });

    test('the matrix is the enabled section of its key on the record doc '
        'type, else null', () {
      final docType = record(sections: [matrix(outputRef: true)]);
      expect(verificationMatrixOf(docType)?.id, matrixKey);
      expect(verificationMatrixOf(record()), isNull);
      expect(
        verificationMatrixOf(
          builtIn('playbook').copyWith(sections: [matrix(outputRef: true)]),
        ),
        isNull,
      );
    });
  });

  group('checkMergedSet verification coverage', () {
    const recordKeys =
        'per_target: true\n'
        'fields:\n'
        '  - id: entries\n'
        '    type: record_status\n';
    const matrixOn =
        '$recordKeys'
        'sections:\n'
        '  - {id: verification_matrix, header: Matrix, output_ref: true}\n';
    const personalFile = '~/.specstone/packs/runbook.yaml';

    MergedDocType record({List<MergedSection> sections = const []}) =>
        builtIn('runbook').copyWith(
          isPerTarget: true,
          fields: [
            const MergedField(id: 'entries', type: FieldType.recordStatus),
          ],
          sections: sections,
        );

    const enabledMatrix = MergedSection(
      id: 'verification_matrix',
      header: 'Matrix',
      isOutputRef: true,
    );

    TypeMatcher<TemplateFault> refusedInConfig(String messagePart) =>
        isA<TemplateFault>()
            .having((f) => f.code, 'code', FaultCode.unknownValue)
            .having((f) => f.code.exitStatus, 'exitStatus', 78)
            .having((f) => f.file, 'file', '.specstone/config.yaml')
            .having((f) => f.key, 'key', 'verification_coverage')
            .having((f) => f.message, 'message', contains(messagePart));

    test('coverage on with an enabled matrix section is accepted', () {
      expect(
        () => check(
          [
            record(sections: [enabledMatrix]),
          ],
          {
            'runbook': [layerOf('runbook', matrixOn)],
          },
          verificationCoverage: true,
        ),
        returnsNormally,
      );
    });

    /// The runbook merged over [layers], as the resolver folds them.
    MergedDocType mergedRunbook(DocTypeLayers layers) =>
        mergeLayers(const DocTypeMerger().builtInBase('runbook'), layers);

    test('coverage on after a layer disables the matrix section is refused '
        'naming the pack version', () {
      final shipped = [layerOf('runbook', matrixOn, file: _epicFile)];
      final layers = [
        ...shipped,
        layerOf(
          'runbook',
          'sections:\n  - {id: verification_matrix, disabled: true}\n',
        ),
      ];
      // The section was there and the project layer took it away.
      expect(verificationMatrixOf(mergedRunbook(shipped)), isNotNull);
      final disabled = mergedRunbook(layers);
      expect(verificationMatrixOf(disabled), isNull);

      expect(
        () =>
            check([disabled], {'runbook': layers}, verificationCoverage: true),
        throwsA(refusedInConfig('software-tech 1.13.0')),
      );
    });

    test('coverage on with a record doc type that never had the matrix '
        'section is refused naming the pack version', () {
      final layers = [layerOf('runbook', recordKeys, file: personalFile)];
      final lacking = mergedRunbook(layers);
      expect(lacking.sections, isEmpty);

      expect(
        () => check([lacking], {'runbook': layers}, verificationCoverage: true),
        throwsA(refusedInConfig('software-tech 1.13.0')),
      );
    });

    test('coverage on with no record doc type is refused', () {
      expect(
        () => check(
          [builtIn('feature').copyWith(path: 'prds/features/F.md')],
          {
            'feature': [layerOf('feature', 'path: prds/features/F.md\n')],
          },
          verificationCoverage: true,
        ),
        throwsA(
          refusedInConfig(
            'verification coverage reads a record, and this merged set holds '
            'no record doc type',
          ),
        ),
      );
    });

    test('coverage off is accepted with no record doc type or no matrix', () {
      for (final (docTypes, layers) in [
        (
          [builtIn('feature').copyWith(path: 'prds/features/F.md')],
          {
            'feature': [layerOf('feature', 'path: prds/features/F.md\n')],
          },
        ),
        (
          [record()],
          {
            'runbook': [layerOf('runbook', recordKeys)],
          },
        ),
      ]) {
        expect(() => check(docTypes, layers), returnsNormally);
        expect(
          () => check(docTypes, layers, verificationCoverage: false),
          returnsNormally,
        );
      }
    });
  });

  group('checkMergedSet targets', () {
    test('a targets config in a merged set with no record doc type is '
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

    test('one '
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
      final type = mergeLayers(
        const DocTypeMerger().builtInBase('runbook'),
        layers,
      );
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

  group('checkMergedSet when_field', () {
    const lowerFile = '~/.specstone/packs/runbook.yaml';
    const upperFile = '.specstone/templates/runbook.yaml';
    const fieldKind = 'fields: [{id: kind, type: string}]\n';
    const ruleOnA =
        'path: a.md\nsections: [{id: a, header: A, '
        'when_field: {field: kind, values: [api]}}]\n';

    void checkRunbook(List<String> texts) {
      final layers = [
        for (final (i, text) in texts.indexed)
          layerOf('runbook', text, file: i == 0 ? lowerFile : upperFile),
      ];
      final type = mergeLayers(
        const DocTypeMerger().builtInBase('runbook'),
        layers,
      );
      check([type], {'runbook': layers});
    }

    test('a when_field naming a field of the doc type is accepted', () {
      expect(() => checkRunbook([fieldKind, ruleOnA]), returnsNormally);
    });

    test('a field an upper layer adds is accepted', () {
      expect(() => checkRunbook([ruleOnA, fieldKind]), returnsNormally);
    });

    test('a when_field naming no field is unknown_value at the layer that '
        'wrote it', () {
      expect(
        () => checkRunbook([ruleOnA, 'description: Other\n']),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.file, 'file', lowerFile)
              .having((f) => f.key, 'key', 'sections.a.when_field.field'),
        ),
      );
    });

    test('a layer that disables the named field is unknown_value', () {
      expect(
        () => checkRunbook([
          '$fieldKind$ruleOnA',
          'fields: [{id: kind, disabled: true}]\n',
        ]),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.key,
            'key',
            'sections.a.when_field.field',
          ),
        ),
      );
    });
  });

  group('checkMergedSet pattern carriers', () {
    const header = 'path: a.md\n';
    const field = 'fields: [{id: patterns, type: string, list: true}]\n';
    const section = 'sections: [{id: out_of_scope, header: Out of scope}]\n';
    const disableSection = 'sections: [{id: out_of_scope, disabled: true}]\n';
    const disableField = 'fields: [{id: patterns, disabled: true}]\n';

    /// The file of layer [index] of the doc type [id]; each layer has its own.
    String layerFile(String id, int index) =>
        '.specstone/templates/$id.$index.yaml';

    /// One layer of [id] per text, lowest first.
    DocTypeLayers layersOf(String id, List<String> texts) => [
      for (final (i, text) in texts.indexed)
        layerOf(id, text, file: layerFile(id, i)),
    ];

    /// The runbook merged over [texts], one layer each, lowest first.
    void checkRunbook(List<String> texts) {
      final layers = layersOf('runbook', texts);
      final type = mergeLayers(
        const DocTypeMerger().builtInBase('runbook'),
        layers,
      );
      check([type], {'runbook': layers});
    }

    /// The `feature` merged over [featureTexts] and the `epic` that extends it
    /// merged over [epicTexts], the epic starting from the merged feature as
    /// the resolver builds it; the epic is checked before the feature.
    void checkEpic(
      List<String> featureTexts, [
      List<String> epicTexts = const [],
    ]) {
      final featureLayers = layersOf('feature', featureTexts);
      final feature = mergeLayers(
        const DocTypeMerger().builtInBase('feature'),
        featureLayers,
      );
      final epicLayers = layersOf('epic', ['extends: feature\n', ...epicTexts]);
      final epic = mergeLayers(
        MergedDocType(
          id: 'epic',
          extendsId: 'feature',
          extendsChain: const ['feature'],
          fields: feature.fields,
          sections: feature.sections,
          lint: feature.lint,
          files: const [],
          disabledFieldIds: feature.disabledFieldIds,
          disabledSectionIds: feature.disabledSectionIds,
        ),
        epicLayers,
      );
      check([epic, feature], {'feature': featureLayers, 'epic': epicLayers});
    }

    Matcher refusesAt(String file) => throwsA(
      isA<TemplateFault>()
          .having((f) => f.code, 'code', FaultCode.unknownValue)
          .having((f) => f.code.exitStatus, 'exit status', 78)
          .having((f) => f.key, 'key', 'sections.out_of_scope')
          .having((f) => f.file, 'file', file),
    );

    test('a doc type with the patterns field and no out_of_scope section is '
        'unknown_value at the layer that wrote the field', () {
      expect(
        () => checkRunbook(['$header$field']),
        refusesAt(layerFile('runbook', 0)),
      );
    });

    test('a higher layer that disables the section is named, not the layer '
        'that wrote the field', () {
      expect(
        () => checkRunbook(['$header$field$section', disableSection]),
        refusesAt(layerFile('runbook', 1)),
      );
    });

    test('a layer that disables the section below the layer that writes the '
        'field is named, not the writer', () {
      expect(
        () => checkRunbook(['$header$section', disableSection, field]),
        refusesAt(layerFile('runbook', 1)),
      );
    });

    test('a project layer that writes the field over a type with no section '
        'is named', () {
      expect(
        () => checkRunbook(['${header}description: Runbook\n', field]),
        refusesAt(layerFile('runbook', 1)),
      );
    });

    test('the highest layer that writes the field is named when several '
        'do', () {
      expect(
        () => checkRunbook(['$header$field', field]),
        refusesAt(layerFile('runbook', 1)),
      );
    });

    test('a doc type with the field and an enabled section loads', () {
      expect(() => checkRunbook(['$header$field$section']), returnsNormally);
    });

    test('a doc type that takes the field and the section through extends '
        'loads, whatever its id', () {
      expect(() => checkEpic(['$field$section']), returnsNormally);
    });

    test('a doc type that takes the field through extends and loses the '
        'section to a disabler on its target names that disabler', () {
      expect(
        () => checkEpic(['$field$section', disableSection]),
        refusesAt(layerFile('feature', 1)),
      );
    });

    test('a doc type that takes the field through extends with no section '
        'names the layer of its target that wrote the field', () {
      expect(() => checkEpic([field]), refusesAt(layerFile('feature', 0)));
    });

    test('a doc type that disables the section it took through extends names '
        'its own disabling layer', () {
      expect(
        () => checkEpic(['$field$section'], [disableSection]),
        refusesAt(layerFile('epic', 1)),
      );
    });

    test('a doc type whose patterns field a layer disables loads with no '
        'section', () {
      expect(
        () => checkRunbook(['$header$field', disableField]),
        returnsNormally,
      );
    });
  });

  group('a field lint', () {
    void checkNote({required FieldType type, bool list = false}) => check(
      [
        builtIn('runbook').copyWith(
          fields: [
            MergedField(
              id: 'note',
              type: type,
              list: list,
              lint: const FieldCaps(maxSentences: 1),
            ),
          ],
        ),
      ],
      {
        'runbook': [
          layerOf(
            'runbook',
            'fields:\n  - id: note\n    lint: {max_sentences: 1}\n',
          ),
        ],
      },
    );

    final lintFault = isA<TemplateFault>()
        .having((f) => f.code, 'code', FaultCode.unknownKey)
        .having((f) => f.key, 'key', 'fields.note.lint')
        .having((f) => f.file, 'file', _runbookFile);

    test('on a non-string field is unknown_key at the field lint key', () {
      expect(() => checkNote(type: FieldType.integer), throwsA(lintFault));
    });

    test('on a list string field is unknown_key at the field lint key', () {
      expect(
        () => checkNote(type: FieldType.string, list: true),
        throwsA(lintFault),
      );
    });

    test('on a plain string field loads', () {
      expect(() => checkNote(type: FieldType.string), returnsNormally);
    });
  });
}
