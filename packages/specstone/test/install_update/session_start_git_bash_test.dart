@TestOn('windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/hook_command.dart';
import '../helpers/script_sandbox.dart';

String _forward(String path) => path.replaceAll(r'\', '/');

/// How Claude Code may spell `CLAUDE_PLUGIN_ROOT`, by label.
final _rootSpellings = <String, String Function(String)>{
  'a forward-slash CLAUDE_PLUGIN_ROOT': _forward,
  'a backslash CLAUDE_PLUGIN_ROOT': (path) => path,
};

void main() {
  final bash = findGitBash();
  final skip = bash == null ? 'Git for Windows is not installed' : null;

  /// Returns a sandbox plugin folder with the two SessionStart scripts of the
  /// shipped plugin and a `plugin.json` of version 0.2.0.
  String writePlugin(ScriptSandbox sb) {
    final pluginDir = '${sb.root.path}\\plugin';
    File('$pluginDir\\.claude-plugin\\plugin.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"name": "specstone", "version": "0.2.0"}\n');
    Directory('$pluginDir\\hooks').createSync();
    for (final name in ['session-start.sh', 'session-start-launcher.sh']) {
      File('${repoRoot().path}\\plugin\\hooks\\$name')
          .copySync('$pluginDir\\hooks\\$name');
    }
    return pluginDir;
  }

  // Git Bash needs its own tools (uname, tr, sed, head) on the PATH, and that
  // folder must not hold specstone.
  String gitUsrBin() => '${File(bash!).parent.parent.path}\\usr\\bin';

  for (final MapEntry(key: label, value: spell) in _rootSpellings.entries) {
    test('install_update/warn_at_session_start/register_session_start_hook '
        'E10: Git Bash reads the appended line and resolves specstone.exe '
        'with $label', () async {
      final sb = await createScriptSandbox();
      final pluginDir = writePlugin(sb);
      File('${sb.home.path}\\.specstone\\bin\\specstone.exe')
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      final envFile = File('${sb.root.path}\\claude_env.sh')
        ..writeAsStringSync('');
      final env = sb.env({
        'PATH': '${gitUsrBin()};${sb.env()['PATH']}',
        'CLAUDE_PLUGIN_ROOT': spell(pluginDir),
        'CLAUDE_ENV_FILE': _forward(envFile.path),
      });
      // The command as hooks.json states it: /bin/sh and the launcher.
      final hook = await Process.run(
        bash!,
        ['-c', hookCommandOf('SessionStart')],
        environment: env,
        includeParentEnvironment: false,
        workingDirectory: sb.root.path,
      );
      final session = await Process.run(
        bash,
        ['-c', r'. "$CLAUDE_ENV_FILE" && command -v specstone'],
        environment: env,
        includeParentEnvironment: false,
        workingDirectory: sb.root.path,
      );

      expect(hook.exitCode, 0, reason: '${hook.stderr}');
      expect(
        envFile.readAsStringSync(),
        r'export PATH="$HOME/.specstone/bin:$PATH"'
        '\n',
      );
      expect(session.exitCode, 0, reason: '${session.stderr}');
      // MSYS may print the match with or without its `.exe`.
      expect(
        '${session.stdout}'.trim().toLowerCase(),
        matches(RegExp(r'/\.specstone/bin/specstone(\.exe)?$')),
      );
    }, skip: skip);

    test('g8-r11: a dot on PATH never starts a planted program under Git '
        'Bash, with $label', () async {
      final sb = await createScriptSandbox();
      plantHookPrograms(sb);
      final pluginDir = writePlugin(sb);

      final r = await runHookCommand(
        sb,
        'SessionStart',
        shell: bash!,
        path: '.;${gitUsrBin()};${sb.env()['PATH']}',
        pluginRootPath: spell(pluginDir),
        extra: {'STUB_LOG_DIR': _forward(sb.logs.path)},
      );

      expect(plantedHookProgramsThatRan(sb), isEmpty);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, contains('the CLI is not installed'));
    }, skip: skip);
  }
}
