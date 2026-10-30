import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/doc_model/confirmed_list.dart';
import 'package:specstone_core/src/doc_model/doc.dart';

const _traceHeader = 'FR trace';
final _traceCell = RegExp(
  r'^us(\d+)(?:_([a-z0-9_]+))?/fr(\d+)(?:_([a-z0-9_]+))?$',
);
final _frPath = RegExp(
  r'^.*/us(\d+)_([^/]+)/functional_requirements/fr(\d+)_(.+)\.md$',
);

/// The result of [writeFirstFingerprints].
typedef FirstFingerprints = ({String lf, String? label});

/// One FR file of the feature as a trace cell can name it (PD11).
final class _NamedFr {
  const new(this.path, this.story, this.fr, this.storySlug, this.frSlug);

  /// The legacy DocPath of the FR file.
  final String path;

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
/// `## FR trace` row `check` tracks, whose cell names exactly one FR of
/// [featureFrs], becomes the FRRef `<story slug>/<fr slug>`, backticks and
/// spaces kept, and the doc's `confirmed:` list gains that FRRef with its
/// `## Statement` fingerprint.
///
/// A cell that names no single FR stays as written and gains no entry. A
/// `confirmed` value that takes no appended entries, a flow list or a scalar,
/// leaves the whole doc as written.
FirstFingerprints writeFirstFingerprints(
  String lf, {
  required Map<String, String> featureFrs,
}) {
  final doc = Doc.parse(lf);
  final index = doc.sections.indexWhere(
    (section) => section.headerText == _traceHeader,
  );
  if (index < 0) return (lf: lf, label: null);
  final list = readConfirmedList(doc);
  if (list == null) return (lf: lf, label: null);

  final lines = doc.afterFrontmatter.split('\n');
  final hits = <String, String>{};
  final named = _namedFrs(featureFrs.keys);
  for (final row in readFrTraceRows(_bodyLines(doc, index))) {
    final hit = _frNamedBy(row.cell, named);
    if (hit == null) continue;
    final at = row.line - 1;
    lines[at] = lines[at].replaceFirst(row.cell, hit.ref);
    hits[hit.ref] = hit.path;
  }
  if (hits.isEmpty) return (lf: lf, label: null);

  final frontmatterLength = lf.length - doc.afterFrontmatter.length;
  final renamed = lf.substring(0, frontmatterLength) + lines.join('\n');
  final added = [
    for (final MapEntry(key: ref, value: path) in hits.entries)
      '$ref ${fingerprintOf(_statementOf(featureFrs[path]!))}',
  ];
  return (
    lf: withConfirmedEntries(renamed, list, added),
    label: 'confirmed (${hits.length})',
  );
}

/// Returns the body lines of section [index] of [doc], numbered by their
/// 1-based line among the lines after the frontmatter.
List<TraceBodyLine> _bodyLines(Doc doc, int index) {
  final body = doc.sections[index].body.split('\n');
  final fenced = fencedLines(body);
  final first = doc.sectionLineIndexes[index] + 2;
  return [
    for (var k = 0; k < body.length; k++)
      (text: body[k], line: first + k, fenced: fenced[k]),
  ];
}

/// Returns the FRs behind [paths], each parseable path one entry.
List<_NamedFr> _namedFrs(Iterable<String> paths) => [
  for (final path in paths)
    if (_frPath.firstMatch(path) case final RegExpMatch match)
      _NamedFr(
        path,
        int.parse(match.group(1)!),
        int.parse(match.group(3)!),
        match.group(2)!,
        match.group(4)!,
      ),
];

/// Returns the one FR of [named] that [cell] names, or null (PD11).
_NamedFr? _frNamedBy(String cell, List<_NamedFr> named) {
  final match = _traceCell.firstMatch(cell);
  if (match == null) return null;
  final hits = named.where(
    (candidate) =>
        candidate.story == int.parse(match.group(1)!) &&
        candidate.fr == int.parse(match.group(3)!) &&
        (match.group(2) == null || candidate.storySlug == match.group(2)) &&
        (match.group(4) == null || candidate.frSlug == match.group(4)),
  );
  return hits.length == 1 ? hits.single : null;
}

/// Returns the `## Statement` body of [frText], or '' when absent.
String _statementOf(String frText) {
  final doc = Doc.parse(frText);
  final index = doc.sections.indexWhere(
    (section) => section.headerText == 'Statement',
  );
  return index < 0 ? '' : doc.sections[index].body;
}
