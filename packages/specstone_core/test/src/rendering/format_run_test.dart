import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/feature_catalog.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/models/opened_resolver.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/generator_kinds.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, withApprovalHashes;
import '../../helpers/fixture_doc_types.dart';
import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart' show shippedPinsConfig;
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
const _featureJson = '$_featureDir/FEATURE.md';
const _notesJson = '$_featureDir/notes.md';
const _storyJson = '$_featureDir/us01_format_docs/USER_STORY.md';

const _featureFormatted =
    '# F-05\n\n## Feature name\n\n- **Human:** Rendering\n\n'
    '## Feature goal\n\n- **why:** share docs\n';
const _featureOutOfOrder =
    '# F-05\n\n## Feature goal\n\n- **why:** share docs\n\n'
    '## Feature name\n\n- **Human:** Rendering\n';
const _storyFormatted =
    '# US-01\n\n## Summary\n\nFormat docs.\n\n'
    '## Acceptance Criteria\n\nDone.\n';
const _storyOutOfOrder =
    '# US-01\n\n## Acceptance Criteria\n\nDone.\n\n'
    '## Summary\n\nFormat docs.\n';
const _storyUnknown = '$_storyFormatted\n## Notes\nx\n';

const _bom = [0xEF, 0xBB, 0xBF];

const _recordType = '''
id: implementation
description: One feature record.
path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md
parent: feature
per_target: true
fields:
  - id: statuses
    type: record_status
    list: true
''';

const _record = '.specstone/records/f05_rendering/IMPLEMENTATION.md';
const _recordOnDisk = '# Record\nbody   \n';
const _recordFormatted = '# Record\n\nbody\n';

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

FormatReport _runWithRecords(_Run run, {String? target}) => runFormat<void>(
  run.project,
  run.project.resolveTarget(
    target,
    workingDirectory: run.root,
    defaultsToDocsRoot: true,
    includeRecordsRoot: true,
  ),
  check: false,
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
    'note_toc': (doc, docPath, type, r) => noBlocks
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
    return OpenedResolver(
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

/// Opens a project whose doc types hold the notes type and the [extra] ones.
Future<_Run> _openMixed(
  Map<String, String> docs, {
  Map<String, String> extra = const {},
}) async {
  final root = await fixtureProject(docs);
  final project = DocsProject.open(
    templates: TemplateResolver(
      shippedFiles: fixturePackFiles(extra: {'note.yaml': _note, ...extra}),
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
    '$front# A\n\n## Contents\n\n$block\nbody\n\n## Steps\n\nx\n';

String _fresh() => '$_toc\ntoc R1\n$_end';

String _stale() => '$_toc\nold\n$_end';

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

const _mapPath = 'docs/prds/FEATURES.md';
final String _rowsMarker = generatedOpenMarker('group_rows');
final String _areaMarker = generatedOpenMarker('area_catalog');

String _areaPath(String slug) => 'docs/prds/features/$slug/AREA.md';

String _mapDoc(String groups) =>
    '# Features\n\n## Features\n\n$_rowsMarker\ngroups[$groups]\n$_end\n';

String _areaDoc(String slug, {String? rows}) =>
    '# $slug\n\n## Features\n\n$_areaMarker\n'
    '${rows ?? 'rows of prds/features/$slug/AREA.md'}\n$_end\n';

/// The docs of a grouped project holding [groups], each with a fresh doc.
Map<String, String> _freshGroups(List<String> groups) => {
  _mapPath: _mapDoc(groups.join(',')),
  for (final slug in groups) _areaPath(slug): _areaDoc(slug),
};

/// Generators of a grouped features doc: the resolver is the group slugs, and
/// each slug has one `AREA.md` companion.
GeneratorRun<List<String>> _groupRun(
  List<String> groups, {
  void Function(void Function() write)? lockWrites,
}) => GeneratorRun<List<String>>(
  registry: GeneratorRegistry<List<String>>(
    {
      'group_rows': (doc, docPath, type, slugs) => [
        GeneratedBlock(
          kind: 'group_rows',
          sectionId: 'features',
          place: const SectionTop(),
          text: 'groups[${slugs.join(',')}]',
        ),
      ],
      'area_catalog': (doc, docPath, type, slugs) => [
        GeneratedBlock(
          kind: 'area_catalog',
          sectionId: 'features',
          place: const SectionTop(),
          text: 'rows of $docPath',
        ),
      ],
    },
    companions: {
      'group_rows': (docPath, type, slugs) => CompanionDocs(
        docTypeId: 'area_index',
        docs: [
          for (final slug in slugs)
            CompanionDoc(
              docPath: 'prds/features/$slug/AREA.md',
              seedText: '# $slug\n\n## Features\n',
            ),
        ],
      ),
    },
  ),
  open: () => OpenedResolver(
    resolver: groups,
    close: () {},
    lockWrites: lockWrites ?? (write) => write(),
  ),
);

Future<_Run> _openGroups(Map<String, String> docs) async {
  final root = await fixtureProject({
    '.specstone/templates/feature.yaml': _groupedFeature,
    '.specstone/templates/area_index.yaml': _areaIndex,
    '.specstone/templates/feature_map.yaml': _featureMap,
    ...docs,
  });
  final project = DocsProject.open(
    templates: TemplateResolver(
      shippedFiles: fixturePackFiles(),
      generatorKinds: {...shippedGeneratorKinds, 'group_rows', 'area_catalog'},
    ),
    workingDirectory: root,
    homeDirectory: null,
  );
  return (root: root, project: project);
}

FormatReport _runGroups(
  _Run run,
  List<String> groups, {
  Directory? home,
  bool check = false,
  String? target,
  void Function(void Function() write)? lockWrites,
}) => runFormat<List<String>>(
  run.project,
  run.project.resolveTarget(
    target,
    workingDirectory: run.root,
    defaultsToDocsRoot: true,
  ),
  check: check,
  generators: _groupRun(groups, lockWrites: lockWrites),
  homeDirectory: home,
);

Future<Directory> _home() => writeTree({});

Map<String, FileStatus> _statuses(FormatReport report) => {
  for (final file in report.files) file.path: file.status,
};

bool _exists(_Run run, String path) => _file(run, path).existsSync();

void main() {
  // ignore: lines_longer_than_80_chars -- the test name stays one literal
  test('a CRLF doc with a padded table and a trailing space is laid out and written with CRLF only', () async {
    const padded =
        '# F-05\n\n## Feature name\n\n- **Human:** Rendering   \n\n'
        '## Feature goal\n\n| Field     | Type   |\n|-----------|--------|\n'
        '| why       | share  |\n';
    const laidOut =
        '# F-05\n\n## Feature name\n\n- **Human:** Rendering\n\n'
        '## Feature goal\n\n| Field | Type |\n|---|---|\n| why | share |\n';
    final cases = [
      (
        reason: 'out of order',
        disk: _featureOutOfOrder,
        written: _featureFormatted,
      ),
      (reason: 'padded table', disk: padded, written: laidOut),
    ];

    for (final (:reason, :disk, :written) in cases) {
      final run = await _open({_feature: disk.replaceAll('\n', '\r\n')});

      final report = _run(run);

      expect(report.files.single.status, FileStatus.formatted, reason: reason);
      expect(
        _read(run, _feature),
        written.replaceAll('\n', '\r\n'),
        reason: reason,
      );
    }
  });

  test('a BOM doc out of order is rewritten with the BOM first '
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

  test('a doc with no line break is written with LF', () async {
    final run = await _open({_feature: '# T'});

    final report = _run(run);

    expect(report.files.single.status, FileStatus.formatted);
    expect(_read(run, _feature), '# T\n');
  });

  test('a CRLF copy of a formatted doc is unchanged, not written, not '
      'listed by check', () async {
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

  test('check lists what would change and writes nothing; formatted docs list '
      'nothing', () async {
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
  });

  // ignore: lines_longer_than_80_chars, one literal so check finds the test
  test('check lists a doc two doc types match, a doc whose layout changes its structure, an open block, and a duplicate header; exit 1', () async {
    const structure = '---\n# F-05\n\n## Feature name\nx\n--- \n';
    final openDoc = '# A\n\n## Contents\n$_toc\nno end\n\n## Steps\nx\n';
    final cases = [
      (
        path: _feature,
        text: _featureOutOfOrder,
        extra: {'zeta.yaml': _zeta},
        line: '$_feature: refused: doc types feature, zeta match this path\n',
      ),
      (
        path: _feature,
        text: structure,
        extra: const <String, String>{},
        line: '$_feature: refused: layout would change the doc structure\n',
      ),
      (
        path: _noteA,
        text: openDoc,
        extra: const <String, String>{},
        line: '$_noteA: refused: open generated block note_toc\n',
      ),
      (
        path: _story,
        text: '$_storyFormatted\n## Summary\ntwice\n',
        extra: const <String, String>{},
        line: '$_story: refused: duplicate header "## Summary"\n',
      ),
      (
        path: _feature,
        text: '# F-05\n\n```\n',
        extra: const <String, String>{},
        line: '$_feature: refused: unclosed code fence\n',
      ),
    ];

    for (final (:path, :text, :extra, :line) in cases) {
      final run = await _openMixed({path: text}, extra: extra);

      final report = _run(run, check: true);

      expect(report.toText(), line, reason: path);
      expect(report.exitStatus, 1, reason: path);
      expect(_read(run, path), text, reason: path);
    }
  });

  // ignore: lines_longer_than_80_chars -- the test name stays one literal
  test('a doc no doc type matches is skipped with a warning; the others are still formatted', () async {
    final cases = [
      (
        check: false,
        feature: _featureOutOfOrder,
        status: FileStatus.formatted,
        after: _featureFormatted,
      ),
      (
        check: true,
        feature: _featureFormatted,
        status: FileStatus.unchanged,
        after: _featureFormatted,
      ),
    ];

    for (final (:check, :feature, :status, :after) in cases) {
      final run = await _open({_feature: feature, _notes: 'free text'});

      final report = _run(run, check: check);

      expect(
        [for (final f in report.files) (f.path, f.status)],
        [(_feature, status), (_notes, FileStatus.skipped)],
        reason: 'check $check',
      );
      expect(report.warnings, [
        '$_notes: no doc type matches this path; skipped',
      ], reason: 'check $check');
      expect(report.exitStatus, 0, reason: 'check $check');
      expect(_read(run, _feature), after, reason: 'check $check');
      expect(_read(run, _notes), 'free text', reason: 'check $check');
    }
  });

  test('hidden files are neither listed nor warned '
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

  test('a folder whose name starts with a dot is left out of the walk and '
      'never warned about', () async {
    final run = await _open({
      _feature: _featureFormatted,
      'docs/.git/HEAD': 'ref: refs/heads/main',
      'docs/$_featureDir/.git/config': 'x',
      'docs/.cache/prds/features/f06_other/FEATURE.md': _featureOutOfOrder,
    });

    final report = _run(run);

    expect([for (final f in report.files) f.path], [_feature]);
    expect(report.warnings, isEmpty);
    expect(
      _read(run, 'docs/.cache/prds/features/f06_other/FEATURE.md'),
      _featureOutOfOrder,
    );
  });

  test('a symbolic link to a file or a folder in the docs root is neither '
      'listed nor formatted', () async {
    final run = await _open({
      _feature: _featureFormatted,
      'elsewhere/FEATURE.md': _featureOutOfOrder,
      'elsewhere/folder/FEATURE.md': _featureOutOfOrder,
      'docs/prds/features/f06_linked/.keep': '',
    });
    Link(_file(run, 'docs/prds/features/f06_linked/FEATURE.md').path)
        .createSync(_file(run, 'elsewhere/FEATURE.md').path);
    Link(_file(run, 'docs/prds/features/f07_folder').path)
        .createSync(_file(run, 'elsewhere/folder').path);

    final report = _run(run);

    expect([for (final f in report.files) f.path], [_feature]);
    expect(report.warnings, isEmpty);
    expect(report.exitStatus, 0);
    expect(_read(run, 'elsewhere/FEATURE.md'), _featureOutOfOrder);
    expect(_read(run, 'elsewhere/folder/FEATURE.md'), _featureOutOfOrder);
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  group('a records root', () {
    Future<_Run> openWithRecord() => _open({
      '.specstone/templates/implementation.yaml': _recordType,
      _feature: _featureOutOfOrder,
      _record: _recordOnDisk,
    });

    test('a records file or folder as the target formats that target only; '
        'the docs root as the target takes in the records root', () async {
      final cases = [
        (target: _record, formatted: [_record]),
        (target: '.specstone/records', formatted: [_record]),
        (target: null, formatted: [_feature, _record]),
      ];

      for (final (:target, :formatted) in cases) {
        final run = await openWithRecord();

        final report = _runWithRecords(run, target: target);

        expect(
          [for (final f in report.files) f.path],
          formatted,
          reason: '$target',
        );
        expect(_read(run, _record), _recordFormatted, reason: '$target');
        expect(
          _read(run, _feature),
          formatted.contains(_feature) ? _featureFormatted : _featureOutOfOrder,
          reason: '$target',
        );
      }
    });

    // ignore: lines_longer_than_80_chars, one literal so check finds the test
    test('the json names a doc by its docs-root path and a record by its project path', () async {
      final run = await openWithRecord();

      final json = _runWithRecords(run).toJson();

      expect(json['files'], [
        {'path': _featureJson, 'status': 'formatted'},
        {'path': _record, 'status': 'formatted'},
      ]);
    });

    test('an absent records root leaves the docs root formatted alone with no '
        'refusal and no warning', () async {
      final run = await _open({_feature: _featureOutOfOrder});

      final report = _runWithRecords(run);

      expect([for (final f in report.files) f.path], [_feature]);
      expect(report.warnings, isEmpty);
      expect(report.exitStatus, 0);
      expect(_read(run, _feature), _featureFormatted);
    });

    test('a records root that is a symbolic link is not followed, with no '
        'refusal and no warning', () async {
      final run = await _open({
        '.specstone/templates/implementation.yaml': _recordType,
        _feature: _featureOutOfOrder,
        'elsewhere/f05_rendering/IMPLEMENTATION.md': _recordOnDisk,
      });
      Link(_file(run, '.specstone/records').path)
          .createSync(_file(run, 'elsewhere').path);

      final report = _runWithRecords(run);

      expect([for (final f in report.files) f.path], [_feature]);
      expect(report.warnings, isEmpty);
      expect(report.exitStatus, 0);
      expect(_read(run, _feature), _featureFormatted);
      expect(
        _read(run, 'elsewhere/f05_rendering/IMPLEMENTATION.md'),
        _recordOnDisk,
      );
    }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);
  });

  // ignore: lines_longer_than_80_chars -- the test name stays one literal
  test('a doc refused for two doc types, a duplicate header, or a layout that changes its structure leaves the other docs written; exit 1', () async {
    const structure = '---\n# F-05\n\n## Feature name\nx\n--- \n';
    final cases = [
      (
        docs: {_feature: _featureOutOfOrder, _story: _storyUnknown},
        extra: const <String, String>{},
        refused: _story,
        written: _feature,
        writtenText: _featureFormatted,
        text:
            '$_feature: formatted\n'
            '$_story: refused: unknown header "## Notes"\n',
      ),
      (
        docs: {_feature: _featureOutOfOrder, _story: _storyOutOfOrder},
        extra: {'zeta.yaml': _zeta},
        refused: _feature,
        written: _story,
        writtenText: _storyFormatted,
        text:
            '$_feature: refused: doc types feature, zeta match this path\n'
            '$_story: formatted\n',
      ),
      (
        docs: {
          _feature: _featureOutOfOrder,
          _story: '$_storyFormatted\n## Summary\ntwice\n',
        },
        extra: const <String, String>{},
        refused: _story,
        written: _feature,
        writtenText: _featureFormatted,
        text:
            '$_feature: formatted\n'
            '$_story: refused: duplicate header "## Summary"\n',
      ),
      (
        docs: {_feature: structure, _story: _storyOutOfOrder},
        extra: const <String, String>{},
        refused: _feature,
        written: _story,
        writtenText: _storyFormatted,
        text:
            '$_feature: refused: layout would change the doc structure\n'
            '$_story: formatted\n',
      ),
    ];

    for (final (:docs, :extra, :refused, :written, :writtenText, :text)
        in cases) {
      final run = await _open(docs, extra: extra);

      final report = _run(run);

      expect(report.toText(), text, reason: refused);
      expect(report.exitStatus, 1, reason: refused);
      expect(_read(run, refused), docs[refused], reason: refused);
      expect(_read(run, written), writtenText, reason: written);
    }
  });

  test('a doc that ends inside a code fence is refused and left '
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

  test('toJson carries unclosedFence only when true', () async {
    final run = await _open({
      _feature: '# F-05\n\n```\n',
      _story: _storyFormatted,
    });

    final json = _run(run, target: 'docs/$_featureDir').toJson();

    expect(json['files'], [
      {'path': _featureJson, 'status': 'refused', 'unclosedFence': true},
      {'path': _storyJson, 'status': 'unchanged'},
    ]);
  });

  test('a doc whose layout '
      'would turn a body line into a frontmatter close is refused and left '
      'alone', () async {
    const text = '---\n# F-05\n\n## Feature name\nx\n--- \n';
    final run = await _open({_feature: text});

    final report = _run(run);

    expect(report.files.single.status, FileStatus.refused);
    expect(
      report.toText(),
      '$_feature: refused: layout would change the doc structure\n',
    );
    expect(report.toJson()['files'], [
      {'path': _featureJson, 'status': 'refused', 'changesStructure': true},
    ]);
    expect(report.exitStatus, 1);
    expect(_read(run, _feature), text);
  });

  test('toJson holds every file in tree '
      'order and the plain warnings', () async {
    final run = await _open({
      _feature: _featureOutOfOrder,
      _notes: 'free text',
      _story: _storyFormatted,
    });

    final json = _run(run, target: 'docs/$_featureDir').toJson();

    expect(json, {
      'files': [
        {'path': _featureJson, 'status': 'formatted'},
        {'path': _notesJson, 'status': 'skipped'},
        {'path': _storyJson, 'status': 'unchanged'},
      ],
      'warnings': ['$_notes: no doc type matches this path; skipped'],
    });
  });

  test('toJson of refused files prints the header and doc '
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
        'path': _featureJson,
        'status': 'refused',
        'docTypes': ['feature', 'zeta'],
      },
      {
        'path': _storyJson,
        'status': 'refused',
        'unknownHeaders': ['## Notes'],
        'duplicateHeaders': ['## Summary'],
      },
    ]);
    expect(json['warnings'], isEmpty);
  });

  test('a run leaves no temp file under '
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

  test('a doc that is not UTF-8 does not stop the other docs from being '
      'written; exit 0', () async {
    final run = await _open({_feature: '', _story: _storyOutOfOrder});
    _file(run, _feature).writeAsBytesSync([0xFF, 0xFE]);

    final report = _run(run);

    expect(
      [for (final f in report.files) (f.path, f.status)],
      [(_feature, FileStatus.skipped), (_story, FileStatus.formatted)],
    );
    expect(report.warnings, ['$_feature: not UTF-8 text; skipped']);
    expect(report.exitStatus, 0);
    expect(_file(run, _feature).readAsBytesSync(), [0xFF, 0xFE]);
    expect(_read(run, _story), _storyFormatted);
  });

  test('a file target formats that file only', () async {
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

  test('a write that fails throws output_not_writable naming the '
      'doc; docs written before it stay written', () async {
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
  }, skip: Platform.isWindows ? 'chmod does not apply on Windows' : false);

  group('a read-only doc', () {
    const readOnlySkip = 'file modes need chmod, which Windows lacks';

    Future<void> makeReadOnly(File file) async {
      await Process.run('chmod', ['444', file.path]);
      addTearDown(() => Process.run('chmod', ['644', file.path]));
    }

    test('format refuses with output_not_writable and leaves the '
        'doc untouched; docs written before it stay written', () async {
      final run = await _open({
        _feature: _featureOutOfOrder,
        _story: _storyOutOfOrder,
      });
      await makeReadOnly(_file(run, _story));

      expect(
        () => _run(run),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.file, 'file', _story)
              .having((f) => f.message, 'message', 'the doc is read-only')
              .having((f) => f.exitStatus, 'exitStatus', 73),
        ),
      );

      expect(_read(run, _story), _storyOutOfOrder);
      expect(_file(run, _story).statSync().mode & 0x80, 0);
      expect(_read(run, _feature), _featureFormatted);
    }, skip: Platform.isWindows ? readOnlySkip : false);

    test('a doc with the Windows read-only attribute set refuses with '
        'output_not_writable and stays untouched; docs written before it stay '
        'written', () async {
      final run = await _open({
        _feature: _featureOutOfOrder,
        _story: _storyOutOfOrder,
      });
      final story = _file(run, _story);
      addTearDown(() => Process.run('attrib', ['-R', story.path]));
      expect((await Process.run('attrib', ['+R', story.path])).exitCode, 0);

      expect(
        () => _run(run),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.file, 'file', _story)
              .having((f) => f.message, 'message', 'the doc is read-only')
              .having((f) => f.exitStatus, 'exitStatus', 73),
        ),
      );

      expect(_read(run, _story), _storyOutOfOrder);
      expect(_read(run, _feature), _featureFormatted);
    }, testOn: 'windows');

    test('a read-only doc that needs no change is unchanged', () async {
      final run = await _open({_feature: _featureFormatted});
      await makeReadOnly(_file(run, _feature));

      final report = _run(run);

      expect(report.files.single.status, FileStatus.unchanged);
    }, skip: Platform.isWindows ? readOnlySkip : false);

    test('--check lists a read-only doc that would change and '
        'raises no fault', () async {
      final run = await _open({_feature: _featureOutOfOrder});
      await makeReadOnly(_file(run, _feature));

      final report = _run(run, check: true);

      expect(report.files.single.status, FileStatus.formatted);
      expect(_read(run, _feature), _featureOutOfOrder);
    }, skip: Platform.isWindows ? readOnlySkip : false);
  });

  group('an unreadable path', () {
    test('a doc that cannot be read is skipped with a warning; '
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

    test('a folder that cannot be listed is skipped with a '
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

  test('a docs root that is a link to a folder outside the '
      'project still reports docs/... paths', () async {
    final outside = await writeTree({
      'prds/features/f05_rendering/FEATURE.md': _featureOutOfOrder,
    });
    final root = await fixtureProject({});
    Link('${root.path}/docs').createSync(outside.path);
    // A docs folder outside the project is writable once the Owner trusts it.
    final home = await writeTree({});
    RootTrust.locate(root, homeDirectory: home).record();
    final project = DocsProject.open(
      templates: TemplateResolver(shippedFiles: fixturePackFiles()),
      workingDirectory: root,
      homeDirectory: home,
    );

    final report = _run((root: root, project: project));

    expect([for (final f in report.files) f.path], [_feature]);
    expect(report.files.single.status, FileStatus.formatted);
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  test('an approved doc rewritten by format keeps an approval hash that '
      'still matches its text', () async {
    final run = await _open({_feature: ''});
    final docType = (run.project.matcher.match(
      'prds/features/f05_rendering/FEATURE.md',
    ) as MatchedDocType).docType;
    String hashOf(String text) => approvalHashOf(toLf(text), docType);
    final hash = hashOf(_featureOutOfOrder);
    final approved = '---\napproved: "$hash"\n---\n$_featureOutOfOrder';
    _file(run, _feature).writeAsStringSync(approved);
    expect(hashOf(approved), hash);

    final report = _run(run);

    expect(report.files.single.status, FileStatus.formatted);
    final written = _read(run, _feature);
    expect(written, isNot(approved));
    expect(written, startsWith('---\napproved: "$hash"\n---\n'));
    expect(hashOf(written), hash);
  });

  test('a first write is refused when no trust record matches the docs '
      'folder outside the project', () async {
    final outside = await writeTree({
      'prds/features/f05_rendering/FEATURE.md': _featureOutOfOrder,
    });
    final root = await fixtureProject({});
    Link('${root.path}/docs').createSync(outside.path);
    final home = await writeTree({});
    final project = DocsProject.open(
      templates: TemplateResolver(shippedFiles: fixturePackFiles()),
      workingDirectory: root,
      homeDirectory: home,
    );

    expect(
      () => _run((root: root, project: project)),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having((f) => f.file, 'file', _feature)
            .having(
              (f) => f.message,
              'message',
              allOf(
                startsWith('cannot write $_feature: the docs folder '),
                endsWith(
                  'lies outside the project; '
                  'run specstone trust at a terminal to allow it',
                ),
              ),
            )
            .having((f) => f.exitStatus, 'exitStatus', 73),
      ),
    );
    expect(
      File('${outside.path}/prds/features/f05_rendering/FEATURE.md')
          .readAsStringSync(),
      _featureOutOfOrder,
    );
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  group('a doc that turns into a link before its write', () {
    const leadsOutside = 'it leads outside the project';
    const underGit = 'it lies under .git';

    // The link replaces the doc once the run has read it and opens its
    // resolver, the last step before the first write.
    Future<({_Run run, _Calls calls, String linked})> swapped(
      String reason,
    ) async {
      final run = await _openNotes({
        _noteA: _noteDoc(_stale()),
        _noteB: _noteDoc(_stale()),
      });
      final elsewhere =
          reason == leadsOutside
                ? await writeTree({'b.md': 'elsewhere'})
                : Directory('${run.root.path}/docs/.git/x')
            ..createSync(recursive: true);
      final linked = '${elsewhere.path}/b.md';
      File(linked).writeAsStringSync('elsewhere');
      final calls = _Calls()
        ..onOpen = () {
          final doc = _file(run, _noteB)..deleteSync();
          Link(doc.path).createSync(linked);
        };
      return (run: run, calls: calls, linked: linked);
    }

    test('a doc linked outside the project or under .git is refused with '
        'output_not_writable, exit 73, and the message for each', () async {
      for (final reason in [leadsOutside, underGit]) {
        final (:run, :calls, :linked) = await swapped(reason);

        expect(
          () => _runNotes(run, _tocRun(calls)),
          throwsA(
            isA<RenderFault>()
                .having(
                  (f) => f.code,
                  'code',
                  RenderFaultCode.outputNotWritable,
                )
                .having((f) => f.file, 'file', _noteB)
                .having(
                  (f) => f.message,
                  'message',
                  'cannot write $_noteB: $reason',
                )
                .having((f) => f.exitStatus, 'exitStatus', 73),
          ),
          reason: reason,
        );
        expect(File(linked).readAsStringSync(), 'elsewhere', reason: reason);
        expect(_read(run, _noteA), _noteDoc(_fresh()), reason: reason);
      }
    });

    test('--check raises no fault for a doc linked outside the project or '
        'under .git and writes nothing', () async {
      for (final reason in [leadsOutside, underGit]) {
        final (:run, :calls, :linked) = await swapped(reason);

        final report = _runNotes(run, _tocRun(calls), check: true);

        expect(report.toText(), '$_noteA\n$_noteB\n', reason: reason);
        expect(File(linked).readAsStringSync(), 'elsewhere', reason: reason);
        expect(_read(run, _noteA), _noteDoc(_stale()), reason: reason);
      }
    });
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  group('generated blocks', () {
    // ignore: lines_longer_than_80_chars, one literal so check finds the test
    test('format rewrites a stale block and keeps every other byte, draft and confirmed included', () async {
      final cases = [
        (reason: 'draft', front: '---\ndraft: true\n---\n', block: _stale()),
        (
          reason: 'confirmed',
          front: '---\ndraft: false\n---\n',
          block: _stale(),
        ),
        (
          reason: 'approved',
          front: '---\napproved: true\n---\n',
          block: _stale(),
        ),
        (
          reason: 'approved hash',
          front: '---\napproved: "0123456789ab"\n---\n',
          block: _stale(),
        ),
        (reason: 'no front matter', front: '', block: _stale()),
        (
          reason: 'hand edit',
          front: '',
          block: '$_toc\nhand edit\nmore\n$_end',
        ),
      ];
      final run = await _openNotes({
        for (final (i, c) in cases.indexed)
          'docs/notes/c$i.md': _noteDoc(c.block, front: c.front),
      });

      final report = _runNotes(run, _tocRun(_Calls()));

      expect(
        report.files.map((f) => f.status),
        everyElement(FileStatus.formatted),
      );
      for (final (i, c) in cases.indexed) {
        expect(
          _read(run, 'docs/notes/c$i.md'),
          _noteDoc(_fresh(), front: c.front),
          reason: c.reason,
        );
      }
    });

    test('format --check lists a doc with a stale block, writes nothing, '
        'exits 1', () async {
      final run = await _openNotes({_noteA: _noteDoc(_stale())});

      final report = _runNotes(run, _tocRun(_Calls()), check: true);

      expect(report.toText(), '$_noteA\n');
      expect(report.exitStatus, 1);
      expect(_read(run, _noteA), _noteDoc(_stale()));
    });

    test('a block that cannot be resolved is not listed', () async {
      final run = await _openNotes({_noteA: _noteDoc(_stale())});

      final report = _runNotes(
        run,
        _tocRun(_Calls(), noBlocks: true),
        check: true,
      );

      expect(report.toText(), '');
      expect(report.exitStatus, 0);
      expect(_read(run, _noteA), _noteDoc(_stale()));
    });

    test('a doc outside the Target is not '
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

    test('an open block refuses the file and '
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

    test('an open marker whose line ends in spaces or a '
        'tab refuses the file and leaves it byte-equal', () async {
      final openDoc = '# A\n\n## Contents\n$_toc  \nbody\n\n## Steps\nx\n';
      final run = await _openNotes({_noteA: openDoc});

      final report = _runNotes(run, _tocRun(_Calls()));

      final refused = report.files.firstWhere((f) => f.path == _noteA);
      expect(refused.status, FileStatus.refused);
      expect(refused.openBlock, '$_toc  ');
      expect(refused.openBlockKind, 'note_toc');
      expect(report.exitStatus, 1);
      expect(_read(run, _noteA), openDoc);
    });

    test('a run with no doc type listing generators never '
        'calls open', () async {
      final run = await _openNotes({_feature: _featureOutOfOrder});
      final calls = _Calls();

      _runNotes(run, _tocRun(calls));

      expect(calls.opened, 0);
      expect(calls.closed, 0);
    });

    test('open runs once per run, before the first write, and '
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

    test('close still runs once when a write throws', () async {
      final run = await _openNotes({_noteA: _noteDoc(_stale())});
      final folder = _file(run, _noteA).parent;
      await Process.run('chmod', ['555', folder.path]);
      addTearDown(() => Process.run('chmod', ['755', folder.path]));
      final calls = _Calls();

      expect(() => _runNotes(run, _tocRun(calls)), throwsA(isA<RenderFault>()));

      expect(calls.opened, 1);
      expect(calls.closed, 1);
    }, skip: Platform.isWindows ? 'chmod does not apply on Windows' : false);

    test('a fault from open stops the run and writes no '
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

    test('sections out of order are reordered and each body '
        'is kept byte for byte outside its block', () async {
      final run = await _openNotes({
        _noteA: '# A\n\n## Steps\n\nx\n  y\n\n## Contents\n\nbody\n',
      });

      _runNotes(run, _tocRun(_Calls()));

      expect(
        _read(run, _noteA),
        '# A\n\n## Contents\n\n${_fresh()}\n\nbody\n\n## Steps\n\nx\n  y\n',
      );
    });

    test('a CRLF doc gets its block in CRLF, and a second run '
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

    test('Write each generated block '
        'statement: a missing section-top block lands one blank line under '
        'the header, and a second check reports unchanged', () async {
      final run = await _openNotes({
        _noteA: '# A\n\n## Contents\n\nbody\n\n## Steps\n\nx\n',
      });
      final generators = _tocRun(_Calls());

      final first = _runNotes(run, generators);

      expect(first.files.single.status, FileStatus.formatted);
      expect(
        _read(run, _noteA),
        '# A\n\n## Contents\n\n${_fresh()}\n\nbody\n\n## Steps\n\nx\n',
      );
      final again = _runNotes(run, generators, check: true);
      expect(again.files.single.status, FileStatus.unchanged);
    });
  });

  group('a features doc and its group docs', () {
    test('a features doc whose group doc is missing or lags reports its '
        'companions lagging, as the plan lists them', () async {
      // D5: the companion lag `check` reads is the plan `format --check` lists.
      final registry = _groupRun(['form', 'list']).registry;
      final lagging = await _openGroups({
        ..._freshGroups(['list']),
        _mapPath: _mapDoc('form,list'),
      });
      final current = await _openGroups(_freshGroups(['form', 'list']));

      expect(
        companionsStateOf(lagging.project, 'prds/FEATURES.md', registry, [
          'form',
          'list',
        ]),
        CompanionsState.lagging,
      );
      expect(
        companionsStateOf(current.project, 'prds/FEATURES.md', registry, [
          'form',
          'list',
        ]),
        CompanionsState.current,
      );
    });

    test('a missing group doc is created approved and reports '
        'created', () async {
      final run = await _openGroups({
        ..._freshGroups(['list']),
        _mapPath: _mapDoc('form,list'),
      });
      final home = await _home();

      final report = _runGroups(run, ['form', 'list'], home: home);

      expect(_statuses(report), {
        _mapPath: FileStatus.unchanged,
        _areaPath('form'): FileStatus.created,
        _areaPath('list'): FileStatus.unchanged,
      });
      final text = _read(run, _areaPath('form'));
      final fields = ApprovalFields.of(Doc.parse(toLf(text)));
      expect(text, contains(_areaDoc('form')));
      expect(fields.isDraft, isFalse);
      expect(
        fields.approvedValue,
        approvalHashOf(toLf(text), run.project.set.lookup('area_index')),
      );
      expect(report.toText(), '${_areaPath('form')}: created\n');
      expect(MoveJournal.pending(run.root), isFalse);
    });

    test('a stale group doc is rewritten and reports formatted', () async {
      final run = await _openGroups({
        ..._freshGroups(['form', 'list']),
        _areaPath('form'): _areaDoc('form', rows: 'old'),
      });
      final home = await _home();

      final report = _runGroups(run, ['form', 'list'], home: home);

      expect(_statuses(report), {
        _mapPath: FileStatus.unchanged,
        _areaPath('form'): FileStatus.formatted,
        _areaPath('list'): FileStatus.unchanged,
      });
      expect(_read(run, _areaPath('form')), _areaDoc('form'));
      expect(report.toText(), '${_areaPath('form')}: formatted\n');
    });

    test('a group doc whose folder the list leaves out is deleted and '
        'reports deleted', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _areaPath('old'): _areaDoc('old'),
      });
      final home = await _home();

      final report = _runGroups(run, ['form'], home: home);

      expect(_statuses(report), {
        _mapPath: FileStatus.unchanged,
        _areaPath('form'): FileStatus.unchanged,
        _areaPath('old'): FileStatus.deleted,
      });
      expect(_exists(run, _areaPath('old')), isFalse);
      expect(_read(run, _areaPath('form')), _areaDoc('form'));
      expect(report.toText(), '${_areaPath('old')}: deleted\n');
      expect(MoveJournal.pending(run.root), isFalse);
    });

    test('a run on the features doc alone deletes a group doc outside '
        'its target that the list leaves out', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _areaPath('old'): _areaDoc('old'),
      });
      final home = await _home();

      final report = _runGroups(run, ['form'], home: home, target: _mapPath);

      expect(_statuses(report)[_areaPath('old')], FileStatus.deleted);
      expect(_exists(run, _areaPath('old')), isFalse);
      expect(_exists(run, _areaPath('form')), isTrue);
    });

    test('a group that changes only the features doc writes it with no '
        'home folder', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _mapPath: _mapDoc('old'),
      });

      final report = _runGroups(run, ['form']);

      expect(_statuses(report), {
        _mapPath: FileStatus.formatted,
        _areaPath('form'): FileStatus.unchanged,
      });
      expect(_read(run, _mapPath), _mapDoc('form'));
    });

    test('an unclosed area_catalog marker in one group doc refuses it, '
        'and no file under the docs root changes', () async {
      final unclosed = '# form\n\n## Features\n\n$_areaMarker\nno end\n';
      final docs = {
        _mapPath: _mapDoc('stale'),
        _areaPath('form'): unclosed,
        _areaPath('list'): _areaDoc('list', rows: 'old'),
        _areaPath('gone'): _areaDoc('gone'),
      };
      final run = await _openGroups(docs);
      final home = await _home();

      final report = _runGroups(run, ['form', 'list', 'third'], home: home);

      for (final MapEntry(:key, :value) in docs.entries) {
        expect(_read(run, key), value, reason: key);
      }
      expect(_exists(run, _areaPath('third')), isFalse);
      expect(_statuses(report), {
        _mapPath: FileStatus.unchanged,
        _areaPath('form'): FileStatus.refused,
        _areaPath('list'): FileStatus.unchanged,
      });
      expect(
        report.toText(),
        '${_areaPath('form')}: refused: open generated block area_catalog\n',
      );
      expect(report.exitStatus, 1);
    });

    test('a run on a folder holding a group doc but not the features doc '
        'writes that doc alone', () async {
      final run = await _openGroups({
        ..._freshGroups(['form', 'list']),
        _areaPath('form'): _areaDoc('form', rows: 'old'),
        _areaPath('old'): _areaDoc('old'),
      });

      final report = _runGroups(run, [
        'form',
        'list',
        'third',
      ], target: 'docs/prds/features/form');

      expect(_statuses(report), {_areaPath('form'): FileStatus.formatted});
      expect(_read(run, _areaPath('form')), _areaDoc('form'));
      expect(_exists(run, _areaPath('third')), isFalse);
      expect(_exists(run, _areaPath('old')), isTrue);
    });

    test('a group doc keeps its CRLF and byte order mark when the group '
        'writes through the journal', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _areaPath('old'): _areaDoc('old'),
      });
      _file(run, _areaPath('form')).writeAsBytesSync([
        ..._bom,
        ...utf8.encode(_areaDoc('form', rows: 'old').replaceAll('\n', '\r\n')),
      ]);
      final home = await _home();

      _runGroups(run, ['form'], home: home);

      expect(_file(run, _areaPath('form')).readAsBytesSync(), [
        ..._bom,
        ...utf8.encode(_areaDoc('form').replaceAll('\n', '\r\n')),
      ]);
      expect(_exists(run, _areaPath('old')), isFalse);
    });

    test('a group that creates a doc with no home folder is refused and '
        'writes nothing', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _mapPath: _mapDoc('old'),
      });

      expect(
        () => _runGroups(run, ['form', 'list']),
        throwsA(
          isA<RenderFault>().having(
            (fault) => fault.code,
            'code',
            RenderFaultCode.outputNotWritable,
          ),
        ),
      );

      expect(_read(run, _mapPath), _mapDoc('old'));
      expect(_exists(run, _areaPath('list')), isFalse);
    });

    test('a set with no group folder and no group doc reports as before '
        'the companion write', () async {
      final run = await _openGroups({
        _mapPath: '# Features\n\n## Features\n\n$_rowsMarker\nold\n$_end\n',
      });

      final report = _runGroups(run, []);

      expect(_statuses(report), {_mapPath: FileStatus.formatted});
      expect(report.toText(), '$_mapPath: formatted\n');
      expect(_read(run, _mapPath), _mapDoc(''));
    });

    // ignore: lines_longer_than_80_chars, one literal so check finds the test
    test('check lists the features doc when a group folder lacks its doc and when a group doc is stale, and writes nothing', () async {
      final cases = [
        (
          docs: {
            ..._freshGroups(['list']),
            _mapPath: _mapDoc('form,list'),
          },
          text: '$_mapPath\n',
        ),
        (
          docs: {
            ..._freshGroups(['form', 'list']),
            _areaPath('form'): _areaDoc('form', rows: 'old'),
          },
          text: '$_mapPath\n${_areaPath('form')}\n',
        ),
      ];

      for (final (:docs, :text) in cases) {
        final run = await _openGroups(docs);

        final report = _runGroups(run, ['form', 'list'], check: true);

        expect(report.toText(), text);
        expect(report.exitStatus, 1);
        for (final MapEntry(:key, :value) in docs.entries) {
          expect(_read(run, key), value, reason: key);
        }
        expect(
          _exists(run, _areaPath('form')),
          docs.containsKey(_areaPath('form')),
        );
      }
    });

    test('check on a group doc whose folder the list leaves out lists the '
        'features doc and that doc, and keeps the doc', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _areaPath('old'): _areaDoc('old'),
      });

      final report = _runGroups(run, ['form'], check: true);

      expect(_statuses(report)[_areaPath('old')], FileStatus.deleted);
      expect(report.toText(), '$_mapPath\n${_areaPath('old')}\n');
      expect(report.exitStatus, 1);
      expect(_read(run, _areaPath('old')), _areaDoc('old'));
    });

    test('a pending journal refuses the group write, and its trash and '
        'parked docs stay', () async {
      final docs = {
        ..._freshGroups(['form']),
        _mapPath: _mapDoc('old'),
      };
      final run = await _openGroups(docs);
      final parked = _file(run, '.specstone/trash/stage/parked.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('parked');
      final home = await _home();

      expect(
        () => _runGroups(run, ['form', 'list'], home: home),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.file, 'file', MoveJournal.journalPath),
        ),
      );

      expect(parked.readAsStringSync(), 'parked');
      expect(_read(run, _mapPath), _mapDoc('old'));
      expect(_exists(run, _areaPath('list')), isFalse);
    });

    test('a listed path holding a doc that is not UTF-8 refuses the group, '
        'and nothing is written', () async {
      final docs = {
        ..._freshGroups(['form', 'list']),
        _mapPath: _mapDoc('old'),
      };
      final run = await _openGroups(docs);
      final bytes = [0xFF, 0xFE, 0xFA];
      _file(run, _areaPath('list')).writeAsBytesSync(bytes);
      final home = await _home();

      final report = _runGroups(run, ['form', 'list'], home: home);

      expect(_read(run, _mapPath), _mapDoc('old'));
      expect(_file(run, _areaPath('list')).readAsBytesSync(), bytes);
      expect(_statuses(report), {
        _mapPath: FileStatus.unchanged,
        _areaPath('form'): FileStatus.unchanged,
        _areaPath('list'): FileStatus.refused,
      });
      expect(
        report.toText(),
        '${_areaPath('list')}: refused: cannot be read as a doc\n',
      );
      expect(report.exitStatus, 1);
      expect(MoveJournal.pending(run.root), isFalse);
    });

    test('a doc the list leaves out that is not UTF-8 is reported skipped '
        'with a warning, and kept', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _areaPath('old'): '',
      });
      final bytes = [0xFF, 0xFE, 0xFA];
      _file(run, _areaPath('old')).writeAsBytesSync(bytes);
      final home = await _home();

      final report = _runGroups(run, ['form'], home: home, target: _mapPath);

      expect(_statuses(report)[_areaPath('old')], FileStatus.skipped);
      expect(report.warnings, ['${_areaPath('old')}: not UTF-8 text; skipped']);
      expect(_file(run, _areaPath('old')).readAsBytesSync(), bytes);
    });

    test('a delete prunes the folder it empties', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _areaPath('old'): _areaDoc('old'),
      });
      final home = await _home();

      _runGroups(run, ['form'], home: home);

      expect(
        Directory('${run.root.path}/docs/prds/features/old').existsSync(),
        isFalse,
      );
      expect(
        Directory('${run.root.path}/docs/prds/features/form').existsSync(),
        isTrue,
      );
    });

    test('a journaled write runs inside the lock the opener gives, and a '
        'single-file write takes none', () async {
      final events = <String>[];
      void lock(void Function() write) {
        events.add('lock');
        write();
        events.add('unlock');
      }

      final grouped = await _openGroups({
        ..._freshGroups(['form']),
        _areaPath('old'): _areaDoc('old'),
      });
      _runGroups(grouped, ['form'], home: await _home(), lockWrites: lock);
      expect(events, ['lock', 'unlock']);
      expect(_exists(grouped, _areaPath('old')), isFalse);

      events.clear();
      final single = await _openGroups({
        ..._freshGroups(['form']),
        _mapPath: _mapDoc('old'),
      });
      _runGroups(single, ['form'], lockWrites: lock);
      expect(events, isEmpty);
    });

    test('a doc that changed after the run read it refuses the journaled '
        'write, and nothing is written', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _areaPath('form'): _areaDoc('form', rows: 'old'),
        _areaPath('old'): _areaDoc('old'),
      });
      final edited = _areaDoc('form', rows: 'edited meanwhile');
      void lock(void Function() write) {
        _file(run, _areaPath('form')).writeAsStringSync(edited);
        write();
      }

      expect(
        () => _runGroups(run, ['form'], home: null, lockWrites: lock),
        throwsA(isA<RenderFault>()),
      );
      final home = await _home();
      expect(
        () => _runGroups(run, ['form'], home: home, lockWrites: lock),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.file, 'file', _areaPath('form')),
        ),
      );

      expect(_read(run, _areaPath('form')), edited);
      expect(_exists(run, _areaPath('old')), isTrue);
      expect(MoveJournal.pending(run.root), isFalse);
    });

    test('a read-only group doc refuses the journaled write before any '
        'change', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _areaPath('form'): _areaDoc('form', rows: 'old'),
        _areaPath('old'): _areaDoc('old'),
      });
      final form = _file(run, _areaPath('form'));
      await Process.run('chmod', ['444', form.path]);
      addTearDown(() => Process.run('chmod', ['644', form.path]));
      final home = await _home();

      expect(
        () => _runGroups(run, ['form'], home: home),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.message, 'message', 'the doc is read-only'),
        ),
      );

      expect(_read(run, _areaPath('form')), _areaDoc('form', rows: 'old'));
      expect(_exists(run, _areaPath('old')), isTrue);
      expect(MoveJournal.pending(run.root), isFalse);
    }, skip: Platform.isWindows ? 'chmod does not apply on Windows' : false);

    test('planFormatWrites plans from a registry and a resolver and writes '
        'no file', () async {
      final run = await _openGroups({
        ..._freshGroups(['form']),
        _mapPath: _mapDoc('old'),
        _areaPath('old'): _areaDoc('old'),
      });
      final target = run.project.resolveTarget(
        null,
        workingDirectory: run.root,
        defaultsToDocsRoot: true,
      );
      final reads = [
        for (final entry in collectDocEntries(target, run.project.matcher))
          readDoc(run.project, entry),
      ];

      final plan = planFormatWrites<List<String>>(
        run.project,
        reads,
        _groupRun(['form', 'list']).registry,
        ['form', 'list'],
      );

      expect(plan.rewrites.keys, [_mapPath]);
      expect(plan.creates.keys, [_areaPath('list')]);
      expect(plan.deletes, [_areaPath('old')]);
      expect(_read(run, _mapPath), _mapDoc('old'));
      expect(_exists(run, _areaPath('list')), isFalse);
      expect(_exists(run, _areaPath('old')), isTrue);
    });

    test('a companion listed outside the docs root or at a path no doc type '
        'matches refuses the group, and nothing is written', () async {
      final cases = [
        (slug: '../../../outside', stray: 'outside/AREA.md'),
        (slug: 'x/y', stray: 'docs/prds/features/x/y/AREA.md'),
      ];

      for (final (:slug, :stray) in cases) {
        final docs = {
          ..._freshGroups(['form']),
          _mapPath: _mapDoc('old'),
          _areaPath('old'): _areaDoc('old'),
        };
        final run = await _openGroups(docs);
        final home = await _home();

        final report = _runGroups(run, ['form', slug], home: home);

        for (final MapEntry(:key, :value) in docs.entries) {
          expect(_read(run, key), value, reason: '$slug $key');
        }
        expect(_exists(run, stray), isFalse, reason: slug);
        expect(MoveJournal.pending(run.root), isFalse, reason: slug);
        expect(report.exitStatus, 1, reason: slug);
        expect(
          report.toText(),
          'docs/prds/features/$slug/AREA.md: refused: '
          'not a path of its doc type under the docs root\n',
          reason: slug,
        );
      }
    });

    test('toText and toJson print created and deleted', () {
      const report = FormatReport(
        check: false,
        files: [
          FileResult(path: 'docs/a/AREA.md', status: FileStatus.created),
          FileResult(path: 'docs/b/AREA.md', status: FileStatus.deleted),
        ],
        warnings: [],
      );

      expect(
        report.toText(),
        'docs/a/AREA.md: created\ndocs/b/AREA.md: deleted\n',
      );
      expect(report.toJson()['files'], [
        {'path': 'a/AREA.md', 'status': 'created'},
        {'path': 'b/AREA.md', 'status': 'deleted'},
      ]);
      expect(report.exitStatus, 0);
    });
  });

  group('a group features doc of the shipped prd-core type', () {
    test('an approved group features doc keeps its approval when format '
        'rewrites its catalog', () async {
      const mapDoc = 'prds/FEATURES.md';
      const groupDoc = 'prds/features/kitchen/FEATURES.md';
      String block(String kind) => '${generatedOpenMarker(kind)}\nold\n$_end\n';
      final root = await writeTree(
        withApprovalHashes({
          '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
          '.specstone/templates/feature.yaml':
              'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
          'docs/prds/features/kitchen/f01_recipes/FEATURE.md':
              '# Recipes\n\n## Problem\n\nNeed it.\n',
          'docs/$mapDoc':
              '# Feature map\n\n## Features\n\n'
              '${block(featureCatalogKind)}\n'
              '## System interaction diagram\n\nOne system.\n\n'
              '## Systems\n\n- Login\n',
          'docs/$groupDoc':
              '# kitchen features\n\n## Features\n\n'
              '${block(groupFeatureCatalogKind)}',
        }),
      );
      final home = await writeTree({});
      final session = openSession(root);
      addTearDown(session.close);
      final project = DocsProject.open(
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: home,
      );

      final report = runFormat<DocIndex>(
        project,
        project.resolveTarget(
          null,
          workingDirectory: root,
          defaultsToDocsRoot: true,
        ),
        check: false,
        homeDirectory: home,
        generators: GeneratorRun<DocIndex>(
          registry: GeneratorRegistry<DocIndex>(
            {
              featureCatalogKind: featureCatalogBlocks,
              groupFeatureCatalogKind: groupFeatureCatalogBlocks,
            },
            companions: {featureCatalogKind: featureCatalogCompanions},
          ),
          open: () => OpenedResolver(
            resolver: session.index,
            close: () {},
            lockWrites: (write) => write(),
          ),
        ),
      );

      expect(_statuses(report), {
        'docs/$mapDoc': FileStatus.formatted,
        'docs/$groupDoc': FileStatus.formatted,
        'docs/prds/features/kitchen/f01_recipes/FEATURE.md':
            FileStatus.unchanged,
      });
      expect(
        File('${root.path}/docs/$groupDoc').readAsStringSync(),
        contains(
          '1 features · 0 stories · 1 planned\n\n'
          '| Feature | What it does | Status | Stories | Serves |\n'
          '|---|---|---|---|---|\n'
          '| [Recipes](f01_recipes/FEATURE.md) | — | planned | 0/0 | — |\n',
        ),
      );
      final checked = await checkOf(root);
      expect([
        for (final f in checked.findings)
          if (f.kind == FindingKind.approvalStale) f.path,
      ], isEmpty);
    });
  });
}
