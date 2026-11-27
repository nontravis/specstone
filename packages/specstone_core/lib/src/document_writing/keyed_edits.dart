import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart' show Doc, KeyBlock;
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show opensHeadingItem;
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show withKeyBlock, withoutKeyBlocks;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart'
    show MatchedDocType;
import 'package:specstone_core/src/doc_model/list_block_writer.dart'
    show listBlockOf, listEntriesOf;
import 'package:specstone_core/src/document_writing/item_landing.dart'
    show requireUnchanged;
import 'package:specstone_core/src/document_writing/keyed_links.dart';
import 'package:specstone_core/src/document_writing/keyed_units.dart';
import 'package:specstone_core/src/document_writing/models/text_edit.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show rebaseDocLinks;
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show markDraft;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Edits

/// A doc a keyed move reads or writes, and its LF text before the move: its
/// text once the call's item edits ran.
final class KeyedDoc {
  const new(this.doc, this.text);

  final IndexedDoc doc;
  final String text;
}

/// What a keyed move writes: the edit of each doc by DocPath, and the address
/// each landing's units hold in their destination, in landing order.
final class KeyedWrites {
  const new(this.edits, this.landed);

  final Map<String, TextEdit> edits;

  /// `<section key>/<key>` as the write sets it, one per landing.
  final List<String> landed;
}

/// Returns the edit of each doc, by DocPath, the blocks and rows of
/// [landings] and the keyed [orders] change, and of each doc that links an
/// anchor they move, with the address each landing wrote.
///
/// [docs] holds every source, destination, and doc of [orders]. Each source
/// loses its units, each doc of [orders] takes its kept units in the order
/// of its addresses within each section, and each destination gains its units
/// last in its section of their key. A doc that gains or loses a unit is
/// marked draft. Each link to a heading whose anchor moves or changes reaches
/// it after the move, in [docs], their linkers, and [alsoFollowIn].
KeyedWrites keyedEdits(
  WriteSession session, {
  required List<KeyedLanding> landings,
  required Map<String, List<String>> orders,
  required List<KeyedDoc> docs,
  Iterable<IndexedDoc> alsoFollowIn = const [],
}) {
  if (docs.isEmpty) return const KeyedWrites({}, []);
  final reads = {
    for (final doc in docs) doc.doc.docPath: _Read.of(session, doc),
  };
  final pieces = [
    for (final landing in landings)
      _Pieces.of(reads[landing.from.docPath]!, landing),
  ];
  final moves = AnchorMoves();
  final written = {
    for (final read in reads.values)
      read.docPath: _Writer(
        session,
        read,
        reads,
        moves,
      ).write(pieces, orders[read.docPath] ?? const []),
  };
  final edits = <String, TextEdit>{
    for (final doc in _linkersOf(session.index, moves, alsoFollowIn))
      doc.docPath: (lfText) => withFollowedAnchors(lfText, doc.docPath, moves),
    for (final MapEntry(key: docPath, value: text) in written.entries)
      docPath: _writeEdit(
        reads[docPath]!,
        text,
        moves,
        draftType: _isDrafted(landings, docPath)
            ? _typeOf(session.index, reads[docPath]!.doc)
            : null,
      ),
  };
  return KeyedWrites(edits, [
    for (final piece in pieces) piece.landing.landedAddress,
  ]);
}

/// Returns the edit that writes [written], the text of [read] once its units
/// moved, with its links followed and marked a draft of [draftType] when
/// one is given.
///
/// The edit throws `RenderFault` `output_not_writable` for a text other than
/// the one [read] was planned from.
TextEdit _writeEdit(
  _Read read,
  String written,
  AnchorMoves moves, {
  required MergedDocType? draftType,
}) => (lfText) {
  requireUnchanged(read.doc, read.text, lfText);
  final followed = withFollowedAnchors(written, read.docPath, moves) ?? written;
  final text = draftType == null ? followed : markDraft(followed, draftType);
  return text == lfText ? null : text;
};

/// Whether the doc at [docPath] gains or loses a unit of [landings].
bool _isDrafted(List<KeyedLanding> landings, String docPath) => landings.any(
  (landing) => landing.from.docPath == docPath || landing.to.docPath == docPath,
);

/// Returns each doc that may link an anchor [moves] change: their linkers
/// and [alsoFollowIn].
Iterable<IndexedDoc> _linkersOf(
  DocIndex index,
  AnchorMoves moves,
  Iterable<IndexedDoc> alsoFollowIn,
) => {
  for (final docPath in moves.docPaths)
    if (index.at(docPath) case final doc?)
      for (final linker in index.linkingTo(doc)) linker.docPath: linker,
  for (final doc in alsoFollowIn) doc.docPath: doc,
}.values;

// MARK: - Reads

/// One doc as planned: its text, lines, units, and heading anchors.
final class _Read {
  new(this.doc, this.text, this.units, this.anchors);

  factory of(WriteSession session, KeyedDoc keyed) {
    final content = _contentOf(session, keyed.doc, keyed.text);
    return _Read(
      keyed.doc,
      keyed.text,
      keyedUnitsOf(content, _typeOf(session.index, keyed.doc)),
      headingAnchorsByLine(content),
    );
  }

  final IndexedDoc doc;
  final String text;
  final List<KeyedUnit> units;

  /// The heading anchor of each heading, by file line.
  final Map<int, String> anchors;

  String get docPath => doc.docPath;

  late final List<String> lines = text.split('\n');

  /// Returns the units [address] names.
  ///
  /// Throws `WriteFault` `item_not_found` when it holds none.
  List<KeyedUnit> unitsOf(String address) {
    final named = [
      for (final unit in units)
        if (unit.address == address) unit,
    ];
    if (named.isEmpty) throw keyedNotFoundOf(docPath, address);
    return named;
  }
}

/// A file line of a doc and the line it was read from, when there is one.
final class _Line {
  const new(this.text, [this.origin]);

  final String text;
  final _Origin? origin;
}

/// A file line of a doc as planned.
final class _Origin {
  const new(this.docPath, this.line);

  final String docPath;
  final int line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is _Origin && other.docPath == docPath && other.line == line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(docPath, line);
}

/// The lines one landing carries to its destination, rebased to it.
final class _Pieces {
  const new({
    required this.landing,
    required this.blocks,
    required this.rows,
    required this.tableHead,
    required this.paragraphs,
  });

  /// Reads the units of [landing] from [source].
  factory of(_Read source, KeyedLanding landing) {
    final units = source.unitsOf(landing.address);
    List<_Line> linesOf(LineRange span) =>
        _rebased(source, span, landing.to.docPath);
    final rows = units.whereType<RowUnit>().toList();
    final paragraphs = {for (final row in rows) ...row.spans.skip(1)}.toList()
      ..sort((a, b) => a.first.compareTo(b.first));
    final head = rows.firstOrNull?.headerLine;
    final landedKey = landing.landedKey;
    List<_Line> rowLinesOf(RowUnit row) {
      final lines = linesOf(row.spans.first);
      if (landedKey == null) return lines;
      return [
        for (final line in lines)
          _Line(_withFirstCell(line.text, row.key, landedKey), line.origin),
      ];
    }

    return _Pieces(
      landing: landing,
      blocks: [
        for (final block in units.whereType<BlockUnit>())
          linesOf(block.spans.single),
      ],
      rows: [for (final row in rows) ...rowLinesOf(row)],
      tableHead: head == null
          ? const []
          : linesOf(LineRange(first: head, last: head + 1)),
      paragraphs: [for (final span in paragraphs) linesOf(span)],
    );
  }

  final KeyedLanding landing;

  final List<List<_Line>> blocks;
  final List<_Line> rows;

  /// The header and delimiter rows of the rows' table; empty without rows.
  final List<_Line> tableHead;
  final List<List<_Line>> paragraphs;

  /// Returns the chunks the units add at a section's end: a new table of the
  /// rows when [hasTable] is false, the blocks, and the paragraphs.
  List<List<_Line>> chunks({required bool hasTable}) => [
    if (!hasTable && tableHead.isNotEmpty) [...tableHead, ...rows],
    ...blocks,
    ...paragraphs,
  ];
}

/// Returns the table [row] with [key] in its first cell set to [landedKey],
/// the cell's backticks kept.
String _withFirstCell(String row, String key, String landedKey) {
  final open = row.indexOf('|') + 1;
  final close = row.indexOf('|', open);
  final end = close < 0 ? row.length : close;
  return row.substring(0, open) +
      row.substring(open, end).replaceFirst(key, landedKey) +
      row.substring(end);
}

/// Returns the lines of [span] of [source], their links rebased to reach
/// from [toDocPath]; each keeps its origin while the rebase keeps the count.
List<_Line> _rebased(_Read source, LineRange span, String toDocPath) {
  final read = source.lines.sublist(span.first - 1, span.last);
  final rebased = rebaseDocLinks(
    read.join('\n'),
    fromDocPath: source.docPath,
    toDocPath: toDocPath,
  ).split('\n');
  final keepsLines = rebased.length == read.length;
  return [
    for (final (at, text) in rebased.indexed)
      _Line(text, keepsLines ? _Origin(source.docPath, span.first + at) : null),
  ];
}

// MARK: - Writer

/// Writes one doc of a keyed move and records where its headings go.
final class _Writer {
  const new(this.session, this.read, this.reads, this.moves);

  final WriteSession session;
  final _Read read;

  /// Every doc of the move as planned, by DocPath.
  final Map<String, _Read> reads;

  /// Where each heading anchor that changes goes; this doc's join it.
  final AnchorMoves moves;

  IndexedDoc get doc => read.doc;

  /// Returns the doc's text once its units leave, its kept units take
  /// [order], and [pieces] land in it.
  String write(List<_Pieces> pieces, List<String> order) {
    var lines = [
      for (final (at, text) in read.lines.indexed)
        _Line(text, _Origin(read.docPath, at + 1)),
    ];
    _cut(lines, [
      for (final piece in pieces)
        if (piece.landing.from.docPath == read.docPath)
          ...read.unitsOf(piece.landing.address),
    ]);
    lines = _reordered(lines, order);
    for (final piece in pieces) {
      if (piece.landing.to.docPath != read.docPath) continue;
      lines = _landed(lines, piece);
    }
    final text = _textOf(lines);
    _recordAnchors(lines, text);
    return _withMovedEntries(text, pieces);
  }

  /// Returns [text] with the `confirmed` entry of each rebased row of
  /// [pieces] gone when this doc is its source, and gained, under the row's
  /// landed key and its fingerprint kept, when this doc is its destination.
  String _withMovedEntries(String text, List<_Pieces> pieces) {
    final fieldOrder = [
      for (final field in _typeOf(session.index, doc).fields) field.id,
    ];
    var result = text;
    for (final KeyedLanding(:from, :to, :key, :landedKey) in [
      for (final piece in pieces) piece.landing,
    ]) {
      if (landedKey == null) continue;
      if (from.docPath == read.docPath) {
        result = _withoutEntries(read.docPath, result, key);
      }
      if (to.docPath != read.docPath) continue;
      final source = reads[from.docPath]!;
      final held = _entriesLabelled(source.docPath, source.text, key);
      if (held.isNotEmpty &&
          _entriesLabelled(read.docPath, result, landedKey).isNotEmpty) {
        throw IndexFault(
          IndexFaultCode.argumentInvalid,
          '${to.docPath} already holds a $_confirmedKey entry for $landedKey',
        );
      }
      result = _withEntries(read.docPath, result, [
        for (final entry in held) '$landedKey${entry.substring(key.length)}',
      ], fieldOrder);
    }
    return result;
  }

  /// Removes the lines of [units] from [lines], fresh from the doc's text; a
  /// blank line before and after a removed run leave one.
  void _cut(List<_Line> lines, List<KeyedUnit> units) {
    final runs = {for (final unit in units) ...unit.spans}.toList()
      ..sort((a, b) => b.first.compareTo(a.first));
    for (final run in runs) {
      lines.removeRange(run.first - 1, run.last);
      final at = run.first - 1;
      final isBlankBefore = at > 0 && isBlankLine(lines[at - 1].text);
      final isBlankAfter = at == lines.length || isBlankLine(lines[at].text);
      if (isBlankBefore && isBlankAfter) lines.removeAt(at - 1);
    }
  }

  /// Returns [lines] with the units [order] names in the order it names
  /// them, each taking the place of a kept unit of its section.
  List<_Line> _reordered(List<_Line> lines, List<String> order) {
    if (order.isEmpty) return lines;
    final byOrigin = {for (final line in lines) line.origin: line};
    final fills = <_Origin, List<_Line>>{};
    final taken = <_Origin>{};
    for (final _Slot(:slot, :fill) in _slotsOf(order)) {
      final span = slot.spans.first;
      final from = fill.spans.first;
      fills[_Origin(read.docPath, span.first)] = [
        for (var at = from.first; at <= from.last; at++)
          ?byOrigin[_Origin(read.docPath, at)],
      ];
      for (var at = span.first; at <= span.last; at++) {
        taken.add(_Origin(read.docPath, at));
      }
    }
    return [
      for (final line in lines)
        if (fills[line.origin] case final fill?)
          ...fill
        else if (!taken.contains(line.origin))
          line,
    ];
  }

  /// Returns each kept unit of [order], in file order, with the unit that
  /// takes its place: per section, the kept units sorted by [order], units
  /// of one address in file order.
  Iterable<_Slot> _slotsOf(List<String> order) sync* {
    final kept = [
      for (final unit in read.units)
        if (order.contains(unit.address)) unit,
    ];
    for (final sectionKey in {for (final unit in kept) unit.sectionKey}) {
      final slots = [
        for (final unit in kept)
          if (unit.sectionKey == sectionKey) unit,
      ];
      int rank(KeyedUnit unit) =>
          order.indexOf(unit.address) * slots.length + slots.indexOf(unit);
      final fills = [...slots]..sort((a, b) => rank(a).compareTo(rank(b)));
      for (final (at, slot) in slots.indexed) {
        yield _Slot(slot, fills[at]);
      }
    }
  }

  /// Returns [lines] with [piece] landed last in the section of its key, the
  /// section added at its template place when the doc lacks it.
  List<_Line> _landed(List<_Line> lines, _Pieces piece) {
    final content = _contentOf(session, doc, _textOf(lines));
    final type = _typeOf(session.index, doc);
    final section = keyedSectionsOf(
      content,
      type,
    ).where((section) => section.key == piece.landing.sectionKey).firstOrNull;
    return section == null
        ? _withSection(lines, content, type, piece)
        : _intoSection(lines, content, section, piece);
  }

  /// Returns [lines] with the rows of [piece] last in the last table of
  /// [section] and its other chunks at the section's end.
  List<_Line> _intoSection(
    List<_Line> lines,
    DocContent content,
    KeyedSection section,
    _Pieces piece,
  ) {
    final body = sectionBodyLines(
      content.sections,
      content.lineFacts,
      section.at,
    );
    final tableEnd = section.tableHeads.isEmpty
        ? null
        : _tableEnd(body, section.tableHeads.last);
    final filled = body.where((line) => !isBlankLine(line.text));
    final end = filled.isEmpty
        ? content.lineFacts.sectionLines[section.at]
        : filled.last.line;
    final result = [...lines]
      ..insertAll(end, [
        for (final chunk in piece.chunks(hasTable: tableEnd != null)) ...[
          const _Line(''),
          ...chunk,
        ],
      ]);
    if (tableEnd != null) result.insertAll(tableEnd, piece.rows);
    return result;
  }

  /// Returns [lines] with the section of [piece]'s key added holding its
  /// chunks: before the first section the doc holds that follows it in
  /// [type], else at the end.
  List<_Line> _withSection(
    List<_Line> lines,
    DocContent content,
    MergedDocType type,
    _Pieces piece,
  ) {
    final sectionKey = piece.landing.sectionKey;
    final template = type.sections.firstWhere((s) => s.id == sectionKey);
    final added = [
      _Line('## ${template.header}'),
      for (final chunk in piece.chunks(hasTable: false)) ...[
        const _Line(''),
        ...chunk,
      ],
    ];
    final before = _laterSectionLine(content, type, sectionKey);
    if (before != null) {
      return [
        ...lines.sublist(0, before - 1),
        ...added,
        const _Line(''),
        ...lines.sublist(before - 1),
      ];
    }
    final kept = [...lines];
    while (kept.isNotEmpty && isBlankLine(kept.last.text)) {
      kept.removeLast();
    }
    return [...kept, const _Line(''), ...added, const _Line('')];
  }

  /// Records in [moves] each heading of [text], whose lines are [lines],
  /// that came from another doc or whose anchor changed.
  void _recordAnchors(List<_Line> lines, String text) {
    final anchors = headingAnchorsByLine(_contentOf(session, doc, text));
    for (final MapEntry(key: line, value: anchor) in anchors.entries) {
      final origin = lines[line - 1].origin;
      if (origin == null) continue;
      final before = reads[origin.docPath]?.anchors[origin.line];
      if (before == null) continue;
      if (origin.docPath == read.docPath && before == anchor) continue;
      moves.add(origin.docPath, before, AnchorPlace(read.docPath, anchor));
    }
  }
}

/// A kept unit's place and the unit that takes it.
final class _Slot {
  const new(this.slot, this.fill);

  final KeyedUnit slot;
  final KeyedUnit fill;
}

/// Returns the file line of the last row of the table whose header row is
/// [head] in [body], its delimiter row when it has none; a blank line, a
/// fence, or a block heading ends the table.
int _tableEnd(List<BodyLine> body, int head) {
  var at = head - body.first.line + 1;
  while (at + 1 < body.length &&
      !body[at + 1].fenced &&
      !isBlankLine(body[at + 1].text) &&
      !opensHeadingItem(body[at + 1].text)) {
    at++;
  }
  return body[at].line;
}

/// Returns the header line of the first section [content] holds that follows
/// [sectionKey] in [type]; null when none does.
int? _laterSectionLine(
  DocContent content,
  MergedDocType type,
  String sectionKey,
) {
  final held = citedSectionsOf(content, type);
  for (final later
      in type.sections.skipWhile((s) => s.id != sectionKey).skip(1)) {
    final at = held.indexWhere((section) => section.key == later.id);
    if (at >= 0) return content.lineFacts.sectionLines[at];
  }
  return null;
}

// MARK: - Confirmed

const _confirmedKey = 'confirmed';

KeyBlock? _confirmedBlockOf(String lfText) =>
    Doc.parse(lfText).frontmatter
        ?.where((block) => block.name == _confirmedKey)
        .firstOrNull;

bool _isLabelled(Object? entry, String label) =>
    entry is String && entry.split(' ').first == label;

/// Returns the entries of [block], the `confirmed` block of the doc at
/// [docPath]; none for no block.
///
/// Throws [RenderFault] `output_not_writable` when it is no valid YAML, so a
/// move refuses before the journal rather than drop an entry it cannot place.
List<Object?> _entriesOf(String docPath, KeyBlock? block) {
  if (block == null) return const [];
  return listEntriesOf(block) ??
      (throw RenderFault(
        RenderFaultCode.outputNotWritable,
        'cannot write $docPath: its $_confirmedKey list is not valid YAML',
      ));
}

/// Returns each `confirmed` entry of [lfText], the text of the doc at
/// [docPath], that names [label].
List<String> _entriesLabelled(String docPath, String lfText, String label) => [
  for (final entry in _entriesOf(docPath, _confirmedBlockOf(lfText)))
    if (entry case final String text when _isLabelled(text, label)) text,
];

/// Returns [lfText], the text of the doc at [docPath], without its
/// `confirmed` entries that name [label]; the key goes with its last entry,
/// since a flow list takes no appended item.
String _withoutEntries(String docPath, String lfText, String label) {
  final block = _confirmedBlockOf(lfText);
  final held = _entriesOf(docPath, block);
  if (block == null) return lfText;
  final kept = [
    for (final entry in held)
      if (!_isLabelled(entry, label)) entry,
  ];
  if (kept.length == held.length) return lfText;
  return kept.isEmpty
      ? withoutKeyBlocks(lfText, [_confirmedKey])
      : withKeyBlock(
          lfText,
          _confirmedKey,
          listBlockOf(_confirmedKey, kept, onDisk: block),
        );
}

/// Returns [lfText], the text of the doc at [docPath], with [entries] added
/// at the end of its `confirmed` list, an absent key at its slot in
/// [fieldOrder].
String _withEntries(
  String docPath,
  String lfText,
  List<String> entries,
  List<String> fieldOrder,
) {
  if (entries.isEmpty) return lfText;
  final block = _confirmedBlockOf(lfText);
  final held = _entriesOf(docPath, block);
  return withKeyBlock(
    lfText,
    _confirmedKey,
    listBlockOf(_confirmedKey, [...held, ...entries], onDisk: block),
    fieldOrder: fieldOrder,
  );
}

String _textOf(List<_Line> lines) =>
    [for (final line in lines) line.text].join('\n');

/// Returns the content of [doc] as [lfText] holds it.
DocContent _contentOf(WriteSession session, IndexedDoc doc, String lfText) =>
    parseIndexedDoc(
      docPath: doc.docPath,
      bytes: utf8.encode(lfText),
      match: MatchedDocType(_typeOf(session.index, doc), target: doc.target),
    ).content;

MergedDocType _typeOf(DocIndex index, IndexedDoc doc) =>
    index.typeOf(doc) ?? (throw StateError('${doc.docPath} has no doc type'));
