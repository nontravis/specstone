import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/document_writing/new_doc.dart'
    show skeletonOf;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/setup_migration/first_fingerprints.dart';
import 'package:specstone_core/src/setup_migration/legacy_moves.dart';
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

const _carriedPacks = ['prd-core', 'software-tech'];
const _docsFolder = 'docs/';
const _specIndexPath = 'specs/INDEX.md';
const _gitignorePath = '.specstone/.gitignore';
const _gitignoreText = 'index.sqlite*\nbuild/\ntrash/\n';
const _gnfrId = 'gnfr';
const _commit1Message = 'move legacy docs to their new paths';
const _commit2Message =
    'rewrite titles, keys, and links; add project configuration';
const _closingLine = 'run specstone check to list what is left to fill';

final _frFile = RegExp(r'/functional_requirements/fr\d+_[^/]+\.md$');

/// Plans the legacy migration of the project at [root].
///
/// Reads the files under `docs/prds` and `docs/specs`, the carried packs, and
/// nothing else; writes nothing. Throws `MigrateFault` `group_slug_duplicate`
/// and a `TemplateFault` before it returns, so a refused run prints nothing.
/// [homeDirectory] is the personal pack home, or null.
RunPlan planLegacyRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
}) {
  final docsRoot = Directory.fromUri(root.uri.resolve(_docsFolder));
  final docPaths = _docPathsOf(docsRoot)..sort(compareCodePoints);
  final specMap = _specMapOf(docsRoot, docPaths);
  final features = scanLegacyFeatures(docPaths);
  refuseDuplicateGroups(features);
  final legacy = planLegacyMoves(
    docPaths,
    specMap: specMap,
    features: features,
  );

  final carried = templates.resolveCarried(
    packNames: _carriedPacks,
    homeDirectory: homeDirectory,
  );
  final gnfr = carried.lookup(_gnfrId);
  final carriedGnfr = <String>{
    if (gnfr != null)
      for (final section in gnfr.sections) section.header,
  };

  final rewrites = _rewritesOf(
    docsRoot,
    docPaths,
    legacy: legacy,
    specMap: specMap,
    features: features,
    carriedGnfr: carriedGnfr,
  );
  final overrides = _overridesOf(features, rewrites.gnfrSections);
  final projectSet = templates.resolveCarried(
    packNames: _carriedPacks,
    homeDirectory: homeDirectory,
    projectLayers: parseOverrides(overrides),
  );
  final pins = {
    for (final MapEntry(:key, :value)
        in templates
            .availableManifests(_carriedPacks, homeDirectory: homeDirectory)
            .entries)
      key: value.version,
  };

  return RunPlan(
    header: 'legacy migration: ${root.path} ($legacyContextPath)',
    moves: legacy.moves,
    prunes: _prunesOf(legacy.moves),
    rewrites: rewrites.planned,
    creates: [
      PlannedCreate(
        path: projectConfigPath,
        text: configText(pins),
        note: ': ${_pinList(pins)}',
      ),
      if (!File.fromUri(root.uri.resolve(_gitignorePath)).existsSync())
        const PlannedCreate(path: _gitignorePath, text: _gitignoreText),
      for (final path in overrides.keys.toList()..sort(compareCodePoints))
        PlannedCreate(path: path, text: overrides[path]!),
      ..._draftsOf(projectSet, docPaths, legacy.moves),
    ],
    left: legacy.left,
    commit1Message: _commit1Message,
    commit2Message: _commit2Message,
    closingLine: _closingLine,
  );
}

/// Returns the DocPath of every file under `prds/` and `specs/`.
List<String> _docPathsOf(Directory docsRoot) {
  final separator = Platform.pathSeparator;
  final prefixLength = docsRoot.path.endsWith(separator)
      ? docsRoot.path.length
      : docsRoot.path.length + 1;
  final paths = <String>[];
  for (final folder in const ['prds', 'specs']) {
    final dir = Directory.fromUri(docsRoot.uri.resolve('$folder/'));
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      paths.add(
        entity.path
            .substring(prefixLength)
            .split(Platform.pathSeparator)
            .join('/'),
      );
    }
  }
  return paths;
}

List<SpecMapRow> _specMapOf(Directory docsRoot, List<String> docPaths) {
  if (!docPaths.contains(_specIndexPath)) return const [];
  final index = File.fromUri(docsRoot.uri.resolve(_specIndexPath));
  return readSpecMap(readDocText(index.readAsBytesSync()).lf);
}

typedef _Rewrites = ({List<PlannedRewrite> planned, List<String> gnfrSections});

_Rewrites _rewritesOf(
  Directory docsRoot,
  List<String> docPaths, {
  required LegacyMoves legacy,
  required List<SpecMapRow> specMap,
  required LegacyFeatures features,
  required Set<String> carriedGnfr,
}) {
  final carriedKeys = {for (final header in carriedGnfr) headerKey(header)};
  final newPaths = legacy.fromOf.keys.toList()
    ..sort((a, b) => compareCodePoints(legacy.fromOf[a]!, legacy.fromOf[b]!));
  final planned = <PlannedRewrite>[];
  final gnfrSections = <String>[];
  final seenKeys = <String>{};

  for (final newPath in newPaths) {
    final legacyPath = legacy.fromOf[newPath]!;
    final original = readDocText(
      File.fromUri(docsRoot.uri.resolve(legacyPath)).readAsBytesSync(),
    );
    var lf = original.lf;
    final changes = <String>[];
    var note = '';

    void label(String? text) {
      if (text != null) changes.add(text);
    }

    final kind = legacy.kindOf[newPath];
    if (kind != null) {
      final rewrite = rewriteLegacyDoc(lf, kind, gnfrHeaders: carriedGnfr);
      lf = rewrite.lf;
      changes.addAll(rewrite.changes);
      final missing = [
        for (final header in rewrite.gnfrSections)
          if (!carriedKeys.contains(headerKey(header)) &&
              seenKeys.add(headerKey(header)))
            header,
      ];
      if (missing.isNotEmpty) {
        gnfrSections.addAll(missing);
        note =
            '; project-layer section${missing.length == 1 ? '' : 's'} '
            '${missing.join(', ')}';
      }

      final renamed = legacyPath != newPath;
      if (renamed && kind == LegacyKind.architecture) {
        final covers = coversOf(_folderOf(legacyPath), specMap);
        if (covers != null) {
          lf = withKeyBlock(lf, 'covers', covers.block);
          changes.add(covers.label);
        }
      }
      if (renamed && kind == LegacyKind.api && newPath.endsWith('/API.md')) {
        final fingerprints = writeFirstFingerprints(
          lf,
          featureFrs: _featureFrsOf(docsRoot, docPaths, features, newPath),
        );
        lf = fingerprints.lf;
        label(fingerprints.label);
      }
    }

    final links = rewriteLinks(lf, docPath: legacyPath, moves: legacy.moves);
    lf = links.lf;
    label(links.label);

    if (changes.isEmpty) continue;
    planned.add(
      PlannedRewrite(
        path: '$_docsFolder$newPath',
        text: writtenText(original, lf),
        changes: changes,
        note: note,
      ),
    );
  }
  return (planned: planned, gnfrSections: gnfrSections);
}

String _folderOf(String docPath) =>
    docPath.substring(0, docPath.lastIndexOf('/') + 1);

/// Returns the LF text of each legacy FR file of the feature that holds the
/// API doc at [apiPath] (`specs/<FeaturePath>/API.md`), by legacy DocPath.
Map<String, String> _featureFrsOf(
  Directory docsRoot,
  List<String> docPaths,
  LegacyFeatures features,
  String apiPath,
) {
  final featurePath = _folderOf(apiPath)
      .substring('specs/'.length)
      .replaceFirst(RegExp(r'/$'), '');
  final folder = features.features
      .where((feature) => feature.featurePath == featurePath)
      .map((feature) => feature.folder)
      .firstOrNull;
  if (folder == null) return const {};
  return {
    for (final path in docPaths)
      if (path.startsWith(folder) && _frFile.hasMatch(path))
        path: readDocText(
          File.fromUri(docsRoot.uri.resolve(path)).readAsBytesSync(),
        ).lf,
  };
}

/// Returns the project-layer files the moved tree needs, by ProjectPath.
Map<String, String> _overridesOf(
  LegacyFeatures features,
  List<String> gnfrSections,
) {
  final gnfr = gnfrOverride(gnfrSections);
  return {
    if (features.grouped) ...groupedPathOverrides(),
    if (gnfr != null) gnfr.key: gnfr.value,
  };
}

/// Returns the folders the moves empty, the deepest first, as ProjectPaths.
List<String> _prunesOf(List<PathMove> moves) => {
  for (final move in moves)
    '$_docsFolder${move.from.substring(0, move.from.lastIndexOf('/'))}',
}.toList()..sort((a, b) => compareCodePoints(b, a));

/// Returns a draft for each singular doc type whose path the moved tree
/// lacks.
List<PlannedCreate> _draftsOf(
  MergedSet set,
  List<String> docPaths,
  List<PathMove> moves,
) {
  final moved = {for (final move in moves) move.from: move.to};
  final present = {for (final path in docPaths) moved[path] ?? path};
  return [
    for (final docType in singularDocTypes(set))
      if (!present.contains(docType.path))
        PlannedCreate(
          path: '$_docsFolder${docType.path}',
          text: skeletonOf(docType, docType.id),
          note: ' (draft)',
        ),
  ];
}

String _pinList(Map<String, PackVersion> pins) => [
  for (final name in pins.keys.toList()..sort(compareCodePoints))
    '$name ${pins[name]}',
].join(', ');
