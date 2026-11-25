import 'package:specstone_core/src/document_writing/item_landing.dart'
    show unitIdsIn;
import 'package:specstone_core/src/document_writing/keyed_units.dart';
import 'package:specstone_core/src/document_writing/move_plan_engine.dart'
    show sourceHashOf;
import 'package:specstone_core/src/document_writing/scenario_items.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;

/// The doc types a plan names as `keep` doc lines under their parent.
const Set<String> _planDocTypes = {featureType, storyType, frType, nfType};

/// Returns the move plan of each doc [addresses] names, as it stands: its
/// `source` line, then a `keep` line per unit in the doc's own order.
///
/// A feature's plan also keeps its stories and sub-features, and a story's its
/// FRs and nfs. A unit no plan line can name, a row keyed by text with a space,
/// gets the comment `# <address> names no plan line` in its place.
String planSkeletonOf(
  WriteSession session,
  List<String> addresses, {
  String? codeTarget,
}) {
  final out = StringBuffer();
  for (final address in addresses) {
    final doc = session.target(address, codeTarget: codeTarget);
    final name = session.index.addressOf(doc);
    final bytes = session.readDocBytes(doc.docPath);
    out.writeln('source $name ${sourceHashOf(bytes ?? const [])}');
    for (final unit in [
      ..._unitsOf(session, doc),
      ..._childrenOf(session, doc),
    ]) {
      out.writeln(
        _hasSpace.hasMatch(unit) ? '# $unit names no plan line' : '$unit keep',
      );
    }
  }
  return out.toString();
}

final _hasSpace = RegExp(r'\s');

/// Returns the address of each item, scenario, block, and row of [doc], in
/// file order, once each; a nested item rides with the item that holds it.
List<String> _unitsOf(WriteSession session, IndexedDoc doc) {
  final index = session.index;
  final content = index.contentOf(doc);
  final type = index.typeOf(doc);
  final name = index.addressOf(doc);
  final keyed = {
    for (final section in keyedSectionsOf(content, type!))
      section.at: [for (final unit in section.units) unit.address],
  };
  final units = [
    for (final (at, section) in citedSectionsOf(content, type).indexed) ...[
      if (section.prefixId case final prefix?)
        for (final id in unitIdsIn(content, at, type, prefix)) '$name#$id',
      if (section.isAcceptanceCriteria && doc.docTypeId == storyType)
        for (final id in scenarioIdsOf(content, type)) '$name#${id.written}',
      for (final address in keyed[at] ?? const <String>[]) '$name#$address',
    ],
  ];
  return units.toSet().toList();
}

/// Returns the address of each story, sub-feature, FR, and nf directly under
/// [doc], in the order the index holds them.
List<String> _childrenOf(WriteSession session, IndexedDoc doc) => [
  for (final child in session.index.childrenOf(doc))
    if (_planDocTypes.contains(child.docTypeId)) session.index.addressOf(child),
];
