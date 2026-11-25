import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:specstone/src/commands/approve_command.dart';
import 'package:specstone/src/commands/build_command.dart';
import 'package:specstone/src/commands/check_command.dart';
import 'package:specstone/src/commands/context_command.dart';
import 'package:specstone/src/commands/delete_command.dart';
import 'package:specstone/src/commands/folder_command.dart';
import 'package:specstone/src/commands/format_command.dart';
import 'package:specstone/src/commands/get_command.dart';
import 'package:specstone/src/commands/guide_command.dart';
import 'package:specstone/src/commands/hook_command.dart';
import 'package:specstone/src/commands/init_command.dart';
import 'package:specstone/src/commands/list_command.dart';
import 'package:specstone/src/commands/migrate_command.dart';
import 'package:specstone/src/commands/move_command.dart';
import 'package:specstone/src/commands/new_command.dart';
import 'package:specstone/src/commands/refs_command.dart';
import 'package:specstone/src/commands/rename_command.dart';
import 'package:specstone/src/commands/reorder_command.dart';
import 'package:specstone/src/commands/search_command.dart';
import 'package:specstone/src/commands/set_command.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone/src/commands/structure_command.dart';
import 'package:specstone/src/commands/trust_command.dart';
import 'package:specstone/src/commands/upgrade_command.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone/src/update_notice.dart';
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

/// Returns the generators of the shipped doc types: the journey kinds,
/// `feature_catalog`, and `component_catalog`.
GeneratorRegistry<DocIndex> _shippedGenerators() {
  final journeys = journeyGenerators();
  return GeneratorRegistry<DocIndex>({
    for (final kind in journeys.kinds) kind: journeys[kind]!,
    featureCatalogKind: featureCatalogBlocks,
    componentCatalogKind: componentCatalogBlocks,
  });
}

/// Runs the specstone command line.
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
    Map<String, String>? environment,
    Duration busyTimeout = indexBusyTimeout,
    required Console console,
    UpgradeCommand? upgrade,
    UpdateNotice? updateNotice,
    Future<void> Function(String line)? courtesy,
  }) : this._(
         registry: generators ?? _shippedGenerators(),
         out: out,
         err: err,
         templates: templates,
         workingDirectory: workingDirectory,
         homeDirectory: homeDirectory,
         environment: environment,
         busyTimeout: busyTimeout,
         console: console,
         upgrade: upgrade,
         updateNotice: updateNotice,
         courtesy: courtesy,
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
    required Map<String, String>? environment,
    required Duration busyTimeout,
    required Console console,
    required UpgradeCommand? upgrade,
    required UpdateNotice? updateNotice,
    required Future<void> Function(String line)? courtesy,
  }) : _out = out ?? stdout,
       _err = err ?? stderr,
       _generators = registry,
       _templates =
           templates ?? TemplateResolver(generatorKinds: registry.kinds),
       _workingDirectory = workingDirectory,
       _environment = environment ?? Platform.environment,
       _homeDirectory =
           homeDirectory ?? homeFrom(environment ?? Platform.environment),
       _busyTimeout = busyTimeout,
       _console = console,
       _updateNoticeOverride = updateNotice,
       _courtesy = courtesy,
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
    addCommand(FolderCommand());
    addCommand(CheckCommand());
    addCommand(SetCommand());
    addCommand(NewCommand());
    addCommand(ApproveCommand());
    addCommand(DeleteCommand());
    addCommand(ReorderCommand());
    addCommand(RenameCommand());
    addCommand(MoveCommand());
    addCommand(MigrateCommand());
    addCommand(InitCommand());
    addCommand(TrustCommand());
    addCommand(HookCommand());
    addCommand(upgrade ?? UpgradeCommand());
  }

  final StringSink _out;
  final StringSink _err;
  final TemplateResolver _templates;
  final GeneratorRegistry<DocIndex> _generators;
  final Directory? _workingDirectory;
  final Directory? _homeDirectory;
  final Map<String, String> _environment;
  final Duration _busyTimeout;
  final Console _console;
  final UpdateNotice? _updateNoticeOverride;
  final Future<void> Function(String line)? _courtesy;
  var _refusedOnPin = false;
  StringBuffer? _capture;
  var _faulted = false;

  late final UpdateNotice _updateNotice =
      _updateNoticeOverride ??
      UpdateNotice(
        console: _console,
        environment: _environment,
        home: _homeDirectory,
      );

  /// Sink that receives normal output: version, usage, and command results.
  ///
  /// While a reply run with `--out` runs, the buffer that becomes its file.
  StringSink get out => _capture ?? _out;

  /// Whether a reply run with `--out` is capturing its output into a file.
  bool get isCapturing => _capture != null;

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

  /// The process environment, or the one a test supplies.
  Map<String, String> get environment => _environment;

  /// How long a read command waits on another call's index write.
  Duration get busyTimeout => _busyTimeout;

  /// The terminal facts and input the write commands read.
  Console get console => _console;

  @override
  void printUsage() => _out.writeln(usage);

  /// Records that the running command was refused on a pack pin, which names
  /// its own fix.
  void recordPinRefusal() => _refusedOnPin = true;

  /// Records that the running command failed with a fault, so a run saving its
  /// output with `--out` writes no file.
  void recordFault() => _faulted = true;

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version') &&
        topLevelResults.command == null &&
        topLevelResults.rest.isEmpty &&
        !topLevelResults.flag('help')) {
      _out.writeln(specstoneVersion);
      return 0;
    }
    _refusedOnPin = false;
    if (_namesLeaf(topLevelResults.command)) {
      _updateNotice.start(_namesOf(topLevelResults.command));
    }
    final saving = _savingCommand(topLevelResults.command);
    final status = saving == null
        ? await super.runCommand(topLevelResults)
        : await _runSaving(topLevelResults, saving);
    await _printStaleLine(topLevelResults.command);
    return status;
  }

  /// Returns the command [chosen] names when it saves its reply with `--out`
  /// through the runner, else null.
  ///
  /// A command saves through the runner when its parser declares `out`, it
  /// writes no `--out` files of its own, and the call passes `--out`.
  SpecstoneCommand? _savingCommand(ArgResults? chosen) {
    if (chosen == null) return null;
    if (chosen.options.contains('help') && chosen.flag('help')) return null;
    final command = commands[chosen.name];
    if (command is! SpecstoneCommand || command.subcommands.isNotEmpty) {
      return null;
    }
    if (command.writesOwnOut || !command.argParser.options.containsKey('out')) {
      return null;
    }
    return command.writesOut(chosen) ? command : null;
  }

  /// Runs [command] with its output held back, then writes it to the `--out`
  /// file and prints the header in its place.
  ///
  /// The run's own exit status stands. A refused call, a refused path, and a
  /// run that faulted write no file.
  Future<int?> _runSaving(ArgResults top, SpecstoneCommand command) async {
    final args = top.command!;
    final parser = command.argParser;
    final asJson = parser.options.containsKey('json') && args.flag('json');
    if (!command.isReplyRun(args)) {
      return command.fail(
        IndexFault(IndexFaultCode.argumentInvalid, command.outRefusal),
        asJson: asJson,
      );
    }
    final roots = locateReadRoots(workingDirectory);
    final String? outPath;
    final File file;
    try {
      outPath = command.outPathOf(args);
      file = outPath == null
          ? bareOutFile(
              roots?.projectRoot ?? workingDirectory,
              outFileName(
                command: command.name,
                flags: command.outFlagsOf(args),
                args: args.rest,
                codeTarget: parser.options.containsKey('target')
                    ? args.option('target')
                    : null,
                asJson: asJson,
              ),
            )
          : File(absoluteFrom(workingDirectory, outPath));
      requireOutPath(
        canonicalPath(file.absolute.path),
        projectRoot: roots?.projectRoot,
        docsRoot: roots?.docsRoot,
        isBare: outPath == null,
      );
    } on SpecstoneFault catch (fault) {
      return command.fail(fault, asJson: asJson);
    }
    final buffer = StringBuffer();
    _capture = buffer;
    _faulted = false;
    final int? status;
    try {
      status = await super.runCommand(top);
    } finally {
      _capture = null;
    }
    if (_faulted) {
      _out.write(buffer);
      return status;
    }
    final text = buffer.toString();
    final warnings = asJson ? _warningsIn(text) : const <String>[];
    final projectRoot = roots?.projectRoot;
    try {
      final saved = answerOutFile(
        command: command.name,
        text: text,
        file: file,
        projectRoot: projectRoot,
        docsRoot: roots?.docsRoot,
        isBare: outPath == null,
        asJson: asJson,
        cleanup: projectRoot == null ? null : readCleanupBounds(projectRoot),
        warnings: warnings,
      );
      final reply = {...saved.json, 'warnings': warnings};
      out.write(
        asJson ? '${SpecstoneCommand.pretty.convert(reply)}\n' : saved.text,
      );
      return status ?? 0;
    } on SpecstoneFault catch (fault) {
      return command.fail(fault, asJson: asJson, warnings: warnings);
    }
  }

  /// Whether [chosen] names the command that `run` executes: a command with
  /// subcommands needs one of them chosen too.
  bool _namesLeaf(ArgResults? chosen) {
    if (chosen == null) return false;
    var command = commands[chosen.name];
    var level = chosen;
    while (command != null && command.subcommands.isNotEmpty) {
      final next = level.command;
      if (next == null) return false;
      command = command.subcommands[next.name];
      level = next;
    }
    return command != null;
  }

  /// Prints the update notice the check beside the command found, if any.
  ///
  /// Never throws: the notice is a courtesy, so a failed write leaves the
  /// command's output and exit status as they are.
  Future<void> _printUpdateNotice() async {
    try {
      final line = _updateNotice.lineAfter();
      if (line == null) return;
      final courtesy = _courtesy;
      if (courtesy == null) {
        _err.writeln(line);
      } else {
        await courtesy(line);
      }
    } on Object {
      // The command's own result stands whatever the line's write did.
    }
  }

  /// Prints the stale-project line when the command that just ended is a row
  /// of the table that gets it.
  ///
  /// Never throws: the line is a courtesy, so a failed lookup or write leaves
  /// the command's output and exit status as they are.
  Future<void> _printStaleLine(ArgResults? command) async {
    try {
      if (_refusedOnPin || !_endsWithStaleLine(command)) return;
      final root = matchProjectRoot(workingDirectory)?.root;
      if (root == null) return;
      final line = staleProjectLine(root, runningVersion: specstoneVersion);
      if (line == null) return;
      final courtesy = _courtesy;
      if (courtesy == null) {
        _err.writeln(line);
      } else {
        await courtesy(line);
      }
    } on Object {
      // The command's own result stands whatever the line's read or write did.
    }
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final status = await _runUsageGuarded(args);
      await _printUpdateNotice();
      return status;
    } finally {
      _updateNotice.abandon();
    }
  }

  Future<int> _runUsageGuarded(Iterable<String> args) async {
    try {
      return await super.run(_withTargetValue(withBareOut(args, argParser))) ??
          0;
    } on UsageException catch (error) {
      _err
        ..writeln(error.message)
        ..writeln()
        ..writeln(error.usage);
      return usageExitCode;
    }
  }
}

/// Returns the `warnings` strings of the JSON object in [text], or none when
/// [text] holds no such array.
List<String> _warningsIn(String text) {
  try {
    return switch (jsonDecode(text)) {
      {'warnings': final List<Object?> warnings} =>
        warnings.whereType<String>().toList(),
      _ => const [],
    };
  } on FormatException {
    return const [];
  }
}

/// The commands that end with no stale-project line: the fix itself, a command
/// that speaks to another program, and a command that finds no project root.
const Set<String> _noStaleLineCommands = {
  'migrate',
  'init',
  'hook',
  'help',
  'upgrade',
};

/// Whether [command] ends with the stale-project line when its project is
/// stale: every command but [_noStaleLineCommands], `--help`, and `check` with
/// no target, whose findings already name the fix.
bool _endsWithStaleLine(ArgResults? command) {
  if (command == null || _noStaleLineCommands.contains(command.name)) {
    return false;
  }
  if (command.options.contains('help') && command.flag('help')) return false;
  return command.name != 'check' || command.rest.isNotEmpty;
}

/// Returns the names of [command] and the commands under it, top first.
List<String> _namesOf(ArgResults? command) => [
  for (var level = command; level != null; level = level.command) ?level.name,
];

/// Returns [args] with an empty value on each `--target` that has none, so the
/// command answers `argument_missing` naming the targets, as the shared
/// `--target` option of `addTargetOption` reads it, instead of a usage error.
///
/// A `--target` at the end, or before an option or `--`, has no value; the
/// arguments after `--` are left as given.
Iterable<String> _withTargetValue(Iterable<String> args) {
  final list = args.toList();
  final end = list.indexOf('--');
  final limit = end < 0 ? list.length : end;
  return [
    for (final (i, arg) in list.indexed)
      if (arg == '--target' &&
          i < limit &&
          (i + 1 >= limit || list[i + 1].startsWith('-')))
        '--target='
      else
        arg,
  ];
}
