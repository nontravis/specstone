import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/upgrade_command.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../specstone_core/test/helpers/write_fixture.dart' show testHome;
import '../helpers/built_cli.dart';
import '../helpers/temp_tree.dart';

const _lead = "specstone: this project's agent files";
const _older =
    '$_lead are older than specstone $specstoneVersion; run specstone migrate';
const _differ =
    '$_lead differ from what specstone $specstoneVersion writes; run '
    'specstone migrate';
const _above = '99.0.0';
const _newer =
    '$_lead come from specstone $_above, newer than this specstone '
    '$specstoneVersion; run specstone upgrade';
const _staleAgentMd = {'.specstone/AGENT.md': 'old\n'};

final _rootName = RegExp(r'specstone_test_\w+');

String _withoutRoot(Object? text) => '$text'.replaceAll(_rootName, '_');

// `$0` is the CLI binary; stdout goes to the null device, stderr to the pipe.
const _stderrReaderGone =
    r'{ sleep 1; "$0" folder 2>&1 >/dev/null; echo "status=$?" >&3; } 3>&2 | true';

void main() {
  late String binary;

  setUpAll(() async => binary = await buildSpecstone());

  Future<ProcessResult> run(
    Directory root,
    List<String> args, {
    String stdin = '',
  }) async {
    final process = await Process.start(
      binary,
      args,
      workingDirectory: root.path,
      environment: {'HOME': testHome().path, 'USERPROFILE': testHome().path},
    );
    process.stdin.write(stdin);
    await process.stdin.close();
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    return ProcessResult(
      process.pid,
      await process.exitCode,
      await out,
      await err,
    );
  }

  Future<Directory> project({
    String config = '',
    Map<String, String> files = _staleAgentMd,
  }) => writeTree({
    '.specstone/config.yaml': '${shippedPinsConfig()}$config',
    ...files,
  });

  group('a yes row prints the line after its own output', () {
    for (final args in [
      ['folder'],
      ['guide', 'fr'],
      ['structure'],
    ]) {
      test('${args.join(' ')} keeps its stdout and exit status', () async {
        final stale = await run(await project(), args);
        final current = await run(await project(files: const {}), args);

        expect(stale.exitCode, 0, reason: '${stale.stderr}');
        expect(stale.stderr, '$_older\n');
        expect(current.stderr, isEmpty);
        expect(_withoutRoot(stale.stdout), _withoutRoot(current.stdout));
        expect(current.exitCode, stale.exitCode);
      });
    }

    for (final args in [
      ['get', 'nope'],
      ['check', 'nope'],
    ]) {
      test('the failing ${args.join(' ')} keeps its exit status and its own '
          'stderr first', () async {
        final stale = await run(await project(), args);
        final current = await run(await project(files: const {}), args);

        expect(stale.exitCode, isNonZero);
        expect(stale.exitCode, current.exitCode);
        expect(stale.stdout, current.stdout);
        expect(stale.stderr, '${current.stderr}$_older\n');
      });
    }
  });

  group('a no row prints no line', () {
    test('check with no target names the file itself', () async {
      final result = await run(await project(), ['check']);

      expect(result.stdout, contains('agent_block_stale'));
      expect(result.stderr, isNot(contains(_lead)));
    });

    test(
      'migrate and init, each refused and leaving the files stale',
      () async {
        final root = await project();
        final migrate = await run(root, ['migrate']);
        final init = await run(root, ['init']);

        expect(migrate.exitCode, isNonZero);
        expect(migrate.stderr, contains('git'));
        expect(migrate.stderr, isNot(contains(_lead)));
        expect(init.exitCode, isNonZero);
        expect(init.stderr, contains('already a Specstone project'));
        expect(init.stderr, isNot(contains(_lead)));
      },
    );

    test('upgrade, refused where this CLI is not the managed one', () async {
      final root = await project();
      final err = StringBuffer();
      final runner = SpecstoneCommandRunner(
        out: StringBuffer(),
        err: err,
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: testHome(),
        environment: const {},
        upgrade: UpgradeCommand(
          runningVersion: specstoneVersion,
          executable: '${root.path}/elsewhere/specstone',
          environment: const {},
        ),
      );

      final status = await runner.run(['upgrade']);

      expect(status, isNonZero);
      expect(err.toString(), contains('installed in ~/.specstone/bin'));
      expect(err.toString(), isNot(contains(_lead)));
    });

    test('hook post-edit', () async {
      final result = await run(await project(), ['hook', 'post-edit']);

      expect(result.stderr, isNot(contains(_lead)));
    });

    test('--version, --help, and help', () async {
      for (final args in [
        ['--version'],
        ['--help'],
        ['help'],
        ['folder', '--help'],
      ]) {
        final result = await run(await project(), args);

        expect(result.stderr, isNot(contains(_lead)), reason: args.join(' '));
      }
    });

    test('mcp', () async {
      final result = await run(await project(), ['mcp']);

      expect(result.stderr, isNot(contains(_lead)));
    });

    test('a command refused on a pin prints the refusal alone', () async {
      final root = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig().replaceFirst(
          RegExp(r'prd-core: \S+'),
          'prd-core: 1.0.0',
        ),
        ..._staleAgentMd,
      });

      final result = await run(root, ['guide', 'fr']);

      expect(result.exitCode, isNonZero);
      expect(result.stderr, contains('Pack prd-core is pinned at 1.0.0'));
      expect(result.stderr, isNot(contains(_lead)));
    });

    test('a project whose agent files match prints none', () async {
      final result = await run(await project(files: const {}), ['folder']);

      expect(result.stderr, isEmpty);
    });
  });

  group('the line form follows the stamp', () {
    for (final (config, line) in [
      ('', _older),
      ('agent_files_version: 0.0.1\n', _older),
      ('agent_files_version: $specstoneVersion\n', _differ),
      ('agent_files_version: $_above\n', _newer),
    ]) {
      test(config.isEmpty ? 'no stamp' : config.trim(), () async {
        final result = await run(await project(config: config), ['folder']);

        expect(result.stderr, '$line\n');
      });
    }

    test('a stamp that does not read prints none', () async {
      final result = await run(
        await project(config: 'agent_files_version: nope\n'),
        ['folder'],
      );

      expect(result.stderr, isEmpty);
    });

    test('a stamp above with every file current prints none', () async {
      final result = await run(
        await project(
          config: 'agent_files_version: $_above\n',
          files: const {},
        ),
        ['folder'],
      );

      expect(result.stderr, isEmpty);
    });
  });

  group('the project root alone', () {
    const top = {
      'app/.git/HEAD': 'ref\n',
      'app/AGENTS.md':
          '<!-- BEGIN specstone v1.0.0 -->\nold\n<!-- END specstone -->\n',
    };

    test('a stale file at a listed top alone prints none', () async {
      final root = await project(
        config: 'code_root: app\nagent_file_roots:\n  - app\n',
        files: top,
      );

      expect((await run(root, ['folder'])).stderr, isEmpty);
    });

    test('a stale file at an unlisted top alone prints none', () async {
      final root = await project(config: 'code_root: app\n', files: top);

      expect((await run(root, ['folder'])).stderr, isEmpty);
    });

    test('a broken agent_file_roots list still prints the line', () async {
      final root = await project(config: 'agent_file_roots: 5\n');

      expect((await run(root, ['folder'])).stderr, '$_older\n');
    });
  });

  group(
    'a stderr reader that leaves before the line is written',
    () {
      test("leaves the exit status the command's own", () async {
        final root = await project();

        // The reader `true` exits at once; the CLI starts a second later,
        // so the line is its only stderr write and meets a broken pipe.
        final result = await Process.run('sh', [
          '-c',
          _stderrReaderGone,
          binary,
        ], workingDirectory: root.path);

        expect(result.stderr, 'status=0\n');
      });
    },
    skip: Platform.isWindows
        ? 'needs a POSIX shell pipeline to close the reader before the CLI '
              'writes'
        : false,
  );

  group('a line that cannot be written', () {
    test('leaves the command output and exit status its own', () async {
      final root = await project();
      final out = StringBuffer();
      final runner = SpecstoneCommandRunner(
        out: out,
        err: _ClosedSink(),
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: testHome(),
        environment: const {},
      );

      final status = await runner.run(['folder']);

      expect(status, 0);
      expect(out.toString(), contains('.specstone'));
    });
  });
}

/// A stream that is closed: every write throws.
final class _ClosedSink implements StringSink {
  @override
  void write(Object? object) => throw const FileSystemException('closed');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      throw const FileSystemException('closed');

  @override
  void writeCharCode(int charCode) => throw const FileSystemException('closed');

  @override
  void writeln([Object? object = '']) =>
      throw const FileSystemException('closed');
}
