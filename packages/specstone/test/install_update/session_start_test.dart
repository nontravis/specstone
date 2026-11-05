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

    group('CLAUDE_ENV_FILE', () {
      const hookPathLine = 'export PATH="\$HOME/.specstone/bin:\$PATH"\n';
      const hookPutMessage =
          'Specstone: the CLI is installed in ~/.specstone/bin, and this '
          "session's later commands get it from the hook, but the PATH "
          'Claude Code starts with still lacks it. Start Claude Code from a '
          'terminal, or add ~/.specstone/bin to the PATH Claude Code gets.';
      const notInstalledMessage =
          'Specstone: the CLI is not installed. Install it: $curlLine';

      File envFile([String content = '']) =>
          File('${sb.root.path}/claude_env.sh')..writeAsStringSync(content);

      test('install_update/warn_at_session_start/register_session_start_hook '
          'E06: off the PATH with the binary present, the line is appended '
          'to the file', () async {
        installBinary('specstone');
        final env = envFile('# kept\n');

        final r = await runHook(extra: {'CLAUDE_ENV_FILE': env.path});

        expect(message(r), hookPutMessage);
        expect(env.readAsStringSync(), '# kept\n$hookPathLine');
      });

      test(
        'install_update/warn_at_session_start/register_session_start_hook '
        'E06: a file without a final line feed keeps its last line whole',
        () async {
          installBinary('specstone');
          final env = envFile('# kept');

          await runHook(extra: {'CLAUDE_ENV_FILE': env.path});

          expect(env.readAsStringSync(), '# kept\n$hookPathLine');
        },
      );

      test('install_update/warn_at_session_start/register_session_start_hook '
          'E06: a second run appends again and truncates nothing', () async {
        installBinary('specstone');
        final env = envFile();

        await runHook(extra: {'CLAUDE_ENV_FILE': env.path});
        await runHook(extra: {'CLAUDE_ENV_FILE': env.path});

        expect(env.readAsStringSync(), '$hookPathLine$hookPathLine');
      });

      test('install_update/warn_at_session_start/register_session_start_hook '
          'E07: specstone on the PATH appends nothing', () async {
        installBinary('specstone');
        final env = envFile('# kept\n');

        final r = await runHook(
          version: '0.2.0',
          extra: {'CLAUDE_ENV_FILE': env.path},
        );

        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
        expect(env.readAsStringSync(), '# kept\n');
      });

      test('install_update/warn_at_session_start/register_session_start_hook '
          'E08: an unset CLAUDE_ENV_FILE appends nothing and the off-PATH '
          'message says the CLI is not on the PATH Claude Code sees', () async {
        installBinary('specstone');

        final r = await runHook();

        expect(message(r), offPathMessage);
        expect(sb.snapshot().keys, ['.specstone/bin/specstone']);
      });

      test('install_update/warn_at_session_start/register_session_start_hook '
          'E08: an empty CLAUDE_ENV_FILE appends nothing and gets the same '
          'message', () async {
        installBinary('specstone');
        final cwd = Directory('${sb.root.path}/cwd')..createSync();

        final r = await Process.run(
          '/bin/bash',
          [scriptPath()],
          environment: sb.env(hookEnv({}))..['CLAUDE_ENV_FILE'] = '',
          includeParentEnvironment: false,
          workingDirectory: cwd.path,
        );

        expect(message(r), offPathMessage);
        expect(cwd.listSync(), isEmpty);
        expect(sb.snapshot().keys, ['.specstone/bin/specstone']);
      });

      test('install_update/warn_at_session_start/register_session_start_hook '
          'E09: no binary appends nothing and the not-installed message '
          'shows', () async {
        final env = envFile('# kept\n');

        final r = await runHook(extra: {'CLAUDE_ENV_FILE': env.path});

        expect(message(r), notInstalledMessage);
        expect(env.readAsStringSync(), '# kept\n');
      });

      test('install_update/warn_at_session_start/find_missing_cli E04: with '
          'CLAUDE_ENV_FILE set the message names the hook; without it the '
          'message does not', () async {
        installBinary('specstone');

        final withFile = message(
          await runHook(extra: {'CLAUDE_ENV_FILE': envFile().path}),
        );
        final without = message(await runHook());

        expect(withFile, hookPutMessage);
        expect(without, offPathMessage);
        expect(withFile, isNot(without));
      });

      test('install_update/warn_at_session_start/register_session_start_hook '
          'E06: an env file in a missing folder still exits 0 with a message '
          'that does not claim the hook put the folder on the PATH', () async {
        installBinary('specstone');
        final missing = '${sb.root.path}/no_such_folder/claude_env.sh';

        final r = await runHook(extra: {'CLAUDE_ENV_FILE': missing});

        expect(message(r), offPathMessage);
        expect(File(missing).existsSync(), isFalse);
      });

      test('install_update/warn_at_session_start/register_session_start_hook '
          'E06: a read-only env file still exits 0 with that message and '
          'stays as it was', () async {
        installBinary('specstone');
        final env = envFile('# kept\n');
        Process.runSync('chmod', ['444', env.path]);
        addTearDown(() => Process.runSync('chmod', ['644', env.path]));

        final r = await runHook(extra: {'CLAUDE_ENV_FILE': env.path});

        expect(message(r), offPathMessage);
        expect(env.readAsStringSync(), '# kept\n');
      });
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

    test('f09/us05/fr02: a plugin version holding a backslash or a tab still '
        'gives valid JSON', () async {
      const plugin = '1.0\\q\tz';
      File('$pluginDir/.claude-plugin/plugin.json')
          .writeAsStringSync('{"name": "specstone", "version": "$plugin"}\n');

      expect(
        message(await runHook(version: '0.1.0')),
        mismatch('0.1.0', plugin),
      );
    });

    const failed =
        'Specstone: the CLI did not report its version. '
        'Reinstall it: $curlLine';

    test('f09/us05/fr02: a hung --version is cut off and gets the reinstall '
        'message', () async {
      sb.stub('specstone', 'sleep 30');
      final watch = Stopwatch()..start();

      final r = await sb.run(
        scriptPath(),
        shell: '/bin/bash',
        extra: hookEnv({}),
      );

      expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
      expect(message(r), failed);
    });

    for (final (name, body) in [
      ('prints endlessly', 'yes'),
      ('ignores TERM', "trap '' TERM; sleep 30"),
    ]) {
      test('f09/us05/fr02: a --version that $name is cut off and gets the '
          'reinstall message', () async {
        sb.stub('specstone', body);
        final watch = Stopwatch()..start();

        final r = await sb.run(
          scriptPath(),
          shell: '/bin/bash',
          extra: hookEnv({}),
        );

        expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
        expect(message(r), failed);
      });
    }

    test('f09/us05/fr02: the version check never calls timeout, whose -k '
        'misses a grandchild on uutils coreutils', () async {
      sb.stub('timeout', r'echo "$0 $*" >> "$STUB_LOG_DIR/timeout.log"');

      final r = await runHook(version: '0.2.0');

      expect(r.exitCode, 0);
      expect(r.stdout, isEmpty);
      expect(sb.logOf('timeout'), isEmpty);
    });

    test(
      'f09/us05/fr02: a 100,000-byte version gets the reinstall message',
      () async {
        final watch = Stopwatch()..start();

        final r = await runHook(version: '1' * 100000);

        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
        expect(message(r), failed);
      },
    );

    test(
      'f09/us05/fr02: a non-ASCII version gets the reinstall message',
      () async {
        expect(message(await runHook(version: '0.2.0\u00e9')), failed);
      },
    );

    test(
      'f09/us05/fr02: a version with leading spaces is trimmed and matches',
      () async {
        final r = await runHook(version: '  0.2.0 ');

        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
      },
    );

    test('f09/us05/fr02: a minified plugin.json with a nested version uses the '
        'top-level one', () async {
      File('$pluginDir/.claude-plugin/plugin.json').writeAsStringSync(
        '{"name":"specstone","version":"0.2.0",'
        '"deps":{"version":"9.9.9"}}',
      );

      final r = await runHook(version: '0.2.0');

      expect(r.exitCode, 0);
      expect(r.stdout, isEmpty);
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
