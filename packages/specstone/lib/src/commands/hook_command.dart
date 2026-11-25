import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Groups the commands that agent hooks run.
class HookCommand extends SpecstoneCommand {
  new() {
    addSubcommand(PostEditCommand());
    addSubcommand(PreShellCommand());
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
/// It never exits 2, so it blocks no edit.
class PostEditCommand extends SpecstoneCommand {
  static const _expected =
      'hook post-edit expects one JSON object holding tool_input.file_path '
      'on stdin';

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
      final report = await ReadSession.runAsync(
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

  /// Returns the DocPath of [filePath] when it names an existing markdown file
  /// in a checked folder of the docs root or the records root, else null.
  String? _checkedDocPath(DocsProject project, String filePath) {
    final docPath = project.docPathAt(
      filePath,
      workingDirectory: specstoneRunner.workingDirectory,
    );
    if (docPath == null || !docPath.endsWith('.md')) return null;
    return isInCheckedFolder(checkedFoldersOf(project.set), docPath)
        ? docPath
        : null;
  }
}

/// Refuses the shell command a `PreToolUse` hook reports when it writes into
/// a temp folder.
///
/// Reads the hook JSON on stdin. A refusal prints one line on stderr and
/// exits 2; every other run exits with another status, so the command runs.
class PreShellCommand extends SpecstoneCommand {
  static const _expected =
      'hook pre-shell expects one JSON object holding tool_input.command or '
      'command on stdin';
  static const _refusedStatus = 2;

  @override
  String get name => 'pre-shell';

  @override
  String get description =>
      'Refuse a shell command that writes into a temp folder.';

  @override
  String get invocation => 'specstone hook pre-shell < pre-tool-use.json';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Expected no argument, got ${argResults!.rest.length}.');
    }
    final runner = specstoneRunner;
    try {
      final command = _commandOf(await runner.console.readAll());
      final root = matchProjectRoot(runner.workingDirectory)?.root;
      if (root == null) return 0;
      final tempFolders = _TempFolders(runner.environment);
      final target = _ShellWrites.of(command)
          .where(
            (write) =>
                tempFolders.holds(write.path) &&
                !isInsideProject(root, write.path, runner.workingDirectory),
          )
          .firstOrNull;
      if (target == null) return 0;
      final folder = canonicalPath(
        '${root.path}${Platform.pathSeparator}.specstone',
      );
      final written = _onOneLine(target.written);
      runner.err.writeln(
        'hook pre-shell refused a shell write to $written, '
        'a temp folder; save the output inside the project, by the '
        "command's --out or under $folder",
      );
      return _refusedStatus;
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: false);
    }
  }

  /// Returns [text] with each line break written as `\n` or `\r`, so the
  /// refusal stays one line.
  String _onOneLine(String text) =>
      text.replaceAll('\n', r'\n').replaceAll('\r', r'\r');

  /// Returns `tool_input.command` from [input], else the top-level `command`,
  /// or throws `argument_invalid`.
  String _commandOf(String input) {
    final Object? decoded;
    try {
      decoded = jsonDecode(input);
    } on FormatException {
      throw IndexFault(IndexFaultCode.argumentInvalid, _expected);
    }
    if (decoded case {'tool_input': {'command': final String command}}
        when command.isNotEmpty) {
      return command;
    }
    if (decoded case {'command': final String command}
        when command.isNotEmpty) {
      return command;
    }
    throw IndexFault(IndexFaultCode.argumentInvalid, _expected);
  }
}

/// Whether [path] lies inside the canonical project [root], where no write is
/// a temp-folder write.
///
/// A relative [path] reads from [workingDirectory]. A path with no known place
/// (see [_hasKnownPlace]), or one the disk cannot resolve, is never inside.
/// [isWindows] picks the host's path style, and [canonical] resolves a path on
/// disk; both default to the running host.
bool isInsideProject(
  Directory root,
  String path,
  Directory workingDirectory, {
  bool? isWindows,
  String Function(String path) canonical = canonicalPath,
}) {
  final windows = isWindows ?? Platform.isWindows;
  if (!_hasKnownPlace(path, isWindows: windows)) return false;
  try {
    final resolved = canonical(absoluteFrom(workingDirectory, path));
    return pathInside(root.path, resolved, isWindows: windows) != null;
  } on FileSystemException {
    return false;
  }
}

/// Whether the hook can place [path] on a host with [isWindows] path style.
///
/// A path that holds `$` or a backtick, starts with `%` or `~`, names a
/// Windows drive or share on a POSIX host, or starts with one separator on
/// Windows has none: the host reads it from a place the hook cannot tell.
bool _hasKnownPlace(String path, {required bool isWindows}) {
  if (path.contains(r'$') || path.contains('`')) return false;
  if (path.startsWith('%') || path.startsWith('~')) return false;
  if (!isWindows) return !isWindowsAbsolutePath(path);
  final startsWithSeparator = path.startsWith('/') || path.startsWith(r'\');
  return !startsWithSeparator || path.startsWith(r'\\');
}

/// A word of a shell command: [written] as typed, [path] with its quotes
/// read.
final class _Word {
  new(this.written, this.path);

  final String written;
  final String path;
}

/// A heredoc whose body waits for the next line end: it ends at a line that
/// holds [delimiter], after its leading tabs when [stripsTabs] (`<<-`).
final class _Heredoc {
  new(this.delimiter, {required this.stripsTabs});

  static final _leadingTabs = RegExp(r'^\t+');

  final String delimiter;
  final bool stripsTabs;

  /// Whether [line] closes the body.
  bool ends(String line) =>
      (stripsTabs ? line.replaceFirst(_leadingTabs, '') : line) == delimiter;
}

/// The temp folders a write target is judged against: the fixed prefixes and
/// the absolute values of the process's own `TMPDIR`, `TMP`, and `TEMP`.
final class _TempFolders {
  new(Map<String, String> environment) {
    for (final name in _variables) {
      final folder = _absoluteFolder(environment[name]);
      if (folder == null) continue;
      if (isWindowsAbsolutePath(folder)) {
        _windowsFolders.add(_windowsKey(folder));
      } else {
        _folders.add(folder);
      }
    }
  }

  static const _variables = ['TMPDIR', 'TMP', 'TEMP'];
  static const _prefixes = [
    '/tmp',
    '/private/tmp',
    '/var/tmp',
    '/var/folders',
    r'$TMPDIR',
    r'${TMPDIR}',
    r'$TMP',
    r'${TMP}',
    r'$TEMP',
    r'${TEMP}',
  ];
  static const _lowerCasePrefixes = [
    '%temp%',
    '%tmp%',
    r'$env:temp',
    r'$env:tmp',
  ];
  static final _trailingSeparators = RegExp(r'[/\\]+$');

  final _folders = <String>[..._prefixes];
  final _windowsFolders = <String>[];

  /// Whether [path], unquoted, lies in a temp folder or is one.
  bool holds(String path) =>
      _folders.any((folder) => _isUnder(path, folder)) ||
      _lowerCasePrefixes.any(
        (prefix) => _isUnder(path.toLowerCase(), prefix),
      ) ||
      _windowsFolders.any((folder) => _isUnder(_windowsKey(path), folder));

  /// Returns [value] without trailing separators when it is an absolute path
  /// below its root, else null.
  ///
  /// The root is `/` or a drive (`C:\`); a network share root is a folder.
  static String? _absoluteFolder(String? value) {
    if (value == null) return null;
    final isAbsolute = value.startsWith('/') || isWindowsAbsolutePath(value);
    final folder = value.replaceFirst(_trailingSeparators, '');
    final isBareDrive = folder.length == 2 && folder.endsWith(':');
    return isAbsolute && folder.isNotEmpty && !isBareDrive ? folder : null;
  }

  /// Returns [path] in lower case with `/` separators, the way Windows
  /// compares paths.
  static String _windowsKey(String path) =>
      path.toLowerCase().replaceAll(r'\', '/');

  static bool _isUnder(String path, String folder) {
    if (!path.startsWith(folder)) return false;
    if (path.length == folder.length) return true;
    final next = path[folder.length];
    return next == '/' || next == r'\';
  }
}

/// The writes of a shell command: each redirect target and `tee` operand in
/// the order the command gives them.
///
/// A hand scanner, since quotes, comments, and heredoc bodies decide what is
/// an operator.
final class _ShellWrites {
  new(this._text);

  static const _blanks = ' \t';
  static const _separators = '\n;|&()';
  static const _wordEnds = ' \t\n;|&()<>';
  static const _escapedInDoubleQuotes = r'"\$`';
  static final _descriptorCopy = RegExp(r'^(\d+-?|-)$');

  final String _text;
  final _targets = <_Word>[];
  final _heredocs = <_Heredoc>[];
  var _pos = 0;

  /// Returns the write targets of [command].
  static List<_Word> of(String command) {
    final scan = _ShellWrites(command).._scanCommands(nested: false);
    return scan._targets;
  }

  /// Reads simple commands up to the end of the text, or to the `)` that
  /// closes a `$(…)` when [nested].
  void _scanCommands({required bool nested}) {
    String? command;
    while (_pos < _text.length) {
      final char = _text[_pos];
      if (char == ')' && nested) {
        _pos++;
        return;
      }
      command = _scanStep(char, command);
    }
  }

  /// Reads the token that starts with [char] and returns the command word of
  /// the simple command that goes on, null after a separator.
  String? _scanStep(String char, String? command) {
    if (_blanks.contains(char)) {
      _pos++;
    } else if (char == '#') {
      _skipComment();
    } else if (command == null && _skipArithmeticAt(_pos)) {
      return null;
    } else if (char == '>' || _text.startsWith('&>', _pos)) {
      _readOutputRedirect();
    } else if (char == '<') {
      _readInputRedirect();
    } else if (_separators.contains(char)) {
      _pos++;
      if (char == '\n') _skipHeredocBodies();
      return null;
    } else {
      final word = _readWord();
      if (command == null) return word.path;
      if (command == 'tee' && !word.path.startsWith('-')) _targets.add(word);
    }
    return command;
  }

  void _skipComment() {
    final end = _text.indexOf('\n', _pos);
    _pos = end < 0 ? _text.length : end;
  }

  /// Skips the arithmetic `((…))` that opens at [open] and returns true; else
  /// leaves the position and returns false.
  ///
  /// `<<` and `>` in arithmetic are no redirects. As in bash, the text is
  /// arithmetic only when the first `)` back to depth 1 is followed by `)`;
  /// `((cd d; ls) > f)` is a subshell in a subshell.
  bool _skipArithmeticAt(int open) {
    if (!_text.startsWith('((', open)) return false;
    var depth = 0;
    for (var i = open; i < _text.length; i++) {
      if (_text[i] == '(') depth++;
      if (_text[i] != ')' || --depth > 1) continue;
      if (!_text.startsWith(')', i + 1)) return false;
      _pos = i + 2;
      return true;
    }
    return false;
  }

  void _skipBlanks() {
    while (_pos < _text.length && _blanks.contains(_text[_pos])) {
      _pos++;
    }
  }

  /// Reads `>`, `>>`, `>|`, `&>`, `&>>`, or `>&` and its word; after `>&` a
  /// descriptor number or `-` is no write, any other word is a file.
  void _readOutputRedirect() {
    final fromAmpersand = _text.startsWith('&>', _pos);
    _pos += fromAmpersand ? 2 : 1;
    final next = _pos < _text.length ? _text[_pos] : '';
    final copiesDescriptor = !fromAmpersand && next == '&';
    if (copiesDescriptor || next == '>' || next == '|') _pos++;
    _skipBlanks();
    final target = _readWord();
    if (target.written.isEmpty) return;
    if (copiesDescriptor && _descriptorCopy.hasMatch(target.path)) return;
    _targets.add(target);
  }

  /// Reads `<`, `<<<`, or `<<` and its word; a heredoc's delimiter waits for
  /// the line end that starts its body.
  void _readInputRedirect() {
    final isHereString = _text.startsWith('<<<', _pos);
    final isHeredoc = !isHereString && _text.startsWith('<<', _pos);
    _pos += isHereString ? 3 : (isHeredoc ? 2 : 1);
    final stripsTabs = isHeredoc && _text.startsWith('-', _pos);
    if (stripsTabs) _pos++;
    _skipBlanks();
    final word = _readWord();
    if (isHeredoc) {
      _heredocs.add(
        _Heredoc(_delimiterOf(word.written), stripsTabs: stripsTabs),
      );
    }
  }

  /// Returns [written] with its quotes removed and each backslash outside
  /// quotes dropped, which is the delimiter line a heredoc ends at.
  static String _delimiterOf(String written) {
    final delimiter = StringBuffer();
    String? quote;
    for (var i = 0; i < written.length; i++) {
      final char = written[i];
      if (quote == '"' && char == r'\' && i + 1 < written.length) {
        final next = written[i + 1];
        if (!_escapedInDoubleQuotes.contains(next)) delimiter.write(char);
        delimiter.write(next);
        i++;
      } else if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          delimiter.write(char);
        }
      } else if (char == "'" || char == '"') {
        quote = char;
      } else if (char == r'\' && i + 1 < written.length) {
        delimiter.write(written[++i]);
      } else {
        delimiter.write(char);
      }
    }
    return delimiter.toString();
  }

  /// Skips the body of each pending heredoc, to its delimiter line.
  void _skipHeredocBodies() {
    for (final heredoc in _heredocs) {
      while (_pos < _text.length) {
        final lineEnd = _text.indexOf('\n', _pos);
        final end = lineEnd < 0 ? _text.length : lineEnd;
        final line = _text.substring(_pos, end);
        _pos = lineEnd < 0 ? end : end + 1;
        if (heredoc.ends(line)) break;
      }
    }
    _heredocs.clear();
  }

  /// Reads the word at [_pos]: quoted parts, escapes, and `$(…)` included.
  _Word _readWord() {
    final start = _pos;
    final path = StringBuffer();
    while (_pos < _text.length) {
      final char = _text[_pos];
      if (char == "'") {
        _readSingleQuoted(path);
      } else if (char == '"') {
        _readDoubleQuoted(path);
      } else if (char == r'\') {
        _readEscaped(path);
      } else if (_text.startsWith(r'$(', _pos)) {
        _readSubstitution(path);
      } else if (_wordEnds.contains(char)) {
        break;
      } else {
        path.write(char);
        _pos++;
      }
    }
    return _Word(_text.substring(start, _pos), path.toString());
  }

  void _readSingleQuoted(StringBuffer path) {
    _pos++;
    final close = _text.indexOf("'", _pos);
    final end = close < 0 ? _text.length : close;
    path.write(_text.substring(_pos, end));
    _pos = close < 0 ? end : end + 1;
  }

  void _readDoubleQuoted(StringBuffer path) {
    _pos++;
    while (_pos < _text.length && _text[_pos] != '"') {
      if (_text[_pos] == r'\') {
        _readEscaped(path);
      } else if (_text.startsWith(r'$(', _pos)) {
        _readSubstitution(path);
      } else {
        path.write(_text[_pos]);
        _pos++;
      }
    }
    if (_pos < _text.length) _pos++;
  }

  /// Keeps a backslash and the character it escapes, as typed.
  void _readEscaped(StringBuffer path) {
    final end = min(_pos + 2, _text.length);
    path.write(_text.substring(_pos, end));
    _pos = end;
  }

  void _readSubstitution(StringBuffer path) {
    final start = _pos;
    if (!_skipArithmeticAt(_pos + 1)) {
      _pos += 2;
      _scanCommands(nested: true);
    }
    path.write(_text.substring(start, _pos));
  }
}
