import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/generator_kinds.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';

const _zeta = '''
id: zeta
description: A second doc type on the same paths.
path: prds/features/f{nn}_rendering/FEATURE.md
''';

const _featureDir = 'prds/features/f05_rendering';
const _feature = 'docs/$_featureDir/FEATURE.md';
const _notes = 'docs/$_featureDir/notes.md';
const _story = 'docs/$_featureDir/us01_format_docs/USER_STORY.md';

const _featureFormatted =
    '# F-05\n\n## Feature name\n- **Human:** Rendering\n\n'
    '## Feature goal\n- **why:** share docs\n';
const _featureOutOfOrder =
    '# F-05\n\n## Feature goal\n- **why:** share docs\n\n'
    '## Feature name\n- **Human:** Rendering\n';
const _storyFormatted =
    '# US-01\n\n## Summary\nFormat docs.\n\n## Acceptance Criteria\nDone.\n';
const _storyOutOfOrder =
    '# US-01\n\n## Acceptance Criteria\nDone.\n\n## Summary\nFormat docs.\n';
const _storyUnknown = '$_storyFormatted\n## Notes\nx\n';

const _bom = [0xEF, 0xBB, 0xBF];

typedef _Run = ({Directory root, DocsProject project});

Future<_Run> _open(
  Map<String, String> docs, {
  Map<String, String> extra = const {},
}) async {
  final root = await fixtureProject(docs);
  final project = DocsProject.open(
    templates: TemplateResolver(shippedFiles: fixturePackFiles(extra: extra)),
    workingDirectory: root,
    homeDirectory: null,
  );
  return (root: root, project: project);
}

FormatReport _run(_Run run, {bool check = false, String? target}) =>
    runFormat<void>(
      run.project,
      run.project.resolveTarget(
        target,
        workingDirectory: run.root,
        defaultsToDocsRoot: true,
      ),
      check: check,
    );

File _file(_Run run, String path) =>
    File('${run.root.path}${Platform.pathSeparator}$path');

String _read(_Run run, String path) => _file(run, path).readAsStringSync();

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

const String _noteA = 'docs/notes/a.md';
const String _noteB = 'docs/notes/b.md';
const String _end = generatedEndMarker;
final String _toc = generatedOpenMarker('note_toc');

/// Counts the calls a [GeneratorRun] gets.
final class _Calls {
  int opened = 0;
  int closed = 0;
  void Function()? onOpen;
  void Function()? onClose;
}

GeneratorRun<String> _tocRun(
  _Calls calls, {
  String resolver = 'R1',
  bool noBlocks = false,
}) => GeneratorRun<String>(
  registry: GeneratorRegistry<String>({
    'note_toc': (doc, type, r) => noBlocks
        ? const []
        : [
            GeneratedBlock(
              kind: 'note_toc',
              sectionId: 'contents',
              place: const SectionTop(),
              text: 'toc $r',
            ),
          ],
  }),
  open: () {
    calls.opened++;
    calls.onOpen?.call();
    return (
      resolver: resolver,
      close: () {
        calls.closed++;
        calls.onClose?.call();
      },
    );
  },
);

Future<_Run> _openNotes(Map<String, String> docs) async {
  final root = await fixtureProject(docs);
  final project = DocsProject.open(
    templates: TemplateResolver(
      shippedFiles: fixturePackFiles(extra: {'note.yaml': _note}),
      generatorKinds: {...shippedGeneratorKinds, 'note_toc'},
    ),
    workingDirectory: root,
    homeDirectory: null,
  );
  return (root: root, project: project);
}

FormatReport _runNotes(
  _Run run,
  GeneratorRun<String> generators, {
  bool check = false,
  String? target,
}) => runFormat<String>(
  run.project,
  run.project.resolveTarget(
    target,
    workingDirectory: run.root,
    defaultsToDocsRoot: true,
  ),
  check: check,
  generators: generators,
);

String _noteDoc(String block, {String front = ''}) =>
    '$front# A\n\n## Contents\n$block\nbody\n\n## Steps\nx\n';

String _fresh() => '$_toc\ntoc R1\n$_end';

String _stale() => '$_toc\nold\n$_end';

void main() {
  test('f05/us01/fr07/e01: a CRLF doc out of order is written with CRLF '
      'only', () async {
    final run = await _open({
      _feature: _featureOutOfOrder.replaceAll('\n', '\r\n'),
    });

    final report = _run(run);

    expect(report.files.single.status, FileStatus.formatted);
    expect(_read(run, _feature), _featureFormatted.replaceAll('\n', '\r\n'));
  });

  test('f05/us01/fr07: a BOM doc out of order is rewritten with the BOM first '
      'and the sections ordered', () async {
    final run = await _open({_feature: ''});
    _file(
      run,
      _feature,
    ).writeAsBytesSync([..._bom, ...utf8.encode(_featureOutOfOrder)]);

    final report = _run(run);

    expect(report.files.single.status, FileStatus.formatted);
    expect(_file(run, _feature).readAsBytesSync(), [
      ..._bom,
      ...utf8.encode(_featureFormatted),
    ]);
  });

  test(
    'f05/us01/fr07/e02: a doc with no line break is written with LF',
    () async {
      final run = await _open({_feature: '# T'});

      final report = _run(run);

      expect(report.files.single.status, FileStatus.formatted);
      expect(
        _read(run, _feature),
        '# T\n\n## Feature name\n\n## Feature goal\n- **why:**\n',
      );
    },
  );

  test('f05/us01/fr06/e01, f05/us01/fr07/e04, s03/inv7, s03/inv8: a CRLF '
      'copy of a formatted doc is unchanged, not written, not listed by '
      'check', () async {
    final crlf = _featureFormatted.replaceAll('\n', '\r\n');
    final run = await _open({_feature: crlf});
    final old = DateTime.utc(2000);
    _file(run, _feature).setLastModifiedSync(old);

    for (final check in [true, false]) {
      final report = _run(run, check: check);

      expect(report.files.single.status, FileStatus.unchanged);
      expect(report.toText(), '');
      expect(report.exitStatus, 0);
    }
    expect(_read(run, _feature), crlf);
    expect(
      _file(run, _feature).lastModifiedSync().millisecondsSinceEpoch,
      old.millisecondsSinceEpoch,
    );
  });

  test(
    'f05/us01/fr06, f05/us01/fr06/e02, f05/us01/fr06/e04: check lists '
    'what would change and writes nothing; formatted docs list nothing',
    () async {
      final run = await _open({
        _feature: _featureOutOfOrder,
        _story: _storyUnknown,
      });

      final report = _run(run, check: true);

      expect(_read(run, _feature), _featureOutOfOrder);
      expect(_read(run, _story), _storyUnknown);
      expect(
        report.toText(),
        '$_feature\n$_story: refused: unknown header "## Notes"\n',
      );
      expect(report.exitStatus, 1);

      final clean = await _open({
        _feature: _featureFormatted,
        _story: _storyFormatted,
      });
      final cleanReport = _run(clean, check: true);
      expect(cleanReport.toText(), '');
      expect(cleanReport.exitStatus, 0);
    },
  );

  test('f05/us01/fr06/e03, f05/us01/fr02/e02: a doc no doc type matches is '
      'skipped with a warning; the others are still formatted', () async {
    final run = await _open({
      _feature: _featureOutOfOrder,
      _notes: 'free text',
    });

    final report = _run(run);

    expect(
      [for (final f in report.files) (f.path, f.status)],
      [(_feature, FileStatus.formatted), (_notes, FileStatus.skipped)],
    );
    expect(report.warnings, [
      '$_notes: no doc type matches this path; skipped',
    ]);
    expect(report.exitStatus, 0);
    expect(_read(run, _feature), _featureFormatted);
    expect(_read(run, _notes), 'free text');
  });

  test('f05/us01/fr02/e02: hidden files are neither listed nor warned '
      'about', () async {
    final run = await _open({
      _feature: _featureFormatted,
      'docs/$_featureDir/.DS_Store': 'x',
      'docs/$_featureDir/.draft.md': 'x',
    });

    final report = _run(run);

    expect([for (final f in report.files) f.path], [_feature]);
    expect(report.warnings, isEmpty);
  });

  test('f05/us01/fr02/e03, s03/inv6: a doc two doc types match is refused '
      'with their ids and left alone', () async {
    final run = await _open(
      {_feature: _featureOutOfOrder},
      extra: {'zeta.yaml': _zeta},
    );

    final report = _run(run);

    final file = report.files.single;
    expect(file.status, FileStatus.refused);
    expect(file.docTypes, ['feature', 'zeta']);
    expect(
      report.toText(),
      '$_feature: refused: doc types feature, zeta match this path\n',
    );
    expect(report.exitStatus, 1);
    expect(_read(run, _feature), _featureOutOfOrder);
  });

  test('f05/us01/fr08/e02, s03/inv6: a refused doc does not stop the others '
      'from being written; exit 1', () async {
    final run = await _open({
      _feature: _featureOutOfOrder,
      _story: _storyUnknown,
    });

    final report = _run(run);

    expect(_read(run, _feature), _featureFormatted);
    expect(_read(run, _story), _storyUnknown);
    expect(report.exitStatus, 1);
    expect(
      report.toText(),
      '$_feature: formatted\n$_story: refused: unknown header "## Notes"\n',
    );
  });

  test('f05/us01/fr04: a doc ending inside a fence is refused and left '
      'alone; a second run adds no section either', () async {
    const unclosed = '# F-05\n\n## Feature name\n- **Human:** x\n```\ncode\n';
    final run = await _open({_feature: unclosed, _story: _storyOutOfOrder});

    for (var pass = 0; pass < 2; pass++) {
      final report = _run(run);

      final file = report.files.first;
      expect(file.status, FileStatus.refused);
      expect(file.unclosedFence, isTrue);
      expect(
        report.toText(),
        contains(
          '$_feature: refused: unclosed code '
          'fence\n',
        ),
      );
      expect(report.exitStatus, 1);
      expect(_read(run, _feature), unclosed);
      expect(_read(run, _story), _storyFormatted);
    }
  });

  test('f05/us01/fr04: under check a doc ending inside a fence is listed '
      'as refused and exits 1', () async {
    final run = await _open({_feature: '# F-05\n\n```\n'});

    final report = _run(run, check: true);

    expect(report.toText(), '$_feature: refused: unclosed code fence\n');
    expect(report.exitStatus, 1);
  });

  test('f05/us01/fr04: toJson carries unclosedFence only when true', () async {
    final run = await _open({
      _feature: '# F-05\n\n```\n',
      _story: _storyFormatted,
    });

    final json = _run(run, target: 'docs/$_featureDir').toJson();

    expect(json['files'], [
      {'path': _feature, 'status': 'refused', 'unclosedFence': true},
      {'path': _story, 'status': 'unchanged'},
    ]);
  });

  test('f05/us01/fr06/e02: a refused doc lists a duplicate header with its '
      'template form', () async {
    final run = await _open({_story: '$_storyFormatted\n## Summary\ntwice\n'});

    final report = _run(run, check: true);

    expect(
      report.toText(),
      '$_story: refused: duplicate header "## Summary"\n',
    );
    expect(report.files.single.duplicateHeaders, ['## Summary']);
  });

  test('f05/us01/fr08, f05/us01/fr08/e01: toJson holds every file in tree '
      'order and the plain warnings', () async {
    final run = await _open({
      _feature: _featureOutOfOrder,
      _notes: 'free text',
      _story: _storyFormatted,
    });

    final json = _run(run, target: 'docs/$_featureDir').toJson();

    expect(json, {
      'files': [
        {'path': _feature, 'status': 'formatted'},
        {'path': _notes, 'status': 'skipped'},
        {'path': _story, 'status': 'unchanged'},
      ],
      'warnings': ['$_notes: no doc type matches this path; skipped'],
    });
  });

  test('f05/us01/fr08: toJson of refused files prints the header and doc '
      'type lists', () async {
    final run = await _open(
      {
        _feature: _featureFormatted,
        _story: '$_storyFormatted\n## Summary\ntwice\n\n## Notes\nx\n',
      },
      extra: {'zeta.yaml': _zeta},
    );

    final json = _run(run).toJson();

    expect(json['files'], [
      {
        'path': _feature,
        'status': 'refused',
        'docTypes': ['feature', 'zeta'],
      },
      {
        'path': _story,
        'status': 'refused',
        'unknownHeaders': ['## Notes'],
        'duplicateHeaders': ['## Summary'],
      },
    ]);
    expect(json['warnings'], isEmpty);
  });

  test('f05/us01/fr08/e04: every doc already formatted prints nothing, exit '
      '0', () async {
    final run = await _open({
      _feature: _featureFormatted,
      _story: _storyFormatted,
    });

    final report = _run(run);

    expect(report.toText(), '');
    expect(report.exitStatus, 0);
  });

  test('f05/us01/fr07/e03, NFR-DI01: a run leaves no temp file under '
      'docs/', () async {
    final run = await _open({
      _feature: _featureOutOfOrder,
      _story: _storyFormatted,
    });

    _run(run);

    final leftovers = [
      for (final entity in Directory(
        '${run.root.path}${Platform.pathSeparator}docs',
      ).listSync(recursive: true))
        if (entity.path.endsWith('.specstone.tmp')) entity.path,
    ];
    expect(leftovers, isEmpty);
  });

  test('Plan decision 8: a doc that is not UTF-8 is skipped with a '
      'warning and left alone', () async {
    final run = await _open({_feature: ''});
    _file(run, _feature).writeAsBytesSync([0xFF, 0xFE]);

    final report = _run(run);

    expect(report.files.single.status, FileStatus.skipped);
    expect(report.warnings, ['$_feature: not UTF-8 text; skipped']);
    expect(report.exitStatus, 0);
    expect(_file(run, _feature).readAsBytesSync(), [0xFF, 0xFE]);
  });

  test('f05/us01/fr02: a file target formats that file only', () async {
    final run = await _open({
      _feature: _featureOutOfOrder,
      _story: '$_storyFormatted\n',
    });

    final report = _run(run, target: _feature);

    expect([for (final f in report.files) f.path], [_feature]);
    expect(
      utf8.decode(_file(run, _feature).readAsBytesSync()),
      _featureFormatted,
    );
  });

  test(
    'f05/us01/fr07: a write that fails throws output_not_writable naming the '
    'doc; docs written before it stay written',
    () async {
      final run = await _open({
        _feature: _featureOutOfOrder,
        _story: _storyOutOfOrder,
      });
      final storyFolder = _file(run, _story).parent;
      await Process.run('chmod', ['555', storyFolder.path]);
      addTearDown(() => Process.run('chmod', ['755', storyFolder.path]));

      expect(
        () => _run(run),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.file, 'file', _story)
              .having((f) => f.exitStatus, 'exitStatus', 73),
        ),
      );
      expect(_read(run, _feature), _featureFormatted);
    },
    skip: Platform.isWindows ? 'chmod does not apply on Windows' : false,
  );

  group('a read-only doc', () {
    const readOnlySkip = 'file modes need chmod, which Windows lacks';

    Future<void> makeReadOnly(File file) async {
      await Process.run('chmod', ['444', file.path]);
      addTearDown(() => Process.run('chmod', ['644', file.path]));
    }

    test(
      'f05/us01/fr07: format refuses with output_not_writable and leaves the '
      'doc untouched; docs written before it stay written',
      () async {
        final run = await _open({
          _feature: _featureOutOfOrder,
          _story: _storyOutOfOrder,
        });
        await makeReadOnly(_file(run, _story));

        expect(
          () => _run(run),
          throwsA(
            isA<RenderFault>()
                .having(
                  (f) => f.code,
                  'code',
                  RenderFaultCode.outputNotWritable,
                )
                .having((f) => f.file, 'file', _story)
                .having((f) => f.message, 'message', 'the doc is read-only')
                .having((f) => f.exitStatus, 'exitStatus', 73),
          ),
        );

        expect(_read(run, _story), _storyOutOfOrder);
        expect(_file(run, _story).statSync().mode & 0x80, 0);
        expect(_read(run, _feature), _featureFormatted);
      },
      skip: Platform.isWindows ? readOnlySkip : false,
    );

    test(
      'f05/us01/fr07: a read-only doc that needs no change is unchanged',
      () async {
        final run = await _open({_feature: _featureFormatted});
        await makeReadOnly(_file(run, _feature));

        final report = _run(run);

        expect(report.files.single.status, FileStatus.unchanged);
      },
      skip: Platform.isWindows ? readOnlySkip : false,
    );

    test('f05/us01/fr07: --check lists a read-only doc that would change and '
        'raises no fault', () async {
      final run = await _open({_feature: _featureOutOfOrder});
      await makeReadOnly(_file(run, _feature));

      final report = _run(run, check: true);

      expect(report.files.single.status, FileStatus.formatted);
      expect(_read(run, _feature), _featureOutOfOrder);
    }, skip: Platform.isWindows ? readOnlySkip : false);
  });

  group('an unreadable path', () {
    test('f05/us01/fr02: a doc that cannot be read is skipped with a warning; '
        'the run goes on and its exit status stays 0', () async {
      final run = await _open({
        _feature: _featureFormatted,
        _story: _storyOutOfOrder,
      });
      final locked = _file(run, _feature);
      await Process.run('chmod', ['000', locked.path]);
      addTearDown(() => Process.run('chmod', ['644', locked.path]));

      final report = _run(run);

      expect(
        [for (final f in report.files) (f.path, f.status)],
        [(_feature, FileStatus.skipped), (_story, FileStatus.formatted)],
      );
      expect(report.warnings, ['$_feature: cannot be read; skipped']);
      expect(report.exitStatus, 0);
      expect(_read(run, _story), _storyFormatted);
    }, skip: unreadablePathSkipReason() ?? false);

    test('f05/us01/fr02: a folder that cannot be listed is skipped with a '
        'warning whose path ends in a slash', () async {
      final run = await _open({
        _feature: _featureOutOfOrder,
        _story: _storyOutOfOrder,
      });
      final locked = _file(run, _story).parent;
      await Process.run('chmod', ['000', locked.path]);
      addTearDown(() => Process.run('chmod', ['755', locked.path]));

      final report = _run(run);

      expect(report.warnings, [
        'docs/$_featureDir/us01_format_docs/: cannot be read; skipped',
      ]);
      expect([for (final f in report.files) f.path], [_feature]);
      expect(report.exitStatus, 0);
      expect(_read(run, _feature), _featureFormatted);
    }, skip: unreadablePathSkipReason() ?? false);
  });

  test('f05/us01/fr08: a docs root that is a link to a folder outside the '
      'project still reports docs/... paths', () async {
    final outside = await writeTree({
      'prds/features/f05_rendering/FEATURE.md': _featureOutOfOrder,
    });
    final root = await fixtureProject({});
    Link('${root.path}/docs').createSync(outside.path);
    final project = DocsProject.open(
      templates: TemplateResolver(shippedFiles: fixturePackFiles()),
      workingDirectory: root,
      homeDirectory: null,
    );

    final report = _run((root: root, project: project));

    expect([for (final f in report.files) f.path], [_feature]);
    expect(report.files.single.status, FileStatus.formatted);
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  group('generated blocks', () {
    test('f05/us03/s1, f05/us03/fr02/e01: format rewrites a stale block and '
        'keeps every other byte, draft and confirmed included', () async {
      const draft = '---\ndraft: true\n---\n';
      const confirmed = '---\ndraft: false\n---\n';
      final run = await _openNotes({
        _noteA: _noteDoc(_stale(), front: draft),
        _noteB: _noteDoc(_stale(), front: confirmed),
      });

      final report = _runNotes(run, _tocRun(_Calls()));

      expect(
        report.files.map((f) => f.status),
        everyElement(FileStatus.formatted),
      );
      expect(_read(run, _noteA), _noteDoc(_fresh(), front: draft));
      expect(_read(run, _noteB), _noteDoc(_fresh(), front: confirmed));
    });

    test(
      'f05/us03/s2, f05/us03/fr02/e02: format inserts a missing block',
      () async {
        final run = await _openNotes({
          _noteA: '# A\n\n## Contents\nbody\n\n## Steps\nx\n',
        });

        _runNotes(run, _tocRun(_Calls()));

        expect(_read(run, _noteA), _noteDoc(_fresh()));
      },
    );

    test('f05/us03/s3, f05/us03/fr03/e01, f05/us03/fr03/e03: format --check '
        'lists a doc with a stale block, writes nothing, exits 1', () async {
      final run = await _openNotes({_noteA: _noteDoc(_stale())});

      final report = _runNotes(run, _tocRun(_Calls()), check: true);

      expect(report.toText(), '$_noteA\n');
      expect(report.exitStatus, 1);
      expect(_read(run, _noteA), _noteDoc(_stale()));
    });

    test('f05/us03/fr03/e02: format, then format --check, lists nothing and '
        'exits 0', () async {
      final run = await _openNotes({_noteA: _noteDoc(_stale())});
      final generators = _tocRun(_Calls());

      _runNotes(run, generators);
      final report = _runNotes(run, generators, check: true);

      expect(report.toText(), '');
      expect(report.exitStatus, 0);
    });

    test(
      'f05/us03/fr03/e04: a block that cannot be resolved is not listed',
      () async {
        final run = await _openNotes({_noteA: _noteDoc(_stale())});

        final report = _runNotes(
          run,
          _tocRun(_Calls(), noBlocks: true),
          check: true,
        );

        expect(report.toText(), '');
        expect(report.exitStatus, 0);
        expect(_read(run, _noteA), _noteDoc(_stale()));
      },
    );

    test('f05/us03/s4, f05/us03/fr02/e03: a hand edit inside a block is '
        'replaced', () async {
      final run = await _openNotes({
        _noteA: _noteDoc('$_toc\nhand edit\nmore\n$_end'),
      });

      _runNotes(run, _tocRun(_Calls()));

      expect(_read(run, _noteA), _noteDoc(_fresh()));
    });

    test("f05/us03/s5, f05/us03/fr02/e08: an approved doc's block is "
        'rewritten and no draft: true is added', () async {
      final run = await _openNotes({
        _noteA: _noteDoc(_stale(), front: '---\ndraft: false\n---\n'),
      });

      _runNotes(run, _tocRun(_Calls()));

      final text = _read(run, _noteA);
      expect(text, contains('draft: false'));
      expect(text, isNot(contains('draft: true')));
      expect(text, contains('toc R1'));
    });

    test('f05/us03/s6, f05/us03/fr02/e07: a doc outside the Target is not '
        'written, and a check over the docs root lists it', () async {
      final run = await _openNotes({
        _noteA: _noteDoc(_stale()),
        _noteB: _noteDoc(_stale()),
      });

      _runNotes(run, _tocRun(_Calls()), target: _noteA);

      expect(_read(run, _noteA), _noteDoc(_fresh()));
      expect(_read(run, _noteB), _noteDoc(_stale()));
      final report = _runNotes(run, _tocRun(_Calls()), check: true);
      expect(report.toText(), '$_noteB\n');
    });

    test('f05/us03/s7, f05/us03/fr02/e06: an open block refuses the file and '
        'the other files still format', () async {
      final openDoc = '# A\n\n## Contents\n$_toc\nno end\n\n## Steps\nx\n';
      final run = await _openNotes({
        _noteA: openDoc,
        _noteB: _noteDoc(_stale()),
      });

      final report = _runNotes(run, _tocRun(_Calls()));

      final refused = report.files.firstWhere((f) => f.path == _noteA);
      expect(refused.status, FileStatus.refused);
      expect(refused.openBlock, _toc);
      expect(
        report.toText(),
        contains('$_noteA: refused: open generated block note_toc'),
      );
      expect(refused.toJson()['openBlock'], _toc);
      expect(report.exitStatus, 1);
      expect(_read(run, _noteA), openDoc);
      expect(_read(run, _noteB), _noteDoc(_fresh()));
    });

    test('f05/us03/fr01/e02: a run with no doc type listing generators never '
        'calls open', () async {
      final run = await _openNotes({_feature: _featureOutOfOrder});
      final calls = _Calls();

      _runNotes(run, _tocRun(calls));

      expect(calls.opened, 0);
      expect(calls.closed, 0);
    });

    test('f05/us03/fr01: open runs once per run, before the first write, and '
        'close runs after the last', () async {
      final run = await _openNotes({
        _noteA: _noteDoc(_stale()),
        _noteB: _noteDoc(_stale()),
      });
      final calls = _Calls();
      final events = <String>[];
      List<String> snapshot() => [_read(run, _noteA), _read(run, _noteB)];
      final stale = _noteDoc(_stale());
      final fresh = _noteDoc(_fresh());
      String when(String docs, String yes, String no) =>
          snapshot().join('|') == docs ? yes : no;
      calls
        ..onOpen = () {
          final at = when('$stale|$stale', 'before writes', 'after a write');
          events.add('open $at');
        }
        ..onClose = () {
          final at = when(
            '$fresh|$fresh',
            'after last write',
            'before last write',
          );
          events.add('close $at');
        };

      _runNotes(run, _tocRun(calls));

      expect(calls.opened, 1);
      expect(calls.closed, 1);
      expect(events, ['open before writes', 'close after last write']);
    });

    test('f05/us03/fr01: close still runs once when a write throws', () async {
      final run = await _openNotes({_noteA: _noteDoc(_stale())});
      final folder = _file(run, _noteA).parent;
      await Process.run('chmod', ['555', folder.path]);
      addTearDown(() => Process.run('chmod', ['755', folder.path]));
      final calls = _Calls();

      expect(() => _runNotes(run, _tocRun(calls)), throwsA(isA<RenderFault>()));

      expect(calls.opened, 1);
      expect(calls.closed, 1);
    }, skip: Platform.isWindows ? 'chmod does not apply on Windows' : false);

    test('f05/us03/fr01/e05: a fault from open stops the run and writes no '
        'file', () async {
      final run = await _openNotes({
        _noteA: _noteDoc(_stale()),
        _noteB: _noteDoc(_stale()),
      });
      final failing = GeneratorRun<String>(
        registry: GeneratorRegistry<String>({}),
        open: () => throw IndexFault(IndexFaultCode.indexBusy, 'busy'),
      );

      expect(() => _runNotes(run, failing), throwsA(isA<IndexFault>()));

      expect(_read(run, _noteA), _noteDoc(_stale()));
      expect(_read(run, _noteB), _noteDoc(_stale()));
    });

    test('f05/us01/fr03: sections out of order are reordered and each body '
        'is kept byte for byte outside its block', () async {
      final run = await _openNotes({
        _noteA: '# A\n\n## Steps\nx\n  y\n\n## Contents\nbody\n',
      });

      _runNotes(run, _tocRun(_Calls()));

      expect(
        _read(run, _noteA),
        '# A\n\n## Contents\n${_fresh()}\nbody\n\n## Steps\nx\n  y\n',
      );
    });

    test('f05/us03/fr02: a CRLF doc gets its block in CRLF, and a second run '
        'is unchanged', () async {
      final run = await _openNotes({
        _noteA: _noteDoc(_stale()).replaceAll('\n', '\r\n'),
      });
      final generators = _tocRun(_Calls());

      _runNotes(run, generators);
      expect(_read(run, _noteA), _noteDoc(_fresh()).replaceAll('\n', '\r\n'));
      final again = _runNotes(run, generators);

      expect(again.files.single.status, FileStatus.unchanged);
    });
  });
}
