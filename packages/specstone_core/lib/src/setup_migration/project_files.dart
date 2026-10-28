import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_version.dart';

const _templatesFolder = '.specstone/templates';
const _featureFolder = 'prds/features/{slug}/f{nn}_{slug}';
const _storyFolder = '$_featureFolder/us{nn}_{slug}';
const _specFolder = 'specs/{slug}/f{nn}_{slug}';

/// The path pattern of each doc type a grouped tree overrides (INV-14).
const _groupedPaths = {
  'feature': '$_featureFolder/FEATURE.md',
  'user_story': '$_storyFolder/USER_STORY.md',
  'fr': '$_storyFolder/fr{nn}_{slug}.md',
  'nf': '$_storyFolder/nf{nn}_{slug}.md',
  'architecture': '$_specFolder/ARCHITECTURE.md',
  'api': '$_specFolder/API.md',
  'domain': '$_specFolder/DOMAIN.md',
  'error': '$_specFolder/ERROR.md',
  'integration': '$_specFolder/INTEGRATION.md',
  'auth': '$_specFolder/AUTH.md',
};

/// Singular doc types print and write first in this order (PD16).
const _draftOrder = ['project', 'features', 'gnfr', 'tech_stack'];

final _otherCharacters = RegExp('[^a-z0-9]+');
final _edgeUnderscores = RegExp(r'^_+|_+$');

/// Returns the `config.yaml` text pinning each of [pins] (INV-15).
///
/// Writes `packs:` only, one pin per line in code point order of the name.
String configText(Map<String, PackVersion> pins) {
  final names = pins.keys.toList()..sort(compareCodePoints);
  final lines = [for (final name in names) '  $name: ${pins[name]}\n'];
  return 'packs:\n${lines.join()}';
}

/// Returns the `covers:` block of the spec folder [legacyFolder], or null.
///
/// Lists the Code path of every [specMap] row naming [legacyFolder], in row
/// order. `label` is the line the dry run prints for the block.
({String block, String label})? coversOf(
  String legacyFolder,
  List<SpecMapRow> specMap,
) {
  final paths = [
    for (final row in specMap)
      if (row.specPath == legacyFolder) row.codePath,
  ];
  if (paths.isEmpty) return null;
  return (
    block: 'covers:\n${[for (final path in paths) '  - $path\n'].join()}',
    label: paths.length == 1
        ? 'covers (1 path)'
        : 'covers (${paths.length} paths)',
  );
}

/// Returns the project-layer `path:` overrides of a grouped tree (INV-14).
///
/// Keys are `.specstone/templates/<id>.yaml`; the group is the first `{slug}`.
Map<String, String> groupedPathOverrides() => {
  for (final MapEntry(:key, :value) in _groupedPaths.entries)
    '$_templatesFolder/$key.yaml': 'path: $value\n',
};

/// Returns the `gnfr` section override for [headers], null when empty.
///
/// Each section id is its header lowercased, every run of characters other than
/// `[a-z0-9]` turned to `_`, and trimmed of `_`.
MapEntry<String, String>? gnfrOverride(List<String> headers) {
  if (headers.isEmpty) return null;
  final sections = [
    for (final header in headers)
      '  - id: ${_sectionId(header)}\n    header: $header\n',
  ];
  return MapEntry(
    '$_templatesFolder/gnfr.yaml',
    'sections:\n${sections.join()}',
  );
}

/// Returns the doc types of [set] whose path holds no `{nn}` and no `{slug}`.
///
/// Ordered `project`, `features`, `gnfr`, `tech_stack`, then the rest by
/// DocPath (PD16).
List<MergedDocType> singularDocTypes(MergedSet set) {
  final singular = [
    for (final docType in set.docTypes)
      if (_isSingular(docType.path)) docType,
  ];
  return singular..sort(_byDraftOrder);
}

/// Parses each of [files] as a project-layer doc type, keyed by its path.
///
/// A malformed override throws a `TemplateFault` here, in the plan, not after
/// commit 2.
List<DocTypeLayer> parseOverrides(Map<String, String> files) => [
  for (final MapEntry(:key, :value) in files.entries)
    DocTypeLayer.parse(
      value,
      file: key,
      docTypeId: _docTypeId(key),
      kind: LayerKind.project,
      files: const _NoFiles(),
    ),
];

String _sectionId(String header) => header
    .toLowerCase()
    .replaceAll(_otherCharacters, '_')
    .replaceAll(_edgeUnderscores, '');

/// Returns the file name of [path] without its folder and `.yaml`.
String _docTypeId(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return name.endsWith('.yaml')
      ? name.substring(0, name.length - '.yaml'.length)
      : name;
}

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
