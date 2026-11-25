import 'package:specstone_core/src/doc_model/models/doc_address.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';

/// One instruction of a move plan.
sealed class PlanLine {
  const new({required this.lineNumber});

  /// The 1-based line of the plan text this instruction was read from.
  final int lineNumber;
}

/// A `source <doc address> <hash>` line.
final class SourceLine extends PlanLine {
  const new({
    required super.lineNumber,
    required this.address,
    required this.hash,
  });

  /// The doc whose content hash the plan records.
  final DocAddress address;

  /// The 12 hex characters of the sha256 of the doc's bytes.
  final String hash;
}

/// A `new <doc type> [--parent <doc address>] [--slug <slug>]` line.
final class NewLine extends PlanLine {
  const new({
    required super.lineNumber,
    required this.docType,
    this.parent,
    this.slug,
  });

  /// The doc type id the new doc takes.
  final String docType;

  /// The doc the new doc nests under; null when none is named.
  final DocAddress? parent;

  /// The slug the new doc is named with; null when none is named.
  final String? slug;
}

/// A `<unit address> -> <destination>` line.
final class MoveLine extends PlanLine {
  const new({
    required super.lineNumber,
    required this.unit,
    required this.destination,
  });

  /// The unit to move; its [DocAddress.sectionKey] holds any `#` suffix.
  final DocAddress unit;

  /// The doc the unit lands in; null for `top`.
  final DocAddress? destination;
}

/// A `<unit address> keep` line.
final class KeepLine extends PlanLine {
  const new({required super.lineNumber, required this.unit});

  /// The unit that stays in its doc.
  final DocAddress unit;
}

/// The instructions of one plan file, in written order.
final class MovePlan {
  const new({required this.path, required this.lines});

  /// The path the plan was read from, as named in a fault message.
  final String path;

  final List<PlanLine> lines;
}

/// Reads [text] as a move plan named [path] in fault messages.
///
/// Reads every line before it judges two lines together; a unit named twice
/// with one instruction keeps its first line.
///
/// Throws [IndexFault] `argument_invalid` naming `<path>:<line>` for a line
/// the grammar cannot read and for a unit two lines instruct differently.
MovePlan parseMovePlan(String text, {required String path}) {
  final lines = <PlanLine>[];
  final rows = text.replaceAll('\r\n', '\n').split('\n');
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index].trim();
    if (row.isEmpty || row.startsWith('#')) continue;
    lines.add(_readLine(row, index + 1, path));
  }
  return MovePlan(path: path, lines: _withoutRepeats(lines, path));
}

PlanLine _readLine(String row, int number, String path) {
  final reader = _LineReader(path, number, row.split(RegExp(r'\s+')));
  final words = reader.words;
  return switch (words.first) {
    'source' => reader.source(),
    'new' => reader.created(),
    _ when words.length == 2 && words[1] == 'keep' => KeepLine(
      lineNumber: number,
      unit: reader.unitAddress(words[0]),
    ),
    _ when words.length == 3 && words[1] == '->' => MoveLine(
      lineNumber: number,
      unit: reader.unitAddress(words[0]),
      destination: words[2] == 'top' ? null : reader.docAddress(words[2]),
    ),
    _ => throw reader.refuse(
      'expected source, new, "<unit> -> <destination>", or "<unit> keep"',
    ),
  };
}

final _hash = RegExp(r'^[0-9a-f]{12}$');

const _grammarWords = {'->', 'keep', 'top', 'source', 'new'};

/// The words of one plan row, with the fault that names the row.
final class _LineReader {
  const new(this.path, this.number, this.words);

  final String path;
  final int number;
  final List<String> words;

  IndexFault refuse(String reason) => _fault(path, number, reason);

  SourceLine source() {
    if (words.length != 3 || !_hash.hasMatch(words[2])) {
      throw refuse('source takes a doc address and 12 hex characters');
    }
    return SourceLine(
      lineNumber: number,
      address: docAddress(words[1]),
      hash: words[2],
    );
  }

  NewLine created() {
    if (words.length < 2 || !isDocTypeIdShaped(words[1])) {
      throw refuse('new takes a doc type');
    }
    DocAddress? parent;
    String? slug;
    for (var at = 2; at < words.length; at += 2) {
      final value = at + 1 < words.length ? words[at + 1] : null;
      if (value == null) throw refuse('${words[at]} takes a value');
      switch (words[at]) {
        case '--parent' when parent == null:
          parent = docAddress(value);
        case '--slug' when slug == null:
          slug = _checkedSlug(value);
        default:
          throw refuse(
            'new takes --parent and --slug once each, not ${words[at]}',
          );
      }
    }
    return NewLine(
      lineNumber: number,
      docType: words[1],
      parent: parent,
      slug: slug,
    );
  }

  /// Reads [word] as a doc address, which takes no `#` suffix.
  DocAddress docAddress(String word) {
    final address = unitAddress(word);
    if (address.sectionKey != null) {
      throw refuse('$word takes a doc address, with no # suffix');
    }
    return address;
  }

  /// Reads [word] as a unit address, whose `#` suffix may not be empty; a
  /// suffix holding `/` reads as `<section key>/<key>`, neither empty.
  DocAddress unitAddress(String word) {
    final address = readDocAddress(word);
    if (_grammarWords.contains(word) || address.body.isEmpty) {
      throw refuse('$word names no doc');
    }
    final suffix = address.sectionKey;
    if (suffix == '') throw refuse('$word has an empty # suffix');
    if (suffix != null &&
        suffix.contains('/') &&
        readKeyedUnitAddress(word) == null) {
      throw refuse('$word names no <section key>/<key>');
    }
    return address;
  }

  /// Checks each `/` part of [slug]; the part count is left to `planNewDoc`.
  String _checkedSlug(String slug) {
    try {
      checkSlugParts(slug);
    } on IndexFault catch (fault) {
      throw refuse(fault.message);
    }
    return slug;
  }
}

IndexFault _fault(String path, int line, String reason) =>
    IndexFault(IndexFaultCode.argumentInvalid, '$path:$line: $reason');

List<PlanLine> _withoutRepeats(List<PlanLine> lines, String path) {
  final firstOfUnit = <String, PlanLine>{};
  final kept = <PlanLine>[];
  for (final line in lines) {
    final unit = _unitOf(line);
    if (unit == null) {
      kept.add(line);
      continue;
    }
    final first = firstOfUnit[unit];
    if (first == null) {
      firstOfUnit[unit] = line;
      kept.add(line);
    } else if (_instructionOf(first) != _instructionOf(line)) {
      throw _fault(
        path,
        line.lineNumber,
        '$unit is on line ${first.lineNumber} and line ${line.lineNumber} '
        'with different instructions',
      );
    }
  }
  return kept;
}

String? _unitOf(PlanLine line) => switch (line) {
  MoveLine(:final unit) || KeepLine(:final unit) => _written(unit),
  SourceLine() || NewLine() => null,
};

String _instructionOf(PlanLine line) => switch (line) {
  MoveLine(:final destination) =>
    '-> ${destination == null ? 'top' : _written(destination)}',
  _ => 'keep',
};

String _written(DocAddress address) => address.sectionKey == null
    ? address.docPart
    : '${address.docPart}#${address.sectionKey}';
