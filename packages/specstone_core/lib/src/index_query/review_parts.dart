import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show tableCellRanges;
import 'package:specstone_core/src/doc_model/sentences.dart' show sentencesOf;
import 'package:specstone_core/src/document_writing/approval_view.dart';
import 'package:specstone_core/src/document_writing/models/changed_unit.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/feature_pattern_parts.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:specstone_core/src/index_query/models/cited_place.dart';
import 'package:specstone_core/src/index_query/models/cited_section.dart';
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/index_query/read_answer.dart'
    show nameWithType;
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/templates/feature_pattern.dart'
    show FeaturePatternBody;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Result

/// What a review part holds.
enum ReviewPartKind {
  /// An item, `###` block, or section holding a dropped or new sentence, whole
  /// in its new text with its dropped sentences under it.
  changedUnit,

  /// An item, `###` block, or section the draft removes, with its dropped
  /// sentences.
  removedUnit,

  /// A target with no approved copy, or that is no draft: the doc whole.
  wholeTarget,

  /// A part that links a changed or removed unit, its doc, or its section.
  citer,

  /// A section that sums up a feature a target touches.
  summarySection,

  /// A feature pattern part of the lowest feature holding a target, or of a
  /// feature under it; its doc is the doc that lists the pattern.
  pattern,
}

/// One part of a review, ready to print.
final class ReviewPart {
  const new({
    required this.kind,
    required this.doc,
    required this.sectionKey,
    required this.itemId,
    required this.cites,
    required this.text,
    this.isBlock = false,
    this.featurePattern,
  });

  final ReviewPartKind kind;
  final IndexedDoc doc;

  /// The id of the feature pattern a [ReviewPartKind.pattern] part prints;
  /// null for any other kind.
  final String? featurePattern;

  /// The key of the section the part sits in; null for a whole target.
  final String? sectionKey;

  /// The ID of the item, or the anchor of the `###` block, the part is; null
  /// for a section or a doc.
  final String? itemId;

  /// Whether [itemId] is the anchor of a `###` block rather than an item ID.
  final bool isBlock;

  /// The units a [ReviewPartKind.citer] cites, each as `<name> (<doc type>)`
  /// then the unit's item ID or block anchor, else `#<section key>`; empty for
  /// any other kind.
  final List<String> cites;

  /// The part's text, as written. A changed unit holds its dropped sentences
  /// under it; a removed unit holds them alone.
  final String text;
}

/// The parts of a review in print order, and the docs its refs file holds.
final class ReviewParts {
  const new({required this.parts, required this.refsDocs});

  /// The changed units, removed units, and whole targets, then the citers,
  /// then the summary sections, then the feature pattern parts.
  final List<ReviewPart> parts;

  /// The addresses of the docs whose design bundle the refs file holds.
  final List<String> refsDocs;
}

// MARK: - Pick

/// Returns the parts a review of [targets] reads and the docs of its refs file.
///
/// [drafts] are the views `draftViewsOf` gives for the same [targets] and
/// [codeTarget]; a draft that is no target prints nothing. [codeTarget] keeps
/// the targets, citers, and summary docs to that code target and the shared
/// docs. Each part is read from the index's stored text and its sections,
/// never from a file.
/// Throws `IndexFault` `doc_not_found` for a target no doc carries.
ReviewParts pickReviewParts(
  DocIndex index,
  List<String> targets,
  List<DraftView> drafts, {
  String? codeTarget,
}) {
  final docs = _targetDocsOf(index, targets, codeTarget);
  final views = _DocViews(index);
  final draftAt = {for (final draft in drafts) draft.docPath: draft};
  final picks = [
    for (final doc in docs) _pickFrom(views, doc, draftAt[doc.docPath]),
  ];
  final printed = [for (final pick in picks) ...pick.parts];
  final wholePaths = {
    for (final pick in picks)
      if (pick.isWhole) pick.doc.docPath,
  };
  final spans = <String, List<LineRange>>{
    for (final pick in picks) pick.doc.docPath: pick.printedSpans,
  };
  final citers = _citersOf(
    index,
    views,
    [for (final pick in picks) ...pick.cited],
    wholePaths: wholePaths,
    spans: spans,
    codeTarget: codeTarget,
  );
  final refs = _refsOf(index, docs);
  final refsDocs = [for (final doc in refs) index.addressOf(doc)];
  return ReviewParts(
    parts: [
      ...printed,
      ...citers,
      ..._summariesOf(
        index,
        views,
        docs,
        [...printed, ...citers],
        wholePaths,
        codeTarget: codeTarget,
      ),
      ..._patternsOf(index, docs, refs),
    ],
    refsDocs: refsDocs,
  );
}

List<IndexedDoc> _targetDocsOf(
  DocIndex index,
  List<String> targets,
  String? codeTarget,
) {
  final seen = <String>{};
  return [
    for (final target in targets)
      for (final doc in index.resolve(target, codeTarget: codeTarget))
        if (seen.add(doc.docPath)) doc,
  ];
}

// MARK: - Changed units

/// What one target contributes: its printed parts, the units citers are found
/// for, and where its printed parts lie in its stored text.
final class _TargetPick {
  const new({
    required this.doc,
    required this.parts,
    required this.cited,
    required this.printedSpans,
    required this.isWhole,
  });

  final IndexedDoc doc;
  final List<ReviewPart> parts;
  final List<_CitedUnit> cited;
  final List<LineRange> printedSpans;

  /// Whether the doc prints whole.
  final bool isWhole;
}

_TargetPick _pickFrom(_DocViews views, IndexedDoc doc, DraftView? draft) {
  final now = views.of(doc);
  if (draft == null) {
    return _TargetPick(
      doc: doc,
      parts: [_wholePartOf(now)],
      cited: const [],
      printedSpans: const [],
      isWhole: true,
    );
  }
  final oldText = draft.comparison.oldText;
  final was = oldText == null ? null : _oldViewOf(draft, oldText);
  final changes = _changesOf(draft, now, was);
  if (was == null) {
    return _TargetPick(
      doc: doc,
      parts: [_wholePartOf(now)],
      cited: [for (final hit in changes.changed) _citedOf(now, hit.unit)],
      printedSpans: const [],
      isWhole: true,
    );
  }
  final printed = _outermostOf(changes.changed);
  return _TargetPick(
    doc: doc,
    parts: [
      for (final hit in printed) _changedPartOf(now, hit),
      for (final hit in changes.removed) _removedPartOf(now, hit),
    ],
    cited: [
      for (final hit in [...changes.changed, ...changes.removed])
        _citedOf(now, hit.unit),
    ],
    printedSpans: [for (final hit in printed) hit.unit.span],
    isWhole: false,
  );
}

ReviewPart _wholePartOf(_DocView view) => ReviewPart(
  kind: ReviewPartKind.wholeTarget,
  doc: view.doc,
  sectionKey: null,
  itemId: null,
  cites: const [],
  text: toLf(view.content.text),
);

ReviewPart _changedPartOf(_DocView view, _Hit hit) {
  final unit = hit.unit;
  return ReviewPart(
    kind: ReviewPartKind.changedUnit,
    doc: view.doc,
    sectionKey: unit.sectionKey,
    itemId: unit.itemId,
    isBlock: unit.kind == _UnitKind.block,
    cites: const [],
    text: [
      view.textOf(unit.span),
      if (hit.dropped.isNotEmpty) _droppedListOf(hit.dropped),
    ].join('\n\n'),
  );
}

ReviewPart _removedPartOf(_DocView view, _Hit hit) => ReviewPart(
  kind: ReviewPartKind.removedUnit,
  doc: view.doc,
  sectionKey: hit.unit.sectionKey,
  itemId: hit.unit.itemId,
  isBlock: hit.unit.kind == _UnitKind.block,
  cites: const [],
  text: hit.dropped.isEmpty ? '' : _droppedListOf(hit.dropped),
);

String _droppedListOf(List<String> sentences) =>
    'Dropped sentences:\n${[for (final s in sentences) '- $s'].join('\n')}';

/// The units of a draft that hold a dropped or new sentence, or that the dry
/// run's changes name.
final class _Changes {
  const new({required this.changed, required this.removed});

  /// Units still in the new text, in no fixed order.
  final List<_Hit> changed;

  /// Units only the approved copy holds.
  final List<_Hit> removed;
}

/// A unit and the sentences it dropped.
final class _Hit {
  new(this.unit);

  final _Unit unit;
  final dropped = <String>[];
}

/// Returns the units of [draft] holding a sentence it dropped or added.
///
/// The sentences are [draft]'s own, those the approve dry run gives. A dropped
/// sentence belongs to the unit that held it in the approved copy [was]; a
/// unit the new text lacks is removed. [was] is null for a draft with no
/// approved copy.
_Changes _changesOf(DraftView draft, _DocView now, _DocView? was) {
  final changed = <String, _Hit>{};
  final removed = <String, _Hit>{};
  for (final sentence in draft.sentences.added) {
    for (final unit in _innermostHolding(now.units, sentence)) {
      changed.putIfAbsent(unit.id, () => _Hit(unit));
    }
  }
  if (was != null) {
    final current = {for (final unit in now.units) unit.id: unit};
    for (final sentence in draft.sentences.dropped) {
      for (final old in _innermostHolding(was.units, sentence)) {
        final kept = current[old.id];
        final hit = kept == null
            ? removed.putIfAbsent(old.id, () => _Hit(old))
            : changed.putIfAbsent(kept.id, () => _Hit(kept));
        hit.dropped.add(sentence);
      }
    }
    _addNamedSections(draft, now, was, changed, removed);
  }
  return _Changes(
    changed: [for (final hit in changed.values.toList()..sort(_byPlace)) hit],
    removed: removed.values.toList(),
  );
}

/// Adds each section the dry run's changes name that no changed or removed
/// unit sits in yet.
void _addNamedSections(
  DraftView draft,
  _DocView now,
  _DocView was,
  Map<String, _Hit> changed,
  Map<String, _Hit> removed,
) {
  for (final ChangedUnit(:kind, :name, :side) in draft.comparison.units) {
    if (kind != UnitKind.section) continue;
    if (side == UnitSide.removed) {
      final old = was.sectionNamed(name);
      if (old != null && now.sectionNamed(name) == null) {
        removed.putIfAbsent(old.id, () => _Hit(old));
      }
      continue;
    }
    final unit = now.sectionNamed(name);
    final isHeld =
        unit != null &&
        [
          ...changed.values,
          ...removed.values,
        ].any((hit) => hit.unit.sectionKey == unit.sectionKey);
    if (unit != null && !isHeld) changed[unit.id] = _Hit(unit);
  }
}

/// Returns the units of [units] that hold [sentence] and hold no other unit
/// that holds it.
List<_Unit> _innermostHolding(List<_Unit> units, String sentence) {
  final holders = [
    for (final unit in units)
      if (unit.sentences.contains(sentence)) unit,
  ];
  return [
    for (final unit in holders)
      if (!holders.any((other) => other.isInside(unit))) unit,
  ];
}

/// Returns [hits] less each that lies inside another, whose dropped sentences
/// move to the outer one; in file order.
List<_Hit> _outermostOf(List<_Hit> hits) {
  final kept = <_Hit>[];
  for (final hit in hits) {
    final outer = kept.where((other) => hit.unit.isInside(other.unit));
    if (outer.isEmpty) {
      kept.add(hit);
    } else {
      outer.first.dropped.addAll(hit.dropped);
    }
  }
  return kept;
}

/// Orders hits by file line, an outer unit before what it holds.
int _byPlace(_Hit a, _Hit b) {
  final byFirst = a.unit.span.first.compareTo(b.unit.span.first);
  if (byFirst != 0) return byFirst;
  final byLast = b.unit.span.last.compareTo(a.unit.span.last);
  return byLast != 0 ? byLast : b.unit.kind.index.compareTo(a.unit.kind.index);
}

// MARK: - Citers

/// A changed or removed unit, as the cited-by index names it.
final class _CitedUnit {
  const new({required this.doc, required this.unit});

  final IndexedDoc doc;
  final _Unit unit;

  /// The unit as a citer's naming line gives it.
  String get label =>
      '${nameWithType(doc)} ${unit.itemId ?? '#${unit.sectionKey}'}';

  /// The places a link names this unit by: itself, its section, its doc.
  List<CitedPlace> get places => [
    if (unit.itemId case final id?)
      CitedPlace(docPath: doc.docPath, kind: CitedKind.item, key: id),
    CitedPlace(
      docPath: doc.docPath,
      kind: CitedKind.section,
      key: unit.sectionKey,
    ),
    CitedPlace(docPath: doc.docPath, kind: CitedKind.doc, key: null),
  ];
}

_CitedUnit _citedOf(_DocView view, _Unit unit) =>
    _CitedUnit(doc: view.doc, unit: unit);

/// A part that cites one or more units, and the labels of those units.
final class _Citer {
  new(this.by);

  final CitedBy by;
  final cites = <String>[];
}

/// Returns each part that links one of [units], once, naming each unit it
/// cites, in the order the units give them.
///
/// A citer inside a doc printed whole, inside a part already printed in its
/// doc ([spans]), or in a doc of another code target than [codeTarget], is
/// left out.
List<ReviewPart> _citersOf(
  DocIndex index,
  _DocViews views,
  List<_CitedUnit> units, {
  required Set<String> wholePaths,
  required Map<String, List<LineRange>> spans,
  required String? codeTarget,
}) {
  final citedBy = citedByIndex(index, inline: false);
  final citers = <String, _Citer>{};
  for (final unit in units) {
    for (final place in unit.places) {
      for (final by in citedBy[place] ?? const <CitedBy>[]) {
        if (wholePaths.contains(by.docPath)) continue;
        final key = '${by.docPath}\u0000${by.bySection}\u0000${by.byItem}';
        final citer = citers.putIfAbsent(key, () => _Citer(by));
        if (!citer.cites.contains(unit.label)) citer.cites.add(unit.label);
      }
    }
  }
  return [
    for (final citer in citers.values)
      ?_citerPartOf(index, views, citer, spans, codeTarget),
  ];
}

ReviewPart? _citerPartOf(
  DocIndex index,
  _DocViews views,
  _Citer citer,
  Map<String, List<LineRange>> spans,
  String? codeTarget,
) {
  final CitedBy(:docPath, :bySection, :byItem) = citer.by;
  final doc = index.at(docPath);
  if (doc == null || !doc.inTarget(codeTarget)) return null;
  final view = views.of(doc);
  final span = view.spanOfPlace(bySection, byItem);
  if (span == null) return null;
  final isPrinted = (spans[docPath] ?? const []).any(
    (printed) => printed.first <= span.first && span.last <= printed.last,
  );
  if (isPrinted) return null;
  return ReviewPart(
    kind: ReviewPartKind.citer,
    doc: doc,
    sectionKey: bySection,
    itemId: byItem,
    cites: citer.cites,
    text: view.textOf(span),
  );
}

// MARK: - Summary sections

/// The sections that sum up a feature, by doc type: the feature's own, and
/// those of each spec doc under it.
const Map<String, List<String>> _summaryKeysByType = {
  featureType: ['benefit_hypothesis', 'flow', 'out_of_scope'],
  'architecture': ['components'],
  'api': ['fr_trace'],
};

/// Returns the summary sections of each feature that holds one of [targets],
/// and of each feature above it, outermost feature first, each once.
///
/// A doc already printed whole, a section of [printed] already printed whole
/// as a changed unit or a citer, or a doc of another code target than
/// [codeTarget], adds none.
List<ReviewPart> _summariesOf(
  DocIndex index,
  _DocViews views,
  List<IndexedDoc> targets,
  List<ReviewPart> printed,
  Set<String> wholePaths, {
  required String? codeTarget,
}) {
  final printedSections = {
    for (final part in printed)
      if (part.itemId == null && part.sectionKey != null)
        '${part.doc.docPath}#${part.sectionKey}',
  };
  final features = <String, IndexedDoc>{};
  for (final target in targets) {
    for (final doc in index.chainOf(target).reversed) {
      if (doc.docTypeId == featureType) {
        features.putIfAbsent(doc.docPath, () => doc);
      }
    }
  }
  final seen = <String>{};
  return [
    for (final feature in features.values)
      for (final doc in [
        feature,
        ...index
            .childrenOf(feature)
            .where((c) => !index.isChainDoc(c) && c.inTarget(codeTarget)),
      ])
        if (!wholePaths.contains(doc.docPath))
          for (final key
              in _summaryKeysByType[doc.docTypeId] ?? const <String>[])
            if (!printedSections.contains('${doc.docPath}#$key') &&
                seen.add('${doc.docPath}#$key'))
              ?_summaryPartOf(views.of(doc), key),
  ];
}

ReviewPart? _summaryPartOf(_DocView view, String sectionKey) {
  final span = view.spanOfPlace(sectionKey, null);
  if (span == null) return null;
  return ReviewPart(
    kind: ReviewPartKind.summarySection,
    doc: view.doc,
    sectionKey: sectionKey,
    itemId: null,
    cites: const [],
    text: view.textOf(span),
  );
}

// MARK: - Feature pattern parts

/// Returns the feature pattern parts of each doc from a target up to and with
/// the lowest feature holding its refs doc, among [refs]; an ancestor of that
/// feature lists none.
///
/// The listers are picked first and walked parents first, their top features
/// in tree order as a design bundle walks them, so a pattern or an item two
/// listers share prints once, at the first kept lister whatever the target
/// order, never at a dropped ancestor.
List<ReviewPart> _patternsOf(
  DocIndex index,
  List<IndexedDoc> targets,
  List<IndexedDoc> refs,
) {
  final topPaths = {
    for (final ref in refs) _lowestFeatureOf(index, ref).docPath,
  };
  final tops = [
    for (final doc in index.docs)
      if (topPaths.contains(doc.docPath)) doc,
  ];
  final listers = {
    for (final top in tops)
      for (final target in targets) ..._chainUpTo(index, target, top),
  };
  final seen = <String>{};
  final order = [
    for (final top in tops)
      for (final doc in index.subtreeOf(top))
        if (listers.contains(doc.docPath) && seen.add(doc.docPath)) doc,
  ];
  // A design bundle carries the lister set featurePatternParts reads.
  final bundle = Bundle(BundleMode.design)..patternListerPaths.addAll(listers);
  return [
    for (final part in featurePatternParts(index, bundle, order))
      ReviewPart(
        kind: ReviewPartKind.pattern,
        doc: part.lister,
        sectionKey: null,
        itemId: null,
        cites: const [],
        text: part.pattern.renderBody(part.items).trimRight(),
        featurePattern: part.pattern.id,
      ),
  ];
}

/// Returns [ref] when it is a feature, else the lowest feature above it, else
/// [ref].
IndexedDoc _lowestFeatureOf(DocIndex index, IndexedDoc ref) => index
    .chainOf(ref)
    .firstWhere((doc) => doc.docTypeId == featureType, orElse: () => ref);

/// Returns the DocPaths of [target] and of each doc above it up to and with
/// [top]; none when [top] does not hold [target].
List<String> _chainUpTo(DocIndex index, IndexedDoc target, IndexedDoc top) {
  final chain = index.chainOf(target);
  final at = chain.indexWhere((doc) => doc.docPath == top.docPath);
  return [for (final doc in chain.take(at + 1)) doc.docPath];
}

// MARK: - Refs docs

/// Returns each doc the refs file's design bundle starts from: per top feature
/// holding targets, the smallest doc whose subtree holds them; each target in
/// no feature's subtree.
List<IndexedDoc> _refsOf(DocIndex index, List<IndexedDoc> targets) {
  final groups = <String, List<List<IndexedDoc>>>{};
  for (final target in targets) {
    final chain = index.chainOf(target).reversed.toList();
    final top = chain.first;
    final key = top.docTypeId == featureType ? top.docPath : target.docPath;
    (groups[key] ??= []).add(chain);
  }
  return [for (final chains in groups.values) _smallestHolding(chains)];
}

/// Returns the deepest doc every one of [chains], each from its top doc down,
/// holds.
IndexedDoc _smallestHolding(List<List<IndexedDoc>> chains) {
  var shared = chains.first.first;
  for (var depth = 0; ; depth++) {
    final docs = {
      for (final chain in chains)
        if (depth < chain.length) chain[depth].docPath,
    };
    if (docs.length != 1 || chains.any((chain) => depth >= chain.length)) {
      return shared;
    }
    shared = chains.first[depth];
  }
}

// MARK: - Doc views

/// The stored view of each doc a review reads, built once.
final class _DocViews {
  new(this.index);

  final DocIndex index;
  final _byPath = <String, _DocView>{};

  _DocView of(IndexedDoc doc) => _byPath[doc.docPath] ??= _DocView(
    doc,
    index.contentOf(doc),
    index.typeOf(doc),
  );
}

/// Returns the approved copy [text] of [draft] as a doc view, read as the index
/// reads a file.
_DocView _oldViewOf(DraftView draft, String text) {
  final type = draft.mergedType;
  final parsed = parseIndexedDoc(
    docPath: draft.docPath,
    bytes: utf8.encode(text),
    match: type == null ? const NoDocType() : MatchedDocType(type),
  );
  return _DocView(parsed.doc, parsed.content, type);
}

/// The kind of a [_Unit], from the narrowest: an item holding an ID, a `###`
/// block, a `##` section or the lead.
enum _UnitKind { item, block, section }

/// The part of a doc a sentence belongs to.
final class _Unit {
  new({
    required this.kind,
    required this.sectionKey,
    required this.key,
    required this.span,
    required this.readSentences,
  });

  final _UnitKind kind;
  final String sectionKey;

  /// The item ID or the block anchor; null for a section.
  final String? key;
  final LineRange span;
  final Set<String> Function() readSentences;

  /// The unit's identity, the same in the approved copy and the draft.
  late final String id = '${kind.index}\u0000$sectionKey\u0000${key ?? ''}';

  late final Set<String> sentences = readSentences();

  String? get itemId => kind == _UnitKind.section ? null : key;

  /// Whether this unit lies inside [outer], a unit of the same doc.
  bool isInside(_Unit outer) {
    if (identical(this, outer)) return false;
    final contained =
        outer.span.first <= span.first && span.last <= outer.span.last;
    final isSameSpan =
        outer.span.first == span.first && outer.span.last == span.last;
    return contained && (!isSameSpan || kind.index < outer.kind.index);
  }
}

/// One doc as a review reads it: its stored text by line, its held sections,
/// and its units.
final class _DocView {
  new(this.doc, this.content, this.type)
    : held = citedSectionsOf(content, type);

  final IndexedDoc doc;
  final DocContent content;
  final MergedDocType? type;
  final List<CitedSection> held;

  late final List<String> _lines = toLf(content.text).split('\n');

  /// Returns the text of [span], its lines as written.
  String textOf(LineRange span) =>
      _lines.sublist(span.first - 1, span.last).join('\n');

  /// Returns the lines a section, the lead, or an item of a section holds:
  /// the item [itemId] of the section [sectionKey], else the section.
  LineRange? spanOfPlace(String sectionKey, String? itemId) {
    if (sectionKey == leadKey) return _leadSpan;
    final at = held.indexWhere((section) => section.key == sectionKey);
    if (at < 0) return null;
    if (itemId == null) return _sectionSpan(at);
    return _extentsAt(at)[itemId];
  }

  /// Returns the section unit headed [header], or null.
  _Unit? sectionNamed(String header) {
    for (final (at, section) in content.sections.indexed) {
      if (section.headerLine.trimLeft().substring(2).trim() == header.trim()) {
        return _sectionUnitAt(at);
      }
    }
    return null;
  }

  late final List<_Unit> units = _unitsOf();

  late final LineRange? _leadSpan = _leadSpanOf();

  final _extents = <int, Map<String, LineRange>>{};

  Map<String, LineRange> _extentsAt(int at) => _extents[at] ??= itemExtentsOf(
    sectionBodyLines(content.sections, content.lineFacts, at),
    prefixId: held[at].prefixId,
    isAcceptanceCriteria: held[at].isAcceptanceCriteria,
  );

  LineRange _sectionSpan(int at) {
    final starts = content.lineFacts.sectionLines;
    final next = at + 1 < starts.length ? starts[at + 1] - 1 : _lines.length;
    return LineRange(first: starts[at], last: _trimmedEnd(starts[at], next));
  }

  LineRange? _leadSpanOf() {
    final starts = content.lineFacts.sectionLines;
    final frontmatter = content.frontmatterText;
    final first = frontmatter == null
        ? 1
        : '\n'.allMatches(frontmatter).length + 1;
    final next = starts.isEmpty ? _lines.length : starts.first - 1;
    final last = _trimmedEnd(first, next);
    var from = first;
    while (from <= last && _lines[from - 1].trim().isEmpty) {
      from++;
    }
    return from > last ? null : LineRange(first: from, last: last);
  }

  /// Returns [last], moved up past blank lines, but not above [first].
  int _trimmedEnd(int first, int last) {
    var end = last;
    while (end > first && _lines[end - 1].trim().isEmpty) {
      end--;
    }
    return end;
  }

  _Unit _sectionUnitAt(int at) => _Unit(
    kind: _UnitKind.section,
    sectionKey: held[at].key,
    key: null,
    span: _sectionSpan(at),
    readSentences: () => _sentencesIn(_lines, _sectionSpan(at)),
  );

  List<_Unit> _unitsOf() {
    final lead = _leadSpan;
    return [
      if (lead != null)
        _Unit(
          kind: _UnitKind.section,
          sectionKey: leadKey,
          key: null,
          span: lead,
          readSentences: () => _sentencesIn(_lines, lead),
        ),
      for (var at = 0; at < held.length; at++) ..._unitsOfSection(at),
    ];
  }

  List<_Unit> _unitsOfSection(int at) {
    final span = _sectionSpan(at);
    final items = _extentsAt(at);
    final itemStarts = {for (final extent in items.values) extent.first};
    return [
      _sectionUnitAt(at),
      for (final MapEntry(:key, :value) in items.entries)
        _unitOf(_UnitKind.item, at, key, value),
      for (final _Heading(:anchor, :line) in _blocksIn(span))
        if (!itemStarts.contains(line))
          if (headingBlockExtentOf(
                sectionBodyLines(content.sections, content.lineFacts, at),
                line,
              )
              case final extent?)
            _unitOf(_UnitKind.block, at, anchor, extent),
    ];
  }

  _Unit _unitOf(_UnitKind kind, int at, String key, LineRange span) => _Unit(
    kind: kind,
    sectionKey: held[at].key,
    key: key,
    span: span,
    readSentences: () => _sentencesIn(_lines, span),
  );

  /// Returns the anchor and file line of each `###` heading inside [span].
  List<_Heading> _blocksIn(LineRange span) {
    final facts = content.lineFacts;
    final anchors = facts.anchors;
    final headingLines = facts.headingLines;
    if (anchors == null || headingLines == null) return const [];
    return [
      for (final (i, slug) in anchors.headingSlugs.indexed)
        if (i < headingLines.length &&
            anchors.headingLevels[i] == _blockLevel &&
            span.first < headingLines[i] &&
            headingLines[i] <= span.last)
          _Heading(anchor: slug, line: headingLines[i]),
    ];
  }
}

/// The level of the heading a `###` block opens.
const _blockLevel = 3;

/// A `###` heading: the anchor a link names it by, and its file line.
final class _Heading {
  const new({required this.anchor, required this.line});

  final String anchor;
  final int line;
}

/// Returns the sentences of the lines [span] holds, as the doc model reads a
/// whole doc.
///
/// A table row is read cell by cell, since a row alone is no table.
Set<String> _sentencesIn(List<String> lines, LineRange span) {
  final slice = lines.sublist(span.first - 1, span.last);
  if (slice.first.trimLeft().startsWith('|')) {
    return {
      for (final row in slice)
        for (final cell in tableCellRanges(row))
          ...sentencesOf(row.substring(cell.start, cell.end)),
    };
  }
  final indent = slice.first.length - slice.first.trimLeft().length;
  return sentencesOf(
    [
      for (final line in slice)
        if (line.length >= indent && line.substring(0, indent).trim().isEmpty)
          line.substring(indent)
        else
          line,
    ].join('\n'),
  ).toSet();
}
