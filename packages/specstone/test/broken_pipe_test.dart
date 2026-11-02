import 'dart:io';

import 'package:test/test.dart';

import 'helpers/built_cli.dart';
import 'helpers/temp_tree.dart';

// The reader `true` exits at once; the CLI starts a second later, so its
// first write meets a pipe whose reader has gone. `$0` is the CLI binary.
const _stdoutReaderGone =
    r'{ sleep 1; "$0" guide fr; echo "status=$?" >&3; } 3>&2 | true';
const _stderrReaderGone =
    r'{ sleep 1; "$0" guide no_such_type 2>&1 >/dev/null; '
    r'echo "status=$?" >&3; } 3>&2 | true';

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  Future<ProcessResult> runPipeline(String script) async {
    final working = await writeTree({});
    return Process.run('sh', [
      '-c',
      script,
      binary,
    ], workingDirectory: working.path);
  }

  group(
    'a reader that leaves before the CLI writes',
    () {
      test('stops the CLI quietly with status 141 when stdout is the '
          'broken pipe', () async {
        final result = await runPipeline(_stdoutReaderGone);

        expect(result.stderr, 'status=141\n');
      });

      test('stops the CLI quietly with status 141 when stderr is the '
          'broken pipe', () async {
        final result = await runPipeline(_stderrReaderGone);

        expect(result.stderr, 'status=141\n');
      });
    },
    skip: Platform.isWindows
        ? 'needs a POSIX shell pipeline to close the reader before the CLI '
              'writes; output_guard_test covers the Windows error codes'
        : false,
  );
}
