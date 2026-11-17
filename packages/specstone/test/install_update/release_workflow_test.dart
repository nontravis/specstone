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

void main() {
  late YamlMap release;
  late YamlMap ci;

  setUpAll(() {
    release = _load('release.yaml');
    ci = _load('ci.yaml');
  });

  test('only publish holds contents: write', () {
    for (final name in ['version', 'test', 'build']) {
      expect(
        _job(release, name).containsKey('permissions'),
        isFalse,
        reason: name,
      );
    }
    expect(_job(release, 'publish')['permissions'], {'contents': 'write'});
  });

  test('no leg of the ci test job can pass while its tests fail', () {
    final job = _job(ci, 'test');
    expect(job.containsKey('continue-on-error'), isFalse);
    expect(job.containsKey('if'), isFalse);
    for (final s in _steps(job)) {
      expect(s.containsKey('continue-on-error'), isFalse, reason: '$s');
    }
    final call = _job(release, 'test');
    expect(call['uses'], './.github/workflows/ci.yaml');
    expect(call.containsKey('with'), isFalse);
  });

  test('build waits for test and publish waits for build', () {
    expect(_job(release, 'build')['needs'], contains('test'));
    expect(_job(release, 'publish')['needs'], contains('build'));
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

    test('a tag off version.dart fails', () async {
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
      test('Test, build, and publish on the tag '
          '$tag publishes a GitHub pre-release with generated notes', () async {
        final log = await publishedWith(tag);

        expectCreateLine(log, tag);
        expect(log, contains('--prerelease'));
      });
    }

    test('Test, build, and publish on the tag '
        'a release tag publishes a normal release', () async {
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
