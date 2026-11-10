import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show namesFileOrFolderFrom;
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show repositoryTopOf;
import 'package:specstone_core/src/setup_migration/project_root.dart'
    show relativeFolderPath;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show isCodeRootValue;

const _rootRank = 0;
const _linkRank = 1;
const _aboveRank = 2;

/// The `code_root` a legacy run infers, with the count behind it.
///
/// `value` is `.` when no key is written; `found` is the winning folder's
/// count of cited paths, `cited` the number of entries cited.
typedef CodeRootChoice = ({String value, int found, int cited});

/// Infers the `code_root` of the legacy project at [root]
/// (`write_project_files` E11).
///
/// A candidate is [root], [linkFolder], and each folder above either up to its
/// repository top. The winner is the candidate from which the most entries
/// resolve, the deepest on a tie, then [root], then [linkFolder], then the code
/// point order of the paths. [implementsEntries] are `path[:Symbol]` entries
/// that count for a regular file; [coversEntries] count for a file or folder.
CodeRootChoice inferCodeRoot(
  Directory root, {
  Directory? linkFolder,
  required List<String> implementsEntries,
  required List<String> coversEntries,
}) {
  final cited = implementsEntries.length + coversEntries.length;
  final ranked = [
    for (final candidate in _candidatesOf(root, linkFolder))
      (
        folder: candidate.folder,
        rank: candidate.rank,
        depth: _depthOf(candidate.folder),
        count: _countFrom(candidate.folder, implementsEntries, coversEntries),
      ),
  ]..sort(_byPreference);
  final winner = ranked.first;
  return (
    value: winner.count > 0 ? _valueOf(root, winner.folder) : '.',
    found: winner.count,
    cited: cited,
  );
}

/// Returns the candidates, each folder once under its lowest rank.
List<({Directory folder, int rank})> _candidatesOf(
  Directory root,
  Directory? linkFolder,
) {
  final byPath = <String, ({Directory folder, int rank})>{};
  void add(Directory folder, int rank) =>
      byPath.putIfAbsent(folder.path, () => (folder: folder, rank: rank));
  add(root, _rootRank);
  if (linkFolder != null) add(linkFolder, _linkRank);
  for (final start in [root, ?linkFolder]) {
    _foldersAbove(start).forEach((folder) => add(folder, _aboveRank));
  }
  return byPath.values.toList();
}

/// Returns each folder above [folder] up to its repository top; none when
/// [folder] lies in no repository.
Iterable<Directory> _foldersAbove(Directory folder) sync* {
  final top = repositoryTopOf(folder);
  if (top == null) return;
  var current = folder;
  while (current.path != top.path) {
    final parent = current.parent;
    if (parent.path == current.path) return;
    current = parent;
    yield current;
  }
}

int _depthOf(Directory folder) =>
    folder.uri.pathSegments.where((segment) => segment.isNotEmpty).length;

int _countFrom(
  Directory base,
  List<String> implementsEntries,
  List<String> coversEntries,
) =>
    implementsEntries
        .where((entry) => ImplementsEntry(entry).namesFileFrom(base))
        .length +
    coversEntries.where((entry) => namesFileOrFolderFrom(base, entry)).length;

typedef _Ranked = ({Directory folder, int rank, int depth, int count});

int _byPreference(_Ranked a, _Ranked b) {
  final byCount = b.count.compareTo(a.count);
  if (byCount != 0) return byCount;
  final byDepth = b.depth.compareTo(a.depth);
  if (byDepth != 0) return byDepth;
  final byRank = a.rank.compareTo(b.rank);
  if (byRank != 0) return byRank;
  return compareCodePoints(a.folder.path, b.folder.path);
}

/// Returns [winner] from [root] as the key value, `.` when no key is written:
/// the winner is the root, or the reader would refuse its path, or none
/// reaches it.
String _valueOf(Directory root, Directory winner) {
  final relative = relativeFolderPath(root, winner);
  return relative != null && isCodeRootValue(relative) ? relative : '.';
}
