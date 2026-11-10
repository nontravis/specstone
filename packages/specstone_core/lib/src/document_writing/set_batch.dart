import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show approvalHashOf;
import 'package:specstone_core/src/document_writing/batch_fault.dart';
import 'package:specstone_core/src/document_writing/batch_file.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/fault.dart';
import 'package:specstone_core/src/index_query/get_docs.dart'
    show basesOf, printedPart, sectionBaseOf;
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show startsWithUtf8Bom;
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The `key` a whole-doc block carries in its result and its fault line.
const _wholeDocKey = 'doc';

/// The `key` of a refused title block.
const _titleKey = 'title';

/// A byte-order mark as the one character a step's text may begin with.
const _byteOrderMark = '\uFEFF';

// MARK: - Public

/// Writes every changed block of [text], a `--batch` file read from
/// [batchPath], or none, and returns one result line per block in file order.
///
/// Each block is checked alone against its doc as it stands on disk under the
/// write lock; any refusal throws one [BatchFault] naming all, before a write.
/// Each doc a changed block reaches is written once, through one journal.
/// `json` is `{'blocks': [...]}`: `name`, `docType`, `path`, `key`, `base`,
/// `draft`, and `written` per block.
ReadAnswer answerSetBatch(
  WriteSession session, {
  required String batchPath,
  required String text,
}) {
  final parsed = parseBatchFile(batchPath, text);
  final refusals = <_Refusal>[
    for (final entry in parsed.lineFaults) (line: entry.line!, entry: entry),
  ];
  final planned = _planBlocks(session, parsed.blocks, refusals);
  if (planned.isEmpty) throw _refused(refusals);

  return session.locked(() {
    final checks = _checkDocs(session, planned, refusals);
    if (refusals.isNotEmpty) throw _refused(refusals);
    final writes = _writesOf(session, checks);
    final steps = [for (final write in writes.values) write.step];
    if (steps.isNotEmpty) MoveJournal(steps).run(session.journalTarget);
    return _answerOf(planned, checks, writes);
  });
}

// MARK: - Planning

/// A refused block or line and the line of the batch file it stands on.
typedef _Refusal = ({int line, BatchEntry entry});

/// One block resolved to the doc and the part it writes.
final class _Planned {
  const new(this.block, this.doc, this.docType, this.target);

  final BatchBlock block;
  final IndexedDoc doc;
  final MergedDocType docType;

  /// What the block writes: a section, the lead, a field, the title, or null
  /// for a whole doc. A field or the title is refused, but still resolved, so
  /// the overlap check names it.
  final SetTarget? target;

  bool get isWholeDoc => target == null;

  /// The section key, `_lead`, the field id, `title`, or `doc`.
  String get key => switch (target) {
    null => _wholeDocKey,
    SectionTarget(:final key) => key,
    LeadTarget() => leadKey,
    FieldTarget(:final fieldId) => fieldId,
    TitleTarget() => _titleKey,
  };

  /// Tells one part of a doc from another; a field named like a section is
  /// another part.
  String get partId => switch (target) {
    SectionTarget(:final key) => 'section:$key',
    FieldTarget(:final fieldId) => 'field:$fieldId',
    _ => key,
  };

  String get base => block.naming.base!;
}

BatchFault _refused(List<_Refusal> refusals) {
  final ordered = [...refusals]..sort((a, b) => a.line.compareTo(b.line));
  return BatchFault([for (final refusal in ordered) refusal.entry]);
}

void _refuse(
  List<_Refusal> refusals,
  BatchBlock block,
  SpecstoneFault fault, {
  required String file,
  required String key,
}) => refusals.add((
  line: block.line,
  entry: BatchEntry.fromFault(
    fault,
    file: file,
    key: fault is WriteFault ? fault.key ?? key : key,
  ),
));

/// Resolves each block of [blocks] and checks its text and its overlap with
/// the other blocks, as far as the text and the doc type decide, without the
/// doc's text or the lock.
///
/// A block refused adds to [refusals] and drops out of the result; it still
/// counts in the overlap check, so a twin of it is refused too.
List<_Planned> _planBlocks(
  WriteSession session,
  List<BatchBlock> blocks,
  List<_Refusal> refusals,
) {
  final resolved = [
    for (final block in blocks) ?_resolveBlock(session, block, refusals),
  ];
  for (final block in resolved) {
    if (_isRefused(refusals, block)) continue;
    _refuseOnFault(refusals, block, () => _checkText(block));
  }
  _refuseOverlaps(resolved, refusals);
  return [
    for (final block in resolved)
      if (!_isRefused(refusals, block)) block,
  ];
}

bool _isRefused(List<_Refusal> refusals, _Planned block) =>
    refusals.any((refusal) => refusal.line == block.block.line);

void _refuseOnFault(
  List<_Refusal> refusals,
  _Planned block,
  void Function() check,
) {
  try {
    check();
  } on SpecstoneFault catch (fault) {
    _refuse(
      refusals,
      block.block,
      fault,
      file: block.doc.docPath,
      key: block.key,
    );
  }
}

/// Resolves the doc [block] names; a block that names no doc adds a refusal
/// and gives null.
_Planned? _resolveBlock(
  WriteSession session,
  BatchBlock block,
  List<_Refusal> refusals,
) {
  final naming = block.naming;
  final (:docPart, :sectionKey) = session.index.splitAddress(naming.path);
  final partKey = sectionKey == null || sectionKey.isEmpty ? null : sectionKey;
  try {
    final doc = session.target(docPart);
    final docType =
        session.index.typeOf(doc) ??
        (throw StateError('${doc.docPath} is typed but its type is gone'));
    final target = switch ((naming.fieldId, naming.isTitle, partKey)) {
      (final fieldId?, _, _) => FieldTarget(fieldId),
      (_, true, _) => const TitleTarget(),
      (_, _, null) => null,
      (_, _, leadKey) => const LeadTarget(),
      (_, _, final section?) => SectionTarget(section),
    };
    return _Planned(block, doc, docType, target);
  } on SpecstoneFault catch (fault) {
    _refuse(
      refusals,
      block,
      fault,
      file: docPart,
      key: partKey ?? _wholeDocKey,
    );
    return null;
  }
}

/// Checks the text of [block] as far as the text and the doc type decide.
///
/// Throws [IndexFault] `argument_invalid` for a field or title block, which a
/// batch takes only inside the whole-doc block of its doc.
void _checkText(_Planned block) {
  switch (block.target) {
    case null:
      _checkWholeDocText(block.block.text);
    case FieldTarget() || TitleTarget():
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        'a block takes a section, the lead, or a whole doc; change a field '
        'or the title inside the whole-doc block of its doc',
      );
    case final target:
      checkPartText(
        doc: block.doc,
        docType: block.docType,
        target: target,
        text: block.block.text,
      );
  }
}

/// Throws [IndexFault] `argument_invalid` when [lf] leaves a fence open.
void _checkWholeDocText(String lf) {
  if (blockScan(lf.split('\n')).openFence case final fence?) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'the doc leaves the fence "$fence" open; close it',
    );
  }
}

/// Refuses every block that writes a part another block of its doc writes, a
/// whole-doc block counting as every part; each entry names the line of each
/// block it overlaps.
void _refuseOverlaps(List<_Planned> resolved, List<_Refusal> refusals) {
  bool overlaps(_Planned a, _Planned b) =>
      !identical(a, b) &&
      a.doc.docPath == b.doc.docPath &&
      (a.isWholeDoc || b.isWholeDoc || a.partId == b.partId);

  for (final block in resolved) {
    final lines = [
      for (final other in resolved)
        if (overlaps(block, other)) other.block.line,
    ];
    if (lines.isEmpty || _isRefused(refusals, block)) continue;
    final which = lines.length == 1
        ? 'the block at line ${lines.single} writes'
        : 'the blocks at lines ${lines.join(', ')} write';
    _refuse(
      refusals,
      block.block,
      IndexFault(
        IndexFaultCode.argumentInvalid,
        '$which the same part; send one block per part of a doc, and a '
        'whole-doc block alone for its doc',
      ),
      file: block.doc.docPath,
      key: block.key,
    );
  }
}

// MARK: - Checking

/// A doc as it stands on disk under the lock.
final class _Disk {
  new(this.bytes, this.parsed) : lfText = toLf(parsed.content.text);

  final List<int> bytes;
  final ParsedDoc parsed;

  /// The doc's text with LF line ends and no BOM.
  final String lfText;

  List<IndexedSection> get sections => parsed.content.sections;
}

/// What one block's check found: its doc as spliced and laid out, whether it
/// marks the doc a draft, and whether that differs from the doc on disk.
typedef _Checked = ({String lfText, bool marksDraft, bool isChanged});

/// One doc's blocks, its text on disk, and each block's check.
final class _DocCheck {
  const new(this.blocks, this.disk, this.results);

  final List<_Planned> blocks;
  final _Disk disk;
  final Map<_Planned, _Checked> results;

  IndexedDoc get doc => blocks.first.doc;
  MergedDocType get docType => blocks.first.docType;

  List<_Planned> get changed => [
    for (final block in blocks)
      if (results[block]!.isChanged) block,
  ];
}

/// Reads each doc of [planned] fresh and checks each of its blocks alone
/// against that text, adding a refusal for each fault.
Map<String, _DocCheck> _checkDocs(
  WriteSession session,
  List<_Planned> planned,
  List<_Refusal> refusals,
) {
  final groups = <String, List<_Planned>>{};
  for (final block in planned) {
    (groups[block.doc.docPath] ??= []).add(block);
  }
  final checks = <String, _DocCheck>{};
  for (final MapEntry(key: docPath, value: blocks) in groups.entries) {
    final disk = _readDisk(session, blocks, refusals);
    if (disk == null) continue;
    final results = _checkBlocks(session, blocks, disk, refusals);
    checks[docPath] = _DocCheck(blocks, disk, results);
  }
  return checks;
}

/// Reads the doc of [blocks] as it is now; null, with a refusal per block,
/// when its file is gone.
_Disk? _readDisk(
  WriteSession session,
  List<_Planned> blocks,
  List<_Refusal> refusals,
) {
  final first = blocks.first;
  final bytes = session.readDocBytes(first.doc.docPath);
  if (bytes != null) {
    return _Disk(
      bytes,
      parseIndexedDoc(
        docPath: first.doc.docPath,
        bytes: bytes,
        match: MatchedDocType(first.docType),
      ),
    );
  }
  final gone = IndexFault(
    IndexFaultCode.docNotFound,
    'no ${first.doc.docTypeId} doc carries the name ${first.doc.name}',
  );
  for (final block in blocks) {
    _refuse(
      refusals,
      block.block,
      gone,
      file: block.doc.docPath,
      key: block.key,
    );
  }
  return null;
}

Map<_Planned, _Checked> _checkBlocks(
  WriteSession session,
  List<_Planned> blocks,
  _Disk disk,
  List<_Refusal> refusals,
) {
  final docType = session.docTypeAt(blocks.first.doc.docPath);
  final onDisk = layOutDoc(disk.lfText, docType);
  final results = <_Planned, _Checked>{};
  for (final block in blocks) {
    // Unedited means what `get` prints now, decided before any check of the
    // part: an absent section's empty block is unchanged even when required.
    if (_isUneditedPart(block, disk)) {
      results[block] = (
        lfText: disk.lfText,
        marksDraft: false,
        isChanged: false,
      );
      continue;
    }
    try {
      final spliced = _splice(block, disk);
      results[block] = (
        lfText: spliced.lfText,
        marksDraft: spliced.marksDraft,
        isChanged: layOutDoc(spliced.lfText, docType) != onDisk,
      );
    } on SpecstoneFault catch (fault) {
      _refuse(
        refusals,
        block.block,
        fault,
        file: block.doc.docPath,
        key: block.key,
      );
    }
  }
  return results;
}

/// Whether [block] names a section or the lead with the base and the text
/// `get` prints for it now.
bool _isUneditedPart(_Planned block, _Disk disk) {
  if (block.target is! SectionTarget && block.target is! LeadTarget) {
    return false;
  }
  final printed = printedPart(
    block.doc,
    disk.parsed.content,
    block.docType,
    block.key,
  );
  return printed != null &&
      printed.base == block.base &&
      printed.text == block.block.text;
}

({String lfText, bool marksDraft}) _splice(_Planned block, _Disk disk) =>
    switch (block.target) {
      null => _spliceWholeDoc(block, disk),
      final target => splicePart(
        doc: block.doc,
        docType: block.docType,
        lfText: disk.lfText,
        sections: disk.sections,
        target: target,
        base: block.base,
        text: block.block.text,
      ),
    };

// MARK: - Whole-doc block

/// Checks the whole-doc [block] against [disk] and returns the doc it writes.
///
/// The block's base is `bases.doc`, the hash of the doc's LF text. Each field
/// block it adds, changes, or removes takes [checkFieldWrite]; each section it
/// removes takes the removal of a single `set`, which refuses a required one.
({String lfText, bool marksDraft}) _spliceWholeDoc(_Planned block, _Disk disk) {
  final currentBase = baseHashOf(disk.lfText);
  if (currentBase != block.base) {
    throw _staleDoc(block.doc, block.base, currentBase, disk.lfText);
  }
  final lfText = _wholeDocText(block.block.text, disk.lfText);
  final held = Doc.parse(disk.lfText);
  final proposed = Doc.parse(lfText);
  _checkTitleAndLead(block, held, proposed);
  final changedFields = _checkFields(block, held, proposed);
  _checkRemovedSections(block, disk, lfText);
  return (
    lfText: lfText,
    marksDraft: _marksDraft(block.docType, disk.lfText, lfText, changedFields),
  );
}

/// Returns the doc the block text [blockText] stands for.
///
/// The trailing blank lines of a block are spacing, so a block that holds the
/// doc on disk less its own trailing blank lines is that doc.
String _wholeDocText(String blockText, String diskLfText) =>
    blockText == '${withoutTrailingBlankLines(diskLfText)}\n'
    ? diskLfText
    : blockText;

WriteFault _staleDoc(
  IndexedDoc doc,
  String sinceBase,
  String currentBase,
  String currentText,
) => WriteFault(
  WriteFaultCode.baseMismatch,
  'the doc changed since base $sinceBase',
  file: doc.docPath,
  key: _wholeDocKey,
  current: CurrentTarget(
    heading: namingLine(doc, base: currentBase),
    text: currentText,
    base: currentBase,
  ),
);

/// Runs the title and the lead [proposed] holds through [checkPartText] when
/// they differ from [held], as a single `set` of either checks its text.
void _checkTitleAndLead(_Planned block, Doc held, Doc proposed) {
  void check(SetTarget target, String text) => checkPartText(
    doc: block.doc,
    docType: block.docType,
    target: target,
    text: text,
  );
  if (proposed.title != held.title) {
    check(const TitleTarget(), proposed.title ?? '');
  }
  if (proposed.lead != held.lead) check(const LeadTarget(), proposed.lead);
}

/// Checks each frontmatter key [proposed] adds, changes, or removes against
/// [held], and returns their ids.
List<String> _checkFields(_Planned block, Doc held, Doc proposed) {
  final before = _fieldBlocks(held);
  final after = _fieldBlocks(proposed);
  void check(String fieldId, String? value, {required bool isHeld}) =>
      checkFieldWrite(
        doc: block.doc,
        docType: block.docType,
        fieldId: fieldId,
        value: value,
        held: isHeld,
      );
  final changed = <String>[];
  for (final MapEntry(key: fieldId, value: next) in after.entries) {
    if (before[fieldId]?.text == next.text) continue;
    check(fieldId, next.indentedValueText, isHeld: before.containsKey(fieldId));
    changed.add(fieldId);
  }
  for (final fieldId in before.keys.where((id) => !after.containsKey(id))) {
    check(fieldId, null, isHeld: true);
    changed.add(fieldId);
  }
  return changed;
}

/// Returns the key blocks of [doc] by their YAML name, the first of two blocks
/// of one name counting, as `get` reads them.
Map<String, KeyBlock> _fieldBlocks(Doc doc) {
  final blocks = <String, KeyBlock>{};
  for (final block in doc.frontmatter ?? const <KeyBlock>[]) {
    if (block.name.isNotEmpty) blocks.putIfAbsent(block.name, () => block);
  }
  return blocks;
}

/// Runs the removal of each section of [disk] that [lfText] lacks through
/// [splicePart], which refuses a required one as a single `set` does.
void _checkRemovedSections(_Planned block, _Disk disk, String lfText) {
  final kept = {for (final s in _sectionsOf(block, lfText)) s.key};
  final removed = <String>{};
  for (final section in disk.sections) {
    // The first held section of a key is the one a single `set` of it reads.
    if (kept.contains(section.key) || !removed.add(section.key)) continue;
    splicePart(
      doc: block.doc,
      docType: block.docType,
      lfText: disk.lfText,
      sections: disk.sections,
      target: SectionTarget(section.key),
      base: sectionBaseOf(section.body, block.docType),
      text: '',
    );
  }
}

List<IndexedSection> _sectionsOf(_Planned block, String lfText) =>
    parseIndexedDoc(
      docPath: block.doc.docPath,
      bytes: utf8.encode(lfText),
      match: MatchedDocType(block.docType),
    ).content.sections;

/// Whether the write marks the doc a draft: false only when every change is an
/// `output_ref` field and the approval hash of the doc does not move, the one
/// rule `approval_stale` judges a content change by.
bool _marksDraft(
  MergedDocType docType,
  String heldText,
  String proposedText,
  List<String> changedFields,
) {
  final outputRefs = {
    for (final field in docType.fields)
      if (field.type == FieldType.outputRef) field.id,
  };
  final onlyOutputRefs =
      changedFields.isNotEmpty && changedFields.every(outputRefs.contains);
  return !onlyOutputRefs ||
      approvalHashOf(heldText, docType) !=
          approvalHashOf(proposedText, docType);
}

// MARK: - Writing

/// A doc's step and the text it writes.
typedef _Write = ({WriteStep step, String lfText});

/// Returns the write of each doc a changed block reaches, by DocPath.
///
/// Trust is checked first, so a project whose roots wait refuses with the
/// trust text before a path check names a different reason.
Map<String, _Write> _writesOf(
  WriteSession session,
  Map<String, _DocCheck> checks,
) {
  final writes = <String, _Write>{};
  for (final MapEntry(key: docPath, value: check) in checks.entries) {
    if (check.changed.isEmpty) continue;
    if (writes.isEmpty) session.journalTarget.requireTrusted();
    writes[docPath] = _writeOf(session, check);
  }
  return writes;
}

/// Returns the step of [check]'s doc: each changed block spliced in file
/// order onto the one before, the doc marked a draft when a block says so, laid
/// out, in its line ending and BOM, guarded by the text it replaces.
_Write _writeOf(WriteSession session, _DocCheck check) {
  final [first, ...rest] = check.changed;
  final firstResult = check.results[first]!;
  var lfText = firstResult.lfText;
  var marksDraft = firstResult.marksDraft;
  for (final next in rest) {
    // The base of a block is its part's, which no other block of the doc
    // changes, so each block checks against the text spliced so far.
    final part = splicePart(
      doc: next.doc,
      docType: next.docType,
      lfText: lfText,
      sections: _sectionsOf(next, lfText),
      target: next.target!,
      base: next.base,
      text: next.block.text,
    );
    lfText = part.lfText;
    marksDraft = marksDraft || part.marksDraft;
  }
  final docPath = check.doc.docPath;
  session.requireWritable(docPath);
  final laidOut = layOutDoc(
    marksDraft ? markDraft(lfText, check.docType) : lfText,
    session.docTypeAt(docPath),
  );
  final raw = check.disk.parsed.content.text;
  final bom = startsWithUtf8Bom(check.disk.bytes) ? _byteOrderMark : '';
  return (
    step: WriteStep(
      session.projectPathOf(docPath),
      '$bom${LineEnding.of(raw).apply(laidOut)}',
      before: textHashOf(raw),
    ),
    lfText: laidOut,
  );
}

// MARK: - Answer

/// Returns one result line and one JSON object per block of [planned], in
/// file order.
ReadAnswer _answerOf(
  List<_Planned> planned,
  Map<String, _DocCheck> checks,
  Map<String, _Write> writes,
) {
  final after = <String, ParsedDoc>{};
  final text = StringBuffer();
  final blocks = <Map<String, Object>>[];
  for (final block in planned) {
    final docPath = block.doc.docPath;
    final check = checks[docPath]!;
    final isWritten = check.results[block]!.isChanged;
    final doc = after[docPath] ??= switch (writes[docPath]) {
      final write? => parseIndexedDoc(
        docPath: docPath,
        bytes: utf8.encode(write.lfText),
        match: MatchedDocType(block.docType),
      ),
      null => check.disk.parsed,
    };
    final base = isWritten ? _baseOf(doc, block) : block.base;
    text.writeln(
      namingLine(
        block.doc,
        sectionKey: block.isWholeDoc ? null : block.key,
        base: base,
        unchanged: !isWritten,
      ),
    );
    blocks.add({
      'name': block.doc.name,
      'docType': ?block.doc.docTypeId,
      'path': docPath,
      'key': block.key,
      'base': base,
      'draft': doc.doc.isDraft,
      'written': isWritten,
    });
  }
  return ReadAnswer(text: text.toString(), json: {'blocks': blocks});
}

/// Returns the base `get` prints for the part [block] writes in [after].
String _baseOf(ParsedDoc after, _Planned block) {
  final bases = basesOf(after.content, block.docType);
  if (block.isWholeDoc) return bases['doc']! as String;
  final sections = bases['sections']! as Map<String, String>;
  return sections[block.key] ?? emptyBaseHash;
}
