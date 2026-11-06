import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/layout.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The result of formatting one doc.
sealed class FormatOutcome {
  const new();
}

/// A doc formatted to its template.
final class Formatted extends FormatOutcome {
  const new(this.text, this.sections);

  /// The formatted text, LF line endings.
  final String text;

  /// The laid-out sections in [text] order, as [Doc.parse] reads them there.
  final List<Section> sections;
}

/// A doc the formatter will not touch: its headers break the template, its
/// text ends inside a code fence, or a generated block it lists has no end.
final class Refused extends FormatOutcome {
  const new({
    this.unknownHeaders = const [],
    this.duplicateHeaders = const [],
    this.unclosedFence = false,
    this.openBlock,
    this.openBlockKind,
  });

  /// Headers the template does not define, as written, in file order.
  final List<String> unknownHeaders;

  /// Headers that occur more than once, in template form `## <header>`.
  final List<String> duplicateHeaders;

  /// Whether the doc ends inside a fenced code block.
  final bool unclosedFence;

  /// The opening marker, as written, of a generated block of a kind the doc
  /// type lists that has no end marker.
  final String? openBlock;

  /// The generator kind that [openBlock] names.
  final String? openBlockKind;
}

final _whitespaceRun = RegExp(r'\s+');

/// Returns [headerText] lowercased, trimmed, each whitespace run one space.
String headerKey(String headerText) =>
    headerText.trim().toLowerCase().replaceAll(_whitespaceRun, ' ');

/// Formats [doc] to the section and key order of [docType].
///
/// Refuses a doc whose headers are unknown or repeated, whose text ends
/// inside a code fence, or that opens a generated block of a kind [docType]
/// lists with no end marker (rendering INV-29), changing nothing.
/// Adds no section. Key blocks are copied as written; the head and every
/// section body get their layout whitespace normalized by [layOutText].
FormatOutcome formatDoc(Doc doc, MergedDocType docType) {
  // An open fence hides the headers after it, so the sections cannot be judged.
  if (doc.hasUnclosedFence) return const Refused(unclosedFence: true);
  final templateByKey = {
    for (final section in docType.sections) headerKey(section.header): section,
  };
  final refusal = _refusal(doc, templateByKey);
  if (refusal != null) return refusal;
  final kinds = docType.listedGenerators.toSet();
  final open = openBlockOf(doc, kinds);
  if (open != null) {
    return Refused(openBlock: open.marker, openBlockKind: open.kind);
  }

  final sectionByKey = {
    for (final section in doc.sections) headerKey(section.headerText): section,
  };
  final out = StringBuffer();
  final frontmatter = doc.frontmatter;
  if (frontmatter != null) {
    out
      ..write('---\n')
      ..writeAll(_orderedBlocks(frontmatter, docType).map((b) => b.text))
      ..write('---\n');
  }
  final head = layOutText(doc.head, blockKinds: kinds);
  if (head.isNotEmpty) out.write(_endWithLineBreak(head));
  final sections = <Section>[];
  for (final template in docType.sections) {
    final found = sectionByKey[headerKey(template.header)];
    if (found == null) continue;
    if (out.isNotEmpty) out.write('\n');
    final body = layOutText(found.body, underHeading: true, blockKinds: kinds);
    final section = Section('## ${template.header}', _endWithLineBreak(body));
    out.write('${section.headerLine}\n${section.body}');
    sections.add(section);
  }
  return Formatted(out.toString(), sections);
}

/// Returns [lfText] laid out as [formatDoc] lays it out for [docType].
///
/// Returns [lfText] unchanged when [docType] is null or [formatDoc] refuses
/// the doc.
String layOutDoc(String lfText, MergedDocType? docType) {
  if (docType == null) return lfText;
  return switch (formatDoc(Doc.parse(lfText), docType)) {
    Formatted(:final text) => text,
    Refused() => lfText,
  };
}

/// Whether [formatDoc] accepts [lfText] and [layOutDoc] leaves it unchanged.
///
/// [doc] is [lfText] as [Doc.parse] reads it, so a caller that holds the
/// parse does not parse again.
bool isLaidOut(Doc doc, String lfText, MergedDocType? docType) =>
    docType != null &&
    switch (formatDoc(doc, docType)) {
      Formatted(:final text) => text == lfText,
      Refused() => false,
    };

Refused? _refusal(Doc doc, Map<String, MergedSection> templateByKey) {
  final unknown = <String>[];
  final seen = <String>{};
  final repeated = <String>[];
  for (final section in doc.sections) {
    final key = headerKey(section.headerText);
    final template = templateByKey[key];
    if (template == null) {
      unknown.add('## ${section.headerText}');
    } else if (!seen.add(key) && !repeated.contains('## ${template.header}')) {
      repeated.add('## ${template.header}');
    }
  }
  if (unknown.isEmpty && repeated.isEmpty) return null;
  return Refused(unknownHeaders: unknown, duplicateHeaders: repeated);
}

/// Returns the keyless block first, then blocks of defined fields in field
/// order, then the rest in file order.
List<KeyBlock> _orderedBlocks(List<KeyBlock> blocks, MergedDocType docType) {
  final keyless = blocks.where((b) => b.key.isEmpty);
  final keyed = blocks.where((b) => b.key.isNotEmpty).toList();
  final defined = [
    for (final field in docType.fields)
      ...keyed.where((b) => b.name == field.id),
  ];
  final rest = keyed.where((b) => !defined.contains(b));
  return [...keyless, ...defined, ...rest];
}

String _endWithLineBreak(String text) =>
    text.isEmpty || text.endsWith('\n') ? text : '$text\n';
