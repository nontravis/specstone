import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/number_label.dart';

// MARK: - Constants

const _traceHeader = 'FR trace';
const _operationsHeader = 'Operations';

/// The text between two labels of a heading that makes the second follow the
/// first (apply_steps_and_pins E28).
const _joiners = {', ', '; ', ' to '};

const _storyMarker = ' of ';

final _headingLine = RegExp(r'^###[ \t]+(`[^`]+`)[ \t]+—[ \t]+(.+?)[ \t]*$');

// MARK: - Types

/// The story and FR numbers of the FR doc a `## FR trace` cell names; null
/// for a cell that names none.
typedef FrOfCell = ({int story, int fr})? Function(String cell);

/// An operation heading the step converted: its 1-based file line and the
/// operation as the heading writes it, backticks included.
typedef ConvertedHeading = ({int line, String operation});

/// The result of [dropHeadingLabels].
///
/// `kept` holds the offsets in `lf` of each heading that holds a label and
/// stays as written.
typedef HeadingStep = ({
  String lf,
  List<ConvertedHeading> converted,
  List<({int start, int end})> kept,
});

/// The step result for a doc with no operation heading to read.
HeadingStep noHeadingStep(String lf) =>
    (lf: lf, converted: const [], kept: const []);

typedef _Frs = Set<({int story, int fr})>;

// MARK: - dropHeadingLabels

/// Returns [lf], an `api` doc, with the label dropped from each operation
/// heading whose labels each name one FR of that operation's `## FR trace`
/// rows (D58, apply_steps_and_pins E28, E29).
///
/// A heading is `` ### `<operation>` — <labels> ``: the labels are
/// `US-<nn> FR-<nn>`, `FR-<nn>`, or a range of two, joined by `,` or `;`,
/// then an optional `of <story>` that is the story of the labels without one.
/// A heading with a label that names no FR of its rows or two, or that reads
/// otherwise, stays as written and is listed in `HeadingStep.kept`.
HeadingStep dropHeadingLabels(String lf, FrOfCell frOf) {
  final doc = Doc.parse(lf);
  final operations = _sectionIndex(doc, _operationsHeader);
  if (operations < 0) return noHeadingStep(lf);
  final frsByOperation = _frsByOperation(doc, frOf);
  final body = doc.afterFrontmatter.split('\n');
  final bodyStart = lf.length - doc.afterFrontmatter.length;
  final firstLine = '\n'.allMatches(lf.substring(0, bodyStart)).length + 1;
  final fenced = fencedLines(body);
  final converted = <ConvertedHeading>[];
  final kept = <({int start, int end})>[];
  var offset = bodyStart;
  final out = StringBuffer(lf.substring(0, bodyStart));
  final header = doc.sectionLineIndexes[operations];
  final last = header + doc.sections[operations].body.split('\n').length;
  for (var i = 0; i < body.length; i++) {
    var text = body[i];
    final match = !fenced[i] && i > header && i <= last
        ? _headingLine.firstMatch(text)
        : null;
    if (match != null) {
      final operation = match.group(1)!;
      final frs = frsByOperation[operation.substring(1, operation.length - 1)];
      if (_namesEachFr(match.group(2)!, frs ?? const {})) {
        text = '### $operation';
        converted.add((line: firstLine + i, operation: operation));
      } else if (numberLabelsIn(match.group(2)!).isNotEmpty) {
        kept.add((start: offset, end: offset + text.length));
      }
    }
    out.write(i == 0 ? text : '\n$text');
    offset += body[i].length + 1;
  }
  return (lf: out.toString(), converted: converted, kept: kept);
}

// MARK: - FR trace

int _sectionIndex(Doc doc, String header) =>
    doc.sections.indexWhere((section) => section.headerText == header);

/// Per operation, the FRs its `## FR trace` rows name.
Map<String, _Frs> _frsByOperation(Doc doc, FrOfCell frOf) {
  final index = _sectionIndex(doc, _traceHeader);
  if (index < 0) return const {};
  final body = doc.sections[index].body.split('\n');
  final fenced = fencedLines(body);
  final firstLine = doc.sectionLineIndexes[index] + 2;
  final lines = [
    for (var k = 0; k < body.length; k++)
      (text: body[k], line: firstLine + k, fenced: fenced[k]),
  ];
  final byLine = {for (final line in lines) line.line: line.text};
  final frs = <String, _Frs>{};
  for (final (:cell, :line) in readFrTraceRows(lines)) {
    final operation = _secondCell(byLine[line]!);
    final fr = frOf(cell);
    if (operation != null && fr != null) {
      (frs[operation] ??= {}).add(fr);
    }
  }
  return frs;
}

/// The second cell of table row [row], one pair of backticks dropped.
String? _secondCell(String row) {
  final cells = row.trim().split('|');
  if (cells.length < 3) return null;
  final cell = cells[2].trim();
  return cell.length > 1 && cell.startsWith('`') && cell.endsWith('`')
      ? cell.substring(1, cell.length - 1)
      : cell;
}

// MARK: - Labels

/// Whether [text], the labels of a heading, reads as the heading shape and
/// each label names exactly one of [frs].
bool _namesEachFr(String text, _Frs frs) {
  final marker = text.lastIndexOf(_storyMarker);
  final listText = marker < 0 ? text : text.substring(0, marker);
  final tail = marker < 0
      ? null
      : _wholeLabel(text.substring(marker + _storyMarker.length));
  if (marker >= 0 && (tail == null || tail.story == null || tail.fr != null)) {
    return false;
  }
  final labels = _listOf(listText);
  if (labels == null) return false;
  var story = tail?.story;
  for (final label in labels) {
    story = label.story ?? story;
    final isSimple =
        label.feature == null &&
        label.fr != null &&
        label.slug == null &&
        label.itemId == null;
    if (!isSimple) return false;
    final hits = {
      for (final fr in frs)
        if (fr.fr == label.fr && (story == null || fr.story == story)) fr,
    };
    if (hits.length != 1) return false;
  }
  return true;
}

/// The labels of [text] when it is nothing but labels and [_joiners], else
/// null.
List<NumberLabel>? _listOf(String text) {
  final labels = numberLabelsIn(text);
  if (labels.isEmpty || labels.first.start != 0) return null;
  if (labels.last.end != text.length) return null;
  for (var i = 1; i < labels.length; i++) {
    if (!_joiners.contains(
      text.substring(labels[i - 1].end, labels[i].start),
    )) {
      return null;
    }
  }
  return labels;
}

/// The one label that is all of [text], else null.
NumberLabel? _wholeLabel(String text) {
  final labels = numberLabelsIn(text);
  return labels.length == 1 && labels.single.end == text.length
      ? labels.single
      : null;
}
