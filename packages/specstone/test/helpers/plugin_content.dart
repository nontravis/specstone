import 'dart:io';

import 'package:specstone/src/command_runner.dart';

import 'package_root.dart';

final _inlineSpan = RegExp(r'`([^`\n]+)`');
final _specstoneCall = RegExp(r'\bspecstone\s+(\S+)');

/// Returns the shipped plugin folder, two levels above the specstone package.
Directory pluginRoot() =>
    Directory.fromUri(packageRoot().uri.resolve('../../plugin/'));

/// Returns the problems in every CLI call that `.md` files under `skills/` and
/// `agents/` of [plugin] name, sorted.
///
/// Scans inline code spans and fenced code lines. A `specstone <word>` must
/// name a command of [runner], then one of its subcommands when it has any;
/// each `--flag` after it must be an option of that command or `help`.
List<String> unknownCliNames(Directory plugin, SpecstoneCommandRunner runner) {
  final problems = <String>{};
  for (final file in _markdownFiles(plugin)) {
    final path = _relativePath(plugin, file);
    for (final scanned in _codeTexts(file.readAsStringSync())) {
      for (final call in _specstoneCall.allMatches(scanned)) {
        final problem = _problemOf(runner, scanned, call);
        if (problem != null) problems.add('$path: $problem');
      }
    }
  }
  return problems.toList()..sort();
}

/// Returns the estimated tokens of every file under [folder]: code points,
/// with `\r\n` folded to `\n`, divided by 4 and rounded down.
int estTokensOf(Directory folder) {
  var codePoints = 0;
  for (final file in folder.listSync(recursive: true).whereType<File>()) {
    codePoints += file.readAsStringSync().replaceAll('\r\n', '\n').runes.length;
  }
  return codePoints ~/ 4;
}

/// Returns one problem per skill folder of [plugin] over [limit] estimated
/// tokens, sorted. Agent files are never sized.
List<String> oversizedSkills(Directory plugin, {int limit = 1500}) {
  final skills = Directory.fromUri(plugin.uri.resolve('skills/'));
  if (!skills.existsSync()) return [];
  final problems = <String>[];
  for (final folder in skills.listSync().whereType<Directory>()) {
    final tokens = estTokensOf(folder);
    if (tokens > limit) {
      problems.add(
        '${_relativePath(plugin, folder)}: $tokens est. tokens, over $limit',
      );
    }
  }
  return problems..sort();
}

Iterable<File> _markdownFiles(Directory plugin) sync* {
  for (final top in const ['skills', 'agents']) {
    final folder = Directory.fromUri(plugin.uri.resolve('$top/'));
    if (!folder.existsSync()) continue;
    yield* folder
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.md'));
  }
}

String _relativePath(Directory plugin, FileSystemEntity entity) {
  final path = entity.uri
      .toFilePath(windows: false)
      .substring(plugin.uri.toFilePath(windows: false).length);
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

/// Yields each inline code span and each fenced code line of [markdown].
Iterable<String> _codeTexts(String markdown) sync* {
  var fenced = false;
  for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      fenced = !fenced;
    } else if (fenced) {
      yield line;
    } else {
      for (final span in _inlineSpan.allMatches(line)) {
        yield span.group(1)!;
      }
    }
  }
}

String? _problemOf(
  SpecstoneCommandRunner runner,
  String scanned,
  RegExpMatch call,
) {
  final tokens = _callTokens(scanned, call);
  final name = tokens.first;
  if (name.startsWith('<')) return null;
  var command = runner.commands[name];
  if (command == null) return 'specstone has no command $name';
  final rest = tokens.skip(1).toList();
  if (command.subcommands.isNotEmpty && rest.isNotEmpty) {
    final next = rest.first;
    if (!next.startsWith('-') && !next.startsWith('<')) {
      final sub = command.subcommands[next];
      if (sub == null) return 'specstone ${command.name} has no command $next';
      command = sub;
    }
  }
  for (final token in rest.where((token) => token.startsWith('--'))) {
    final flag = token.substring(2).split('=').first;
    if (flag != 'help' && !command.argParser.options.containsKey(flag)) {
      return 'specstone ${command.name} has no --$flag';
    }
  }
  return null;
}

/// Returns the whitespace-split words of the call at [call], up to the next
/// `specstone ` in the same span or line.
List<String> _callTokens(String scanned, RegExpMatch call) {
  final next = _specstoneCall
      .allMatches(scanned)
      .map((m) => m.start)
      .where((start) => start > call.start);
  final end = next.isEmpty ? scanned.length : next.first;
  return scanned
      .substring(call.start, end)
      .trim()
      .split(RegExp(r'\s+'))
      .skip(1)
      .toList();
}
