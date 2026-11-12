import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/fault.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/layout.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

final _spaceTabEnd = RegExp(r'[ \t]+$');

/// Returns the text of each doc [names] address, or of one section of each.
///
/// Blocks print in argument order, each doc once; every name is resolved
/// before any prints. [codeTarget], when given, keeps each name to that code
/// target's docs and the shared docs. Throws an [IndexFault], or an
/// [IndexFaults] when the names hold faults of two or more codes, each fault
/// naming every name it covers.
ReadAnswer answerGet(DocIndex index, List<String> names, {String? codeTarget}) {
  final blocks = _printedOnce(_readAll(index, names, codeTarget));
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
///
/// A name's fault is an [IndexFault], or the `doc_type_unknown`
/// [TemplateFault] `resolve` throws; any other fault propagates.
List<List<_GetBlock>> _readAll(
  DocIndex index,
  List<String> names,
  String? codeTarget,
) {
  final reads = <List<_GetBlock>>[];
  final groups = <String, _FaultGroup>{};
  void collect(SpecstoneFault fault, String code, String message) =>
      (groups[code] ??= _FaultGroup(fault)).messages.add(message);
  for (final name in names) {
    try {
      reads.add(_readName(index, name, codeTarget));
    } on IndexFault catch (fault) {
      collect(fault, fault.code.wire, fault.message);
    } on TemplateFault catch (fault) {
      collect(fault, fault.code.wire, fault.message);
    }
  }
  final faults = [for (final group in groups.values) group.fault];
  return switch (faults) {
    [] => reads,
    [final fault] => throw fault,
    _ => throw IndexFaults(faults),
  };
}

/// The faults of one code: [first], and the distinct messages of all of them.
final class _FaultGroup {
  new(this.first);

  final SpecstoneFault first;
  final messages = <String>{};

  /// The fault that names every name of the group: [first] for one message,
  /// else one fault of its code holding the messages in first-name order.
  SpecstoneFault get fault {
    if (messages.length == 1) return first;
    final joined = messages.join('; ');
    return switch (first) {
      IndexFault(:final code) => IndexFault(code, joined),
      TemplateFault(:final code) => TemplateFault(code, joined),
      _ => first,
    };
  }
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
List<_GetBlock> _readName(DocIndex index, String address, String? codeTarget) {
  final (docPart: name, sectionKey: key) = index.splitAddress(address);

  final blocks = <_GetBlock>[];
  for (final doc in index.resolve(name, codeTarget: codeTarget)) {
    final content = index.contentOf(doc);
    final docType = index.typeOf(doc);
    if (key == null) {
      blocks.add(
        _GetBlock(doc, content.text, bases: basesOf(content, docType)),
      );
    } else if (_partBlock(doc, content, docType, key) case final part?) {
      blocks.add(part);
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

/// Returns the block `get` prints for the section [key] of [doc], or for its
/// lead when [key] is [leadKey]; null when the doc holds no such section and
/// its type has no template section of that key.
///
/// A template section the doc lacks prints its naming line alone, under the
/// base of empty text, so that block fed back unedited writes nothing.
_GetBlock? _partBlock(
  IndexedDoc doc,
  DocContent content,
  MergedDocType? docType,
  String key,
) {
  if (key == leadKey) {
    final parsed = Doc.parse(toLf(content.text));
    return _GetBlock(
      doc,
      parsed.lead,
      sectionKey: leadKey,
      base: leadBaseOf(parsed, docType),
      printsEmptyAsNothing: true,
    );
  }
  final held = [
    for (final section in content.sections)
      if (section.key == key) section,
  ];
  if (held.isNotEmpty) {
    return _GetBlock(
      doc,
      held.map((section) => '${section.text}\n').join(),
      sectionKey: key,
      base: sectionBaseOf(held.first.body, docType),
    );
  }
  if (docType?.sections.any((s) => s.id == key) ?? false) {
    return _GetBlock(
      doc,
      '',
      sectionKey: key,
      base: emptyBaseHash,
      printsEmptyAsNothing: true,
    );
  }
  return null;
}

/// Returns the base and the text `get` prints under the naming line for the
/// section [key] of [doc] as [content] holds it now, the lead when [key] is
/// [leadKey]; null when there is no such part.
///
/// A batch block whose base and text equal these is unedited.
({String base, String text})? printedPart(
  IndexedDoc doc,
  DocContent content,
  MergedDocType? docType,
  String key,
) {
  final block = _partBlock(doc, content, docType, key);
  return block == null
      ? null
      : (base: block.base!, text: block.afterNamingLine);
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

  /// Whether empty [text] prints as the naming line alone; true for a lead and
  /// for a template section the doc lacks.
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
    return '$line\n$afterNamingLine';
  }

  /// What `get` prints under the naming line: [text] ended by a line break,
  /// nothing for empty text that [printsEmptyAsNothing].
  String get afterNamingLine =>
      printsEmptyAsNothing && text.isEmpty ? '' : _endedLine(text);
}

/// Returns [text] ended by a line break, adding one only when it lacks it.
String _endedLine(String text) => text.endsWith('\n') ? text : '$text\n';
