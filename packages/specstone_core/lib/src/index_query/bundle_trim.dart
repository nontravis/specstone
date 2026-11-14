import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show CitedSection, citedSectionsOf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _htmlComment = RegExp(r'<!--[\s\S]*?-->');

/// Returns the text a summary of [doc] prints after its naming line: its
/// `# ` title line, then its summary sections, one blank line apart (INV-25),
/// with the items [citedBy] holds lines for, each printed whole there.
({String text, List<CitedItem> cited}) summaryPrintOf(
  IndexedDoc doc,
  DocContent content,
  MergedDocType? docType,
  BundleMode mode,
  CitedByIndex? citedBy,
) {
  final title = doc.title;
  final held = citedSectionsOf(content, docType);
  final blocks = [if (title != null) '# $title'];
  final cited = <CitedItem>[];
  for (final section in summarySectionsOf(content, docType, mode)) {
    final print = sectionPrintOf(doc, content, held, section, citedBy);
    blocks.add(print.block);
    cited.addAll(print.cited);
  }
  return (text: blocks.join('\n\n'), cited: cited);
}

/// Returns [section] of [doc], whose held sections [held] reads, as a bundle
/// prints it, with the lines [citedBy] holds for its items after them.
({String block, List<CitedItem> cited}) sectionPrintOf(
  IndexedDoc doc,
  DocContent content,
  List<CitedSection> held,
  IndexedSection section,
  CitedByIndex? citedBy,
) {
  final at = content.sections.indexOf(section);
  final items = citedBy == null
      ? const <CitedItem>[]
      : citedItemsIn(citedBy, doc, content, held[at], at);
  final block = sectionBlockOf(
    section,
    bodyLine: content.lineFacts.sectionLines[at] + 1,
    after: citedLinesAfter(items),
  );
  return (block: block, cited: items);
}

/// Returns the kept sections of a summary doc whose merged section is a
/// summary section, in section order (INV-25).
List<IndexedSection> summarySectionsOf(
  DocContent content,
  MergedDocType? docType,
  BundleMode mode,
) {
  final summaryIds = {
    for (final section in docType?.sections ?? const <MergedSection>[])
      if (section.summary == true) section.id,
  };
  return [
    for (final section in keptSectionsOf(content, docType, mode))
      if (summaryIds.contains(section.key)) section,
  ];
}

/// Returns [section] as a bundle prints it: its header line, then its body
/// with HTML comments removed, trimmed at its end.
///
/// [bodyLine] is the file line of the body's first line, and [after] gives
/// the lines to print after a file line (see [printedBodyOf]).
String sectionBlockOf(
  IndexedSection section, {
  int bodyLine = 1,
  Map<int, List<String>> after = const {},
}) =>
    '${section.headerLine}\n'
    '${printedBodyOf(section.body, firstLine: bodyLine, after: after)}';

/// Returns the sections [content] keeps for [mode], in its doc type's section
/// order, a section the type does not define after them in file order
/// (INV-15). A section is kept unless, with HTML comments removed and both
/// ends trimmed, its body equals its merged section's `template` likewise
/// cleaned, or is `N/A`, or starts with `N/A —`; in `query` only the sections
/// whose merged section is a query section stay (INV-14).
List<IndexedSection> keptSectionsOf(
  DocContent content,
  MergedDocType? docType,
  BundleMode mode,
) {
  final merged = {
    for (final section in docType?.sections ?? const <MergedSection>[])
      section.id: section,
  };
  final kept = <IndexedSection>[];
  final undefined = <IndexedSection>[];
  for (final section in content.sections) {
    if (_kept(section, merged[section.key], mode)) {
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

bool _kept(IndexedSection section, MergedSection? merged, BundleMode mode) {
  if (mode == BundleMode.query && merged?.query != true) return false;
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

/// Returns [text] with every HTML comment removed, except one whose `<!--`
/// sits in fenced code or an inline code span.
///
/// A comment runs to the first `-->` whatever it holds, so a backtick or a
/// fence line inside a comment never hides it.
String removeHtmlComments(String text) {
  final kept = StringBuffer();
  var from = 0;
  for (final (:start, :end) in _commentRangesOf(text)) {
    kept.write(text.substring(from, start));
    from = end;
  }
  return (kept..write(text.substring(from))).toString();
}

/// Returns [text], whose first line is file line [firstLine], as a bundle
/// prints a body: HTML comments removed, trimmed at its end, and each of
/// [after]'s lines right after its file line (INV-85).
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
  final comments = _commentRangesOf(text);
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

/// Returns where [offset] of the original text falls once [comments] are
/// removed.
int _keptOffset(int offset, List<({int start, int end})> comments) {
  var removed = 0;
  for (final (:start, :end) in comments) {
    if (start >= offset) break;
    removed += (end < offset ? end : offset) - start;
  }
  return offset - removed;
}

/// Returns the offsets of each HTML comment of [text] that
/// [removeHtmlComments] removes, in order.
List<({int start, int end})> _commentRangesOf(String text) {
  final code = _codeRanges(text);
  final ranges = <({int start, int end})>[];
  var search = 0;
  while (true) {
    final comment = _htmlComment.allMatches(text, search).firstOrNull;
    if (comment == null) break;
    if (code.any((r) => r.start <= comment.start && comment.start < r.end)) {
      search = comment.start + 1;
      continue;
    }
    ranges.add((start: comment.start, end: comment.end));
    search = comment.end;
  }
  return ranges;
}

/// Returns the offsets of each fenced line and each inline code span of [text].
List<({int start, int end})> _codeRanges(String text) {
  final lines = text.split('\n');
  final fenced = fencedLines([
    for (final line in lines) line.replaceFirst(RegExp(r'\r$'), ''),
  ]);
  final ranges = <({int start, int end})>[];
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    if (fenced[i]) {
      ranges.add((start: offset, end: offset + lines[i].length));
    } else {
      for (final (:start, :end, ticks: _) in codeSpansOf(lines[i])) {
        ranges.add((start: offset + start, end: offset + end));
      }
    }
    offset += lines[i].length + 1;
  }
  return ranges;
}

/// Returns [text] with HTML comments removed and both ends trimmed.
String _cleaned(String text) => removeHtmlComments(text).trim();
