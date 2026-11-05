@TestOn('windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

/// Returns Git for Windows' `bash.exe`, or null when it is not installed.
String? findGitBash() {
  final localAppData = Platform.environment['LOCALAPPDATA'];
  final roots = [
    Platform.environment['ProgramFiles'],
    Platform.environment['ProgramFiles(x86)'],
    if (localAppData != null) '$localAppData\\Programs',
  ];
  for (final root in roots.nonNulls) {
    final bash = File('$root\\Git\\bin\\bash.exe');
    if (bash.existsSync()) return bash.path;
  }
  return null;
}

String _forward(String path) => path.replaceAll(r'\', '/');

void main() {
  final bash = findGitBash();

  test('install_update/warn_at_session_start/register_session_start_hook E10: '
      'Git Bash reads the appended line and resolves specstone.exe', () async {
    final sb = await createScriptSandbox();
    final pluginDir = '${sb.root.path}\\plugin';
    File('$pluginDir\\.claude-plugin\\plugin.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"name": "specstone", "version": "0.2.0"}\n');
    File('${sb.home.path}\\.specstone\\bin\\specstone.exe')
      ..createSync(recursive: true)
      ..writeAsStringSync('');
    final envFile = File('${sb.root.path}\\claude_env.sh')
      ..writeAsStringSync('');
    // Git Bash needs its own tools (uname, tr, sed, head) on the PATH, and
    // that folder must not hold specstone.
    final gitUsrBin = '${File(bash!).parent.parent.path}\\usr\\bin';
    final env = sb.env({
      'PATH': '$gitUsrBin;${sb.env()['PATH']}',
      'CLAUDE_PLUGIN_ROOT': _forward(pluginDir),
      'CLAUDE_ENV_FILE': _forward(envFile.path),
    });
    final script = _forward('${repoRoot().path}/plugin/hooks/session-start.sh');

    final hook = await Process.run(
      bash,
      [script],
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
  }, skip: bash == null ? 'Git for Windows is not installed' : null);
}
