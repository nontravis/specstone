@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/hook_command.dart';
import '../helpers/script_sandbox.dart';

void main() {
  late ScriptSandbox sb;

  setUp(() async {
    sb = await createScriptSandbox();
    plantHookPrograms(sb);
    sb.stub('specstone', r'''
echo "$*" > "$STUB_LOG_DIR/specstone.args"
cat > "$STUB_LOG_DIR/specstone.stdin"
echo "from the stub"
exit ${STUB_EXIT:-0}''');
  });

  Future<ProcessResult> runPostEdit({
    required String path,
    String? stdinText,
    Map<String, String> extra = const {},
  }) => runHookCommand(
    sb,
    'PostToolUse',
    path: path,
    stdinText: stdinText,
    extra: extra,
  );

  String logged(String name) =>
      File('${sb.logs.path}/$name').readAsStringSync();

  group('post-edit hook (G8-R11)', () {
    test('the command starts its script through an absolute shell', () {
      expect(hookCommandOf('PostToolUse'), startsWith('/bin/sh '));
    });

    test('runs the absolute specstone with hook post-edit; stdin and stdout '
        'pass through', () async {
      final r = await runPostEdit(
        path: '${sb.stubs.path}:/usr/bin:/bin',
        stdinText: '{"tool_name":"Edit"}\n',
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, 'from the stub\n');
      expect(logged('specstone.args'), 'hook post-edit\n');
      expect(logged('specstone.stdin'), '{"tool_name":"Edit"}\n');
      expect(plantedHookProgramsThatRan(sb), isEmpty);
    });

    test('keeps the exit status of specstone', () async {
      final r = await runPostEdit(
        path: '${sb.stubs.path}:/usr/bin:/bin',
        extra: {'STUB_EXIT': '3'},
      );

      expect(r.exitCode, 3);
    });

    for (final MapEntry(key: label, value: path)
        in hookPathsWithRelativeEntries('STUBS').entries) {
      test('$label on PATH never starts a planted program; the absolute '
          'specstone runs', () async {
        final r = await runPostEdit(
          path: path.replaceAll('STUBS', sb.stubs.path),
          stdinText: 'in\n',
        );

        expect(plantedHookProgramsThatRan(sb), isEmpty);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(logged('specstone.args'), 'hook post-edit\n');
        expect(logged('specstone.stdin'), 'in\n');
      });
    }

    test('a PATH of relative entries only starts no planted program', () async {
      final r = await runPostEdit(path: '.::bin');

      expect(plantedHookProgramsThatRan(sb), isEmpty);
      expect(r.exitCode, isNot(0));
    });

    test('a trailing empty entry on PATH finds no planted specstone', () async {
      File('${sb.stubs.path}/specstone').deleteSync();

      final r = await runPostEdit(path: '${sb.stubs.path}:/usr/bin:/bin:');

      expect(plantedHookProgramsThatRan(sb), isEmpty);
      expect(r.exitCode, isNot(0));
    });
  });
}
