import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';

const _traceHeader = 'FR trace';
final _traceCell = RegExp(
  r'^us(\d+)(?:_([a-z0-9_]+))?/fr(\d+)(?:_([a-z0-9_]+))?$',
);
final _separatorRow = RegExp(r'^\|[\s:|-]+\|$');
final _sectionHeader = RegExp(r'^ {0,3}##(?:[ \t]|$)');
final _frPath = RegExp(
  r'^.*/us(\d+)_([^/]+)/functional_requirements/fr(\d+)_(.+)\.md$',
);

/// The result of [writeFirstFingerprints].
typedef FirstFingerprints = ({String lf, String? label});

/// One FR file of the feature as a trace cell can name it (PD11).
final class _NamedFr {
  const new(this.story, this.fr, this.storySlug, this.frSlug);

  /// The story folder's number.
  final int story;

  /// The FR file's number.
  final int fr;

  /// The story folder's slug.
  final String storySlug;

  /// The FR file's slug.
  final String frSlug;

  /// The FRRef: `<story slug>/<fr slug>`.
  String get ref => '$storySlug/$frSlug';
}

/// Writes the first `confirmed` entries of an API doc's FR trace (F6-D18).
///
/// [lf] is an `API.md` renamed one to one, after `rewriteLegacyDoc`. Each
/// `## FR trace` cell that names exactly one FR of [featureFrs] becomes the
/// FRRef `<story slug>/<fr slug>`, backticks and spaces kept, and the doc's
/// `confirmed:` list gains that FRRef with its `## Statement` fingerprint.
///
/// A cell that names no single FR stays as written and gains no entry.
FirstFingerprints writeFirstFingerprints(
  String lf, {
  required Map<String, String> featureFrs,
}) {
  final doc = Doc.parse(lf);
  final index = doc.sections.indexWhere(
    (section) => section.headerText == _traceHeader,
  );
  if (index < 0) return (lf: lf, label: null);

  final named = _namedFrs(featureFrs.keys);
  final refs = <String>{};
  var text = _withRenamedCells(lf, doc, index, named, refs);
  if (refs.isEmpty) return (lf: lf, label: null);

  final statements = <String, String>{
    for (final path in featureFrs.keys)
      ?_frRefOf(path): _statementOf(featureFrs[path]!),
  };
  final block = _existingBlock(doc);
  final added = [
    for (final ref in refs)
      '  - $ref ${fingerprintOf(statements[ref] ?? '')}\n',
  ].join();
  text = withKeyBlock(text, 'confirmed', '$block$added');
  return (lf: text, label: 'confirmed (${refs.length})');
}

/// Returns the existing `confirmed:` block of [doc], every line ending in
/// `\n`, or `confirmed:\n` when the doc has none.
String _existingBlock(Doc doc) {
  final block = doc.frontmatter
      ?.where((b) => b.name == 'confirmed')
      .firstOrNull
      ?.text;
  return block ?? 'confirmed:\n';
}

/// Returns the FRs behind [paths], each parseable path one entry.
List<_NamedFr> _namedFrs(Iterable<String> paths) => [
  for (final path in paths)
    if (_frPath.firstMatch(path) case final RegExpMatch match)
      _NamedFr(
        int.parse(match.group(1)!),
        int.parse(match.group(3)!),
        match.group(2)!,
        match.group(4)!,
      ),
];

/// Returns the FRRef of [path], or null on a path of another shape.
String? _frRefOf(String path) {
  final match = _frPath.firstMatch(path);
  return match == null ? null : '${match.group(2)}/${match.group(4)}';
}

/// Rewrites each trace cell that names exactly one FR of [named].
///
/// Adds each rewritten FRRef to [refs]; a cell that stays gains none.
String _withRenamedCells(
  String lf,
  Doc doc,
  int index,
  List<_NamedFr> named,
  Set<String> refs,
) {
  final lines = doc.afterFrontmatter.split('\n');
  var sawHeader = false;
  for (var i = doc.sectionLineIndexes[index] + 1; i < lines.length; i++) {
    final text = lines[i].trim();
    if (_sectionHeader.hasMatch(text)) break;
    if (!text.startsWith('|')) continue;
    if (sawHeader && !_separatorRow.hasMatch(text)) {
      _renameCell(lines, i, text, named, refs);
    } else {
      sawHeader = true;
    }
  }
  final frontmatterLength = lf.length - doc.afterFrontmatter.length;
  return lf.substring(0, frontmatterLength) + lines.join('\n');
}

/// Renames the first cell of row [i] when it names exactly one FR.
void _renameCell(
  List<String> lines,
  int i,
  String row,
  List<_NamedFr> named,
  Set<String> refs,
) {
  final cell = _firstCell(row);
  final unquoted = _unquoted(cell);
  final match = _traceCell.firstMatch(unquoted);
  if (match == null) return;
  final hits = named
      .where(
        (candidate) =>
            candidate.story == int.parse(match.group(1)!) &&
            candidate.fr == int.parse(match.group(3)!) &&
            (match.group(2) == null || candidate.storySlug == match.group(2)) &&
            (match.group(4) == null || candidate.frSlug == match.group(4)),
      )
      .toList();
  if (hits.length != 1) return;
  lines[i] = lines[i].replaceFirst(unquoted, hits.single.ref);
  refs.add(hits.single.ref);
}

/// Returns the first table cell of [row], trimmed.
String _firstCell(String row) {
  final inner = row.substring(1);
  final end = inner.indexOf('|');
  return (end < 0 ? inner : inner.substring(0, end)).trim();
}

/// Returns [cell] with one pair of backticks dropped.
String _unquoted(String cell) =>
    cell.length > 1 && cell.startsWith('`') && cell.endsWith('`')
    ? cell.substring(1, cell.length - 1)
    : cell;

/// Returns the `## Statement` body of [frText], or '' when absent.
String _statementOf(String frText) {
  final doc = Doc.parse(frText);
  final index = doc.sections.indexWhere(
    (section) => section.headerText == 'Statement',
  );
  return index < 0 ? '' : doc.sections[index].body;
}
