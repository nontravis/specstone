import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

const usageLine = 'Usage: specstone <command> [arguments]';

void main() {
  group('SpecstoneCommandRunner', () {
    late StringBuffer out;
    late StringBuffer err;
    late SpecstoneCommandRunner runner;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
      runner = SpecstoneCommandRunner(out: out, err: err);
    });

    test('--version prints the core version and exits 0', () async {
      expect(await runner.run(['--version']), 0);
      expect(out.toString(), '$specstoneVersion\n');
      expect(err.toString(), isEmpty);
    });

    test('no arguments prints the usage and exits 0', () async {
      expect(await runner.run([]), 0);
      expect(out.toString(), contains(usageLine));
    });

    test('--help prints the generated usage and exits 0', () async {
      expect(await runner.run(['--help']), 0);
      expect(out.toString(), contains(usageLine));
      expect(out.toString(), contains('--version'));
      expect(out.toString(), contains('mcp'));
    });

    test('mcp --help prints the mcp usage to out and exits 0', () async {
      expect(await runner.run(['mcp', '--help']), 0);
      expect(
        out.toString(),
        contains('Run the Specstone MCP server over stdio.'),
      );
      expect(err.toString(), isEmpty);
    });

    test('help mcp prints the mcp usage to out and exits 0', () async {
      expect(await runner.run(['help', 'mcp']), 0);
      expect(out.toString(), contains('Usage: specstone mcp'));
      expect(err.toString(), isEmpty);
    });

    test('an unknown command prints usage to stderr and exits 64', () async {
      expect(await runner.run(['nope']), usageExitCode);
      expect(err.toString(), contains('Could not find a command named "nope"'));
      expect(err.toString(), contains(usageLine));
      expect(out.toString(), isEmpty);
    });

    test('an unknown option prints usage to stderr and exits 64', () async {
      expect(await runner.run(['--bogus']), usageExitCode);
      expect(
        err.toString(),
        contains('Could not find an option named "--bogus"'),
      );
      expect(out.toString(), isEmpty);
    });

    test('--version with a trailing unknown command exits 64, not 0', () async {
      expect(await runner.run(['--version', 'nope']), usageExitCode);
      expect(err.toString(), contains('Could not find a command named "nope"'));
      expect(out.toString(), isEmpty);
    });

    test(
      'mcp with an extra argument exits 64 and never starts the server',
      () async {
        expect(await runner.run(['mcp', 'extra']), usageExitCode);
        expect(out.toString(), isEmpty);
        expect(err.toString(), isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
