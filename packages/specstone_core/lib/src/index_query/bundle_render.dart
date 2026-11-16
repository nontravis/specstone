import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_follow.dart';
import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/feature_pattern_parts.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/read_answer.dart';

String _summaryNextStep(BundleMode mode) =>
    'Read a summary doc whole with: '
    'specstone context <name> --for ${mode.wire}';

const _overBudgetNextStep =
    'narrow the target, or run it again with --out and no --budget';

const _overBudgetSummaryNextStep =
    'narrow the target, or run it again with --summary --out and no --budget';

/// What one entry of a bundle text is.
///
/// - [doc]: a picked, joined, or summary doc.
/// - [cited]: a part a link appended.
/// - [pattern]: a feature pattern part.
/// - [names]: a `==> names:` block of a top doc's chain children.
/// - [citedBy]: the cited-by lines of one item, block, section, or doc, a part
///   of its own in a split bundle.
enum BundleEntryKind { doc, cited, pattern, names, citedBy }

/// One doc or part a bundle text prints, with the lines it spans there,
/// counted from 1: its naming line `first` to its `last` line, and the
/// header line of each `##` section it prints whole. A cited part names
/// the `##` section that holds it and its item ID, when it has them, and so
/// does a cited-by part, except that a section's has its `sectionKey` alone
/// and a doc's neither. A feature pattern part's `doc` is the doc that
/// lists it and its `featurePattern` the pattern id; null for any other
/// entry. A names block's `doc` is its top doc.
typedef BundleEntry = ({
  IndexedDoc doc,
  BundleEntryKind kind,
  bool summary,
  String? sectionKey,
  String? itemId,
  String? featurePattern,
  int first,
  int last,
  List<({String key, int first})> sections,
});

/// One file's text of a bundle: the text, each doc and part it prints in
/// print order, and its est. token size as its closing line gives it.
typedef BundleText = ({String text, List<BundleEntry> entries, int tokens});

/// Returns the number of docs [entries] hold, as a bundle's closing line and
/// its `--out` header count them: no part is a doc.
int docCountOf(List<BundleEntry> entries) =>
    entries.where((entry) => entry.kind == BundleEntryKind.doc).length;

/// A `context` answer, with where each doc and part sits in its text.
final class ContextAnswer extends ReadAnswer {
  const new({
    required super.text,
    required super.json,
    super.warnings,
    super.exitStatus,
    required this.entries,
    required this.tokens,
    this.codeTarget,
    this.refs,
  });

  /// Each doc and part [text] prints, in print order; empty when it prints no
  /// doc text, as over budget.
  final List<BundleEntry> entries;

  /// The est. token size of [text], as its closing line gives it.
  final int tokens;

  /// The code target [text] names first, for a `--code` call in a project
  /// with two or more; null otherwise.
  final String? codeTarget;

  /// The refs file's text, entries, and size when the answer is split; null
  /// otherwise, when [text] holds the whole bundle.
  final BundleText? refs;

  /// The read-first file: [text] with its [entries] and [tokens].
  BundleText get readFirst => (text: text, entries: entries, tokens: tokens);
}

String _overBudgetLine(String listName, int tokens) =>
    '- $listName · $tokens tokens\n';

/// Returns the closing-list name of [doc], marked ` · summary` when [summary].
String _listName(IndexedDoc doc, bool summary) =>
    summary ? '${nameWithType(doc)} · summary' : nameWithType(doc);

/// Returns the closing-list name of [part],
/// `<name> (<doc type>) · cited <section key> [<ID>]`; a summary doc's is
/// marked ` · summary` before ` · cited`, a naming line's has no key, and
/// a path's is `<DocPath> · cited`.
String _partListName(AppendedPart part) =>
    '${part.pathOnly ? part.doc.docPath : _listName(part.doc, part.summary)}'
    ' · cited'
    '${part.sectionKey == null ? '' : ' ${part.sectionKey}'}'
    '${part.itemId == null ? '' : ' [${part.itemId}]'}';

/// Returns the block of [part]: its naming line, `<DocPath>#<section key>`
/// (`#<anchor>` for a `###` block that starts no item) with ` · item <ID>`
/// for an item, or `<DocPath> · summary` for a doc, then ` · cited`, then its
/// text; a path prints as `==> <DocPath> · cited <==` alone, and a naming-line
/// doc as `==> <name> (<doc type>) · <DocPath> · cited <==` alone.
String _partBlock(AppendedPart part) {
  final doc = part.doc;
  if (part.pathOnly) return '==> ${doc.docPath} · cited <==';
  if (part.nameOnly) {
    return '==> ${nameWithType(doc)} · ${doc.docPath} · cited <==';
  }
  final key = part.heading ?? part.sectionKey;
  final path = key == null ? doc.docPath : '${doc.docPath}#$key';
  final item = part.itemId == null ? '' : ' · item ${part.itemId}';
  final summary = part.summary ? ' · summary' : '';
  return '==> ${nameWithType(doc)} · $path$item$summary · cited <==\n'
      '${part.text}';
}

/// Returns the `citedBy` key of a doc object, an empty list when [items] holds
/// no line; none outside a design bundle, which has no [citedBy].
Map<String, Object> _citedByKey(List<CitedItem> items, CitedByIndex? citedBy) =>
    {if (citedBy != null) 'citedBy': citedByJson(items)};

/// Returns the JSON keys that mark [part], after its `text` or `tokens`.
Map<String, Object> _partKeys(AppendedPart part) => {
  if (part.summary) 'summary': true,
  'cited': true,
  'section': ?part.sectionKey,
  'heading': ?part.heading,
  'item': ?part.itemId,
};

/// Returns the closing line of a bundle text of [docs] docs and [tokens] est.
/// tokens, with its line end.
String closingLineOf(int docs, int tokens) =>
    '==> bundle: $docs docs, $tokens tokens <==\n';

/// Returns the header line that names the code target a `--code` path lies
/// in, or '' when there is none to name (one target).
String codeTargetLine(String? name) =>
    name == null ? '' : '==> code target: $name <==\n';

/// Renders [bundle]'s docs as one `context` answer.
///
/// The parts the bundle's links cite print after its docs. [label] is the
/// target as given, or the code path for `--code`; [byCode] prints it under the
/// JSON key `code` instead of `target`, with the picked `codeTarget` when the
/// project has two or more. A bundle larger than [budget] prints its sizes and
/// the next step instead of doc text, with exit status 1; an equal one prints
/// whole. The answer places each doc and part in its text, for `--out`'s index.
///
/// With [split], an `implement` or `design` bundle puts each part in one of
/// two texts: [ContextAnswer.text] holds the read-first part, and
/// [ContextAnswer.refs] the refs part, each with its own entries, closing
/// line, and list. A `design` bundle's cited-by lines then print as parts of
/// the refs text, never after their item. [split] changes no other output.
ContextAnswer answerContext(
  DocIndex index,
  Bundle bundle, {
  required String label,
  required bool byCode,
  int? budget,
  bool split = false,
}) {
  final splits = split && bundle.mode != BundleMode.query;
  final ordered = bundle.printOrder(index);
  final summaryOnly = bundle.summaryOnly;
  bool inSummary(IndexedDoc doc) => summaryOnly.contains(doc.docPath);
  final citedBy = bundle.mode == BundleMode.design
      ? citedByIndex(index, inline: !splits)
      : null;
  final docPrints = [
    for (final doc in ordered)
      _docBlock(
        index,
        doc,
        bundle.mode,
        summary: inSummary(doc),
        citedBy: citedBy,
      ),
  ];
  final docBlocks = [for (final print in docPrints) print.block];
  final patternParts = featurePatternParts(index, bundle, ordered);
  final patternBlocks = [
    for (final part in patternParts) featurePatternBlock(part),
  ];
  final slots = _slotsOf(ordered, patternParts);
  final parts = followLinks(index, bundle, citedBy: citedBy);
  final partBlocks = [for (final part in parts) _partBlock(part)];
  final pieces = [
    ..._docSidePieces(
      index,
      bundle,
      ordered,
      patternParts,
      patternBlocks,
      slots,
      splits: splits,
      readFirstOnly: false,
      printOf: (doc) => docPrints[doc],
    ),
    ..._listPieces(index, bundle, splits: splits),
    for (final (i, part) in parts.indexed) ...[
      _Piece(
        partBlocks[i],
        doc: part.doc,
        kind: BundleEntryKind.cited,
        listName: _partListName(part),
        inRefs: splits,
        summary: part.summary,
        sections: [for (final section in part.sections) section.shiftedBy(1)],
        sectionKey: part.sectionKey,
        itemId: part.itemId,
      ),
      if (splits) ..._citedByPieces(part.doc, part.cited),
    ],
  ];
  final tokens = tokenSizeOf(_shownOf(pieces));
  final named = byCode && index.hasTwins ? bundle.codeTarget : null;
  if (budget != null && tokens > budget) {
    return _overBudget(
      ordered,
      docBlocks,
      summaryOnly,
      bundle,
      slots: slots,
      patternParts: patternParts,
      patternBlocks: patternBlocks,
      parts: parts,
      partBlocks: partBlocks,
      label: label,
      byCode: byCode,
      budget: budget,
      tokens: tokens,
      codeTarget: named,
    );
  }
  final readFirst = _textOf(
    [
      for (final piece in pieces)
        if (!piece.inRefs) piece,
    ],
    mode: bundle.mode,
    codeTargetLine: codeTargetLine(named),
  );
  final refs = splits
      ? _textOf(
          [
            for (final piece in pieces)
              if (piece.inRefs) piece,
          ],
          mode: bundle.mode,
          codeTargetLine: '',
          isRefs: true,
        )
      : null;
  final json = <String, Object>{
    byCode ? 'code' : 'target': label,
    'codeTarget': ?named,
    'for': bundle.mode.wire,
    'tokens': tokens,
    'docs': [
      for (final (doc, block) in docBlocks.indexed)
        {
          'name': ordered[doc].name,
          'docType': ?ordered[doc].docTypeId,
          'path': ordered[doc].docPath,
          'tokens': tokenSizeOf(block),
          'text': _blockBody(block),
          if (inSummary(ordered[doc])) 'summary': true,
          ..._citedByKey(docPrints[doc].cited, citedBy),
        },
      for (final (i, part) in parts.indexed)
        {
          ..._partDocJson(part, partBlocks[i]),
          if (!part.pathOnly && !part.nameOnly)
            'text': _blockBody(partBlocks[i]),
          ..._partKeys(part),
          ..._citedByKey(part.cited, citedBy),
        },
    ],
    if (bundle.mode == BundleMode.design)
      'featurePatterns': [
        for (final part in patternParts) featurePatternJson(part),
      ],
    ..._mapJson(index, bundle.mapTops, bundle.codeTarget),
    ..._namesJson(index, bundle.nameListTops, bundle.codeTarget),
  };
  return ContextAnswer(
    text: readFirst.text,
    json: json,
    warnings: [...bundle.warnings],
    entries: readFirst.entries,
    tokens: readFirst.tokens,
    codeTarget: named,
    refs: refs,
  );
}

/// The read-first block of each doc by index, built on first use: an index is
/// one read snapshot, so a feature or spec doc that many bundles of one run
/// print renders once. It holds a block for each doc, summary, and mode a run
/// asks for and is never trimmed; a `check` run ends with its index.
final _readFirstBlocksOf = Expando<Map<(String, BundleMode, bool), String>>();

/// Returns the est. tokens of the read-first file `answerContext` gives
/// [bundle] when split, which [ContextAnswer.readFirst] gives as `tokens`.
///
/// It builds the read-first pieces alone, with the builders `answerContext`
/// uses, and no appended part, cited-by part, or refs block, since the size
/// counts none of them.
int readFirstTokensOf(DocIndex index, Bundle bundle) {
  final ordered = bundle.printOrder(index);
  final summaryOnly = bundle.summaryOnly;
  final blocks = _readFirstBlocksOf[index] ??= {};
  final patternParts = featurePatternParts(index, bundle, ordered);
  final pieces = [
    ..._docSidePieces(
      index,
      bundle,
      ordered,
      patternParts,
      [for (final part in patternParts) featurePatternBlock(part)],
      _slotsOf(ordered, patternParts),
      splits: true,
      readFirstOnly: true,
      printOf: (doc) {
        final picked = ordered[doc];
        final summary = summaryOnly.contains(picked.docPath);
        final block = blocks[(picked.docPath, bundle.mode, summary)] ??=
            _docBlock(
              index,
              picked,
              bundle.mode,
              summary: summary,
              citedBy: null,
            ).block;
        return (block: block, cited: const [], sections: const []);
      },
    ),
    ..._listPieces(index, bundle, splits: true),
  ];
  return tokenSizeOf(_shownOf(pieces));
}

/// One doc's block with the places of it that carry cited-by lines and the
/// `##` sections it prints whole.
typedef _DocPrint = ({
  String block,
  List<CitedItem> cited,
  List<SectionLine> sections,
});

/// Returns the pieces of the docs and feature pattern parts of [slots], each
/// doc followed by its cited-by pieces when [splits].
///
/// A split bundle puts a summary doc and a doc that joins the refs in the refs
/// text; with [readFirstOnly], the pieces of those docs, which no read-first
/// file holds, are left out, and [printOf] is asked for no other doc.
List<_Piece> _docSidePieces(
  DocIndex index,
  Bundle bundle,
  List<IndexedDoc> ordered,
  List<FeaturePatternPart> patternParts,
  List<String> patternBlocks,
  List<_Slot> slots, {
  required bool splits,
  required bool readFirstOnly,
  required _DocPrint Function(int doc) printOf,
}) {
  final summaryOnly = bundle.summaryOnly;
  final pieces = <_Piece>[];
  for (final (:doc, :part) in slots) {
    if (doc == null) {
      pieces.add(
        _Piece(
          patternBlocks[part!],
          doc: patternParts[part].lister,
          kind: BundleEntryKind.pattern,
          listName: featurePatternListName(patternParts[part].pattern.id),
          featurePattern: patternParts[part].pattern.id,
        ),
      );
      continue;
    }
    final picked = ordered[doc];
    final summary = summaryOnly.contains(picked.docPath);
    final inRefs = splits && (summary || bundle.joinsRefs(index, picked));
    if (readFirstOnly && inRefs) continue;
    final print = printOf(doc);
    pieces.add(
      _Piece(
        print.block,
        doc: picked,
        listName: _listName(picked, summary),
        inRefs: inRefs,
        summary: summary,
        sections: print.sections,
      ),
    );
    if (splits && !readFirstOnly) {
      pieces.addAll(_citedByPieces(picked, print.cited));
    }
  }
  return pieces;
}

/// Returns the map and names pieces of [bundle], which every text of it that
/// holds them prints after its docs.
List<_Piece> _listPieces(
  DocIndex index,
  Bundle bundle, {
  required bool splits,
}) => [
  for (final top in _byTreeOrder(index, bundle.mapTops))
    _Piece(_mapBlock(index, index.at(top)!, bundle.codeTarget)),
  for (final top in _byTreeOrder(index, bundle.nameListTops))
    _Piece(
      _namesBlock(index, index.at(top)!, bundle.codeTarget),
      // An unsplit answer's index leaves a names block out, as it always has.
      doc: splits ? index.at(top) : null,
      kind: BundleEntryKind.names,
    ),
];

/// One block of a bundle text, in the whole bundle's print order, with what
/// its closing list and its entry need.
final class _Piece {
  const new(
    this.block, {
    this.doc,
    this.kind = BundleEntryKind.doc,
    this.listName,
    this.inRefs = false,
    this.summary = false,
    this.sections = const [],
    this.sectionKey,
    this.itemId,
    this.featurePattern,
  });

  final String block;

  /// The doc the entry names; null for a block with no entry, a query map.
  final IndexedDoc? doc;
  final BundleEntryKind kind;

  /// The closing-list line of the block, without its `- `; null for a block
  /// the list leaves out.
  final String? listName;

  /// Whether a split bundle puts the block in the refs text.
  final bool inRefs;
  final bool summary;

  /// The `##` sections the block prints whole, each with its header's line
  /// in the block, counted from 0.
  final List<SectionLine> sections;
  final String? sectionKey;
  final String? itemId;
  final String? featurePattern;

  /// Returns the entry of the block, which starts on line [first] of its text.
  BundleEntry? entryAt(int first) {
    final doc = this.doc;
    if (doc == null) return null;
    return (
      doc: doc,
      kind: kind,
      summary: summary,
      sectionKey: sectionKey,
      itemId: itemId,
      featurePattern: featurePattern,
      first: first,
      last: first + lineCountOf(block) - 1,
      sections: [
        for (final section in sections)
          (key: section.key, first: first + section.line),
      ],
    );
  }
}

/// Returns the cited-by part of each item, block, section, or doc of [items]
/// of [doc], in the refs text.
List<_Piece> _citedByPieces(IndexedDoc doc, List<CitedItem> items) => [
  for (final item in items)
    _Piece(
      citedByPartBlock(doc, item),
      doc: doc,
      kind: BundleEntryKind.citedBy,
      listName: citedByListName(doc, item),
      inRefs: true,
      sectionKey: item.sectionKey,
      itemId: item.item,
    ),
];

String _shownOf(List<_Piece> pieces) =>
    [for (final piece in pieces) piece.block].join('\n\n');

/// Returns the text of [pieces], one file of the bundle: the blocks joined by
/// one blank line, then the closing line and list, with the next-step line
/// after a list that holds a summary.
///
/// [codeTargetLine] opens the text and shifts its entries one line down.
BundleText _textOf(
  List<_Piece> pieces, {
  required BundleMode mode,
  required String codeTargetLine,
  bool isRefs = false,
}) {
  final shown = _shownOf(pieces);
  final tokens = tokenSizeOf(shown);
  final starts = _blockStarts([
    for (final piece in pieces) piece.block,
  ], firstLine: codeTargetLine.isEmpty ? 1 : 2);
  final entries = [
    for (final (i, piece) in pieces.indexed) ?piece.entryAt(starts[i]),
  ];
  final list = [
    for (final piece in pieces)
      if (piece.listName case final name?) '- $name\n',
  ];
  final listsSummary = pieces.any((piece) => piece.summary);
  final blocks = isRefs && pieces.isEmpty ? '' : '$shown\n';
  final closing =
      '${closingLineOf(docCountOf(entries), tokens)}'
      '${list.join()}'
      '${listsSummary ? '${_summaryNextStep(mode)}\n' : ''}';
  return (
    text: '$codeTargetLine$blocks$closing',
    entries: entries,
    tokens: tokens,
  );
}

/// Returns the line, from [firstLine], where each of [blocks] starts once
/// they are joined by one blank line.
List<int> _blockStarts(List<String> blocks, {required int firstLine}) {
  final starts = <int>[];
  var line = firstLine;
  for (final block in blocks) {
    starts.add(line);
    line += lineCountOf(block) + 1;
  }
  return starts;
}

/// One block of the doc side of a bundle text: the index of a picked doc in
/// the print order, or of a feature pattern part, never both.
typedef _Slot = ({int? doc, int? part});

/// Returns the blocks of [ordered] with each of [patternParts] right after
/// its lister, both in print order.
List<_Slot> _slotsOf(
  List<IndexedDoc> ordered,
  List<FeaturePatternPart> patternParts,
) {
  final slots = <_Slot>[];
  var next = 0;
  for (final (i, doc) in ordered.indexed) {
    slots.add((doc: i, part: null));
    while (next < patternParts.length &&
        patternParts[next].lister.docPath == doc.docPath) {
      slots.add((doc: null, part: next++));
    }
  }
  return slots;
}

/// Returns the name, doc type, path, and printed size of [part], whose block
/// is [block]; a path gives its path and size alone.
Map<String, Object> _partDocJson(AppendedPart part, String block) => {
  if (!part.pathOnly) ...{
    'name': part.doc.name,
    'docType': ?part.doc.docTypeId,
  },
  'path': part.doc.docPath,
  'tokens': tokenSizeOf(block),
};

/// Returns the reply for a bundle of [tokens] est. tokens that exceeds
/// [budget]: each doc's and part's size, no doc text, and the next step,
/// which keeps `--summary` when the bundle has it.
ContextAnswer _overBudget(
  List<IndexedDoc> ordered,
  List<String> docBlocks,
  Set<String> summaryOnly,
  Bundle bundle, {
  required List<_Slot> slots,
  required List<FeaturePatternPart> patternParts,
  required List<String> patternBlocks,
  required List<AppendedPart> parts,
  required List<String> partBlocks,
  required String label,
  required bool byCode,
  required int budget,
  required int tokens,
  required String? codeTarget,
}) {
  final next = bundle.summary
      ? _overBudgetSummaryNextStep
      : _overBudgetNextStep;
  final sizes = [for (final block in docBlocks) tokenSizeOf(block)];
  final lines = [
    for (final (:doc, :part) in slots)
      if (doc == null)
        _overBudgetLine(
          featurePatternListName(patternParts[part!].pattern.id),
          tokenSizeOf(patternBlocks[part]),
        )
      else
        _overBudgetLine(
          _listName(ordered[doc], summaryOnly.contains(ordered[doc].docPath)),
          sizes[doc],
        ),
    for (final (i, part) in parts.indexed)
      _overBudgetLine(_partListName(part), tokenSizeOf(partBlocks[i])),
  ];
  final text =
      '${codeTargetLine(codeTarget)}'
      'The bundle holds $tokens est. tokens, over the budget of $budget; '
      'no doc text is printed.\n'
      'Docs it would hold:\n'
      '${lines.join()}'
      'Next step: $next.\n';
  final json = <String, Object>{
    byCode ? 'code' : 'target': label,
    'codeTarget': ?codeTarget,
    'for': bundle.mode.wire,
    'budget': budget,
    'tokens': tokens,
    'overBudget': true,
    'docs': [
      for (final (i, doc) in ordered.indexed)
        {
          'name': doc.name,
          'docType': ?doc.docTypeId,
          'path': doc.docPath,
          'tokens': sizes[i],
          if (summaryOnly.contains(doc.docPath)) 'summary': true,
        },
      for (final (i, part) in parts.indexed)
        {..._partDocJson(part, partBlocks[i]), ..._partKeys(part)},
    ],
    if (bundle.mode == BundleMode.design)
      'featurePatterns': [
        for (final (i, part) in patternParts.indexed)
          {
            'id': part.pattern.id,
            'doc': featurePatternDocAddress(part.lister),
            'tokens': tokenSizeOf(patternBlocks[i]),
          },
      ],
    'next': next,
  };
  return ContextAnswer(
    text: text,
    json: json,
    warnings: [...bundle.warnings],
    exitStatus: 1,
    entries: const [],
    tokens: tokens,
    codeTarget: codeTarget,
  );
}

/// Returns the doc block of [doc] for [mode]: its naming line, then its
/// frontmatter text, head, and kept sections, each trimmed at its end and
/// joined by one blank line, with the lines [citedBy] holds for the whole doc
/// printed after the naming line and for its places printed after them, and
/// the line each kept section starts on in the block.
({String block, List<CitedItem> cited, List<SectionLine> sections}) _docBlock(
  DocIndex index,
  IndexedDoc doc,
  BundleMode mode, {
  required bool summary,
  required CitedByIndex? citedBy,
}) {
  final content = index.contentOf(doc);
  final docType = index.typeOf(doc);
  if (summary) {
    final print = summaryPrintOf(doc, content, docType, mode, citedBy);
    final block = '${namingLine(doc, summary: true)}\n${print.text}';
    final sections = [
      for (final section in print.sections) section.shiftedBy(1),
    ];
    return (block: block, cited: print.cited, sections: sections);
  }
  final parts = <String>[];
  if (mode != BundleMode.query) {
    final frontmatter = content.frontmatterText;
    if (frontmatter != null) parts.add(frontmatter.trimRight());
    final head = removeHtmlComments(content.head);
    if (head.trim().isNotEmpty) parts.add(head.trimRight());
  }
  final docEntry = citedBy == null ? null : citedDocIn(citedBy, doc);
  final docLines = citedLinesAfter(citedBy, [?docEntry])[0] ?? const [];
  final cited = <CitedItem>[?docEntry];
  final sections = <SectionLine>[];
  final held = citedSectionsOf(content, docType);
  // The naming line is the block's line 0.
  var line = 1 + docLines.length + lineAfterBlocks(parts);
  for (final section in keptSectionsOf(content, docType, mode)) {
    final print = sectionPrintOf(doc, content, held, section, citedBy);
    cited.addAll(print.cited);
    sections.add(SectionLine(key: section.key, line: line));
    line += lineAfterBlocks([print.block]);
    parts.add(print.block);
  }
  final block = [namingLine(doc), ...docLines, parts.join('\n\n')].join('\n');
  return (block: block, cited: cited, sections: sections);
}

/// Returns the map block of [top]: its subtree, one line per doc with its
/// name, doc type, and token size, indented two spaces per depth below [top];
/// [codeTarget] keeps that target's per-target docs alone.
String _mapBlock(DocIndex index, IndexedDoc top, String? codeTarget) {
  final lines = [
    for (final member in index.subtreeOf(top))
      if (member.inTarget(codeTarget)) _mapLine(index, top, member),
  ];
  return '==> map: ${nameWithType(top)} <==\n${lines.join('\n')}';
}

String _mapLine(DocIndex index, IndexedDoc top, IndexedDoc member) =>
    '${' ' * (2 * _depthBelow(index, top, member))}'
    '- ${nameWithType(member)} · ${member.tokens} tokens';

/// Returns the names block of [top]: one `- <name> (<doc type>) · <n> tokens`
/// line per ChainType child of [top]; [codeTarget] keeps
/// that target's per-target children alone.
String _namesBlock(DocIndex index, IndexedDoc top, String? codeTarget) {
  final lines = [
    for (final child in index.childrenOf(top))
      if (index.isChainDoc(child) && (child.inTarget(codeTarget)))
        '- ${nameWithType(child)} · ${child.tokens} tokens',
  ];
  return '==> names: ${nameWithType(top)} <==\n${lines.join('\n')}';
}

int _depthBelow(DocIndex index, IndexedDoc top, IndexedDoc doc) {
  var depth = 0;
  for (
    var member = doc;
    member.docPath != top.docPath;
    member = index.parentOf(member)!
  ) {
    depth++;
  }
  return depth;
}

/// Returns each DocPath of [paths] in tree order.
List<String> _byTreeOrder(DocIndex index, Set<String> paths) => [
  for (final doc in index.docs)
    if (paths.contains(doc.docPath)) doc.docPath,
];

/// Returns the block after its naming line, trimmed at both ends: the doc's
/// JSON `text`.
String _blockBody(String block) =>
    block.substring(block.indexOf('\n') + 1).trim();

Map<String, Object> _mapJson(
  DocIndex index,
  Set<String> tops,
  String? codeTarget,
) => {
  if (tops.isNotEmpty)
    'map': [
      for (final top in _byTreeOrder(index, tops))
        _docJson(index, index.at(top)!, codeTarget),
    ],
};

Map<String, Object> _docJson(
  DocIndex index,
  IndexedDoc doc,
  String? codeTarget,
) => {
  'name': doc.name,
  'docType': ?doc.docTypeId,
  'path': doc.docPath,
  'tokens': doc.tokens,
  'children': [
    for (final child in index.childrenOf(doc))
      if (child.inTarget(codeTarget)) _docJson(index, child, codeTarget),
  ],
};

Map<String, Object> _namesJson(
  DocIndex index,
  Set<String> tops,
  String? codeTarget,
) => {
  if (tops.isNotEmpty)
    'names': [
      for (final top in _byTreeOrder(index, tops))
        for (final child in index.childrenOf(index.at(top)!))
          if (index.isChainDoc(child) && (child.inTarget(codeTarget)))
            {
              'name': child.name,
              'docType': ?child.docTypeId,
              'path': child.docPath,
              'tokens': child.tokens,
            },
    ],
};
