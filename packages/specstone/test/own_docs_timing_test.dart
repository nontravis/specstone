@Tags(['timing'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers/best_of.dart';
import 'helpers/built_cli.dart';
import 'helpers/reference_time.dart';
import 'helpers/timing_metric.dart';

/// Names the folder that holds the project's own docs and `.specstone/`.
const _docsVariable = 'SPECSTONE_OWN_DOCS';

const _syncContextBudget = Duration(seconds: 3);
const _setSyncBudget = Duration(seconds: 2);
const _reviewContextBudget = Duration(seconds: 1);

/// The fewest FRs the timed review's story holds.
const _reviewStoryFrs = 2;

/// Folders the copy leaves out at any depth: other checkouts, build output,
/// and run artifacts, none of which a sync reads.
const _skippedAnywhere = {
  '.worktrees',
  '.dart_tool',
  'build',
  'tmp',
  'coverage',
  '.superpowers',
};

/// Folders the copy leaves out at the project root, by path from the root.
const _skippedAtRoot = {
  'evals',
  'scratch',
  '.specstone/reports',
  '.specstone/bundles',
};

const _verdictsMarker = '==> verdicts <==';
const _groupSeparator = ' · ';

void _copyTree(Directory from, Directory to, {String relative = ''}) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final path = relative.isEmpty ? name : '$relative/$name';
    if (_skippedAnywhere.contains(name) || _skippedAtRoot.contains(path)) {
      continue;
    }
    final target = '${to.path}/$name';
    switch (entity) {
      case Directory():
        _copyTree(entity, Directory(target), relative: path);
      case Link():
        Link(target).createSync(entity.targetSync());
      case File():
        entity.copySync(target);
    }
  }
}

/// Copies the docs project at [source] into a new temp folder.
Directory _copyProject(String source) {
  final copy = Directory.systemTemp.createTempSync('specstone_own_docs_');
  _copyTree(Directory(source), copy);
  return copy;
}

/// Returns the group files `context --for sync --out` printed on [stdout].
List<String> _groupFiles(String stdout, String root) => [
  for (final line in LineSplitter.split(stdout))
    if (line.split(_groupSeparator) case [_, _, final file])
      if (File(file).isAbsolute) file else '$root/$file',
];

/// Returns the name of each doc a `list <doc type> --json` call printed on
/// [stdout].
List<String> _listedNames(String stdout) => [
  for (final doc
      in ((jsonDecode(stdout) as Map<String, Object?>)['docs']!
              as List<Object?>)
          .cast<Map<String, Object?>>())
    doc['name']! as String,
];

/// Returns [group] with every unjudged `?` verdict line set to `match`.
String _judgedAsMatch(String group) {
  final lines = LineSplitter.split(group).toList();
  final marker = lines.lastIndexOf(_verdictsMarker);
  final judged = [
    for (var i = 0; i < lines.length; i++)
      if (i > marker && lines[i].startsWith('? '))
        'match ${lines[i].substring(2)}'
      else
        lines[i],
  ];
  return '${judged.join('\n')}\n';
}

void main() {
  final source = Platform.environment[_docsVariable];
  final skip = source == null
      ? 'set $_docsVariable to the folder that holds .specstone/config.yaml'
      : null;
  late String exe;
  late ReferenceScale scale;
  late Directory base;
  late String feature;

  ProcessResult run(Directory project, List<String> args) =>
      runSpecstoneSync(exe, args, workingDirectory: project.path);

  MeasuredRun timed(Directory project, List<String> args) {
    final measured = measureChild(() => run(project, args));
    expect(
      measured.result.exitCode,
      0,
      reason: '${measured.result.stdout}\n${measured.result.stderr}',
    );
    return measured;
  }

  /// Picks the top-level feature with the slowest non-empty sync work list.
  String slowestFeature(Directory project) {
    final listed = run(project, ['list', 'feature', '--json']);
    final names = [
      for (final doc
          in ((jsonDecode('${listed.stdout}') as Map<String, Object?>)['docs']!
                  as List<Object?>)
              .cast<Map<String, Object?>>())
        if (!(doc['name']! as String).contains('/')) doc['name']! as String,
    ];
    String? slowest;
    var slowestTime = Duration.zero;
    for (final name in names) {
      final measured = timed(project, [
        'context',
        name,
        '--for',
        'sync',
        '--out',
      ]);
      final groups = _groupFiles('${measured.result.stdout}', project.path);
      // ignore: avoid_print, the pick is part of the measurement a reader checks.
      print(
        'diagnostic: sync work of $name ${groups.length} groups '
        '${measured.elapsed.inMilliseconds} ms',
      );
      if (groups.isNotEmpty && measured.elapsed >= slowestTime) {
        slowest = name;
        slowestTime = measured.elapsed;
      }
    }
    expect(slowest, isNotNull, reason: 'no top-level feature has sync work');
    return slowest!;
  }

  /// Picks the docs a review call times from the index: the first story
  /// holding two or more FRs, its FRs, and the first agent doc, a
  /// cross-feature set the size of a builder check's drafts.
  List<String> reviewTargets(Directory project) {
    List<String> listed(String docType) =>
        _listedNames('${run(project, ['list', docType, '--json']).stdout}');
    final frsByStory = <String, List<String>>{};
    for (final fr in listed('fr')) {
      final slash = fr.lastIndexOf('/');
      if (slash > 0) (frsByStory[fr.substring(0, slash)] ??= []).add(fr);
    }
    final stories = [
      for (final entry in frsByStory.entries)
        if (entry.value.length >= _reviewStoryFrs) entry,
    ];
    final agents = listed('agent');
    expect(stories, isNotEmpty, reason: 'no story holds two FRs');
    expect(agents, isNotEmpty, reason: 'no agent doc');
    final MapEntry(key: story, value: frs) = stories.first;
    return [
      'user_story:$story',
      for (final fr in frs) 'fr:$fr',
      'agent:${agents.first}',
    ];
  }

  group("on the project's own docs", () {
    setUpAll(() async {
      exe = await buildSpecstone();
      scale = ReferenceScale.measure();
      base = _copyProject(source!);
      addTearDown(() => base.deleteSync(recursive: true));
      feature = slowestFeature(base);
      // ignore: avoid_print, the picked feature names what the budgets timed.
      print('diagnostic: timed feature $feature');
    });

    test('the fastest of five context --for sync --out calls on the own docs '
        'stays within 3 s', () {
      final call = ['context', feature, '--for', 'sync', '--out'];
      expectWithinBound(
        bestOf(
          timingRuns,
          () => timed(base, call).elapsed,
          label: 'context --for sync calls',
          metric: timingMetric,
          scale: scale,
        ),
        _syncContextBudget,
      );
    });

    test('the fastest of five context --for review --out calls on the own docs '
        'stays within 1 s', () {
      final targets = reviewTargets(base);
      // ignore: avoid_print, the picked docs name what the budget timed.
      print('diagnostic: timed review of ${targets.join(' ')}');
      final call = ['context', ...targets, '--for', 'review', '--out'];
      expectWithinBound(
        bestOf(
          timingRuns,
          () => timed(base, call).elapsed,
          label: 'context --for review calls',
          metric: timingMetric,
          scale: scale,
        ),
        _reviewContextBudget,
      );
    });

    test(
      'the fastest of five set --sync calls on one group file of a fresh copy '
      'of the own docs stays within 2 s',
      () {
        expectWithinBound(
          bestOf(
            timingRuns,
            () {
              final copy = _copyProject(base.path);
              try {
                final made = run(copy, [
                  'context',
                  feature,
                  '--for',
                  'sync',
                  '--out',
                ]);
                expect(made.exitCode, 0, reason: '${made.stderr}');
                final group = File(
                  _groupFiles('${made.stdout}', copy.path).first,
                );
                final scratch = Directory.systemTemp.createTempSync(
                  'specstone_judged_',
                );
                addTearDown(() => scratch.deleteSync(recursive: true));
                final judged = File('${scratch.path}/sync.txt')
                  ..writeAsStringSync(_judgedAsMatch(group.readAsStringSync()));
                return timed(copy, ['set', '--sync', judged.path]).elapsed;
              } finally {
                copy.deleteSync(recursive: true);
              }
            },
            label: 'set --sync calls',
            metric: timingMetric,
            scale: scale,
          ),
          _setSyncBudget,
        );
      },
    );
  }, skip: skip);
}
