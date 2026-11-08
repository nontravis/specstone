import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// How a `link_self` message shows an empty link target, `[x]()`.
const _emptyTarget = '(empty)';

/// One string `doc_ref` value of a doc, with its field and its file line.
typedef _DocRefValue = ({MergedField field, String value, int line});

/// Returns the `resolve_doc_links` findings of [doc]'s `doc_ref` values and
/// links.
///
/// A typed doc is checked for both, an untyped doc of a checked folder for
/// links only. A doc the markdown parser failed on gets `markdown_unparsed`,
/// stating the `index_query` warning, since its links go unchecked.
Iterable<Finding> checkDocLinks(CheckContext context, IndexedDoc doc) sync* {
  final unparsed = markdownUnparsedWarning(doc.docPath);
  if (doc.warnings.contains(unparsed)) {
    context.state(unparsed);
    yield context.finding(
      doc,
      FindingKind.markdownUnparsed,
      line: 1,
      message:
          'the markdown parser failed on this doc; its links are not checked',
    );
  }
  if (doc.isTyped) {
    final values = _docRefValuesOf(context, doc);
    yield* _unresolvedDocRefs(context, doc, values);
    yield* _repeatedDocRefs(context, doc, values);
    yield* _selfDocRefs(context, doc, values);
  }
  yield* _unresolvedNames(context, doc);
  yield* _unresolvedLinks(context, doc);
  yield* _missingAnchors(context, doc);
  yield* _selfLinks(context, doc);
  yield* _malformedLinks(context, doc);
  yield* _missingFileLinks(context, doc);
}

/// What names a doc to a doc-name mention (RULE-11), and the top-level
/// features: one read per index, since an index is one read snapshot.
typedef _NameSets = ({Set<String> names, Set<String> topLevelFeatures});

final _nameSetsOf = Expando<_NameSets>();

_NameSets _nameSets(DocIndex index) => _nameSetsOf[index] ??= (
  names: {
    for (final doc in index.docs) ...[
      doc.name,
      if (doc.docTypeId != null) '${doc.docTypeId}:${doc.name}',
    ],
  },
  topLevelFeatures: {
    for (final doc in index.docs)
      if (doc.docTypeId == featureType && !doc.name.contains('/')) doc.name,
  },
);

/// Yields a finding per doc-name mention of [doc] that names no doc while the
/// first slug of its Name names a top-level feature (RULE-11); any other
/// unresolved mention is plain text.
///
/// The mention's section key is never read.
Iterable<Finding> _unresolvedNames(CheckContext context, IndexedDoc doc) sync* {
  final sets = _nameSets(context.index);
  for (final mention in context.contentOf(doc).lineFacts.nameMentions) {
    final address = mention.address;
    if (sets.names.contains(address.docPart)) continue;
    if (!sets.topLevelFeatures.contains(address.body.split('/').first)) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.docNameUnresolved,
      line: mention.line,
      message: 'doc name ${mention.text} names no doc',
      keys: {'name': mention.text},
    );
  }
}

/// Returns the string values of every `doc_ref` field of [doc], in field
/// order, then source order.
List<_DocRefValue> _docRefValuesOf(CheckContext context, IndexedDoc doc) => [
  for (final field in context.typeOf(doc)?.fields ?? const <MergedField>[])
    if (field.type == FieldType.docRef)
      for (final (:value, :line, text: _)
          in context.linesOf(doc).entriesOf(field.id))
        if (value is String) (field: field, value: value, line: line),
];

/// Whether [value] of [field] names [target]: [target] carries it as its Name
/// and is of one of the field's doc types, any type when it names none.
bool _names(MergedField field, String value, IndexedDoc target) =>
    target.name == value &&
    (field.docTypes?.contains(target.docTypeId) ?? true);

/// Yields a finding per `doc_ref` value that names no doc.
Iterable<Finding> _unresolvedDocRefs(
  CheckContext context,
  IndexedDoc doc,
  List<_DocRefValue> values,
) sync* {
  for (final (:field, :value, :line) in values) {
    if (context.index.docs.any((other) => _names(field, value, other))) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.docRefUnresolved,
      line: line,
      message: '${field.id} value $value names no doc',
      keys: {'field': field.id, 'value': value},
    );
  }
}

/// Yields a finding per `doc_ref` value its field already holds above it.
Iterable<Finding> _repeatedDocRefs(
  CheckContext context,
  IndexedDoc doc,
  List<_DocRefValue> values,
) sync* {
  final seen = <(String, String)>{};
  for (final (:field, :value, :line) in values) {
    if (seen.add((field.id, value))) continue;
    yield context.finding(
      doc,
      FindingKind.docRefDuplicate,
      line: line,
      message: '${field.id} holds $value a second time',
      keys: {'field': field.id, 'value': value},
    );
  }
}

/// Yields a finding per `doc_ref` value that names [doc] itself.
Iterable<Finding> _selfDocRefs(
  CheckContext context,
  IndexedDoc doc,
  List<_DocRefValue> values,
) sync* {
  for (final (:field, :value, :line) in values) {
    if (!_names(field, value, doc)) continue;
    yield context.finding(
      doc,
      FindingKind.docRefSelf,
      line: line,
      message: '${field.id} value $value names the doc that holds it',
      keys: {'field': field.id, 'value': value},
    );
  }
}

/// Yields a finding per non-empty `#anchor` of a doc link or a self link of
/// [doc] that is no anchor of its target (RULE-13).
///
/// An empty anchor names the target's top, so it always resolves. A target
/// whose anchor set is unknown is not checked: unknown is never empty.
Iterable<Finding> _missingAnchors(CheckContext context, IndexedDoc doc) sync* {
  final facts = context.contentOf(doc).lineFacts;
  for (final place in [...facts.links, ...facts.selfLinks]) {
    final anchor = place.anchor;
    if (anchor == null || anchor.isEmpty) continue;
    final target = context.index.at(place.target);
    if (target == null) continue;
    final anchors = context.contentOf(target).lineFacts.anchors;
    if (anchors == null || anchors.holds(anchor)) continue;
    yield context.finding(
      doc,
      FindingKind.linkAnchorMissing,
      line: place.line,
      message:
          'link target ${place.shown} names anchor $anchor, which '
          '${place.target} does not hold',
      keys: {'target': place.shown, 'anchor': anchor},
    );
  }
}

/// Yields a finding per link of [doc] to [doc] itself with no `#`; a `#`
/// alone names the doc's top.
Iterable<Finding> _selfLinks(CheckContext context, IndexedDoc doc) sync* {
  for (final place in context.contentOf(doc).lineFacts.selfLinks) {
    if (place.anchor != null) continue;
    yield context.finding(
      doc,
      FindingKind.linkSelf,
      line: place.line,
      message:
          'link target ${place.shown.isEmpty ? _emptyTarget : place.shown} '
          'names the doc that holds it',
      keys: {'target': place.shown},
    );
  }
}

/// Yields a finding per link of [doc] whose target the reference grammar
/// cannot read (RULE-11), so no such link is skipped silently.
Iterable<Finding> _malformedLinks(CheckContext context, IndexedDoc doc) sync* {
  for (final place in context.contentOf(doc).lineFacts.unreadableLinks) {
    yield context.finding(
      doc,
      FindingKind.referenceMalformed,
      line: place.line,
      message:
          'link target ${place.shown} cannot be read: the WHATWG URL parser '
          'fails on it',
      keys: {'form': 'link_target', 'text': place.shown},
    );
  }
}

/// Yields a finding per link of [doc] whose target is indexed nowhere.
///
/// The index stores each link's line and destination as written, so no doc
/// text is read here.
Iterable<Finding> _unresolvedLinks(CheckContext context, IndexedDoc doc) sync* {
  for (final place in context.linesOf(doc).links) {
    if (context.index.at(place.target) != null) continue;
    yield context.finding(
      doc,
      FindingKind.linkUnresolved,
      line: place.line,
      message: 'link target ${place.shown} is no doc',
      keys: {'target': place.shown},
    );
  }
}

/// Yields a finding per file link of [doc] whose file or folder is missing
/// under the docs root.
///
/// A target that leaves the docs root is checked on disk the same way; the
/// message names it from the project root.
Iterable<Finding> _missingFileLinks(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final root = context.docsRoot.path;
  final separator = Platform.pathSeparator;
  for (final place in context.linesOf(doc).fileLinks) {
    final onDisk = [
      if (root.endsWith(separator))
        root.substring(0, root.length - 1)
      else
        root,
      ...place.target.split('/'),
    ].join(separator);
    if (FileSystemEntity.typeSync(onDisk) != FileSystemEntityType.notFound) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.linkTargetMissing,
      line: place.line,
      message:
          'link target ${place.shown} is missing at '
          '${_projectPathOf(place.target)}',
      keys: {'target': place.shown, 'path': _projectPathOf(place.target)},
    );
  }
}

/// Returns [target], a path under the docs root, as a path from the project
/// root: `docs/<target>` with each `..` folded lexically, so `docs/../../x`
/// is `../x`.
String _projectPathOf(String target) {
  final parts = <String>[docsFolderName];
  for (final segment in target.split('/')) {
    if (segment != '..') {
      parts.add(segment);
    } else if (parts.isEmpty || parts.last == '..') {
      parts.add('..');
    } else {
      parts.removeLast();
    }
  }
  return parts.join('/');
}
