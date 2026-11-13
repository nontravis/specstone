import 'package:specstone_core/src/consistency_check/reference_rules.dart'
    show architectureTypeId;
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc, blockScan;
import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/number_label.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/parents.dart'
    show resolveParents;
import 'package:specstone_core/src/setup_migration/api_heading_labels.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart'
    show legacyFolderIdOf;
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
/// list or a range (R82).
const _listJoiners = {', ', '; ', ' and ', ' or ', ' to '};

final _featureFolder = RegExp(r'^f(\d+)_([a-z0-9_]+)$');
final _storyFolder = RegExp(r'^us(\d+)_([a-z0-9_]+)$');
final _frFile = RegExp(r'^fr(\d+)_([a-z0-9_]+)\.md$');

const _featureFile = 'FEATURE.md';
const _storyFile = 'USER_STORY.md';
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

/// The feature a doc sits under, by number and name, and its story's number
/// when it sits under one.
typedef _Place = ({int feature, String featureName, int? story});

/// The place a legacy doc path gives: its feature and story, and what is left
/// of the path.
typedef _Located = ({
  int feature,
  String featureSlug,
  int? story,
  String? storySlug,
  List<String> rest,
  bool isSpec,
});

/// No feature and no story: a doc outside any feature.
const _Base _noPlace = (feature: null, story: null);

// MARK: - LabelTree

/// The docs and files a label resolves against: DocPaths with their order
/// numbers, and the item IDs each doc holds.
final class LabelTree {
  /// Reads the numbered docs of [docs], DocPath and LF text, as the index does.
  ///
  /// [docTypes] holds the merged type of each typed doc by DocPath. A doc's
  /// feature and story are the nearest `feature` and `user_story` up its
  /// parent chain in [set], at any depth, numbered by their own path segment.
  /// A feature, user story, FR, or spec doc under a feature is numbered.
  new of(
    Iterable<({String docPath, String lf})> docs, {
    required MergedSet set,
    required Map<String, MergedDocType> docTypes,
  }) : this._fromIndex(_readIndex(docs, set, docTypes));

  /// Reads the docs of a legacy tree at the final path the move list gives
  /// each, as [LabelTree.of] reads them.
  ///
  /// A doc is named and numbered by its final path, and a legacy ID finds it
  /// by the folder ID of its legacy path, such as `ai02`. A label a doc cites
  /// reads against its place before the move: [resolve] takes the legacy path
  /// as the citing doc, its feature folder read as the FeaturePath that
  /// [featurePaths] gives it (legacy feature folder to FeaturePath); a doc
  /// under no such folder keeps its path's own place.
  new legacy(
    Iterable<({String docPath, String legacyPath, String lf})> docs, {
    Map<String, MergedDocType> docTypes = const {},
    Map<String, String> featurePaths = const {},
  }) : _docs = [
         for (final (:docPath, :legacyPath, :lf) in docs)
           ?_TreeDoc.parseLegacy(
             docPath,
             lf,
             docTypes[docPath],
           )?.withLegacyFolder(_legacyFolderOf(legacyPath)),
       ],
       _placeOf = ((path) =>
           _legacyPlaceOf(_atFeaturePath(path, featurePaths)));

  new _fromIndex(_Index index) : _docs = index.docs, _placeOf = index.placeOf;

  final List<_TreeDoc> _docs;
  final _Place? Function(String docPath) _placeOf;
  final _declarations = <String, RegExp>{};

  // Each label is a lookup, not a scan of every doc, so the pass grows with
  // its labels plus its docs rather than their product.
  late final Map<String, _TreeDoc> _byPath = {
    for (final doc in _docs) doc.path: doc,
  };
  late final Map<int, List<_TreeDoc>> _byFeature = _grouped(
    (doc) => [doc.feature],
  );

  /// The docs under each legacy feature folder, by its whole name and by its
  /// whole folder ID, the two names a legacy ID's first folder points at.
  late final Map<String, List<_TreeDoc>> _byLegacyFolder = _grouped((doc) {
    final folder = doc.legacyFolder;
    if (folder == null) return const [];
    final id = legacyFolderIdOf(folder);
    return [folder, if (id != null && id != folder) id];
  });

  /// Returns [_docs] grouped under each key [keysOf] gives, in tree order.
  Map<K, List<_TreeDoc>> _grouped<K>(List<K> Function(_TreeDoc doc) keysOf) {
    final groups = <K, List<_TreeDoc>>{};
    for (final doc in _docs) {
      for (final key in keysOf(doc)) {
        (groups[key] ??= []).add(doc);
      }
    }
    return groups;
  }

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
  String? nameOf(String docPath) => _byPath[docPath]?.name;

  /// Whether the doc at [docPath] is the `api` doc of a feature.
  bool isApi(String docPath) =>
      nameOf(docPath)?.startsWith('$_apiTypeId:') ?? false;

  /// The story and FR numbers of the FR doc that [cell], a `## FR trace` FR
  /// cell of the `api` doc at [apiDocPath], names; null for a cell that
  /// names none.
  ({int story, int fr})? frNamedBy(String apiDocPath, String cell) {
    final place = _placeOf(apiDocPath);
    if (place == null) return null;
    final name = '${place.featureName}/$cell';
    for (final doc in _byFeature[place.feature] ?? const <_TreeDoc>[]) {
      if (doc.kind == _DocKind.fr && doc.name == name) {
        return (story: doc.story!, fr: doc.fr!);
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
    if (feature == null || label.isPartOfPath) return const [];
    final isStoryLess = label.feature != null && parts.story == null;
    if (parts.fr != null && isStoryLess) return const [];
    final legacyId = _legacyIdOf(label);
    final inFeature = legacyId == null
        ? _byFeature[feature]
        : _byLegacyFolder[legacyId];
    final inScope = (inFeature ?? const <_TreeDoc>[]).where(
      (doc) =>
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

/// The first folder a legacy ID names, as written: `ai02`, or a whole folder
/// name.
String? _legacyIdOf(NumberLabel label) =>
    label.prefix == null ? null : label.written.split('/').first;

/// The feature folder name of [legacyPath], or null.
String? _legacyFolderOf(String legacyPath) {
  final segments = legacyPath.split('/');
  return segments.length < 4 ? null : segments[2];
}

/// [docPath] with its legacy feature folder replaced by the FeaturePath that
/// [featurePaths] gives it, else [docPath] as it is.
String _atFeaturePath(String docPath, Map<String, String> featurePaths) {
  for (final MapEntry(key: folder, value: featurePath)
      in featurePaths.entries) {
    if (docPath.startsWith(folder)) {
      return 'prds/features/$featurePath/${docPath.substring(folder.length)}';
    }
  }
  return docPath;
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

_Base _baseOf(_Place? place) {
  return place == null
      ? _noPlace
      : (feature: place.feature, story: place.story);
}

/// The place of a legacy doc path, read by the legacy tree's fixed layout.
_Place? _legacyPlaceOf(String docPath) {
  final located = _locateLegacy(docPath);
  return located == null
      ? null
      : (
          feature: located.feature,
          featureName: located.featureSlug,
          story: located.story,
        );
}

/// Reads the feature and story a legacy doc path sits under, or null for a
/// path under neither `prds/features/` nor `specs/`.
_Located? _locateLegacy(String docPath) {
  final segments = docPath.split('/');
  final isSpec = segments.length == 3 && segments.first == 'specs';
  final isPrd =
      segments.length >= 4 &&
      segments[0] == 'prds' &&
      segments[1] == 'features';
  if (!isSpec && !isPrd) return null;
  final folder = _featureFolder.firstMatch(segments[isSpec ? 1 : 2]);
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

// MARK: - Index

/// The numbered docs of a run and the place of each typed doc.
typedef _Index = ({
  List<_TreeDoc> docs,
  _Place? Function(String docPath) placeOf,
});

/// The `{nn}` and `{slug}` of a doc's own path segment, and whether the doc is
/// a spec doc: a file with no placeholder of its own.
typedef _Own = ({int? number, String? slug, bool isSpec});

/// Reads each typed doc of [docs] as the index does: its place from its type
/// and parent chain in [set], never from the shape of its path.
_Index _readIndex(
  Iterable<({String docPath, String lf})> docs,
  MergedSet set,
  Map<String, MergedDocType> docTypes,
) {
  final typed = [
    for (final (:docPath, :lf) in docs)
      if (docTypes[docPath] case final type?)
        (docPath: docPath, lf: lf, type: type),
  ];
  final indexed = {
    for (final (:docPath, lf: _, :type) in typed)
      docPath: _indexedOf(docPath, type),
  };
  final parents = resolveParents(indexed.values, set).parents;
  final owns = {
    for (final (:docPath, lf: _, :type) in typed)
      docPath: _ownOf(set, type, docPath),
  };
  final places = {
    for (final doc in indexed.values)
      doc.docPath: _placeIn(doc, indexed, parents, owns),
  };
  return (
    docs: [
      for (final (:docPath, :lf, :type) in typed)
        ?_indexedDoc(
          docPath,
          lf,
          type,
          indexed[docPath]!.name,
          places[docPath],
          owns[docPath],
        ),
    ],
    placeOf: (docPath) => places[docPath],
  );
}

IndexedDoc _indexedOf(String docPath, MergedDocType type) => IndexedDoc(
  docPath: docPath,
  docTypeId: type.id,
  name: docNameOf(docPath, type),
  frontmatter: const {},
  tokens: 0,
);

/// The place of [doc]: the nearest `feature` up its parent chain, [doc]
/// included, and the nearest `user_story`; null when no numbered feature is
/// above it.
_Place? _placeIn(
  IndexedDoc doc,
  Map<String, IndexedDoc> indexed,
  Map<String, String> parents,
  Map<String, _Own?> owns,
) {
  int? story;
  for (IndexedDoc? at = doc; at != null; at = indexed[parents[at.docPath]]) {
    final number = owns[at.docPath]?.number;
    if (at.docTypeId == storyType) story ??= number;
    if (at.docTypeId == featureType) {
      return number == null
          ? null
          : (feature: number, featureName: at.name, story: story);
    }
  }
  return null;
}

/// The own-segment values of the doc at [docPath], or null when no path of
/// [type] matches it.
_Own? _ownOf(MergedSet set, MergedDocType type, String docPath) {
  final shape = DocPathShape.ofDoc(type, set, docPath);
  if (shape == null) return null;
  final own = shape.matchOwn(docPath.split('/')[shape.ownIndex]);
  return own == null
      ? null
      : (number: own.number, slug: own.slug, isSpec: isSpecDocShape(shape));
}

/// The numbered doc at [docPath], or null for a doc the pass does not number:
/// a feature, user story, FR, or spec doc under a feature.
_TreeDoc? _indexedDoc(
  String docPath,
  String lf,
  MergedDocType type,
  String indexName,
  _Place? place,
  _Own? own,
) {
  if (place == null || own == null) return null;
  final kind = switch (type.id) {
    featureType => _DocKind.feature,
    storyType => _DocKind.story,
    frType => _DocKind.fr,
    _ when own.isSpec => _DocKind.spec,
    _ => null,
  };
  if (kind == null || (kind == _DocKind.fr && own.number == null)) return null;
  final isTyped = kind == _DocKind.feature || kind == _DocKind.spec;
  return _TreeDoc._(
    path: docPath,
    lf: lf,
    kind: kind,
    feature: place.feature,
    story: place.story,
    fr: kind == _DocKind.fr ? own.number : null,
    name: isTyped ? '${type.id}:$indexName' : indexName,
    slug: own.slug ?? place.featureName,
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
    this.legacyFolder,
  });

  static _TreeDoc? parseLegacy(String docPath, String lf, MergedDocType? type) {
    final located = _locateLegacy(docPath);
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
              name: '$featureType:$featureSlug',
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

  /// This doc with [legacyFolder] set: the name of its legacy feature folder.
  _TreeDoc withLegacyFolder(String? legacyFolder) => _TreeDoc._(
    path: path,
    lf: lf,
    kind: kind,
    feature: feature,
    story: story,
    fr: fr,
    name: name,
    slug: slug,
    legacyFolder: legacyFolder,
  );

  final String? legacyFolder;
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
    List<({String docPath, String lf})> docs, {
    required MergedSet set,
    required Map<String, MergedDocType> docTypes,
  }) {
    final tree = LabelTree.of(docs, set: set, docTypes: docTypes);
    final sorted = _sortedBy(docs, (doc) => doc.docPath);
    final results = {
      for (final (:docPath, :lf) in sorted)
        docPath: _convertDoc(tree, docPath, lf),
    };
    final docTexts = withLabelAnchorsMoved(sorted, {
      for (final MapEntry(:key, :value) in results.entries) key: value.lf,
    }, docTypes);
    final files = <_FileResult>[
      for (final (:docPath, lf: _) in sorted)
        (
          path: docPath,
          converted: docTexts.containsKey(docPath),
          headings: results[docPath]!.headings,
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

  /// The `number labels:` plan line: each doc the pass rewrites, then
  /// after `; left:` each label it keeps as `<path>:<line> <label>`; null for
  /// a tree with no label.
  String? get planLine => planLineOn(const {});

  /// The [planLine] with the lines of each doc in [written], its LF text as
  /// the run writes it after every later step, counted on that text, so each
  /// cited line is the line of the file `check` reads.
  String? planLineOn(Map<String, String> written) {
    final files = [for (final file in _files) _onWritten(file, written)];
    return numberLabelsPlanLine(
      converted: [
        for (final file in files) ...[
          if (file.converted) file.path,
          for (final (:line, :label) in file.headings)
            '${file.path}:$line $label',
        ],
      ],
      kept: [
        for (final file in files)
          for (final (:line, :label) in file.kept) '${file.path}:$line $label',
      ],
    );
  }

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
    return (
      path: file.path,
      converted: file.converted,
      headings: [
        for (final heading in file.headings)
          (
            line: _sameLineIn(passLines, writtenLines, heading.line),
            label: heading.label,
          ),
      ],
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

/// The `number labels:` plan line: the [converted] entries, then after
/// `; left:` the [kept] ones; null when both are empty.
String? numberLabelsPlanLine({
  required Iterable<String> converted,
  required Iterable<String> kept,
}) {
  if (converted.isEmpty && kept.isEmpty) return null;
  return '$_planLabel${converted.join(', ')}'
      '${kept.isEmpty ? '' : '$_leftLabel${kept.join(', ')}'}';
}

/// A doc the pass read, whether it changed it, the operation headings it
/// converted, and the labels it kept.
typedef _FileResult = ({
  String path,
  bool converted,
  List<_Kept> headings,
  List<_Kept> kept,
});

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

/// Returns the text of each of [docs] a label conversion changes, its links
/// to a heading whose slug the conversion changed set to the new slug (D58,
/// ledger G11); the one step both the upgrade and the legacy run take.
///
/// [docs] are the texts before the conversion and [converted] the texts
/// after it, by the path each doc's links are relative to. A heading changes
/// its slug when its operation label is dropped or a label in its text
/// becomes a doc name; the move is read heading by heading.
Map<String, String> withLabelAnchorsMoved(
  List<({String docPath, String lf})> docs,
  Map<String, String> converted,
  Map<String, MergedDocType> docTypes,
) {
  final texts = {
    for (final (:docPath, :lf) in docs)
      if (converted[docPath] case final text? when text != lf) docPath: text,
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
  for (final (:line, :column, :length, text: replacement) in edits.reversed) {
    final current = lines[line];
    lines[line] =
        current.substring(0, column) +
        replacement +
        current.substring(column + length);
  }
  return lines.join('\n');
}
