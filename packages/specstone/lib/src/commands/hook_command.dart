import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Groups the commands that agent hooks run.
class HookCommand extends SpecstoneCommand {
  new() {
    addSubcommand(PostEditCommand());
    addSubcommand(PreBashCommand());
  }

  @override
  String get name => 'hook';

  @override
  String get description => 'Commands that agent hooks run.';

  @override
  String get invocation => 'specstone hook <command>';
}

/// Checks the doc a `PostToolUse` hook reports as edited.
///
/// Reads the hook JSON on stdin and prints the doc's findings as hook output.
/// It never exits 2, so it blocks no edit (PD5 to PD7).
class PostEditCommand extends SpecstoneCommand {
  static const _expected =
      'hook post-edit expects one JSON object holding tool_input.file_path '
      'on stdin';
  static const _docsFolder = 'docs/';

  @override
  String get name => 'post-edit';

  @override
  String get description =>
      'Check the doc a PostToolUse hook edited and print its findings.';

  @override
  String get invocation => 'specstone hook post-edit < post-tool-use.json';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Expected no argument, got ${argResults!.rest.length}.');
    }
    final runner = specstoneRunner;
    try {
      final filePath = _filePathOf(await runner.console.readAll());
      final project = DocsProject.open(
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
      );
      final docPath = _checkedDocPath(project, filePath);
      if (docPath == null) return 0;
      final report = ReadSession.run(
        (session) => runCheck(session, docPath: docPath),
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
        busyTimeout: runner.busyTimeout,
      );
      if (report.findings.isEmpty) return 0;
      final text = report.text;
      final context = text.substring(0, text.length - 1);
      final output = {
        'hookSpecificOutput': {
          'hookEventName': 'PostToolUse',
          'additionalContext': context,
        },
      };
      runner.out.write('${SpecstoneCommand.pretty.convert(output)}\n');
      return 0;
    } on RenderFault catch (fault) {
      if (fault.code == RenderFaultCode.projectNotFound) return 0;
      return fail(fault, asJson: false);
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: false);
    }
  }

  /// Returns `tool_input.file_path` from [input], or throws
  /// `argument_invalid`.
  String _filePathOf(String input) {
    final Object? decoded;
    try {
      decoded = jsonDecode(input);
    } on FormatException {
      throw IndexFault(IndexFaultCode.argumentInvalid, _expected);
    }
    if (decoded case {'tool_input': {'file_path': final String path}}
        when path.isNotEmpty) {
      return path;
    }
    throw IndexFault(IndexFaultCode.argumentInvalid, _expected);
  }

  /// Returns the DocPath of [filePath] when it names a markdown file in a
  /// checked folder of the docs root, else null.
  String? _checkedDocPath(DocsProject project, String filePath) {
    final file = File(filePath);
    final resolved = file.isAbsolute
        ? file
        : File(
            '${specstoneRunner.workingDirectory.absolute.path}'
            '${Platform.pathSeparator}$filePath',
          );
    if (!project.isInsideDocsRoot(resolved)) return null;
    final shown = project.displayPath(resolved);
    if (!shown.startsWith(_docsFolder)) return null;
    final docPath = shown.substring(_docsFolder.length);
    if (!docPath.endsWith('.md')) return null;
    final folder = docPath.split('/').first;
    return checkedFoldersOf(project.set).contains(folder) ? docPath : null;
  }
}

/// Makes Claude Code ask the Owner before a shell call that confirms an
/// Owner-gated command with `--yes`.
///
/// Reads the `PreToolUse` hook JSON on stdin and takes `tool_input.command`,
/// whatever the tool (`Bash`, `PowerShell`, `Monitor`). A command holding the
/// whole word `approve`, `delete`, `migrate`, or `init` and the token `--yes`
/// gets one `ask` object; any other command, and input it cannot read, gets
/// nothing. It never answers `allow` or `deny`, so it blocks no call.
class PreBashCommand extends SpecstoneCommand {
  static final _gatedWord = RegExp(r'\b(approve|delete|migrate|init)\b');
  static final _yesToken = RegExp(r'(?<![\w-])--yes(?![\w-])');
  static final _gatedCall = RegExp(
    r'''\bspecstone(?:\.exe)?['"]?\s+(approve|delete|migrate|init)\b''',
  );
  static final _commandEnd = RegExp(r'&&|\|\||[;|\r\n)]');
  static final _whitespace = RegExp(r'\s+');
  static final _quotes = RegExp(r'''^['"]+|['"]+$''');
  static final _hashSuffix = RegExp(r'@[0-9a-f]+$');
  // `$(`, `${`, `$name`, a backtick, `<(`, or a `<` redirect.
  static final _expansion = RegExp(r'\$[({A-Za-z_]|`|<');
  static final _xargs = RegExp(r'\bxargs\b');
  static const _planOption = '--plan';
  static const _reasonLimit = 300;
  static const _hiddenNames =
      'names come from a shell expansion the Owner cannot see; write them out';

  @override
  String get name => 'pre-bash';

  @override
  String get description =>
      'Ask the Owner before a shell call runs an Owner-gated command with '
      '--yes.';

  @override
  String get invocation => 'specstone hook pre-bash < pre-tool-use.json';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Expected no argument, got ${argResults!.rest.length}.');
    }
    final runner = specstoneRunner;
    final command = _commandOf(await runner.console.readAll());
    final reason = command == null ? null : _reasonFor(command);
    if (reason == null) return 0;
    final output = {
      'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': reason,
      },
    };
    runner.out.write('${SpecstoneCommand.pretty.convert(output)}\n');
    return 0;
  }

  /// Returns `tool_input.command` from [input], or null when there is none.
  String? _commandOf(String input) {
    final Object? decoded;
    try {
      decoded = jsonDecode(input);
    } on FormatException {
      return null;
    }
    return switch (decoded) {
      {'tool_input': {'command': final String command}} => command,
      _ => null,
    };
  }

  /// Returns the reason of the ask, or null when [command] needs none.
  ///
  /// The reason is `Owner confirmation: ` and one segment per gated
  /// `specstone <subcommand>` call, in order, joined with `; `: the call with
  /// its names, flags and `@<hash>` dropped. A call whose names or plan come
  /// from a shell expansion reads `specstone <subcommand>: ` and the reason to
  /// write them out. A command with no such call names itself. The reason is
  /// cut to 300 characters.
  String? _reasonFor(String command) {
    if (!_gatedWord.hasMatch(command) || !_yesToken.hasMatch(command)) {
      return null;
    }
    final segments = [
      for (final call in _gatedCall.allMatches(command))
        _segmentOf(
          call[1]!,
          before: command.substring(0, call.start),
          rest: command.substring(call.end),
        ),
    ];
    final named = segments.isEmpty
        ? command.trim().replaceAll(_whitespace, ' ')
        : segments.join('; ');
    final reason = 'Owner confirmation: $named';
    return String.fromCharCodes(reason.runes.take(_reasonLimit));
  }

  /// Returns `specstone <subcommand>` and the names in [rest], the text after
  /// the subcommand, up to the end of that shell command.
  ///
  /// [before] is the text ahead of the call; its last shell command may feed
  /// the call through `xargs`.
  String _segmentOf(
    String subcommand, {
    required String before,
    required String rest,
  }) {
    final end = _commandEnd.firstMatch(rest)?.start ?? rest.length;
    final arguments = rest.substring(0, end);
    final stageStart = _commandEnd.allMatches(before).lastOrNull?.end ?? 0;
    if (_expansion.hasMatch(arguments) ||
        _xargs.hasMatch(before.substring(stageStart))) {
      return 'specstone $subcommand: $_hiddenNames';
    }
    final names = <String>[];
    var skipValue = false;
    for (final raw in arguments.split(_whitespace)) {
      final word = raw.replaceAll(_quotes, '');
      if (word.isEmpty) continue;
      if (word.startsWith('@')) {
        return 'specstone $subcommand: $_hiddenNames';
      }
      if (skipValue) {
        skipValue = false;
      } else if (word.startsWith('-')) {
        skipValue = word == _planOption;
      } else {
        names.add(word.replaceFirst(_hashSuffix, ''));
      }
    }
    return ['specstone $subcommand', ...names].join(' ');
  }
}
