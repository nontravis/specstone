import 'dart:math';

import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart'
    show orderedMoves;
import 'package:specstone_core/src/templates/code_point_order.dart';

const _featuresFolder = 'prds/features/';
const _specsFolder = 'specs/';
const _topicsFolder = 'specs/topics/';
const _architectureFolder = 'specs/architecture/';

/// The Spec map file, which stays in place whatever row names its folder (E13).
const _specIndexPath = 'specs/INDEX.md';

/// The Spec map `feature_id` that marks a cross-cutting row.
const _crossCutting = '—';

const _projectDocs = <String, (String, LegacyKind)>{
  'prds/d01_context.md': ('prds/PROJECT.md', LegacyKind.project),
  'prds/d02_features.md': ('prds/FEATURES.md', LegacyKind.features),
  'prds/d03_non_functional.md': ('prds/GNFR.md', LegacyKind.gnfr),
};

const _resolveCollision =
    'move or rename the legacy files each line names, or the file that stays, '
    'so no two moves land on one path, no move lands on a file that stays, '
    'and no moves form a cycle, then run specstone migrate again';

final _storyFile = RegExp(
  r'^(us\d+_[^/]+)/(?:(USER_STORY\.md)'
  r'|functional_requirements/(fr\d+_[^/]+\.md)'
  r'|non_functional_requirements/(nf\d+_[^/]+\.md))$',
);

/// The doc file name and doc type of each legacy spec kind, by kind name.
const _specKinds = <String, (String, LegacyKind)>{
  'architecture': ('ARCHITECTURE', LegacyKind.architecture),
  'api': ('API', LegacyKind.api),
  'domain': ('DOMAIN', LegacyKind.domain),
  'integration': ('INTEGRATION', LegacyKind.integration),
  'errors': ('ERROR', LegacyKind.error),
  'auth': ('AUTH', LegacyKind.auth),
};

/// A legacy spec file `s<NN>_<kind>.md` or `s<NN>_<kind>_<suffix>.md`.
///
/// Group 1 is the kind, which ends at the `_` or at the `.md`.
final _specFile = RegExp(
  r'^s\d+_('
  '${_specKinds.keys.join('|')}'
  r')(?:_[^/]+)?\.md$',
);

/// The doc type a legacy file is renamed to.
enum LegacyKind {
  project,
  features,
  gnfr,
  feature,
  userStory,
  fr,
  nf,
  architecture,
  api,
  domain,
  integration,
  error,
  auth,
  topic,
}

/// The renames of a legacy migrate run and the files no rule places.
final class LegacyMoves {
  const new({
    required this.moves,
    required this.kindOf,
    required this.fromOf,
    required this.left,
  });

  /// The renames in the order the journal runs them, none with `from == to`.
  ///
  /// Code point order of `from`, but a move onto a path another move leaves
  /// runs after that move.
  final List<PathMove> moves;

  /// The doc type of every typed file, by its new DocPath.
  ///
  /// Includes a typed file that keeps its path.
  final Map<String, LegacyKind> kindOf;

  /// The legacy DocPath of every planned file, by its new DocPath.
  ///
  /// Includes a file that keeps its path.
  final Map<String, String> fromOf;

  /// The DocPaths no rule places, in code point order.
  final List<String> left;
}

/// Plans the renames of the legacy files [docPaths].
///
/// [docPaths] are every file under `prds/` and `specs/`. A file is placed by
/// its name, its folder, and the Spec map only (INV-2). Throws
/// `MigrateFault` `legacy_collision` when two moves land on one path, a move
/// lands on a staying file, or moves form a cycle, each compared ignoring
/// letter case; no move is dropped (E14).
LegacyMoves planLegacyMoves(
  List<String> docPaths, {
  required List<SpecMapRow> specMap,
  required LegacyFeatures features,
}) {
  final sorted = [...docPaths]..sort(compareCodePoints);
  final specFolders = _specFoldersOf(specMap);
  final topicFolders = _topicFolderNames(specFolders, sorted);

  final placed = <String, _Placement>{};
  final specFiles = <_FeatureSpecFile>[];
  for (final path in sorted) {
    final placement =
        _placeProjectDoc(path) ??
        _placeInFeature(path, features) ??
        _placeContainer(path, features) ??
        _placeTopic(path);
    if (placement != null) {
      placed[path] = placement;
      continue;
    }
    final specFile = _readSpecFile(path, specFolders, topicFolders, features);
    if (specFile is _CrossCuttingFile) placed[path] = specFile.placement;
    if (specFile is _FeatureSpecFile) specFiles.add(specFile);
  }
  placed.addAll(_resolveFeatureSpecs(specFiles));

  final moves = [
    for (final path in sorted)
      if (placed[path] case final placement? when placement.to != path)
        (from: path, to: placement.to),
  ];
  refuseCollisions(sorted, moves);

  return LegacyMoves(
    moves: orderedMoves(moves, keyOf: caseBlindPath),
    kindOf: {
      for (final placement in placed.values)
        if (placement.kind != null) placement.to: placement.kind!,
    },
    fromOf: {
      for (final MapEntry(key: from, value: placement) in placed.entries)
        placement.to: from,
    },
    left: [
      for (final path in sorted)
        if (!placed.containsKey(path)) path,
    ],
  );
}

/// Returns [path] as every legacy path comparison of E11, E12, and E14 sees it.
///
/// Dart's locale-free simple Unicode lowercase, so `Ä` and `ä` fold too. It is
/// not a file system's fold: NTFS and APFS fold some names it keeps apart
/// (`ς` and `Σ`) and keep apart some it folds (`İ` and `i`).
String caseBlindPath(String path) => path.toLowerCase();

typedef _Placement = ({String to, LegacyKind? kind});

sealed class _SpecFile {
  const new();
}

final class _CrossCuttingFile extends _SpecFile {
  const new(this.placement);

  final _Placement placement;
}

final class _FeatureSpecFile extends _SpecFile {
  const new({
    required this.from,
    required this.featurePath,
    required this.docName,
    required this.kind,
  });

  final String from;
  final String featurePath;

  /// The singular doc file name, such as `ARCHITECTURE`.
  final String docName;
  final LegacyKind kind;

  String get oldName => from.substring(from.lastIndexOf('/') + 1);

  /// The old folder path, ending in `/`.
  String get oldFolder => from.substring(0, from.lastIndexOf('/') + 1);
}

_Placement? _placeProjectDoc(String path) {
  final doc = _projectDocs[path];
  return doc == null ? null : (to: doc.$1, kind: doc.$2);
}

/// Rule 2: the files of a feature that has a FeaturePath.
_Placement? _placeInFeature(String path, LegacyFeatures features) {
  for (final feature in features.features) {
    final featurePath = feature.featurePath;
    if (featurePath == null || !path.startsWith(feature.folder)) continue;
    final relative = path.substring(feature.folder.length);
    final root = '$_featuresFolder$featurePath/';
    if (relative == 'FEATURE.md') {
      return (to: '$root$relative', kind: LegacyKind.feature);
    }
    final story = _storyFile.firstMatch(relative);
    if (story == null) return null;
    final folder = '$root${story.group(1)}/';
    if (story.group(2) != null) {
      return (to: '$folder${story.group(2)}', kind: LegacyKind.userStory);
    }
    if (story.group(3) != null) {
      return (to: '$folder${story.group(3)}', kind: LegacyKind.fr);
    }
    return (to: '$folder${story.group(4)}', kind: LegacyKind.nf);
  }
  return null;
}

/// Rule 3: the `FEATURE.md` of a container whose children are features.
_Placement? _placeContainer(String path, LegacyFeatures features) {
  if (!features.containers.contains(path)) return null;
  final folder = path.substring(0, path.length - 'FEATURE.md'.length);
  if (!features.features.any((f) => f.group == folder)) return null;
  final name = folder.substring(0, folder.length - 1);
  final slug = groupSlugOf(name.substring(name.lastIndexOf('/') + 1));
  if (slug == null) return null;
  return (to: '$_featuresFolder$slug/FEATURE.md', kind: null);
}

/// Rule 4: `specs/architecture/<topic>.md`.
_Placement? _placeTopic(String path) {
  if (!path.startsWith(_architectureFolder) || !path.endsWith('.md')) {
    return null;
  }
  final topic = path.substring(_architectureFolder.length);
  if (topic.contains('/')) return null;
  return (to: '$_topicsFolder$topic', kind: LegacyKind.topic);
}

Map<String, Set<String>> _specFoldersOf(List<SpecMapRow> specMap) {
  final idsByFolder = <String, Set<String>>{};
  for (final row in specMap) {
    if (row.specPath.isEmpty) continue;
    (idsByFolder[row.specPath] ??= {}).add(row.featureId);
  }
  return idsByFolder;
}

/// The `specs/topics/` subfolder name of each cross-cutting spec folder that
/// can place a file.
///
/// Such a folder is `specs/` or a subfolder of it that holds one of [paths].
/// One whose last segment no other shares (ignoring letter case) keeps it; the
/// folders that share one take [trailingRunNames] among them (E12). `specs/`
/// keeps its own last segment, `specs`, and joins no sharing set, since it has
/// no trailing run.
Map<String, String> _topicFolderNames(
  Map<String, Set<String>> specFolders,
  List<String> paths,
) {
  final byLastSegment = <String, List<String>>{};
  final holding = {
    for (final path in paths) path.substring(0, path.lastIndexOf('/') + 1),
  };
  final folders = [
    for (final MapEntry(key: folder, value: ids) in specFolders.entries)
      if (ids.length == 1 && ids.single == _crossCutting) folder,
  ]..sort(compareCodePoints);
  final names = <String, String>{};
  for (final folder in folders) {
    final canPlace =
        folder.startsWith(_specsFolder) &&
        folder != _architectureFolder &&
        holding.contains(folder);
    if (!canPlace) continue;
    if (folder == _specsFolder) {
      names[folder] = _lastSegmentOf(folder);
      continue;
    }
    (byLastSegment[caseBlindPath(_lastSegmentOf(folder))] ??= []).add(folder);
  }
  for (final sharing in byLastSegment.values) {
    final runs = sharing.length == 1
        ? [_lastSegmentOf(sharing.single)]
        : trailingRunNames(sharing);
    for (var i = 0; i < sharing.length; i++) {
      names[sharing[i]] = runs[i];
    }
  }
  return names;
}

/// The last segment of a spec folder path ending in `/`.
String _lastSegmentOf(String folder) {
  final segments = folder.split('/');
  return segments[segments.length - 2];
}

/// Returns the subfolder name of each of [oldFolders], in the same order.
///
/// Each entry is an old folder path starting with `specs/` and ending in `/`.
/// An entry's name is the shortest run of trailing segments that differs,
/// ignoring letter case, from the same-length run of every other entry by
/// position, a folder with fewer segments comparing as its whole path. An
/// entry no run tells apart gets its whole path under `specs/`, without the
/// final `/`; `specs/` itself has no segment and gets `''`.
List<String> trailingRunNames(List<String> oldFolders) {
  assert(
    oldFolders.every((f) => f.startsWith(_specsFolder) && f.endsWith('/')),
    'every entry is a folder path from specs/ to a final /',
  );
  final segments = [
    for (final folder in oldFolders)
      [
        for (final segment in folder.substring(_specsFolder.length).split('/'))
          if (segment.isNotEmpty) segment,
      ],
  ];
  return [for (var i = 0; i < segments.length; i++) _runNameOf(i, segments)];
}

String _runNameOf(int index, List<List<String>> segments) {
  final own = segments[index];
  for (var length = 1; length < own.length; length++) {
    final run = caseBlindPath(_trailingRun(own, length));
    final tellsApart = [
      for (var i = 0; i < segments.length; i++)
        if (i != index) caseBlindPath(_trailingRun(segments[i], length)),
    ].every((other) => other != run);
    if (tellsApart) return _trailingRun(own, length);
  }
  return own.join('/');
}

String _trailingRun(List<String> segments, int length) =>
    segments.sublist(max(0, segments.length - length)).join('/');

/// Rule 5: a direct file of a spec folder some Spec map row names.
_SpecFile? _readSpecFile(
  String path,
  Map<String, Set<String>> specFolders,
  Map<String, String> topicFolders,
  LegacyFeatures features,
) {
  if (!path.startsWith(_specsFolder)) return null;
  final split = path.lastIndexOf('/') + 1;
  final folder = path.substring(0, split);
  if (folder == _architectureFolder) return null;
  final name = path.substring(split);
  final ids = specFolders[folder]?.where((id) => id != _crossCutting).toList();
  if (ids == null) return null;

  if (ids.isEmpty) {
    final topic = topicFolders[folder];
    if (topic == null || path == _specIndexPath) return null;
    return _CrossCuttingFile((to: '$_topicsFolder$topic/$name', kind: null));
  }
  if (ids.length != 1) return null;

  final match = _specFile.firstMatch(name);
  final featurePath = _featurePathOfId(ids.single, features);
  if (match == null || featurePath == null) return null;
  final (docName, kind) = _specKinds[match.group(1)]!;
  return _FeatureSpecFile(
    from: path,
    featurePath: featurePath,
    docName: docName,
    kind: kind,
  );
}

/// Returns the FeaturePath of the one feature folder named [featureId].
String? _featurePathOfId(String featureId, LegacyFeatures features) {
  final carriers = [
    for (final feature in features.features)
      if (feature.folder.endsWith('/$featureId/')) feature,
  ];
  return carriers.length == 1 ? carriers.single.featurePath : null;
}

/// Rule 6: places the spec files of each feature by the doc file they map to.
Map<String, _Placement> _resolveFeatureSpecs(List<_FeatureSpecFile> files) {
  final byDoc = <String, List<_FeatureSpecFile>>{};
  for (final file in files) {
    (byDoc['${file.featurePath}/${file.docName}'] ??= []).add(file);
  }

  final placed = <String, _Placement>{};
  for (final group in byDoc.values) {
    if (group.length == 1) {
      final file = group.single;
      placed[file.from] = (
        to: '$_specsFolder${file.featurePath}/${file.docName}.md',
        kind: file.kind,
      );
      continue;
    }
    final byName = <String, List<_FeatureSpecFile>>{};
    for (final file in group) {
      (byName[caseBlindPath(file.oldName)] ??= []).add(file);
    }
    for (final sameName in byName.values) {
      placed.addAll(_placeUnderOldNames(sameName));
    }
  }
  return placed;
}

/// Places [sameName], files of one name and feature, under their old names.
///
/// Several files of a name each go into a subfolder (E11); a lone file, and a
/// file held directly by `specs/`, go straight into the feature's spec folder.
Map<String, _Placement> _placeUnderOldNames(List<_FeatureSpecFile> sameName) {
  final subfolders = sameName.length == 1
      ? const ['']
      : [
          for (final run in trailingRunNames([
            for (final file in sameName) file.oldFolder,
          ]))
            if (run.isEmpty) '' else '$run/',
        ];
  return {
    for (var i = 0; i < sameName.length; i++)
      sameName[i].from: (
        to:
            '$_specsFolder${sameName[i].featurePath}/${subfolders[i]}'
            '${sameName[i].oldName}',
        kind: null,
      ),
  };
}

/// Throws `legacy_collision` for every target in [moves] that two moves land
/// on, that a move shares with a staying file, or that lies on a cycle of
/// moves (E14).
///
/// A target is the case-blind path; the fault line names its first spelling in
/// code point order. [sorted] holds every input path.
void refuseCollisions(List<String> sorted, List<PathMove> moves) {
  final faults = _collisionFaults(sorted, moves);
  for (final move in movesOnCycles(moves)) {
    faults.putIfAbsent(caseBlindPath(move.to), () => _cycleFault(move));
  }
  if (faults.isEmpty) return;
  final lines = faults.values.toList()
    ..sort((a, b) => compareCodePoints(a.file!, b.file!));
  throw MigrateFault(
    lines.first.code,
    lines.first.message,
    file: lines.first.file,
    more: lines.sublist(1),
  );
}

Map<String, MigrateFault> _collisionFaults(
  List<String> sorted,
  List<PathMove> moves,
) {
  final movesOnto = <String, List<PathMove>>{};
  for (final move in moves) {
    (movesOnto[caseBlindPath(move.to)] ??= []).add(move);
  }
  final moving = {for (final move in moves) move.from};
  final staying = <String, List<String>>{};
  for (final path in sorted) {
    final key = caseBlindPath(path);
    if (movesOnto.containsKey(key) && !moving.contains(path)) {
      (staying[key] ??= []).add(path);
    }
  }
  return {
    for (final MapEntry(:key, value: onto) in movesOnto.entries)
      if (onto.length + (staying[key]?.length ?? 0) > 1)
        key: _collisionFault(onto, staying[key] ?? const []),
  };
}

MigrateFault _collisionFault(List<PathMove> onto, List<String> staying) {
  final spellings = [for (final move in onto) move.to, ...staying]
    ..sort(compareCodePoints);
  final lands = [
    for (final move in onto) '${move.from} moves to ${move.to}',
    for (final path in staying) '$path stays',
  ];
  return MigrateFault(
    MigrateFaultCode.legacyCollision,
    'these legacy files land on one path: ${lands.join(', ')}; '
    '$_resolveCollision',
    file: spellings.first,
  );
}

MigrateFault _cycleFault(PathMove move) => MigrateFault(
  MigrateFaultCode.legacyCollision,
  '${move.from} moves to ${move.to}, which lies on a cycle of moves, each '
  'file waiting for another to leave its path; $_resolveCollision',
  file: move.to,
);

/// Returns the moves that lie on a cycle of moves, each waiting for another to
/// leave the path it moves onto.
///
/// A move onto its own old path in another letter case waits for nothing, so
/// no move waits for itself. A move that only leads from one cycle to another
/// lies on none. Public for tests.
List<PathMove> movesOnCycles(List<PathMove> moves) {
  final candidates = [
    for (final move in moves)
      if (caseBlindPath(move.to) != caseBlindPath(move.from)) move,
  ];
  final leaving = <String, List<int>>{};
  for (var i = 0; i < candidates.length; i++) {
    (leaving[caseBlindPath(candidates[i].from)] ??= []).add(i);
  }
  final componentOf = _componentIds([
    for (final move in candidates)
      leaving[caseBlindPath(move.to)] ?? const <int>[],
  ]);
  final sizes = <int, int>{};
  for (final id in componentOf) {
    sizes[id] = (sizes[id] ?? 0) + 1;
  }
  return [
    for (var i = 0; i < candidates.length; i++)
      if (sizes[componentOf[i]]! > 1) candidates[i],
  ];
}

/// Returns the strongly connected component id of each node of [edges], where
/// `edges[i]` lists the nodes `i` points to (Tarjan, without recursion).
List<int> _componentIds(List<List<int>> edges) {
  final count = edges.length;
  final order = List<int>.filled(count, -1);
  final lowLink = List<int>.filled(count, 0);
  final nextEdge = List<int>.filled(count, 0);
  final componentOf = List<int>.filled(count, -1);
  final open = <int>[];
  var visited = 0;
  var components = 0;

  void enter(int node, List<int> calls) {
    order[node] = lowLink[node] = visited++;
    open.add(node);
    calls.add(node);
  }

  for (var root = 0; root < count; root++) {
    if (order[root] != -1) continue;
    final calls = <int>[];
    enter(root, calls);
    while (calls.isNotEmpty) {
      final node = calls.last;
      if (nextEdge[node] < edges[node].length) {
        final next = edges[node][nextEdge[node]++];
        if (order[next] == -1) {
          enter(next, calls);
        } else if (componentOf[next] == -1) {
          lowLink[node] = min(lowLink[node], order[next]);
        }
        continue;
      }
      calls.removeLast();
      if (calls.isNotEmpty) {
        final caller = calls.last;
        lowLink[caller] = min(lowLink[caller], lowLink[node]);
      }
      if (lowLink[node] != order[node]) continue;
      int member;
      do {
        member = open.removeLast();
        componentOf[member] = components;
      } while (member != node);
      components++;
    }
  }
  return componentOf;
}
