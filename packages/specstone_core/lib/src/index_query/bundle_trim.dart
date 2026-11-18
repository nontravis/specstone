import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/html_comments.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show CitedSection, citedSectionsOf;
import 'package:specstone_core/src/index_query/line_facts.dart' show LineRange;
import 'package:specstone_core/src/index_query/models/cited_item.dart';
import 'package:specstone_core/src/index_query/summary_cut.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

export 'package:specstone_core/src/index_query/html_comments.dart'
    show removeHtmlComments;

/// A `##` section a printed text holds whole, with the line its header sits
/// on, counted from 0 at the text's first line.
final class SectionLine {
  const new({required this.key, required this.line});

  final String key;
  final int line;

  /// Returns this section [lines] lines lower in the text.
  SectionLine shiftedBy(int lines) => SectionLine(key: key, line: line + lines);

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is SectionLine && other.key == key && other.line == line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(key, line);
}

/// One `##` section as a bundle prints it, with the places of it that carry
/// cited-by lines.
final class SectionPrint {
  const new({required this.block, required this.cited});

  final String block;
  final List<CitedItem> cited;
}

/// One doc as a bundle prints it, with the places of it that carry cited-by
/// lines and the `##` sections it prints whole.
final class DocPrint {
  const new({required this.text, required this.cited, required this.sections});

  final String text;
  final List<CitedItem> cited;
  final List<SectionLine> sections;

  /// Returns this print with [line] before its text, each section one line
  /// lower.
  DocPrint afterLine(String line) => DocPrint(
    text: '$line\n$text',
    cited: cited,
    sections: [for (final section in sections) section.shiftedBy(1)],
  );
}

/// Returns the number of lines [text] spans.
int lineCountOf(String text) => '\n'.allMatches(text).length + 1;

/// Returns the line, counted from 0, where a block joined after [blocks] by
/// one blank line starts.
int lineAfterBlocks(Iterable<String> blocks) =>
    blocks.fold(0, (line, block) => line + lineCountOf(block) + 1);

/// Returns the text a summary of [doc] prints after its naming line: the
/// lines [citedBy] holds for the whole doc, its `# ` title line, then its
/// summary sections, one blank line apart, with the places [citedBy] holds
/// lines for printed there, and the line each section starts on.
DocPrint summaryPrintOf(
  IndexedDoc doc,
  DocContent content,
  MergedDocType? docType,
  BundleMode mode,
  CitedByIndex? citedBy,
) {
  final title = doc.title;
  final held = citedSectionsOf(content, docType);
  final blocks = [if (title != null) '# $title'];
  final docEntry = citedBy == null ? null : citedDocIn(citedBy, doc);
  final docLines = citedLinesAfter(citedBy, [?docEntry])[0] ?? const [];
  final cited = <CitedItem>[?docEntry];
  final sections = <SectionLine>[];
  var line = docLines.length + lineAfterBlocks(blocks);
  for (final section in summarySectionsOf(content, docType, mode)) {
    final print = sectionPrintOf(
      doc,
      content,
      held,
      section,
      citedBy,
      summaryRows: summaryRowCountOf(docType, section.key),
    );
    sections.add(SectionLine(key: section.key, line: line));
    line += lineAfterBlocks([print.block]);
    blocks.add(print.block);
    cited.addAll(print.cited);
  }
  return DocPrint(
    text: [...docLines, blocks.join('\n\n')].join('\n'),
    cited: cited,
    sections: sections,
  );
}

/// Returns [section] of [doc], whose held sections [held] reads, as a bundle
/// prints it, with the lines [citedBy] holds for the section after its header
/// line and for its items and `###` blocks after them.
///
/// With [summaryRows], the section prints cut by [cutToRows], and only the
/// items and blocks whole inside the printed lines get a cited-by line.
/// [matrixCut] gives the file lines the Verification matrix section leaves out
/// (see [sectionBlockOf]).
SectionPrint sectionPrintOf(
  IndexedDoc doc,
  DocContent content,
  List<CitedSection> held,
  IndexedSection section,
  CitedByIndex? citedBy, {
  int? summaryRows,
  Set<int> matrixCut = const {},
}) {
  final at = content.sections.indexOf(section);
  final printed = summaryRows == null
      ? section
      : IndexedSection(
          key: section.key,
          headerLine: section.headerLine,
          body: cutToRows(section.body, summaryRows).body,
        );
  final items = citedBy == null
      ? const <CitedItem>[]
      : [
          ?citedSectionIn(citedBy, doc, content, held[at], at),
          ...citedItemsIn(
            citedBy,
            doc,
            content,
            held[at],
            at,
            within: summaryRows == null
                ? null
                : _bodyRangeOf(content, at, printed.body),
          ),
        ];
  final block = sectionBlockOf(
    printed,
    bodyLine: content.lineFacts.sectionLines[at] + 1,
    after: citedLinesAfter(citedBy, items),
    matrixCut: matrixCut,
  );
  return SectionPrint(block: block, cited: items);
}

/// Returns the kept sections of a summary doc whose merged section is a
/// summary section or sets `summary_rows`, in section order.
List<IndexedSection> summarySectionsOf(
  DocContent content,
  MergedDocType? docType,
  BundleMode mode,
) {
  final summaryIds = {
    for (final section in docType?.sections ?? const <MergedSection>[])
      if (section.summary == true || section.summaryRowCount != null)
        section.id,
  };
  return [
    for (final section in keptSectionsOf(content, docType, mode))
      if (summaryIds.contains(section.key)) section,
  ];
}

/// Returns the file lines of the body [printed] of the section at [at], which
/// starts on the line after its header.
LineRange _bodyRangeOf(DocContent content, int at, String printed) {
  final first = content.lineFacts.sectionLines[at] + 1;
  return (first: first, last: first + lineCountOf(printed) - 1);
}

/// Returns the `summary_rows` count of the merged section [key] of [docType],
/// or null when it sets none.
int? summaryRowCountOf(MergedDocType? docType, String key) {
  for (final section in docType?.sections ?? const <MergedSection>[]) {
    if (section.id == key) return section.summaryRowCount;
  }
  return null;
}

/// Returns [section] as a bundle prints it: its header line, the lines [after]
/// gives for the header's file line, then its body with HTML comments
/// removed, trimmed at its end.
///
/// [bodyLine] is the file line of the body's first line, and [after] gives
/// the lines to print after a file line (see [printedBodyOf]). The body leaves
/// out its lines on the file lines [matrixCut] holds, which are matrix rows,
/// so a section holding none of them prints whole.
String sectionBlockOf(
  IndexedSection section, {
  int bodyLine = 1,
  Map<int, List<String>> after = const {},
  Set<int> matrixCut = const {},
}) {
  final headerLine = bodyLine - 1;
  final body = printedBodyOf(
    matrixCut.isEmpty
        ? section.body
        : _withoutLines(section.body, bodyLine, matrixCut),
    firstLine: bodyLine,
    after: {
      for (final MapEntry(:key, :value) in after.entries)
        if (key != headerLine) key: value,
    },
  );
  return [section.headerLine, ...?after[headerLine], body].join('\n');
}

/// Returns [body], whose first line is file line [firstLine], less the lines on
/// [cutLines].
String _withoutLines(String body, int firstLine, Set<int> cutLines) => [
  for (final (i, text) in body.split('\n').indexed)
    if (!cutLines.contains(firstLine + i)) text,
].join('\n');

/// Returns the file lines of the Verification matrix rows of [record] that a
/// bundle printing [wholePaths] whole leaves out: each row whose item is an FR
/// of the record's feature that [wholePaths] does not hold.
///
/// A malformed line, a story's row, and the row of an unknown item are no
/// part of the answer. A doc that is no record has none.
Set<int> matrixLinesOutOfScope(
  DocIndex index,
  IndexedDoc record,
  Set<String> wholePaths,
) => {
  for (final entry in index.statusTree.recordEntriesAt(record.docPath))
    for (final row in entry.matrixRows)
      if (_frOfFeature(index, record.name, row.item) case final fr?)
        if (!wholePaths.contains(fr.docPath)) row.line,
};

/// Returns the FR [item] names in the feature [feature], or null when it names
/// none there.
IndexedDoc? _frOfFeature(DocIndex index, String feature, String item) {
  for (final fr in index.ofTypeNamed(frType, '$feature/$item')) {
    var holder = index.parentOf(fr);
    while (holder != null && holder.docTypeId != featureType) {
      holder = index.parentOf(holder);
    }
    if (holder?.name == feature) return fr;
  }
  return null;
}

/// Returns the sections [content] keeps for [mode], in its doc type's section
/// order, a section the type does not define after them in file order.
/// A section is kept unless, with HTML comments removed and both
/// ends trimmed, its body equals its merged section's `template` likewise
/// cleaned, or is `N/A`, or starts with `N/A —`; in `query` only the sections
/// whose merged section is a query section stay, unless [isTarget] names the
/// doc the call asks for, which keeps every section the other rules keep.
List<IndexedSection> keptSectionsOf(
  DocContent content,
  MergedDocType? docType,
  BundleMode mode, {
  bool isTarget = false,
}) {
  final merged = {
    for (final section in docType?.sections ?? const <MergedSection>[])
      section.id: section,
  };
  final kept = <IndexedSection>[];
  final undefined = <IndexedSection>[];
  for (final section in content.sections) {
    if (_kept(section, merged[section.key], mode, isTarget: isTarget)) {
      (merged.containsKey(section.key) ? kept : undefined).add(section);
    }
  }
  final inTemplateOrder = [
    for (final section in docType?.sections ?? const <MergedSection>[])
      for (final candidate in kept)
        if (candidate.key == section.id) candidate,
  ];
  return [...inTemplateOrder, ...undefined];
}

bool _kept(
  IndexedSection section,
  MergedSection? merged,
  BundleMode mode, {
  required bool isTarget,
}) {
  if (mode == BundleMode.query && !isTarget && merged?.query != true) {
    return false;
  }
  if (merged == null) return _naChecked(section.body);
  final body = _cleaned(section.body);
  final template = merged.template;
  if (template != null && body == _cleaned(template)) return false;
  return _naChecked(section.body);
}

bool _naChecked(String body) {
  final cleaned = _cleaned(body);
  return cleaned != 'N/A' && !cleaned.startsWith('N/A —');
}

/// Returns [text], whose first line is file line [firstLine], as a bundle
/// prints a body: HTML comments removed, trimmed at its end, and each of
/// [after]'s lines right after its file line.
///
/// A file line inside a removed comment, or past the trimmed end, takes its
/// lines at the nearest kept offset, so none is dropped.
String printedBodyOf(
  String text, {
  int firstLine = 1,
  Map<int, List<String>> after = const {},
}) {
  final printed = removeHtmlComments(text).trimRight();
  if (after.isEmpty) return printed;
  final comments = [
    for (final (:start, :end) in commentRangesOf(text))
      _CommentRange(start: start, end: end),
  ];
  final lineEnds = _lineEndsOf(text);
  final out = StringBuffer();
  var from = 0;
  final byLine = after.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  for (final MapEntry(key: line, value: lines) in byLine) {
    final end = lineEnds[(line - firstLine).clamp(0, lineEnds.length - 1)];
    final offset = _keptOffset(end, comments).clamp(from, printed.length);
    out
      ..write(printed.substring(from, offset))
      ..write('\n${lines.join('\n')}');
    from = offset;
  }
  return (out..write(printed.substring(from))).toString();
}

/// Returns the offset where each line of [text] ends, in line order.
List<int> _lineEndsOf(String text) {
  final ends = <int>[];
  for (var at = text.indexOf('\n'); at >= 0; at = text.indexOf('\n', at + 1)) {
    ends.add(at);
  }
  return ends..add(text.length);
}

/// An HTML comment's offsets in the original text, `end` past its last
/// character.
final class _CommentRange {
  const new({required this.start, required this.end});

  final int start;
  final int end;
}

/// Returns where [offset] of the original text falls once [comments] are
/// removed.
int _keptOffset(int offset, List<_CommentRange> comments) {
  var removed = 0;
  for (final _CommentRange(:start, :end) in comments) {
    if (start >= offset) break;
    removed += (end < offset ? end : offset) - start;
  }
  return offset - removed;
}

/// Returns [text] with HTML comments removed and both ends trimmed.
String _cleaned(String text) => removeHtmlComments(text).trim();
