@Tags(['timing'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../specstone_core/test/helpers/shipped_pins.dart';
import 'helpers/baseline_tree.dart';
import 'helpers/best_of.dart';
import 'helpers/built_cli.dart';

const _approveDocCount = 2000;
const _approveDraftCount = 20;
const _sentencesPerDoc = 55;
const _droppedPerDraft = 10;
const _added = 'Added one. Added two. Added three. Added four. Added five.';
const _filler = 'the amber birch cedar delta ember fjord grove haven iris';
const _commit = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678';

/// Returns a doc body of the first [keep] of [_sentencesPerDoc] sentences, 5 KB
/// in all.
///
/// Sentence `n` is unique to doc [doc] and holds an em dash, so the held text
/// is UTF-16 as a real project's is.
String _sentencesOfDoc(int doc, {required int keep}) => [
  for (var n = 0; n < keep; n++)
    'Doc $doc says item $n is held in this project \u2014 $_filler.',
].join(' ');

String _feature(int k, String status, String body) =>
    '---\n$status\n---\n\n# Feature $k\n\n## Problem\n\n$body\n';

String _featurePath(int k) =>
    'docs/prds/features/f${(k + 1).toString().padLeft(2, '0')}_x/FEATURE.md';

/// Writes a project of [_approveDocCount] docs of about 5 KB.
///
/// [_approveDraftCount] of them are features that are drafts now, with
/// [_droppedPerDraft] sentences dropped and five added since the approved
/// copy; the others are notes.
Directory _writeApproveProject() {
  final root = Directory.systemTemp.createTempSync('specstone_approve_');
  addTearDown(() => root.deleteSync(recursive: true));
  void write(String path, String text) => File('${root.path}/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
  write('.specstone/config.yaml', shippedPinsConfig());
  for (var k = 0; k < _approveDraftCount; k++) {
    final kept = _sentencesOfDoc(k, keep: _sentencesPerDoc - _droppedPerDraft);
    write(_featurePath(k), _feature(k, 'draft: true', '$kept $_added'));
  }
  for (var k = _approveDraftCount; k < _approveDocCount; k++) {
    write(
      'docs/notes/n_$k.md',
      '# Note $k\n\n${_sentencesOfDoc(k, keep: _sentencesPerDoc)}\n',
    );
  }
  return root;
}

/// A git that holds one approved commit of each feature of the project.
///
/// The run is timed without a git process, since git's own time is not what
/// the approve view's sentence lookup costs.
ProcessResult _approvedHistory(
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String>? environment,
}) {
  ProcessResult answer(String stdout) => ProcessResult(0, 0, stdout, '');
  switch (arguments.first) {
    case 'rev-parse':
      return answer('\n');
    case 'log':
      return answer('$_commit\x00\n${arguments.last}\x00');
    default: // show <commit>:<path>
      final path = arguments.last.substring(_commit.length + 1);
      final k = int.parse(RegExp(r'f(\d+)_x').firstMatch(path)![1]!) - 1;
      return answer(
        _feature(
          k,
          'approved: true',
          _sentencesOfDoc(k, keep: _sentencesPerDoc),
        ),
      );
  }
}

void main() {
  late Directory project;
  late String exe;

  setUpAll(() async {
    project = await writeBaselineTree();
    exe = await buildSpecstone();
  });

  Duration timed(List<String> args, {Set<int> exitCodes = const {0}}) {
    final watch = Stopwatch()..start();
    final run = Process.runSync(exe, args, workingDirectory: project.path);
    watch.stop();
    expect(exitCodes, contains(run.exitCode), reason: '${run.stderr}');
    return watch.elapsed;
  }

  test('F1-D26, F1-D35: the generated tree matches the baseline figures', () {
    final files = Directory('${project.path}/docs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    expect(files, hasLength(1826));
    expect(files.fold<int>(0, (sum, f) => sum + f.lengthSync()), 19056244);
  });

  test('NFR-P02, f01/us01/fr02/e01: the fastest of five specstone calls from '
      'no index builds the full index within 10 s', () {
    expect(
      bestOf(timingRuns, () {
        for (final suffix in ['', '-wal', '-shm']) {
          final sibling = File(
            '${project.path}/.specstone/index.sqlite$suffix',
          );
          if (sibling.existsSync()) sibling.deleteSync();
        }
        expect(
          File('${project.path}/.specstone/index.sqlite').existsSync(),
          isFalse,
        );
        return timed(['structure', '--json']);
      }, label: 'full index runs'),
      lessThanOrEqualTo(const Duration(seconds: 10)),
    );
  });

  test('NFR-P01: specstone context for a story, with a current index, answers '
      'within 500 ms in the fastest of five calls', () {
    const call = ['context', 'feature_1/story_1', '--for', 'implement'];
    timed(call); // warm-up: the index is current after it
    expect(
      bestOf(timingRuns, () => timed(call), label: 'context calls'),
      lessThanOrEqualTo(const Duration(milliseconds: 500)),
    );
    final watch = Stopwatch()..start();
    final session = ReadSession.open(
      templates: TemplateResolver(),
      workingDirectory: project,
      homeDirectory: null,
    );
    answerContext(
      session.index,
      pickBundle(
        session.index,
        'feature_1/story_1',
        BundleMode.implement,
        noProject: false,
      ),
      label: 'feature_1/story_1',
      byCode: false,
    );
    session.close();
    // ignore: avoid_print, the gate reports the in-process call so a slow run shows where the time went.
    print(
      'diagnostic: in-process context call ${watch.elapsedMilliseconds} ms',
    );
  });

  test('NFR-P03, f04/us01/fr01/e01: a whole-project specstone check, with a '
      'current index, finishes within 2 s in the fastest of five calls', () {
    const call = ['check'];
    final code = Directory('${project.path}/src')
        .listSync(recursive: true)
        .whereType<File>();
    expect(
      code,
      hasLength(1042),
    ); // one file per FR, 52 x 5 x 4, and one per topic
    final records = Directory('${project.path}/docs/specs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('IMPLEMENTATION.md'))
        .toList();
    expect(records, hasLength(52)); // one record per feature
    final entry = RegExp(r"^  - '[^']+:implemented'$", multiLine: true);
    final path = RegExp(
      r"^  - '[^']+:src/feature_\d+/story_\d/req_\d\.dart:Req\d'$",
      multiLine: true,
    );
    for (final record in records) {
      final text = record.readAsStringSync();
      expect(entry.allMatches(text), hasLength(20), reason: record.path);
      expect(path.allMatches(text), hasLength(20), reason: record.path);
    }
    final first = Process.runSync(
      exe,
      call,
      workingDirectory: project.path,
    ); // warm-up: the index is current after it
    expect(first.exitCode, anyOf(0, 1), reason: '${first.stderr}');
    final out = first.stdout.toString();
    for (final kind in const [
      'implements_path_unresolved',
      'implements_symbol_unresolved',
      'implements_missing',
      'record_entry_unresolved',
      'record_entry_duplicate',
      'code_uncovered',
    ]) {
      expect(out, isNot(contains(kind)), reason: kind);
    }
    expect(
      bestOf(
        timingRuns,
        () => timed(call, exitCodes: {0, 1}),
        label: 'check calls',
      ),
      lessThanOrEqualTo(const Duration(seconds: 2)),
    );
  });

  test('a whole-project specstone check that reads 1,000 more code files '
      'full of comment lines still finishes within 2 s', () {
    const fileCount = 1000;
    const commentLines = 60;
    final folder = Directory('${project.path}/src/feature_1/comments')
      ..createSync(recursive: true);
    addTearDown(() => folder.deleteSync(recursive: true));
    final body = [
      for (var line = 0; line < commentLines; line++) ...[
        '/// Line $line parses `user_id` and `a/b` per README.md and x.md.',
        '// See `login` and `f<nn>/us<nn>` in notes.md#top, then docs/none.md.',
        'final value$line = $line; // not a comment line, `feature_1/story_1`',
      ],
    ].join('\n');
    for (var n = 0; n < fileCount; n++) {
      File('${folder.path}/c_$n.dart').writeAsStringSync('$body\n');
    }
    File('${folder.path}/cited.dart')
        .writeAsStringSync('// Implements `feature_1/story_1`.\n');
    const call = ['check'];
    final first = Process.runSync(exe, call, workingDirectory: project.path);
    expect(first.exitCode, 1, reason: '${first.stderr}');
    expect(
      first.stdout.toString(),
      allOf(
        contains(
          'src/feature_1/comments/cited.dart:1: doc_cited_in_code: '
          'feature_1/story_1 names a doc',
        ),
        isNot(contains('comments/c_')),
      ),
    );
    expect(
      bestOf(
        timingRuns,
        () => timed(call, exitCodes: {0, 1}),
        label: 'check calls over comment-rich code',
      ),
      lessThanOrEqualTo(const Duration(seconds: 2)),
    );
  });

  test('NFR-P03: a broken code path in a record shows in the check, so the '
      'timed runs read the records', () {
    final record = File(
      '${project.path}/docs/specs/f01_feature_1/IMPLEMENTATION.md',
    );
    final original = record.readAsStringSync();
    addTearDown(() => record.writeAsStringSync(original));
    record.writeAsStringSync(
      original.replaceFirst(
        'src/feature_1/story_1/req_1.dart:Req1',
        'src/feature_1/story_1/gone.dart:Req1',
      ),
    );
    final run = Process.runSync(exe, ['check'], workingDirectory: project.path);
    expect(
      run.stdout.toString(),
      matches(
        RegExp(
          r'specs/f01_feature_1/IMPLEMENTATION\.md:\d+: '
          'implements_path_unresolved',
        ),
      ),
    );
  });

  test('approve --dry-run builds the views of 20 drafts of 55 sentences over '
      '2,000 docs of 5 KB within 2 s in the fastest of five runs', () {
    final root = _writeApproveProject();
    Duration build() {
      final watch = Stopwatch()..start();
      final answer = WriteSession.run(
        (session) => approveDryRun(
          session,
          history: ApprovalHistory(runGit: _approvedHistory),
        ),
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: null,
      );
      watch.stop();
      expect(answer.json['count'], _approveDraftCount);
      expect(answer.text, contains('$_droppedPerDraft sentences dropped'));
      return watch.elapsed;
    }

    build(); // warm-up: the index is current after it
    expect(
      bestOf(timingRuns, build, label: 'approve view runs'),
      lessThanOrEqualTo(const Duration(seconds: 2)),
    );
  });
}
