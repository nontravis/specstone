import 'package:specstone_core/src/consistency_check/reference_rules.dart'
    show architectureTypeId;
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc, blockScan;
import 'package:specstone_core/src/doc_model/number_label.dart';
import 'package:specstone_core/src/setup_migration/api_heading_labels.dart';
import 'package:specstone_core/src/setup_migration/models/label_conversion.dart';
import 'package:specstone_core/src/setup_migration/models/label_doc.dart';
import 'package:specstone_core/src/setup_migration/models/label_tree.dart';
import 'package:specstone_core/src/setup_migration/renumber_anchors.dart'
    show SlugMoves, headingSlugsOf, withAnchorsMoved, withConcernsAnchorsMoved;
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

// MARK: - Constants

const _planLabel = 'number labels: ';
const _leftLabel = '; left: ';

/// The text between two labels that makes the second follow the first in a
/// list or a range.
const _listJoiners = {', ', '; ', ' and ', ' or ', ' to '};

// MARK: - Types

/// A reader of a label: the name of the one doc it names, else null.
typedef _Resolve = String? Function(NumberLabel label, NumberLabel? before);

/// A label's replacement: the 0-based line, the column of its first character,
/// and its length in that line.
final class _LineEdit {
  const new({
    required this.line,
    required this.column,
    required this.length,
    required this.text,
  });

  final int line;
  final int column;
  final int length;
  final String text;
}

/// The edits that convert a text's labels and the labels it keeps.
final class _Converted {
  const new({required this.edits, required this.kept});

  final List<_LineEdit> edits;
  final List<KeptLabel> kept;
}

/// A doc after the heading step and the label conversion, the operation
/// headings it converted, the labels it replaced, and the labels it keeps.
final class _DocResult {
  const new({
    required this.lf,
    required this.headings,
    required this.labels,
    required this.kept,
  });

  final String lf;
  final List<KeptLabel> headings;
  final int labels;
  final List<KeptLabel> kept;
}

/// A doc the pass read, whether it changed it, the operation headings it
/// converted, how many labels it replaced, and the labels it kept.
final class _FileResult {
  const new({
    required this.path,
    required this.converted,
    required this.headings,
    required this.labels,
    required this.kept,
  });

  final String path;
  final bool converted;
  final List<KeptLabel> headings;
  final int labels;
  final List<KeptLabel> kept;
}

// MARK: - LabelPass

/// The one-time pass of a pack upgrade that replaces each number label that
/// names exactly one doc with that doc's name.
///
/// A converted label becomes the doc name in a code span, the name alone
/// inside a code span that holds it and inside a `mermaid` block. A file under
/// the `code:` roots is never read. Every byte outside a converted label stays.
final class LabelPass {
  new _(this._tree, this._docTexts, this._files);

  /// Plans the pass over every doc of the run, DocPath and LF text after the
  /// earlier passes.
  ///
  /// [docTypes] holds the merged type of each typed doc by DocPath, and [set]
  /// the types they merge into, which place each doc; an `architecture` doc's
  /// bare `see` anchors move only with it.
  static LabelPass plan(
    List<LabelDoc> docs, {
    required MergedSet set,
    required Map<String, MergedDocType> docTypes,
  }) {
    final tree = LabelTree.of(docs, set: set, docTypes: docTypes);
    final sorted = _sortedBy(docs, (doc) => doc.docPath);
    final results = {
      for (final LabelDoc(:docPath, :lf) in sorted)
        docPath: _convertDoc(tree, docPath, lf),
    };
    final docTexts = withLabelAnchorsMoved(sorted, {
      for (final MapEntry(:key, :value) in results.entries) key: value.lf,
    }, docTypes);
    final files = <_FileResult>[
      for (final LabelDoc(:docPath) in sorted)
        _FileResult(
          path: docPath,
          converted: docTexts.containsKey(docPath),
          headings: results[docPath]!.headings,
          labels: results[docPath]!.labels,
          kept: results[docPath]!.kept,
        ),
    ];
    return LabelPass._(tree, docTexts, files);
  }

  final LabelTree _tree;
  final Map<String, String> _docTexts;
  final List<_FileResult> _files;

  /// Returns the text of the doc at [path] with its labels converted, [lf]
  /// when it has none to convert.
  String apply(String path, String lf) => _docTexts[path] ?? lf;

  /// The `number labels:` plan line, `<n> rewrites in <m> files; left: <k>`,
  /// or null for a tree with no label.
  ///
  /// `<n>` counts the labels the pass replaces and the operation headings it
  /// cuts, `<m>` the files it rewrites, `<k>` the labels it keeps.
  String? get planLine => numberLabelsPlanLine(
    rewrites: _files.fold(
      0,
      (sum, file) => sum + file.labels + file.headings.length,
    ),
    files: _files.where((file) => file.converted).length,
    left: _files.fold(0, (sum, file) => sum + file.kept.length),
  );

  /// Each file the pass rewrites, then, in the file's place, each operation
  /// heading it cuts as `<path>:<line> <operation>`, in tree order.
  List<String> get paths => pathsOn(const {});

  /// The [paths] with the lines of each doc in [written], its LF text as
  /// the run writes it after every later step, counted on that text, so each
  /// cited line is the line of the file `check` reads.
  List<String> pathsOn(Map<String, String> written) => [
    for (final file in _files.map((file) => _onWritten(file, written))) ...[
      if (file.converted) file.path,
      for (final KeptLabel(:line, :label) in file.headings)
        '${file.path}:$line $label',
    ],
  ];

  /// Each label the pass keeps as `<path>:<line> <label>`, in tree order.
  List<String> get left => leftOn(const {});

  /// The [left] with the lines of each doc in [written], as [pathsOn] counts
  /// them.
  List<String> leftOn(Map<String, String> written) => [
    for (final file in _files.map((file) => _onWritten(file, written)))
      for (final KeptLabel(:line, :label) in file.kept)
        '${file.path}:$line $label',
  ];

  /// Returns [file] with its lines counted on its [written] text.
  ///
  /// A kept label does not resolve, so converting the written text again
  /// finds each one at its written line; a converted heading is found as the
  /// same occurrence of its line's text.
  _FileResult _onWritten(_FileResult file, Map<String, String> written) {
    final text = written[file.path];
    if (text == null) return file;
    final passLines = (_docTexts[file.path] ?? '').split('\n');
    final writtenLines = text.split('\n');
    return _FileResult(
      path: file.path,
      converted: file.converted,
      headings: [
        for (final heading in file.headings)
          KeptLabel(
            line: _sameLineIn(passLines, writtenLines, heading.line),
            label: heading.label,
          ),
      ],
      labels: file.labels,
      kept: _convertDoc(_tree, file.path, text).kept,
    );
  }
}

/// Returns the 1-based line of [to] that holds the same occurrence of the
/// text of [line], a 1-based line of [from]; [line] itself when none does.
int _sameLineIn(List<String> from, List<String> to, int line) {
  if (line < 1 || line > from.length) return line;
  final text = from[line - 1];
  final occurrence = from.take(line - 1).where((l) => l == text).length;
  var seen = 0;
  for (final (index, candidate) in to.indexed) {
    if (candidate != text) continue;
    if (seen == occurrence) return index + 1;
    seen++;
  }
  return line;
}

/// The `number labels:` plan line for [rewrites] replaced labels and cut
/// headings in [files] files, with [left] labels kept; null when all three
/// are zero.
String? numberLabelsPlanLine({
  required int rewrites,
  required int files,
  required int left,
}) {
  if (rewrites == 0 && files == 0 && left == 0) return null;
  return '$_planLabel$rewrites rewrites in $files files$_leftLabel$left';
}

List<T> _sortedBy<T>(List<T> items, String Function(T item) key) =>
    [...items]..sort((a, b) => compareCodePoints(key(a), key(b)));

// MARK: - Docs

/// Returns [lf], the doc at [docPath], with the labels of its operation
/// headings dropped when it is an `api` doc, then each label that names one
/// doc converted.
///
/// A heading that keeps its labels stays as written: its labels are listed
/// and never converted.
_DocResult _convertDoc(LabelTree tree, String docPath, String lf) {
  final step = tree.isApi(docPath)
      ? dropHeadingLabels(lf, (cell) => tree.frNamedBy(docPath, cell))
      : noHeadingStep(lf);
  final bodyStart = step.lf.length - Doc.parse(step.lf).afterFrontmatter.length;
  bool isInKeptHeading(NumberLabel label) => step.kept.any(
    (heading) =>
        heading.start <= bodyStart + label.start &&
        bodyStart + label.start < heading.end,
  );
  final converted = _convertMarkdown(step.lf, (label, before) {
    if (isInKeptHeading(label)) return null;
    final target = tree.resolve(label, citingDocPath: docPath, before: before);
    return target == null ? null : tree.nameOf(target);
  });
  return _DocResult(
    lf: converted.lf,
    headings: [
      for (final (:line, :operation) in step.converted)
        KeptLabel(line: line, label: operation),
    ],
    labels: converted.rewrites,
    kept: converted.kept,
  );
}

/// Returns the text of each of [docs] a label conversion changes, its links
/// to a heading whose slug the conversion changed set to the new slug; the one
/// step both the upgrade and the legacy run take.
///
/// [docs] are the texts before the conversion and [converted] the texts
/// after it, by the path each doc's links are relative to. A heading changes
/// its slug when its operation label is dropped or a label in its text
/// becomes a doc name; the move is read heading by heading.
Map<String, String> withLabelAnchorsMoved(
  List<LabelDoc> docs,
  Map<String, String> converted,
  Map<String, MergedDocType> docTypes,
) {
  final texts = {
    for (final LabelDoc(:docPath, :lf) in docs)
      if (converted[docPath] case final text? when text != lf) docPath: text,
  };
  final moves = SlugMoves({
    for (final LabelDoc(:docPath, :lf) in docs)
      if (texts[docPath] case final text?
          when _slugMovesOf(lf, text).isNotEmpty)
        docPath: _slugMovesOf(lf, text),
  });
  if (moves.isEmpty) return texts;
  for (final LabelDoc(:docPath, :lf) in docs) {
    var text = texts[docPath] ?? lf;
    text = withAnchorsMoved(text, docPath, moves).moved?.lf ?? text;
    final type = docTypes[docPath];
    if (type != null && type.id == architectureTypeId) {
      final concerns = withConcernsAnchorsMoved(
        RenumberDoc(docPath, text, type),
        text,
        moves,
      );
      text = concerns?.lf ?? text;
    }
    if (text != lf) texts[docPath] = text;
  }
  return texts;
}

/// Each heading slug of [before] that differs from the slug of the same
/// heading in [after], by heading position.
Map<String, String> _slugMovesOf(String before, String after) {
  final old = headingSlugsOf(Doc.parse(before).afterFrontmatter);
  final now = headingSlugsOf(Doc.parse(after).afterFrontmatter);
  if (old == null || now == null || old.length != now.length) return const {};
  return {
    for (var i = 0; i < old.length; i++)
      if (old[i] != now[i]) old[i]: now[i],
  };
}

// MARK: - Markdown

/// Returns [lf], a doc or a markdown file, with the labels [resolve] names
/// converted, how many it converted, and the labels it keeps.
///
/// [resolve] gives the name of the one doc a label names, or null; its second
/// argument is the label that puts one just before in a list.
/// With [legacyIds] the legacy IDs of a pre-`f<nn>` tree read as labels.
LabelConversion convertLabelsIn(
  String lf,
  String? Function(NumberLabel label, NumberLabel? before) resolve, {
  bool legacyIds = false,
}) => _convertMarkdown(lf, resolve, legacyIds: legacyIds);

LabelConversion _convertMarkdown(
  String lf,
  _Resolve resolve, {
  bool legacyIds = false,
}) {
  final _Converted(:edits, :kept) = _markdownEdits(
    lf,
    resolve,
    legacyIds: legacyIds,
  );
  return LabelConversion(
    lf: _applyLineEdits(lf, edits),
    rewrites: edits.length,
    kept: kept,
  );
}

/// Returns the edits that convert the labels [resolve] names in [lf], a doc or
/// a markdown file, and the labels it keeps.
///
/// Labels are read as `numberLabelsInMarkdown` reads them, after the
/// frontmatter.
_Converted _markdownEdits(
  String lf,
  _Resolve resolve, {
  bool legacyIds = false,
}) {
  final body = Doc.parse(lf).afterFrontmatter;
  final labels = numberLabelsInMarkdown(body, legacyIds: legacyIds);
  if (labels.isEmpty) return const _Converted(edits: [], kept: []);
  final prefixLength = lf.length - body.length;
  final firstLine = '\n'.allMatches(lf.substring(0, prefixLength)).length;
  final lines = body.split('\n');
  final scan = blockScan(lines);
  final starts = _lineStarts(lines);
  final paragraphSpans = <int, List<CodeSpan>>{};
  final edits = <_LineEdit>[];
  final kept = <KeptLabel>[];
  var line = 0;
  NumberLabel? previous;
  NumberLabel? carried;
  for (final label in labels) {
    while (line + 1 < lines.length && starts[line + 1] <= label.start) {
      line++;
    }
    final isListed =
        previous != null &&
        _isListGap(body.substring(previous.end, label.start), previous.itemId);
    final before = isListed ? carried : null;
    final name = resolve(label, before);
    previous = label;
    carried = _carry(label, before);
    if (name == null) {
      kept.add(KeptLabel(line: firstLine + line + 1, label: label.written));
      continue;
    }
    var first = line;
    while (first > 0 && scan.continuesParagraph[first]) {
      first--;
    }
    var last = line;
    while (last + 1 < lines.length && scan.continuesParagraph[last + 1]) {
      last++;
    }
    final spans = paragraphSpans.putIfAbsent(
      first,
      () => codeSpansOf(
        body.substring(starts[first], starts[last] + lines[last].length),
      ),
    );
    final isBare =
        scan.fenced[line] ||
        _insideSpan(
          spans,
          label.start - starts[first],
          label.end - starts[first],
        );
    edits.add(
      _LineEdit(
        line: firstLine + line,
        column: label.start - starts[line],
        length: label.end - label.start,
        text: isBare ? name : '`$name`',
      ),
    );
  }
  return _Converted(edits: edits, kept: kept);
}

/// Whether [gap], the text between two labels, joins them in a list or a
/// range: a joiner, with any item IDs and a joiner after each, once the
/// [firstItemId] that follows the first label is set aside.
bool _isListGap(String gap, String? firstItemId) {
  var rest = gap;
  if (firstItemId != null && rest.startsWith(' $firstItemId')) {
    rest = rest.substring(firstItemId.length + 1);
  }
  while (true) {
    final joiner = _listJoiners.where(rest.startsWith).firstOrNull;
    if (joiner == null) return false;
    rest = rest.substring(joiner.length);
    if (rest.isEmpty) return true;
    final itemId = _itemIdAtStart(rest);
    if (itemId == null) return false;
    rest = rest.substring(itemId.length);
  }
}

/// The item ID that [text] opens with, read as the label reader reads the ID
/// after a label, or null.
String? _itemIdAtStart(String text) =>
    numberLabelsIn('FR-01 $text').first.itemId;

/// Returns [label] with a missing feature and story taken from [before].
///
/// The label after it in a list reads against these parts.
NumberLabel _carry(NumberLabel label, NumberLabel? before) {
  if (before == null || label.feature != null) return label;
  return NumberLabel(
    start: label.start,
    end: label.end,
    written: label.written,
    shape: label.shape,
    feature: before.feature,
    story: label.story ?? before.story,
    fr: label.fr,
    slug: label.slug,
    itemId: label.itemId,
    isPartOfPath: label.isPartOfPath,
  );
}

// MARK: - Text

List<int> _lineStarts(List<String> lines) {
  final starts = <int>[];
  var at = 0;
  for (final line in lines) {
    starts.add(at);
    at += line.length + 1;
  }
  return starts;
}

/// Whether the offsets [start] to [end] lie between the backticks of a span.
bool _insideSpan(List<CodeSpan> spans, int start, int end) => spans.any(
  (span) => start >= span.start + span.ticks && end <= span.end - span.ticks,
);

/// Returns [text] with each of [edits], in order of position, applied; every
/// other byte stays.
String _applyLineEdits(String text, List<_LineEdit> edits) {
  if (edits.isEmpty) return text;
  final lines = text.split('\n');
  for (final _LineEdit(:line, :column, :length, text: replacement)
      in edits.reversed) {
    final current = lines[line];
    lines[line] =
        current.substring(0, column) +
        replacement +
        current.substring(column + length);
  }
  return lines.join('\n');
}
