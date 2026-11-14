import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers/script_sandbox.dart';

YamlMap _load(String name) {
  final file = File('${repoRoot().path}/.github/workflows/$name');
  return loadYaml(file.readAsStringSync()) as YamlMap;
}

YamlMap _jobs(YamlMap workflow) => workflow['jobs'] as YamlMap;

YamlMap _job(YamlMap workflow, String name) => _jobs(workflow)[name] as YamlMap;

List<YamlMap> _steps(YamlMap job) =>
    (job['steps'] as YamlList).cast<YamlMap>().toList();

String _runText(YamlMap job) =>
    _steps(job).map((step) => '${step['run'] ?? ''}').join('\n');

String _stepText(YamlMap job) =>
    _steps(job).map((step) => step.toString()).join('\n');

void main() {
  late YamlMap release;
  late YamlMap ci;

  setUpAll(() {
    release = _load('release.yaml');
    ci = _load('ci.yaml');
  });

  test('f09/us04/fr05: release.yaml runs on a v* tag with read-only top '
      'permissions', () {
    final on = release['on'] as YamlMap;
    expect((on['push'] as YamlMap)['tags'], ['v*']);
    expect(release['permissions'], {'contents': 'read'});
  });

  test("f09/us04/fr05/e01, e05: version, then ci.yaml's jobs, then build, "
      'then publish', () {
    expect(
      _jobs(release).keys,
      unorderedEquals(['version', 'test', 'build', 'publish']),
    );
    final test = _job(release, 'test');
    expect(test['needs'], 'version');
    expect(test['uses'], './.github/workflows/ci.yaml');
    expect(_job(release, 'build')['needs'], 'test');
    expect(_job(release, 'publish')['needs'], 'build');
  });

  test('f09/us04/fr05: only publish holds contents: write', () {
    for (final name in ['version', 'test', 'build']) {
      expect(
        _job(release, name).containsKey('permissions'),
        isFalse,
        reason: name,
      );
    }
    expect(_job(release, 'publish')['permissions'], {'contents': 'write'});
  });

  test('f09/us04/fr05, f09/us04/fr06: build packs and smoke-tests the four '
      'targets', () {
    final build = _job(release, 'build');
    final include =
        ((build['strategy'] as YamlMap)['matrix'] as YamlMap)['include']
            as YamlList;
    expect(include.map((e) => (e as YamlMap)['runner']), [
      'macos-15',
      'macos-15-intel',
      'ubuntu-22.04',
      'windows-latest',
    ]);
    expect(include.map((e) => (e as YamlMap)['target']), [
      'macos-arm64',
      'macos-x64',
      'linux-x64',
      'windows-x64',
    ]);
    expect(build['runs-on'], r'${{ matrix.runner }}');
    expect(((build['defaults'] as YamlMap)['run'] as YamlMap)['shell'], 'bash');

    final text = _stepText(build);
    for (final fragment in [
      'dart build cli -t bin/specstone.dart',
      'tool/third_party_notices.dart',
      'SPECSTONE_ARCHIVE_DIR',
      'install.sh',
      'install.ps1',
      'uninstall',
    ]) {
      expect(text, contains(fragment));
    }

    final run = _runText(build);
    expect(
      run.indexOf(r'mkdir -p "$RUNNER_TEMP/stage"'),
      allOf(isNonNegative, lessThan(run.indexOf('tool/third_party_notices'))),
    );

    final pwshSteps = _steps(build).where((s) => s['shell'] == 'pwsh').toList();
    expect(pwshSteps, isNotEmpty);
    for (final step in pwshSteps) {
      expect(step['if'], "runner.os == 'Windows'");
      expect('${step['run']}', isNot(contains(r'$RUNNER_TEMP')));
    }
    for (final step in _steps(build)) {
      final run = '${step['run'] ?? ''}';
      if (step['shell'] == 'pwsh') continue;
      if (run.contains('tar -czf') ||
          run.contains('install.sh') ||
          run.contains('uninstall.sh')) {
        expect(step['if'], "runner.os != 'Windows'", reason: run);
      }
    }
  });

  test('f09/us04/fr06: each install smoke opens the SQLite index between the '
      'install and the uninstall', () {
    final steps = _steps(_job(release, 'build'));
    for (final (installer, uninstaller, index) in [
      ('install.sh', 'uninstall.sh', '.specstone/index.sqlite'),
      ('install.ps1', 'uninstall.ps1', r'.specstone\index.sqlite'),
    ]) {
      final run = steps
          .map((step) => '${step['run'] ?? ''}')
          .singleWhere((run) => run.contains(uninstaller));
      final installed = run.indexOf(installer);
      final listed = run.indexOf('list feature');
      expect(installed, isNonNegative, reason: run);
      expect(listed, greaterThan(installed), reason: run);
      expect(run.indexOf(index), greaterThan(listed), reason: run);
      expect(run.indexOf(uninstaller), greaterThan(run.indexOf(index)));
    }
  });

  test('Package each archive with its notices '
      'E04: Stage the bundle copies the target shim into bin', () {
    final stage = _steps(_job(release, 'build'))
        .singleWhere((s) => s['name'] == 'Stage the bundle');
    final run = '${stage['run']}';
    final windowsArm = run.indexOf(r'if [ "$RUNNER_OS" = Windows ]; then');
    final posixArm = run.indexOf('else');
    final cmdCopy = run.indexOf(
      r'cp -p packages/specstone/bin/stn.cmd "$RUNNER_TEMP/stage/bin/stn.cmd"',
    );
    final stnCopy = run.indexOf(
      r'cp -p packages/specstone/bin/stn "$RUNNER_TEMP/stage/bin/stn"',
    );
    // Each copy runs only in its platform arm, so a tar.gz never stages
    // stn.cmd and the zip never stages stn.
    expect(windowsArm, isNonNegative);
    expect(cmdCopy, greaterThan(windowsArm), reason: run);
    expect(cmdCopy, lessThan(posixArm), reason: run);
    expect(stnCopy, greaterThan(posixArm), reason: run);
  });

  test('Package each archive with its notices '
      'E04: the packed archive is checked between the pack steps and '
      'SHA256SUMS', () {
    final steps = _steps(_job(release, 'build'));
    final names = steps.map((s) => '${s['name'] ?? s['uses'] ?? ''}').toList();
    final check = names.indexOf('Check the shim in the archive');
    expect(check, isNonNegative, reason: names.join(', '));
    expect(check, greaterThan(names.indexOf('Pack the archive')));
    expect(check, greaterThan(names.indexOf('Pack the archive (Windows)')));
    expect(check, lessThan(names.indexOf('Write SHA256SUMS')));

    final run = '${steps[check]['run']}';
    expect(run, contains('tar -tvzf'));
    expect(run, contains(r"grep -q 'bin/stn.cmd$'"));
    expect(run, contains(r"grep 'bin/stn$'"));
    expect(run, contains(r"grep -q 'stn.cmd$'"));
    expect(run, contains("grep -Eq '^-..x'"));
  });

  test('f09/us04/fr05/e02: the version job checks the tag against '
      'version.dart and the five spots', () {
    final version = _job(release, 'version');
    expect(version['runs-on'], 'ubuntu-latest');
    final run = _runText(version);
    expect(run, contains('GITHUB_REF_NAME'));
    expect(run, contains('packages/specstone_core/lib/src/version.dart'));
    expect(run, contains('specstoneVersion'));
    expect(run, contains('dart test test/src/shared_version_test.dart'));
    expect(run, contains('--enforce-lockfile'));
  });

  test('f09/us04/fr05: publish uploads four archives and SHA256SUMS with '
      'generated notes', () {
    final publish = _job(release, 'publish');
    expect(publish['runs-on'], 'ubuntu-latest');
    final run = _runText(publish);
    expect(run, contains('gh release create'));
    expect(run, contains('--generate-notes'));
    expect(run, contains('SHA256SUMS'));
    expect(_stepText(publish), contains('actions/download-artifact@v8'));
  });

  test('f09/us04/fr07, f09/us04/s2: ci.yaml tests on Linux, macOS arm64, and '
      'Windows and answers workflow_call', () {
    expect((ci['on'] as YamlMap).containsKey('workflow_call'), isTrue);
    final matrix =
        (_job(ci, 'test')['strategy'] as YamlMap)['matrix'] as YamlMap;
    expect(matrix['os'], ['ubuntu-latest', 'macos-latest', 'windows-latest']);
    expect(matrix['suite'], ['core', 'cli']);
    expect((_job(ci, 'test')['strategy'] as YamlMap)['fail-fast'], isFalse);
  });

  test('each test step of the test job runs in one suite leg only', () {
    for (final step in _steps(_job(ci, 'test'))) {
      final dir = '${step['working-directory'] ?? ''}';
      final cond = '${step['if'] ?? ''}';
      if (dir == 'packages/specstone_core') {
        expect(cond, contains("matrix.suite == 'core'"));
      }
      if (dir == 'packages/specstone') {
        expect(cond, contains("matrix.suite == 'cli'"));
      }
    }
    final timing = _steps(_job(ci, 'test'))
        .singleWhere((s) => '${s['run']}'.contains('--tags timing'));
    expect(timing['if'], "matrix.suite == 'cli'");
    final upload = _steps(
      _job(ci, 'test'),
    ).singleWhere((s) => '${s['uses']}'.startsWith('actions/upload-artifact@'));
    expect('${(upload['with'] as YamlMap)['name']}', contains('matrix.suite'));
  });

  test('coverage and its upload run on the ubuntu legs only', () {
    final steps = _steps(_job(ci, 'test'));
    final gate = steps
        .where((s) => '${s['run']}'.contains('--fail-under=80'))
        .toList();
    expect(gate, hasLength(1));
    expect(
      gate.single['if'],
      "matrix.suite == 'core' && matrix.os == 'ubuntu-latest'",
    );
    final corePlain = steps.singleWhere(
      (s) =>
          s['if'] == "matrix.suite == 'core' && matrix.os != 'ubuntu-latest'",
    );
    expect(
      '${corePlain['run']}',
      allOf(startsWith('dart test'), isNot(contains('coverage'))),
    );
    for (final s in steps.where(
      (s) => '${s['run']}'.contains('--coverage-path'),
    )) {
      expect('${s['if']}', contains("matrix.os == 'ubuntu-latest'"));
    }
    final upload = steps.singleWhere(
      (s) => '${s['uses']}'.startsWith('actions/upload-artifact@'),
    );
    expect(upload['if'], "matrix.os == 'ubuntu-latest'");
  });

  test('f09/us04/fr07: the PowerShell script tests run in their own Windows '
      'job and stay out of the main Windows step', () {
    final job = _job(ci, 'test-scripts-windows');
    expect(job['runs-on'], 'windows-latest');
    // 30 while ci.yaml's WORKAROUND (fix item 79) holds; 20 once it goes.
    expect(job['timeout-minutes'], 30);
    expect(_runText(job), contains('dart test --tags ps1'));
    final main = _steps(_job(ci, 'test'));
    final windowsStep = main.singleWhere(
      (step) =>
          step['if'] ==
          "matrix.suite == 'cli' && matrix.os == 'windows-latest'",
    );
    expect('${windowsStep['run']}', contains('--exclude-tags timing,ps1'));
    final otherStep = main.singleWhere(
      (step) =>
          step['if'] == "matrix.suite == 'cli' && matrix.os == 'macos-latest'",
    );
    expect('${otherStep['run']}', isNot(contains('ps1')));
  });

  test('f09/us04/fr05: no run script holds a workflow expression', () {
    for (final workflow in [release, ci]) {
      for (final job in _jobs(workflow).values) {
        if ((job as YamlMap).containsKey('uses')) continue;
        for (final step in _steps(job)) {
          expect('${step['run'] ?? ''}', isNot(contains(r'${{')));
        }
      }
    }
  });

  test('f09/us04/fr05, INV-4: every build upload name matches the publish '
      'download pattern', () {
    final upload = _steps(
      _job(release, 'build'),
    ).firstWhere((s) => '${s['uses']}'.startsWith('actions/upload-artifact@'));
    final download = _steps(_job(release, 'publish')).firstWhere(
      (s) => '${s['uses']}'.startsWith('actions/download-artifact@'),
    );
    final name = (upload['with'] as YamlMap)['name'] as String;
    final withDownload = download['with'] as YamlMap;
    final pattern = withDownload['pattern'] as String;
    expect(withDownload['merge-multiple'], isTrue);
    final targets =
        (((_job(release, 'build')['strategy'] as YamlMap)['matrix']
                    as YamlMap)['include']
                as YamlList)
            .map((e) => (e as YamlMap)['target'] as String);
    final glob = RegExp('^${RegExp.escape(pattern).replaceAll(r'\*', '.*')}\$');
    for (final target in targets) {
      expect(
        glob.hasMatch(name.replaceAll(r'${{ matrix.target }}', target)),
        isTrue,
        reason: target,
      );
    }
  });

  group('the version job script', () {
    Future<ProcessResult> runCheck(String ref) {
      final step = _steps(_job(release, 'version'))
          .firstWhere((s) => '${s['run']}'.contains('GITHUB_REF_NAME'));
      return Process.run(
        'bash',
        ['-c', '${step['run']}'],
        workingDirectory: repoRoot().path,
        environment: {'GITHUB_REF_NAME': ref},
      );
    }

    test('f09/us04/fr05/e02: the tag equal to version.dart passes', () async {
      final r = await runCheck('v$specstoneVersion');
      expect(r.exitCode, 0, reason: '${r.stderr}');
    });

    test('f09/us04/fr05/e02: a tag off version.dart fails', () async {
      final r = await runCheck('v$specstoneVersion.1');
      expect(r.exitCode, 1);
    });
  }, testOn: '!windows');

  group('the publish step script', () {
    late Directory work;

    setUp(() {
      work = Directory.systemTemp.createTempSync('publish_step_');
      File('${work.path}/specstone-x.tar.gz').writeAsStringSync('archive');
      _writeStub(work, 'gh', r'printf "%s\n" "$*" >> "$STUB_LOG"');
      _writeStub(work, 'sha256sum', 'echo "0000  specstone-x.tar.gz"');
    });

    tearDown(() => work.deleteSync(recursive: true));

    Future<String> publishedWith(String ref) async {
      final step = _steps(_job(release, 'publish'))
          .firstWhere((s) => '${s['run']}'.contains('gh release create'));
      final log = File('${work.path}/gh.log');
      final r = await Process.run(
        'bash',
        ['-e', '-c', '${step['run']}'],
        workingDirectory: work.path,
        environment: {
          'PATH': '${work.path}/stubs:${Platform.environment['PATH']}',
          'GITHUB_REF_NAME': ref,
          'GITHUB_REPOSITORY': 'nontravis/specstone',
          'STUB_LOG': log.path,
        },
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return log.readAsStringSync();
    }

    void expectCreateLine(String log, String tag) {
      expect(log, contains('release create $tag '));
      expect(log, contains('--verify-tag'));
      expect(log, contains('--generate-notes'));
      expect(log, endsWith('specstone-x.tar.gz SHA256SUMS\n'));
    }

    for (final tag in ['v1.2.0-beta.1', 'v1.2.0-rc.1', 'v1.2.0-alpha-1']) {
      test(
        'Test, build, and publish on the tag '
        'E06: $tag publishes a GitHub pre-release with generated notes',
        () async {
          final log = await publishedWith(tag);

          expectCreateLine(log, tag);
          expect(log, contains('--prerelease'));
        },
      );
    }

    test('Test, build, and publish on the tag '
        'E07: a release tag publishes a normal release', () async {
      final log = await publishedWith('v1.2.0');

      expectCreateLine(log, 'v1.2.0');
      expect(log, isNot(contains('--prerelease')));
    });
  }, testOn: '!windows');
}

void _writeStub(Directory work, String name, String body) {
  final file = File('${work.path}/stubs/$name')
    ..createSync(recursive: true)
    ..writeAsStringSync('#!/bin/sh\n$body\n');
  Process.runSync('chmod', ['755', file.path]);
}
