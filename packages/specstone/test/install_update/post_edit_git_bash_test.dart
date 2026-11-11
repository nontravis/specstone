@TestOn('windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/hook_command.dart';
import '../helpers/plugin_content.dart';
import '../helpers/script_sandbox.dart';

String _forward(String path) => path.replaceAll(r'\', '/');

String _backward(String path) => path.replaceAll('/', r'\');

/// How Claude Code may spell `CLAUDE_PLUGIN_ROOT`, by label.
final _rootSpellings = <String, String Function(String)>{
  'a forward-slash CLAUDE_PLUGIN_ROOT': _forward,
  'a backslash CLAUDE_PLUGIN_ROOT': _backward,
};

void main() {
  final bash = findGitBash();

  for (final MapEntry(key: label, value: spell) in _rootSpellings.entries) {
    test('g8-r11: the PostToolUse command under Git Bash runs the absolute '
        'specstone, never a planted one; stdin and the exit status pass '
        'through, with $label', () async {
      final sb = await createScriptSandbox();
      plantHookPrograms(sb);
      // Git Bash runs a file that starts with `#!` without an `.exe`.
      File('${sb.stubs.path}\\specstone').writeAsStringSync(
        '#!/bin/sh\n'
        'echo "\$*" > "\$STUB_LOG_DIR/specstone.args"\n'
        'cat > "\$STUB_LOG_DIR/specstone.stdin"\n'
        'echo from the stub\n'
        'exit 3\n',
      );
      final gitUsrBin = '${File(bash!).parent.parent.path}\\usr\\bin';
      final pluginRootPath = pluginRoot().path.replaceFirst(
        RegExp(r'[\\/]$'),
        '',
      );

      final r = await runHookCommand(
        sb,
        'PostToolUse',
        shell: bash,
        path: '.;${sb.stubs.path};$gitUsrBin',
        pluginRootPath: spell(pluginRootPath),
        stdinText: '{"tool_name":"Edit"}\n',
        extra: {'STUB_LOG_DIR': _forward(sb.logs.path)},
      );

      expect(plantedHookProgramsThatRan(sb), isEmpty);
      expect(r.exitCode, 3, reason: '${r.stderr}');
      expect('${r.stdout}'.trim(), 'from the stub');
      expect(
        File('${sb.logs.path}\\specstone.args').readAsStringSync().trim(),
        'hook post-edit',
      );
      expect(
        File('${sb.logs.path}\\specstone.stdin').readAsStringSync(),
        '{"tool_name":"Edit"}\n',
      );
    }, skip: bash == null ? 'Git for Windows is not installed' : null);
  }
}
