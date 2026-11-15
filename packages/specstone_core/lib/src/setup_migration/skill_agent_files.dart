import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/document_writing/journal_bounds.dart'
    show isGitEntry, skippedLineOf, underGitLineOf, writeRefusalOf;
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show textHashOf;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/cite_pass.dart'
    show citeRuleSince;
import 'package:specstone_core/src/setup_migration/claude_settings.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

const _ownedPrefix = 'specstone-';
const _claudeFolder = '.claude';
const _settingsPath = '$_claudeFolder/settings.json';

/// Why a skill or agent file needs a run.
enum SkillFileDriftKind {
  /// The file's bytes differ from what the CLI writes.
  differs,

  /// The file is missing from a folder of a group in use.
  missing,

  /// The CLI no longer ships the file.
  unshipped,

  /// `.claude/settings.json` does not hold the Specstone hook group alone.
  settingsStale,

  /// `.claude/settings.json` is missing from a Claude Code folder group in use.
  settingsMissing,

  /// `.claude/settings.json` is no JSON object a run can merge into.
  settingsMalformed,
}

/// One drift: its path from the project root, `/`-separated, and its kind.
typedef SkillFileDrift = ({String path, SkillFileDriftKind kind});

/// The skill and agent file changes of one run, every path from the project
/// root with `/` separators.
///
/// `writes` holds `.claude/settings.json` beside the skill and agent files when
/// the Claude Code folder group takes part and the file is not current;
/// `malformedSettings` holds, for each such file that no run can merge into,
/// its path, why it does not parse, and whether it is no file at all, and
/// plans no write for it.
///
/// `trash` lists each path to move to the trash: the folder or file of a
/// `specstone-*` entry the CLI ships nothing of, which moves whole, and each
/// unshipped file inside an entry it ships; `topTrash` holds those of it that
/// lie at a repository top. `skipped` holds the warning line
/// for each folder or file the run leaves because its real path lies outside
/// the project root or under `.git`.
typedef SkillFilePlan = ({
  List<AgentWrite> writes,
  List<({String path, String failure, bool isNoFile})> malformedSettings,
  List<String> trash,
  List<String> topTrash,
  List<String> skipped,
  Set<String> writeSet,
});

/// Whether [upgrades] first ship the skill and agent files: the pack upgrade
/// that writes every one of them once.
///
/// It rides the pack versions of the cite rule, so one pack bump serves both
/// one-time passes.
bool shipsSkillFiles(List<PackUpgrade> upgrades) =>
    crossesSince(upgrades, citeRuleSince);

/// Plans the `specstone-*` skill and agent file changes of [inputs], by folder
/// group at the project root and at each repository top.
///
/// [full] is the `init`, legacy, and one-time upgrade upsert at the project
/// root; otherwise a folder group takes writes only while one of its folders
/// holds a `specstone-*` entry. An unlisted top always takes the full upsert
/// once; [includesListedTops] gives each listed top the same as the root, for
/// the run that first ships these files. Entries not named `specstone-*` are
/// never read.
SkillFilePlan planSkillAndAgentFiles(
  AgentFileInputs inputs, {
  required bool full,
  bool includesListedTops = false,
}) {
  final bases = agentFileBasesOf(inputs);
  final planner = _Planner(bases.first.directory);
  for (final base in bases) {
    planner.plan(base, full: full, includesListedTops: includesListedTops);
  }
  planner.trashUnclaimed();
  return (
    writes: planner.writes,
    malformedSettings: planner.malformedSettings,
    trash: planner.trash,
    topTrash: planner.topTrash,
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
/// to write or trash and no malformed settings file. Never throws for a
/// malformed settings file; it is a [SkillFileDriftKind.settingsMalformed].
List<SkillFileDrift> skillAndAgentFileDrifts(AgentFileInputs inputs) {
  final plan = planSkillAndAgentFiles(inputs, full: false);
  return [
    for (final write in plan.writes) (path: write.path, kind: _kindOf(write)),
    for (final (:path, failure: _, isNoFile: _) in plan.malformedSettings)
      (path: path, kind: SkillFileDriftKind.settingsMalformed),
    for (final path in plan.trash)
      (path: path, kind: SkillFileDriftKind.unshipped),
  ];
}

SkillFileDriftKind _kindOf(AgentWrite write) {
  final isSettings = _isSettingsPath(write.path);
  return switch ((isSettings, write.isNew)) {
    (true, true) => SkillFileDriftKind.settingsMissing,
    (true, false) => SkillFileDriftKind.settingsStale,
    (false, true) => SkillFileDriftKind.missing,
    (false, false) => SkillFileDriftKind.differs,
  };
}

bool _isSettingsPath(String path) =>
    path == _settingsPath || path.endsWith('/$_settingsPath');

final class _Planner {
  new(this._root) : _rendered = renderHostFiles() {
    _shipped = {for (final file in _rendered) file.path};
  }

  final Directory _root;
  final List<RenderedFile> _rendered;
  late final Set<String> _shipped;

  final writes = <AgentWrite>[];
  final malformedSettings = <({String path, String failure, bool isNoFile})>[];
  final trash = <String>[];
  final topTrash = <String>[];
  final skipped = <String>[];
  final writeSet = <String>{};
  final _planned = <String>{};
  final _entriesToTrash = <(AgentFileBase, String)>[];

  /// Plans the writes of [base]; the entries to trash wait for
  /// [trashUnclaimed], so every group has claimed its files by then.
  void plan(
    AgentFileBase base, {
    required bool full,
    required bool includesListedTops,
  }) {
    final isUpsert = base.isTop
        ? base.isUnlisted || (full && includesListedTops)
        : full;
    if (base.isTop) {
      final refusal = writeRefusalOf(base.directory.path, projectRoot: _root);
      if (refusal != null) {
        if (isUpsert) {
          _skip(skippedLineOf(base.path, refusal));
        }
        return;
      }
    }
    for (final group in AgentFolderGroup.values) {
      _planGroup(base, group, isUpsert: isUpsert);
    }
  }

  void _planGroup(
    AgentFileBase base,
    AgentFolderGroup group, {
    required bool isUpsert,
  }) {
    final refusals = <String>[];
    final listed = {
      for (final folder in group.folders)
        if (_isUsable(base, folder, refusals)) folder: _namesIn(base, folder),
    };
    final entries = {
      for (final MapEntry(key: folder, value: names) in listed.entries)
        folder: [
          for (final name in names)
            if (name.startsWith(_ownedPrefix)) name,
        ],
    };
    final isInUse = entries.values.any((names) => names.isNotEmpty);
    if (!isInUse && !isUpsert) return;
    refusals.forEach(_skip);
    for (final file in _rendered) {
      final names = listed[file.folder];
      if (names != null) _planFile(base, file, names);
    }
    if (group == AgentFolderGroup.claudeCode) _planSettings(base);
    for (final MapEntry(key: folder, value: names) in entries.entries) {
      for (final name in names) {
        _entriesToTrash.add((base, '${folder.path}/$name'));
      }
    }
  }

  /// Plans the trash of every entry the groups listed, once all of them have
  /// claimed their files: a folder linked to another host's folder lists that
  /// host's files as unshipped, and they are claimed, not trash.
  void trashUnclaimed() {
    for (final (base, entry) in _entriesToTrash) {
      _planTrash(base, entry);
    }
  }

  /// Whether [folder] and its top are folders, or missing, where a run may
  /// write; the line that names a refusal or a top that is no folder is added
  /// to [refusals] for the caller to record when its group takes part.
  bool _isUsable(
    AgentFileBase base,
    AgentFolder folder,
    List<String> refusals,
  ) {
    for (final relative in [folder.path.split('/').first, folder.path]) {
      final path = _pathIn(base, relative);
      final refusal = writeRefusalOf(path, projectRoot: _root);
      if (refusal != null) {
        refusals.add(skippedLineOf(_rootPath(base, relative), refusal));
        return false;
      }
      if (_isNoFolder(path)) {
        refusals.add(
          '${_rootPath(base, relative)} is not a folder; '
          'left as it is',
        );
        return false;
      }
    }
    return true;
  }

  bool _existsAt(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  bool _isNoFolder(String path) {
    final type = FileSystemEntity.typeSync(path);
    return type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory;
  }

  /// The names listed in [folder], by code point; none when it is missing.
  List<String> _namesIn(AgentFileBase base, AgentFolder folder) {
    final directory = Directory(_pathIn(base, folder.path));
    if (!directory.existsSync()) return const [];
    return [
      for (final entity in directory.listSync(followLinks: false))
        _nameOf(entity),
    ]..sort(compareCodePoints);
  }

  void _planFile(AgentFileBase base, RenderedFile file, List<String> names) {
    final twin = caseTwinOf(
      file.entry,
      names,
      existsOnDisk: () =>
          _existsAt(_pathIn(base, '${file.folder.path}/${file.entry}')),
    );
    if (twin != null) {
      return _skip(
        '${_rootPath(base, '${file.folder.path}/${file.entry}')} '
        'differs only in case from $twin; left as it is',
      );
    }
    final target = File(_pathIn(base, file.path));
    if (!_planned.add(canonicalPath(target.path))) return;
    final current =
        FileSystemEntity.typeSync(target.path) == FileSystemEntityType.file
        ? utf8.decode(readPlanInput(target), allowMalformed: true)
        : null;
    if (current != null && toLf(current) == file.text) return;
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

  /// Plans `.claude/settings.json` of [base] for a Claude Code group that takes
  /// part: a write when the file is missing or stale, a record when it is
  /// malformed, nothing when it is current.
  ///
  /// A `.claude` the group already named as refused or no folder takes no
  /// second line.
  void _planSettings(AgentFileBase base) {
    final claude = _pathIn(base, _claudeFolder);
    if (writeRefusalOf(claude, projectRoot: _root) != null ||
        _isNoFolder(claude)) {
      return;
    }
    final target = File(_pathIn(base, _settingsPath));
    if (!_planned.add(canonicalPath(target.path))) return;
    final path = _rootPath(base, _settingsPath);
    final refusal = writeRefusalOf(target.path, projectRoot: _root);
    if (refusal != null) return _skip(skippedLineOf(path, refusal));
    final type = FileSystemEntity.typeSync(target.path);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      return _recordMalformed(path, 'it is not a file', isNoFile: true);
    }
    final bytes = type == FileSystemEntityType.file
        ? readPlanInput(target)
        : null;
    switch (settingsStateOf(bytes)) {
      case SettingsCurrent():
        return;
      case SettingsMalformed(:final failure):
        _recordMalformed(path, failure);
      case SettingsMissing(:final text):
        _addSettingsWrite(base, path, text, before: null);
      case SettingsStale(:final text):
        _addSettingsWrite(
          base,
          path,
          text,
          before: textHashOf(utf8.decode(bytes!)),
        );
    }
  }

  void _recordMalformed(String path, String failure, {bool isNoFile = false}) =>
      malformedSettings.add((path: path, failure: failure, isNoFile: isNoFile));

  void _addSettingsWrite(
    AgentFileBase base,
    String path,
    String text, {
    required String? before,
  }) {
    writeSet.add(path);
    writes.add(
      AgentWrite(
        path: path,
        text: text,
        isNew: before == null,
        before: before,
        isAtTop: base.isTop,
      ),
    );
  }

  void _planTrash(AgentFileBase base, String entry) {
    final isShipped = _shipped.any(
      (path) => path == entry || path.startsWith('$entry/'),
    );
    if (!isShipped) return _trashOrLeave(base, entry);
    for (final relative in _filesUnder(base, entry)) {
      if (!_shipped.contains(relative)) _trash(base, relative);
    }
  }

  /// Trashes [entry], or leaves it whole and names it when a `.git` entry lies
  /// anywhere inside, so no repository history goes with the trash.
  void _trashOrLeave(AgentFileBase base, String entry) {
    if (!_holdsGitEntry(base, entry)) return _trash(base, entry);
    _skip(underGitLineOf(_rootPath(base, entry)));
  }

  bool _holdsGitEntry(AgentFileBase base, String entry) {
    final path = _pathIn(base, entry);
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type != FileSystemEntityType.directory) return false;
    return Directory(path)
        .listSync(recursive: true, followLinks: false)
        .any((entity) => isGitEntry(_nameOf(entity)));
  }

  void _trash(AgentFileBase base, String relative) {
    final path = _rootPath(base, relative);
    final real = _pathIn(base, relative);
    if (_planned.contains(_placedPath(real))) return;
    final refusal = writeRefusalOf(real, projectRoot: _root);
    if (refusal == null) {
      trash.add(path);
      if (base.isTop) topTrash.add(path);
    } else {
      _skip(skippedLineOf(path, refusal));
    }
  }

  /// Where [path] lies: its folder resolved, its own name kept, so a link at
  /// [path] counts as itself and not as the file it leads to.
  String _placedPath(String path) {
    final separator = Platform.pathSeparator;
    final cut = path.lastIndexOf(separator);
    final folder = canonicalPath(path.substring(0, cut));
    return '$folder$separator${path.substring(cut + 1)}';
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
        if (FileSystemEntity.typeSync(entity.path) ==
                FileSystemEntityType.file &&
            !_relativeOf(entity, prefixLength).split('/').any(isGitEntry))
          '$entry/${_relativeOf(entity, prefixLength)}',
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

String _relativeOf(FileSystemEntity entity, int prefixLength) =>
    Uri.decodeComponent(entity.uri.path.substring(prefixLength));

/// Returns the name in [names] that spells [entry] with other case, or null.
///
/// A twin counts only on a disk that folds case: [entry] is not listed, yet
/// [existsOnDisk] finds it. On another disk the two names are two entries.
String? caseTwinOf(
  String entry,
  List<String> names, {
  required bool Function() existsOnDisk,
}) {
  if (names.contains(entry)) return null;
  final folded = entry.toLowerCase();
  for (final name in names) {
    if (name.toLowerCase() == folded) return existsOnDisk() ? name : null;
  }
  return null;
}

String _nameOf(FileSystemEntity entity) =>
    entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
