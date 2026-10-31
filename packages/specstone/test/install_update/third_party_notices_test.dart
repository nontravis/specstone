@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';
import '../helpers/temp_tree.dart';

void main() {
  test(
    'f09/us04/fr06/e02, e03: the notices hold each runtime package, mermaid, '
    'and SQLite',
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
      expect(text, contains('## mermaid'));
      expect(text, contains('Permission is hereby granted'));
      expect(text, contains('## SQLite\n'));
      expect(text, isNot(contains('\n## test ')));
      expect(text, isNot(contains('\n## specstone_core ')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
