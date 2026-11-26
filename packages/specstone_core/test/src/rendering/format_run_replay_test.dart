import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/models/opened_resolver.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/generator_kinds.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';
import '../../helpers/temp_tree.dart';

const _note = '''
id: note
description: A note with a generated block.
path: notes/{slug}.md
generators: [note_toc]
sections:
  - id: contents
    header: Contents
  - id: steps
    header: Steps
''';

const _groupedFeature = 'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n';

const _areaIndex = '''
id: area_index
description: One index per feature group.
path_from: feature_groups
file: AREA.md
generators: [area_catalog]
sections:
  - id: features
    header: Features
''';

const _featureMap = '''
id: feature_map
description: The features doc.
path: prds/FEATURES.md
generators: [group_rows]
sections:
  - id: features
    header: Features
''';

final String _toc = generatedOpenMarker('note_toc');
final String _rows = generatedOpenMarker('group_rows');
final String _area = generatedOpenMarker('area_catalog');
const String _end = generatedEndMarker;

String _noteDoc(String body, {String block = 'toc R1'}) =>
    '# A\n\n## Contents\n\n$_toc\n$block\n$_end\n\n$body\n\n## Steps\n\nx\n';

String _mapDoc(String groups) =>
    '# Features\n\n## Features\n\n$_rows\ngroups[$groups]\n$_end\n';

String _areaDoc(String slug, {String? rows}) =>
    '# $slug\n\n## Features\n\n$_area\n'
    '${rows ?? 'rows of prds/features/$slug/AREA.md'}\n$_end\n';

const _map = 'docs/prds/FEATURES.md';

String _areaPath(String slug) => 'docs/prds/features/$slug/AREA.md';

/// A fixture project and the root folder it sits in.
final class _Open {
  const new({required this.root, required this.project});

  final Directory root;
  final DocsProject project;
}

Future<_Open> _open(Map<String, String> files) async {
  final root = await fixtureProject({
    '.specstone/templates/feature.yaml': _groupedFeature,
    '.specstone/templates/area_index.yaml': _areaIndex,
    '.specstone/templates/feature_map.yaml': _featureMap,
    ...files,
  });
  final project = DocsProject.open(
    templates: TemplateResolver(
      shippedFiles: fixturePackFiles(extra: {'note.yaml': _note}),
      generatorKinds: {
        ...shippedGeneratorKinds,
        'note_toc',
        'group_rows',
        'area_catalog',
      },
    ),
    workingDirectory: root,
    homeDirectory: null,
  );
  return _Open(root: root, project: project);
}

String _read(_Open open, String path) =>
    File('${open.root.path}/$path').readAsStringSync();

bool _exists(_Open open, String path) =>
    File('${open.root.path}/$path').existsSync();

/// Generators of the notes and of a grouped features doc; the resolver is the
/// list of group slugs, and [finishJournal] is what a write
/// command's replay of a pending journal is.
GeneratorRun<List<String>> _run(
  List<String> slugs, {
  void Function()? finishJournal,
  void Function(void Function() write)? lockWrites,
}) => GeneratorRun<List<String>>(
  finishJournal: finishJournal,
  registry: GeneratorRegistry<List<String>>(
    {
      'note_toc': (doc, docPath, type, r) => const [
        GeneratedBlock(
          kind: 'note_toc',
          sectionId: 'contents',
          place: SectionTop(),
          text: 'toc R1',
        ),
      ],
      'group_rows': (doc, docPath, type, r) => [
        GeneratedBlock(
          kind: 'group_rows',
          sectionId: 'features',
          place: const SectionTop(),
          text: 'groups[${r.join(',')}]',
        ),
      ],
      'area_catalog': (doc, docPath, type, r) => [
        GeneratedBlock(
          kind: 'area_catalog',
          sectionId: 'features',
          place: const SectionTop(),
          text: 'rows of $docPath',
        ),
      ],
    },
    companions: {
      'group_rows': (docPath, type, r) => CompanionDocs(
        docTypeId: 'area_index',
        docs: [
          for (final slug in r)
            CompanionDoc(
              docPath: 'prds/features/$slug/AREA.md',
              seedText: '# $slug\n\n## Features\n',
            ),
        ],
      ),
    },
  ),
  open: () => OpenedResolver(
    resolver: slugs,
    close: () {},
    lockWrites: lockWrites ?? (write) => write(),
  ),
);

FormatReport _format(
  _Open open,
  GeneratorRun<List<String>> run, {
  Directory? home,
}) => runFormat<List<String>>(
  open.project,
  open.project.resolveTarget(
    null,
    workingDirectory: open.root,
    defaultsToDocsRoot: true,
  ),
  check: false,
  generators: run,
  homeDirectory: home,
);

/// Records a journal of [steps] and stops before its first step, as a command
/// that died right after saving it does.
void _stopAfterSaving(_Open open, Directory home, List<JournalStep> steps) {
  expect(
    () => MoveJournal(steps).run(
      JournalTarget.of(open.project, homeDirectory: home),
      onSaved: () => throw StateError('stopped'),
    ),
    throwsStateError,
  );
}

void main() {
  group('a pending journal finished before the run reads', () {
    test('a doc the journal moved stays at its new path, and a doc it '
        'rewrote keeps the rewrite', () async {
      final open = await _open({
        'docs/notes/a.md': _noteDoc('moved body', block: 'old'),
        'docs/notes/b.md': _noteDoc('old body', block: 'old'),
      });
      final home = await writeTree({});
      final bBefore = _read(open, 'docs/notes/b.md');
      _stopAfterSaving(open, home, [
        const MoveStep('docs/notes/a.md', 'docs/notes/c.md'),
        WriteStep(
          'docs/notes/b.md',
          _noteDoc('replayed body', block: 'old'),
          before: textHashOf(bBefore),
        ),
      ]);
      void replay() => MoveJournal.replay(
        JournalTarget.of(open.project, homeDirectory: home),
      );

      _format(open, _run([], finishJournal: replay), home: home);

      expect(_exists(open, 'docs/notes/a.md'), isFalse);
      expect(_read(open, 'docs/notes/c.md'), _noteDoc('moved body'));
      expect(_read(open, 'docs/notes/b.md'), _noteDoc('replayed body'));
      expect(MoveJournal.pending(open.root), isFalse);
    });
  });

  group('finishing a pending journal', () {
    test('runs only for a write that finds a journal pending', () async {
      final open = await _open({
        'docs/notes/a.md': _noteDoc('body', block: 'old'),
      });
      final home = await writeTree({});
      var finished = 0;
      void finish() => finished++;

      _format(open, _run([], finishJournal: finish), home: home);
      expect(finished, 0);

      _stopAfterSaving(open, home, [
        const MoveStep('docs/notes/a.md', 'docs/notes/c.md'),
      ]);
      runFormat<List<String>>(
        open.project,
        open.project.resolveTarget(
          null,
          workingDirectory: open.root,
          defaultsToDocsRoot: true,
        ),
        check: true,
        generators: _run([], finishJournal: finish),
      );
      expect(finished, 0);
    });
  });

  group('the journaled group write checks creates and deletes again', () {
    test('a doc that appeared where a companion is created refuses the '
        'group, and nothing is written', () async {
      final open = await _open({
        _map: _mapDoc('old'),
        _areaPath('form'): _areaDoc('form'),
      });
      final home = await writeTree({});
      final appeared = _areaPath('list');
      void lock(void Function() write) {
        File('${open.root.path}/$appeared')
          ..createSync(recursive: true)
          ..writeAsStringSync('someone else\n');
        write();
      }

      expect(
        () =>
            _format(open, _run(['form', 'list'], lockWrites: lock), home: home),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.file, 'file', appeared),
        ),
      );

      expect(_read(open, _map), _mapDoc('old'));
      expect(_read(open, appeared), 'someone else\n');
      expect(MoveJournal.pending(open.root), isFalse);
    });

    test('a doc the group deletes that changed since the run read it '
        'refuses the group, and nothing is written', () async {
      final open = await _open({
        _map: _mapDoc('old'),
        _areaPath('form'): _areaDoc('form'),
        _areaPath('gone'): _areaDoc('gone'),
      });
      final home = await writeTree({});
      final edited = _areaDoc('gone', rows: 'edited meanwhile');
      void lock(void Function() write) {
        File('${open.root.path}/${_areaPath('gone')}')
            .writeAsStringSync(edited);
        write();
      }

      expect(
        () => _format(open, _run(['form'], lockWrites: lock), home: home),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.file, 'file', _areaPath('gone')),
        ),
      );

      expect(_read(open, _areaPath('gone')), edited);
      expect(_read(open, _map), _mapDoc('old'));
      expect(MoveJournal.pending(open.root), isFalse);
    });
  });
}
