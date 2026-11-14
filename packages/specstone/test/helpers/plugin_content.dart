import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart';
import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';

import 'package_root.dart';

final _specstoneCall = RegExp(r'\bspecstone\s+(\S+)');
final _skillName = RegExp(r'^([a-z0-9-]+):[a-z0-9-]+$');
final _nonLatinLetter = RegExp(r'[^\P{L}\p{Script=Latin}]', unicode: true);

/// Returns the shipped plugin folder, two levels above the specstone package.
Directory pluginRoot() =>
    Directory.fromUri(packageRoot().uri.resolve('../../plugin/'));

/// Returns every file of the skill folders `specstone-<name>/` and the agent
/// files `specstone-<name>.md` under [root], sorted by path.
///
/// Any other entry of [root], the `AGENT.md` asset among them, is left out.
List<File> agentSourceFiles(Directory root) {
  final files = <File>[];
  for (final entity in root.listSync()) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (!name.startsWith('specstone-')) continue;
    if (entity is Directory) {
      files.addAll(entity.listSync(recursive: true).whereType<File>());
    } else if (entity is File && name.endsWith('.md')) {
      files.add(entity);
    }
  }
  return files..sort((a, b) => a.path.compareTo(b.path));
}

/// Returns every shipped file, the skill and agent sources first and the
/// plugin folder's files after them.
List<File> shippedFiles() => [
  ...agentSourceFiles(agentAssetsRoot()),
  ...pluginRoot().listSync(recursive: true).whereType<File>(),
];

/// Returns the path of [file] below the folder it ships from, [agentAssetsRoot]
/// or [pluginRoot], with `/` separators.
String shippedPathOf(File file) {
  final path = file.uri.toFilePath(windows: false);
  for (final root in [agentAssetsRoot(), pluginRoot()]) {
    if (path.startsWith(root.uri.toFilePath(windows: false))) {
      return _relativePath(root, file);
    }
  }
  throw ArgumentError('not a shipped file: $path');
}

/// Returns the folder that holds the skill and agent sources, beside the
/// `AGENT.md` asset in the core package.
Directory agentAssetsRoot() => Directory.fromUri(
  packageRoot().uri.resolve('../specstone_core/assets/agent/'),
);

/// Returns the problems in every CLI call that `.md` files of the skill and
/// agent sources under [plugin] name, sorted.
///
/// Scans inline code spans and code block lines. A `specstone <word>` must
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

/// Returns the word after every `specstone ` in the code spans and code block
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

/// Returns one problem per inline code span in a `.md` file of the skill and
/// agent sources under [plugin] that names another plugin's skill, sorted.
///
/// A span names a skill when its whole text is `<prefix>:<name>`, two words of
/// lowercase letters, digits, and hyphens, and the prefix is neither
/// `specstone` nor in [docTypes]. Code blocks are never read: they hold whole
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

/// Returns one problem per file of a skill folder under [plugin] over [limit]
/// estimated tokens, each file sized alone, sorted. Agent files are never
/// sized.
///
/// A file's estimated tokens are its code points, with `\r\n` folded to `\n`,
/// divided by 4 and rounded down.
List<String> oversizedSkillFiles(Directory plugin, {int limit = 1500}) {
  final problems = <String>[];
  for (final file in agentSourceFiles(plugin)) {
    if (!_relativePath(plugin, file).contains('/')) continue;
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

Iterable<File> _markdownFiles(Directory plugin) =>
    agentSourceFiles(plugin).where((file) => file.path.endsWith('.md'));

String _relativePath(Directory plugin, FileSystemEntity entity) {
  final path = entity.uri
      .toFilePath(windows: false)
      .substring(plugin.uri.toFilePath(windows: false).length);
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

/// Yields each inline code span and each line of a code block of [markdown],
/// in text order, as the `markdown` package parses it.
Iterable<String> _codeTexts(String markdown) sync* {
  for (final code in _codeOf(markdown)) {
    if (code.isBlock) {
      yield* LineSplitter.split(code.text);
    } else {
      yield code.text;
    }
  }
}

/// Yields each inline code span of [markdown], code blocks left out.
Iterable<String> _inlineSpans(String markdown) => [
  for (final code in _codeOf(markdown))
    if (!code.isBlock) code.text,
];

typedef _Code = ({String text, bool isBlock});

/// Returns each code block (fenced or indented) and inline code span of
/// [markdown], in text order.
List<_Code> _codeOf(String markdown) {
  // encodeHtml off keeps code text as written: `<type>`, not `&lt;type&gt;`.
  final document = Document(
    extensionSet: ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final found = <_Code>[];
  void walk(Iterable<Node> nodes) {
    for (final node in nodes.whereType<Element>()) {
      switch (node.tag) {
        case 'pre':
          found.add((text: node.textContent, isBlock: true));
        case 'code':
          found.add((text: node.textContent, isBlock: false));
        default:
          walk(node.children ?? const []);
      }
    }
  }

  walk(document.parse(markdown));
  return found;
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
