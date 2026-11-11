import 'dart:convert';
import 'dart:io';

import 'plugin_content.dart';
import 'script_sandbox.dart';

/// Names that the planted-program tests put in the run folder and in a
/// relative `bin` folder; a planted program only records that it ran.
const hookPlantedNames = [
  'specstone',
  'bash',
  'sh',
  'uname',
  'tr',
  'sed',
  'head',
  'tail',
  'sleep',
  'kill',
  'cat',
];

/// Returns the one command of the [event] hook in the plugin's `hooks.json`.
String hookCommandOf(String event) {
  final decoded = jsonDecode(
    File.fromUri(pluginRoot().uri.resolve('hooks/hooks.json'))
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final entries =
      (decoded['hooks'] as Map<String, dynamic>)[event] as List<dynamic>;
  final hooks =
      (entries.single as Map<String, dynamic>)['hooks'] as List<dynamic>;
  return (hooks.single as Map<String, dynamic>)['command'] as String;
}

/// Plants every [hookPlantedNames] program in the run folder and in `bin`
/// below it.
///
/// Git Bash runs a file that starts with `#!` without an execute bit.
void plantHookPrograms(ScriptSandbox sb) {
  for (final folder in ['.', 'bin']) {
    for (final name in hookPlantedNames) {
      final file = File('${sb.root.path}/$folder/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\n: > "\$STUB_LOG_DIR/planted-$name.ran"\n',
        );
      if (!Platform.isWindows) Process.runSync('chmod', ['755', file.path]);
    }
  }
}

/// Returns the planted programs that ran.
List<String> plantedHookProgramsThatRan(ScriptSandbox sb) => [
  for (final name in hookPlantedNames)
    if (File('${sb.logs.path}/planted-$name.ran').existsSync()) name,
];

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

/// Runs the [event] hook's command from `hooks.json` through `[shell] -c`,
/// in the sandbox's run folder, with `CLAUDE_PLUGIN_ROOT` set to
/// [pluginRootPath] (default: the shipped plugin folder) and [path] as PATH.
Future<ProcessResult> runHookCommand(
  ScriptSandbox sb,
  String event, {
  required String path,
  String shell = '/bin/sh',
  String? pluginRootPath,
  String? stdinText,
  Map<String, String> extra = const {},
}) async {
  final pluginRootValue =
      pluginRootPath ?? pluginRoot().path.replaceFirst(RegExp(r'/$'), '');
  final process = await Process.start(
    shell,
    ['-c', hookCommandOf(event)],
    environment: sb.env({
      'PATH': path,
      'CLAUDE_PLUGIN_ROOT': pluginRootValue,
      ...extra,
    }),
    includeParentEnvironment: false,
    workingDirectory: sb.root.path,
  );
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  if (stdinText != null) process.stdin.write(stdinText);
  await process.stdin.close().catchError((Object _) {});
  return ProcessResult(
    process.pid,
    await process.exitCode,
    await stdout,
    await stderr,
  );
}

/// The PATH values that each hold a relative entry before the absolute
/// [stubs] folder, by label.
Map<String, String> hookPathsWithRelativeEntries(String stubs) => {
  'a dot': '.:$stubs:/usr/bin:/bin',
  'a leading empty entry': ':$stubs:/usr/bin:/bin',
  'a middle empty entry': '$stubs::/usr/bin:/bin',
  'a relative folder': 'bin:$stubs:/usr/bin:/bin',
  'a dot, an empty entry, and a relative folder': '.::bin:$stubs:/usr/bin:/bin',
};
