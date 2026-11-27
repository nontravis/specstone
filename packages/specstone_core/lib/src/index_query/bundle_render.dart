import 'package:specstone_core/src/index_query/ancestor_pieces.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart'
    show readRangeTokenLimit;
import 'package:specstone_core/src/index_query/bundle_follow.dart';
import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/feature_pattern_parts.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/models/ancestor_piece.dart';
import 'package:specstone_core/src/index_query/models/bundle_entry.dart';
import 'package:specstone_core/src/index_query/models/bundle_text.dart';
import 'package:specstone_core/src/index_query/models/cited_item.dart';
import 'package:specstone_core/src/index_query/models/feature_pattern_part.dart';
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show verificationMatrixOf;

String _summaryNextStep(BundleMode mode) =>
    'Read a summary doc whole with: '
    'specstone context <name> --for ${mode.wire}';

const _overBudgetNextStep =
    'narrow the target, or run it again with --out and no --budget';

const _overBudgetSummaryNextStep =
    'narrow the target, or run it again with --summary --out and no --budget';

/// The tier of a part a split read-first file always holds.
const _mustTier = 0;

/// The tier of an ancestor spec piece.
const _pieceTier = 1;

/// The tier of any other doc the bundle prints whole.
const _wholeDocTier = 2;

/// The tier of a doc a `bundle_with` field joins.
const _linkedDocTier = 3;

/// The tier of a doc that joins through `bundle:` and stays out of refs.
const _joinedDocTier = 4;

/// The tier of a record outside every target subtree.
const _recordTier = 5;

/// Returns the number of docs [entries] hold, as a bundle's closing line and
/// its `--out` header count them: no part is a doc, but each doc a review part
/// sits in counts once.
int docCountOf(List<BundleEntry> entries) => {
  for (final entry in entries)
    if (entry.kind == BundleEntryKind.doc || entry.kind.isReviewPart)
      entry.doc.docPath,
}.length;

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
  BundleText get readFirst =>
      BundleText(text: text, entries: entries, tokens: tokens);
}

String _overBudgetLine(String listName, int tokens) =>
    '- $listName · $tokens tokens\n';

/// Returns the closing-list name of [doc], marked ` · summary` when [summary].
String _listName(IndexedDoc doc, bool summary) =>
    summary ? '${nameWithType(doc)} · summary' : nameWithType(doc);

/// Returns the closing-list name of a picked [doc]: its stub name when
/// [imported], else [_listName].
String _docListName(
  IndexedDoc doc, {
  required bool summary,
  required bool imported,
}) => imported ? stubListName(doc) : _listName(doc, summary);

/// Returns the closing-list name of [part],
/// `<name> (<doc type>) · cited <section key> [<ID>]`; a summary doc's is
/// marked ` · summary` before ` · cited`, a naming line's has no key, and
/// a path's is `<DocPath> · cited`; a stub's is its stub name alone.
String _partListName(AppendedPart part) => part.loaded
    ? stubListName(part.doc)
    : '${part.pathOnly ? part.doc.docPath : _listName(part.doc, part.summary)}'
          ' · cited'
          '${part.sectionKey == null ? '' : ' ${part.sectionKey}'}'
          '${part.itemId == null ? '' : ' [${part.itemId}]'}';

/// Returns the block of [part]: its naming line, `<DocPath>#<section key>`
/// with ` · block <anchor>` for a `###` block that starts no item,
/// ` · item <ID>` for an item, or ` · summary` for a doc, then ` · cited`, then
/// its text; a path prints as `==> <DocPath> · cited <==` alone, and a
/// naming-line doc as `==> <name> (<doc type>) · <DocPath> · cited <==` alone;
/// a stub prints as its stub line.
String _partBlock(AppendedPart part) {
  final doc = part.doc;
  if (part.loaded) return stubLine(doc);
  if (part.pathOnly) return '==> ${doc.docPath} · cited <==';
  if (part.nameOnly) {
    return '==> ${nameWithType(doc)} · ${doc.docPath} · cited <==';
  }
  final key = part.sectionKey;
  final path = key == null ? doc.docPath : '${doc.docPath}#$key';
  final block = part.heading == null ? '' : ' · block ${part.heading}';
  final item = part.itemId == null ? '' : ' · item ${part.itemId}';
  final summary = part.summary ? ' · summary' : '';
  return '==> ${nameWithType(doc)} · $path$block$item$summary · cited <==\n'
      '${part.text}';
}

/// Returns `cited` for an outbound piece and `cites` for an inbound one.
String _pieceMark(PieceDirection direction) => switch (direction) {
  PieceDirection.outbound => 'cited',
  PieceDirection.inbound => 'cites',
};

/// Returns the closing-list name of [piece],
/// `<name> (<doc type>) · cited <section key> [<ID>]`, with `cites` for an
/// inbound piece; a lead piece has no section key and a piece with no item ID
/// no `[<ID>]`.
String _pieceListName(AncestorPiece piece) =>
    '${nameWithType(piece.doc)} · ${_pieceMark(piece.direction)}'
    '${piece.sectionKey.isEmpty ? '' : ' ${piece.sectionKey}'}'
    '${piece.itemId == null ? '' : ' [${piece.itemId}]'}';

/// Returns the block of [piece]: its naming line, `<DocPath>#<section key>`
/// (`<DocPath>` alone for a piece of the lead) with ` · block <anchor>` for a
/// `###` block that starts no item and ` · item <ID>` for an item, then
/// ` · cited` or ` · cites`, then its text.
String _pieceBlock(AncestorPiece piece) {
  final key = piece.sectionKey;
  final path = key.isEmpty ? piece.doc.docPath : '${piece.doc.docPath}#$key';
  final block = piece.heading == null ? '' : ' · block ${piece.heading}';
  final item = piece.itemId == null ? '' : ' · item ${piece.itemId}';
  return '==> ${nameWithType(piece.doc)} · $path$block$item · '
      '${_pieceMark(piece.direction)} <==\n${piece.text}';
}

/// Returns the `citedBy` key of a doc object, an empty list when [items] holds
/// no line; none outside a design bundle, which has no [citedBy].
Map<String, Object> _citedByKey(List<CitedItem> items, CitedByIndex? citedBy) =>
    {if (citedBy != null) 'citedBy': citedByJson(items)};

/// Returns the JSON keys that mark [part], after its `text` or `tokens`.
Map<String, Object> _partKeys(AppendedPart part) => part.loaded
    ? const {}
    : {
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

/// Returns the est. tokens of a file of [runes] runes plus its closing line,
/// which names [docs] docs and the count this returns.
///
/// The line's own digits can move the count, so it settles at the least count
/// that the line printing it gives.
int wholeFileTokensOf(int runes, int docs) {
  var tokens = runes ~/ runesPerToken;
  while (true) {
    final closing = runeCountOf(closingLineOf(docs, tokens));
    final settled = (runes + closing) ~/ runesPerToken;
    if (settled == tokens) return tokens;
    tokens = settled;
  }
}

/// Returns the header line that names the code target a `--code` path lies
/// in, or '' when there is none to name (one target).
String codeTargetLine(String? name) =>
    name == null ? '' : '==> code target: $name <==\n';

/// Renders [bundle]'s docs as one `context` answer.
///
/// The parts the bundle's links cite print after its docs. The JSON key
/// `args` lists [targets] in the order given; a `--code` call holds `code`
/// instead. A bundle larger than [budget] prints its sizes and
/// the next step instead of doc text, with exit status 1; an equal one prints
/// whole. The answer places each doc and part in its text, for `--out`'s index.
///
/// With [split], an `implement` or `design` bundle puts each part in one of
/// two texts: [ContextAnswer.text] holds the read-first part, and
/// [ContextAnswer.refs] the refs part, each with its own entries, closing
/// line, and list. The read-first text holds the target subtrees, the chain
/// docs above them, and the feature pattern and names parts, then fills by
/// tier to one read. A `design` bundle's cited-by lines then print as parts of
/// the refs text, never after their item, and each ancestor spec doc prints
/// whole in the refs text, with its pieces at its place, and no cited-by line
/// for a link from the target subtree into one. [split] changes no other
/// output.
///
/// [readFirstEnd] ends a split read-first text, after its doc list, such as a
/// work group's `Cross-group links:` part; its closing line and the fill count
/// it.
ContextAnswer answerContext(
  DocIndex index,
  Bundle bundle, {
  required List<String> targets,
  int? budget,
  bool split = false,
  String readFirstEnd = '',
}) {
  assert(split || readFirstEnd.isEmpty, 'only a split read-first text ends');
  return _answerContext(
    index,
    bundle,
    code: null,
    targets: targets,
    budget: budget,
    split: split,
    readFirstEnd: readFirstEnd,
  );
}

/// Renders [bundle]'s docs as the `context` answer of a `--code` call.
///
/// [label] is the code path, printed under the JSON key `code`, with the picked
/// `codeTarget` when the project has two or more. Every other rule is
/// [answerContext]'s.
ContextAnswer answerCodeContext(
  DocIndex index,
  Bundle bundle, {
  required String label,
  int? budget,
  bool split = false,
}) => _answerContext(
  index,
  bundle,
  code: label,
  targets: const [],
  budget: budget,
  split: split,
);

ContextAnswer _answerContext(
  DocIndex index,
  Bundle bundle, {
  required String? code,
  required List<String> targets,
  required int? budget,
  required bool split,
  String readFirstEnd = '',
}) {
  final byCode = code != null;
  final splits = split && bundle.mode != BundleMode.query;
  final ordered = bundle.printOrder(index);
  final summaryOnly = bundle.summaryOnly;
  bool inSummary(IndexedDoc doc) => summaryOnly.contains(doc.docPath);
  final wholePaths = _wholePathsOf(ordered, bundle);
  final ancestors = _ancestorSpecsOf(index, bundle, splits: splits);
  final citedBy = bundle.mode == BundleMode.design
      ? _citedByOf(index, bundle, ancestors, splits: splits)
      : null;
  final docPrints = [
    for (final doc in ordered)
      _docPrintOf(index, bundle, doc, wholePaths, citedBy: citedBy),
  ];
  final docBlocks = [for (final print in docPrints) print.text];
  final patternParts = featurePatternParts(index, bundle, ordered);
  final patternBlocks = [
    for (final part in patternParts) featurePatternBlock(part),
  ];
  final slots = _slotsOf(ordered, patternParts);
  final parts = followLinks(
    index,
    bundle,
    ancestorPieceRanges: ancestors.pieceRanges,
  );
  final partBlocks = [for (final part in parts) _partBlock(part)];
  final pieces = [
    ..._docSidePieces(
      index,
      bundle,
      ordered,
      patternParts,
      patternBlocks,
      slots,
      ancestors,
      splits: splits,
      kept: _Kept.all,
      printOf: (doc, part) => part == _MatrixPart.whole
          ? docPrints[doc]
          : _docPrintOf(
              index,
              bundle,
              ordered[doc],
              wholePaths,
              citedBy: null,
              part: part,
            ),
    ),
    ..._listPieces(index, bundle, splits: splits),
    for (final (i, part) in parts.indexed)
      _Piece(
        partBlocks[i],
        doc: part.doc,
        kind: BundleEntryKind.cited,
        listName: _partListName(part),
        tier: null,
        inRefs: splits,
        summary: part.summary,
        loaded: part.loaded,
        sections: [for (final section in part.sections) section.shiftedBy(1)],
        sectionKey: part.sectionKey,
        itemId: part.itemId,
      ),
  ];
  final tokens = tokenSizeOf(_shownOf(pieces));
  final named = byCode && index.hasTwins ? bundle.codeTarget : null;
  final codeLine = codeTargetLine(named);
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
      code: code,
      targets: targets,
      budget: budget,
      tokens: tokens,
      codeTarget: named,
    );
  }
  final placed = splits
      ? _filledPieces(pieces, codeTargetLine: codeLine, end: readFirstEnd)
      : pieces;
  final readFirst = _textOf(
    [
      for (final piece in placed)
        if (!piece.inRefs) piece,
    ],
    mode: bundle.mode,
    codeTargetLine: codeLine,
    countsWholeFile: splits,
    end: readFirstEnd,
  );
  final refs = splits
      ? _textOf(
          [
            for (final piece in placed)
              if (piece.inRefs) piece,
          ],
          mode: bundle.mode,
          codeTargetLine: '',
          countsWholeFile: true,
          isRefs: true,
        )
      : null;
  final json = <String, Object>{
    ..._argumentKeys(code, targets),
    'codeTarget': ?named,
    'for': bundle.mode.wire,
    'tokens': tokens,
    'docs': [
      for (final (doc, block) in docBlocks.indexed)
        if (bundle.isImported(ordered[doc]))
          _stubDocJson(ordered[doc], block)
        else
          {
            'name': ordered[doc].name,
            'docType': ?ordered[doc].docTypeId,
            'path': ordered[doc].docPath,
            'tokens': tokenSizeOf(block),
            'text': _blockBody(
              _withVerbatimHeadings(
                index,
                ordered[doc],
                docPrints[doc].sections,
                block,
              ),
            ),
            if (inSummary(ordered[doc])) 'summary': true,
            ..._citedByKey(docPrints[doc].cited, citedBy),
          },
      for (final (i, part) in parts.indexed)
        {
          ..._partDocJson(part, partBlocks[i]),
          if (!part.pathOnly && !part.nameOnly && !part.loaded)
            'text': _blockBody(
              _withVerbatimHeadings(index, part.doc, [
                for (final section in part.sections) section.shiftedBy(1),
              ], partBlocks[i]),
            ),
          ..._partKeys(part),
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

/// The print of each doc by index, built on first use: an index is
/// one read snapshot, so a feature or spec doc that many bundles of one run
/// print renders once. It holds a block for each doc, summary, and mode a run
/// asks for; a record's matrix cut is part of the key, since two bundles of one
/// run print different rows of it; which part of a record's block a print
/// holds, whole or without or only its matrix section, is part of the key too;
/// so is whether the bundle marks the doc imported, since one index serves
/// bundles with and without an imported set. A `check` run ends with its index.
final _docPrintsOf =
    Expando<Map<(String, BundleMode, bool, bool, bool, String), DocPrint>>();

/// Returns the print of [doc] in [bundle]; one with no [citedBy] is built once
/// per index, whichever bundle of the run asks, since [_docBlock] reads
/// nothing else of the bundle.
DocPrint _docPrintOf(
  DocIndex index,
  Bundle bundle,
  IndexedDoc doc,
  Set<String> wholePaths, {
  required CitedByIndex? citedBy,
  _MatrixPart part = _MatrixPart.whole,
}) {
  final summary = bundle.summaryOnly.contains(doc.docPath);
  final imported = bundle.isImported(doc);
  final isTarget = bundle.targetPaths.contains(doc.docPath);
  final matrixCut = _matrixCutOf(index, doc, bundle.mode, wholePaths);
  DocPrint build() => _docBlock(
    index,
    doc,
    bundle.mode,
    summary: summary,
    imported: imported,
    citedBy: citedBy,
    isTarget: isTarget,
    matrixCut: matrixCut,
    part: part,
  );
  if (citedBy != null) return build();
  return (_docPrintsOf[index] ??= {})[(
        doc.docPath,
        bundle.mode,
        summary,
        imported,
        isTarget,
        '${part.name}:${_cutKeyOf(matrixCut)}',
      )] ??=
      build();
}

/// Returns the store key of [cut]: its sorted lines joined, one constant for
/// the empty cut a doc with no matrix rows out of scope holds.
String _cutKeyOf(Set<int> cut) =>
    cut.isEmpty ? '' : (cut.toList()..sort()).join(',');

/// Returns the est. tokens of the read-first file `answerContext` gives
/// [bundle] when split, which [ContextAnswer.readFirst] gives as `tokens`.
///
/// It builds the pieces a read-first file may hold, with the builders
/// `answerContext` uses, ancestor spec pieces included, and fills the file
/// from them as `answerContext` does, with no code target line. No appended
/// part, cited-by part, or refs block is built, since none is read-first.
int readFirstTokensOf(DocIndex index, Bundle bundle) => _textOf(
  [
    for (final piece in _filledPieces(
      _readFirstPieces(index, bundle, kept: _Kept.readFirst),
      codeTargetLine: '',
    ))
      if (!piece.inRefs) piece,
  ],
  mode: bundle.mode,
  codeTargetLine: '',
  countsWholeFile: true,
).tokens;

/// Returns [readFirstTokensOf] of [bundle] when it passes
/// [readRangeTokenLimit], else null, sizing the must parts alone.
///
/// The fill adds a tier part only while the file stays within the limit, and
/// each part grows it, so the file passes the limit exactly when its must
/// parts do, and then it holds them alone.
int? readFirstOverLimitOf(DocIndex index, Bundle bundle) {
  final tokens = _wholeFileTokensOf(
    index,
    _readFirstPieces(index, bundle, kept: _Kept.must),
    mode: bundle.mode,
  );
  return tokens > readRangeTokenLimit ? tokens : null;
}

/// Returns the runes each doc prints in the split answer of [bundle], by
/// DocPath, with no answer built: the runes of each doc block the answer holds
/// in its read-first or refs text, a doc printed in two parts, such as a record
/// and its matrix section, summing both.
///
/// It places the blocks as `answerContext` does with `split`, no code target
/// line, and no read-first end. No appended part, cited-by part, or JSON is
/// built, since none holds a doc block.
Map<String, int> printedDocRunesOf(DocIndex index, Bundle bundle) {
  final runes = <String, int>{};
  final pieces = _filledPieces(
    _readFirstPieces(index, bundle, kept: _Kept.all),
    codeTargetLine: '',
  );
  for (final piece in pieces) {
    final doc = piece.doc;
    if (doc == null || piece.kind != BundleEntryKind.doc) continue;
    final blockRunes = runeCountOf(piece.block);
    runes.update(
      doc.docPath,
      (sum) => sum + blockRunes,
      ifAbsent: () => blockRunes,
    );
  }
  return runes;
}

/// The runes of each block string an index sized, by block identity: a doc
/// block of one run is one string, so every bundle that prints it counts it
/// once. An index is one read snapshot, so it holds no stale count.
final _blockRunes = Expando<Map<String, int>>();

/// Returns the `tokens` [_textOf] gives [pieces] with no code target line and
/// `countsWholeFile`, counted from the runes of each block, the blank lines
/// between them, and the closing list, so the text is never built.
int _wholeFileTokensOf(
  DocIndex index,
  List<_Piece> pieces, {
  required BundleMode mode,
}) {
  final runes = _blockRunes[index] ??= Map<String, int>.identity();
  var blockRunes = _ReadFirstSize._blocksEndRunes;
  for (final piece in pieces) {
    blockRunes += runes[piece.block] ??= runeCountOf(piece.block);
  }
  if (pieces.length > 1) {
    blockRunes += (pieces.length - 1) * _ReadFirstSize._blockGapRunes;
  }
  final listsSummary = pieces.any((piece) => piece.summary);
  final listed =
      '${[for (final piece in pieces) _listLineOf(piece)].join()}'
      '${listsSummary ? '${_summaryNextStep(mode)}\n' : ''}';
  final docs = {
    for (final piece in pieces)
      if (piece.doc case final doc?)
        if (piece.kind == BundleEntryKind.doc || piece.kind.isReviewPart)
          doc.docPath,
  }.length;
  return wholeFileTokensOf(blockRunes + runeCountOf(listed), docs);
}

/// Returns the [kept] pieces of [bundle]'s read-first file, in print order,
/// before the fill.
List<_Piece> _readFirstPieces(
  DocIndex index,
  Bundle bundle, {
  required _Kept kept,
}) {
  final ordered = bundle.printOrder(index);
  final wholePaths = _wholePathsOf(ordered, bundle);
  final patternParts = featurePatternParts(index, bundle, ordered);
  return [
    ..._docSidePieces(
      index,
      bundle,
      ordered,
      patternParts,
      [for (final part in patternParts) featurePatternBlock(part)],
      _slotsOf(ordered, patternParts),
      kept == _Kept.must
          ? _AncestorSpecs(
              paths: _movedAncestorPathsOf(bundle),
              piecesByDoc: const {},
              pieceRanges: const {},
            )
          : _ancestorSpecsOf(index, bundle, splits: true),
      splits: true,
      kept: kept,
      printOf: (doc, part) {
        final print = _docPrintOf(
          index,
          bundle,
          ordered[doc],
          wholePaths,
          citedBy: null,
          part: part,
        );
        return DocPrint(text: print.text, cited: const [], sections: const []);
      },
    ),
    ..._listPieces(index, bundle, splits: true),
  ];
}

/// Which part of a doc's block a print holds: the whole block, or a record's
/// block with its Verification matrix section left out or alone.
enum _MatrixPart { whole, without, only }

/// Which pieces of a bundle's doc side [_docSidePieces] builds.
enum _Kept {
  /// Every piece, as an answer prints them.
  all,

  /// The pieces a read-first file may hold.
  readFirst,

  /// The must parts of a read-first file alone.
  must,
}

/// The ancestor spec docs of a split design bundle, which the refs text holds
/// whole, and the pieces of them the read-first text prints.
final class _AncestorSpecs {
  const new({
    required this.paths,
    required this.piecesByDoc,
    required this.pieceRanges,
  });

  /// The DocPaths of the docs the refs text holds; empty when the bundle has
  /// none to move.
  final Set<String> paths;

  /// The pieces of each doc by DocPath, in file order.
  final Map<String, List<AncestorPiece>> piecesByDoc;

  /// The file lines of each ancestor spec doc's pieces by DocPath, with or
  /// without a split; a doc with no piece maps to none.
  final Map<String, List<LineRange>> pieceRanges;

  bool holds(IndexedDoc doc) => paths.contains(doc.docPath);

  List<AncestorPiece> piecesOf(IndexedDoc doc) =>
      piecesByDoc[doc.docPath] ?? const [];
}

/// Returns the ancestor spec docs of [bundle]; with [splits] the refs text
/// holds them, else only their [_AncestorSpecs.pieceRanges] are set.
///
/// A doc the target subtree also holds, as a multi-target call gives, keeps
/// its print, as [ancestorPiecesOf] reads it.
_AncestorSpecs _ancestorSpecsOf(
  DocIndex index,
  Bundle bundle, {
  required bool splits,
}) {
  if (!bundle.hasAncestorSpecs) {
    return const _AncestorSpecs(paths: {}, piecesByDoc: {}, pieceRanges: {});
  }
  final piecesByDoc = <String, List<AncestorPiece>>{};
  for (final piece in ancestorPiecesOf(index, bundle)) {
    (piecesByDoc[piece.doc.docPath] ??= []).add(piece);
  }
  final paths = _movedAncestorPathsOf(bundle);
  final pieceRanges = {
    for (final path in paths)
      path: [
        for (final piece in piecesByDoc[path] ?? const <AncestorPiece>[])
          LineRange(first: piece.first, last: piece.last),
      ],
  };
  if (!splits) {
    return _AncestorSpecs(
      paths: const {},
      piecesByDoc: const {},
      pieceRanges: pieceRanges,
    );
  }
  return _AncestorSpecs(
    paths: paths,
    piecesByDoc: piecesByDoc,
    pieceRanges: pieceRanges,
  );
}

/// Returns the ancestor spec docs of [bundle] that a split moves to the refs
/// text: those its target subtree does not hold.
Set<String> _movedAncestorPathsOf(Bundle bundle) =>
    bundle.ancestorSpecPaths.difference(bundle.targetSubtreePaths);

/// Returns who cites each place of a design [bundle], the links from its
/// target subtree into [ancestors] left out when [splits], since the
/// read-first text prints those links' pieces.
CitedByIndex _citedByOf(
  DocIndex index,
  Bundle bundle,
  _AncestorSpecs ancestors, {
  required bool splits,
}) {
  final cited = citedByIndex(index, inline: !splits);
  if (ancestors.paths.isEmpty) return cited;
  return cited.withoutLinks(
    from: bundle.targetSubtreePaths,
    into: ancestors.paths,
  );
}

/// Returns the bundle piece that prints the ancestor spec [piece], an entry of
/// its own.
_Piece _ancestorPiece(AncestorPiece piece) => _Piece(
  _pieceBlock(piece),
  doc: piece.doc,
  kind: switch (piece.direction) {
    PieceDirection.outbound => BundleEntryKind.cited,
    PieceDirection.inbound => BundleEntryKind.cites,
  },
  listName: _pieceListName(piece),
  tier: _pieceTier,
  sectionKey: piece.sectionKey.isEmpty ? null : piece.sectionKey,
  itemId: piece.itemId,
);

/// Returns the pieces of the docs and feature pattern parts of [slots], each
/// doc followed by its cited-by pieces when [splits], each tagged with its
/// fill tier.
///
/// A split bundle puts a summary doc, an ancestor spec doc of [ancestors], and
/// a doc that joins the refs in the refs text; past [_Kept.all], the pieces
/// of those docs, which no read-first file holds, are left out, and with
/// [_Kept.must] every part of a tier too. [printOf] is asked for no doc left
/// out. An ancestor spec doc's own pieces print at its slot.
///
/// A design record that keeps its Verification matrix section prints without
/// it and, in [_Kept.all], is followed by a refs piece of that section alone,
/// before its cited-by pieces; a tiered record gets that piece from the fill
/// only when it stays read-first. A stub of an imported doc takes the must
/// tier of any tier it would have.
List<_Piece> _docSidePieces(
  DocIndex index,
  Bundle bundle,
  List<IndexedDoc> ordered,
  List<FeaturePatternPart> patternParts,
  List<String> patternBlocks,
  List<_Slot> slots,
  _AncestorSpecs ancestors, {
  required bool splits,
  required _Kept kept,
  required DocPrint Function(int doc, _MatrixPart part) printOf,
}) {
  final summaryOnly = bundle.summaryOnly;
  final pieces = <_Piece>[];
  for (final _Slot(:doc, :part) in slots) {
    if (doc == null) {
      pieces.add(
        _Piece(
          patternBlocks[part!],
          doc: patternParts[part].lister,
          kind: BundleEntryKind.pattern,
          listName: featurePatternListName(patternParts[part].pattern.id),
          tier: _mustTier,
          featurePattern: patternParts[part].pattern.id,
        ),
      );
      continue;
    }
    final picked = ordered[doc];
    final summary = summaryOnly.contains(picked.docPath);
    final imported = bundle.isImported(picked);
    final docTier = summary || ancestors.holds(picked)
        ? null
        : _docTierOf(index, bundle, picked);
    // A stub is one fixed line: it stays in the file its tier gives, so the
    // fill never weighs it against the budget or marks it moved.
    final tier = imported && docTier != null ? _mustTier : docTier;
    final inRefs = splits && tier == null;
    if (!imported && kept != _Kept.must) {
      pieces.addAll(ancestors.piecesOf(picked).map(_ancestorPiece));
    }
    if (kept != _Kept.all && inRefs) continue;
    if (kept == _Kept.must && tier != _mustTier) continue;
    final holdsMatrix =
        splits &&
        tier != null &&
        _holdsMatrixPart(index, bundle, picked, imported: imported);
    final print = printOf(
      doc,
      holdsMatrix ? _MatrixPart.without : _MatrixPart.whole,
    );
    final listName = _docListName(picked, summary: summary, imported: imported);
    _Piece docPiece(
      DocPrint of, {
      required int? tier,
      bool inRefs = false,
      _MatrixSplit? split,
    }) => _Piece(
      of.text,
      doc: picked,
      listName: listName,
      tier: tier,
      inRefs: inRefs,
      summary: summary && !imported,
      loaded: imported,
      sections: of.sections,
      split: split,
    );
    final matrixPiece = holdsMatrix && kept == _Kept.all
        ? docPiece(printOf(doc, _MatrixPart.only), tier: null, inRefs: true)
        : null;
    // A record the fill may move goes to the refs text whole; one it keeps
    // read-first prints its matrix section there alone.
    final moves = holdsMatrix && tier != _mustTier
        ? _MatrixSplit(
            whole: docPiece(printOf(doc, _MatrixPart.whole), tier: tier),
            matrix: matrixPiece,
          )
        : null;
    pieces.add(docPiece(print, tier: tier, inRefs: inRefs, split: moves));
    if (matrixPiece != null && moves == null) pieces.add(matrixPiece);
    if (splits && kept == _Kept.all) {
      final cited = holdsMatrix
          ? printOf(doc, _MatrixPart.whole).cited
          : print.cited;
      pieces.addAll(_citedByPieces(picked, cited));
    }
  }
  return pieces;
}

/// Returns the fill tier of [doc], a doc [bundle] prints whole: must for a
/// doc of a target subtree or a chain doc above one, null for a `bundle:`
/// join of the refs file, else the tier of its join or kind.
int? _docTierOf(DocIndex index, Bundle bundle, IndexedDoc doc) {
  final path = doc.docPath;
  if (bundle.targetSubtreePaths.contains(path) ||
      bundle.chainAbovePaths.contains(path)) {
    return _mustTier;
  }
  if (bundle.joinsRefs(index, doc)) return null;
  if (bundle.linkedDocs.containsKey(path)) return _linkedDocTier;
  if (bundle.joinedPaths.contains(path)) return _joinedDocTier;
  if (index.typeOf(doc)?.isRecordType ?? false) return _recordTier;
  return _wholeDocTier;
}

/// Returns the map and names pieces of [bundle], which every text of it that
/// holds them prints after its docs.
///
/// A names block is a must part: it prints with a chain doc above a target.
List<_Piece> _listPieces(
  DocIndex index,
  Bundle bundle, {
  required bool splits,
}) => [
  for (final top in _byTreeOrder(index, bundle.mapTops))
    _Piece(
      _mapBlock(index, index.at(top)!, bundle.codeTarget),
      tier: _mustTier,
    ),
  for (final top in _byTreeOrder(index, bundle.nameListTops))
    _Piece(
      _namesBlock(index, index.at(top)!, bundle.codeTarget),
      // An unsplit answer's index leaves a names block out, as it always has.
      doc: splits ? index.at(top) : null,
      kind: BundleEntryKind.names,
      tier: _mustTier,
    ),
];

/// What a tiered record piece that prints without its matrix section becomes
/// once the fill places it.
final class _MatrixSplit {
  const new({required this.whole, required this.matrix});

  /// The whole record, which goes to the refs text when the fill moves it.
  final _Piece whole;

  /// The matrix section alone, which the refs text holds when the record
  /// stays read-first; null when the bundle builds no refs text.
  final _Piece? matrix;
}

/// One block of a bundle text, in the whole bundle's print order, with what
/// its closing list and its entry need.
final class _Piece {
  const new(
    this.block, {
    this.doc,
    this.kind = BundleEntryKind.doc,
    this.listName,
    required this.tier,
    this.inRefs = false,
    this.moved = false,
    this.summary = false,
    this.loaded = false,
    this.sections = const [],
    this.sectionKey,
    this.itemId,
    this.featurePattern,
    this.split,
  });

  final String block;

  /// The doc the entry names; null for a block with no entry, a query map.
  final IndexedDoc? doc;
  final BundleEntryKind kind;

  /// The closing-list line of the block, without its `- `; null for a block
  /// the list leaves out.
  final String? listName;

  /// The read-first fill tier of the block: 0 for a must part, 1 to 5 for a
  /// part read-first while it fits, null for a part a split bundle always
  /// puts in the refs text.
  final int? tier;

  /// Whether a split bundle puts the block in the refs text; for a tier 1 to
  /// 5 part, the fill sets it.
  final bool inRefs;

  /// Whether the fill moved the block from the read-first text to the refs
  /// text.
  final bool moved;

  final bool summary;

  /// Whether the block is the stub line of an imported doc.
  final bool loaded;

  /// The `##` sections the block prints whole, each with its header's line
  /// in the block, counted from 0.
  final List<SectionLine> sections;
  final String? sectionKey;
  final String? itemId;
  final String? featurePattern;

  /// For a record piece that prints without its matrix section, what the fill
  /// places in its stead; null for any other piece.
  final _MatrixSplit? split;

  /// Returns this block placed in the refs text when [inRefs], else in the
  /// read-first text; a tier part placed in refs is moved.
  _Piece placedInRefs({required bool inRefs}) => _Piece(
    block,
    doc: doc,
    kind: kind,
    listName: listName,
    tier: tier,
    inRefs: inRefs,
    moved: inRefs,
    summary: summary,
    loaded: loaded,
    sections: sections,
    sectionKey: sectionKey,
    itemId: itemId,
    featurePattern: featurePattern,
  );

  /// Returns the entry of the block, which starts on line [first] of its text.
  BundleEntry? entryAt(int first) {
    final doc = this.doc;
    if (doc == null) return null;
    return BundleEntry(
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
          EntrySection(key: section.key, first: first + section.line),
      ],
      moved: moved,
      loaded: loaded,
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
      tier: null,
      inRefs: true,
      sectionKey: item.sectionKey,
      itemId: item.item,
    ),
];

String _shownOf(List<_Piece> pieces) =>
    [for (final piece in pieces) piece.block].join('\n\n');

/// Returns [pieces] with each tier 1 to 5 part placed by the read-first
/// budget, [readRangeTokenLimit] est. tokens.
///
/// The read-first text holds every must part, then takes each tier 1 to 5
/// part, tier by tier and in print order within a tier, while the whole text
/// stays within the budget; a part that does not fit goes to the refs text,
/// and the next one is still tried. A part of no tier keeps its text. The
/// text's [codeTargetLine] and [end] count in its size.
List<_Piece> _filledPieces(
  List<_Piece> pieces, {
  required String codeTargetLine,
  String end = '',
}) {
  var size = _ReadFirstSize(
    fixedRunes: runeCountOf(codeTargetLine) + runeCountOf(end),
  );
  for (final piece in pieces) {
    if (piece.tier == _mustTier) size = size.plus(piece);
  }
  final fitting = <int>{};
  for (var tier = _pieceTier; tier <= _recordTier; tier++) {
    for (final (at, piece) in pieces.indexed) {
      if (piece.tier != tier) continue;
      final next = size.plus(piece);
      if (next.tokens > readRangeTokenLimit) continue;
      size = next;
      fitting.add(at);
    }
  }
  return [
    for (final (at, piece) in pieces.indexed)
      if (piece.tier case final tier? when tier != _mustTier)
        ..._placedPieces(piece, inRefs: !fitting.contains(at))
      else
        piece,
  ];
}

/// Returns the pieces [piece], a tier 1 to 5 part, becomes in the text the fill
/// puts it in: a record without its matrix section becomes the whole record
/// when moved, else itself and its matrix section in the refs text.
List<_Piece> _placedPieces(_Piece piece, {required bool inRefs}) {
  final split = piece.split;
  if (split == null) return [piece.placedInRefs(inRefs: inRefs)];
  if (inRefs) return [split.whole.placedInRefs(inRefs: true)];
  return [piece.placedInRefs(inRefs: false), ?split.matrix];
}

/// The est. tokens of a read-first text as [_textOf] writes it, counted from
/// the sizes of its blocks and list lines, so no candidate text is rendered.
///
/// It counts each part [_textOf] writes; a change to that text changes it. A
/// read-first text has no next-step line, since a summary part goes to refs.
final class _ReadFirstSize {
  const new({
    required this.fixedRunes,
    this.blockRunes = 0,
    this.blocks = 0,
    this.listRunes = 0,
    this.docs = 0,
  });

  /// The runes of the blank line that joins two blocks.
  static const _blockGapRunes = 2;

  /// The runes of the line feed that ends the last block.
  static const _blocksEndRunes = 1;

  /// The runes of the text outside its blocks and list: its code target line
  /// and its end.
  final int fixedRunes;
  final int blockRunes;
  final int blocks;
  final int listRunes;
  final int docs;

  /// Returns this size with [piece] added to the text.
  _ReadFirstSize plus(_Piece piece) => _ReadFirstSize(
    fixedRunes: fixedRunes,
    blockRunes: blockRunes + runeCountOf(piece.block),
    blocks: blocks + 1,
    listRunes: listRunes + runeCountOf(_listLineOf(piece)),
    docs: piece.doc != null && piece.kind == BundleEntryKind.doc
        ? docs + 1
        : docs,
  );

  /// The whole text's count, as [wholeFileTokensOf] settles it.
  int get tokens {
    final shown = blockRunes + (blocks == 0 ? 0 : blocks - 1) * _blockGapRunes;
    return wholeFileTokensOf(
      fixedRunes + shown + _blocksEndRunes + listRunes,
      docs,
    );
  }
}

/// Returns the closing-list line of [piece], with its line end; '' for a
/// block the list leaves out.
String _listLineOf(_Piece piece) => switch (piece.listName) {
  final name? => '- $name${piece.moved ? ' · $movedWord' : ''}\n',
  null => '',
};

/// Returns the text of [pieces], one file of the bundle: the blocks joined by
/// one blank line, then the closing line and list, with the next-step line
/// after a list that holds a summary.
///
/// - [codeTargetLine]: opens the text and shifts its entries one line down.
/// - [countsWholeFile]: the closing line and `tokens` count the whole text, as
///   a split file's header does; else the blocks alone.
/// - [end]: closes the text after its list, counted with the whole text.
BundleText _textOf(
  List<_Piece> pieces, {
  required BundleMode mode,
  required String codeTargetLine,
  required bool countsWholeFile,
  bool isRefs = false,
  String end = '',
}) {
  final shown = _shownOf(pieces);
  final starts = _blockStarts([
    for (final piece in pieces) piece.block,
  ], firstLine: codeTargetLine.isEmpty ? 1 : 2);
  final entries = [
    for (final (i, piece) in pieces.indexed) ?piece.entryAt(starts[i]),
  ];
  final listsSummary = pieces.any((piece) => piece.summary);
  final blocks = isRefs && pieces.isEmpty ? '' : '$shown\n';
  final listed =
      '${[for (final piece in pieces) _listLineOf(piece)].join()}'
      '${listsSummary ? '${_summaryNextStep(mode)}\n' : ''}';
  final docs = docCountOf(entries);
  final tokens = countsWholeFile
      ? wholeFileTokensOf(
          runeCountOf(codeTargetLine) +
              runeCountOf(blocks) +
              runeCountOf(listed) +
              runeCountOf(end),
          docs,
        )
      : tokenSizeOf(shown);
  return BundleText(
    text: '$codeTargetLine$blocks${closingLineOf(docs, tokens)}$listed$end',
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
final class _Slot {
  const new({required this.doc, required this.part});

  final int? doc;
  final int? part;
}

/// Returns the blocks of [ordered] with each of [patternParts] right after
/// its lister, both in print order.
List<_Slot> _slotsOf(
  List<IndexedDoc> ordered,
  List<FeaturePatternPart> patternParts,
) {
  final slots = <_Slot>[];
  var next = 0;
  for (final (i, doc) in ordered.indexed) {
    slots.add(_Slot(doc: i, part: null));
    while (next < patternParts.length &&
        patternParts[next].lister.docPath == doc.docPath) {
      slots.add(_Slot(doc: null, part: next++));
    }
  }
  return slots;
}

/// Returns the JSON entry of an imported [doc] whose stub line is [block]: its
/// name, doc type, path, the stub line's size, and `loadedBy`, with no text.
Map<String, Object> _stubDocJson(IndexedDoc doc, String block) => {
  'name': doc.name,
  'docType': ?doc.docTypeId,
  'path': doc.docPath,
  'tokens': tokenSizeOf(block),
  'loadedBy': stubLoadedBy,
};

/// Returns the name, doc type, path, and printed size of [part], whose block
/// is [block]; a path gives its path and size alone, and a stub its stub
/// entry.
Map<String, Object> _partDocJson(AppendedPart part, String block) => part.loaded
    ? _stubDocJson(part.doc, block)
    : {
        if (!part.pathOnly) ...{
          'name': part.doc.name,
          'docType': ?part.doc.docTypeId,
        },
        'path': part.doc.docPath,
        'tokens': tokenSizeOf(block),
      };

/// Returns the JSON keys that name what the call bundles: `code` for a code
/// path, else `args`, the target arguments in the order given.
Map<String, Object> _argumentKeys(String? code, List<String> targets) {
  if (code != null) return {'code': code};
  return {'args': targets};
}

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
  required String? code,
  required List<String> targets,
  required int budget,
  required int tokens,
  required String? codeTarget,
}) {
  final next = bundle.summary
      ? _overBudgetSummaryNextStep
      : _overBudgetNextStep;
  final sizes = [for (final block in docBlocks) tokenSizeOf(block)];
  final lines = [
    for (final _Slot(:doc, :part) in slots)
      if (doc == null)
        _overBudgetLine(
          featurePatternListName(patternParts[part!].pattern.id),
          tokenSizeOf(patternBlocks[part]),
        )
      else
        _overBudgetLine(
          _docListName(
            ordered[doc],
            summary: summaryOnly.contains(ordered[doc].docPath),
            imported: bundle.isImported(ordered[doc]),
          ),
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
    ..._argumentKeys(code, targets),
    'codeTarget': ?codeTarget,
    'for': bundle.mode.wire,
    'budget': budget,
    'tokens': tokens,
    'overBudget': true,
    'docs': [
      for (final (i, doc) in ordered.indexed)
        if (bundle.isImported(doc))
          _stubDocJson(doc, docBlocks[i])
        else
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
///
/// In `query` only a [isTarget] doc prints its head and every kept section.
/// A record leaves out the Verification matrix rows on the file lines
/// [matrixCut] holds. An [imported] doc prints its stub line alone. With
/// [part] `without`, a record prints no Verification matrix section; with
/// `only`, its naming line and that section alone.
DocPrint _docBlock(
  DocIndex index,
  IndexedDoc doc,
  BundleMode mode, {
  required bool summary,
  required bool imported,
  required CitedByIndex? citedBy,
  required bool isTarget,
  required Set<int> matrixCut,
  _MatrixPart part = _MatrixPart.whole,
}) {
  if (imported) {
    return DocPrint(text: stubLine(doc), cited: const [], sections: const []);
  }
  final content = index.contentOf(doc);
  final docType = index.typeOf(doc);
  final matrixKey = docType == null ? null : verificationMatrixOf(docType)?.id;
  if (summary) {
    return summaryPrintOf(
      doc,
      content,
      docType,
      mode,
      citedBy,
      keyHeadings: true,
    ).afterLine(namingLine(doc, summary: true));
  }
  final parts = <String>[];
  if (mode != BundleMode.query && part != _MatrixPart.only) {
    final frontmatter = content.frontmatterText;
    if (frontmatter != null) parts.add(frontmatter.trimRight());
  }
  if ((mode != BundleMode.query || isTarget) && part != _MatrixPart.only) {
    final head = removeHtmlComments(content.head);
    if (head.trim().isNotEmpty) {
      parts.add(mode == BundleMode.query ? head.trim() : head.trimRight());
    }
  }
  final docEntry = citedBy == null ? null : citedDocIn(citedBy, doc);
  final docLines = citedLinesAfter(citedBy, [?docEntry])[0] ?? const [];
  final cited = <CitedItem>[?docEntry];
  final sections = <SectionLine>[];
  final held = citedSectionsOf(content, docType);
  // The naming line is the block's line 0.
  var line = 1 + docLines.length + lineAfterBlocks(parts);
  for (final section in keptSectionsOf(
    content,
    docType,
    mode,
    isTarget: isTarget,
  )) {
    final isMatrix = section.key == matrixKey;
    if (isMatrix ? part == _MatrixPart.without : part == _MatrixPart.only) {
      continue;
    }
    final print = sectionPrintOf(
      doc,
      content,
      held,
      section,
      citedBy,
      keyHeading: true,
      matrixCut: matrixCut,
    );
    cited.addAll(print.cited);
    sections.add(SectionLine(key: section.key, line: line));
    line += lineAfterBlocks([print.block]);
    parts.add(print.block);
  }
  final block = [namingLine(doc), ...docLines, parts.join('\n\n')].join('\n');
  return DocPrint(text: block, cited: cited, sections: sections);
}

/// Returns whether a split design [bundle] prints [doc] as a record whose
/// Verification matrix section goes to the refs text: a record printed whole,
/// not imported, that keeps the section.
bool _holdsMatrixPart(
  DocIndex index,
  Bundle bundle,
  IndexedDoc doc, {
  required bool imported,
}) {
  final docType = index.typeOf(doc);
  if (imported ||
      bundle.mode != BundleMode.design ||
      bundle.summaryOnly.contains(doc.docPath) ||
      docType == null) {
    return false;
  }
  final matrixKey = verificationMatrixOf(docType)?.id;
  if (matrixKey == null) return false;
  return keptSectionsOf(
    index.contentOf(doc),
    docType,
    bundle.mode,
    isTarget: bundle.targetPaths.contains(doc.docPath),
  ).any((section) => section.key == matrixKey);
}

/// Returns the file lines of the matrix rows [doc] leaves out of a [mode]
/// bundle that prints [wholePaths] whole; none in `query`.
Set<int> _matrixCutOf(
  DocIndex index,
  IndexedDoc doc,
  BundleMode mode,
  Set<String> wholePaths,
) => mode == BundleMode.query
    ? const {}
    : matrixLinesOutOfScope(index, doc, wholePaths);

/// Returns the DocPaths of the docs of [ordered] a bundle prints whole: all
/// but the ones in [Bundle.summaryOnly] and the imported ones, which print as
/// a stub.
Set<String> _wholePathsOf(List<IndexedDoc> ordered, Bundle bundle) => {
  for (final doc in ordered)
    if (!bundle.summaryOnly.contains(doc.docPath) && !bundle.isImported(doc))
      doc.docPath,
};

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

/// Returns [block], a printed block of [doc], with each section header line
/// [sections] locates in it set back to the header line the index holds, as a
/// JSON `text` keeps its headings verbatim.
///
/// It reads the lines [sections] gives, never a pattern, so a body line that
/// ends in `{#...}` stays.
String _withVerbatimHeadings(
  DocIndex index,
  IndexedDoc doc,
  List<SectionLine> sections,
  String block,
) {
  final headers = {
    for (final section in index.contentOf(doc).sections)
      section.key: section.headerLine,
  };
  final lines = block.split('\n');
  for (final SectionLine(:key, :line) in sections) {
    if (headers[key] case final header?) lines[line] = header;
  }
  return lines.join('\n');
}

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
