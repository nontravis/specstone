import 'dart:io';

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

  test('f09/us04/fr07, f09/us04/s2: ci.yaml tests the four targets and '
      'answers workflow_call', () {
    expect((ci['on'] as YamlMap).containsKey('workflow_call'), isTrue);
    final matrix =
        (_job(ci, 'test')['strategy'] as YamlMap)['matrix'] as YamlMap;
    expect(matrix['os'], [
      'ubuntu-latest',
      'macos-latest',
      'macos-15-intel',
      'windows-latest',
    ]);
  });
}
