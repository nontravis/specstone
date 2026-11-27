import 'dart:math';

import 'package:specstone_core/src/document_writing/report_file.dart';
import 'package:specstone_core/src/document_writing/report_grammar.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// Answers whether the project holds a section.
final class SectionLookup {
  const new(this._holds);

  /// Holds a key when [index] resolves the doc address to exactly one doc that
  /// holds a section of that key or a field of its doc type with that id.
  ///
  /// A doc address that faults or names 2 or more docs holds nothing. A
  /// [codeTarget] keeps a name to that target's docs and the shared docs.
  factory ofIndex(DocIndex index, {String? codeTarget}) =>
      SectionLookup((docAddress, key) {
        final List<IndexedDoc> docs;
        try {
          docs = index.resolve(docAddress, codeTarget: codeTarget);
        } on IndexFault {
          return false;
        } on TemplateFault {
          return false;
        }
        if (docs.length != 1) return false;
        final doc = docs.single;
        return index.contentOf(doc).sections.any((s) => s.key == key) ||
            (index.typeOf(doc)?.fields.any((f) => f.id == key) ?? false);
      });

  final bool Function(String docAddress, String key) _holds;

  /// Whether the project holds the section [key] of the doc [docAddress].
  bool holds(String docAddress, String key) => _holds(docAddress, key);
}

/// The decisions the `--author` files leave open.
final class AuthorDecisions {
  const new _(this._open, this._unkeyed);

  /// Opens a decision key only when a file leaves it open and no file lands it.
  ///
  /// Within one file, the last `Decision:` or `Not landed:` line of a key
  /// decides that file's state. A `Decision:` line lands only when [sections]
  /// holds every section it names, else the decision stays open.
  factory read(List<ReportFile> authors, SectionLookup sections) {
    final leftOpen = <_OpenDecision>[];
    final landed = <int>{};
    _UnkeyedLine? unkeyed;
    for (final (index, file) in authors.indexed) {
      final states = <int, bool>{};
      for (final line in reportLinesOf(file.text).map(trimmedReportLine)) {
        final read = readDecisionLine(line);
        if (read == null) continue;
        if (read.key case final key?) {
          states[key] =
              read.isOpen ||
              !read.sections.every((s) => sections.holds(s.docAddress, s.key));
        } else if (read.isUnkeyedAsk) {
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
