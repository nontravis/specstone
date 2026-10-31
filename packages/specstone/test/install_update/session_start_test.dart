@TestOn('!windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../helpers/plugin_content.dart';
import '../helpers/script_sandbox.dart';

void main() {
  const raw = 'https://raw.githubusercontent.com/nontravis/specstone/main';
  const curlLine = 'curl -fsSL $raw/install.sh | sh';
  const irmLine = 'irm $raw/install.ps1 | iex';
  const offPathMessage =
      'Specstone: the CLI is installed in ~/.specstone/bin but not on the '
      'PATH Claude Code sees. Start Claude Code from a terminal, or add '
      '~/.specstone/bin to the PATH Claude Code gets.';
  const mingw = 'MINGW64_NT-10.0-19045';

  late ScriptSandbox sb;
  late String pluginDir;

  setUp(() async {
    sb = await createScriptSandbox();
    pluginDir = '${sb.root.path}/plugin';
    File('$pluginDir/.claude-plugin/plugin.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"name": "specstone", "version": "0.2.0"}\n');
  });

  String scriptPath() => '${repoRoot().path}/plugin/hooks/session-start.sh';

  Map<String, String> hookEnv(Map<String, String> extra) => {
    'CLAUDE_PLUGIN_ROOT': pluginDir,
    ...extra,
  };

  /// Runs the hook with a `specstone` stub that prints [version] and exits
  /// [exit], or with no stub when [version] is null.
  Future<ProcessResult> runHook({
    String? version,
    int exit = 0,
    Map<String, String> extra = const {},
  }) {
    if (version != null) {
      sb.stub(
        'specstone',
        r'printf "%s" "$STUB_VERSION"; exit ${STUB_EXIT:-0}',
      );
    }
    return sb.run(
      scriptPath(),
      shell: '/bin/bash',
      extra: hookEnv({
        'STUB_VERSION': ?version,
        if (exit != 0) 'STUB_EXIT': '$exit',
        ...extra,
      }),
    );
  }

  /// Decodes the hook output, checks both keys carry one text, returns it.
  String message(ProcessResult r) {
    expect(r.exitCode, 0);
    final decoded = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    final specific = decoded['hookSpecificOutput'] as Map<String, dynamic>;
    expect(specific['hookEventName'], 'SessionStart');
    expect(decoded['systemMessage'], specific['additionalContext']);
    return decoded['systemMessage'] as String;
  }

  void installBinary(String name) {
    final file = File('${sb.home.path}/.specstone/bin/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\necho 0.2.0\n');
    Process.runSync('chmod', ['755', file.path]);
  }

  String mismatch(String cli, String plugin) =>
      'Specstone: the CLI is $cli and the plugin is $plugin. '
      'Run: specstone upgrade';

  group('session-start.sh', () {
    test(
      'f09/us05/fr02, f09/us05/s1: equal versions print nothing; exit 0',
      () async {
        final r = await runHook(version: '0.2.0');

        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
      },
    );

    test(
      'f09/us05/fr02/e01, f09/us05/s2: an older CLI gets the mismatch message',
      () async {
        expect(
          message(await runHook(version: '0.1.0')),
          mismatch('0.1.0', '0.2.0'),
        );
      },
    );

    test(
      'f09/us05/fr02/e02, f09/us05/s3: an older plugin gets the same message',
      () async {
        expect(
          message(await runHook(version: '0.3.0')),
          mismatch('0.3.0', '0.2.0'),
        );
      },
    );

    test(
      'f09/us05/fr02/e03: trailing newlines of --version are trimmed',
      () async {
        final r = await runHook(version: '0.2.0\n\n');

        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
      },
    );

    test('f09/us05/fr02, f09/us05/s6: a failing --version gets the reinstall '
        'message', () async {
      expect(
        message(await runHook(version: '0.2.0', exit: 1)),
        'Specstone: the CLI did not report its version. '
        'Reinstall it: $curlLine',
      );
    });

    test('f09/us05/fr02: a --version that prints nothing gets the reinstall '
        'message', () async {
      expect(
        message(await runHook(version: '\n')),
        'Specstone: the CLI did not report its version. '
        'Reinstall it: $curlLine',
      );
    });

    test('f09/us05/fr03/e01, f09/us05/s4: an installed CLI off the PATH gets '
        'the off-PATH message', () async {
      installBinary('specstone');

      expect(message(await runHook()), offPathMessage);
    });

    test('f09/us05/fr03/e02, f09/us05/s5: no CLI on macOS or Linux names the '
        'curl line', () async {
      for (final uname in ['Darwin', 'Linux']) {
        expect(
          message(await runHook(extra: {'STUB_UNAME_S': uname})),
          'Specstone: the CLI is not installed. Install it: $curlLine',
        );
      }
    });

    test('f09/us05/fr03/e03: Git Bash on Windows names the irm line and finds '
        'specstone.exe', () async {
      for (final uname in [mingw, 'MSYS_NT-10.0', 'CYGWIN_NT-10.0']) {
        expect(
          message(await runHook(extra: {'STUB_UNAME_S': uname})),
          'Specstone: the CLI is not installed. Install it: $irmLine',
        );
      }
      installBinary('specstone.exe');

      expect(
        message(await runHook(extra: {'STUB_UNAME_S': mingw})),
        offPathMessage,
      );
    });

    test(
      'f09/us05/fr03: a reinstall message on Git Bash names the irm line',
      () async {
        expect(
          message(
            await runHook(
              version: '0.2.0',
              exit: 1,
              extra: {'STUB_UNAME_S': mingw},
            ),
          ),
          'Specstone: the CLI did not report its version. '
          'Reinstall it: $irmLine',
        );
      },
    );

    test('f09/us05/fr03: USERPROFILE stands in for a missing HOME', () async {
      installBinary('specstone');

      final r = await runHook(extra: {'HOME': '', 'USERPROFILE': sb.home.path});

      expect(message(r), offPathMessage);
    });

    test(
      'f09/us05/fr02/e04, INV-9: the script writes nothing, opens no network, '
      'and reads no stdin',
      () async {
        for (final tool in ['curl', 'wget']) {
          sb.stub(tool, r'echo "$0 $*" >> "$STUB_LOG_DIR/net.log"');
        }
        sb.stub('specstone', r'printf "%s" "$STUB_VERSION"');
        final tmp = Directory(sb.env()['TMPDIR']!);
        List<String> files(Directory d) =>
            d.listSync(recursive: true).map((e) => e.path).toList()..sort();
        final homeBefore = sb.snapshot();
        final tmpBefore = files(tmp);

        // An open stdin pipe that is never closed: a script that reads
        // stdin would block here until the timeout.
        final process = await Process.start(
          '/bin/bash',
          [scriptPath()],
          environment: sb.env(hookEnv({'STUB_VERSION': '0.1.0'})),
          includeParentEnvironment: false,
          workingDirectory: sb.root.path,
        );
        final stdout = process.stdout.transform(utf8.decoder).join();
        unawaited(process.stderr.drain<void>());
        final code = await process.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );

        expect(code, 0);
        expect(await stdout, contains('specstone upgrade'));
        expect(sb.snapshot(), homeBefore);
        expect(files(tmp), tmpBefore);
        expect(sb.logOf('net'), isEmpty);
      },
    );

    test('f09/us05/fr02: a version holding a quote or a backslash still gives '
        'valid JSON', () async {
      const version = r'0.1.0"x\';

      expect(message(await runHook(version: version)), contains(version));
    });

    test('f09/us05/fr02: a version holding a tab or a newline still gives '
        'valid JSON', () async {
      const version = '0.1.0\tx\ny';

      expect(
        message(await runHook(version: version)),
        mismatch(version, '0.2.0'),
      );
    });

    test(
      'f09/us05/fr02: an unreadable plugin version prints nothing',
      () async {
        File('$pluginDir/.claude-plugin/plugin.json').deleteSync();

        final r = await runHook(version: '0.1.0');

        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
      },
    );

    test('f09/us05/fr01: hooks.json holds the SessionStart entry beside the '
        'unchanged PostToolUse entry', () {
      final decoded = jsonDecode(
        File.fromUri(pluginRoot().uri.resolve('hooks/hooks.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;

      expect((decoded['hooks'] as Map<String, dynamic>)['SessionStart'], [
        {
          'hooks': [
            {
              'type': 'command',
              'command': r'bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"',
              'timeout': 10,
            },
          ],
        },
      ]);
    });

    test('f09/us05/fr01/e02: git keeps every .sh at LF', () async {
      final r = await Process.run('git', [
        'check-attr',
        'eol',
        '--',
        'install.sh',
        'uninstall.sh',
        'plugin/hooks/session-start.sh',
      ], workingDirectory: repoRoot().path);

      final lines = LineSplitter.split(r.stdout as String).toList();
      expect(lines, hasLength(3));
      expect(lines, everyElement(endsWith('eol: lf')));
    });
  });
}
