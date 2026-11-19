import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';

const _byteOrderMark = '﻿';
const _styleToken = '[style]';
const _notLandedLead = 'Not landed:';
const _notLandedNone = 'Not landed: none';
const _noAuditReason = 'no audit report names it';

/// Round heading, a part break of an audit file.
final _roundHeading = RegExp(r'^## Round [0-9]+[ \t]*$');

/// `Audited:` and `Styled:` lines, each naming one typed draft at one hash.
final _draftLine = RegExp(
  r'^(Audited|Styled): ([a-z][a-z0-9_]*:[^\s@]+)@([0-9a-f]{12})$',
);

/// A `Findings:` or `Outside the drafts:` line, with an optional first item.
final _sectionLine = RegExp(r'^(Findings|Outside the drafts):(?:[ \t]+(.*))?$');

/// Any label line: a capital, then letters, spaces, or `'`, then a colon.
final _labelLine = RegExp(r"^[A-Z][A-Za-z ']*:(?: |$)");

/// A Markdown ATX heading: 1 to 6 `#`, then a blank or the line end.
final _atxHeading = RegExp(r'^#{1,6}(?:[ \t]|$)');

final _dashItem = RegExp(r'^-[ \t]+(.+)$');
final _edgeBlanks = RegExp(r'^[ \t]+|[ \t]+$');

/// One report file: the path as the call named it and its decoded text.
final class ReportFile {
  const new({required this.path, required this.text});

  final String path;
  final String text;

  /// The last segment of [path], for the reasons that name a file.
  String get name => path.split(RegExp(r'[/\\]')).last;
}

/// The audit and author report files of one call, read from disk.
final class ReportFiles {
  new _(this.audits, this.authors, this.unreadableReason);

  /// Reads each report, relative paths from [workingDirectory].
  ///
  /// Stops at the first file that is missing, unreadable, or not UTF-8; it
  /// sets [unreadableReason], and the lists hold the files read before it.
  static ReportFiles read({
    required List<String> auditPaths,
    required List<String> authorPaths,
    required Directory workingDirectory,
  }) {
    final audits = <ReportFile>[];
    final authors = <ReportFile>[];
    final unreadable =
        _readAll(auditPaths, audits, workingDirectory) ??
        _readAll(authorPaths, authors, workingDirectory);
    return ReportFiles._(audits, authors, unreadable);
  }

  /// The reason every draft is asked, or null when every file was read.
  final String? unreadableReason;

  final List<ReportFile> audits;
  final List<ReportFile> authors;
}

String? _readAll(
  List<String> paths,
  List<ReportFile> into,
  Directory workingDirectory,
) {
  for (final path in paths) {
    final file = File(path).isAbsolute
        ? File(path)
        : File('${workingDirectory.path}${Platform.pathSeparator}$path');
    try {
      into.add(
        ReportFile(path: path, text: utf8.decode(file.readAsBytesSync())),
      );
    } on FileSystemException catch (error) {
      return _unreadableReason(path, error.osError?.message ?? error.message);
    } on FormatException catch (error) {
      return _unreadableReason(path, error.message);
    }
  }
  return null;
}

String _unreadableReason(String path, String osMessage) =>
    'report $path unreadable: $osMessage';

/// The audit reports of a call, read as parts in argument then file order.
final class AuditSequence {
  new _(this._parts);

  factory parse(List<ReportFile> audits) =>
      AuditSequence._([for (final file in audits) ..._partsOf(file)]);

  final List<_Part> _parts;

  /// The index of the last part whose `Audited:` line names [address].
  int? _auditPartOf(String address) {
    for (var i = _parts.length - 1; i >= 0; i--) {
      if (_parts[i].audited.containsKey(address)) return i;
    }
    return null;
  }

  /// The hash of the last `Styled:` line for [address] from part [from] on,
  /// else the hash of its `Audited:` line in part [from].
  String _judgedHash(String address, {required int from}) {
    for (var i = _parts.length - 1; i >= from; i--) {
      final styled = _parts[i].styled[address];
      if (styled != null) return styled;
    }
    return _parts[from].audited[address]!;
  }

  /// Returns the reason for the first counted item from part [from] on that
  /// [name] matches, else null.
  String? _namedIn(RegExp name, String address, {required int from}) {
    for (final part in _parts.skip(from)) {
      final styleItemsSkipped = part.styled.containsKey(address);
      for (final item in part.items) {
        if (styleItemsSkipped && item.isStyle) continue;
        if (name.hasMatch(item.text)) {
          return 'named in ${item.section.label} of ${part.fileName}';
        }
      }
    }
    return null;
  }
}

enum _Section {
  findings('Findings'),
  outsideTheDrafts('Outside the drafts');

  new(this.label);

  final String label;
}

final class _Item {
  new(this.section, this.text);

  final _Section section;
  String text;

  bool get isStyle => text.contains(_styleToken);
}

final class _Part {
  new(this.fileName);

  final String fileName;
  final audited = <String, String>{};
  final styled = <String, String>{};
  final items = <_Item>[];
}

List<_Part> _partsOf(ReportFile file) {
  final segments = <List<String>>[[]];
  for (final line in _linesOf(file.text)) {
    if (_roundHeading.hasMatch(line)) {
      segments.add([]);
    } else {
      segments.last.add(line);
    }
  }
  final hasRounds = segments.length > 1;
  return [
    for (final (index, lines) in segments.indexed)
      if (index > 0 || !hasRounds || lines.any(_isNonBlank))
        _readPart(file.name, lines),
  ];
}

List<String> _linesOf(String text) {
  final body = text.startsWith(_byteOrderMark) ? text.substring(1) : text;
  return [
    for (final line in body.split('\n'))
      if (line.endsWith('\r')) line.substring(0, line.length - 1) else line,
  ];
}

bool _isNonBlank(String line) => _trimmed(line).isNotEmpty;

String _trimmed(String line) => line.replaceAll(_edgeBlanks, '');

bool _isContinuation(String raw) =>
    (raw.startsWith(' ') || raw.startsWith('\t')) && _isNonBlank(raw);

_Part _readPart(String fileName, List<String> lines) {
  final part = _Part(fileName);
  _Section? open;
  _Item? last;

  void addItem(String text) {
    last = _Item(open!, text);
    part.items.add(last!);
  }

  for (final raw in lines) {
    if (open != null && _isContinuation(raw)) {
      final line = _trimmed(raw);
      if (last case final item?) {
        item.text = '${item.text}\n$line';
      } else {
        addItem(line);
      }
      continue;
    }
    final line = _trimmed(raw);
    if (line.isEmpty) continue;

    if (_draftLine.firstMatch(line) case final match?) {
      final into = match[1] == 'Audited' ? part.audited : part.styled;
      into[match[2]!] = match[3]!;
      open = null;
      last = null;
    } else if (_sectionLine.firstMatch(line) case final match?) {
      open = match[1] == _Section.findings.label
          ? _Section.findings
          : _Section.outsideTheDrafts;
      last = null;
      final first = match[2];
      if (first != null && first.isNotEmpty && first != 'none') addItem(first);
    } else if (_labelLine.hasMatch(line) || _atxHeading.hasMatch(line)) {
      open = null;
      last = null;
    } else if (open != null) {
      addItem(_dashItem.firstMatch(line)?[1] ?? line);
    }
  }
  return part;
}

/// What the judge needs to know of one draft.
final class JudgedDraft {
  const new({
    required this.name,
    required this.docPath,
    required this.currentHash,
  });

  /// The address `DocIndex.addressOf` gives: a DocPath when the typed name
  /// is shared.
  final String name;
  final String docPath;

  /// The draft's current `bases.doc` hash.
  final String currentHash;
}

/// Judges each draft of an `approve --auto` call by the clean-draft tests.
final class CleanDraftJudge {
  new({
    required List<Finding> findings,
    required AuditSequence? audit,
    required bool noAudit,
    required List<ReportFile> authors,
    String? unreadableReason,
  }) : _findings = findings,
       _audit = audit,
       _noAudit = noAudit,
       _unreadableReason = unreadableReason,
       _notLandedFile = _firstNotLandedFile(authors);

  /// Fails every draft when set: [ReportFiles.unreadableReason] of the call.
  final String? _unreadableReason;
  final List<Finding> _findings;
  final AuditSequence? _audit;
  final bool _noAudit;
  final String? _notLandedFile;

  /// Returns the reason of the first failing test, or null for a clean draft.
  String? reasonFor(JudgedDraft draft) =>
      _unreadableReason ??
      _checkReason(draft) ??
      (_noAudit ? null : _auditReason(draft)) ??
      _authorReason();

  String? _checkReason(JudgedDraft draft) {
    for (final finding in _findings) {
      if (finding.path != draft.docPath) continue;
      final clearedByApproval =
          finding.kind == FindingKind.unconfirmed &&
          finding.waitsFor == WaitsFor.owner;
      if (!clearedByApproval) return 'check finding ${finding.kind.wire}';
    }
    return null;
  }

  String? _auditReason(JudgedDraft draft) {
    final audit = _audit;
    final from = audit?._auditPartOf(draft.name);
    if (audit == null || from == null) return _noAuditReason;
    final judged = audit._judgedHash(draft.name, from: from);
    if (judged != draft.currentHash) {
      return 'audited at $judged, now ${draft.currentHash}';
    }
    return audit._namedIn(_nameIn(draft), draft.name, from: from);
  }

  String? _authorReason() {
    final file = _notLandedFile;
    return file == null ? null : 'Not landed line in $file';
  }
}

/// One bounded search for the draft's `name` or its `docPath`.
RegExp _nameIn(JudgedDraft draft) {
  final forms = {draft.name, draft.docPath}.map(RegExp.escape).join('|');
  return RegExp(
    '${r'(?<=^|[ \t`(\[])'}(?:$forms)${r'(?=$|[ \t`@#:,.;)\]])'}',
    multiLine: true,
  );
}

String? _firstNotLandedFile(List<ReportFile> authors) {
  for (final file in authors) {
    final landed = _linesOf(file.text)
        .map(_trimmed)
        .any((l) => l.startsWith(_notLandedLead) && l != _notLandedNone);
    if (landed) return file.name;
  }
  return null;
}
