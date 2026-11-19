import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart';
import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:yaml/yaml.dart';

import 'package_root.dart';

final _specstoneCall = RegExp(r'\bspecstone\s+(\S+)');

/// The roles a saved `check` file names, as the shipped agent text allows.
const checkRoles = [
  'gate',
  'author',
  'audit',
  'sync',
  'bootstrap',
  'plan',
  'update',
  'done',
];

/// `--out`, then a path under the reports folder of a `check` role file, both
/// quotes present or both absent.
final _savedCheckFile = RegExp(
  '--out\\s+("?)<folder>/reports/check\\.(?:${checkRoles.join('|')}|<role>)'
  r'\.<XXXXXX>\.txt\1(?!\S)',
);
final _skillName = RegExp(r'^([a-z0-9-]+):[a-z0-9-]+$');
final _nonLatinLetter = RegExp(r'[^\P{L}\p{Script=Latin}]', unicode: true);
final _claudeVariable = RegExp(r'\$\{CLAUDE_\w*\}?');
final _relativeMarkdownPath = RegExp(
  r'^(?:\.\.|\.|references|\.agents|\.claude|specstone-[\w-]+)(?:/[\w.-]+)+\.md$',
);

const _hostToolNames = {'Skill', 'Agent', 'Write', 'Edit', 'Read'};
const _claudeSkillsFolder = '.claude/skills/';
const _maxDescriptionLength = 1024;
const _frontmatterFence = '---\n';
const _frontmatterEndFence = '\n---\n';
const _tomlBodyStart = 'developer_instructions = """\n';
const _tomlBodyEnd = '"""';

/// Returns every file under [root] that git tracks, sorted by path: the file
/// set Specstone ships, with ignored files such as `.DS_Store` left out.
///
/// A [root] outside any git work tree, such as a fixture folder, has nothing
/// to ignore, so all its files are returned.
List<File> trackedFiles(Directory root) {
  if (!_isInsideWorkTree(root)) {
    return root.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }
  final result = Process.runSync(
    'git',
    ['ls-files', '-z', '--', '.'],
    workingDirectory: root.path,
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError('git ls-files failed: ${result.stderr}');
  }
  return [
    for (final path in (result.stdout as String).split('\u0000'))
      if (path.isNotEmpty) File.fromUri(root.uri.resolve(path)),
  ]..sort((a, b) => a.path.compareTo(b.path));
}

bool _isInsideWorkTree(Directory root) =>
    Process.runSync('git', [
      'rev-parse',
      '--is-inside-work-tree',
    ], workingDirectory: root.path).exitCode ==
    0;

/// Returns every tracked file of the skill folders `specstone-<name>/` and the
/// agent files `specstone-<name>.md` under [root], sorted by path.
///
/// Any other entry of [root], the `AGENT.md` asset among them, is left out.
List<File> agentSourceFiles(Directory root) => [
  for (final file in trackedFiles(root))
    if (_isAgentSource(_relativePath(root, file))) file,
];

bool _isAgentSource(String path) {
  final segments = path.split('/');
  if (!segments.first.startsWith('specstone-')) return false;
  return segments.length > 1 || path.endsWith('.md');
}

/// Returns the path of [file] below [agentAssetsRoot], with `/` separators.
String shippedPathOf(File file) {
  final root = agentAssetsRoot();
  final path = file.uri.toFilePath(windows: false);
  if (path.startsWith(root.uri.toFilePath(windows: false))) {
    return _relativePath(root, file);
  }
  throw ArgumentError('not a shipped file: $path');
}

/// Returns the folder that holds the skill and agent sources, beside the
/// `AGENT.md` asset in the core package.
Directory agentAssetsRoot() => Directory.fromUri(
  packageRoot().uri.resolve('../specstone_core/assets/agent/'),
);

/// One skill or agent file as a host reads it, with `\n` line ends.
///
/// `path` runs from the folder the file sits in: below the sources folder for
/// a source, from the project root for a render, with `/` separators.
/// `frontmatter` is the text before `body`, its fences included, or null when
/// the file has none; for a Codex TOML file it is everything before the
/// `developer_instructions` value, and `body` is that value unescaped.
typedef ContentFile = ({
  String path,
  String body,
  String? frontmatter,
  bool isSkillFile,
});

/// Returns the skill and agent sources and every host's render of them.
List<ContentFile> contentFiles() => [
  ...contentFilesOf(agentAssetsRoot()),
  ...renderedContentFiles(renderHostFiles()),
];

/// Whether [path] of the skill and agent sources is a file in a skill folder.
bool isSkillSourcePath(String path) => path.contains('/');

/// Returns the files [agentSourceFiles] finds under [root], as sources.
List<ContentFile> contentFilesOf(Directory root) => [
  for (final file in agentSourceFiles(root))
    _contentFile(
      _relativePath(root, file),
      file.readAsStringSync(),
      isSkillFile: isSkillSourcePath(_relativePath(root, file)),
    ),
];

/// Returns [rendered] as content files, a Codex TOML file read by its
/// `developer_instructions` value.
List<ContentFile> renderedContentFiles(List<RenderedFile> rendered) => [
  for (final file in rendered)
    _contentFile(
      file.path,
      file.text,
      isSkillFile:
          file.folder == AgentFolder.claudeSkills ||
          file.folder == AgentFolder.agentsSkills,
    ),
];

ContentFile _contentFile(
  String path,
  String rawText, {
  required bool isSkillFile,
}) {
  final text = rawText.replaceAll('\r\n', '\n');
  final (frontmatter, body) = switch (path) {
    _ when path.endsWith('.toml') => _tomlParts(text),
    _ when path.endsWith('.md') => _markdownParts(text),
    _ => (null, text),
  };
  return (
    path: path,
    body: body,
    frontmatter: frontmatter,
    isSkillFile: isSkillFile,
  );
}

(String?, String) _markdownParts(String text) {
  final end = text.indexOf(_frontmatterEndFence);
  if (!text.startsWith(_frontmatterFence) || end < 0) return (null, text);
  final split = end + _frontmatterEndFence.length;
  return (text.substring(0, split), text.substring(split));
}

(String?, String) _tomlParts(String text) {
  final start = text.indexOf(_tomlBodyStart);
  final end = text.lastIndexOf(_tomlBodyEnd);
  if (start < 0 || end < start) return (null, text);
  final bodyStart = start + _tomlBodyStart.length;
  return (
    text.substring(0, bodyStart),
    _tomlUnescape(text.substring(bodyStart, end)),
  );
}

String _tomlUnescape(String value) => value.replaceAllMapped(
  RegExp(r'\\(?:u([0-9a-fA-F]{4})|(.))', dotAll: true),
  (match) => match[1] != null
      ? String.fromCharCode(int.parse(match[1]!, radix: 16))
      : match[2]!,
);

String _textOf(ContentFile file) => '${file.frontmatter ?? ''}${file.body}';

/// Returns the problems in every CLI call that `.md` and `.toml` files of
/// [files] name, sorted.
///
/// Scans inline code spans and code block lines. A `specstone <word>` must
/// name a command of [runner], then one of its subcommands when it has any;
/// each `--flag` after it must be an option of that command or `help`.
List<String> unknownCliNames(
  List<ContentFile> files,
  SpecstoneCommandRunner runner,
) {
  final problems = <String>{};
  for (final file in _markdownFiles(files)) {
    for (final scanned in _codeTexts(_textOf(file))) {
      for (final call in _specstoneCall.allMatches(scanned)) {
        final problem = _problemOf(runner, scanned, call);
        if (problem != null) problems.add('${file.path}: $problem');
      }
    }
  }
  return problems.toList()..sort();
}

/// Returns one problem per `specstone check` call in a body of [files] that
/// lacks `--out <folder>/reports/check.<role>.<XXXXXX>.txt`, as `path: call`,
/// sorted.
///
/// Reads the code spans and code block lines [unknownCliNames] reads, bodies
/// only. `<role>` is one of [checkRoles] or the placeholder of a shared
/// reference; the path may be double-quoted.
List<String> checkCallsWithoutSavedFile(List<ContentFile> files) {
  final problems = <String>{};
  for (final file in _markdownFiles(files)) {
    for (final scanned in _codeTexts(file.body)) {
      for (final call in _specstoneCall.allMatches(scanned)) {
        if (call.group(1) != 'check') continue;
        final text = _callTextOf(scanned, call);
        if (!_savedCheckFile.hasMatch(text)) {
          problems.add('${file.path}: ${text.replaceAll(RegExp(r'\s+'), ' ')}');
        }
      }
    }
  }
  return problems.toList()..sort();
}

/// Returns one problem per host-tied text in the body of a file of [files],
/// sorted.
///
/// Host-tied text is a `${CLAUDE_` variable, a `.claude/skills/` path in a file
/// outside `.claude/`, or an inline code span that is a host's tool name:
/// `Skill`, `Agent`, `Write`, `Edit`, or `Read`. Frontmatter is never read.
List<String> hostTiedText(List<ContentFile> files) {
  final problems = <String>{};
  for (final file in files) {
    for (final variable in _claudeVariable.allMatches(file.body)) {
      problems.add('${file.path}: ${variable[0]}');
    }
    if (!file.path.startsWith('.claude/') &&
        file.body.contains(_claudeSkillsFolder)) {
      problems.add('${file.path}: $_claudeSkillsFolder');
    }
    for (final span in _inlineSpans(file.body)) {
      if (_hostToolNames.contains(span)) problems.add('${file.path}: `$span`');
    }
  }
  return problems.toList()..sort();
}

/// Returns one problem per `SKILL.md` of [files] whose `name` differs from its
/// folder or whose `description` passes 1,024 characters, sorted.
List<String> skillHeadProblems(List<ContentFile> files) {
  final problems = <String>[];
  for (final file in files) {
    final segments = file.path.split('/');
    if (!file.isSkillFile || segments.last != 'SKILL.md') continue;
    final folder = segments[segments.length - 2];
    final head = _headOf(file);
    final name = head?['name'];
    if (name != folder) {
      problems.add(
        name == null
            ? '${file.path}: no name'
            : '${file.path}: name $name is not $folder',
      );
    }
    final length = '${head?['description'] ?? ''}'.runes.length;
    if (length > _maxDescriptionLength) {
      problems.add(
        '${file.path}: description is $length characters, over '
        '$_maxDescriptionLength',
      );
    }
  }
  return problems..sort();
}

YamlMap? _headOf(ContentFile file) {
  final frontmatter = file.frontmatter;
  if (frontmatter == null) return null;
  final inner = frontmatter.substring(
    _frontmatterFence.length,
    frontmatter.length - _frontmatterEndFence.length,
  );
  final head = loadYaml(inner);
  return head is YamlMap ? head : null;
}

/// Returns one problem per backticked relative `.md` path in a render of
/// [files] that names no file of [files], sorted.
///
/// A path is read from the folder of a skill file, or from the project root in
/// an agent file. A sources folder holds its agents beside its skills, so
/// only renders are read. A span is a path only when its first segment is
/// `..`, `.`, `references`, `.agents`, `.claude`, or a `specstone-*` folder:
/// a project doc path such as `specs/x.md` is never read.
List<String> unresolvedPaths(List<ContentFile> files) {
  final known = {for (final file in files) file.path};
  final problems = <String>{};
  for (final file in files.where(_isRender)) {
    final folder = file.isSkillFile
        ? file.path.substring(0, file.path.lastIndexOf('/'))
        : '';
    for (final span in _inlineSpans(_textOf(file))) {
      if (!_relativeMarkdownPath.hasMatch(span)) continue;
      if (!known.contains(_joined(folder, span))) {
        problems.add('${file.path}: $span names no rendered file');
      }
    }
  }
  return problems.toList()..sort();
}

bool _isRender(ContentFile file) =>
    AgentFolder.values.any((folder) => file.path.startsWith('${folder.path}/'));

/// Returns [relative] from [folder] with `.` and `..` resolved, or null when
/// it climbs out of the root.
String? _joined(String folder, String relative) {
  final segments = <String>[
    ...folder.split('/').where((segment) => segment.isNotEmpty),
  ];
  for (final segment in relative.split('/')) {
    if (segment == '..') {
      if (segments.isEmpty) return null;
      segments.removeLast();
    } else if (segment != '.') {
      segments.add(segment);
    }
  }
  return segments.join('/');
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

/// Returns one problem per inline code span in a `.md` or `.toml` file of
/// [files] that names another plugin's skill, sorted.
///
/// A span names a skill when its whole text is `<prefix>:<name>`, two words of
/// lowercase letters, digits, and hyphens, and the prefix is not in
/// [docTypes]. Code blocks are never read: they hold whole commands.
List<String> otherPluginSkillNames(
  List<ContentFile> files,
  Set<String> docTypes,
) {
  final problems = <String>{};
  for (final file in _markdownFiles(files)) {
    for (final span in _inlineSpans(_textOf(file))) {
      final prefix = _skillName.firstMatch(span)?.group(1);
      if (prefix == null || docTypes.contains(prefix)) continue;
      problems.add("${file.path}: $span is another plugin's skill");
    }
  }
  return problems.toList()..sort();
}

/// Returns one problem per file of a skill in [files] over [limit] estimated
/// tokens, each file sized alone, sorted. Agent files are never sized.
///
/// A file's estimated tokens are its code points divided by 4 and rounded
/// down.
List<String> oversizedSkillFiles(List<ContentFile> files, {int limit = 1500}) {
  final problems = <String>[];
  for (final file in files.where((file) => file.isSkillFile)) {
    final tokens = _textOf(file).runes.length ~/ 4;
    if (tokens > limit) {
      problems.add('${file.path}: $tokens est. tokens, over $limit');
    }
  }
  return problems..sort();
}

/// Returns `<file>:<line>` for each line of a file under [root] that holds a
/// letter outside the Latin script, sorted.
///
/// The plugin is written in English; the agent speaks the Owner's language, so
/// a label in another script presumes one Owner's language.
List<String> nonLatinLetterLines(Directory root) {
  final problems = <String>[];
  for (final file in trackedFiles(root)) {
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      if (_nonLatinLetter.hasMatch(lines[index])) {
        problems.add('${_relativePath(root, file)}:${index + 1}');
      }
    }
  }
  return problems..sort();
}

Iterable<ContentFile> _markdownFiles(List<ContentFile> files) => files.where(
  (file) => file.path.endsWith('.md') || file.path.endsWith('.toml'),
);

String _relativePath(Directory root, FileSystemEntity entity) {
  final path = entity.uri
      .toFilePath(windows: false)
      .substring(root.uri.toFilePath(windows: false).length);
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
List<String> _callTokens(String scanned, RegExpMatch call) =>
    _callTextOf(scanned, call).split(RegExp(r'\s+')).skip(1).toList();

/// Returns the trimmed text of the call at [call], up to the next `specstone `
/// in the same span or line.
String _callTextOf(String scanned, RegExpMatch call) {
  final next = _specstoneCall
      .allMatches(scanned)
      .map((m) => m.start)
      .where((start) => start > call.start);
  final end = next.isEmpty ? scanned.length : next.first;
  return scanned.substring(call.start, end).trim();
}
