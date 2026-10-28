@Tags(['timing'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import 'helpers/baseline_tree.dart';
import 'helpers/best_of.dart';
import 'helpers/built_cli.dart';

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
    final first = Process.runSync(
      exe,
      call,
      workingDirectory: project.path,
    ); // warm-up: the index is current after it
    expect(first.exitCode, anyOf(0, 1), reason: '${first.stderr}');
    final out = first.stdout.toString();
    expect(out, isNot(contains('implements_path_unresolved')));
    expect(out, isNot(contains('implements_symbol_unresolved')));
    expect(out, isNot(contains('code_uncovered')));
    expect(
      bestOf(
        timingRuns,
        () => timed(call, exitCodes: {0, 1}),
        label: 'check calls',
      ),
      lessThanOrEqualTo(const Duration(seconds: 2)),
    );
  });
}
