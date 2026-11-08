import 'package:specstone_core/src/consistency_check/reference_rules.dart'
    show architectureTypeId;
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc, blockScan;
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show isCommentLine, markdownExtension;
import 'package:specstone_core/src/doc_model/number_label.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/setup_migration/api_heading_labels.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart'
    show featurePathOf;
import 'package:specstone_core/src/setup_migration/renumber_anchors.dart'
    show SlugMoves, headingSlugsOf, withAnchorsMoved, withConcernsAnchorsMoved;
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

const _planLabel = 'number labels: ';
const _leftLabel = '; left: ';

/// The text between two labels that makes the second follow the first in a
/// list or a range (R82).
const _listJoiners = {', ', '; ', ' and ', ' or ', ' to '};

final _featureFolder = RegExp(r'^f(\d+)_([a-z0-9_]+)$');
final _storyFolder = RegExp(r'^us(\d+)_([a-z0-9_]+)$');
final _frFile = RegExp(r'^fr(\d+)_([a-z0-9_]+)\.md$');

const _featureFile = 'FEATURE.md';
const _storyFile = 'USER_STORY.md';
const _featureTypeId = 'feature';
const _apiTypeId = 'api';

// MARK: - Types

/// The feature and story a label reads against; null for a place with none.
typedef _Base = ({int? feature, int? story});

/// A label with every part it lacks taken from its [_Base].
typedef _Parts = ({int? feature, int? story, int? fr});

/// A reader of a label: the name of the one doc it names, else null.
typedef _Resolve = String? Function(NumberLabel label, NumberLabel? before);

/// A label a file keeps: its 1-based line and the label as written.
typedef _Kept = ({int line, String label});

/// A label's replacement: the 0-based line, the column of its first character,
/// and its length in that line.
typedef _LineEdit = ({int line, int column, int length, String text});

typedef _Converted = ({List<_LineEdit> edits, List<_Kept> kept});

/// A doc after the heading step and the label conversion, the operation
/// headings it converted, and the labels it keeps.
typedef _DocResult = ({String lf, List<_Kept> headings, List<_Kept> kept});

enum _DocKind { feature, story, fr, spec }

/// The place a doc path gives: its feature and story, and what is left of
/// the path.
typedef _Located = ({
  int feature,
  String featureSlug,
  int? story,
  String? storySlug,
  List<String> rest,
  bool isSpec,
});

/// No feature and no story: a code file, or a doc outside any feature.
const _Base _noPlace = (feature: null, story: null);

// MARK: - LabelTree

/// The docs and files a label resolves against: DocPaths with their order
/// numbers, and the item IDs each doc holds.
final class LabelTree {
  /// Reads the numbered docs of [docs], DocPath and LF text, each once.
  ///
  /// A doc is numbered when its path is a feature, user story, or FR doc of
  /// `prds/features/`, or a spec doc of `specs/f<nn>_<slug>/` whose merged
  /// type [docTypes] holds by DocPath; a spec doc is named from that type.
  new of(
    Iterable<({String docPath, String lf})> docs, {
    Map<String, MergedDocType> docTypes = const {},
  }) : _docs = [
         for (final (:docPath, :lf) in docs)
           ?_TreeDoc.parse(docPath, lf, docTypes[docPath]),
       ],
       _placeOf = _locate;

  /// Reads the docs of a legacy tree at the final path the move list gives
  /// each, as [LabelTree.of] reads them.
  ///
  /// A doc is named by its final path, but a label it cites reads against its
  /// place before the move: [resolve] takes the legacy path as the citing doc
  /// (`ai<nn>` feature folders included).
  new legacy(
    Iterable<({String docPath, String lf})> docs, {
    Map<String, MergedDocType> docTypes = const {},
  }) : _docs = [
         for (final (:docPath, :lf) in docs)
           ?_TreeDoc.parse(docPath, lf, docTypes[docPath]),
       ],
       _placeOf = _locateLegacy;

  final List<_TreeDoc> _docs;
  final _Located? Function(String docPath) _placeOf;
  final _declarations = <String, RegExp>{};

  // MARK: - Resolving

  /// The one DocPath [label], read relative to [citingDocPath], names; null
  /// for none or two or more (E26, E27).
  ///
  /// [before] is the label the list or range puts just before [label]: a
  /// label that lacks a feature or story then has two readings, the citing
  /// doc's place and [before]'s, and resolves only when they name exactly one
  /// doc between them.
  String? resolve(
    NumberLabel label, {
    required String citingDocPath,
    NumberLabel? before,
  }) => _resolveFrom(label, _baseOf(_placeOf(citingDocPath)), before);

  /// The name of the doc at [docPath], or null for a doc the tree does not
  /// number.
  String? nameOf(String docPath) {
    for (final doc in _docs) {
      if (doc.path == docPath) return doc.name;
    }
    return null;
  }

  /// Whether the doc at [docPath] is the `api` doc of a feature.
  bool isApi(String docPath) =>
      nameOf(docPath)?.startsWith('$_apiTypeId:') ?? false;

  /// The story and FR numbers of the FR doc that [cell], a `## FR trace` FR
  /// cell of the `api` doc at [apiDocPath], names; null for a cell that
  /// names none.
  ({int story, int fr})? frNamedBy(String apiDocPath, String cell) {
    final located = _locate(apiDocPath);
    if (located == null) return null;
    final name = '${located.featureSlug}/$cell';
    for (final doc in _docs) {
      if (doc.kind == _DocKind.fr && doc.feature == located.feature) {
        if (doc.name == name) return (story: doc.story!, fr: doc.fr!);
      }
    }
    return null;
  }

  String? _resolveFrom(NumberLabel label, _Base base, NumberLabel? before) {
    final readings = <_Base>[base];
    if (before != null && label.feature == null) {
      final prior = _partsOf(before, base);
      readings.add((feature: prior.feature, story: prior.story));
    }
    final named = {
      for (final reading in readings) ..._candidates(label, reading),
    };
    return named.length == 1 ? named.single : null;
  }

  /// The paths of the docs [label] names when read against [base].
  List<String> _candidates(NumberLabel label, _Base base) {
    final parts = _partsOf(label, base);
    final feature = parts.feature;
    if (feature == null) return const [];
    final isStoryLess = label.feature != null && parts.story == null;
    if (parts.fr != null && isStoryLess) return const [];
    final inScope = _docs.where(
      (doc) =>
          doc.feature == feature &&
          (parts.story == null || doc.story == parts.story) &&
          (parts.fr == null || doc.fr == parts.fr),
    );
    final itemId = label.itemId;
    if (itemId != null) {
      final declaration = _declarationOf(itemId);
      return [
        for (final doc in inScope)
          if (declaration.hasMatch(doc.lf)) doc.path,
      ];
    }
    final kind = parts.fr != null
        ? _DocKind.fr
        : parts.story != null
        ? _DocKind.story
        : _DocKind.feature;
    return [
      for (final doc in inScope)
        if (doc.kind == kind && (label.slug == null || label.slug == doc.slug))
          doc.path,
    ];
  }

  /// The pattern for a line that opens with [itemId] after any list mark,
  /// heading mark, table bar, or emphasis.
  RegExp _declarationOf(String itemId) => _declarations.putIfAbsent(
    itemId,
    () => RegExp(
      r'^[ \t]*(?:>[ \t]*)*(?:(?:[-*+]|\d+[.)])[ \t]+)?(?:#{1,6}[ \t]+)?'
      r'(?:\|[ \t]*)?(?:\*\*|__|`)?'
      '${RegExp.escape(itemId)}(?![A-Za-z0-9])',
      multiLine: true,
    ),
  );
}

/// [label] with each part it lacks taken from [base].
_Parts _partsOf(NumberLabel label, _Base base) {
  if (label.feature != null) {
    return (feature: label.feature, story: label.story, fr: label.fr);
  }
  if (label.story != null) {
    return (feature: base.feature, story: label.story, fr: label.fr);
  }
  return (feature: base.feature, story: base.story, fr: label.fr);
}

_Base _baseOf(_Located? located) {
  return located == null
      ? _noPlace
      : (feature: located.feature, story: located.story);
}

/// Reads the feature and story a doc path sits under, or null for a path
/// under neither `prds/features/` nor `specs/`.
_Located? _locate(String docPath) =>
    _locateUnder(docPath, _featureFolder.firstMatch);

/// Reads the place of a doc of a legacy tree: its feature folder is
/// `<prefix><nn>[_<nn>]*_<slug>`, the last number the feature's, and a legacy
/// spec doc has no feature place.
_Located? _locateLegacy(String docPath) => _locateUnder(docPath, (folder) {
  final featurePath = featurePathOf(folder);
  return featurePath == null ? null : _featureFolder.firstMatch(featurePath);
}, allowsSpec: false);

_Located? _locateUnder(
  String docPath,
  RegExpMatch? Function(String folderName) readFeature, {
  bool allowsSpec = true,
}) {
  final segments = docPath.split('/');
  final isSpec =
      allowsSpec && segments.length == 3 && segments.first == 'specs';
  final isPrd =
      segments.length >= 4 &&
      segments[0] == 'prds' &&
      segments[1] == 'features';
  if (!isSpec && !isPrd) return null;
  final folder = readFeature(segments[isSpec ? 1 : 2]);
  final feature = folder == null ? null : int.tryParse(folder.group(1)!);
  if (folder == null || feature == null) return null;
  var rest = segments.sublist(isSpec ? 2 : 3);
  final storyFolder = isPrd && rest.length >= 2
      ? _storyFolder.firstMatch(rest.first)
      : null;
  final story = storyFolder == null
      ? null
      : int.tryParse(storyFolder.group(1)!);
  if (story != null) rest = rest.sublist(1);
  return (
    feature: feature,
    featureSlug: folder.group(2)!,
    story: story,
    storySlug: story == null ? null : storyFolder!.group(2),
    rest: rest,
    isSpec: isSpec,
  );
}

/// One numbered doc: its place in the tree and the name that cites it.
final class _TreeDoc {
  new _({
    required this.path,
    required this.lf,
    required this.kind,
    required this.feature,
    required this.story,
    required this.fr,
    required this.name,
    required this.slug,
  });

  static _TreeDoc? parse(String docPath, String lf, MergedDocType? type) {
    final located = _locate(docPath);
    if (located == null || located.rest.length != 1) return null;
    final file = located.rest.single;
    final featureSlug = located.featureSlug;
    final storySlug = located.storySlug;
    _TreeDoc doc({
      required _DocKind kind,
      required String name,
      required String slug,
      int? fr,
    }) => _TreeDoc._(
      path: docPath,
      lf: lf,
      kind: kind,
      feature: located.feature,
      story: located.story,
      fr: fr,
      name: name,
      slug: slug,
    );
    if (located.isSpec) {
      return type == null
          ? null
          : doc(
              kind: _DocKind.spec,
              name: '${type.id}:$featureSlug',
              slug: featureSlug,
            );
    }
    if (storySlug == null) {
      return file == _featureFile
          ? doc(
              kind: _DocKind.feature,
              name: '$_featureTypeId:$featureSlug',
              slug: featureSlug,
            )
          : null;
    }
    if (file == _storyFile) {
      return doc(
        kind: _DocKind.story,
        name: '$featureSlug/$storySlug',
        slug: storySlug,
      );
    }
    final frFile = _frFile.firstMatch(file);
    final fr = frFile == null ? null : int.tryParse(frFile.group(1)!);
    return fr == null
        ? null
        : doc(
            kind: _DocKind.fr,
            name: '$featureSlug/$storySlug/${frFile!.group(2)}',
            slug: frFile.group(2)!,
            fr: fr,
          );
  }

  final String path;
  final String lf;
  final _DocKind kind;
  final int feature;
  final int? story;
  final int? fr;

  /// The doc's name as a doc-name mention writes it (`doc_model` RULE-11).
  final String name;

  /// The slug of the folder or file a folder path ends with.
  final String slug;
}

// MARK: - LabelPass

/// The one-time pass of a pack upgrade that replaces each number label that
/// names exactly one doc with that doc's name (D18, R81, R82).
///
/// A converted label becomes the doc name in a code span, the name alone
/// inside a code span that holds it and inside a `mermaid` block. A file under
/// the `code:` roots has no story or feature, so only a full label or a
/// folder path that names its feature resolves there. Every byte outside a
/// converted label stays.
final class LabelPass {
  new _(this._docTexts, this.codeFiles, this._files);

  /// Plans the pass over every doc of the run, DocPath and LF text after the
  /// earlier passes, and the files under the `code:` roots.
  ///
  /// [trackedCodeFiles] are the ProjectPaths and decoded text, line ends as
  /// written, of the files the
  /// project's git tracks; their labels convert. A label in an
  /// [untrackedCodeFiles] file stays and is listed. [docTypes] holds the
  /// merged type of each typed doc by DocPath; an `architecture` doc's bare
  /// `see` anchors move only with it.
  static LabelPass plan(
    List<({String docPath, String lf})> docs,
    List<({String path, String text})> trackedCodeFiles, {
    List<({String path, String text})> untrackedCodeFiles = const [],
    Map<String, MergedDocType> docTypes = const {},
  }) {
    final tree = LabelTree.of(docs, docTypes: docTypes);
    final sorted = _sortedBy(docs, (doc) => doc.docPath);
    final results = {
      for (final (:docPath, :lf) in sorted)
        docPath: _convertDoc(tree, docPath, lf),
    };
    final docTexts = _withAnchorsMoved(sorted, results, docTypes);
    final files = <_FileResult>[
      for (final (:docPath, lf: _) in sorted)
        (
          path: docPath,
          converted: docTexts.containsKey(docPath),
          headings: results[docPath]!.headings,
          kept: results[docPath]!.kept,
        ),
    ];
    final codeFiles = <String, String>{};
    final codeResolve = _codeResolverOf(tree);
    final code = [
      for (final file in trackedCodeFiles) (file: file, isTracked: true),
      for (final file in untrackedCodeFiles) (file: file, isTracked: false),
    ]..sort((a, b) => compareCodePoints(a.file.path, b.file.path));
    for (final (:file, :isTracked) in code) {
      final (:edits, :kept) = _codeFileEdits(
        file.path,
        file.text,
        isTracked ? codeResolve : _keepsEvery,
      );
      if (edits.isNotEmpty) {
        codeFiles[file.path] = _applyLineEdits(file.text, edits);
      }
      files.add((
        path: file.path,
        converted: edits.isNotEmpty,
        headings: const [],
        kept: kept,
      ));
    }
    return LabelPass._(docTexts, codeFiles, files);
  }

  final Map<String, String> _docTexts;
  final List<_FileResult> _files;

  /// The text of each code file the pass changes, line ends as written, by
  /// ProjectPath.
  final Map<String, String> codeFiles;

  /// Returns the text of the doc at [path] with its labels converted, [lf]
  /// when it has none to convert.
  String apply(String path, String lf) => _docTexts[path] ?? lf;

  /// The `number labels:` plan line: each doc and file the pass rewrites, then
  /// after `; left:` each label it keeps as `<path>:<line> <label>`; null for
  /// a tree with no label.
  String? get planLine {
    final named = [
      for (final file in _files) ...[
        if (file.converted) file.path,
        for (final (:line, :label) in file.headings)
          '${file.path}:$line $label',
      ],
    ];
    final kept = [
      for (final file in _files)
        for (final (:line, :label) in file.kept) '${file.path}:$line $label',
    ];
    if (named.isEmpty && kept.isEmpty) return null;
    return '$_planLabel${named.join(', ')}'
        '${kept.isEmpty ? '' : '$_leftLabel${kept.join(', ')}'}';
  }
}

/// A file the pass read, whether it changed it, the operation headings it
/// converted, and the labels it kept.
typedef _FileResult = ({
  String path,
  bool converted,
  List<_Kept> headings,
  List<_Kept> kept,
});

/// Whether the code file at [path], whose text is [text], holds a number label
/// the pass reads: a doc's reading for markdown, any line's for another file.
bool holdsNumberLabel(String path, String text) =>
    _codeFileEdits(path, text, _keepsEvery).kept.isNotEmpty;

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
  return (
    lf: converted.lf,
    headings: [
      for (final (:line, :operation) in step.converted)
        (line: line, label: operation),
    ],
    kept: converted.kept,
  );
}

/// Returns the text of each doc the pass changes, its links to a heading
/// whose slug the pass changed set to the new slug (D58, ledger G11).
///
/// A heading changes its slug when its operation label is dropped or a label
/// in its text becomes a doc name; the move is read heading by heading.
Map<String, String> _withAnchorsMoved(
  List<({String docPath, String lf})> docs,
  Map<String, _DocResult> results,
  Map<String, MergedDocType> docTypes,
) {
  final texts = {
    for (final (:docPath, :lf) in docs)
      if (results[docPath]!.lf != lf) docPath: results[docPath]!.lf,
  };
  final moves = SlugMoves({
    for (final (:docPath, :lf) in docs)
      if (texts[docPath] case final text?
          when _slugMovesOf(lf, text).isNotEmpty)
        docPath: _slugMovesOf(lf, text),
  });
  if (moves.isEmpty) return texts;
  for (final (:docPath, :lf) in docs) {
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

// MARK: - Resolvers

String? _keepsEvery(NumberLabel label, NumberLabel? before) => null;

/// Resolves in a code file: no place, and no list reading (E26, E27).
_Resolve _codeResolverOf(LabelTree tree) => (label, _) {
  final target = tree._resolveFrom(label, _noPlace, null);
  return target == null ? null : tree.nameOf(target);
};

// MARK: - Markdown

/// Returns [lf], a doc or a markdown file, with the labels [resolve] names
/// converted, and the labels it keeps.
///
/// [resolve] gives the name of the one doc a label names, or null; its second
/// argument is the label that puts one just before in a list.
/// With [legacyIds] the legacy IDs of a pre-`f<nn>` tree read as labels.
({String lf, List<({int line, String label})> kept}) convertLabelsIn(
  String lf,
  String? Function(NumberLabel label, NumberLabel? before) resolve, {
  bool legacyIds = false,
}) => _convertMarkdown(lf, resolve, legacyIds: legacyIds);

({String lf, List<_Kept> kept}) _convertMarkdown(
  String lf,
  _Resolve resolve, {
  bool legacyIds = false,
}) {
  final (:edits, :kept) = _markdownEdits(lf, resolve, legacyIds: legacyIds);
  return (lf: _applyLineEdits(lf, edits), kept: kept);
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
  if (labels.isEmpty) return (edits: const [], kept: const []);
  final prefixLength = lf.length - body.length;
  final firstLine = '\n'.allMatches(lf.substring(0, prefixLength)).length;
  final lines = body.split('\n');
  final scan = blockScan(lines);
  final starts = _lineStarts(lines);
  final paragraphSpans = <int, List<CodeSpan>>{};
  final edits = <_LineEdit>[];
  final kept = <_Kept>[];
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
      kept.add((line: firstLine + line + 1, label: label.written));
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
    edits.add((
      line: firstLine + line,
      column: label.start - starts[line],
      length: label.end - label.start,
      text: isBare ? name : '`$name`',
    ));
  }
  return (edits: edits, kept: kept);
}

/// Whether [gap], the text between two labels, joins them in a list or a
/// range: a joiner, with any item IDs and a joiner after each, once the
/// [firstItemId] that follows the first label is set aside (R82).
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
  );
}

// MARK: - Code files

/// Returns the edits that convert the labels [resolve] names in the code file
/// at [path], whose text is [text], and the labels it keeps.
///
/// A markdown file is read as a doc. In any other file every line is read:
/// the name goes in a code span in a comment line, and alone elsewhere, as in
/// a string such as a test name, and inside a code span that holds the label.
/// Offsets are lines and columns, so `\r` at a line end is never touched.
_Converted _codeFileEdits(String path, String text, _Resolve resolve) {
  final extension = _extensionOf(path);
  if (extension == markdownExtension) {
    return _markdownEdits(toLf(text), resolve);
  }
  final edits = <_LineEdit>[];
  final kept = <_Kept>[];
  for (final (index, line) in text.split('\n').indexed) {
    final labels = numberLabelsIn(line);
    if (labels.isEmpty) continue;
    final spans = codeSpansOf(line);
    final isComment = isCommentLine(line, extension);
    for (final label in labels) {
      final name = resolve(label, null);
      if (name == null) {
        kept.add((line: index + 1, label: label.written));
        continue;
      }
      final isSpanned = _insideSpan(spans, label.start, label.end);
      edits.add((
        line: index,
        column: label.start,
        length: label.end - label.start,
        text: isComment && !isSpanned ? '`$name`' : name,
      ));
    }
  }
  return (edits: edits, kept: kept);
}

String _extensionOf(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot);
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
  for (final (:line, :column, :length, text: replacement) in edits.reversed) {
    final current = lines[line];
    lines[line] =
        current.substring(0, column) +
        replacement +
        current.substring(column + length);
  }
  return lines.join('\n');
}
