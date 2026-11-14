import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _htmlComment = RegExp(r'<!--[\s\S]*?-->');

/// Returns the text a summary of [doc] prints after its naming line: its
/// `# ` title line, then its summary sections, one blank line apart (INV-25).
String summaryBodyOf(
  IndexedDoc doc,
  DocContent content,
  MergedDocType? docType,
  BundleMode mode,
) {
  final title = doc.title;
  return [
    if (title != null) '# $title',
    for (final section in summarySectionsOf(content, docType, mode))
      sectionBlockOf(section),
  ].join('\n\n');
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
String sectionBlockOf(IndexedSection section) =>
    '${section.headerLine}\n${removeHtmlComments(section.body).trimRight()}';

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
  final code = _codeRanges(text);
  final kept = StringBuffer();
  var from = 0;
  var search = 0;
  while (true) {
    final comment = _htmlComment.allMatches(text, search).firstOrNull;
    if (comment == null) break;
    if (code.any((r) => r.start <= comment.start && comment.start < r.end)) {
      search = comment.start + 1;
      continue;
    }
    kept.write(text.substring(from, comment.start));
    from = search = comment.end;
  }
  return (kept..write(text.substring(from))).toString();
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
