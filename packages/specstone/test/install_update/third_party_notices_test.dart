@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';
import '../helpers/temp_tree.dart';

void main() {
  test(
    'f09/us04/fr06/e02, e03: the notices hold each runtime package, mermaid, '
    'the Dart SDK, and SQLite',
    () async {
      final out = File('${(await writeTree({})).path}/THIRD_PARTY_NOTICES');
      final r = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/third_party_notices.dart',
        out.path,
      ], workingDirectory: repoRoot().path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final text = out.readAsStringSync();
      for (final name in [
        'args',
        'dart_mcp',
        'markdown',
        'crypto',
        'yaml',
        'sqlite3',
      ]) {
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
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('f09/us04/fr06/e03: a dependency with no license file fails the tool, '
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
