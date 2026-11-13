import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart' show canonicalPath;

/// One code base the shared PRD drives: its name and its code root.
///
/// The name is null for the one unnamed target a `code_root:`-only config
/// gives. `codeRoot` is the config's value as written, relative to the project
/// root and `/`-separated, `.` for the project root itself.
final class CodeTarget {
  const new(this.name, {required this.codeRoot});

  /// The target's name under `targets:`, one slug; null for the unnamed
  /// target of a `code_root:`-only config.
  final String? name;

  /// The folder this target's code paths are written from, as written in the
  /// config.
  final String codeRoot;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is CodeTarget && other.name == name && other.codeRoot == codeRoot;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(name, codeRoot);

  @override
  String toString() => 'CodeTarget($name, $codeRoot)';
}

/// Returns the folder [target]'s code paths are written from, [projectRoot]
/// joined with its `code_root`, as [canonicalPath] reads it.
Directory codeRootFolderOf(Directory projectRoot, CodeTarget target) =>
    Directory(
      canonicalPath(
        '${projectRoot.path}/'
        '${target.codeRoot.replaceAll(RegExp(r'[\\/]'), '/')}',
      ),
    );

/// Returns each of [targets]' code root folders that lie inside [target]'s,
/// as `/`-separated paths from it; [projectRoot] resolves the roots.
///
/// One nested-roots rule: a file under the root of another target nested in
/// this one belongs to that target.
List<String> nestedRootsOf(
  Directory projectRoot,
  CodeTarget target,
  List<CodeTarget> targets,
) {
  final own = codeRootFolderOf(projectRoot, target).path;
  final others = [
    for (final other in targets)
      if (other != target) codeRootFolderOf(projectRoot, other).path,
  ];
  return _nestedPathsOf(own, others);
}

/// Returns each of [roots] that lies inside [own], `/`-separated from it.
List<String> _nestedPathsOf(String own, List<String> roots) {
  final prefix = own.endsWith('/') ? own : '$own/';
  return [
    for (final path in roots)
      if (path.length > prefix.length && path.startsWith(prefix))
        path.substring(prefix.length).replaceAll(RegExp(r'[\\/]'), '/'),
  ];
}

/// Returns the named targets of [targets], in order; empty with one unnamed
/// target.
List<String> targetNamesOf(Iterable<CodeTarget> targets) => [
  for (final target in targets)
    if (target.name != null) target.name!,
];
