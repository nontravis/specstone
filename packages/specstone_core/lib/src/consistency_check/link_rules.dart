import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/feature_pattern_rules.dart'
    show isSkipSpan, skipLinesOf;
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/consistency_check/outside_docs.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show acceptanceSectionId, readDocAddress;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/doc_mentions.dart'
    show pathsWrittenIn;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show SectionTarget, anchorTargetOf, classifyLink;
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/models/cited_section.dart';
import 'package:specstone_core/src/index_query/models/link_cite.dart';
import 'package:specstone_core/src/index_query/models/link_place.dart';
import 'package:specstone_core/src/index_query/models/written_path.dart';
import 'package:specstone_core/src/portable_path.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// How a `link_self` message shows an empty link target, `[x]()`.
const _emptyTarget = '(empty)';

/// One string `doc_ref` value of a doc, with its field and its file line.
final class _DocRefValue {
  const new({required this.field, required this.value, required this.line});

  final MergedField field;
  final String value;
  final int line;
}

/// Returns the link findings of [doc]'s `doc_ref` values and
/// links.
///
/// A typed doc is checked for both, an untyped doc of a checked folder for
/// links only. A doc the markdown parser failed on gets `markdown_unparsed`,
/// stating the index warning, since its links go unchecked. With two
/// or more targets, a shared doc's reference to a per-target doc gets
/// `per_target_reference`.
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
  final values = _docRefValuesOf(context, doc);
  if (doc.isTyped) {
    yield* _unresolvedDocRefs(context, doc, values);
    yield* _repeatedDocRefs(context, doc, values);
    yield* _selfDocRefs(context, doc, values);
  }
  yield* _unresolvedNames(context, doc);
  yield* _unresolvedLinks(context, doc);
  yield* _missingAnchors(context, doc);
  yield* _missingItems(context, doc);
  yield* _staleLinkTexts(context, doc);
  yield* _selfLinks(context, doc);
  yield* _missingFileLinks(context, doc);
  yield* _outsideLinks(context, doc);
  if (context.index.hasTwins && doc.target == null) {
    yield* _perTargetReferences(context, doc, values);
  }
}

/// Returns the docs of [named] that [from] reaches by a Name.
///
/// With two or more targets a per-target doc reaches its own target's docs
/// and the shared docs alone.
List<IndexedDoc> _reachable(
  CheckContext context,
  IndexedDoc from,
  List<IndexedDoc> named,
) {
  final own = from.target;
  if (own == null || !context.index.hasTwins) return named;
  return [
    for (final doc in named)
      if (doc.inTarget(own)) doc,
  ];
}

/// The docs a doc-name mention can name, by Name and by `<doc type>:<Name>`,
/// and the top-level features: one read per index, since an index is one read
/// snapshot.
final class _NameSets {
  const new({required this.docsNamed, required this.topLevelFeatures});

  final Map<String, List<IndexedDoc>> docsNamed;
  final Set<String> topLevelFeatures;
}

final _nameSetsOf = Expando<_NameSets>();

_NameSets _nameSets(DocIndex index) =>
    _nameSetsOf[index] ??= _readNameSets(index);

_NameSets _readNameSets(DocIndex index) {
  final docsNamed = <String, List<IndexedDoc>>{};
  for (final doc in index.docs) {
    (docsNamed[doc.name] ??= []).add(doc);
    if (doc.docTypeId != null) {
      (docsNamed['${doc.docTypeId}:${doc.name}'] ??= []).add(doc);
    }
  }
  return _NameSets(
    docsNamed: docsNamed,
    topLevelFeatures: {
      for (final doc in index.docs)
        if (doc.docTypeId == featureType && !doc.name.contains('/')) doc.name,
    },
  );
}

/// Yields a finding per doc-name mention of [doc] that names no doc it
/// reaches while the first slug of its Name names a top-level feature;
/// any other unresolved mention is plain text.
///
/// The mention's section key is never read.
Iterable<Finding> _unresolvedNames(CheckContext context, IndexedDoc doc) sync* {
  final sets = _nameSets(context.index);
  final skips = skipLinesOf(context, doc);
  for (final mention in context.contentOf(doc).lineFacts.nameMentions) {
    if (isSkipSpan(skips, mention.line, mention.text)) continue;
    final address = mention.address;
    final named = sets.docsNamed[address.docPart] ?? const <IndexedDoc>[];
    if (_reachable(context, doc, named).isNotEmpty) continue;
    if (!sets.topLevelFeatures.contains(address.body.split('/').first)) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.docNameUnresolved,
      line: mention.line,
      message: 'doc name ${mention.text} names no doc',
      keys: {'value': mention.text},
    );
  }
}

/// Returns the string values of every `doc_ref` field of [doc], in field
/// order, then source order.
List<_DocRefValue> _docRefValuesOf(CheckContext context, IndexedDoc doc) => [
  for (final field in context.typeOf(doc)?.fields ?? const <MergedField>[])
    if (field.type == FieldType.docRef)
      for (final YamlEntry(:value, :line)
          in context.linesOf(doc).entriesOf(field.id))
        if (value is String)
          _DocRefValue(field: field, value: value, line: line),
];

/// Whether [value] of [field] names [target]: [target] carries it as its Name
/// and is of one of the field's doc types, any type when it names none.
bool _names(MergedField field, String value, IndexedDoc target) =>
    target.name == value &&
    (field.docTypes?.contains(target.docTypeId) ?? true);

/// Returns the docs that [value] of [field] names.
List<IndexedDoc> _docsNamedBy(
  CheckContext context,
  MergedField field,
  String value,
) => [
  for (final other in context.index.docs)
    if (_names(field, value, other)) other,
];

/// Yields a finding per `doc_ref` value that names no doc [doc] reaches.
Iterable<Finding> _unresolvedDocRefs(
  CheckContext context,
  IndexedDoc doc,
  List<_DocRefValue> values,
) sync* {
  for (final _DocRefValue(:field, :value, :line) in values) {
    final named = _docsNamedBy(context, field, value);
    if (_reachable(context, doc, named).isNotEmpty) continue;
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
  for (final _DocRefValue(:field, :value, :line) in values) {
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
  for (final _DocRefValue(:field, :value, :line) in values) {
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
/// [doc] that is no anchor of its target.
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
    if (_isOutsideDocLink(context, place.target)) continue;
    final anchors = context.contentOf(target).lineFacts.anchors;
    if (anchors == null || anchors.holds(anchor)) continue;
    final targetPath = projectPathOfDocPath(place.target);
    yield context.finding(
      doc,
      FindingKind.linkAnchorMissing,
      line: place.line,
      message:
          'link target ${place.shown} names anchor $anchor, which '
          '$targetPath does not hold',
      keys: {'value': place.shown, 'anchor': anchor, 'targetPath': targetPath},
    );
  }
}

/// Yields a finding per item link of [doc] whose `##` section of its target
/// holds no item with the cited ID.
///
/// [classifyLink] alone judges each link. Only a link whose anchor resolves
/// to a `##` section can be an item link, so a missing anchor and an unknown
/// anchor set give no finding here. The items are the stored ItemFacts, so
/// no doc text is read.
Iterable<Finding> _missingItems(CheckContext context, IndexedDoc doc) sync* {
  final facts = context.contentOf(doc).lineFacts;
  for (final link in facts.linkTexts) {
    final anchor = link.anchor;
    final target = context.index.at(link.target);
    if (anchor == null || anchor.isEmpty || target == null) continue;
    if (_isOutsideDocLink(context, link.target)) continue;
    final content = context.contentOf(target);
    final anchorTarget = anchorTargetOf(content.lineFacts, anchor);
    if (anchorTarget is! SectionTarget) continue;
    final at = anchorTarget.sectionIndex;
    if (at >= content.sections.length) continue;
    final template = context.templateSectionAt(target, at);
    final cite = classifyLink(
      link,
      target: anchorTarget,
      sectionAt: (_) => CitedSection(
        key: template?.id ?? content.sections[at].key,
        prefixId: template?.prefixId,
        isAcceptanceCriteria: template?.id == acceptanceSectionId,
      ),
    );
    if (cite is! ItemCite) continue;
    if (content.itemFacts.sectionItems[at].any(
      (item) => item.id == cite.itemId,
    )) {
      continue;
    }
    final targetPath = projectPathOfDocPath(target.docPath);
    yield context.finding(
      doc,
      FindingKind.linkItemMissing,
      line: link.line,
      message:
          'link target ${link.shown} names item ${link.text}, which section '
          '${cite.sectionKey} of $targetPath does not hold',
      keys: {
        'value': link.shown,
        'item': link.text,
        'section': cite.sectionKey,
        'targetPath': targetPath,
      },
    );
  }
}

/// Yields a finding per link of [doc] whose typed text reads as an address
/// that differs from the address of the doc its target resolves to, or that
/// names a doc type the merged set does not define.
///
/// A bare text, of any slug count, takes none (D9). A typed text of the
/// target's own type passes with the target's Name or its last slug, the form
/// `rename` writes. The fix is the target's `<doc type>:<Name>`, any
/// `#<section key>` kept. A link that resolves to no doc, that leaves the docs,
/// or whose target is untyped, so has no address, gives none here.
Iterable<Finding> _staleLinkTexts(CheckContext context, IndexedDoc doc) sync* {
  final facts = context.contentOf(doc).lineFacts;
  for (final link in facts.addressLinkTexts) {
    final target = context.index.at(link.target);
    final targetType = target?.docTypeId;
    if (target == null || targetType == null) continue;
    if (_isOutsideDocLink(context, link.target)) continue;
    final address = readDocAddress(link.text);
    final typeId = address.typeId;
    if (typeId == null) continue;
    final isOwnName =
        address.body == target.name ||
        address.body == target.name.split('/').last;
    if (typeId == targetType && isOwnName) continue;
    final targetAddress = '$targetType:${target.name}';
    final key = address.sectionKey;
    final fix = key == null ? targetAddress : '$targetAddress#$key';
    yield context.finding(
      doc,
      FindingKind.linkTextStale,
      line: link.line,
      message:
          'link text ${link.text} names another address than the doc it '
          'links; write it as $fix',
      keys: {'value': link.text, 'fix': fix},
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
      keys: {'value': place.shown},
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
    if (_isOutsideDocLink(context, place.target)) continue;
    yield context.finding(
      doc,
      FindingKind.linkUnresolved,
      line: place.line,
      message: 'link target ${place.shown} is no doc',
      keys: {'value': place.shown},
    );
  }
}

/// Yields a finding per file link of [doc] whose file or folder is missing
/// under the root [doc] is read from: the docs root, or the project root for
/// a record.
///
/// A docs target that leaves the docs root is checked on disk the same way;
/// the message names it from the project root.
Iterable<Finding> _missingFileLinks(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final root = rootOfDocPath(
    doc.docPath,
    docsRoot: context.docsRoot,
    projectRoot: context.projectRoot,
  ).path;
  final separator = Platform.pathSeparator;
  final base = isRecordsDocPath(doc.docPath) ? '' : docsFolderName;
  for (final place in context.linesOf(doc).fileLinks) {
    if (_isOutsideFileLink(context, doc, place.target)) continue;
    final names = place.target.split('/');
    final onDisk = [
      if (root.endsWith(separator))
        root.substring(0, root.length - 1)
      else
        root,
      ...names,
    ].join(separator);
    if (isPortablePath(place.target) &&
        FileSystemEntity.typeSync(onDisk) != FileSystemEntityType.notFound) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.linkTargetMissing,
      line: place.line,
      message:
          'link target ${place.shown} is missing at '
          '${_projectPathOf(base, place.target)}',
      keys: {
        'value': place.shown,
        'targetPath': _projectPathOf(base, place.target),
      },
    );
  }
}

bool _isOutsideDocLink(CheckContext context, String target) =>
    outsideDocsPathOf(context, projectPathOfDocPath(target)) != null;

bool _isOutsideFileLink(CheckContext context, IndexedDoc doc, String target) =>
    outsideDocsPathOf(context, projectFilePathOf(target, doc.docPath)) != null;

/// Yields a finding per link of [doc] to a project file outside the checked
/// folders, whether the file exists or not.
///
/// The link's place alone decides, never a folder name. A link this reports
/// gets none of the findings that resolve it.
Iterable<Finding> _outsideLinks(CheckContext context, IndexedDoc doc) sync* {
  final lines = context.linesOf(doc);
  for (final place in lines.links) {
    yield* _outsideFinding(
      context,
      doc,
      place,
      projectPathOfDocPath(place.target),
    );
  }
  for (final place in lines.fileLinks) {
    yield* _outsideFinding(
      context,
      doc,
      place,
      projectFilePathOf(place.target, doc.docPath),
    );
  }
}

Iterable<Finding> _outsideFinding(
  CheckContext context,
  IndexedDoc doc,
  LinkPlace place,
  String projectPath,
) sync* {
  final path = outsideDocsPathOf(context, projectPath);
  if (path == null) return;
  yield context.finding(
    doc,
    FindingKind.linkOutsideDocs,
    line: place.line,
    message:
        'links $path, outside the docs; move the file into the docs or '
        'drop the link',
    keys: {'value': place.shown, 'targetPath': path},
  );
}

/// Returns [target], a path under [base], the folder of the doc's root (`''`
/// for a record, read from the project root), as a path from the project
/// root: `<base>/<target>` with each `..` folded lexically, so `docs/../../x`
/// is `../x`.
String _projectPathOf(String base, String target) {
  final parts = <String>[if (base.isNotEmpty) base];
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

/// Yields a finding per reference of the shared [doc] to a per-target doc: a
/// `doc_ref` value, a doc-name mention, a `.md` link, or a path in text.
Iterable<Finding> _perTargetReferences(
  CheckContext context,
  IndexedDoc doc,
  List<_DocRefValue> values,
) sync* {
  final sets = _nameSets(context.index);
  final facts = context.contentOf(doc).lineFacts;
  for (final _DocRefValue(:field, :value, :line) in values) {
    final named = _docsNamedBy(context, field, value);
    yield* _perTargetFinding(context, doc, named, line, value);
  }
  for (final mention in facts.nameMentions) {
    final named = sets.docsNamed[mention.address.docPart] ?? const [];
    yield* _perTargetFinding(context, doc, named, mention.line, mention.text);
  }
  for (final place in facts.links) {
    final named = [?context.index.at(place.target)];
    yield* _perTargetFinding(context, doc, named, place.line, place.shown);
  }
  for (final WrittenPath(:line, :written, :named) in pathsWrittenIn(
    context.index,
    doc,
  )) {
    yield* _perTargetFinding(context, doc, [named], line, written);
  }
}

/// Yields the `per_target_reference` finding of the shared [doc] for the
/// reference [written] at [line] when every doc of [named] is per-target.
///
/// One comparison of the two docs' targets covers every reference kind.
Iterable<Finding> _perTargetFinding(
  CheckContext context,
  IndexedDoc doc,
  List<IndexedDoc> named,
  int line,
  String written,
) sync* {
  if (named.isEmpty || named.any((target) => target.target == null)) return;
  final held = {for (final target in named) target.target};
  final targets = [
    for (final name in context.index.targetNames)
      if (held.contains(name)) name,
  ];
  yield context.finding(
    doc,
    FindingKind.perTargetReference,
    line: line,
    message: '$written names a per-target doc of ${targets.join(', ')}',
    keys: {'value': written, 'targets': targets},
  );
}
