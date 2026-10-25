@Tags(['timing'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import 'helpers/baseline_tree.dart';
import 'helpers/built_cli.dart';

void main() {
  late Directory project;
  late String exe;

  setUpAll(() async {
    project = await writeBaselineTree();
    exe = await buildSpecstone();
  });

  Duration timed(List<String> args) {
    final watch = Stopwatch()..start();
    final run = Process.runSync(exe, args, workingDirectory: project.path);
    watch.stop();
    expect(run.exitCode, 0, reason: '${run.stderr}');
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

  test('NFR-P02, f01/us01/fr02/e01: a specstone call from no index builds the '
      'full index within 10 s', () {
    expect(
      File('${project.path}/.specstone/index.sqlite').existsSync(),
      isFalse,
    );
    expect(
      timed(['structure', '--json']),
      lessThanOrEqualTo(const Duration(seconds: 10)),
    );
  });

  test('NFR-P01: specstone context for a story, with a current index, answers '
      'within 500 ms per call', () {
    const call = ['context', 'feature_1/story_1', '--for', 'implement'];
    timed(call); // warm-up: the index is current after it
    for (var i = 0; i < 5; i++) {
      expect(timed(call), lessThanOrEqualTo(const Duration(milliseconds: 500)));
    }
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
}
