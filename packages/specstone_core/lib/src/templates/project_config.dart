import 'dart:io';

import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/portable_path.dart';
import 'package:specstone_core/src/release_version.dart';
import 'package:specstone_core/src/templates/cleanup_bounds.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/models/matrix_mode.dart';
import 'package:specstone_core/src/templates/models/root_match.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

/// The project config path, relative to the project root.
const projectConfigPath = '.specstone/config.yaml';

const _specstoneFolder = '.specstone';

const _coreName = 'prd-core';
const _codeRootKey = 'code_root';
const _targetsKey = 'targets';
const _reservedTargetName = 'refs';
const _agentFileRootsKey = 'agent_file_roots';
const _agentFilesVersionKey = 'agent_files_version';

/// The config key that turns on `check`'s coverage finding.
const verificationCoverageKey = 'verification_coverage';

/// One slug of lowercase letters, digits, and underscores.
final _targetNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// Lowercase letters and digits in hyphen-separated groups.
final _kebabCase = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

final _driveLetter = RegExp('^[A-Za-z]:');

/// Returns the project root for a folder holding a `docs` link.
///
/// When `<folder>/docs` is a symbolic link, the root is the parent of the
/// link's resolved target; otherwise [folder]. The result is canonical.
Directory rootThroughDocsLink(Directory folder) {
  final docs = '${folder.path}${Platform.pathSeparator}docs';
  if (FileSystemEntity.isLinkSync(docs)) {
    try {
      return Directory(Link(docs).resolveSymbolicLinksSync()).parent;
    } on FileSystemException {
      // A dangling link has no target to stand for; the folder is the root.
    }
  }
  return Directory(folder.resolveSymbolicLinksSync());
}

/// Returns the first root from [start] upward for which [isRoot] holds.
///
/// The walk is [matchRootUpward]'s. Returns null when no folder up to the
/// file-system root yields one; never throws.
Directory? findRootUpward(
  Directory start,
  bool Function(Directory candidate) isRoot,
) => matchRootUpward(start, isRoot)?.root;

/// Returns the first root from [start] upward for which [isRoot] holds, with
/// the folder the walk stood in.
///
/// At each folder the candidates are [rootThroughDocsLink] of the folder, then
/// the folder itself when that is another path. A `docs` link to a folder
/// outside any project thus falls through to the folder's own markers. The
/// root and the folder are canonical; they differ only when the root came
/// through the folder's `docs` link. Returns null when no folder up to the
/// file-system root yields one; never throws, a folder that cannot be resolved
/// stands for itself, absolute.
RootMatch? matchRootUpward(
  Directory start,
  bool Function(Directory candidate) isRoot,
) {
  var dir = start.absolute;
  while (true) {
    final own = _canonicalOr(
      () => Directory(dir.resolveSymbolicLinksSync()),
      dir,
    );
    final linked = _canonicalOr(() => rootThroughDocsLink(dir), dir);
    if (isRoot(linked)) return RootMatch(folder: own, root: linked);
    if (own.path != linked.path && isRoot(own)) {
      return RootMatch(folder: own, root: own);
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

Directory _canonicalOr(Directory Function() resolve, Directory fallback) {
  try {
    return resolve();
  } on FileSystemException {
    return fallback;
  }
}

/// Returns the project root holding [start], or null outside a project.
///
/// The root is the first [findRootUpward] candidate holding
/// `.specstone/config.yaml`, canonical. Never throws.
Directory? findProjectRoot(Directory start) => matchProjectRoot(start)?.root;

/// Returns the project root holding [start] and the folder the walk stood in
/// when it found it, as [matchRootUpward] does; null outside a project.
///
/// The root is the first candidate holding `.specstone/config.yaml`. Never
/// throws.
RootMatch? matchProjectRoot(Directory start) => matchRootUpward(
  start,
  (candidate) =>
      File.fromUri(candidate.uri.resolve(projectConfigPath)).existsSync(),
);

/// The project config: the pack version each pack is pinned to, the code
/// targets code paths are written from, the repository tops already offered
/// agent files, the Version stamp of the run that wrote them, the Verification
/// matrix mode, and the bounds that keep the saved bundles and reports small.
final class ProjectConfig {
  new _({
    required this.pins,
    required this.targets,
    required this.hasCodeRoot,
    required this.agentFileRoots,
    required this.agentFilesVersion,
    required this.matrixMode,
    required this.cleanup,
  });

  /// Reads `.specstone/config.yaml` under the project [root].
  ///
  /// Throws `unknown_value` first when `.specstone` is a link or a file, since
  /// no byte is read through it, then `unknown_key` for a key other than
  /// `packs`, `code_root`, `targets`, `agent_file_roots`,
  /// `agent_files_version`, `verification_coverage`, and `cleanup`, a `packs`
  /// key that is not kebab-case, or a `cleanup` key other than its three
  /// bounds,
  /// `missing_key` when `packs` is absent, `pack_version_invalid` for a bad
  /// pin, `prd_core_missing` when `packs` pins no `prd-core`, and
  /// `unknown_value` for a `code_root` that is not a string, is empty, is
  /// absolute, or holds a backslash, for an `agent_file_roots` that is not a
  /// list of such strings, for an `agent_files_version` that is not a Version,
  /// for a `verification_coverage` outside `false`, `true`, `fr`, and
  /// `edge_case`, for a `cleanup` that
  /// is not a map or holds a bound that is not a positive integer, and for a
  /// `targets` that is empty, sits beside `code_root:`, or holds two targets
  /// on one code folder.
  ///
  /// A `packs` key is checked before its pin parses, so the first fault in file
  /// order wins, and before any pack file is opened.
  static ProjectConfig read(Directory root) {
    requireSpecstoneFolder(root);
    final text = decodeYamlBytes(
      readPlanInput(File.fromUri(root.uri.resolve(projectConfigPath))),
      file: projectConfigPath,
    );
    final map = readYamlMap(text, file: projectConfigPath);
    checkKeys(
      map,
      {
        'packs',
        _codeRootKey,
        _targetsKey,
        _agentFileRootsKey,
        _agentFilesVersionKey,
        verificationCoverageKey,
        cleanupKey,
      },
      file: projectConfigPath,
      format: 'config',
    );
    final packs = requireValue<YamlMap>(map, 'packs', file: projectConfigPath);
    final pins = <String, PackVersion>{};
    for (final MapEntry(:key, :value) in packs.nodes.entries) {
      final name = '${(key as YamlNode).value}';
      if (!_kebabCase.hasMatch(name)) {
        throw TemplateFault(
          FaultCode.unknownKey,
          'pack names are kebab-case',
          file: projectConfigPath,
          key: 'packs.$name',
        );
      }
      pins[name] = PackVersion.fromYaml(
        value,
        file: projectConfigPath,
        key: 'packs.$name',
      );
    }
    if (!pins.containsKey(_coreName)) {
      throw TemplateFault(
        FaultCode.prdCoreMissing,
        'the packs must pin $_coreName',
        file: projectConfigPath,
        key: 'packs',
      );
    }
    final targets = _readTargets(root, map);
    return ProjectConfig._(
      pins: Map.unmodifiable(pins),
      targets: List.unmodifiable(targets),
      hasCodeRoot: map.containsKey(_codeRootKey),
      agentFileRoots: _readAgentFileRoots(map),
      agentFilesVersion: _readAgentFilesVersion(map),
      matrixMode: _readMatrixMode(map),
      cleanup: CleanupBounds.fromConfig(map, file: projectConfigPath),
    );
  }

  /// The pinned version of each pack, in file order.
  final Map<String, PackVersion> pins;

  /// The code targets, in config order; with no `targets:` one unnamed target
  /// whose code root is `code_root:`'s.
  final List<CodeTarget> targets;

  /// The named targets, in config order; empty with one unnamed target.
  List<String> get targetNames => targetNamesOf(targets);

  /// The folder code paths are written from, relative to the project root:
  /// the first [targets] entry's code root.
  ///
  /// `/`-separated and possibly outside the project root (`../code`); `.` when
  /// the config has no `code_root`.
  String get codeRoot => targets.first.codeRoot;

  /// Whether the file holds a `code_root:` key; [codeRoot] reads `.` for an
  /// absent key and for `code_root: .` alike. A `targets:` config has none,
  /// since each target holds its own `code_root:`.
  final bool hasCodeRoot;

  /// The repository tops already offered agent files, each as written.
  ///
  /// `/`-separated paths from the project root, possibly outside it
  /// (`../stratum_ui`); empty when the config has no `agent_file_roots`.
  final List<String> agentFileRoots;

  /// The last Version whose run left the agent files as it writes them; null
  /// when the config has no `agent_files_version`.
  final ReleaseVersion? agentFilesVersion;

  /// The Verification matrix mode `verification_coverage:` names;
  /// [MatrixMode.off] when the config has no such key.
  final MatrixMode matrixMode;

  /// The bounds the prune commands keep `bundles/` and `reports/` within; each
  /// default when the config has no `cleanup`.
  final CleanupBounds cleanup;

  /// The config path, relative to the project root.
  String get file => projectConfigPath;
}

/// What the config's `agent_files_version` holds, as [readAgentFilesVersion]
/// reads it.
sealed class AgentFilesStamp;

/// The config is readable and has no `agent_files_version`.
final class AgentFilesStampAbsent implements AgentFilesStamp {
  const new();
}

/// The config is readable and holds [version].
final class AgentFilesStampVersion implements AgentFilesStamp {
  const new(this.version);

  final ReleaseVersion version;
}

/// The config, or its `agent_files_version`, cannot be read.
final class AgentFilesStampUnreadable implements AgentFilesStamp {
  const new();
}

/// Reads `agent_files_version` alone from the config under the project
/// [root], for commands that load no templates.
///
/// Reads no other key, so a broken `agent_file_roots` or `packs` does not hide
/// the stamp. Never throws: a fault of any kind is
/// [AgentFilesStampUnreadable], apart from the readable
/// [AgentFilesStampAbsent].
AgentFilesStamp readAgentFilesVersion(Directory root) {
  try {
    requireSpecstoneFolder(root);
    final text = decodeYamlBytes(
      readPlanInput(File.fromUri(root.uri.resolve(projectConfigPath))),
      file: projectConfigPath,
    );
    final version = _readAgentFilesVersion(
      readYamlMap(text, file: projectConfigPath),
    );
    return version == null
        ? const AgentFilesStampAbsent()
        : AgentFilesStampVersion(version);
  } on TemplateFault {
    return const AgentFilesStampUnreadable();
  } on FileSystemException {
    return const AgentFilesStampUnreadable();
  }
}

/// Reads `cleanup` alone from the config under the project [root], for
/// commands that load no templates.
///
/// Reads no other key, so a broken `packs` or an unknown key does not hide the
/// bounds. Never throws: a config that cannot be read gives
/// [CleanupBounds.defaults], and each bound that does not read gives its own
/// default.
CleanupBounds readCleanupBounds(Directory root) {
  try {
    requireSpecstoneFolder(root);
    final text = decodeYamlBytes(
      readPlanInput(File.fromUri(root.uri.resolve(projectConfigPath))),
      file: projectConfigPath,
    );
    return CleanupBounds.fromConfigLeniently(
      readYamlMap(text, file: projectConfigPath),
    );
  } on TemplateFault {
    return CleanupBounds.defaults;
  } on FileSystemException {
    return CleanupBounds.defaults;
  }
}

/// Reads `verification_coverage:` by the node's own type, so a quoted `'true'`
/// stays a string and is refused.
MatrixMode _readMatrixMode(YamlMap map) =>
    switch (map[verificationCoverageKey]) {
      null || false => MatrixMode.off,
      true || 'fr' => MatrixMode.fr,
      'edge_case' => MatrixMode.edgeCase,
      _ => throw TemplateFault(
        FaultCode.unknownValue,
        '$verificationCoverageKey takes false, true, fr, or edge_case',
        file: projectConfigPath,
        key: verificationCoverageKey,
      ),
    };

ReleaseVersion? _readAgentFilesVersion(YamlMap map) {
  final text = optionalValue<String>(
    map,
    _agentFilesVersionKey,
    file: projectConfigPath,
  );
  if (text == null) return null;
  return ReleaseVersion.tryParse(text) ??
      (throw TemplateFault(
        FaultCode.unknownValue,
        'the key $_agentFilesVersionKey must be a Version such as 1.3.0',
        file: projectConfigPath,
        key: _agentFilesVersionKey,
      ));
}

/// Throws `unknown_value` unless `.specstone` under [root] is absent or a real
/// folder.
///
/// A link or a file there leads a read or a write of the index, the config, or
/// the trash outside the project, so every command that opens or sets up a
/// project calls this before it touches the folder.
void requireSpecstoneFolder(Directory root) {
  final folder = '${root.path}${Platform.pathSeparator}$_specstoneFolder';
  final type = FileSystemEntity.typeSync(folder, followLinks: false);
  if (type == FileSystemEntityType.notFound ||
      type == FileSystemEntityType.directory) {
    return;
  }
  throw TemplateFault(
    FaultCode.unknownValue,
    '$_specstoneFolder must be a real folder inside the project root, '
    'not a link or a file',
    file: _specstoneFolder,
  );
}

/// Reads the targets of the config [map]: its `targets:` entries in file
/// order, or one unnamed target at `code_root:` when the key is absent.
///
/// [root] joins each code root for the one-folder comparison.
List<CodeTarget> _readTargets(Directory root, YamlMap map) {
  final hasTargets = map.containsKey(_targetsKey);
  final hasCodeRoot = map.containsKey(_codeRootKey);
  if (!hasTargets) {
    return [CodeTarget(null, codeRoot: _readCodeRootAt(map, '', _codeRootKey))];
  }
  if (hasCodeRoot) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'each target holds its own code_root; drop the code_root key beside '
      'targets',
      file: projectConfigPath,
      key: _codeRootKey,
    );
  }
  final targetsMap = optionalValue<YamlMap>(
    map,
    _targetsKey,
    file: projectConfigPath,
  );
  if (targetsMap == null || targetsMap.isEmpty) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the key $_targetsKey must be a non-empty mapping of target name to '
      'its code_root',
      file: projectConfigPath,
      key: _targetsKey,
    );
  }
  final targets = <CodeTarget>[];
  for (final MapEntry(:key) in targetsMap.nodes.entries) {
    final name = '${(key as YamlNode).value}';
    if (name.toLowerCase() == _reservedTargetName) {
      throw TemplateFault(
        FaultCode.unknownValue,
        'a target cannot be named $_reservedTargetName in any letter case: '
        'it names the refs file of a bundle written without a target',
        file: projectConfigPath,
        key: _targetsKey,
      );
    }
    if (!_targetNamePattern.hasMatch(name)) {
      throw TemplateFault(
        FaultCode.unknownKey,
        'a target name is one slug of lowercase letters, digits, and '
        'underscores',
        file: projectConfigPath,
        key: '$_targetsKey.$name',
      );
    }
    final entry =
        optionalValue<YamlMap>(
          targetsMap,
          name,
          file: projectConfigPath,
          prefix: '$_targetsKey.',
        ) ??
        (throw TemplateFault(
          FaultCode.unknownValue,
          'the target $name must be a mapping holding its code_root',
          file: projectConfigPath,
          key: '$_targetsKey.$name',
        ));
    checkKeys(
      entry,
      {_codeRootKey},
      file: projectConfigPath,
      format: 'config',
      prefix: '$_targetsKey.$name.',
    );
    targets.add(
      CodeTarget(
        name,
        codeRoot: _readCodeRootAt(entry, '$_targetsKey.$name.', _codeRootKey),
      ),
    );
  }
  _refuseOneFolder(root, targets);
  return targets;
}

/// Throws `unknown_value` when two of [targets] name one code folder, naming
/// both, since a code path picks its target by its longest code root.
void _refuseOneFolder(Directory root, List<CodeTarget> targets) {
  for (var i = 0; i < targets.length; i++) {
    for (var j = i + 1; j < targets.length; j++) {
      final first = codeRootFolderOf(root, targets[i]).path;
      final second = codeRootFolderOf(root, targets[j]).path;
      if (first == second) {
        throw TemplateFault(
          FaultCode.unknownValue,
          'the targets ${targets[i].name} and ${targets[j].name} name one '
          'code folder, and a code path picks its target by its longest code '
          'root',
          file: projectConfigPath,
          key: _targetsKey,
        );
      }
    }
  }
}

/// Reads a `code_root:` value at [key] of [map], `.` when absent or null.
///
/// [prefix] builds the fault key, `'targets.<name>.'` inside a target.
String _readCodeRootAt(YamlMap map, String prefix, String key) {
  final value = optionalValue<String>(
    map,
    key,
    file: projectConfigPath,
    prefix: prefix,
  );
  if (value == null) return '.';
  if (!isPortableCodeEntry(value)) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the key $key must be a non-empty relative path with / separators and '
      'no name ending in a space or a dot',
      file: projectConfigPath,
      key: '$prefix$key',
    );
  }
  return value;
}

List<String> _readAgentFileRoots(YamlMap map) {
  final roots = stringList(map, _agentFileRootsKey, file: projectConfigPath);
  if (!roots.every(isPortableCodeEntry)) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the key $_agentFileRootsKey must hold non-empty relative paths with / '
      'separators and no name ending in a space or a dot',
      file: projectConfigPath,
      key: _agentFileRootsKey,
    );
  }
  return List.unmodifiable(roots);
}

/// Whether [value] is a config path entry the reader accepts (`code_root`, each
/// `agent_file_roots` entry): a non-empty relative path with `/` separators.
///
/// Omitting the key or writing `.` is the one spelling of the root itself, so
/// the empty string is refused.
bool isCodeRootValue(String value) =>
    value.isNotEmpty && !_isAbsolute(value) && !value.contains(r'\');

/// Whether [value] is a path entry that names the same place on every OS: an
/// [isCodeRootValue] with no name that [hasWindowsDroppedEnd].
///
/// The gate for the config's `code_root` and `agent_file_roots`, and for each
/// `code:` entry, so every reader of such a name finds the same folder.
bool isPortableCodeEntry(String value) =>
    isCodeRootValue(value) && isPortablePath(value);

/// Whether [path] is rooted or starts with a drive letter, on any platform.
///
/// A config written on Windows must stay invalid on POSIX, where `C:/abs` is
/// an ordinary relative name to `File.isAbsolute`.
bool _isAbsolute(String path) =>
    path.startsWith('/') || _driveLetter.hasMatch(path);
