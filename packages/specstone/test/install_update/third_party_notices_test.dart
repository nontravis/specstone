@Tags(['integration'])
@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers/script_sandbox.dart';
import '../helpers/temp_tree.dart';

Future<ProcessResult> _runNoticesOn(String vendoredSource) async {
  final root = await writeTree({
    'pubspec.yaml':
        'name: fixture_workspace\n'
        'publish_to: none\n'
        'environment:\n  sdk: ^3.13.0\n'
        'workspace:\n  - packages/specstone\n',
    'packages/specstone/pubspec.yaml':
        'name: specstone\n'
        'publish_to: none\n'
        'resolution: workspace\n'
        'environment:\n  sdk: ^3.13.0\n',
    'packages/specstone/lib/src/vendored.dart': vendoredSource,
    'packages/specstone_core/assets/mermaid/LICENSE': 'Mermaid license.\n',
  });
  final get = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'get',
  ], workingDirectory: root.path);
  expect(get.exitCode, 0, reason: '${get.stderr}');
  return Process.run(Platform.resolvedExecutable, [
    'run',
    '${repoRoot().path}/tool/third_party_notices.dart',
    '${root.path}/THIRD_PARTY_NOTICES',
  ], workingDirectory: root.path);
}

void main() {
  test('the notices hold each runtime package, mermaid, '
      'the Dart SDK, and SQLite', () async {
    final out = File('${(await writeTree({})).path}/THIRD_PARTY_NOTICES');
    final r = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/third_party_notices.dart',
      out.path,
    ], workingDirectory: repoRoot().path);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final text = out.readAsStringSync();
    for (final name in ['args', 'markdown', 'crypto', 'yaml', 'sqlite3']) {
      expect(text, contains('\n## $name '));
    }
    final mermaid = RegExp(
      r'\n## mermaid\n(.*?)(?=\n## |$)',
      dotAll: true,
    ).firstMatch(text)?.group(1);
    expect(mermaid, isNotNull);
    expect(mermaid, contains('Permission is hereby granted'));
    expect(text, contains('## SQLite\n'));
    final sdk = RegExp(
      r'\n## Dart SDK\n(.*?)(?=\n## |$)',
      dotAll: true,
    ).firstMatch(text)?.group(1);
    expect(sdk, isNotNull);
    expect(sdk, contains('Dart project authors'));
    expect(text, isNot(contains('\n## test ')));
    expect(text, isNot(contains('\n## specstone_core ')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  // D15
  test(
    'the notices hold each license file kept beside vendored code',
    () async {
      final out = File('${(await writeTree({})).path}/THIRD_PARTY_NOTICES');
      final r = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/third_party_notices.dart',
        out.path,
      ], workingDirectory: repoRoot().path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final beside = RegExp(
        r'\n## specstone_core/lib/src/index_query/git_ignore\.LICENSE\n(.*?)(?=\n## |$)',
        dotAll: true,
      ).firstMatch(out.readAsStringSync())?.group(1);
      expect(beside, isNotNull);
      expect(
        beside,
        contains('Redistribution and use in source and binary forms'),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // D15
  test('a source file adapted from other code with no license beside it '
      'fails the tool', () async {
    final root = await writeTree({
      'pubspec.yaml':
          'name: fixture_workspace\n'
          'publish_to: none\n'
          'environment:\n  sdk: ^3.13.0\n'
          'workspace:\n  - packages/specstone\n',
      'packages/specstone/pubspec.yaml':
          'name: specstone\n'
          'publish_to: none\n'
          'resolution: workspace\n'
          'environment:\n  sdk: ^3.13.0\n',
      'packages/specstone/lib/src/vendored.dart':
          '// Adapted from other_project/lib/x.dart.\nvoid vendored() {}\n',
      'packages/specstone_core/assets/mermaid/LICENSE': 'Mermaid license.\n',
    });
    final get = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
    ], workingDirectory: root.path);
    expect(get.exitCode, 0, reason: '${get.stderr}');
    final out = File('${root.path}/THIRD_PARTY_NOTICES');

    final r = await Process.run(Platform.resolvedExecutable, [
      'run',
      '${repoRoot().path}/tool/third_party_notices.dart',
      out.path,
    ], workingDirectory: root.path);

    expect(r.exitCode, 1);
    expect(r.stderr, contains('specstone/lib/src/vendored.dart'));
    expect(r.stderr, contains('vendored.LICENSE'));
    expect(out.existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  // D15: a doc comment is the file saying it too.
  for (final source in [
    'void vendored() {} // adapted from other_project/lib/x.dart\n',
    '/* adapted from other_project/lib/x.dart */\nvoid vendored() {}\n',
    '/// Adapted from other_project/lib/x.dart.\nvoid vendored() {}\n',
  ]) {
    test('a trailing, block, or doc comment saying code is adapted fails the '
        'tool: ${source.split('\n').first}', () async {
      final r = await _runNoticesOn(source);

      expect(r.exitCode, 1);
      expect(r.stderr, contains('vendored.LICENSE'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  // D15
  test('a string saying adapted from is not a notice trigger', () async {
    final r = await _runNoticesOn(
      "const note = '// adapted from nowhere';\n"
      "const doc = '/// adapted from nowhere';\n"
      'void vendored() {}\n',
    );

    expect(r.exitCode, 0, reason: '${r.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a runtime package added to the CLI later has its license in the '
      'notices', () async {
    final root = await writeTree({
      'pubspec.yaml':
          'name: fixture_workspace\n'
          'publish_to: none\n'
          'environment:\n  sdk: ^3.13.0\n'
          'workspace:\n  - packages/specstone\n',
      'packages/specstone/pubspec.yaml':
          'name: specstone\n'
          'publish_to: none\n'
          'resolution: workspace\n'
          'environment:\n  sdk: ^3.13.0\n'
          'dependencies:\n  added_later: {path: ../../added_later}\n',
      'added_later/pubspec.yaml':
          'name: added_later\n'
          'version: 4.5.6\n'
          'publish_to: none\n'
          'environment:\n  sdk: ^3.13.0\n',
      'added_later/lib/added_later.dart': '',
      'added_later/LICENSE': 'Added later license text.\n',
      'packages/specstone_core/assets/mermaid/LICENSE': 'Mermaid license.\n',
    });
    final get = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
    ], workingDirectory: root.path);
    expect(get.exitCode, 0, reason: '${get.stderr}');
    final out = File('${root.path}/THIRD_PARTY_NOTICES');

    final r = await Process.run(Platform.resolvedExecutable, [
      'run',
      '${repoRoot().path}/tool/third_party_notices.dart',
      out.path,
    ], workingDirectory: root.path);

    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(
      out.readAsStringSync(),
      contains('\n## added_later 4.5.6\n\nAdded later license text.'),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the release workflow writes the notices file at each release, and no '
      'copy is checked in', () {
    final workflow = loadYaml(
      File('${repoRoot().path}/.github/workflows/release.yaml')
          .readAsStringSync(),
    ) as YamlMap;
    final runs = [
      for (final job in (workflow['jobs'] as YamlMap).values)
        for (final step in ((job as YamlMap)['steps'] as YamlList?) ?? const [])
          '${(step as YamlMap)['run']}',
    ];

    expect(
      runs.where(
        (run) => run.contains('dart run tool/third_party_notices.dart'),
      ),
      hasLength(1),
    );
    expect(
      File('${repoRoot().path}/THIRD_PARTY_NOTICES').existsSync(),
      isFalse,
    );
  });

  test('a dependency with no license file fails the tool, '
      'naming it', () async {
    final root = await writeTree({
      'pubspec.yaml':
          'name: fixture_workspace\n'
          'publish_to: none\n'
          'environment:\n  sdk: ^3.13.0\n'
          'workspace:\n  - packages/specstone\n',
      'packages/specstone/pubspec.yaml':
          'name: specstone\n'
          'publish_to: none\n'
          'resolution: workspace\n'
          'environment:\n  sdk: ^3.13.0\n'
          'dependencies:\n  unlicensed: {path: ../../unlicensed}\n',
      'unlicensed/pubspec.yaml':
          'name: unlicensed\n'
          'version: 1.2.3\n'
          'publish_to: none\n'
          'environment:\n  sdk: ^3.13.0\n',
      'unlicensed/lib/unlicensed.dart': '',
    });
    final get = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
    ], workingDirectory: root.path);
    expect(get.exitCode, 0, reason: '${get.stderr}');
    final out = File('${root.path}/THIRD_PARTY_NOTICES');

    final r = await Process.run(Platform.resolvedExecutable, [
      'run',
      '${repoRoot().path}/tool/third_party_notices.dart',
      out.path,
    ], workingDirectory: root.path);

    expect(r.exitCode, 1);
    expect(r.stderr, contains('unlicensed'));
    expect(r.stderr, contains('LICENSE'));
    expect(out.existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
