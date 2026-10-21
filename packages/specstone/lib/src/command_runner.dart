import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:specstone/src/commands/mcp_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Exit status for a usage error (`EX_USAGE` from sysexits), returned when an
/// unknown command or option is given.
const int usageExitCode = 64;

/// Runs the `specstone` command line.
///
/// Prints the Specstone version for `--version`, prints generated usage for
/// `--help` or no arguments, and maps a [UsageException] to usage on stderr
/// with [usageExitCode] instead of letting it escape.
class SpecstoneCommandRunner extends CommandRunner<int> {
  new({StringSink? out, StringSink? err})
    : _out = out ?? stdout,
      _err = err ?? stderr,
      super(
        'specstone',
        'Keeps PRD and spec documents for spec-driven development.',
      ) {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the Specstone version.',
    );
    addCommand(McpCommand());
  }

  final StringSink _out;
  final StringSink _err;

  @override
  void printUsage() => _out.writeln(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version')) {
      _out.writeln(specstoneVersion);
      return 0;
    }
    return super.runCommand(topLevelResults);
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      return await super.run(args) ?? 0;
    } on UsageException catch (error) {
      _err
        ..writeln(error.message)
        ..writeln()
        ..writeln(error.usage);
      return usageExitCode;
    }
  }
}
