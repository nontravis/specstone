import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_link_rules.dart'
    show CodeLink;
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show ownerTargetOf;
import 'package:specstone_core/src/consistency_check/contract_block.dart';
import 'package:specstone_core/src/consistency_check/edge_case_blocks.dart';
import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/matrix_form.dart';
import 'package:specstone_core/src/document_writing/code_judge.dart';
import 'package:specstone_core/src/document_writing/locked_doc_texts.dart';
import 'package:specstone_core/src/document_writing/remove_task_refs.dart'
    show removalsOf;
import 'package:specstone_core/src/document_writing/rewrite_records.dart'
    show readRecord;
import 'package:specstone_core/src/document_writing/stamp_fault.dart';
import 'package:specstone_core/src/document_writing/sync_lines.dart';
import 'package:specstone_core/src/document_writing/sync_record_lines.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/code_bundle.dart'
    show coveringDocsOf;
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/record_entries.dart'
    show
        recordCodeFieldOf,
        recordCodeLineOf,
        recordItemsOf,
        recordStatusFieldOf,
        recordStatusLineOf,
        recordTestFieldOf,
        recordTestLineOf;
import 'package:specstone_core/src/path_tail.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/matrix_mode.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

const _waitingHeader = 'Waiting:';
const _mismatchesHeader = 'Mismatches:';
const _keptHeader = 'Kept:';
const _unjudgedMessage =
    'the verdict is still ?; write match, planned, or mismatch';

// MARK: - Answer

/// Applies the lines of [parsed] in file order and writes each changed doc
/// once, drafts and approvals kept, through one journal; a file that changes
/// no doc writes neither. A line a pending draft covers waits; a task's refs
/// go once each of its links is written. Throws [SyncFault] of every refused
/// line, and [IndexFault] `argument_invalid` for an unknown [codeTarget].
ReadAnswer answerSetSync(
  WriteSession session,
  ParsedSync parsed, {
  String? codeTarget,
}) {
  session.index.checkCodeTarget(codeTarget);
  return session.locked(() {
    final texts = LockedDocTexts(session);
    final run = _SyncRun(session, texts, parsed.lines, codeTarget);
    final refusals = run.apply();
    if (refusals.isNotEmpty) throw SyncFault(parsed.path, refusals);
    final removals = removalsOf(session, texts, run.removable, codeTarget);
    final written = writeChangedDocs(session, texts);
    return _answerOf(written, run, removals.noRefs);
  });
}

// MARK: - Lines

/// The application of one file's lines to the docs they name, in file order.
final class _SyncRun {
  new(this._session, this._texts, this._lines, this._codeTarget);

  final WriteSession _session;
  final LockedDocTexts _texts;
  final List<SyncLine> _lines;
  final String? _codeTarget;
  final _docs = <String, IndexedDoc>{};
  final _judges = <String, CodeJudge>{};

  /// The stories and FRs of each record's feature, by the record's DocPath.
  final _items = <String, Map<String, IndexedDoc>>{};

  // Read on the first line that needs them, so a file of no such line reads
  // neither.
  late final MatrixMode _mode = _session.project.matrixMode;
  late final CheckContext _context = _session.checkContext();

  /// Each entry a `repoint` line moves, by doc and old pointer, to its new
  /// pointer; [_movedFrom] holds the reverse.
  final _movedTo = <String, String>{};
  final _movedFrom = <String, String>{};

  /// The `mismatch` lines as written, in file order.
  final mismatches = <String>[];

  /// The lines that wait on a pending draft, each as written then
  /// ` · waits for <doc address>`, in file order.
  final waiting = <String>[];

  /// Each kept task, by task id, to the `<doc> <entry>` links that kept it.
  final kept = <String, List<String>>{};

  /// The tasks whose refs go: each `remove-task` line naming one names a
  /// link a `match` or `planned` line writes, in file order.
  final removable = <String>{};

  /// The links a `match` or `planned` line writes, by doc and pointer.
  final _stampedLinks = <String>{};

  /// The `remove-task` lines that wait on no draft, in file order.
  final _removals = <_Removal>[];

  /// The tasks a waiting `remove-task` line names.
  final _waitingTasks = <String>{};

  /// Applies every line, settles each named task, and returns the refused
  /// lines in file order.
  List<SyncRefusal> apply() {
    _readRepoints();
    final refusals = _sameEntryRefusals();
    final refused = {for (final refusal in refusals) refusal.line};
    for (final line in _lines) {
      if (refused.contains(line.lineNumber)) continue;
      try {
        _apply(line);
      } on _Refused catch (fault) {
        refusals.add(fault.refusal);
      }
    }
    _settleTasks();
    return refusals..sort((a, b) => a.line.compareTo(b.line));
  }

  void _apply(SyncLine line) {
    switch (line) {
      case UnjudgedLine():
        throw _Refused(
          _refusal(line, WriteFaultCode.verdictUnjudged, _unjudgedMessage),
        );
      case final FingerprintedLine stamp:
        _stamp(stamp);
      case final MismatchLine mismatch:
        _requireEntry(mismatch);
        mismatches.add(_asWritten(line));
      case final RepointLine repoint:
        _repoint(repoint);
      case final TestsLine tests:
        _applyToRecord(
          tests,
          tests.record,
          tests.item,
          (text) => applyTestsLine(text.text, text.docType, tests),
        );
      case final RowLine row:
        _applyToRecord(
          row,
          row.record,
          row.item,
          (text) => applyRowLine(
            text.text,
            text.docType,
            row,
            mode: _mode,
            isRefusedForm: (matrixRow) =>
                isRefusedFormRow(_context, text.doc, matrixRow),
          ),
        );
      case final RemoveTaskLine removal:
        _remove(removal);
    }
  }

  /// Refuses `stamp_entry_unknown` when the doc of [line] holds its entry as
  /// no code link, under either path a `repoint` gives it, and no matrix row.
  void _requireEntry(VerdictLine line) {
    final doc = _docOf(line, line.doc);
    final text = _texts.of(doc);
    final fields = stampFieldsOf(text.text, stampableFieldsOf(text.docType));
    final isHeld =
        _heldPointerOf(fields, doc, line.entry) != null ||
        (_isRecord(text) &&
            matrixRowsNamed(text.text, text.docType, line.entry).isNotEmpty);
    if (!isHeld) throw _Refused(_unknown(line, doc, line.entry));
  }

  /// Holds [line] for [_settleTasks], or lists it as waiting while a doc that
  /// covers its link is a pending draft.
  void _remove(RemoveTaskLine line) {
    final doc = _docOf(line, line.doc);
    final fields = _linkFieldsOf(_texts.of(doc));
    if (_heldPointerOf(fields, doc, line.entry) == null) {
      throw _Refused(_unknown(line, doc, line.entry));
    }
    final draft = _draftCovering(doc, line.entry);
    if (draft != null) {
      _waitingTasks.add(line.task);
      return _wait(line, draft);
    }
    _removals.add(_Removal(line, _linkKey(doc, line.entry)));
  }

  /// Sorts each task the held `remove-task` lines name: kept while one of
  /// its links has no `match` or `planned` line written, else removable
  /// unless one of its lines waits.
  void _settleTasks() {
    for (final _Removal(:line, :link) in _removals) {
      if (_stampedLinks.contains(link)) continue;
      kept.putIfAbsent(line.task, () => []).add('${line.doc} ${line.entry}');
    }
    removable.addAll([
      for (final _Removal(:line) in _removals)
        if (!kept.containsKey(line.task) && !_waitingTasks.contains(line.task))
          line.task,
    ]);
  }

  /// Lists [line] under `Waiting:`, naming [draft].
  void _wait(SyncLine line, IndexedDoc draft) => waiting.add(
    '${_asWritten(line)} · waits for ${_session.index.addressOf(draft)}',
  );

  /// Returns the first pending draft, in DocPath order, of the docs that
  /// cover the code [entry] of [doc] names once the file's repoints apply;
  /// null when none is a draft or [doc] holds no such entry.
  IndexedDoc? _draftCovering(IndexedDoc doc, String entry) {
    final fields = _linkFieldsOf(_texts.of(doc));
    final pointer = _heldPointerOf(fields, doc, entry);
    if (pointer == null) return null;
    final field = fields.firstWhere(
      (field) => field.entries.any(
        (value) => value is String && _pointerOf(field, value) == pointer,
      ),
    );
    final link = _linkOf(doc, field, _movedTo[_key(doc, pointer)] ?? pointer);
    if (link == null) return null;
    final drafts = [
      for (final covering in coveringDocsOf(_session.index, link))
        if (covering.isDraft) covering,
    ]..sort((a, b) => a.docPath.compareTo(b.docPath));
    return drafts.firstOrNull;
  }

  /// Returns the fields of [text] whose entries name code: its `covers`-like
  /// fields, its record `implements`, and its record `tests`.
  List<StampField> _linkFieldsOf(LockedDocText text) => stampFieldsOf(
    text.text,
    [...stampableFieldsOf(text.docType), ?recordTestFieldOf(text.docType)],
  );

  /// Returns the code link [pointer] of [field] of [doc] names, as the
  /// covering-doc pick reads it; null when the field reads from no root.
  ///
  /// The pick reads only the link's path and root, so the link carries no
  /// file line and no fingerprint.
  CodeLink? _linkOf(IndexedDoc doc, StampField field, String pointer) {
    final project = _session.project;
    final isFromProject = readsFromProjectRoot(field.field);
    final target = isFromProject ? null : ownerTargetOf(doc, project.targets);
    final root = isFromProject
        ? project.projectRoot
        : target == null
        ? null
        : project.codeRootOf(target);
    if (root == null) return null;
    return CodeLink(
      field: field.field.id,
      line: 0,
      value: pointer,
      pointer: pointer,
      path: field.field.pointer == PointerKind.itemTest
          ? recordTestLineOf(pointer)?.path ?? pointer
          : field.pathOf(pointer),
      recorded: null,
      root: root,
      target: target,
    );
  }

  /// Returns the key of the link [entry] of [doc] names, its path the one a
  /// `repoint` line of the file gives it.
  String _linkKey(IndexedDoc doc, String entry) =>
      _key(doc, _movedTo[_key(doc, entry)] ?? entry);

  /// Ends the entry [line] names with its fingerprint once the judge passes
  /// it, at the path a `repoint` line of the file gives it; a judged line
  /// whose code a pending draft covers waits instead.
  void _stamp(FingerprintedLine line) {
    final doc = _docOf(line, line.doc);
    final text = _texts.of(doc);
    final fields = stampFieldsOf(text.text, stampableFieldsOf(text.docType));
    final pointer = _heldPointerOf(fields, doc, line.entry);
    if (pointer == null) return _stampRows(line, doc, text);
    final judged = _movedTo[_key(doc, pointer)] ?? pointer;
    var isRecordEntry = false;
    for (final field in fields) {
      for (final (at, value) in field.entries.indexed) {
        if (value is! String || _pointerOf(field, value) != pointer) continue;
        if (_judgeOf(doc).refusalOf(field, judged, line.fingerprint)
            case final refusal?) {
          throw _Refused(_stampRefusal(line, refusal));
        }
        field.entries[at] = codeLinkEntryOf(pointer, line.fingerprint);
        field.isStamped = true;
        isRecordEntry = isRecordEntry || field.isRecord;
      }
    }
    if (_draftCovering(doc, line.entry) case final draft?) {
      return _wait(line, draft);
    }
    _stampedLinks.add(_linkKey(doc, line.entry));
    final stamped = withStampedFields(text.text, fields);
    text.text = line is MatchLine && isRecordEntry
        ? _withImplemented(stamped, text.docType, pointer)
        : stamped;
  }

  /// Rewrites the path of the entry [line] names, its fingerprint kept; an
  /// entry already at its new path is left as it is, and one whose new code a
  /// pending draft covers waits.
  void _repoint(RepointLine line) {
    final doc = _docOf(line, line.doc);
    final text = _texts.of(doc);
    final fields = stampFieldsOf(text.text, [
      ...stampableFieldsOf(text.docType),
      ?recordTestFieldOf(text.docType),
    ]);
    final moved = _movedPointer(line.entry, line.newPath, text.docType);
    var isHeld = false;
    for (final field in fields) {
      for (final (at, value) in field.entries.indexed) {
        if (value is! String) continue;
        final pointer = _pointerOf(field, value);
        isHeld = isHeld || pointer == moved || pointer == line.entry;
        if (pointer != line.entry) continue;
        final fingerprint = pointer == value
            ? null
            : CodeLinkEntry(value).fingerprint;
        field.entries[at] = fingerprint == null
            ? moved
            : codeLinkEntryOf(moved, fingerprint);
        field.isStamped = true;
      }
    }
    if (!isHeld) throw _Refused(_unknown(line, doc, line.entry));
    if (_draftCovering(doc, line.entry) case final draft?) {
      return _wait(line, draft);
    }
    text.text = withStampedFields(text.text, fields);
  }

  /// Ends each matrix row the entry of [line] names with its fingerprint once
  /// it equals the fingerprint of the rows' block now; rows of an FR that is
  /// a pending draft wait.
  void _stampRows(FingerprintedLine line, IndexedDoc doc, LockedDocText text) {
    final rows = _isRecord(text)
        ? matrixRowsNamed(text.text, text.docType, line.entry)
        : const <MatrixRow>[];
    if (rows.isEmpty) throw _Refused(_unknown(line, doc, line.entry));
    if (_blockFingerprintOf(line, doc, rows.first) != line.fingerprint) {
      throw _Refused(
        _refusal(
          line,
          WriteFaultCode.stampStale,
          '${line.entry} changed after ${line.fingerprint}; judge it again',
        ),
      );
    }
    final fr = _itemOf(line, doc, rows.first.item);
    if (fr.isDraft) return _wait(line, fr);
    text.text = withRowsStamped(text.text, rows, line.fingerprint);
  }

  /// Returns the fingerprint `check` gives the block [row] of the record [doc]
  /// records: its FR's contract block, or its edge case.
  String _blockFingerprintOf(
    FingerprintedLine line,
    IndexedDoc doc,
    MatrixRow row,
  ) {
    final fr = _itemOf(line, doc, row.item);
    final edgeCase = row.edgeCase;
    final block = fr.docTypeId != frType
        ? null
        : edgeCase == null
        ? contractBlockOf(_context, fr)?.text
        : edgeCaseBlocksOf(_context, fr)[edgeCase];
    if (block == null) {
      throw _Refused(
        _refusal(
          line,
          WriteFaultCode.stampEntryUnresolved,
          '${line.entry} does not resolve: '
          '${FindingKind.matrixRowUnresolved.wire}',
        ),
      );
    }
    return fingerprintOf(block);
  }

  /// Sets the text of the record [address] names to what [apply] returns,
  /// once [item] names a story or FR of the record's feature.
  void _applyToRecord(
    SyncLine line,
    String address,
    String item,
    String Function(LockedDocText text) apply,
  ) {
    final doc = _docOf(line, address);
    final text = _texts.of(doc);
    if (!_isRecord(text)) {
      throw _Refused(
        SyncRefusal.invalid(line.lineNumber, '$address names no record'),
      );
    }
    _itemOf(line, doc, item);
    try {
      text.text = readRecord(doc.docPath, () => apply(text));
    } on IndexFault catch (fault) {
      throw _Refused(_faultRefusal(line, fault));
    } on RenderFault catch (fault) {
      throw _Refused(
        SyncRefusal(
          line: line.lineNumber,
          code: fault.code.wire,
          exitStatus: fault.code.exitStatus,
          message: fault.message,
        ),
      );
    }
  }

  /// Returns the story or FR [item] names under the feature of [record].
  IndexedDoc _itemOf(SyncLine line, IndexedDoc record, String item) {
    final items = _items.putIfAbsent(record.docPath, () {
      final feature = _session.index.parentOf(record);
      return feature == null || feature.docTypeId != featureType
          ? const <String, IndexedDoc>{}
          : recordItemsOf(feature, _session.index.childrenOf);
    });
    return items[item] ??
        (throw _Refused(
          _refusal(
            line,
            WriteFaultCode.stampEntryUnknown,
            '$item names no story or FR of the feature of '
            '${_session.index.addressOf(record)}',
          ),
        ));
  }

  bool _isRecord(LockedDocText text) =>
      text.docType.id == _session.index.set.recordDocType?.id;

  /// Records the old and new pointer of each `repoint` line whose doc
  /// resolves, so a verdict line may name its entry either way.
  void _readRepoints() {
    for (final line in _lines.whereType<RepointLine>()) {
      final IndexedDoc doc;
      try {
        doc = _docOf(line, line.doc);
      } on _Refused {
        continue;
      }
      final docType = _session.index.typeOf(doc);
      if (docType == null) continue;
      final moved = _movedPointer(line.entry, line.newPath, docType);
      _movedTo[_key(doc, line.entry)] = moved;
      _movedFrom[_key(doc, moved)] = line.entry;
    }
  }

  /// Returns a refusal for each `match` or `planned` line beside another
  /// verdict line of its entry named another way: by another address of its
  /// doc, or by the other path of a `repoint`.
  List<SyncRefusal> _sameEntryRefusals() {
    final seen = <String, List<VerdictLine>>{};
    final refusals = <SyncRefusal>[];
    for (final line in _lines.whereType<VerdictLine>()) {
      final IndexedDoc doc;
      try {
        doc = _docOf(line, line.doc);
      } on _Refused {
        continue;
      }
      final entry = _movedTo[_key(doc, line.entry)] ?? line.entry;
      final earlier = seen.putIfAbsent(_key(doc, entry), () => []);
      final clash = earlier
          .where((other) => _isStamp(line) || _isStamp(other))
          .firstOrNull;
      if (clash != null) {
        refusals.add(
          SyncRefusal.invalid(
            line.lineNumber,
            '${line.entry} already holds the verdict of line '
            '${clash.lineNumber}; a match or planned line stands alone',
          ),
        );
      }
      earlier.add(line);
    }
    return refusals;
  }

  /// Returns the pointer [fields] hold for [entry]: [entry] itself, else the
  /// other path a `repoint` line gives it; null when they hold neither.
  String? _heldPointerOf(
    List<StampField> fields,
    IndexedDoc doc,
    String entry,
  ) {
    final key = _key(doc, entry);
    for (final candidate in [entry, ?_movedTo[key], ?_movedFrom[key]]) {
      final isHeld = fields.any(
        (field) => field.entries.any(
          (value) => value is String && _pointerOf(field, value) == candidate,
        ),
      );
      if (isHeld) return candidate;
    }
    return null;
  }

  IndexedDoc _docOf(SyncLine line, String address) {
    if (_docs[address] case final doc?) return doc;
    try {
      return _docs[address] = _session.target(address, codeTarget: _codeTarget);
    } on IndexFault catch (fault) {
      throw _Refused(_faultRefusal(line, fault));
    }
  }

  CodeJudge _judgeOf(IndexedDoc doc) => _judges.putIfAbsent(
    doc.docPath,
    () => CodeJudge(_session, ownerTargetOf(doc, _session.project.targets)),
  );

  SyncRefusal _unknown(SyncLine line, IndexedDoc doc, String entry) => _refusal(
    line,
    WriteFaultCode.stampEntryUnknown,
    'no entry of ${_session.index.addressOf(doc)} reads $entry',
  );
}

String _key(IndexedDoc doc, String pointer) => '${doc.docPath}\u0000$pointer';

bool _isStamp(VerdictLine line) => line is MatchLine || line is PlannedLine;

/// Returns the pointer of [value], an entry of [field]: a `tests` entry
/// whole, any other entry before its fingerprint.
String _pointerOf(StampField field, String value) =>
    field.field.pointer == PointerKind.itemTest
    ? value
    : CodeLinkEntry(value).pointer;

/// Returns [pointer] with its path made [newPath]: a record entry keeps its
/// item, and its Symbol or test name unless [newPath] holds `:<symbol>`, which
/// replaces it.
String _movedPointer(String pointer, String newPath, MergedDocType docType) {
  final holdsItems =
      recordCodeFieldOf(docType) != null || recordTestFieldOf(docType) != null;
  final line = holdsItems ? recordCodeLineOf(pointer) : null;
  if (line == null) return newPath;
  final next = splitPathTail(newPath);
  final tail = next.tail ?? splitPathTail(line.code).tail;
  return '${line.item}:${next.path}${tail == null ? '' : ':$tail'}';
}

/// Returns [lfText] with the `planned` status of the item of [entry], a
/// record `implements` entry, set to `implemented`.
String _withImplemented(String lfText, MergedDocType docType, String entry) {
  final item = recordCodeLineOf(entry)?.item;
  final fields = stampFieldsOf(lfText, [?recordStatusFieldOf(docType)]);
  for (final field in fields) {
    for (final (at, value) in field.entries.indexed) {
      if (value is! String) continue;
      final status = recordStatusLineOf(value);
      if (status?.item != item || status?.status != RecordStatus.planned) {
        continue;
      }
      field.entries[at] = '$item:${RecordStatus.implemented.wire}';
      field.isStamped = true;
    }
  }
  return withStampedFields(lfText, fields);
}

SyncRefusal _refusal(SyncLine line, WriteFaultCode code, String message) =>
    SyncRefusal(
      line: line.lineNumber,
      code: code.wire,
      exitStatus: code.exitStatus,
      message: message,
    );

SyncRefusal _faultRefusal(SyncLine line, IndexFault fault) => SyncRefusal(
  line: line.lineNumber,
  code: fault.code.wire,
  exitStatus: fault.code.exitStatus,
  message: fault.message,
);

SyncRefusal _stampRefusal(SyncLine line, StampRefusal refusal) =>
    _refusal(line, refusal.code, refusal.message);

/// A line the run refuses, thrown to end that line's apply.
final class _Refused implements Exception {
  const new(this.refusal);

  final SyncRefusal refusal;
}

/// A `remove-task` line held until every line is applied, with the key of
/// the link it names.
final class _Removal {
  const new(this.line, this.link);

  final RemoveTaskLine line;
  final String link;
}

/// Returns [line] as the file holds it.
String _asWritten(SyncLine line) => switch (line) {
  MatchLine(:final doc, :final entry, :final fingerprint) =>
    'match $doc $entry $fingerprint',
  PlannedLine(:final doc, :final entry, :final fingerprint) =>
    'planned $doc $entry $fingerprint',
  MismatchLine(:final doc, :final entry, :final point) =>
    'mismatch $doc $entry: $point',
  RepointLine(:final doc, :final entry, :final newPath) =>
    'repoint $doc $entry $newPath',
  RemoveTaskLine(:final task, :final doc, :final entry) =>
    'remove-task $task $doc $entry',
  UnjudgedLine() || RowLine() || TestsLine() => throw StateError(
    'a ${line.runtimeType} line never waits or lists',
  ),
};

// MARK: - Result

/// Returns the answer of a sync that [run] applied and [written] wrote, with
/// the `no refs` line of each task in [noRefs].
ReadAnswer _answerOf(
  List<WrittenDoc> written,
  _SyncRun run,
  List<String> noRefs,
) {
  final text = StringBuffer();
  final docs = <Map<String, Object>>[];
  for (final WrittenDoc(:doc, :base) in written) {
    text.writeln(namingLine(doc, base: base));
    docs.add({
      'path': doc.docPath,
      'name': doc.name,
      'docType': ?doc.docTypeId,
      'base': base,
    });
  }
  for (final task in noRefs) {
    text.writeln('$task · no refs');
  }
  final kept = [
    for (final MapEntry(key: task, value: links) in run.kept.entries)
      '$task · kept by ${links.join(', ')}',
  ];
  for (final (header, lines) in [
    (_waitingHeader, run.waiting),
    (_mismatchesHeader, run.mismatches),
    (_keptHeader, kept),
  ]) {
    if (lines.isEmpty) continue;
    text.writeln(header);
    lines.forEach(text.writeln);
  }
  return ReadAnswer(
    text: text.toString(),
    json: {
      'docs': docs,
      'waiting': run.waiting,
      'mismatches': run.mismatches,
      'kept': run.kept.keys.toList(),
      'noRefs': noRefs,
    },
  );
}
