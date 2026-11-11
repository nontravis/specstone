import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';

import 'package_root.dart';

final _inlineSpan = RegExp(r'`([^`\n]+)`');
final _specstoneCall = RegExp(r'\bspecstone\s+(\S+)');
final _skillName = RegExp(r'^([a-z0-9-]+):[a-z0-9-]+$');
final _nonLatinLetter = RegExp(r'[^\P{L}\p{Script=Latin}]', unicode: true);

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

/// Returns the word after every `specstone ` in the code spans and fenced
/// lines of [markdown], in text order.
List<String> cliCommands(String markdown) => [
  for (final scanned in _codeTexts(markdown))
    for (final call in _specstoneCall.allMatches(scanned)) call.group(1)!,
];

/// Returns the id of each doc type the shipped packs define.
///
/// Read in a fresh folder outside any project, where every shipped pack loads.
Set<String> shippedDocTypes() {
  final empty = Directory.systemTemp.createTempSync('specstone_doc_types_');
  try {
    return {
      for (final docType
          in TemplateResolver()
              .resolve(workingDirectory: empty, homeDirectory: null)
              .docTypes)
        docType.id,
    };
  } finally {
    empty.deleteSync(recursive: true);
  }
}

/// Returns one problem per inline code span in a `.md` file under `skills/` and
/// `agents/` of [plugin] that names another plugin's skill, sorted.
///
/// A span names a skill when its whole text is `<prefix>:<name>`, two words of
/// lowercase letters, digits, and hyphens, and the prefix is neither
/// `specstone` nor in [docTypes]. Fenced lines are never read: they hold whole
/// commands.
List<String> otherPluginSkillNames(Directory plugin, Set<String> docTypes) {
  final problems = <String>{};
  for (final file in _markdownFiles(plugin)) {
    final path = _relativePath(plugin, file);
    for (final span in _inlineSpans(file.readAsStringSync())) {
      final prefix = _skillName.firstMatch(span)?.group(1);
      if (prefix == null ||
          prefix == 'specstone' ||
          docTypes.contains(prefix)) {
        continue;
      }
      problems.add("$path: $span is another plugin's skill");
    }
  }
  return problems.toList()..sort();
}

int _codePointsOf(File file) =>
    file.readAsStringSync().replaceAll('\r\n', '\n').runes.length;

/// Returns one problem per file under `skills/` of [plugin] over [limit]
/// estimated tokens, each file sized alone, sorted; empty when the folder is
/// absent. Agent files are never sized.
///
/// A file's estimated tokens are its code points, with `\r\n` folded to `\n`,
/// divided by 4 and rounded down.
List<String> oversizedSkillFiles(Directory plugin, {int limit = 1500}) {
  final skills = Directory.fromUri(plugin.uri.resolve('skills/'));
  if (!skills.existsSync()) return [];
  final problems = <String>[];
  for (final file in skills.listSync(recursive: true).whereType<File>()) {
    final tokens = _codePointsOf(file) ~/ 4;
    if (tokens > limit) {
      problems.add(
        '${_relativePath(plugin, file)}: $tokens est. tokens, over $limit',
      );
    }
  }
  return problems..sort();
}

/// Returns `<file>:<line>` for each line of a file under [plugin] that holds
/// a letter outside the Latin script, sorted.
///
/// The plugin is written in English; the agent speaks the Owner's language, so
/// a label in another script presumes one Owner's language.
List<String> nonLatinLetterLines(Directory plugin) {
  final problems = <String>[];
  for (final file in plugin.listSync(recursive: true).whereType<File>()) {
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      if (_nonLatinLetter.hasMatch(lines[index])) {
        problems.add('${_relativePath(plugin, file)}:${index + 1}');
      }
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

/// Yields each inline code span of [markdown], fenced lines left out.
Iterable<String> _inlineSpans(String markdown) sync* {
  var fenced = false;
  for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      fenced = !fenced;
    } else if (!fenced) {
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
  var path = command.name;
  final rest = tokens.skip(1).toList();
  if (command.subcommands.isNotEmpty && rest.isNotEmpty) {
    final next = rest.first;
    if (!next.startsWith('-') && !next.startsWith('<')) {
      final sub = command.subcommands[next];
      if (sub == null) return 'specstone ${command.name} has no command $next';
      command = sub;
      path = '$path ${sub.name}';
    }
  }
  for (final token in rest.where(
    (token) => token.startsWith('--') && token != '--',
  )) {
    final flag = token.substring(2).split('=').first;
    if (flag != 'help' && !command.argParser.options.containsKey(flag)) {
      return 'specstone $path has no --$flag';
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
