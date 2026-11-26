import 'package:specstone_core/src/doc_model/doc_link.dart' show docsFolderName;
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/release_version.dart';
import 'package:specstone_core/src/setup_migration/models/rendered_file.dart'
    show AgentFolderGroup;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart'
    show projectTemplatesFolder;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:yaml/yaml.dart';

/// Singular doc types print and write first in this order.
const _draftOrder = [
  'project',
  'goal',
  'glossary',
  'features',
  'gnfr',
  'tech_stack',
];

/// Returns the `config.yaml` text pinning each of [pins].
///
/// Writes `packs:`, one pin per line in code point order of the name, then a
/// `code_root:` line only when [codeRoot] is not `.` or [keepCodeRootKey] is
/// set, then a `targets:` map only when [targets] is not empty, then an
/// `agent_file_roots:` list only when [agentFileRoots] is not empty, then an
/// `agent_file_groups:` list only when [agentFileGroups] is not empty, then an
/// `agent_files_version:` line only when [agentFilesVersion] is set; each
/// scalar is quoted when plain YAML would read it as another value. Throws
/// [ArgumentError] for an agent file root the reader would refuse, an unknown
/// agent file group, an unnamed target, or [targets] beside a `code_root:`
/// line.
///
/// [keepCodeRootKey] keeps the line of a config that already holds the key,
/// so an explicit `code_root: .` is not dropped.
String configText(
  Map<String, PackVersion> pins, {
  String codeRoot = '.',
  bool keepCodeRootKey = false,
  List<CodeTarget> targets = const [],
  List<String> agentFileRoots = const [],
  List<String> agentFileGroups = const [],
  ReleaseVersion? agentFilesVersion,
}) {
  if (targets.isNotEmpty && (codeRoot != '.' || keepCodeRootKey)) {
    throw ArgumentError.value(
      targets,
      'targets',
      'each target holds its own code_root, so the config has no code_root key',
    );
  }
  for (final root in agentFileRoots) {
    if (!isPortableCodeEntry(root)) {
      throw ArgumentError.value(
        root,
        'agentFileRoots',
        'must be a non-empty relative path with / separators and no name '
            'ending in a space or a dot',
      );
    }
  }
  for (final group in agentFileGroups) {
    if (AgentFolderGroup.ofConfigName(group) == null) {
      throw ArgumentError.value(
        group,
        'agentFileGroups',
        'must be one of ${agentFileGroupNames.join(', ')}',
      );
    }
  }
  final names = pins.keys.toList()..sort(compareCodePoints);
  final lines = [for (final name in names) '  $name: ${pins[name]}\n'];
  final codeRootLine = codeRoot == '.' && !keepCodeRootKey
      ? ''
      : 'code_root: ${_stringScalar(codeRoot)}\n';
  final targetLines = [for (final target in targets) _targetLines(target)];
  final targetsLine = targetLines.isEmpty
      ? ''
      : 'targets:\n${targetLines.join()}';
  final agentFileRootsLine = agentFileRoots.isEmpty
      ? ''
      : listBlockOf('agent_file_roots', agentFileRoots);
  final agentFileGroupsLine = agentFileGroups.isEmpty
      ? ''
      : listBlockOf('agent_file_groups', agentFileGroups);
  final agentFilesVersionLine = agentFilesVersion == null
      ? ''
      : 'agent_files_version: $agentFilesVersion\n';
  return 'packs:\n${lines.join()}$codeRootLine$targetsLine'
      '$agentFileRootsLine$agentFileGroupsLine$agentFilesVersionLine';
}

/// Returns the lines of [target] under `targets:`.
String _targetLines(CodeTarget target) {
  final name = target.name;
  if (name == null) {
    throw ArgumentError.value(target, 'targets', 'every target is named');
  }
  return '  ${_stringScalar(name)}:\n'
      '    code_root: ${_stringScalar(target.codeRoot)}\n';
}

/// Returns the doc types of [set] whose path holds no `{nn}` and no `{slug}`,
/// project spec doc types excluded.
///
/// Ordered project, goal, glossary, features, gnfr, tech_stack, then the rest
/// by DocPath.
List<MergedDocType> singularDocTypes(MergedSet set) {
  final singular = [
    for (final docType in _onePathTypes(set))
      if (!set.isProjectSpecType(docType)) docType,
  ];
  return singular..sort(_byDraftOrder);
}

/// Returns the DocPath of each doc type of [set] with one doc per project,
/// project spec types included, one per name in [twinNames] in place of the
/// shared path for a per-target type.
Set<String> singularLayoutPathsOf(
  MergedSet set, {
  required List<String> twinNames,
}) => {
  for (final type in _onePathTypes(set))
    if (type.path case final path?)
      if (type.isPerTarget && twinNames.isNotEmpty)
        for (final name in twinNames) PathPattern(path).forTarget(name).source
      else
        path,
};

/// Whether [path] is one of [layoutPaths], or one of them under the docs
/// folder.
bool isSingularLayoutPath(String path, Set<String> layoutPaths) {
  const prefix = '$docsFolderName/';
  return layoutPaths.contains(path) ||
      (path.startsWith(prefix) &&
          layoutPaths.contains(path.substring(prefix.length)));
}

/// Parses the doc-type files among [files] as project-layer doc types.
///
/// Keys are `.specstone/templates/<id>.yaml`; like the project loader it reads
/// only top-level `<id>.yaml` files, not `pack.yaml`, in code point order of
/// the name. A malformed override throws a `TemplateFault` here, in
/// the plan, not after commit 2.
List<DocTypeLayer> parseOverrides(Map<String, String> files) {
  const prefix = '$projectTemplatesFolder/';
  final names = [
    for (final key in files.keys)
      if (key.startsWith(prefix) &&
          isDocTypeFileName(key.substring(prefix.length)))
        key.substring(prefix.length),
  ]..sort(compareCodePoints);
  return [
    for (final name in names)
      DocTypeLayer.parse(
        files['$prefix$name']!,
        file: '$prefix$name',
        docTypeId: name.substring(0, name.length - '.yaml'.length),
        kind: LayerKind.project,
        files: const _NoFiles(),
      ),
  ];
}

/// Returns [text] as a single-quoted YAML scalar, `'` doubled.
String _quoted(String text) => "'${text.replaceAll("'", "''")}'";

/// Returns [text] as written when plain YAML reads back the same string,
/// else quoted.
///
/// A path may read as a number (`2024`), a word (`true`), a comment, or a
/// mapping.
String _stringScalar(String text) {
  try {
    if (loadYaml(text) == text) return text;
  } on YamlException {
    // Text plain YAML refuses, such as `[a`, is written quoted.
  }
  return _quoted(text);
}

/// Returns the doc types of [set] whose path holds no `{nn}` and no `{slug}`.
Iterable<MergedDocType> _onePathTypes(MergedSet set) =>
    set.docTypes.where((docType) => _isSingular(docType.path));

bool _isSingular(String? path) =>
    path != null && !path.contains('{nn}') && !path.contains('{slug}');

int _byDraftOrder(MergedDocType a, MergedDocType b) {
  final rankA = _draftOrder.indexOf(a.id);
  final rankB = _draftOrder.indexOf(b.id);
  if (rankA >= 0 || rankB >= 0) {
    if (rankA < 0) return 1;
    if (rankB < 0) return -1;
    return rankA.compareTo(rankB);
  }
  return compareCodePoints(a.path!, b.path!);
}

/// A [LayerFiles] view of a layer that holds no reference target.
final class _NoFiles implements LayerFiles {
  const new();

  @override
  bool exists(String layerRelativePath) => false;
}
