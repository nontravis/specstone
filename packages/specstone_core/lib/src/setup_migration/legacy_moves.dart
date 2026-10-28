import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

const _featuresFolder = 'prds/features/';
const _specsFolder = 'specs/';
const _topicsFolder = 'specs/topics/';
const _architectureFolder = 'specs/architecture/';

/// The Spec map `feature_id` that marks a cross-cutting row.
const _crossCutting = '—';

const _projectDocs = <String, (String, LegacyKind)>{
  'prds/d01_context.md': ('prds/PROJECT.md', LegacyKind.project),
  'prds/d02_features.md': ('prds/FEATURES.md', LegacyKind.features),
  'prds/d03_non_functional.md': ('prds/GNFR.md', LegacyKind.gnfr),
};

final _storyFile = RegExp(
  r'^(us\d+_[^/]+)/(?:(USER_STORY\.md)'
  r'|functional_requirements/(fr\d+_[^/]+\.md)'
  r'|non_functional_requirements/(nf\d+_[^/]+\.md))$',
);
final _specFile = RegExp(
  r'^s\d+_(architecture|api_[^/]+|domain|integration|errors|auth)\.md$',
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

  /// The renames in code point order of `from`, none with `from == to`.
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
/// its name, its folder, and the Spec map only (INV-2); a move onto a path a
/// staying file or an earlier move takes is dropped and its source stays
/// (NFR-DI01).
LegacyMoves planLegacyMoves(
  List<String> docPaths, {
  required List<SpecMapRow> specMap,
  required LegacyFeatures features,
}) {
  final sorted = [...docPaths]..sort(compareCodePoints);
  final specFolders = _specFoldersOf(specMap);

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
    final specFile = _readSpecFile(path, specFolders, features);
    if (specFile is _CrossCuttingFile) placed[path] = specFile.placement;
    if (specFile is _FeatureSpecFile) specFiles.add(specFile);
  }
  placed.addAll(_resolveFeatureSpecs(specFiles));

  final kept = _withoutBlockedMoves(sorted, placed);

  return LegacyMoves(
    moves: [
      for (final MapEntry(key: from, value: placement) in kept.entries)
        if (from != placement.to) (from: from, to: placement.to),
    ],
    kindOf: {
      for (final placement in kept.values)
        if (placement.kind != null) placement.to: placement.kind!,
    },
    fromOf: {
      for (final MapEntry(key: from, value: placement) in kept.entries)
        placement.to: from,
    },
    left: [
      for (final path in sorted)
        if (!kept.containsKey(path)) path,
    ],
  );
}

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

  String get oldFolderName {
    final folder = from.substring(0, from.lastIndexOf('/'));
    return folder.substring(folder.lastIndexOf('/') + 1);
  }
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

/// Rule 5: a direct file of a spec folder some Spec map row names.
_SpecFile? _readSpecFile(
  String path,
  Map<String, Set<String>> specFolders,
  LegacyFeatures features,
) {
  if (!path.startsWith(_specsFolder)) return null;
  final split = path.lastIndexOf('/') + 1;
  final folder = path.substring(0, split);
  final name = path.substring(split);
  final ids = specFolders[folder]?.where((id) => id != _crossCutting).toList();
  if (ids == null) return null;

  if (ids.isEmpty) {
    final segments = folder.split('/');
    final last = segments[segments.length - 2];
    return _CrossCuttingFile((to: '$_topicsFolder$last/$name', kind: null));
  }
  if (ids.length != 1) return null;

  final match = _specFile.firstMatch(name);
  final featurePath = _featurePathOfId(ids.single, features);
  if (match == null || featurePath == null) return null;
  final (docName, kind) = _specDocOf(match.group(1)!);
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

(String, LegacyKind) _specDocOf(String name) => switch (name) {
  'architecture' => ('ARCHITECTURE', LegacyKind.architecture),
  'domain' => ('DOMAIN', LegacyKind.domain),
  'integration' => ('INTEGRATION', LegacyKind.integration),
  'errors' => ('ERROR', LegacyKind.error),
  'auth' => ('AUTH', LegacyKind.auth),
  _ => ('API', LegacyKind.api),
};

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
    for (final file in group) {
      final shared = group.where((o) => o.oldName == file.oldName).length > 1;
      final folder = shared ? '${file.oldFolderName}/' : '';
      placed[file.from] = (
        to: '$_specsFolder${file.featurePath}/$folder${file.oldName}',
        kind: null,
      );
    }
  }
  return placed;
}

/// Rule 8: drops each move onto a path a staying file or an earlier move takes.
///
/// Keeps the placements of [sorted] in order. A dropped source stays, so it
/// takes its own path; the pass repeats until no move drops.
Map<String, _Placement> _withoutBlockedMoves(
  List<String> sorted,
  Map<String, _Placement> placed,
) {
  final dropped = <String>{};
  for (var changed = true; changed;) {
    changed = false;
    final taken = {
      for (final path in sorted)
        if (!placed.containsKey(path) || dropped.contains(path)) path,
      for (final MapEntry(key: from, value: placement) in placed.entries)
        if (from == placement.to) from,
    };
    for (final path in sorted) {
      final placement = placed[path];
      if (placement == null || dropped.contains(path)) continue;
      if (placement.to == path) continue;
      if (taken.add(placement.to)) continue;
      dropped.add(path);
      changed = true;
    }
  }
  return {
    for (final path in sorted)
      if (placed[path] != null && !dropped.contains(path)) path: placed[path]!,
  };
}
