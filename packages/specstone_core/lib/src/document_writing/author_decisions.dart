import 'dart:math';

import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show holdsSectionAddress, targetListsIn;
import 'package:specstone_core/src/document_writing/report_file.dart';

const _decisionLead = 'Decision:';
const _notLandedLead = 'Not landed:';
const _notLandedMark = 'NOT LANDED';

/// The word `none` at the start of a line, bounded by no letter, digit, or `_`.
final _noneWord = RegExp('^none(?![A-Za-z0-9_])');

/// A whole list item that is one section key.
final _sectionKey = RegExp(r'^[A-Za-z0-9_]+$');

/// A decision key right after a label, ended by a space, `:`, `(`, or the
/// line end, so `D1` and `D10` stay apart.
final _decisionKey = RegExp(r'^D([0-9]+)(?=[ :(]|$)');

/// The decisions the `--author` files leave open.
final class AuthorDecisions {
  const new _(this._open, this._unkeyed);

  /// Opens a decision key only when a file leaves it open and no file lands it.
  ///
  /// Within one file, the last `Decision:` or `Not landed:` line of a key
  /// decides that file's state.
  factory read(List<ReportFile> authors) {
    final leftOpen = <_OpenDecision>[];
    final landed = <int>{};
    _UnkeyedLine? unkeyed;
    for (final (index, file) in authors.indexed) {
      final states = <int, bool>{};
      for (final line in reportLinesOf(file.text).map(trimmedReportLine)) {
        final isDecision = line.startsWith(_decisionLead);
        final isNotLanded = line.startsWith(_notLandedLead);
        if (!isDecision && !isNotLanded) continue;
        final lead = isDecision ? _decisionLead : _notLandedLead;
        final rest = line.substring(lead.length).trimLeft();
        final key = _decisionKey.firstMatch(rest);
        if (key != null) {
          states[int.parse(key[1]!)] = isNotLanded || !_landsSection(rest);
        } else if (isNotLanded && !_opensWithNone(rest)) {
          unkeyed ??= _UnkeyedLine(index, file.name);
        }
      }
      for (final MapEntry(:key, :value) in states.entries) {
        if (value) {
          leftOpen.add(_OpenDecision(key, index, file.name));
        } else {
          landed.add(key);
        }
      }
    }
    final open = leftOpen.where((d) => !landed.contains(d.number)).toList()
      ..sort();
    return AuthorDecisions._(open, unkeyed);
  }

  final List<_OpenDecision> _open;
  final _UnkeyedLine? _unkeyed;

  /// The reason that fails every draft of the call, or null when no
  /// decision is open and no unkeyed `Not landed:` line is read. Both causes
  /// are named, each with its file, in the order the files were passed.
  String? get reason {
    final unkeyed = _unkeyed;
    final named = _open.map((d) => 'D${d.number} in ${d.file}');
    final keyed = _open.isEmpty ? null : 'not landed: ${named.join(', ')}';
    final unkeyedReason = unkeyed == null
        ? null
        : 'Not landed line in ${unkeyed.file}';
    if (keyed == null || unkeyed == null) return keyed ?? unkeyedReason;
    final firstKeyedIndex = _open.map((d) => d.fileIndex).reduce(min);
    return unkeyed.fileIndex < firstKeyedIndex
        ? '$unkeyedReason; $keyed'
        : '$keyed; $unkeyedReason';
  }
}

bool _landsSection(String rest) =>
    !rest.contains(_notLandedMark) &&
    (holdsSectionAddress(rest) || _holdsSectionList(rest));

bool _holdsSectionList(String rest) => targetListsIn(rest).any(
  (list) => list.split(',').any((key) => _sectionKey.hasMatch(_bareKey(key))),
);

String _bareKey(String key) => key.replaceAll('#', '').trim();

/// Whether [rest] opens with the word `none`, ended by the line end or by a
/// character that is no letter, digit, or `_`.
bool _opensWithNone(String rest) => _noneWord.hasMatch(rest);

final class _OpenDecision implements Comparable<_OpenDecision> {
  const new(this.number, this.fileIndex, this.file);

  final int number;
  final int fileIndex;
  final String file;

  @override
  int compareTo(_OpenDecision other) {
    final byNumber = number.compareTo(other.number);
    return byNumber != 0 ? byNumber : fileIndex.compareTo(other.fileIndex);
  }
}

final class _UnkeyedLine {
  const new(this.fileIndex, this.file);

  final int fileIndex;
  final String file;
}
