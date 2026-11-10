import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/layout.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _spaceTabEnd = RegExp(r'[ \t]+$');

/// Returns the text of each doc [names] address, or of one of its sections.
///
/// A name is as `resolve` takes it, then `#` and a section key to keep that
/// section of each doc that holds it or defines it in its template, or
/// [leadKey] to keep the lead of every resolved doc, empty or not. A whole doc
/// prints as written. Blocks print in argument order, each once: a doc read
/// whole takes the place of the first name that names it or any of its parts,
/// and drops every section of it. Every name is resolved before anything
/// prints. Throws an [IndexFault] when the names hold faults of one code, an
/// [IndexFaults] when they hold faults of two or more, each fault naming every
/// name it covers: `doc_not_found` for a name no doc carries,
/// `section_not_found` when no resolved doc holds a section with the key.
ReadAnswer answerGet(DocIndex index, List<String> names) {
  final blocks = _printedOnce(_readAll(index, names));
  return ReadAnswer(
    text: [for (final block in blocks) block.printed].join('\n'),
    json: {
      'docs': [
        for (final block in blocks)
          {
            'name': block.doc.name,
            'docType': ?block.doc.docTypeId,
            'path': block.doc.docPath,
            'section': ?block.sectionKey,
            'base': ?block.base,
            'bases': ?block.bases,
            'text': block.text,
          },
      ],
    },
  );
}

/// Returns the blocks of every name, none read until all names resolved.
List<List<_GetBlock>> _readAll(DocIndex index, List<String> names) {
  final reads = <List<_GetBlock>>[];
  final messages = <IndexFaultCode, List<String>>{};
  for (final name in names) {
    try {
      reads.add(_readName(index, name));
    } on IndexFault catch (fault) {
      (messages[fault.code] ??= []).add(fault.message);
    }
  }
  final faults = [
    for (final MapEntry(:key, :value) in messages.entries)
      IndexFault(key, value.join('; ')),
  ];
  return switch (faults) {
    [] => reads,
    [final fault] => throw fault,
    _ => throw IndexFaults(faults),
  };
}

/// Returns [reads] flat, each doc once: a doc read whole stands for every part
/// of it, at the place of the first block that names the doc.
List<_GetBlock> _printedOnce(List<List<_GetBlock>> reads) {
  final blocks = [for (final read in reads) ...read];
  final whole = {
    for (final block in blocks)
      if (block.sectionKey == null) block.doc.docPath: block,
  };
  final seen = <(String, String?)>{};
  return [
    for (final block in blocks)
      if (whole[block.doc.docPath] ?? block case final printed
          when seen.add((printed.doc.docPath, printed.sectionKey)))
        printed,
  ];
}

/// Returns the blocks one [address] reads, one per doc it holds a part of.
List<_GetBlock> _readName(DocIndex index, String address) {
  final (docPart: name, sectionKey: key) = index.splitAddress(address);

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
    if (key == leadKey) {
      final parsed = Doc.parse(toLf(content.text));
      blocks.add(
        _GetBlock(
          doc,
          parsed.lead,
          sectionKey: leadKey,
          base: leadBaseOf(parsed, docType),
          printsEmptyAsNothing: true,
        ),
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
          sectionKey: key,
          base: sectionBaseOf(held.first.body, docType),
        ),
      );
      continue;
    }
    final template = docType?.sections.where((s) => s.id == key).firstOrNull;
    if (template != null) {
      blocks.add(
        _GetBlock(
          doc,
          '## ${template.header}\n',
          sectionKey: key,
          base: emptyBaseHash,
        ),
      );
    }
  }
  if (blocks.isEmpty) {
    throw IndexFault(
      IndexFaultCode.sectionNotFound,
      'no doc named $name holds a section with the key $key',
    );
  }
  return blocks;
}

/// Returns the base of the whole doc, of its title, of each section, and of
/// each field.
///
/// A base is the [baseHashOf] of the target's text: the whole text with LF
/// line ends, the title with no `# ` (see [titleBaseOf]), a section's body as
/// laid out (see [sectionBaseOf]), the lead as laid out (see [leadBaseOf]), a
/// field's whole key block.
/// The result holds `doc`, `title`, `sections` keyed by section key, and
/// `fields` keyed by field id. `approve --yes` checks `doc`. `sections`
/// lists [leadKey] first when the lead holds non-blank text. [docType],
/// when given, lists its sections and fields first, in its order, an absent
/// one with [emptyBaseHash]; held ones its template lacks follow in file order.
/// Of two sections or two field blocks sharing a key, the first counts; a doc
/// with no title has the base of empty text.
Map<String, Object> basesOf(DocContent content, MergedDocType? docType) {
  final lfText = toLf(content.text);
  final doc = Doc.parse(lfText);

  final sections = <String, String>{
    if (doc.lead.isNotEmpty) leadKey: leadBaseOf(doc, docType),
    for (final section in docType?.sections ?? const <MergedSection>[])
      section.id: emptyBaseHash,
  };
  final seen = <String>{};
  for (final section in content.sections) {
    if (seen.add(section.key)) {
      sections[section.key] = sectionBaseOf(section.body, docType);
    }
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
    'doc': baseHashOf(lfText),
    'title': titleBaseOf(doc.title),
    'sections': sections,
    'fields': fields,
  };
}

/// Returns the base of a section [body]: the hash of its laid-out text.
///
/// A non-empty laid-out body ends in a line break, as `format` writes it.
String sectionBaseOf(String body, MergedDocType? docType) =>
    _laidOutBase(body, underHeading: true, docType: docType);

/// Returns the base of [doc]'s lead: the hash of its laid-out text.
///
/// A non-empty laid-out lead ends in a line break, as `format` writes it.
String leadBaseOf(Doc doc, MergedDocType? docType) =>
    _laidOutBase(doc.lead, underHeading: doc.title != null, docType: docType);

String _laidOutBase(
  String text, {
  required bool underHeading,
  required MergedDocType? docType,
}) {
  final laid = layOutText(
    text,
    underHeading: underHeading,
    blockKinds: docType?.listedGenerators.toSet() ?? const {},
  );
  return baseHashOf(laid.isEmpty || laid.endsWith('\n') ? laid : '$laid\n');
}

/// Returns the base of a title: the hash of [title] without the spaces and
/// tabs at its end; the hash of empty text for null.
String titleBaseOf(String? title) =>
    baseHashOf((title ?? '').replaceFirst(_spaceTabEnd, ''));

/// One doc `answerGet` prints: its [text] and the base or bases it names.
final class _GetBlock {
  const new(
    this.doc,
    this.text, {
    this.sectionKey,
    this.base,
    this.bases,
    this.printsEmptyAsNothing = false,
  });

  final IndexedDoc doc;
  final String text;

  /// The key of the section [text] holds, `_lead` for the lead; null for a
  /// whole-doc read.
  final String? sectionKey;

  /// The base of the section [text] holds; null for a whole-doc read.
  final String? base;

  /// The bases of every target of the doc; null for a section read.
  final Map<String, Object>? bases;

  /// Whether empty [text] prints as the naming line alone; true for a lead.
  final bool printsEmptyAsNothing;

  /// The naming line, then [text] ended by a line break.
  ///
  /// The line names the target its base belongs to: the section, or the whole
  /// doc with its `doc` base.
  String get printed {
    final line = namingLine(
      doc,
      sectionKey: sectionKey,
      base: base ?? bases?['doc'] as String?,
    );
    return printsEmptyAsNothing && text.isEmpty
        ? '$line\n'
        : '$line\n${_endedLine(text)}';
  }
}

/// Returns [text] ended by a line break, adding one only when it lacks it.
String _endedLine(String text) => text.endsWith('\n') ? text : '$text\n';
