import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:specstone/src/commands/guide_command.dart';
import 'package:specstone/src/commands/mcp_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Exit status for a usage error (`EX_USAGE` from sysexits), returned when an
/// unknown command or option is given.
const int usageExitCode = 64;

/// Returns the folder in `HOME`, else `USERPROFILE` (Windows) of [env].
///
/// An empty value counts as unset. Returns null when neither names a folder, so
/// no relative path ever stands in for the home.
Directory? homeFrom(Map<String, String> env) {
  for (final key in const ['HOME', 'USERPROFILE']) {
    final value = env[key];
    if (value != null && value.isNotEmpty) return Directory(value);
  }
  return null;
}

/// Runs the `specstone` command line.
///
/// Prints the Specstone version for `--version`, prints generated usage for
/// `--help` or no arguments, and maps a [UsageException] to usage on stderr
/// with [usageExitCode] instead of letting it escape.
class SpecstoneCommandRunner extends CommandRunner<int> {
  new({
    StringSink? out,
    StringSink? err,
    TemplateResolver? templates,
    Directory? workingDirectory,
    Directory? homeDirectory,
  }) : _out = out ?? stdout,
       _err = err ?? stderr,
       _templates = templates ?? TemplateResolver(),
       _workingDirectory = workingDirectory ?? Directory.current,
       _homeDirectory = homeDirectory ?? homeFrom(Platform.environment),
       super(
         'specstone',
         'Keeps PRD and spec documents for spec-driven development.',
       ) {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the Specstone version.',
    );
    addCommand(GuideCommand());
    addCommand(McpCommand());
  }

  final StringSink _out;
  final StringSink _err;
  final TemplateResolver _templates;
  final Directory _workingDirectory;
  final Directory? _homeDirectory;

  /// Sink that receives normal output: version, usage, and command results.
  StringSink get out => _out;

  /// Sink that receives usage errors.
  StringSink get err => _err;

  /// Resolver that `guide` uses to load and merge the doc type templates.
  TemplateResolver get templates => _templates;

  /// Folder the project is looked up from, the process working folder by
  /// default.
  Directory get workingDirectory => _workingDirectory;

  /// Home folder that holds the personal packs, `~`, or null when the
  /// environment names none.
  Directory? get homeDirectory => _homeDirectory;

  @override
  void printUsage() => _out.writeln(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version') &&
        topLevelResults.command == null &&
        topLevelResults.rest.isEmpty &&
        !topLevelResults.flag('help')) {
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
