import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/table_first_cells.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _architectureType = 'architecture';
const _projectArchitectureType = 'project_architecture';
const _integrationType = 'integration';
const _componentsSection = 'components';
const _externalSystemsSection = 'external_systems';
const _systemsSection = 'systems';

/// The names a diagram's boxes and participants are held to, and the role
/// names an `actor` is held to.
final class DiagramNames {
  const new({required this.names, required this.roles});

  /// The Component and System names a box or participant may carry.
  final Set<String> names;

  /// The role names an `actor` may carry.
  final Set<String> roles;
}

/// Returns the System cell of every doc whose type holds a `systems` section.
Set<String> systemNamesOf(CheckContext context) => {
  for (final doc in context.index.docs)
    if (_holdsSection(context.typeOf(doc), _systemsSection))
      ...firstCellsOf(context, doc, _systemsSection),
};

/// Returns the names the docs of [target] give every diagram of that target.
///
/// The Component and System cells of each `project_architecture` doc, and a
/// feature's mention alone and with each Component cell of its
/// `architecture` doc.
Set<String> targetDocNamesOf(CheckContext context, String? target) {
  final names = <String>{};
  for (final doc in context.index.docs) {
    if (!doc.inTarget(target)) continue;
    switch (doc.docTypeId) {
      case _projectArchitectureType:
        if (context.typeHoldsSection(
          _projectArchitectureType,
          _componentsSection,
        )) {
          names.addAll(firstCellsOf(context, doc, _componentsSection));
        }
        if (context.typeHoldsSection(
          _projectArchitectureType,
          _externalSystemsSection,
        )) {
          names.addAll(firstCellsOf(context, doc, _externalSystemsSection));
        }
      case _architectureType:
        final mention = '$featureType:${doc.name}';
        names.add(mention);
        if (context.typeHoldsSection(_architectureType, _componentsSection)) {
          for (final cell in firstCellsOf(context, doc, _componentsSection)) {
            names.add('$mention $cell');
          }
        }
    }
  }
  return names;
}

/// Returns the names only [doc] gives: its own Component cells, and the
/// System cells of the `integration` doc of its name and target.
Set<String> docNamesOf(CheckContext context, IndexedDoc doc) => {
  ...firstCellsOf(context, doc, _componentsSection),
  if (context.typeHoldsSection(_integrationType, _externalSystemsSection))
    for (final integration in context.index.docs)
      if (integration.docTypeId == _integrationType &&
          integration.name == doc.name &&
          integration.inTarget(doc.target))
        ...firstCellsOf(context, integration, _externalSystemsSection),
};

bool _holdsSection(MergedDocType? type, String id) =>
    type != null && type.sections.any((section) => section.id == id);
