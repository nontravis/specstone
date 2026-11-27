import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:markdown/markdown.dart';
import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/setup_migration/models/rendered_file.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
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

/// Host tool names whose exact capitalized spelling skill prose never uses for
/// an English word, so a case-sensitive bare prose match is one.
const _bareHostToolNames = [
  'Grep',
  'Glob',
  'Bash',
  'WebFetch',
  'WebSearch',
  'AskUserQuestion',
  'TodoWrite',
  'MultiEdit',
  'NotebookEdit',
];
const _quotedHostToolNames = <String>{
  'Skill',
  'Agent',
  'Write',
  'Edit',
  'Read',
  'Task',
  ..._bareHostToolNames,
};
final _bareHostToolName = RegExp('\\b(?:${_bareHostToolNames.join('|')})\\b');
final _hostToolCall = RegExp('^(?:${_quotedHostToolNames.join('|')})\\(');
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
final class ContentFile {
  const new({
    required this.path,
    required this.body,
    required this.frontmatter,
    required this.isSkillFile,
  });

  final String path;
  final String body;
  final String? frontmatter;
  final bool isSkillFile;
}

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
  return ContentFile(
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

/// Returns every `specstone check` call in a body of [files] as `path: call`,
/// sorted, a call wrapped over lines on one line.
///
/// Reads the code spans and code block lines [unknownCliNames] reads, bodies
/// only.
List<String> checkCalls(List<ContentFile> files) {
  final calls = <String>{};
  for (final file in _markdownFiles(files)) {
    for (final scanned in _codeTexts(file.body)) {
      for (final call in _specstoneCall.allMatches(scanned)) {
        if (call.group(1) != 'check') continue;
        final text = _callTextOf(scanned, call).replaceAll(RegExp(r'\s+'), ' ');
        calls.add('${file.path}: $text');
      }
    }
  }
  return calls.toList()..sort();
}

/// Returns each call of [checkCalls] that lacks
/// `--out <folder>/reports/check.<role>.<XXXXXX>.txt`.
///
/// `<role>` is one of [checkRoles] or the placeholder of a shared reference;
/// the path may be double-quoted.
List<String> checkCallsWithoutSavedFile(List<ContentFile> files) => [
  for (final call in checkCalls(files))
    if (!_savedCheckFile.hasMatch(call)) call,
];

/// Returns one problem per host-tied text in the body of a file of [files],
/// sorted.
///
/// Host-tied text is a `${CLAUDE_` variable, a `.claude/skills/` path in a file
/// outside `.claude/`, an inline code span that is a host's tool name
/// ([_quotedHostToolNames]) or opens with one and `(`, or a bare whole word of
/// prose spelled as one of [_bareHostToolNames], case-sensitive,
/// code spans and blocks left out. Frontmatter is never read.
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
      if (_quotedHostToolNames.contains(span) || _hostToolCall.hasMatch(span)) {
        problems.add('${file.path}: `$span`');
      }
    }
    for (final text in _proseTexts(file.body)) {
      for (final name in _bareHostToolName.allMatches(text)) {
        problems.add('${file.path}: ${name[0]}');
      }
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

/// The doc types outside `prd-core` that the shipped packs define, plus the
/// retired ones, each with its path file name.
final class PackDocTypes {
  new(this.fileNameById, {this.typesBySectionKey = const {}});

  /// Reads the types from the packs the binary carries.
  factory shipped() => PackDocTypes.fromPackFiles(shippedPackFiles);

  /// Reads the types from [packFiles], keyed `<pack>/<file>`.
  ///
  /// A pack's type files give each `id` and `path`; [_retiredDocTypes] seeds
  /// the types no pack ships. A type `prd-core` defines is left out.
  factory fromPackFiles(Map<String, Uint8List> packFiles) {
    final foreign = <String, String?>{..._retiredDocTypes};
    final core = <String>{};
    final coreKeys = <String>{};
    final typesByKey = <String, Set<String>>{};
    for (final entry in packFiles.entries) {
      final segments = entry.key.split('/');
      if (segments.length != _packFileSegments ||
          !segments.last.endsWith('.yaml') ||
          segments.last == 'pack.yaml') {
        continue;
      }
      final node = loadYaml(utf8.decode(entry.value));
      if (node is! YamlMap || node['id'] is! String) continue;
      final id = node['id'] as String;
      final keys = _sectionKeysOf(node['sections']);
      if (segments.first == _corePackName) {
        core.add(id);
        coreKeys.addAll(keys);
      } else {
        foreign[id] = _fileNameOf(node['path']) ?? foreign[id];
        for (final key in keys) {
          typesByKey.putIfAbsent(key, () => {}).add(id);
        }
      }
    }
    return PackDocTypes(
      Map.of(foreign)..removeWhere((id, _) => core.contains(id)),
      typesBySectionKey: {
        for (final MapEntry(:key, :value) in typesByKey.entries)
          if (!coreKeys.contains(key)) key: (value.toList()..sort()),
      },
    );
  }

  /// Each type id with the file name of its path, null when the path holds
  /// `{nn}` or `{slug}` or the type has none.
  final Map<String, String?> fileNameById;

  /// Each section key a non-`prd-core` type defines and no `prd-core` type
  /// defines, with those type ids sorted.
  final Map<String, List<String>> typesBySectionKey;
}

const _corePackName = 'prd-core';
const _packFileSegments = 2;

/// The types no 2.0.0 pack ships, each with its path file name; `topic` has
/// none, as its path holds `{slug}`.
const _retiredDocTypes = <String, String?>{
  'error': 'ERROR.md',
  'project_error': 'ERROR.md',
  'domain': 'DOMAIN.md',
  'project_domain': 'DOMAIN.md',
  'project_integration': 'INTEGRATION.md',
  'auth': 'AUTH.md',
  'project_auth': 'AUTH.md',
  'topic': null,
};

Iterable<String> _sectionKeysOf(Object? sections) => [
  if (sections is YamlList)
    for (final section in sections)
      if (section is YamlMap && section['id'] is String)
        section['id'] as String,
];

String? _fileNameOf(Object? path) {
  if (path is! String) return null;
  final name = path.split('/').last;
  return name.contains('{') ? null : name;
}

/// Returns one `<file>: <type>` problem per doc type outside `prd-core` that a
/// `.md` or `.toml` file of [files] names, sorted.
///
/// A type is named by a `<type>:<name>` address, by its path file name with
/// the `.md` extension, such as `ARCHITECTURE.md`, or by a code span that is
/// its id or a section key only such types define. A span in [cliWords] passes.
/// Prose and fenced code are words other packs share, so inspection judges
/// them.
List<String> packDocTypeNames(
  List<ContentFile> files,
  PackDocTypes types, {
  required Set<String> cliWords,
}) {
  final ids = types.fileNameById.keys.toList()..sort();
  if (ids.isEmpty) return const [];
  final idByFileName = <String, String>{};
  for (final id in ids) {
    final fileName = types.fileNameById[id];
    if (fileName != null) idByFileName.putIfAbsent(fileName, () => id);
  }
  final address = RegExp(
    '(?<![A-Za-z0-9_])(${ids.map(RegExp.escape).join('|')}):[A-Za-z0-9_<]',
  );
  final fileNames = idByFileName.keys.map(RegExp.escape).join('|');
  final fileName = idByFileName.isEmpty
      ? null
      : RegExp('(?<![A-Za-z0-9_])($fileNames)');
  final problems = <String>{};
  for (final file in _markdownFiles(files)) {
    final text = _textOf(file);
    for (final match in address.allMatches(text)) {
      problems.add('${file.path}: ${match.group(1)}');
    }
    for (final match in fileName?.allMatches(text) ?? const <RegExpMatch>[]) {
      problems.add('${file.path}: ${idByFileName[match.group(1)]}');
    }
    for (final span in _inlineSpans(text)) {
      if (cliWords.contains(span)) continue;
      if (types.fileNameById.containsKey(span)) {
        problems.add('${file.path}: $span');
      } else if (types.typesBySectionKey[span] case final owners?) {
        problems.add('${file.path}: $span of ${owners.join(', ')}');
      }
    }
  }
  return problems.toList()..sort();
}

/// Returns every command name and option name of every command of [runner],
/// subcommands included, with no `--`.
Set<String> cliWordsOf(SpecstoneCommandRunner runner) {
  final words = <String>{};
  void collect(Command<int> command) {
    words
      ..add(command.name)
      ..addAll(command.argParser.options.keys);
    command.subcommands.values.forEach(collect);
  }

  runner.commands.values.forEach(collect);
  return words;
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

/// Yields each text run of [markdown] outside every code span and code block.
Iterable<String> _proseTexts(String markdown) sync* {
  Iterable<String> walk(Iterable<Node> nodes) sync* {
    for (final node in nodes) {
      if (node is Text) {
        yield node.text;
      } else if (node is Element && node.tag != 'pre' && node.tag != 'code') {
        yield* walk(node.children ?? const []);
      }
    }
  }

  yield* walk(_parse(markdown));
}

final class _Code {
  const new(this.text, {required this.isBlock});

  final String text;
  final bool isBlock;
}

/// Returns each code block (fenced or indented) and inline code span of
/// [markdown], in text order.
List<_Code> _codeOf(String markdown) {
  final found = <_Code>[];
  void walk(Iterable<Node> nodes) {
    for (final node in nodes.whereType<Element>()) {
      switch (node.tag) {
        case 'pre':
          found.add(_Code(node.textContent, isBlock: true));
        case 'code':
          found.add(_Code(node.textContent, isBlock: false));
        default:
          walk(node.children ?? const []);
      }
    }
  }

  walk(_parse(markdown));
  return found;
}

List<Node> _parse(String markdown) {
  // encodeHtml off keeps text as written: `<type>`, not `&lt;type&gt;`.
  final document = Document(
    extensionSet: ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  return document.parse(markdown);
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
