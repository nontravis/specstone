import 'package:specstone_core/src/doc_model/doc_items.dart'
    show opensHeadingItem;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show startsTable;
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show sectionItemsAt;
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Units

/// A unit of a section that carries no item ID, named by its section key
/// and its key.
sealed class KeyedUnit {
  const new({required this.sectionKey, required this.spans});

  /// The key of the section that holds the unit.
  final String sectionKey;

  /// The file lines the unit takes, in file order.
  final List<LineRange> spans;

  /// The key the unit is named by within its section.
  String get key;

  /// `<section key>/<key>`, as a plan line names the unit.
  String get address => '$sectionKey/$key';
}

/// A `###` block, keyed by its heading anchor.
final class BlockUnit extends KeyedUnit {
  const new({
    required super.sectionKey,
    required this.anchor,
    required super.spans,
  });

  final String anchor;

  @override
  String get key => anchor;
}

/// A table row, keyed by its first cell with its backticks dropped; it takes
/// each paragraph of its section that opens with that key in a code span.
///
/// Its first span is the row, each later span one such paragraph.
final class RowUnit extends KeyedUnit {
  const new({
    required super.sectionKey,
    required this.key,
    required this.headerLine,
    required super.spans,
  });

  @override
  final String key;

  /// The file line of its table's header row; the delimiter row follows it.
  final int headerLine;
}

/// The keyed units of one section and the tables outside its blocks.
final class KeyedSection {
  const new({
    required this.at,
    required this.key,
    required this.blocks,
    required this.tableHeads,
    required this.rows,
  });

  /// The index of the section among the held sections of its doc.
  final int at;
  final String key;
  final List<BlockUnit> blocks;

  /// The file line of the header row of each table outside [blocks].
  final List<int> tableHeads;

  /// The rows of its one table; none when it holds another count of tables.
  final List<RowUnit> rows;

  /// Its blocks and rows in file order.
  List<KeyedUnit> get units =>
      <KeyedUnit>[...blocks, ...rows]
        ..sort((a, b) => a.spans.first.first.compareTo(b.spans.first.first));
}

/// Returns the blocks and rows of [content], a doc of [type], in file order.
///
/// A section whose items carry IDs, and a story's acceptance criteria, give
/// none. Only a section that holds one table outside its blocks gives rows.
List<KeyedUnit> keyedUnitsOf(DocContent content, MergedDocType type) => [
  for (final section in keyedSectionsOf(content, type)) ...section.units,
];

/// Returns each section of [content], a doc of [type], that holds keyed
/// units, in file order.
List<KeyedSection> keyedSectionsOf(DocContent content, MergedDocType type) {
  final anchors = headingAnchorsByLine(content);
  return [
    for (final (at, section) in citedSectionsOf(content, type).indexed)
      if (section.prefixId == null && !section.isAcceptanceCriteria)
        _keyedSectionOf(content, type, at, section.key, anchors),
  ];
}

/// Returns the heading anchor of each heading of [content], by file line.
Map<int, String> headingAnchorsByLine(DocContent content) {
  final lines = content.lineFacts.headingLines;
  final slugs = content.lineFacts.anchors?.headingSlugs;
  if (lines == null || slugs == null) return const {};
  return {for (final (at, line) in lines.indexed) line: slugs[at]};
}

KeyedSection _keyedSectionOf(
  DocContent content,
  MergedDocType type,
  int at,
  String sectionKey,
  Map<int, String> anchors,
) {
  final body = sectionBodyLines(content.sections, content.lineFacts, at);
  final items = sectionItemsAt(content, at, type);
  final blocks = _blocksOf(items, body, sectionKey, anchors);
  bool isInBlock(int line) => blocks.any(
    (block) =>
        block.spans.single.first <= line && line <= block.spans.single.last,
  );
  final tableHeads = [
    for (final line in _tableHeadLines(body))
      if (!isInBlock(line)) line,
  ];
  return KeyedSection(
    at: at,
    key: sectionKey,
    blocks: blocks,
    tableHeads: tableHeads,
    rows: tableHeads.length != 1
        ? const []
        : _rowsOf(items, sectionKey, tableHeads.single, isInBlock),
  );
}

List<BlockUnit> _blocksOf(
  List<SectionItem> items,
  List<BodyLine> body,
  String sectionKey,
  Map<int, String> anchors,
) => [
  for (final item in items)
    if (item.kind == SectionItemKind.heading)
      if (anchors[item.line] case final anchor?)
        BlockUnit(
          sectionKey: sectionKey,
          anchor: anchor,
          spans: [LineRange(first: item.line, last: _blockEnd(body, item))],
        ),
];

List<RowUnit> _rowsOf(
  List<SectionItem> items,
  String sectionKey,
  int headerLine,
  bool Function(int line) isInBlock,
) => [
  for (final item in items)
    if (item.kind == SectionItemKind.tableRow && !isInBlock(item.line))
      if (_rowKeyOf(item) case final key? when key.isNotEmpty)
        RowUnit(
          sectionKey: sectionKey,
          key: key,
          headerLine: headerLine,
          spans: [
            LineRange(first: item.line, last: item.line),
            for (final paragraph in items)
              if (paragraph.kind == SectionItemKind.paragraph &&
                  !isInBlock(paragraph.line) &&
                  paragraph.head.startsWith('`$key`'))
                LineRange(first: paragraph.line, last: _lastLineOf(paragraph)),
          ],
        ),
];

String? _rowKeyOf(SectionItem row) =>
    row.cells?.firstOrNull?.replaceAll('`', '').trim();

int _lastLineOf(SectionItem item) =>
    item.line + item.text.split('\n').length - 1;

/// Returns the last non-blank file line of the block [head] opens: up to the
/// next unfenced heading item line, or the section's last.
int _blockEnd(List<BodyLine> body, SectionItem head) {
  final next = body
      .where((line) => line.line > head.line)
      .where((line) => !line.fenced && opensHeadingItem(line.text))
      .firstOrNull;
  var end = next == null ? body.last.line : next.line - 1;
  while (end > head.line && isBlankLine(body[end - body.first.line].text)) {
    end--;
  }
  return end;
}

/// Returns the file line of each table header row of [body].
List<int> _tableHeadLines(List<BodyLine> body) => [
  for (var k = 0; k + 1 < body.length; k++)
    if (!body[k].fenced &&
        !body[k + 1].fenced &&
        !isBlankLine(body[k].text) &&
        startsTable(body[k].text, body[k + 1].text))
      body[k].line,
];

/// Whether [line] holds only whitespace.
bool isBlankLine(String line) => line.trim().isEmpty;

// MARK: - Judging

/// Where one keyed unit address of a plan lands.
final class KeyedLanding {
  const new({
    required this.from,
    required this.to,
    required this.sectionKey,
    required this.key,
    this.landedKey,
  });

  /// The doc the units leave and the doc they land in.
  final IndexedDoc from;
  final IndexedDoc to;

  final String sectionKey;

  /// The key the plan line writes; the units are found in [from] by it.
  final String key;

  /// The key the units hold in [to] when it differs from [key]: an `fr_trace`
  /// row's FR cell, rebased to the feature of [to]. Null otherwise.
  final String? landedKey;

  /// `<section key>/<key>`, as a plan line names the units.
  String get address => '$sectionKey/$key';

  /// `<section key>/<key>` as [to] holds the units.
  String get landedAddress => '$sectionKey/${landedKey ?? key}';

  /// Whether [unit] is one of the units this landing moves.
  bool takes(KeyedUnit unit) => unit.address == address;
}

/// Returns the fault for a doc at [docPath] that holds no unit [address].
WriteFault keyedNotFoundOf(String docPath, String address) =>
    WriteFault(WriteFaultCode.itemNotFound, '$docPath holds no $address');

/// Returns the units of [doc] that [address], `<section key>/<key>`, names.
///
/// Throws [WriteFault] `item_not_found` when it holds none.
List<KeyedUnit> requireKeyedUnits(
  DocIndex index,
  IndexedDoc doc,
  String address,
) {
  final type = index.typeOf(doc);
  final units = type == null
      ? const <KeyedUnit>[]
      : [
          for (final unit in keyedUnitsOf(index.contentOf(doc), type))
            if (unit.address == address) unit,
        ];
  if (units.isNotEmpty) return units;
  throw keyedNotFoundOf(doc.docPath, address);
}

/// Throws [IndexFault] `argument_invalid` when [landing]'s destination,
/// holding [content] as a doc of [type], cannot take [units].
///
/// It cannot when its type has no section of their key, when that section
/// holds two or more tables and [units] hold a row, or when it already holds
/// a unit of their key.
void requireKeyedRoom(
  KeyedLanding landing,
  MergedDocType? type,
  DocContent content,
  List<KeyedUnit> units,
) {
  final KeyedLanding(:to, :sectionKey, :address, :landedAddress) = landing;
  if (type == null || !type.sections.any((s) => s.id == sectionKey)) {
    throw _roomFault('${to.docPath} has no $sectionKey section for $address');
  }
  final section = keyedSectionsOf(
    content,
    type,
  ).where((section) => section.key == sectionKey).firstOrNull;
  if (section == null) return;
  if (units.any((unit) => unit is RowUnit) && section.tableHeads.length > 1) {
    throw _roomFault(
      '${to.docPath} holds two or more tables in its $sectionKey section, '
      'so it takes no row $address',
    );
  }
  if (section.units.any((unit) => unit.address == landedAddress)) {
    throw _roomFault('${to.docPath} already holds $landedAddress');
  }
}

IndexFault _roomFault(String message) =>
    IndexFault(IndexFaultCode.argumentInvalid, message);
