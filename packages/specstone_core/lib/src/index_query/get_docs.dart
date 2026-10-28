import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _sectionSeparator = '#';

/// Returns the text of each doc [address] names, or of one of its sections.
///
/// [address] is a name as `resolve` takes it, then `#` and a section key to
/// keep that section of each doc that holds it. A whole doc prints as written.
/// Throws an [IndexFault] when no doc carries the name, or when no resolved
/// doc holds a section with the key.
ReadAnswer answerGet(DocIndex index, String address) {
  final hash = address.indexOf(_sectionSeparator);
  final name = hash < 0 ? address : address.substring(0, hash);
  final key = hash < 0 ? null : address.substring(hash + 1);

  final blocks = <_GetBlock>[];
  for (final doc in index.resolve(name)) {
    final content = index.contentOf(doc);
    final docType = index.typeOf(doc);
    if (key == null) {
      blocks.add(
        _GetBlock(doc, content.text, bases: basesOf(content, docType)),
      );
      continue;
    }
    final held = [
      for (final section in content.sections)
        if (section.key == key) section,
    ];
    if (held.isNotEmpty) {
      blocks.add(
        _GetBlock(
          doc,
          held.map((section) => '${section.text}\n').join(),
          base: baseHashOf(held.first.body),
        ),
      );
      continue;
    }
    final template = docType?.sections.where((s) => s.id == key).firstOrNull;
    if (template != null) {
      blocks.add(
        _GetBlock(doc, '## ${template.header}\n', base: emptyBaseHash),
      );
    }
  }
  if (blocks.isEmpty) {
    throw IndexFault(
      IndexFaultCode.sectionNotFound,
      'no doc named $name holds a section with the key $key',
    );
  }

  return ReadAnswer(
    text: [for (final block in blocks) block.printed].join('\n'),
    json: {
      'docs': [
        for (final block in blocks)
          {
            'name': block.doc.name,
            'docType': ?block.doc.docTypeId,
            'path': block.doc.docPath,
            'section': ?key,
            'base': ?block.base,
            'bases': ?block.bases,
            'text': block.text,
          },
      ],
    },
  );
}

/// Returns the base of the title, of each section, and of each field of a doc.
///
/// A base is the [baseHashOf] of the target's text: the title with no `# `,
/// a section's body, a field's whole key block. The result holds `title`,
/// `sections` keyed by section key, and `fields` keyed by field id. [docType],
/// when given, lists its sections and fields first, in its order, an absent
/// one with [emptyBaseHash]; held ones its template lacks follow in file order.
/// Of two sections or two field blocks sharing a key, the first counts; a doc
/// with no title has the base of empty text.
Map<String, Object> basesOf(DocContent content, MergedDocType? docType) {
  final doc = Doc.parse(toLf(content.text));

  final sections = <String, String>{
    for (final section in docType?.sections ?? const <MergedSection>[])
      section.id: emptyBaseHash,
  };
  final seen = <String>{};
  for (final section in content.sections) {
    if (seen.add(section.key)) sections[section.key] = baseHashOf(section.body);
  }

  final fields = <String, String>{
    for (final field in docType?.fields ?? const <MergedField>[])
      field.id: emptyBaseHash,
  };
  final seenFields = <String>{};
  for (final block in doc.frontmatter ?? const <KeyBlock>[]) {
    if (block.name.isNotEmpty && seenFields.add(block.name)) {
      fields[block.name] = baseHashOf(block.text);
    }
  }

  return {
    'title': baseHashOf(doc.title ?? ''),
    'sections': sections,
    'fields': fields,
  };
}

/// One doc `answerGet` prints: its [text] and the base or bases it names.
final class _GetBlock {
  const new(this.doc, this.text, {this.base, this.bases});

  final IndexedDoc doc;
  final String text;

  /// The base of the section [text] holds; null for a whole-doc read.
  final String? base;

  /// The bases of every target of the doc; null for a section read.
  final Map<String, Object>? bases;

  /// The naming line, then [text] ended by a line break.
  String get printed => '${namingLine(doc, base: base)}\n${_endedLine(text)}';
}

/// Returns [text] ended by a line break, adding one only when it lacks it.
String _endedLine(String text) => text.endsWith('\n') ? text : '$text\n';
