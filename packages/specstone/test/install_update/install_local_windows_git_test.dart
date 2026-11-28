@Tags(['integration'])
@TestOn('windows')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/install_local_repo.dart';
import '../helpers/script_sandbox.dart';

void main() {
  test('Windows is refused before any git call and changes nothing', () async {
    final tool = await compileInstallLocal();
    final sandbox = await createScriptSandbox();
    sandbox
      ..installFake()
      ..stub('git', r'echo %* >> "%STUB_LOG_DIR%\git.log"');
    final before = sandbox.snapshot();

    final result = await Process.run(
      tool,
      const [],
      workingDirectory: sandbox.root.path,
      environment: sandbox.env(),
      includeParentEnvironment: false,
    );

    expect(result.exitCode, 1, reason: '${result.stderr}');
    expect(result.stderr, contains('macOS and Linux only'));
    expect(sandbox.logOf('git'), isEmpty);
    expect(sandbox.snapshot(), before);
  });
}
