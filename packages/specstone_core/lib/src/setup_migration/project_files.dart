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

final _idRun = RegExp('[a-z0-9]+');
final _plainId = RegExp(r'^[a-z][a-z0-9_]*$');
const _yamlWords = {'true', 'false', 'null'};
final _plainPath = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_./-]*$');

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
/// order, skipping empty paths. `label` is the line the dry run prints for the
/// block.
({String block, String label})? coversOf(
  String legacyFolder,
  List<SpecMapRow> specMap,
) {
  final paths = [
    for (final row in specMap)
      if (row.specPath == legacyFolder && row.codePath.isNotEmpty) row.codePath,
  ];
  if (paths.isEmpty) return null;
  final lines = [for (final path in paths) '  - ${_coverPath(path)}\n'].join();
  return (
    block: 'covers:\n$lines',
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
/// Each header is a single-quoted YAML scalar. Its id is the lowercased
/// `[a-z0-9]` runs joined by `_`, `category_<n>` (n the 1-based position) when
/// none remain, and suffixed `_2`, `_3`, ... to the first id no earlier header
/// took, so ids stay unique for any header list.
///
/// [carriedIds] are the section ids the carried `gnfr` already holds; they
/// count as taken, so an override adds a section and never replaces one.
MapEntry<String, String>? gnfrOverride(
  List<String> headers, {
  Set<String> carriedIds = const {},
}) {
  if (headers.isEmpty) return null;
  final used = {...carriedIds};
  final sections = <String>[];
  for (final (index, header) in headers.indexed) {
    final base = _sectionId(header) ?? 'category_${index + 1}';
    var id = base;
    for (var suffix = 2; !used.add(id); suffix++) {
      id = '${base}_$suffix';
    }
    sections.add(
      '  - id: ${_sectionIdScalar(id)}\n    header: ${_quoted(header)}\n',
    );
  }
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

/// Parses the doc-type files among [files] as project-layer doc types.
///
/// Keys are `.specstone/templates/<id>.yaml`; like the project loader it reads
/// only top-level `<id>.yaml` files, not `pack.yaml`, in code point order of
/// the name (INV-22). A malformed override throws a `TemplateFault` here, in
/// the plan, not after commit 2.
List<DocTypeLayer> parseOverrides(Map<String, String> files) {
  const prefix = '$_templatesFolder/';
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

/// Returns the lowercased `[a-z0-9]` runs of [header] joined by `_`, or null.
String? _sectionId(String header) {
  final runs = _idRun.allMatches(header.toLowerCase());
  return runs.isEmpty ? null : runs.map((run) => run[0]).join('_');
}

/// Returns [text] as a single-quoted YAML scalar, `'` doubled.
String _quoted(String text) => "'${text.replaceAll("'", "''")}'";

/// Returns the section [id] as written when YAML reads a string, else quoted.
String _sectionIdScalar(String id) =>
    _plainId.hasMatch(id) && !_yamlWords.contains(id) ? id : _quoted(id);

/// Returns [path] as written when plain YAML reads it back, else quoted.
String _coverPath(String path) =>
    _plainPath.hasMatch(path) ? path : _quoted(path);

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
