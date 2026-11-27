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

List<YamlMap> _matrix(YamlMap workflow) =>
    (((_job(workflow, 'build')['strategy'] as YamlMap)['matrix']
                as YamlMap)['include']
            as YamlList)
        .cast<YamlMap>()
        .toList();

String _text(String name) =>
    File('${repoRoot().path}/.github/workflows/$name').readAsStringSync();

String _run(YamlMap job, String name) =>
    '${_steps(job).firstWhere((s) => s['name'] == name)['run']}';

int _stepIndex(YamlMap job, String name) =>
    _steps(job).indexWhere((s) => s['name'] == name);

Set<String> _upstream(YamlMap workflow, String name) {
  final needs = _job(workflow, name)['needs'];
  final direct = switch (needs) {
    null => <String>[],
    final String one => [one],
    _ => (needs as YamlList).cast<String>().toList(),
  };
  return {
    for (final d in direct) ...{d, ..._upstream(workflow, d)},
  };
}

const _archiveNames = {
  'specstone-macos-arm64.tar.gz',
  'specstone-macos-x64.tar.gz',
  'specstone-linux-x64.tar.gz',
  'specstone-windows-x64.zip',
};

void main() {
  late YamlMap release;
  late YamlMap ci;

  setUpAll(() {
    release = _load('release.yaml');
    ci = _load('ci.yaml');
  });

  test('no leg of the ci test or timing job can pass while its tests fail', () {
    for (final name in ['test', 'timing']) {
      final job = _job(ci, name);
      expect(job.containsKey('continue-on-error'), isFalse, reason: name);
      expect(job.containsKey('if'), isFalse, reason: name);
      for (final s in _steps(job)) {
        expect(s.containsKey('continue-on-error'), isFalse, reason: '$s');
        if (name == 'timing') {
          expect(s.containsKey('if'), isFalse, reason: '$s');
        }
      }
    }
    final call = _job(release, 'test');
    expect(call['uses'], './.github/workflows/ci.yaml');
    expect(call.containsKey('with'), isFalse);
  });

  test('every build upload name matches the publish download pattern', () {
    bool isUpload(YamlMap s) => '${s['uses']}'.startsWith('actions/upload-');
    bool isDownload(YamlMap s) =>
        '${s['uses']}'.startsWith('actions/download-');
    final upload = _steps(_job(release, 'build')).firstWhere(isUpload);
    final download = _steps(_job(release, 'publish')).firstWhere(isDownload);
    final name = (upload['with'] as YamlMap)['name'] as String;
    final pattern = (download['with'] as YamlMap)['pattern'] as String;
    final glob = RegExp('^${RegExp.escape(pattern).replaceAll(r'\*', '.*')}\$');
    for (final entry in _matrix(release)) {
      final target = entry['target'] as String;
      final uploaded = name.replaceAll(r'${{ matrix.target }}', target);
      expect(glob.hasMatch(uploaded), isTrue, reason: target);
    }
  });

  test('each build target and extension is the one its installer fetches', () {
    for (final entry in _matrix(release)) {
      final target = entry['target'] as String;
      final ext = entry['ext'] as String;
      final installer = ext == 'zip' ? 'install.ps1' : 'install.sh';
      final text = File('${repoRoot().path}/$installer').readAsStringSync();
      expect(text, contains("'$target'"), reason: '$installer $target');
      expect(text, contains('specstone-\$target.$ext'), reason: installer);
    }
  });

  test('build steps name their shell and platform consistently', () {
    for (final step in _steps(_job(release, 'build'))) {
      final run = '${step['run'] ?? ''}';
      if (step['shell'] == 'pwsh') {
        expect(step['if'], "runner.os == 'Windows'", reason: run);
        expect(run, isNot(contains(r'$RUNNER_TEMP')), reason: run);
      } else if (run.contains('tar -czf') ||
          run.contains('install.sh') ||
          run.contains('uninstall.sh')) {
        expect(step['if'], "runner.os != 'Windows'", reason: run);
      }
    }
  });

  test('the ci test matrix runs the three runners', () {
    final job = _job(ci, 'test');
    final matrix = (job['strategy'] as YamlMap)['matrix'] as YamlMap;
    expect(job['runs-on'], r'${{ matrix.os }}');
    expect(matrix['os'], ['ubuntu-latest', 'macos-latest', 'windows-latest']);
    expect(matrix.containsKey('include'), isFalse);
    expect(matrix.containsKey('exclude'), isFalse);
  });

  test('the ci cli suite runs one leg per CLI_SHARDS shard', () {
    final shards = int.parse('${(ci['env'] as YamlMap)['CLI_SHARDS']}');
    final legs =
        (((_job(ci, 'test')['strategy'] as YamlMap)['matrix'] as YamlMap)['leg']
                as YamlList)
            .where((leg) => (leg as YamlMap)['suite'] == 'cli');
    expect(
      legs.map((leg) => (leg as YamlMap)['shard']),
      List.generate(shards, (i) => i),
    );
    final steps = _steps(_job(ci, 'test'));
    final cliSteps = steps.where(
      (s) => '${s['if']}'.contains("matrix.leg.suite == 'cli'"),
    );
    final cliTests = cliSteps.where((s) => s.containsKey('run')).toList();
    expect(cliTests, hasLength(3));
    for (final s in cliTests) {
      final run = '${s['run']}';
      expect(run, contains(r'--total-shards=${{ env.CLI_SHARDS }}'));
      expect(run, contains(r'--shard-index=${{ matrix.leg.shard }}'));
    }
    final upload = cliSteps.singleWhere(
      (s) => '${s['uses']}'.startsWith('actions/upload-'),
    );
    expect(
      '${(upload['with'] as YamlMap)['name']}',
      contains('matrix.leg.shard'),
    );
  });

  // D18
  test('the ci core suite runs one leg per CORE_SHARDS shard', () {
    final shards = int.parse('${(ci['env'] as YamlMap)['CORE_SHARDS']}');
    final legs =
        (((_job(ci, 'test')['strategy'] as YamlMap)['matrix'] as YamlMap)['leg']
                as YamlList)
            .where((leg) => (leg as YamlMap)['suite'] == 'core');
    expect(
      legs.map((leg) => (leg as YamlMap)['shard']),
      List.generate(shards, (i) => i),
    );
    final coreSteps = _steps(_job(ci, 'test'))
        .where((s) => '${s['if']}'.contains("matrix.leg.suite == 'core'"));
    final coreTests = coreSteps.where((s) => s.containsKey('run')).toList();
    expect(coreTests, hasLength(2));
    for (final s in coreTests) {
      final run = '${s['run']}';
      expect(run, contains(r'--total-shards=${{ env.CORE_SHARDS }}'));
      expect(run, contains(r'--shard-index=${{ matrix.leg.shard }}'));
    }
    final upload = coreSteps.singleWhere(
      (s) => '${s['uses']}'.startsWith('actions/upload-'),
    );
    final name = '${(upload['with'] as YamlMap)['name']}';
    expect(name, startsWith('core-coverage-shard-'));
    expect(name, contains('matrix.leg.shard'));
    expect(
      '${(upload['with'] as YamlMap)['path']}',
      endsWith('/coverage.json'),
    );
  });

  // D18
  test('the core-coverage job merges every core shard against the floor', () {
    final job = _job(ci, 'core-coverage');
    expect(job['needs'], 'test');
    final download = _steps(job)
        .singleWhere((s) => '${s['uses']}'.startsWith('actions/download-'));
    expect((download['with'] as YamlMap)['pattern'], 'core-coverage-shard-*');
    final check = _run(job, 'Check the merged core coverage');
    final countLine = check
        .split('\n')
        .singleWhere((line) => line.contains('coverage.json'));
    expect(countLine, contains(r'-eq ${{ env.CORE_SHARDS }}'));
    expect(check, contains('--fail-under=80'));
  });

  test('the timing gate runs in its own job on the three runners', () {
    final timing = _job(ci, 'timing');
    final matrix = (timing['strategy'] as YamlMap)['matrix'] as YamlMap;
    expect(matrix['os'], ['ubuntu-latest', 'macos-latest', 'windows-latest']);
    final timingRuns = _steps(timing).map((s) => '${s['run'] ?? ''}');
    expect(timingRuns.where((r) => r.contains('--tags timing')), [
      'dart test --tags timing test/nfr_timing_test.dart',
    ]);
    for (final s in _steps(_job(ci, 'test'))) {
      expect('${s['run'] ?? ''}', isNot(contains('--tags timing')));
    }
  });

  test('ci runs on a push to main, develop, and release branches', () {
    final on = ci['on'] as YamlMap;
    expect((on['push'] as YamlMap)['branches'], [
      'main',
      'develop',
      'release/**',
    ]);
    expect(
      on.keys,
      containsAll(['pull_request', 'workflow_dispatch', 'workflow_call']),
    );
  });

  test(
    'the release builds macos-x64 on macos-15-intel and ci never uses it',
    () {
      final x64 = _matrix(release)
          .singleWhere((e) => e['target'] == 'macos-x64');
      expect(x64['runner'], 'macos-15-intel');
      expect(_text('ci.yaml'), isNot(contains('macos-15-intel')));
      expect(_text('ci.yaml'), isNot(contains('macos-x64')));
    },
  );

  test('no ci job runs on a macOS x64 runner', () {
    final text = _text('ci.yaml');
    for (final x64Runner in ['intel', 'macos-13', 'macos-12', 'large']) {
      expect(text, isNot(contains(x64Runner)), reason: x64Runner);
    }
    final macRunners = RegExp(r'macos-[\w.-]+').allMatches(text);
    expect({for (final m in macRunners) m.group(0)}, {'macos-latest'});
  });

  test('build and publish need the version job through the test job', () {
    expect(_upstream(release, 'test'), contains('version'));
    expect(_upstream(release, 'build'), containsAll(['test', 'version']));
    expect(_upstream(release, 'publish'), containsAll(['build', 'version']));
  });

  test('the release workflow triggers on tags only and checks no branch', () {
    final push = (release['on'] as YamlMap)['push'] as YamlMap;
    expect(push.keys, ['tags']);
    expect(push['tags'], ['v*']);
    final text = _text('release.yaml');
    for (final branchCheck in [
      'git branch',
      'merge-base',
      '--contains',
      'release/',
      'github.ref ==',
    ]) {
      expect(text, isNot(contains(branchCheck)), reason: branchCheck);
    }
  });

  test('the release runs version, test, build, and smoke in order', () {
    expect(((release['on'] as YamlMap)['push'] as YamlMap)['tags'], ['v*']);
    expect(_job(release, 'version')['needs'], isNull);
    expect(_job(release, 'ci-passed')['needs'], isNull);
    expect(_job(release, 'test')['needs'], ['version', 'ci-passed']);
    expect(_job(release, 'build')['needs'], ['version', 'ci-passed', 'test']);
    expect(_job(release, 'publish')['needs'], ['version', 'build']);
    expect(
      _run(_job(release, 'version'), 'Check the tag against version.dart'),
      contains('GITHUB_REF_NAME'),
    );
    final build = _job(release, 'build');
    expect(_run(build, 'Build the CLI'), startsWith('dart build cli'));
    expect(build['runs-on'], r'${{ matrix.runner }}');
    expect(_matrix(release).map((e) => e['runner']).toSet(), hasLength(4));
    final smokes = [
      _steps(build).singleWhere(
        (s) => s['name'] == 'Smoke-test install.sh and uninstall.sh',
      ),
      _steps(build).singleWhere(
        (s) => s['name'] == 'Smoke-test install.ps1 and uninstall.ps1',
      ),
    ];
    expect(smokes.map((s) => s['if']), [
      "runner.os != 'Windows'",
      "runner.os == 'Windows'",
    ]);
  });

  test(
    'the top-level permissions stay contents read and no job inherits write',
    () {
      expect(release['permissions'], {'contents': 'read'});
      expect(_job(release, 'publish')['permissions'], {'contents': 'write'});
      expect(_job(release, 'ci-passed')['permissions'], {'actions': 'read'});
      for (final name in _jobs(release).keys) {
        if (name == 'publish' || name == 'ci-passed') continue;
        expect(_job(release, '$name')['permissions'], isNull, reason: '$name');
      }
    },
  );

  test('the test jobs run unless ci passed on the tagged commit', () {
    final test = _job(release, 'test');
    expect(
      '${test['if']}',
      contains("needs.ci-passed.outputs.passed != 'true'"),
    );
    expect(test['uses'], './.github/workflows/ci.yaml');
  });

  test('build takes a skipped test only with a passed ci run', () {
    final build = _job(release, 'build');
    final condition = '${build['if']}';
    expect(condition, contains('!cancelled()'));
    expect(condition, contains("needs.version.result == 'success'"));
    expect(condition, contains("needs.test.result == 'success'"));
    expect(
      condition,
      matches(
        RegExp(
          r"needs\.test\.result == 'skipped' && "
          r"needs\.ci-passed\.result == 'success' && "
          r"needs\.ci-passed\.outputs\.passed == 'true'",
        ),
      ),
    );
    expect(build['needs'], containsAll(['version', 'ci-passed', 'test']));
  });

  test('the test and build conditions are exactly these', () {
    expect(
      _job(release, 'test')['if'],
      "needs.ci-passed.outputs.passed != 'true'",
    );
    expect(
      _job(release, 'build')['if'],
      r"${{ !cancelled() && needs.version.result == 'success' && "
      "(needs.test.result == 'success' || (needs.test.result == 'skipped' && "
      "needs.ci-passed.result == 'success' && "
      "needs.ci-passed.outputs.passed == 'true')) }}",
    );
  });

  test('publish needs a built archive set', () {
    expect(
      '${_job(release, 'publish')['if']}',
      contains("needs.build.result == 'success'"),
    );
  });

  group('the ci-passed step script', () {
    late Directory work;
    late File output;

    setUp(() {
      work = Directory.systemTemp.createTempSync('ci_passed_step_');
      output = File('${work.path}/github_output')..createSync();
    });

    tearDown(() => work.deleteSync(recursive: true));

    ProcessResult runStep(String ghBody) {
      _writeStub(work, 'gh', ghBody);
      final step = _steps(_job(release, 'ci-passed')).firstWhere(
        (s) => s['name'] == 'Find a passed ci run of the tagged commit',
      );
      return Process.runSync(
        'bash',
        ['-e', '-c', '${step['run']}'],
        workingDirectory: work.path,
        environment: {
          'PATH': '${work.path}/stubs:${Platform.environment['PATH']}',
          'GITHUB_OUTPUT': output.path,
          'GITHUB_REPOSITORY': 'nontravis/specstone',
          'GITHUB_SHA': 'abc123',
          'STUB_LOG': '${work.path}/gh.log',
        },
      );
    }

    String ghStub(String count) =>
        'printf "%s\\n" "\$*" >> "\$STUB_LOG"\necho $count';

    test('a passed ci run of the commit writes passed=true', () {
      final r = runStep(ghStub('1'));

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(output.readAsStringSync().trim(), 'passed=true');
    });

    test('no passed ci run of the commit writes passed=false', () {
      final r = runStep(ghStub('0'));

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(output.readAsStringSync().trim(), 'passed=false');
    });

    test('a failing gh call writes passed=false and exits 0', () {
      final r = runStep('exit 1');

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(output.readAsStringSync().trim(), 'passed=false');
    });

    test('the query asks for a successful run of the tagged commit', () {
      runStep(ghStub('1'));

      final log = File('${work.path}/gh.log').readAsStringSync();
      expect(log, contains('head_sha=abc123'));
      expect(log, contains('status=success'));
    });

    test('the query reads the ci.yaml runs and prints only the count', () {
      runStep(ghStub('1'));

      final log = File('${work.path}/gh.log').readAsStringSync();
      expect(log, contains('actions/workflows/ci.yaml/runs?'));
      expect(log, contains('--jq .total_count'));
    });

    test('the ci-passed query counts push runs only', () {
      runStep(ghStub('1'));

      final log = File('${work.path}/gh.log').readAsStringSync();
      expect(log, contains('event=push'));
    });
  }, testOn: '!windows');

  test('each smoke test installs from the local archive in a temp home', () {
    final build = _job(release, 'build');
    final sums = _stepIndex(build, 'Write SHA256SUMS');
    final unix = _run(build, 'Smoke-test install.sh and uninstall.sh');
    expect(unix, contains(r'home="$RUNNER_TEMP/smoke-home"'));
    expect(
      unix,
      contains(
        r'HOME="$home" SPECSTONE_ARCHIVE_DIR="$RUNNER_TEMP/dist" '
        'sh install.sh',
      ),
    );
    expect(unix, contains(r'HOME="$home" sh uninstall.sh'));
    final windows = _run(build, 'Smoke-test install.ps1 and uninstall.ps1');
    expect(
      windows,
      contains(r'$env:SPECSTONE_ARCHIVE_DIR = "$env:RUNNER_TEMP\dist"'),
    );
    expect(windows, contains(r'$env:USERPROFILE = $home_dir'));
    expect(windows, contains('install.ps1'));
    expect(windows, contains('uninstall.ps1'));
    final upload = _steps(build)
        .indexWhere((s) => '${s['uses']}'.startsWith('actions/upload-'));
    for (final name in [
      'Smoke-test install.sh and uninstall.sh',
      'Smoke-test install.ps1 and uninstall.ps1',
    ]) {
      expect(_stepIndex(build, name), greaterThan(sums), reason: name);
      expect(_stepIndex(build, name), lessThan(upload), reason: name);
    }
    expect(_job(release, 'publish')['needs'], contains('build'));
  });

  test('every archive name is the same each release', () {
    final asset = (_job(release, 'build')['env'] as YamlMap)['ASSET'] as String;
    final names = {
      for (final e in _matrix(release))
        asset
            .replaceAll(r'${{ matrix.target }}', '${e['target']}')
            .replaceAll(r'${{ matrix.ext }}', '${e['ext']}'),
    };
    expect(names, _archiveNames);
    expect(asset, isNot(contains('ref_name')));
    expect(asset, isNot(contains('version')));
    for (final name in names) {
      expect(name, isNot(matches(RegExp(r'\d+\.\d+'))), reason: name);
    }
  });

  test('stn.exe links the C runtime statically', () {
    final script = File(
      '${repoRoot().path}/packages/specstone/shim/windows/build.ps1',
    ).readAsStringSync();
    expect(script, contains("'/MT'"));
    expect(script, isNot(contains("'/MD'")));
  });

  test('stn.exe is compiled from its C source with MSVC at release', () {
    final compile = _steps(_job(release, 'build'))
        .firstWhere((s) => s['name'] == 'Compile stn.exe');
    expect(compile['if'], "runner.os == 'Windows'");
    expect('${compile['run']}', contains('shim/windows/build.ps1 -OutFile'));
    final script = File(
      '${repoRoot().path}/packages/specstone/shim/windows/build.ps1',
    ).readAsStringSync();
    expect(script, contains("Invoke-Tool 'cl'"));
    expect(script, contains(r'"$PSScriptRoot\stn.c"'));
    expect(
      File('${repoRoot().path}/packages/specstone/shim/windows/stn.c')
          .existsSync(),
      isTrue,
    );
    final stage = _run(_job(release, 'build'), 'Stage the bundle');
    expect(stage, contains(r'cp -p "$RUNNER_TEMP/stn/stn.exe"'));
  });

  group('the version job script on a pre-release', () {
    late Directory repo;

    setUp(() {
      repo = Directory.systemTemp.createTempSync('pre_release_version_');
      File('${repo.path}/packages/specstone_core/lib/src/version.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "const String specstoneVersion = '1.2.0-beta.1';\n",
        );
    });

    tearDown(() => repo.deleteSync(recursive: true));

    ProcessResult runCheck(String ref) {
      final step = _steps(_job(release, 'version'))
          .firstWhere((s) => '${s['run']}'.contains('GITHUB_REF_NAME'));
      return Process.runSync(
        'bash',
        ['-c', '${step['run']}'],
        workingDirectory: repo.path,
        environment: {'GITHUB_REF_NAME': ref},
      );
    }

    test('the literal pre-release tag passes', () {
      final r = runCheck('v1.2.0-beta.1');
      expect(r.exitCode, 0, reason: '${r.stderr}');
    });

    test('the tag without its pre-release part fails', () {
      expect(runCheck('v1.2.0').exitCode, 1);
    });
  }, testOn: '!windows');

  test('the pre-release version runs through every job unchanged', () {
    for (final name in _jobs(release).keys) {
      expect(
        '${_job(release, '$name')['if'] ?? ''}',
        isNot(contains('prerelease')),
        reason: '$name',
      );
    }
    final steps = _steps(_job(release, 'build'));
    final runs = steps.map((s) => '${s['run'] ?? ''}').join('\n');
    expect(runs, contains(r'${GITHUB_REF_NAME#v}'));
    expect(runs, isNot(contains(r'${GITHUB_REF_NAME%')));
    expect(runs, isNot(contains(r'${GITHUB_REF_NAME#v%')));
    expect(runs, contains(r"$env:GITHUB_REF_NAME -replace '^v', ''"));
    expect(runs, isNot(matches(RegExp("-replace '[^']*-[^']*'"))));
    for (final s in steps) {
      expect(
        s.containsKey('if') ? '${s['if']}' : '',
        isNot(contains('prerelease')),
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

    test('the tag equal to version.dart passes', () async {
      final r = await runCheck('v$specstoneVersion');
      expect(r.exitCode, 0, reason: '${r.stderr}');
    });
  }, testOn: '!windows');

  group('the archive steps', () {
    late Directory work;

    String temp() => '${work.path}/tmp';

    setUp(() {
      work = Directory.systemTemp.createTempSync('archive_steps_');
      File('${work.path}/LICENSE').writeAsStringSync('license');
      File('${work.path}/packages/specstone/bin/stn')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', [
        '755',
        '${work.path}/packages/specstone/bin/stn',
      ]);
      File('${temp()}/build/bundle/bin/specstone')
        ..createSync(recursive: true)
        ..writeAsStringSync('binary');
      File('${temp()}/build/bundle/lib/native.so')
        ..createSync(recursive: true)
        ..writeAsStringSync('native');
      File('${temp()}/stn/stn.exe')
        ..createSync(recursive: true)
        ..writeAsStringSync('exe');
      Directory('${temp()}/dist').createSync(recursive: true);
      _writeStub(work, 'dart', r'printf notices > "$3"');
      _writeStub(
        work,
        'unzip',
        r'(cd "$RUNNER_TEMP/stage" && find . -type f | sed "s|^\./||")',
      );
    });

    tearDown(() => work.deleteSync(recursive: true));

    ProcessResult runStep(String name, {required String os}) {
      final step = _steps(_job(release, 'build'))
          .firstWhere((s) => s['name'] == name);
      return Process.runSync(
        'bash',
        ['-e', '-c', '${step['run']}'],
        workingDirectory: work.path,
        environment: {
          'PATH': '${work.path}/stubs:${Platform.environment['PATH']}',
          'RUNNER_TEMP': temp(),
          'RUNNER_OS': os,
          'ASSET': 'specstone-test.tar.gz',
        },
      );
    }

    List<String> packedTar() {
      expect(runStep('Stage the bundle', os: 'Linux').exitCode, 0);
      expect(runStep('Pack the archive', os: 'Linux').exitCode, 0);
      final r = Process.runSync('tar', [
        '-tzf',
        '${temp()}/dist/specstone-test.tar.gz',
      ]);
      return [
        for (final line in '${r.stdout}'.split('\n'))
          if (line.isNotEmpty) line.replaceFirst(RegExp(r'^\./'), ''),
      ];
    }

    test('a tar.gz archive holds bin/stn and no stn.exe', () {
      final entries = packedTar();

      expect(entries, contains('bin/stn'));
      expect(entries, isNot(contains('bin/stn.exe')));
      expect(
        entries,
        containsAll([
          'bin/specstone',
          'lib/native.so',
          'LICENSE',
          'THIRD_PARTY_NOTICES',
        ]),
      );
      final check = runStep('Check the shim in the archive', os: 'Linux');
      expect(check.exitCode, 0, reason: '${check.stderr}');

      File('${temp()}/stage/bin/stn.exe').writeAsStringSync('exe');
      Process.runSync('tar', [
        '-czf',
        '${temp()}/dist/specstone-test.tar.gz',
        '-C',
        '${temp()}/stage',
        '.',
      ]);
      final rejected = runStep('Check the shim in the archive', os: 'Linux');
      expect(rejected.exitCode, 1);
      expect(rejected.stderr, contains('stn.exe packed into'));
    });

    test('a zip archive holds bin/stn.exe and neither stn nor stn.cmd', () {
      expect(runStep('Stage the bundle', os: 'Windows').exitCode, 0);
      final bin = Directory('${temp()}/stage/bin')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .toSet();
      expect(bin, {'specstone', 'stn.exe'});
      final check = runStep('Check the shim in the archive', os: 'Windows');
      expect(check.exitCode, 0, reason: '${check.stderr}');

      for (final extra in ['stn', 'stn.cmd']) {
        File('${temp()}/stage/bin/$extra').writeAsStringSync('x');
        final rejected = runStep(
          'Check the shim in the archive',
          os: 'Windows',
        );
        expect(rejected.exitCode, 1, reason: extra);
        expect(rejected.stderr, contains('packed into'), reason: extra);
        File('${temp()}/stage/bin/$extra').deleteSync();
      }
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
      test('a pre-release tag $tag is published as a pre-release', () async {
        final log = await publishedWith(tag);

        expectCreateLine(log, tag);
        expect(log, contains('--prerelease'));
      });
    }

    test('a release tag is published as a normal release', () async {
      final log = await publishedWith('v1.2.0');

      expectCreateLine(log, 'v1.2.0');
      expect(log, isNot(contains('--prerelease')));
    });

    test('the release carries the four archives and SHA256SUMS', () async {
      File('${work.path}/specstone-x.tar.gz').deleteSync();
      for (final name in _archiveNames) {
        File('${work.path}/$name').writeAsStringSync('archive');
      }
      _writeStub(work, 'sha256sum', r'for f in "$@"; do echo "0000  $f"; done');
      final log = await publishedWith('v1.2.0');

      final sorted = (_archiveNames.toList()..sort()).join(' ');
      expect(log, endsWith('$sorted SHA256SUMS\n'));
      final sums = File('${work.path}/SHA256SUMS').readAsLinesSync();
      expect(sums, [
        for (final n in _archiveNames.toList()..sort()) '0000  $n',
      ]);
    });
  }, testOn: '!windows');
}

void _writeStub(Directory work, String name, String body) {
  final file = File('${work.path}/stubs/$name')
    ..createSync(recursive: true)
    ..writeAsStringSync('#!/bin/sh\n$body\n');
  Process.runSync('chmod', ['755', file.path]);
}
