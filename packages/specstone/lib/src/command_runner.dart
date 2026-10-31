import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:specstone/src/commands/approve_command.dart';
import 'package:specstone/src/commands/build_command.dart';
import 'package:specstone/src/commands/check_command.dart';
import 'package:specstone/src/commands/context_command.dart';
import 'package:specstone/src/commands/delete_command.dart';
import 'package:specstone/src/commands/format_command.dart';
import 'package:specstone/src/commands/get_command.dart';
import 'package:specstone/src/commands/guide_command.dart';
import 'package:specstone/src/commands/hook_command.dart';
import 'package:specstone/src/commands/init_command.dart';
import 'package:specstone/src/commands/list_command.dart';
import 'package:specstone/src/commands/mcp_command.dart';
import 'package:specstone/src/commands/migrate_command.dart';
import 'package:specstone/src/commands/new_command.dart';
import 'package:specstone/src/commands/refs_command.dart';
import 'package:specstone/src/commands/rename_command.dart';
import 'package:specstone/src/commands/reorder_command.dart';
import 'package:specstone/src/commands/search_command.dart';
import 'package:specstone/src/commands/set_command.dart';
import 'package:specstone/src/commands/structure_command.dart';
import 'package:specstone/src/console.dart';
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
    GeneratorRegistry<DocIndex>? generators,
    Directory? workingDirectory,
    Directory? homeDirectory,
    Duration busyTimeout = indexBusyTimeout,
    Console? console,
  }) : this._(
         registry: generators ?? journeyGenerators(),
         out: out,
         err: err,
         templates: templates,
         workingDirectory: workingDirectory,
         homeDirectory: homeDirectory,
         busyTimeout: busyTimeout,
         console: console,
       );

  // The registry is resolved once, so the default resolver's kinds come from
  // the same source as the generators that run.
  new _({
    required GeneratorRegistry<DocIndex> registry,
    required StringSink? out,
    required StringSink? err,
    required TemplateResolver? templates,
    required Directory? workingDirectory,
    required Directory? homeDirectory,
    required Duration busyTimeout,
    required Console? console,
  }) : _out = out ?? stdout,
       _err = err ?? stderr,
       _generators = registry,
       _templates =
           templates ?? TemplateResolver(generatorKinds: registry.kinds),
       _workingDirectory = workingDirectory,
       _homeDirectory = homeDirectory ?? homeFrom(Platform.environment),
       _busyTimeout = busyTimeout,
       _console = console ?? SystemConsole(),
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
    addCommand(FormatCommand());
    addCommand(BuildCommand());
    addCommand(StructureCommand());
    addCommand(ListCommand());
    addCommand(GetCommand());
    addCommand(SearchCommand());
    addCommand(RefsCommand());
    addCommand(ContextCommand());
    addCommand(McpCommand());
    addCommand(CheckCommand());
    addCommand(SetCommand());
    addCommand(NewCommand());
    addCommand(ApproveCommand());
    addCommand(DeleteCommand());
    addCommand(ReorderCommand());
    addCommand(RenameCommand());
    addCommand(MigrateCommand());
    addCommand(InitCommand());
    addCommand(HookCommand());
  }

  final StringSink _out;
  final StringSink _err;
  final TemplateResolver _templates;
  final GeneratorRegistry<DocIndex> _generators;
  final Directory? _workingDirectory;
  final Directory? _homeDirectory;
  final Duration _busyTimeout;
  final Console _console;

  /// Sink that receives normal output: version, usage, and command results.
  StringSink get out => _out;

  /// Sink that receives usage errors.
  StringSink get err => _err;

  /// Resolver that `guide` and `format` use to load and merge the doc type
  /// templates.
  TemplateResolver get templates => _templates;

  /// The generators `format` runs for the doc types that list them.
  GeneratorRegistry<DocIndex> get generators => _generators;

  /// Folder the project is looked up from, the process working folder by
  /// default.
  ///
  /// The process working folder is read on each call, so only a command that
  /// uses it can fail on a deleted folder.
  Directory get workingDirectory => _workingDirectory ?? Directory.current;

  /// Home folder that holds the personal packs, `~`, or null when the
  /// environment names none.
  Directory? get homeDirectory => _homeDirectory;

  /// How long a read command waits on another call's index write.
  Duration get busyTimeout => _busyTimeout;

  /// The terminal facts and input the write commands read.
  Console get console => _console;

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
