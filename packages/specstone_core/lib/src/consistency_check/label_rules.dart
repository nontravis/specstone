import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/models/label_part.dart';
import 'package:specstone_core/src/doc_model/number_label.dart'
    show builtInLabelPrefixes;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/label_place.dart';
import 'package:specstone_core/src/index_query/models/prefixed_label_place.dart';

/// The most labels one run of a number label finding holds.
const _maxRunLabels = 3;

/// Returns one `number_label` finding per number label in the body of [doc],
/// a typed doc.
///
/// The body is the text after the frontmatter; prose, code spans, and
/// `mermaid` blocks are read, other fenced code is not. The labels are
/// the ones the index found when it parsed the doc, so no text is read here.
///
/// One finding per run of [numberLabelRunsOf].
Iterable<Finding> checkNumberLabels(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final lines = context.linesOf(doc);
  final runs = numberLabelRunsOf(
    numberLabels: lines.numberLabels,
    prefixedLabels: lines.prefixedLabels,
    listed: context.numberLabelPrefixes.toSet(),
  );
  for (final LabelPlace(:line, :written) in runs) {
    yield _finding(context, doc, line, written);
  }
}

/// Returns the number label runs of a text, in order, each with its 1-based
/// line and the run as written.
///
/// A label is a built-in form or a part with a prefix in [listed]. Each
/// stretch of such parts that holds a listed one is cut into runs of up to
/// three labels; it owns the built-in labels it spans, so none of them is
/// reported again. A part with an unlisted prefix ends a stretch and is no
/// label. Both rules that report number labels pick their set here.
List<LabelPlace> numberLabelRunsOf({
  required List<LabelPlace> numberLabels,
  required List<PrefixedLabelPlace> prefixedLabels,
  required Set<String> listed,
}) {
  final runs = <LabelPlace>[];
  final owned = <LabelPlace, int>{};
  for (final chain in prefixedLabels) {
    for (final stretch in _stretchesOf(chain.parts, listed)) {
      if (!stretch.any((part) => listed.contains(part.prefix))) continue;
      final owners = {
        for (final part in stretch) ?part.ownerStart: part.ownerWritten!,
      };
      for (final written in owners.values) {
        final label = LabelPlace(line: chain.line, written: written);
        owned[label] = (owned[label] ?? 0) + 1;
      }
      for (var from = 0; from < stretch.length; from += _maxRunLabels) {
        final run = stretch.skip(from).take(_maxRunLabels);
        runs.add(
          LabelPlace(
            line: chain.line,
            written: [for (final part in run) part.written].join(' '),
          ),
        );
      }
    }
  }
  for (final label in numberLabels) {
    final dropped = owned[label] ?? 0;
    if (dropped > 0) {
      owned[label] = dropped - 1;
      continue;
    }
    runs.add(label);
  }
  return runs;
}

/// Returns the runs of adjacent parts of [parts] that are a built-in label or
/// carry a prefix of [listed].
List<List<LabelPart>> _stretchesOf(List<LabelPart> parts, Set<String> listed) {
  final stretches = <List<LabelPart>>[];
  var current = <LabelPart>[];
  for (final part in parts) {
    final isLabel =
        builtInLabelPrefixes.contains(part.prefix) ||
        listed.contains(part.prefix);
    if (isLabel) {
      current.add(part);
    } else if (current.isNotEmpty) {
      stretches.add(current);
      current = [];
    }
  }
  if (current.isNotEmpty) stretches.add(current);
  return stretches;
}

Finding _finding(
  CheckContext context,
  IndexedDoc doc,
  int line,
  String written,
) => context.finding(
  doc,
  FindingKind.numberLabel,
  line: line,
  message:
      '$written is a number label; cite the doc by its name, '
      'such as `<feature>/<story>`',
  keys: {'label': written},
);
