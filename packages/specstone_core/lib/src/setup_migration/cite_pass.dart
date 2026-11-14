import 'package:specstone_core/src/consistency_check/cite_rules.dart'
    show isSeeTargetCite, seeTargetsIn;
import 'package:specstone_core/src/index_query/cite_candidates.dart';
import 'package:specstone_core/src/index_query/cite_resolution.dart';
import 'package:specstone_core/src/index_query/doc_mentions.dart'
    show namesakesByFileName;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show docNameOf, docStructureOf;
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_version.dart';

// MARK: - Constants

const _planLabel = 'cites: ';
const _leftLabel = '; left: ';
const _space = 0x20;

/// The pack versions that first ship the cite rule.
///
/// A pack upgrade that moves one of these pins up from below its version runs
/// the cite pass once; a later upgrade never does.
final Map<String, PackVersion> citeRuleSince = Map.unmodifiable({
  for (final (pack, version) in const [
    ('prd-core', '1.9.0'),
    ('software-tech', '1.7.0'),
  ])
    pack: PackVersion.parse(version, file: 'cite_pass.dart', key: pack),
});

/// Whether [upgrades] move a [citeRuleSince] pin from below its version to it
/// or later: the one trigger of the cite pass.
bool runsCitePass(List<PackUpgrade> upgrades) =>
    crossesSince(upgrades, citeRuleSince);

// MARK: - Types

/// A doc of the run: planned DocPath, LF text, merged doc type, null for an
/// untyped doc, and the code target whose pattern set matched it, if any.
typedef CitePassDoc = ({
  String docPath,
  String lf,
  MergedDocType? type,
  String? target,
});

/// A cite the pass keeps, at its 1-based file line, as written.
typedef _Kept = ({int line, String cite});

/// A typed doc after the pass: its text, the cites it rewrote, and those it
/// kept.
typedef _DocResult = ({String lf, int rewrites, List<_Kept> kept});

/// One typed doc the pass read, with its result.
typedef _Read = ({String docPath, MergedDocType type, _DocResult result});

/// One doc of the planned tree: what a cite resolves to, and what its
/// sections are read from.
typedef _TreeEntry = ({
  CiteDoc doc,
  String lf,
  MergedDocType? type,
  String? target,
});

/// One replacement on a 1-based line: 0-based columns from `start` up to
/// `end` take `text`.
typedef _Edit = ({int line, int start, int end, String text});

// MARK: - CitePass

/// The pass of a pack upgrade that rewrites each old cite form naming exactly
/// one doc, section, or item to its link.
///
/// It reads each typed doc's body as `check` reads its cite candidates and
/// resolves each through `resolveCite` over the planned tree, so it rewrites
/// what `cite_unlinked` reports as one link and keeps every other form.
final class CitePass {
  new _(this._tree, this._docTexts, this._reads, this._idPrefixes);

  /// Plans the pass over every doc of the run, its text after the earlier
  /// passes; untyped docs are cite targets but are never rewritten.
  ///
  /// - [idPrefixes]: the item ID prefixes of the run's merged set, as
  ///   `itemIdPrefixesOf` gives them.
  static CitePass plan(
    List<CitePassDoc> docs, {
    required Set<String> idPrefixes,
  }) {
    final tree = _PlannedCiteTree(docs);
    final reads = <_Read>[];
    final docTexts = <String, String>{};
    for (final (:docPath, :lf, :type, target: _) in docs) {
      if (type == null) continue;
      final result = _convertDoc(tree, docPath, lf, type, idPrefixes);
      reads.add((docPath: docPath, type: type, result: result));
      if (result.lf != lf) docTexts[docPath] = result.lf;
    }
    reads.sort((a, b) => compareCodePoints(a.docPath, b.docPath));
    return CitePass._(tree, docTexts, reads, idPrefixes);
  }

  final _PlannedCiteTree _tree;
  final Map<String, String> _docTexts;
  final List<_Read> _reads;
  final Set<String> _idPrefixes;

  /// Returns the text of the doc at [docPath] with its cites converted, [lf]
  /// when it has none to convert.
  String apply(String docPath, String lf) => _docTexts[docPath] ?? lf;

  /// The `cites:` plan line, `<n> rewrites in <m> docs; left: <k>`, or null
  /// for a tree with no old cite form.
  ///
  /// `<n>` counts each form the pass rewrites once, however many links it
  /// becomes, `<m>` the docs it rewrites, `<k>` the forms it keeps.
  String? get planLine {
    final rewrites = _reads.fold(0, (sum, read) => sum + read.result.rewrites);
    final left = _reads.fold(0, (sum, read) => sum + read.result.kept.length);
    if (rewrites == 0 && left == 0) return null;
    return '$_planLabel$rewrites rewrites in ${_docTexts.length} docs'
        '$_leftLabel$left';
  }

  /// The DocPath of each doc the pass rewrites, in code point order.
  List<String> get paths => [..._docTexts.keys]..sort(compareCodePoints);

  /// Each form the pass keeps as `<DocPath>:<line> <cite>`, in code point
  /// order of the DocPath, each line counted on the doc's text in [written],
  /// its LF text as the run writes it after every later step, when it holds
  /// one.
  ///
  /// A kept form names no one link, so reading the written text again finds
  /// each one at its written line.
  List<String> leftOn(Map<String, String> written) => [
    for (final (:docPath, :type, :result) in _reads)
      for (final (:line, :cite) in switch (written[docPath]) {
        final text? => _convertDoc(
          _tree,
          docPath,
          text,
          type,
          _idPrefixes,
        ).kept,
        null => result.kept,
      })
        '$docPath:$line $cite',
  ];
}

// MARK: - Conversion

/// Returns the doc at [docPath], of [type], with each cite that names one
/// link rewritten to it, and the cites it keeps.
_DocResult _convertDoc(
  CiteTree tree,
  String docPath,
  String lf,
  MergedDocType type,
  Set<String> idPrefixes,
) {
  final forms = citeFormsOf(lf, idPrefixes: idPrefixes);
  if (forms.isEmpty) return (lf: lf, rewrites: 0, kept: const []);
  final lines = lf.split('\n');
  final seeTargets = seeTargetsIn(docStructureOf(lf, type), type);
  final edits = <_Edit>[];
  final kept = <_Kept>[];
  var rewrites = 0;
  for (final form in forms) {
    final candidate = form.candidate;
    if (isSeeTargetCite(seeTargets[candidate.line], candidate)) continue;
    final resolved = resolveCite(tree, docPath, candidate);
    if (resolved is CiteNoDoc) continue;
    if (resolved is CiteLink && !form.isInSpan) {
      edits.addAll(
        _editsOf(
          form,
          resolved,
          citeLinkMarkdown(docPath, resolved),
          lines[candidate.line - 1],
        ),
      );
      rewrites++;
    } else {
      kept.add((line: candidate.line, cite: candidate.written));
    }
  }
  return (lf: _withEdits(lines, edits), rewrites: rewrites, kept: kept);
}

/// Returns the edits that write [form], on [line], as the [markdown] links of
/// [link].
///
/// A doc or section cite becomes its one link. An item cite drops its doc
/// part and the spaces after it, and each item ID becomes its own link, the
/// words between them kept.
List<_Edit> _editsOf(
  CiteForm form,
  CiteLink link,
  List<String> markdown,
  String line,
) {
  final number = form.candidate.line;
  if (link.items.isEmpty) {
    return [
      (line: number, start: form.start, end: form.end, text: markdown.single),
    ];
  }
  final linkOf = {
    for (final (index, item) in link.items.indexed)
      item.itemId: markdown[index],
  };
  var dropEnd = form.end;
  while (dropEnd < line.length && line.codeUnitAt(dropEnd) == _space) {
    dropEnd++;
  }
  return [
    (line: number, start: form.start, end: dropEnd, text: ''),
    for (final (:column, :itemId) in form.items)
      if (linkOf[itemId] case final text?)
        (line: number, start: column, end: column + itemId.length, text: text),
  ];
}

/// Returns [lines] joined with each of [edits] applied, the rightmost edit of
/// a line first so each column still holds.
String _withEdits(List<String> lines, List<_Edit> edits) {
  if (edits.isEmpty) return lines.join('\n');
  final edited = [...lines];
  final ordered = [...edits]
    ..sort((a, b) => a.line != b.line ? a.line - b.line : b.start - a.start);
  for (final (:line, :start, :end, :text) in ordered) {
    edited[line - 1] = edited[line - 1].replaceRange(start, end, text);
  }
  return edited.join('\n');
}

// MARK: - Planned tree

/// The [CiteTree] of a migrate run: the docs as the run plans them, named and
/// sectioned as the index will read them after the run.
final class _PlannedCiteTree implements CiteTree {
  new(List<CitePassDoc> docs)
    : _docs = {
        for (final (:docPath, :lf, :type, :target) in docs)
          docPath: (
            doc: (
              docPath: docPath,
              docTypeId: type?.id,
              name: docNameOf(docPath, type, target: target),
            ),
            lf: lf,
            type: type,
            target: target,
          ),
      };

  final Map<String, _TreeEntry> _docs;
  final _sections = <String, List<CiteSection>>{};

  late final Map<String, List<String>> _byName = _grouped(
    (entry) => entry.doc.name,
  );
  late final Map<String, List<String>> _byTypeAndName = _grouped(
    (entry) => '${entry.doc.docTypeId}:${entry.doc.name}',
  );
  late final Map<String, Map<String, List<String>>> _namesakes =
      namesakesByFileName(_docs.keys);

  /// Returns the DocPaths of the tree grouped under the key [keyOf] gives.
  Map<String, List<String>> _grouped(String Function(_TreeEntry) keyOf) {
    final groups = <String, List<String>>{};
    for (final MapEntry(key: docPath, :value) in _docs.entries) {
      (groups[keyOf(value)] ??= []).add(docPath);
    }
    return groups;
  }

  @override
  List<CiteDoc> named(
    String name, {
    required String? typeId,
    required String fromDocPath,
  }) {
    final paths = typeId == null
        ? _byName[name]
        : _byTypeAndName['$typeId:$name'];
    final own = _docs[fromDocPath]?.target;
    return [
      for (final docPath in paths ?? const <String>[])
        if (_docs[docPath] case final entry?)
          if (own == null || entry.target == null || entry.target == own)
            entry.doc,
    ];
  }

  @override
  CiteDoc? at(String docPath) => _docs[docPath]?.doc;

  @override
  Map<String, List<String>> namesakes(String fileName) =>
      _namesakes[fileName] ?? const {};

  @override
  List<CiteSection> sectionsOf(String docPath) =>
      _sections[docPath] ??= switch (_docs[docPath]) {
        final entry? => citeSectionsOf(docStructureOf(entry.lf, entry.type)),
        null => const [],
      };
}
