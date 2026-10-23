import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The result of formatting one doc.
sealed class FormatOutcome {
  const new();
}

/// A doc formatted to its template.
final class Formatted extends FormatOutcome {
  const new(this.text);

  /// The formatted text, LF line endings.
  final String text;
}

/// A doc the formatter will not touch because its headers break the template.
final class Refused extends FormatOutcome {
  const new({required this.unknownHeaders, required this.duplicateHeaders});

  /// Headers the template does not define, as written, in file order.
  final List<String> unknownHeaders;

  /// Headers that occur more than once, in template form `## <header>`.
  final List<String> duplicateHeaders;
}

final _whitespaceRun = RegExp(r'\s+');
final _trailingBlankLines = RegExp(r'(?:\n[ \t]*)+$');

/// Returns [headerText] lowercased, trimmed, each whitespace run one space.
String headerKey(String headerText) =>
    headerText.trim().toLowerCase().replaceAll(_whitespaceRun, ' ');

/// Formats [doc] to the section and key order of [docType].
///
/// Refuses a doc whose headers are unknown or repeated, changing nothing.
/// Bodies and key blocks are copied as written; only a missing required
/// section is added.
FormatOutcome formatDoc(Doc doc, MergedDocType docType) {
  final templateByKey = {
    for (final section in docType.sections) headerKey(section.header): section,
  };
  final refusal = _refusal(doc, templateByKey);
  if (refusal != null) return refusal;

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
  if (doc.head.isNotEmpty) out.write(_endWithLineBreak(doc.head));
  for (final template in docType.sections) {
    final found = sectionByKey[headerKey(template.header)];
    if (found == null && !template.required) continue;
    if (out.isNotEmpty) out.write('\n');
    final header = '## ${template.header}\n';
    out.write(
      found == null
          ? header + _addedBody(template.template)
          : header + _endWithLineBreak(found.body),
    );
  }
  return Formatted(out.toString());
}

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
      ...keyed.where((b) => _keyName(b.key) == field.id),
  ];
  final rest = keyed.where((b) => !defined.contains(b));
  return [...keyless, ...defined, ...rest];
}

/// Returns the key without the quotes YAML allows around it.
String _keyName(String key) {
  if (key.length < 2) return key;
  final quote = key[0];
  final quoted = (quote == '"' || quote == "'") && key.endsWith(quote);
  return quoted ? key.substring(1, key.length - 1) : key;
}

/// Returns the template text with trailing blank lines dropped, or nothing.
String _addedBody(String? template) {
  if (template == null) return '';
  final text = template.replaceFirst(_trailingBlankLines, '');
  return text.isEmpty ? '' : '$text\n';
}

String _endWithLineBreak(String text) =>
    text.isEmpty || text.endsWith('\n') ? text : '$text\n';
