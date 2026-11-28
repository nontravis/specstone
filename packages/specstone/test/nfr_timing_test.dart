@Tags(['timing'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../specstone_core/test/helpers/no_generators.dart';
import '../../specstone_core/test/helpers/shipped_pins.dart';
import '../../specstone_core/test/helpers/write_fixture.dart' show testHome;
import 'helpers/baseline_tree.dart';
import 'helpers/baseline_work_tree.dart';
import 'helpers/best_of.dart';
import 'helpers/built_cli.dart';
import 'helpers/children_cpu_time.dart';
import 'helpers/reference_time.dart';
import 'helpers/timing_metric.dart';

/// The files a busy project's `.specstone/bundles/` held when measured.
const _savedBundleCount = 1221;
const _approveDocCount = 2000;
const _approveDraftCount = 20;
const _sentencesPerDoc = 55;
const _droppedPerDraft = 10;
const _added = 'Added one. Added two. Added three. Added four. Added five.';
const _filler = 'the amber birch cedar delta ember fjord grove haven iris';
const _commit = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678';
const _busyLoop = r'i=0; while [ $i -lt 100000 ]; do i=$((i+1)); done';

/// Clock granularity: one shell thread cannot spend more CPU than wall.
const _tick = Duration(milliseconds: 20);

/// The timed full reindexes the reindex gate takes the fastest of.
const _reindexRuns = 3;
// A fixed amount of work (301M steps, over 200 ms CPU), never a wall span.
const _selfCpuLoopCount = 301000000;
const _residueModulus = 7;
const _residueCycleSum = 21;

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
  late ReferenceScale scale;
  late BaselineWorkTree baselineWork;

  setUpAll(() async {
    project = await writeBaselineTree();
    baselineWork = await BaselineWorkTree.build();
    exe = await buildSpecstone();
    scale = ReferenceScale.measure();
  });

  Duration timed(List<String> args, {Set<int> exitCodes = const {0}}) {
    final run = measureChild(
      () => runSpecstoneSync(exe, args, workingDirectory: project.path),
    );
    expect(
      exitCodes,
      contains(run.result.exitCode),
      reason: '${run.result.stderr}',
    );
    return run.elapsed;
  }

  test('the generated tree matches the baseline figures', () {
    final files = [
      for (final folder in ['docs', '.specstone/records'])
        ...Directory('${project.path}/$folder')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.md')),
    ];
    expect(files, hasLength(1826));
    expect(files.fold<int>(0, (sum, f) => sum + f.lengthSync()), 19056244);
  });

  test('the fastest of three specstone calls from '
      'no index builds the full index within 10 s', () {
    expectWithinBound(
      bestOf(
        _reindexRuns,
        () {
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
        },
        label: 'full index runs',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(seconds: 10),
    );
  });

  test('specstone context for a story, with a current index, answers '
      'within 500 ms in the fastest of five calls', () {
    const call = ['context', 'feature_1/story_1', '--for', 'implement'];
    timed(call); // warm-up: the index is current after it
    expectWithinBound(
      bestOf(
        timingRuns,
        () => timed(call),
        label: 'context calls',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(milliseconds: 500),
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
        ['feature_1/story_1'],
        BundleMode.implement,
        noProject: false,
      ),
      targets: ['feature_1/story_1'],
    );
    session.close();
    // ignore: avoid_print, the gate reports the in-process call so a slow run shows where the time went.
    print(
      'diagnostic: in-process context call ${watch.elapsedMilliseconds} ms',
    );
  });

  test('specstone context --out, over a bundles folder of $_savedBundleCount '
      'small files, answers within 500 ms in the fastest of five calls', () {
    const call = [
      'context',
      'feature_1/story_1',
      '--for',
      'implement',
      '--out',
    ];
    final bundles = Directory('${project.path}/.specstone/bundles')
      ..createSync(recursive: true);
    addTearDown(() => bundles.deleteSync(recursive: true));
    for (var n = 0; n < _savedBundleCount; n++) {
      File('${bundles.path}/saved_$n.txt').writeAsStringSync('saved\n');
    }
    timed(call); // warm-up: the index is current after it
    final best = bestOf(
      timingRuns,
      () => timed(call),
      label: 'prune calls',
      metric: timingMetric,
      scale: scale,
    );
    expectWithinBound(best, const Duration(milliseconds: 500));
    // ignore: avoid_print, the gate reports the figure so a slow run shows by how much.
    print(
      'diagnostic: context --out over $_savedBundleCount files '
      'reference-runner ${timingMetric.name} $best',
    );
  });

  test('specstone context for a story, ending with the stale-project '
      'line over every skill, agent, and settings file, answers within 500 ms '
      'in the fastest of five calls', () {
    const call = ['context', 'feature_1/story_1', '--for', 'implement'];
    final home = {'HOME': testHome().path, 'USERPROFILE': testHome().path};
    final init = Directory.systemTemp.createTempSync('specstone_skills_');
    addTearDown(() => init.deleteSync(recursive: true));
    final made = runSpecstoneSync(
      exe,
      ['init'],
      workingDirectory: init.path,
      environment: home,
    );
    expect(made.exitCode, 0, reason: '${made.stdout}\n${made.stderr}');
    final copied = <File>[];
    for (final folder in ['.claude', '.agents', '.codex', '.cursor']) {
      for (final file in Directory(
        '${init.path}/$folder',
      ).listSync(recursive: true).whereType<File>()) {
        final target = File(
          '${project.path}${file.path.substring(init.path.length)}',
        );
        copied.add(
          target
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(file.readAsBytesSync()),
        );
      }
    }
    addTearDown(() {
      for (final file in copied) {
        if (file.existsSync()) file.deleteSync();
      }
    });
    final current = runSpecstoneSync(
      exe,
      call,
      workingDirectory: project.path,
      environment: home,
    ); // warm-up: the index is current after it
    expect(current.exitCode, 0, reason: '${current.stderr}');
    expect(current.stderr.toString(), isNot(contains('specstone migrate')));
    copied
        .firstWhere((file) => file.path.endsWith('.toml'))
        .writeAsStringSync('hand edit\n');
    final stale = runSpecstoneSync(
      exe,
      call,
      workingDirectory: project.path,
      environment: home,
    );
    expect(stale.stderr.toString(), contains('run specstone migrate'));
    expectWithinBound(
      bestOf(
        timingRuns,
        () => timed(call),
        label: 'stale-line context calls',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(milliseconds: 500),
    );
  });

  test('specstone context --for design, with its '
      'cited-by lines, answers within 1 s in the fastest of five calls', () {
    const call = ['context', 'feature_1/story_1', '--for', 'design'];
    final first = runSpecstoneSync(
      exe,
      call,
      workingDirectory: project.path,
    ); // warm-up: the index is current after it
    expect(first.exitCode, 0, reason: '${first.stderr}');
    expect(first.stdout.toString(), contains('  · cited by '));
    expect(
      '  · cited by feature_1/story_2/req_1 (fr) '.allMatches(
        first.stdout.toString(),
      ),
      hasLength(denseCiteCount),
      reason: 'the bundle prints a cited-by line for each picked item cited',
    );
    expectWithinBound(
      bestOf(
        timingRuns,
        () => timed(call),
        label: 'design context calls',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(seconds: 1),
    );
  });

  test('a whole-project specstone check, with a '
      'current index, finishes within 2 s in the fastest of five calls', () {
    const call = ['check'];
    final code = Directory('${project.path}/src')
        .listSync(recursive: true)
        .whereType<File>();
    expect(
      code,
      hasLength(1042),
    ); // one file per FR, 52 x 5 x 4, and one per topic
    final records = Directory('${project.path}/.specstone/records')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('IMPLEMENTATION.md'))
        .toList();
    expect(records, hasLength(52)); // one record per feature
    final architectures = Directory('${project.path}/docs/specs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('ARCHITECTURE.md'))
        .toList();
    expect(architectures, hasLength(52)); // one architecture doc per feature
    for (final doc in architectures) {
      expect(doc.readAsStringSync(), contains('```mermaid'), reason: doc.path);
    }
    final entry = RegExp(r"^  - '[^']+:implemented'$", multiLine: true);
    final path = RegExp(
      r"^  - '[^']+:src/feature_\d+/story_\d/req_\d\.dart:Req\d [0-9a-f]{12}'$",
      multiLine: true,
    );
    for (final record in records) {
      final text = record.readAsStringSync();
      expect(entry.allMatches(text), hasLength(20), reason: record.path);
      expect(path.allMatches(text), hasLength(20), reason: record.path);
    }
    final first = runSpecstoneSync(
      exe,
      call,
      workingDirectory: project.path,
    ); // warm-up: the index is current after it
    expect(first.exitCode, anyOf(0, 1), reason: '${first.stderr}');
    expect(first.stderr.toString(), isNot(contains('Mermaid parse')));
    final out = first.stdout.toString();
    for (final kind in const [
      'diagram_parse_failed',
      'implements_path_unresolved',
      'implements_symbol_unresolved',
      'implements_missing',
      'record_entry_unresolved',
      'record_entry_duplicate',
      'code_suspect',
      'code_unconfirmed',
    ]) {
      expect(out, isNot(contains(kind)), reason: kind);
    }
    expectWithinBound(
      bestOf(
        timingRuns,
        () => timed(call, exitCodes: {0, 1}),
        label: 'check calls',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(seconds: 2),
    );
  });

  // D17: each write command, its generated block refresh included, answers
  // within the bound `check` keeps.
  test('set, new, move, rename, approve, delete, and reorder on the baseline '
      'tree each finish within 2 s in the fastest of five calls', () {
    final root = baselineWork.reset();
    final home = {'HOME': testHome().path, 'USERPROFILE': testHome().path};
    ProcessResult run(List<String> args) => runSpecstoneSync(
      exe,
      args,
      workingDirectory: root.path,
      environment: home,
    );
    String ran(List<String> args) {
      final result = run(args);
      expect(result.exitCode, 0, reason: '$args: ${result.stderr}');
      return result.stdout as String;
    }

    Duration timedWrite(List<String> args) {
      final measured = measureChild(() => run(args));
      expect(
        measured.result.exitCode,
        0,
        reason: '$args: ${measured.result.stderr}',
      );
      return measured.elapsed;
    }

    String baseOf(String address) {
      final docs = jsonDecode(ran(['get', address, '--json'])) as Map;
      return ((docs['docs']! as List).first as Map)['base']! as String;
    }

    final batch = File('${root.path}/batch.md');
    var summaries = 0;
    Duration setSummary() {
      final got = ran(['get', 'feature:feature_1']);
      final cut = got.indexOf('\n') + 1;
      final body = got.substring(cut);
      // The doc's other fields, `draft` among them, stay as they are: a batch
      // that drops one writes it.
      var fields = <String>[];
      var rest = '\n$body';
      if (body.startsWith('---\n')) {
        final end = body.indexOf('\n---\n');
        fields = [
          for (final line in LineSplitter.split(body.substring(4, end)))
            if (!line.startsWith('summary:')) line,
        ];
        rest = body.substring(end + '\n---\n'.length);
      }
      batch.writeAsStringSync(
        '${got.substring(0, cut)}---\n'
        '${[for (final line in fields) '$line\n'].join()}'
        'summary: Summary ${summaries++}.\n---\n$rest',
      );
      return timedWrite(['set', '--batch', batch.path]);
    }

    Duration best(String label, Duration Function() write) => bestOf(
      timingRuns,
      write,
      label: label,
      metric: timingMetric,
      scale: scale,
    );

    setSummary(); // warm-up: the feature map holds its block after it
    expectWithinBound(
      best('set calls', setSummary),
      const Duration(seconds: 2),
    );

    var stories = 0;
    expectWithinBound(
      best(
        'new calls',
        () => timedWrite([
          'new',
          'user_story',
          '--parent',
          'feature:feature_1',
          '--slug',
          'probe_${stories++}',
        ]),
      ),
      const Duration(seconds: 2),
    );

    var feature = 1;
    expectWithinBound(
      best('move calls', () {
        final from = feature;
        feature = from == 2 ? 1 : 2;
        return timedWrite([
          'move',
          'user_story:feature_$from/probe_0',
          '--under',
          'feature:feature_$feature',
        ]);
      }),
      const Duration(seconds: 2),
    );

    var slug = 'story_1';
    var renames = 0;
    expectWithinBound(
      best('rename calls', () {
        final from = slug;
        slug = 'renamed_${renames++}';
        return timedWrite([
          'rename',
          'user_story:feature_3/$from',
          '--to',
          slug,
        ]);
      }),
      const Duration(seconds: 2),
    );

    var drafts = 0;
    expectWithinBound(
      best('approve calls', () {
        final draft = 'user_story:feature_4/draft_${drafts++}';
        ran([
          'new',
          'user_story',
          '--parent',
          'feature:feature_4',
          '--slug',
          draft.split('/').last,
        ]);
        return timedWrite(['approve', '$draft@${baseOf(draft)}', '--yes']);
      }),
      const Duration(seconds: 2),
    );

    var doomed = 0;
    expectWithinBound(
      best('delete calls', () {
        final story = 'gone_${doomed++}';
        ran([
          'new',
          'user_story',
          '--parent',
          'feature:feature_4',
          '--slug',
          story,
        ]);
        return timedWrite(['delete', 'user_story:feature_4/$story']);
      }),
      const Duration(seconds: 2),
    );

    // Each call moves the feature map row of feature_1 between first and
    // second, so every call changes the order.
    var place = '1';
    expectWithinBound(
      best('reorder calls', () {
        place = place == '1' ? '2' : '1';
        return timedWrite(['reorder', 'feature:feature_1', '--to', place]);
      }),
      const Duration(seconds: 2),
    );
  });

  test('specstone context for a story whose FR cites an item of another FR '
      'appends the item and answers within 500 ms in the fastest of five '
      'calls', () {
    const call = ['context', 'feature_2/story_1', '--for', 'implement'];
    final first = runSpecstoneSync(
      exe,
      call,
      workingDirectory: project.path,
    ); // warm-up: the index is current after it
    expect(first.exitCode, 0, reason: '${first.stderr}');
    expect(
      first.stdout.toString(),
      allOf(
        contains(
          '==> feature_1/story_1/req_1 (fr) · '
          'prds/features/f01_feature_1/us01_story_1/fr01_req_1.md#edge_cases '
          '· item E01 · cited <==\n- **E01** Baseline text.\n',
        ),
        contains('- feature_1/story_1/req_1 (fr) · cited edge_cases [E01]'),
      ),
    );
    expectWithinBound(
      bestOf(
        timingRuns,
        () => timed(call),
        label: 'followed context calls',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(milliseconds: 500),
    );
  });

  test('a whole-project specstone check over a project whose FRs each link an '
      'item finishes within 2 s in the fastest of five calls', () {
    const link =
        '[E01](../../f01_feature_1/us01_story_1/fr01_req_1.md#edge-cases)';
    const broken =
        '[E99](../../f01_feature_1/us01_story_1/fr01_req_1.md#edge-cases)';
    final frs = [
      for (final file in Directory(
        '${project.path}/docs/prds/features',
      ).listSync(recursive: true).whereType<File>())
        if (RegExp(r'fr\d+_req_\d+\.md$').hasMatch(file.path)) file,
    ];
    final originals = {for (final f in frs) f: f.readAsStringSync()};
    addTearDown(() {
      originals.forEach((file, text) => file.writeAsStringSync(text));
    });
    var count = 0;
    for (final MapEntry(key: file, value: text) in originals.entries) {
      count++;
      file.writeAsStringSync('$text\nSee ${count == 1 ? broken : link}.\n');
    }
    expect(count, greaterThan(1000));
    const call = ['check'];
    final first = runSpecstoneSync(
      exe,
      call,
      workingDirectory: project.path,
    ); // warm-up: the index is current after it
    expect(first.exitCode, 1, reason: '${first.stderr}');
    final missing = RegExp(
      r'^.*: link_item_missing: .*$',
      multiLine: true,
    ).allMatches(first.stdout.toString());
    expect(missing, hasLength(1), reason: 'the rule ran over the linked items');
    expectWithinBound(
      bestOf(
        timingRuns,
        () => timed(call, exitCodes: {1}),
        label: 'check calls over item links',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(seconds: 2),
    );
  });

  test('a whole-project specstone check over a project whose FRs each hold a '
      'bare item ID finishes within 2 s in the fastest of five calls', () {
    const heldId = 'E900';
    const lackedId = 'E901';
    const section = '## Edge cases\n';
    final frs = [
      for (final file in Directory(
        '${project.path}/docs/prds/features',
      ).listSync(recursive: true).whereType<File>())
        if (RegExp(r'fr\d+_req_\d+\.md$').hasMatch(file.path)) file,
    ];
    final originals = {for (final f in frs) f: f.readAsStringSync()};
    addTearDown(() {
      originals.forEach((file, text) => file.writeAsStringSync(text));
    });
    var count = 0;
    for (final MapEntry(key: file, value: text) in originals.entries) {
      count++;
      final mentioned = count == 1 ? lackedId : heldId;
      final held = text.replaceFirst(section, '$section- **$heldId** Held.\n');
      file.writeAsStringSync('$held\nSee $mentioned here.\n');
    }
    expect(count, greaterThan(1000));
    const call = ['check'];
    final first = runSpecstoneSync(
      exe,
      call,
      workingDirectory: project.path,
    ); // warm-up: the index is current after it
    expect(first.exitCode, 1, reason: '${first.stderr}');
    final missing = RegExp(
      r'^.*: item_mention_missing: .*$',
      multiLine: true,
    ).allMatches(first.stdout.toString());
    expect(missing, hasLength(1), reason: 'the rule ran over the bare IDs');
    expectWithinBound(
      bestOf(
        timingRuns,
        () => timed(call, exitCodes: {1}),
        label: 'check calls over bare item IDs',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(seconds: 2),
    );
  });

  test('a whole-project specstone check --repeats, '
      'with a current index, finishes within 2 s in the fastest of five '
      'calls', () {
    const call = ['check', '--repeats'];
    final first = runSpecstoneSync(
      exe,
      call,
      workingDirectory: project.path,
    ); // warm-up: the index is current after it
    expect(first.exitCode, 0, reason: '${first.stderr}');
    expect(first.stdout.toString(), matches(RegExp(r'\d+ repeat groups?\n$')));
    expectWithinBound(
      bestOf(
        timingRuns,
        () => timed(call),
        label: 'check --repeats calls',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(seconds: 2),
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
    final first = runSpecstoneSync(exe, call, workingDirectory: project.path);
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
    // The new files change the folder its feature's record covers.
    final suspects = RegExp(
      r'^.*: code_suspect: .*$',
      multiLine: true,
    ).allMatches(first.stdout.toString()).map((m) => m[0]);
    expect(suspects, hasLength(1));
    expect(
      suspects.single,
      startsWith('.specstone/records/f01_feature_1/IMPLEMENTATION.md:'),
    );
    expectWithinBound(
      bestOf(
        timingRuns,
        () => timed(call, exitCodes: {0, 1}),
        label: 'check calls over comment-rich code',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(seconds: 2),
    );
  });

  test('a broken code path in a record shows in the check, so the '
      'timed runs read the records', () {
    final record = File(
      '${project.path}/.specstone/records/f01_feature_1/IMPLEMENTATION.md',
    );
    final original = record.readAsStringSync();
    addTearDown(() => record.writeAsStringSync(original));
    record.writeAsStringSync(
      original.replaceFirst(
        'src/feature_1/story_1/req_1.dart:Req1',
        'src/feature_1/story_1/gone.dart:Req1',
      ),
    );
    final run = runSpecstoneSync(exe, [
      'check',
    ], workingDirectory: project.path);
    expect(
      run.stdout.toString(),
      matches(
        RegExp(
          r'\.specstone/records/f01_feature_1/IMPLEMENTATION\.md:\d+: '
          'implements_path_unresolved',
        ),
      ),
    );
  });

  test('a whole-project specstone check reads every skill and agent '
      'file of an init project within 2 s in the fastest of five calls', () {
    final root = Directory.systemTemp.createTempSync('specstone_skills_');
    addTearDown(() => root.deleteSync(recursive: true));
    final environment = {
      'HOME': testHome().path,
      'USERPROFILE': testHome().path,
    };
    final init = runSpecstoneSync(
      exe,
      ['init'],
      workingDirectory: root.path,
      environment: environment,
    );
    expect(init.exitCode, 0, reason: '${init.stdout}\n${init.stderr}');
    const edited = '.codex/agents/specstone-sdd-engineer.toml';
    final file = File('${root.path}/$edited');
    final original = file.readAsStringSync();
    ProcessResult check() => runSpecstoneSync(
      exe,
      ['check'],
      workingDirectory: root.path,
      environment: environment,
    );

    expect(check().stdout.toString(), isNot(contains('agent_block_stale')));
    file.writeAsStringSync('hand edit\n');
    expect(
      check().stdout.toString(),
      contains('$edited:1: agent_block_stale: '),
      reason: 'the timed runs read the skill and agent files',
    );
    file.writeAsStringSync(original);
    const settings = '.claude/settings.json';
    final settingsFile = File('${root.path}/$settings');
    final settingsOriginal = settingsFile.readAsStringSync();
    settingsFile.writeAsStringSync('{}\n');
    expect(
      check().stdout.toString(),
      contains('$settings:1: agent_block_stale: '),
      reason: 'the timed runs read the settings file',
    );
    settingsFile.writeAsStringSync(settingsOriginal);
    expect(check().stdout.toString(), isNot(contains('agent_block_stale')));
    expectWithinBound(
      bestOf(
        timingRuns,
        () {
          final run = measureChild(check);
          expect(
            run.result.exitCode,
            anyOf(0, 1),
            reason: '${run.result.stderr}',
          );
          return run.elapsed;
        },
        label: 'check calls over skill, agent, and settings files',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(seconds: 2),
    );
  });

  test('approve --dry-run builds the views of 20 drafts of 55 sentences over '
      '2,000 docs of 5 KB within 2 s in the fastest of five runs', () {
    final root = _writeApproveProject();
    Duration build() => measureInProcess(() {
      final answer = WriteSession.run(
        (session) => approveDryRun(
          session,
          history: ApprovalHistory(runGit: _approvedHistory),
          generators: noGenerators,
        ),
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: null,
      );
      expect(answer.json['count'], _approveDraftCount);
      expect(answer.text, contains('$_droppedPerDraft sentences dropped'));
    });

    build(); // warm-up: the index is current after it
    expectWithinBound(
      bestOf(
        timingRuns,
        build,
        label: 'approve view runs',
        metric: timingMetric,
        scale: scale,
      ),
      const Duration(seconds: 2),
    );
  });

  test('childrenCpuTime counts a busy child once it is waited for', () {
    final watch = Stopwatch()..start();
    final before = childrenCpuTime();
    final run = Process.runSync('/bin/sh', ['-c', _busyLoop]);
    final cpu = childrenCpuTime() - before;
    watch.stop();
    expect(run.exitCode, 0);
    expect(cpu, greaterThan(const Duration(milliseconds: 50)));
    expect(cpu, lessThanOrEqualTo(watch.elapsed + _tick));
  }, testOn: 'mac-os || linux');

  test('selfCpuTime counts in-process work', () {
    final watch = Stopwatch()..start();
    final before = selfCpuTime();
    final sum = _residueSum(_selfCpuLoopCount);
    final cpu = selfCpuTime() - before;
    watch.stop();
    expect(sum, _selfCpuLoopCount ~/ _residueModulus * _residueCycleSum);
    expect(cpu, greaterThan(const Duration(milliseconds: 50)));
    expect(
      cpu,
      lessThanOrEqualTo(watch.elapsed * Platform.numberOfProcessors + _tick),
    );
  }, testOn: 'mac-os || linux');
}

int _residueSum(int count) {
  var sum = 0;
  for (var i = 0; i < count; i++) {
    sum += i % _residueModulus;
  }
  return sum;
}
