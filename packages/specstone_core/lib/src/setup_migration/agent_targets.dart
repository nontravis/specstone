import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/journal_bounds.dart'
    show skippedLineOf, writeRefusalOf;
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show textHashOf;
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show codeRootFiles;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/release_version.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart'
    show relativeFolderPath;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show isPortableCodeEntry;

const _agentMdPath = '.specstone/AGENT.md';
const _cursorFolder = '.cursor';
const _gitEntry = '.git';
const _codeField = 'code';
const _docsFolder = 'docs/';
const _pathSeparator = '/';
const _defaultInstructionName = 'AGENTS.md';
const _agentsLinePrefix = 'agent files: ';
const _malformedMessage =
    'the Specstone marker lines are malformed; repair the block by hand so '
    'the file holds one BEGIN line and one END line after it, or neither, '
    'then run the command again';
const _fenceMessage =
    'close the code fence that opens on this line, then run the command '
    'again';
const _byteOrderMark = '﻿';
final _separators = RegExp(r'[/\\]');
final _beginToken = RegExp(r'<!-- BEGIN specstone v(\S+) -->');

/// The pack versions from which the agent files are written once.
///
/// A pack upgrade that moves one of these pins up from below its version runs
/// the full agent file upsert
/// (`setup_migration/set_up_new_project/write_agent_files`).
final Map<String, PackVersion> agentFilesSince = Map.unmodifiable({
  for (final (pack, version) in const [
    ('prd-core', '1.7.0'),
    ('software-tech', '1.4.0'),
  ])
    pack: PackVersion.parse(version, file: 'agent_targets.dart', key: pack),
});

/// Returns the nearest folder at or above [folder] holding a `.git` entry,
/// folder or file, or null when none does.
///
/// Starts no `git` process. A [folder] that does not exist walks up from its
/// nearest parent that does.
Directory? repositoryTopOf(Directory folder) {
  var current = _canonicalOf(folder);
  while (true) {
    final entry = current.uri.resolve(_gitEntry).toFilePath();
    if (FileSystemEntity.typeSync(entry, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) return null;
    current = parent;
  }
}

/// Returns the folders of the code roots: [codeRoot] from [projectRoot], then
/// each of [codeEntries] from [codeRoot], each once.
///
/// An entry that is no relative `/` path ([isPortableCodeEntry]) names no
/// folder, as the code file lister reads it: a drive letter would throw on
/// Windows, and a `\` would turn into a `/` and reach a folder above the root.
List<Directory> codeRootFolders(
  Directory projectRoot, {
  required String codeRoot,
  required Iterable<String> codeEntries,
}) {
  final base = projectRoot.uri.resolveUri(Uri(path: '$codeRoot/'));
  final folders = <String, Directory>{};
  for (final uri in [
    base,
    for (final entry in codeEntries.where(isPortableCodeEntry))
      base.resolveUri(Uri(path: entry)),
  ]) {
    final folder = _canonicalOf(Directory.fromUri(uri));
    folders.putIfAbsent(folder.path, () => folder);
  }
  return folders.values.toList();
}

/// Returns the folders of the code roots: each of [targets]' code roots, then
/// each `code:` entry of that target's docs under [set], each folder once.
///
/// A shared doc's entries count for no target when [targets] holds two or more.
/// The one source of code roots for `check`, `chooseRun`, `init`, and upgrade.
List<Directory> codeFoldersOf(
  Directory projectRoot,
  MergedSet set, {
  required List<CodeTarget> targets,
}) {
  final entriesOf = _entriesByTarget(projectRoot, set, targets);
  final folders = <String, Directory>{};
  for (final target in targets) {
    for (final folder in codeRootFolders(
      projectRoot,
      codeRoot: target.codeRoot,
      codeEntries: entriesOf[target] ?? const {},
    )) {
      folders.putIfAbsent(folder.path, () => folder);
    }
  }
  return folders.values.toList();
}

/// Returns the code files of [targets], each as its path from the code root
/// of the target that lists it.
///
/// A target lists the files under the `code:` entries of its own docs, read
/// from its own root; a file under the root of another target nested in its
/// own belongs to that target. A shared doc's entries count for no target when
/// [targets] holds two or more. Roots and entries are read as
/// `filesUnderCodeRoot` reads them.
List<({Directory root, String path})> codeFilesOf(
  Directory projectRoot,
  MergedSet set, {
  required List<CodeTarget> targets,
}) {
  final entriesOf = _entriesByTarget(projectRoot, set, targets);
  final roots = [
    for (final target in targets)
      codeRootFolders(
        projectRoot,
        codeRoot: target.codeRoot,
        codeEntries: const [],
      ).first,
  ];
  return [
    for (var index = 0; index < targets.length; index++)
      for (final path in codeRootFiles(
        roots[index],
        entriesOf[targets[index]] ?? const {},
        skipFolders: _nestedRootsOf(roots[index], roots),
      ))
        (root: roots[index], path: path),
  ];
}

/// Returns the `code:` entries of each target's docs; a shared doc's entries
/// go to the one target of a single-target project.
Map<CodeTarget, Set<String>> _entriesByTarget(
  Directory projectRoot,
  MergedSet set,
  List<CodeTarget> targets,
) {
  final entriesOf = <CodeTarget, Set<String>>{};
  for (final (:target, :entry) in _codeEntriesOf(
    projectRoot,
    set,
    targetNames: targetNamesOf(targets),
  )) {
    final owner = _ownerOf(targets, target);
    if (owner != null) entriesOf.putIfAbsent(owner, () => {}).add(entry);
  }
  return entriesOf;
}

/// Returns the folders of the roots in [roots] that lie inside [own], as paths
/// from [own] in `/` form.
List<String> _nestedRootsOf(Directory own, List<Directory> roots) {
  final prefix = own.path.endsWith(Platform.pathSeparator)
      ? own.path
      : '${own.path}${Platform.pathSeparator}';
  return [
    for (final other in roots)
      if (other.path.length > prefix.length && other.path.startsWith(prefix))
        other.path
            .substring(prefix.length)
            .split(Platform.pathSeparator)
            .join(_pathSeparator),
  ];
}

/// Returns the target the doc named [name] belongs to; a shared doc (null
/// [name]) belongs to the one target of a single-target project, else to none.
CodeTarget? _ownerOf(List<CodeTarget> targets, String? name) {
  if (name == null) return targets.length == 1 ? targets.first : null;
  return targets.where((target) => target.name == name).firstOrNull;
}

/// Returns the `code:` entries of every doc under `docs/` whose type holds the
/// `code` field, each once, in doc path order.
///
/// [targetNames] are the config's, so a per-target doc is matched and read.
List<String> codeEntriesOnDisk(
  Directory projectRoot,
  MergedSet set, {
  required List<String> targetNames,
}) => {
  for (final (target: _, :entry) in _codeEntriesOf(
    projectRoot,
    set,
    targetNames: targetNames,
  ))
    entry,
}.toList();

/// Returns the `code:` entries of each doc whose type holds the `code` field,
/// in doc path order, with the target the doc's path names; null for a shared
/// doc.
Iterable<({String? target, String entry})> _codeEntriesOf(
  Directory projectRoot,
  MergedSet set, {
  required List<String> targetNames,
}) sync* {
  final docsRoot = Directory.fromUri(projectRoot.uri.resolve(_docsFolder));
  if (!docsRoot.existsSync()) return;
  final matcher = DocTypeMatcher(set, targetNames: targetNames);
  final prefixLength = docsRoot.uri.path.length;
  final docs = <String, File>{
    for (final entity in docsRoot.listSync(recursive: true, followLinks: false))
      if (entity is File && entity.path.endsWith('.md'))
        Uri.decodeComponent(entity.uri.path.substring(prefixLength)): entity,
  };
  for (final docPath in docs.keys.toList()..sort(compareCodePoints)) {
    final match = matcher.match(docPath);
    if (match is! MatchedDocType) continue;
    if (!match.docType.fields.any((field) => field.id == _codeField)) continue;
    final text = _decode(readPlanInput(docs[docPath]!));
    if (text == null) continue;
    for (final (:value, line: _, text: _) in DocLines.of(
      toLf(text),
    ).entriesOf(_codeField)) {
      if (value is String) yield (target: match.target, entry: value);
    }
  }
}

/// What `init`, `migrate`, and `check` need to find the agent files.
final class AgentFileInputs {
  const new({
    required this.projectRoot,
    required this.cliVersion,
    required this.codeRootFolders,
    required this.agentFileRoots,
  });

  /// The canonical project root.
  final Directory projectRoot;

  /// The running CLI's Version.
  final String cliVersion;

  /// The code root folders, from [codeRootFolders].
  final List<Directory> codeRootFolders;

  /// The tops `agent_file_roots` lists, each as a path from [projectRoot].
  final List<String> agentFileRoots;
}

/// The reasons an agent file differs from what the CLI writes.
enum AgentDriftKind {
  /// A block, or a rules file, differs from what the CLI writes.
  blockStale,

  /// `.specstone/AGENT.md` holds other bytes.
  agentMdStale,

  /// An import block names a `.specstone/AGENT.md` that is missing.
  agentMdMissing,

  /// A repository top that `agent_file_roots` does not list.
  topUnlisted,

  /// The Specstone marker lines of a file are malformed.
  markersMalformed,

  /// A code fence of a file is still open at its end.
  codeFenceOpen,
}

/// One drift: its path from the project root, `/`-separated, its 1-based
/// line, and its kind.
typedef AgentDrift = ({String path, int line, AgentDriftKind kind});

/// Returns every drift of the agent files at the project root and at each
/// repository top, in the order of the files.
///
/// The one predicate `check` and `migrate` call: it is empty exactly when
/// [planAgentWrites] with `full: false` has nothing to do, bar a malformed
/// file. A file whose real path lies outside the project root is no drift,
/// since no run writes it (R99).
List<AgentDrift> agentFileDrifts(AgentFileInputs inputs) {
  final survey = _Survey.of(inputs);
  final root = _canonicalOf(inputs.projectRoot);
  final drifts = <AgentDrift>[];
  if (survey.agentMd.exists &&
      !survey.agentMd.matches &&
      _isWritable(root, survey.agentMd.realPath)) {
    drifts.add((
      path: _agentMdPath,
      line: 1,
      kind: AgentDriftKind.agentMdStale,
    ));
  }
  for (final folder in survey.folders) {
    // A top outside the project root is never listed (R99), and a file no run
    // may write (outside the root or under `.git`) has no drift a run could
    // fix; a file that links into the project still has.
    if (folder.isUnlisted && !_isOutside(folder.path)) {
      drifts.add((
        path: folder.path,
        line: 1,
        kind: AgentDriftKind.topUnlisted,
      ));
    }
    for (final file in folder.files.where(
      (file) => file.exists && _isWritable(root, file.realPath),
    )) {
      drifts.addAll(
        file.drifts(
          isAgentMdMissing: !survey.agentMd.exists,
          isChecked: !folder.isUnlisted,
        ),
      );
    }
  }
  return drifts;
}

/// One agent file write.
final class AgentWrite {
  const new({
    required this.path,
    required this.text,
    required this.isNew,
    required this.before,
    required this.isAtTop,
  });

  /// The path from the project root; it may name a symbolic link, which the
  /// writer must write through to the link's target.
  final String path;

  /// The whole new file text, in the file's own line ending.
  final String text;

  /// Whether the file does not exist yet.
  final bool isNew;

  /// The [textHashOf] of the existing file's text; null for a new file.
  final String? before;

  /// Whether the file lies at a repository top, outside the project's commits.
  final bool isAtTop;
}

/// The agent file writes of one run.
final class AgentWritePlan {
  const new({
    required this.rootWrites,
    required this.topWrites,
    required this.agentFileRoots,
    required this.addedRoots,
    required this.writeSet,
    this.skipped = const [],
  });

  /// The writes at the project root, `.specstone/AGENT.md` first.
  final List<AgentWrite> rootWrites;

  /// The writes at repository tops.
  final List<AgentWrite> topWrites;

  /// The full new `agent_file_roots` list.
  final List<String> agentFileRoots;

  /// The tops this run lists for the first time, in [agentFileRoots] order.
  final List<String> addedRoots;

  /// The canonical path of every agent file the plan lists, each inside the
  /// project root.
  ///
  /// A migrate records it with its journal, so a replay admits these paths
  /// and no others.
  final Set<String> writeSet;

  /// The warning line for each agent file the run would write but leaves,
  /// because its real path lies outside the project root or under `.git`
  /// (R99).
  final List<String> skipped;

  /// The plan's `agent files:` line, empty when no file is written.
  String get line {
    final paths = [
      for (final write in [...rootWrites, ...topWrites]) write.path,
    ];
    return paths.isEmpty ? '' : '$_agentsLinePrefix${paths.join(', ')}';
  }

  /// Whether the run writes no file and lists no new top.
  bool get isEmpty =>
      rootWrites.isEmpty && topWrites.isEmpty && addedRoots.isEmpty;
}

/// Plans the agent file writes of [inputs].
///
/// [full] is the `init`, legacy, and one-time upgrade upsert at the project
/// root; otherwise the root and each listed top only refresh what exists. An
/// unlisted top always takes the full upsert once. Reads every file first.
///
/// Throws `MigrateFault` `agent_block_malformed`, naming every malformed file
/// with its first marker line, before it returns.
AgentWritePlan planAgentWrites(AgentFileInputs inputs, {required bool full}) {
  final survey = _Survey.of(inputs)..throwIfMalformed();
  final root = _canonicalOf(inputs.projectRoot);
  final rootWrites = <AgentWrite>[];
  final topWrites = <AgentWrite>[];
  final added = <String>[];
  final skipped = <String>[];
  final writeSet = <String>{};
  var hasImport = false;
  for (final folder in survey.folders) {
    for (final file in folder.files) {
      final isUpsert = survey.isUpsert(folder, file, full: full);
      final text = file.nextText(isUpsert: isUpsert);
      final refusal = writeRefusalOf(file.realPath, projectRoot: root);
      if (refusal != null) {
        if (text != null) skipped.add(skippedLineOf(file.path, refusal));
        continue;
      }
      hasImport = hasImport || file.importsAfter(isUpsert: isUpsert);
      if (text == null) continue;
      writeSet.add(file.realPath);
      (folder.isTop ? topWrites : rootWrites).add(
        AgentWrite(
          path: file.path,
          text: text,
          isNew: !file.exists,
          before: file.current.hashOrNull,
          isAtTop: folder.isTop,
        ),
      );
    }
    if (folder.isUnlisted && !_isOutside(folder.path)) added.add(folder.path);
  }
  final agentMd = survey.agentMd;
  if (!agentMd.matches && (full || agentMd.exists || hasImport)) {
    final refusal = writeRefusalOf(agentMd.realPath, projectRoot: root);
    if (refusal == null) {
      writeSet.add(agentMd.realPath);
      rootWrites.insert(
        0,
        AgentWrite(
          path: _agentMdPath,
          text: agentMdText,
          isNew: !agentMd.exists,
          before: agentMd.before,
          isAtTop: false,
        ),
      );
    } else {
      skipped.insert(0, skippedLineOf(_agentMdPath, refusal));
    }
  }
  return AgentWritePlan(
    rootWrites: rootWrites,
    topWrites: topWrites,
    agentFileRoots: [...inputs.agentFileRoots, ...added],
    addedRoots: added,
    writeSet: writeSet,
    skipped: skipped,
  );
}

/// The state of `.specstone/AGENT.md`.
final class _AgentMd {
  const new({
    required this.realPath,
    required this.exists,
    required this.matches,
    this.before,
  });

  /// The canonical path of the file the run writes, every link resolved.
  final String realPath;

  final bool exists;
  final bool matches;

  /// The [textHashOf] of the existing file's text; null when it is missing.
  final String? before;
}

/// One agent file as found on disk, or as a full upsert would create it.
final class _AgentFile {
  new({
    required this.path,
    required this.realPath,
    required this.block,
    required this.expected,
    required this.current,
    required this.isImport,
    required this.isCursor,
  }) : scan = current == null ? null : scanMarkers(current);

  /// The path from the project root.
  final String path;

  /// The canonical path of the file the run writes, every link resolved.
  final String realPath;

  /// The block the CLI writes into this file.
  final String block;

  /// The whole text the CLI writes into a new file: [block], or the rules
  /// file with its frontmatter.
  final String expected;

  /// The file text, a leading byte order mark kept; null when it is missing.
  final String? current;
  final bool isImport;
  final bool isCursor;
  final MarkerScan? scan;

  bool get exists => current != null;

  bool get isMalformed => scan?.isMalformed ?? false;

  bool get _hasBlock => scan?.beginLine != null;

  /// Returns the new file text, or null when the file stays as it is.
  ///
  /// A missing file is created only when [isUpsert]; a file with no block
  /// gets one only then too.
  String? nextText({required bool isUpsert}) {
    final text = current;
    if (text == null) return isUpsert ? expected : null;
    if (isCursor) return _rewrittenCursor(text);
    if (!_hasBlock && !isUpsert) return null;
    return upsertBlock(text, block);
  }

  /// Whether the file holds an import block once the run has written.
  bool importsAfter({required bool isUpsert}) =>
      isImport && exists && (_hasBlock || isUpsert);

  /// Returns this file's drifts; the stale and missing ones only when
  /// [isChecked].
  Iterable<AgentDrift> drifts({
    required bool isAgentMdMissing,
    required bool isChecked,
  }) sync* {
    final marker = scan!;
    if (marker.isMalformed) {
      yield (
        path: path,
        line: marker.firstMarkerLine!,
        kind: marker.openFenceLine == null
            ? AgentDriftKind.markersMalformed
            : AgentDriftKind.codeFenceOpen,
      );
      return;
    }
    if (!isChecked) return;
    final begin = marker.beginLine;
    if (nextText(isUpsert: false) != null) {
      yield (
        path: path,
        line: _staleLine(begin),
        kind: AgentDriftKind.blockStale,
      );
    }
    if (isImport && begin != null && isAgentMdMissing) {
      yield (path: path, line: begin, kind: AgentDriftKind.agentMdMissing);
    }
  }

  /// The BEGIN line when the block body differs, else 1 for a rules file
  /// whose frontmatter alone differs.
  int _staleLine(int? begin) {
    if (!isCursor) return begin!;
    return begin != null && upsertBlock(current!, block) != null ? begin : 1;
  }

  String? _rewrittenCursor(String text) {
    final bom = text.startsWith(_byteOrderMark) ? _byteOrderMark : '';
    final lf = toLf(text.substring(bom.length));
    if (_withoutVersion(lf) == _withoutVersion(expected)) return null;
    return '$bom${LineEnding.of(text).apply(expected)}';
  }

  static String _withoutVersion(String text) {
    for (final match in _beginToken.allMatches(text)) {
      if (ReleaseVersion.tryParse(match[1]!) != null) {
        return text.replaceRange(match.start, match.end, '');
      }
    }
    return text;
  }
}

/// One folder that takes agent files: the project root or a repository top.
final class _Folder {
  const new({
    required this.path,
    required this.isTop,
    required this.isListed,
    required this.files,
  });

  /// The path from the project root, empty for the root.
  final String path;
  final bool isTop;
  final bool isListed;
  final List<_AgentFile> files;

  bool get isUnlisted => isTop && !isListed;

  /// Whether the run may create files and blocks here.
  ///
  /// The root follows [full]; a listed top only refreshes; an unlisted top
  /// takes the full upsert once.
  bool isUpsert({required bool full}) => isTop ? !isListed : full;

  _Folder withFiles(List<_AgentFile> files) =>
      _Folder(path: path, isTop: isTop, isListed: isListed, files: files);
}

/// The agent files of a run, read once, each real file once.
final class _Survey {
  const new(this.folders, this.agentMd, this._topUpserted);

  /// Reads the root first, then each qualifying top; a real file two folders
  /// reach keeps its first name only, so no two writes land on it.
  factory of(AgentFileInputs inputs) {
    final root = _canonicalOf(inputs.projectRoot);
    final listed = {
      for (final entry in inputs.agentFileRoots)
        _canonicalOf(
          Directory.fromUri(root.uri.resolveUri(Uri(path: '$entry/'))),
        ).path,
    };
    final tops = _qualifyingTops(root, inputs.codeRootFolders);
    final (:folders, :topUpserted) = _eachFileOnce([
      _Folder(
        path: '',
        isTop: false,
        isListed: true,
        files: _filesIn(root, '', root: root, cliVersion: inputs.cliVersion),
      ),
      for (final MapEntry(key: path, value: top) in tops.entries)
        _Folder(
          path: path,
          isTop: true,
          isListed: listed.contains(top.path),
          files: _filesIn(top, path, root: root, cliVersion: inputs.cliVersion),
        ),
    ]);
    return _Survey(folders, _agentMdOf(root), topUpserted);
  }

  final List<_Folder> folders;
  final _AgentMd agentMd;

  /// The real paths of the kept files an unlisted top also names.
  final Set<String> _topUpserted;

  /// Whether the run may create [file] in [folder] or give it a block: by
  /// the folder's rule, or because an unlisted top names it too.
  bool isUpsert(_Folder folder, _AgentFile file, {required bool full}) =>
      folder.isUpsert(full: full) || _topUpserted.contains(file.realPath);

  /// Throws the `agent_block_malformed` fault when any file is malformed.
  void throwIfMalformed() {
    final faults = [
      for (final folder in folders)
        for (final file in folder.files)
          if (file.isMalformed)
            MigrateFault(
              MigrateFaultCode.agentBlockMalformed,
              file.scan!.openFenceLine == null
                  ? _malformedMessage
                  : _fenceMessage,
              file: file.path,
              line: file.scan!.firstMarkerLine,
            ),
    ];
    if (faults.isEmpty) return;
    throw MigrateFault(
      faults.first.code,
      faults.first.message,
      file: faults.first.file,
      line: faults.first.line,
      more: faults.skip(1).toList(),
    );
  }
}

/// Returns [folders] with each real file in the first folder that names it,
/// and the real paths of the kept files a later unlisted top names too.
({List<_Folder> folders, Set<String> topUpserted}) _eachFileOnce(
  List<_Folder> folders,
) {
  final seen = <String>{};
  final topUpserted = <String>{};
  final kept = <_Folder>[];
  for (final folder in folders) {
    final files = <_AgentFile>[];
    for (final file in folder.files) {
      if (seen.add(file.realPath)) {
        files.add(file);
      } else if (folder.isUnlisted) {
        topUpserted.add(file.realPath);
      }
    }
    kept.add(folder.withFiles(files));
  }
  return (folders: kept, topUpserted: topUpserted);
}

/// Returns the qualifying repository tops of [folders], by their path from
/// [root], in code point order, each once.
///
/// A top qualifies unless its work tree holds [root] (E17).
Map<String, Directory> _qualifyingTops(
  Directory root,
  List<Directory> folders,
) {
  final tops = <String, Directory>{};
  for (final folder in folders) {
    final top = repositoryTopOf(folder);
    if (top == null) continue;
    final toRoot = relativeFolderPath(top, root);
    final path = relativeFolderPath(root, top);
    if (toRoot == null || path == null || !_isOutside(toRoot)) continue;
    // A top the config reader would refuse as an `agent_file_roots` entry.
    if (!isPortableCodeEntry(path)) continue;
    tops[path] = top;
  }
  final paths = tops.keys.toList()..sort(compareCodePoints);
  return {for (final path in paths) path: tops[path]!};
}

/// Whether the relative [path] leaves its start folder.
bool _isOutside(String path) => path == '..' || path.startsWith('../');

/// Whether a run may write the file at the canonical [path]: it lies inside
/// the canonical project [root] and below no `.git` entry (R99).
bool _isWritable(Directory root, String path) =>
    writeRefusalOf(path, projectRoot: root) == null;

/// Returns the agent files of [folder], an existing file once per real file,
/// and the file a full upsert would create.
List<_AgentFile> _filesIn(
  Directory folder,
  String prefix, {
  required Directory root,
  required String cliVersion,
}) {
  final toRoot = relativeFolderPath(folder, root) ?? '.';
  final stem = toRoot == '.' ? '' : '$toRoot/';
  final importBlockText = importBlock(
    cliVersion: cliVersion,
    agentMdPath: '$stem$_agentMdPath',
    projectDocPath: '$stem${_docsFolder}prds/PROJECT.md',
  );
  final inlineBlockText = inlineBlock(cliVersion: cliVersion);
  final namesByFile = <String, List<String>>{};
  for (final name in agentInstructionNames) {
    final file = _fileIn(folder, name);
    if (FileSystemEntity.typeSync(file.path) != FileSystemEntityType.file) {
      continue;
    }
    (namesByFile[file.resolveSymbolicLinksSync()] ??= []).add(name);
  }
  String pathOf(String name) => prefix.isEmpty ? name : '$prefix/$name';
  final files = <_AgentFile>[];
  for (final MapEntry(key: realPath, value: names) in namesByFile.entries) {
    final text = _readAgentText(_fileIn(folder, names.first));
    if (text == null) continue;
    final isImport = names.every(agentImportNames.contains);
    final block = isImport ? importBlockText : inlineBlockText;
    files.add(
      _AgentFile(
        path: pathOf(names.first),
        realPath: realPath,
        block: block,
        expected: block,
        current: text,
        isImport: isImport,
        isCursor: false,
      ),
    );
  }
  final hasInstruction = namesByFile.isNotEmpty;
  final hasCursorFolder =
      FileSystemEntity.typeSync(_fileIn(folder, _cursorFolder).path) ==
      FileSystemEntityType.directory;
  if (!hasInstruction && !hasCursorFolder) {
    files.add(
      _AgentFile(
        path: pathOf(_defaultInstructionName),
        realPath: _realPathOf(_fileIn(folder, _defaultInstructionName)),
        block: inlineBlockText,
        expected: inlineBlockText,
        current: null,
        isImport: false,
        isCursor: false,
      ),
    );
  }
  final cursor = _fileIn(folder, agentCursorPath);
  final cursorText = cursor.existsSync() ? _readAgentText(cursor) : null;
  if (cursor.existsSync() ? cursorText != null : hasCursorFolder) {
    files.add(
      _AgentFile(
        path: pathOf(agentCursorPath),
        realPath: _realPathOf(cursor),
        block: inlineBlockText,
        expected: cursorRulesText(cliVersion: cliVersion),
        current: cursorText,
        isImport: false,
        isCursor: true,
      ),
    );
  }
  return files;
}

_AgentMd _agentMdOf(Directory root) {
  final file = _fileIn(root, _agentMdPath);
  final realPath = _realPathOf(file);
  if (!file.existsSync()) {
    return _AgentMd(realPath: realPath, exists: false, matches: false);
  }
  final bytes = readPlanInput(file);
  return _AgentMd(
    realPath: realPath,
    exists: true,
    matches: _sameBytes(bytes, utf8.encode(agentMdText)),
    before: textHashOf(utf8.decode(bytes, allowMalformed: true)),
  );
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

File _fileIn(Directory folder, String relative) =>
    File.fromUri(folder.uri.resolve(relative));

/// Returns the real path of [file], every link on it resolved; a missing
/// file keeps its name under its folder's canonical path.
String _realPathOf(File file) => file.existsSync()
    ? file.resolveSymbolicLinksSync()
    : _fileIn(_canonicalOf(file.parent), file.uri.pathSegments.last).path;

/// Returns the canonical [folder], or its absolute normalized path when it
/// does not exist.
Directory _canonicalOf(Directory folder) {
  var existing = _withoutFinalSeparator(
    folder.absolute.uri.normalizePath().toFilePath(),
  );
  final missing = <String>[];
  while (FileSystemEntity.typeSync(existing) == FileSystemEntityType.notFound) {
    final parent = Directory(existing).parent.path;
    if (parent == existing) return Directory(existing);
    missing.add(existing.substring(parent.length).replaceAll(_separators, ''));
    existing = parent;
  }
  final resolved = Directory(existing).resolveSymbolicLinksSync();
  return Directory(
    missing.isEmpty
        ? resolved
        : _withoutFinalSeparator(
            [resolved, ...missing.reversed].join(Platform.pathSeparator),
          ),
  );
}

String _withoutFinalSeparator(String path) {
  final isRoot = path.length <= 1 || path.endsWith(r':\');
  return !isRoot && path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
}

/// Returns [bytes] as text without a byte order mark, or null when they are
/// not UTF-8.
String? _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// Returns the text of [file] with its byte order mark kept, or null when it
/// is not UTF-8.
String? _readAgentText(File file) {
  final bytes = readPlanInput(file);
  final text = _decode(bytes);
  final hasMark =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  return text == null ? null : (hasMark ? '$_byteOrderMark$text' : text);
}

extension on String? {
  /// The [textHashOf] of this text, or null for a missing file.
  String? get hashOrNull => switch (this) {
    final String text => textHashOf(text),
    null => null,
  };
}
