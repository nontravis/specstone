import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/document_writing/journal_bounds.dart'
    show skippedLineOf, writeRefusalOf;
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show textHashOf;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

const _ownedPrefix = 'specstone-';

/// Why a skill or agent file needs a run.
enum SkillFileDriftKind {
  /// The file's bytes differ from what the CLI writes.
  differs,

  /// The file is missing from a folder of a group in use.
  missing,

  /// The CLI no longer ships the file.
  unshipped,
}

/// One drift: its path from the project root, `/`-separated, and its kind.
typedef SkillFileDrift = ({String path, SkillFileDriftKind kind});

/// The skill and agent file changes of one run, every path from the project
/// root with `/` separators.
///
/// `trash` lists each path to move to the trash: the folder or file of a
/// `specstone-*` entry the CLI ships nothing of, which moves whole, and each
/// unshipped file inside an entry it ships. `skipped` holds the warning line
/// for each folder or file the run leaves because its real path lies outside
/// the project root or under `.git`.
typedef SkillFilePlan = ({
  List<AgentWrite> writes,
  List<String> trash,
  List<String> skipped,
  Set<String> writeSet,
});

/// Plans the `specstone-*` skill and agent file changes of [inputs], by folder
/// group at the project root and at each repository top.
///
/// [full] is the `init`, legacy, and one-time upgrade upsert at the project
/// root; otherwise a folder group takes writes only while one of its folders
/// holds a `specstone-*` entry. An unlisted top always takes the full upsert
/// once. Entries not named `specstone-*` are never read.
SkillFilePlan planSkillAndAgentFiles(
  AgentFileInputs inputs, {
  required bool full,
}) {
  final bases = agentFileBasesOf(inputs);
  final planner = _Planner(bases.first.directory);
  for (final base in bases) {
    planner.plan(base, full: full);
  }
  return (
    writes: planner.writes,
    trash: planner.trash,
    skipped: planner.skipped,
    writeSet: planner.writeSet,
  );
}

/// Returns the skill or agent folder that holds [path], from the project root
/// with `/` separators, or null when [path] is no skill or agent file.
String? skillFolderOf(String path) {
  final padded = '/$path';
  for (final folder in AgentFolder.values) {
    final index = padded.indexOf('/${folder.path}/');
    if (index >= 0) return path.substring(0, index + folder.path.length);
  }
  return null;
}

/// Returns every drift of the skill and agent files, in plan order.
///
/// Empty exactly when [planSkillAndAgentFiles] with `full: false` has nothing
/// to write or trash.
List<SkillFileDrift> skillAndAgentFileDrifts(AgentFileInputs inputs) {
  final plan = planSkillAndAgentFiles(inputs, full: false);
  return [
    for (final write in plan.writes)
      (
        path: write.path,
        kind: write.isNew
            ? SkillFileDriftKind.missing
            : SkillFileDriftKind.differs,
      ),
    for (final path in plan.trash)
      (path: path, kind: SkillFileDriftKind.unshipped),
  ];
}

final class _Planner {
  new(this._root) : _rendered = renderHostFiles() {
    _shipped = {for (final file in _rendered) file.path};
  }

  final Directory _root;
  final List<RenderedFile> _rendered;
  late final Set<String> _shipped;

  final writes = <AgentWrite>[];
  final trash = <String>[];
  final skipped = <String>[];
  final writeSet = <String>{};
  final _planned = <String>{};

  void plan(AgentFileBase base, {required bool full}) {
    // A top the run may not write takes no skill or agent file, and its
    // instruction files are named already.
    if (base.isTop &&
        writeRefusalOf(base.directory.path, projectRoot: _root) != null) {
      return;
    }
    for (final group in AgentFolderGroup.values) {
      _planGroup(base, group, full: full);
    }
  }

  void _planGroup(
    AgentFileBase base,
    AgentFolderGroup group, {
    required bool full,
  }) {
    final entries = {
      for (final folder in group.folders)
        if (_isUsable(base, folder)) folder: _ownedEntriesIn(base, folder),
    };
    final isInUse = entries.values.any((names) => names.isNotEmpty);
    if (!isInUse && !base.isUpsert(full: full)) return;
    for (final file in _rendered) {
      if (entries.containsKey(file.folder)) _planFile(base, file);
    }
    for (final MapEntry(key: folder, value: names) in entries.entries) {
      for (final name in names) {
        _planTrash(base, '${folder.path}/$name');
      }
    }
  }

  /// Whether [folder] and its top lie where a run may write; a refusal is
  /// named once.
  bool _isUsable(AgentFileBase base, AgentFolder folder) {
    for (final relative in [folder.path.split('/').first, folder.path]) {
      final refusal = writeRefusalOf(
        _pathIn(base, relative),
        projectRoot: _root,
      );
      if (refusal == null) continue;
      _skip(skippedLineOf(_rootPath(base, relative), refusal));
      return false;
    }
    return true;
  }

  List<String> _ownedEntriesIn(AgentFileBase base, AgentFolder folder) {
    final directory = Directory(_pathIn(base, folder.path));
    if (!directory.existsSync()) return const [];
    return [
      for (final entity in directory.listSync(followLinks: false))
        if (_nameOf(entity).startsWith(_ownedPrefix)) _nameOf(entity),
    ]..sort(compareCodePoints);
  }

  void _planFile(AgentFileBase base, RenderedFile file) {
    final target = File(_pathIn(base, file.path));
    final current =
        FileSystemEntity.typeSync(target.path) == FileSystemEntityType.file
        ? utf8.decode(readPlanInput(target), allowMalformed: true)
        : null;
    if (current != null && toLf(current) == file.text) return;
    if (!_planned.add(canonicalPath(target.path))) return;
    final path = _rootPath(base, file.path);
    final refusal = writeRefusalOf(target.path, projectRoot: _root);
    if (refusal != null) return _skip(skippedLineOf(path, refusal));
    writeSet.add(path);
    writes.add(
      AgentWrite(
        path: path,
        text: file.text,
        isNew: current == null,
        before: current == null ? null : textHashOf(current),
        isAtTop: base.isTop,
      ),
    );
  }

  void _planTrash(AgentFileBase base, String entry) {
    final isShipped = _shipped.any(
      (path) => path == entry || path.startsWith('$entry/'),
    );
    if (!isShipped) return _trash(base, entry);
    for (final relative in _filesUnder(base, entry)) {
      if (!_shipped.contains(relative)) _trash(base, relative);
    }
  }

  void _trash(AgentFileBase base, String relative) {
    final path = _rootPath(base, relative);
    final refusal = writeRefusalOf(_pathIn(base, relative), projectRoot: _root);
    if (refusal == null) {
      trash.add(path);
    } else {
      _skip(skippedLineOf(path, refusal));
    }
  }

  /// The files of [entry], from [base], by code point; a link to a folder is
  /// never followed.
  List<String> _filesUnder(AgentFileBase base, String entry) {
    final path = _pathIn(base, entry);
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.file) {
      return [entry];
    }
    if (FileSystemEntity.isLinkSync(path)) return const [];
    final directory = Directory(path);
    final prefixLength = directory.uri.path.length;
    return [
      for (final entity in directory.listSync(
        recursive: true,
        followLinks: false,
      ))
        if (FileSystemEntity.typeSync(entity.path) == FileSystemEntityType.file)
          '$entry/${Uri.decodeComponent(entity.uri.path.substring(prefixLength))}',
    ]..sort(compareCodePoints);
  }

  void _skip(String line) {
    if (!skipped.contains(line)) skipped.add(line);
  }

  String _pathIn(AgentFileBase base, String relative) => File.fromUri(
    base.directory.uri.resolveUri(Uri(pathSegments: relative.split('/'))),
  ).path;

  String _rootPath(AgentFileBase base, String relative) =>
      base.path.isEmpty ? relative : '${base.path}/$relative';
}

String _nameOf(FileSystemEntity entity) =>
    entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
