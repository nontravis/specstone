import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/number_label.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_words.dart'
    show itemIdPrefixesOf;
import 'package:specstone_core/src/index_query/parents.dart'
    show resolveParents;
import 'package:specstone_core/src/setup_migration/legacy_tree.dart'
    show legacyFolderIdOf;
import 'package:specstone_core/src/setup_migration/models/label_doc.dart';
import 'package:specstone_core/src/setup_migration/models/story_fr.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

// MARK: - Constants

final _featureFolder = RegExp(r'^f(\d+)_([a-z0-9_]+)$');
final _storyFolder = RegExp(r'^us(\d+)_([a-z0-9_]+)$');
final _frFile = RegExp(r'^fr(\d+)_([a-z0-9_]+)\.md$');

const _featureFile = 'FEATURE.md';
const _storyFile = 'USER_STORY.md';
const _apiTypeId = 'api';

// MARK: - Types

/// The feature and story a label reads against; null for a place with none.
final class _Base {
  const new({required this.feature, required this.story});

  final int? feature;
  final int? story;
}

/// A label with every part it lacks taken from its [_Base].
final class _Parts {
  const new({required this.feature, required this.story, required this.fr});

  final int? feature;
  final int? story;
  final int? fr;
}

enum _DocKind { feature, story, fr, spec }

/// The feature a doc sits under, by number and name, and its story's number
/// when it sits under one.
final class _Place {
  const new({
    required this.feature,
    required this.featureName,
    required this.story,
  });

  final int feature;
  final String featureName;
  final int? story;
}

/// The place a legacy doc path gives: its feature and story, and what is left
/// of the path.
final class _Located {
  const new({
    required this.feature,
    required this.featureSlug,
    required this.story,
    required this.storySlug,
    required this.rest,
    required this.isSpec,
  });

  final int feature;
  final String featureSlug;
  final int? story;
  final String? storySlug;
  final List<String> rest;
  final bool isSpec;
}

/// No feature and no story: a doc outside any feature.
const _noPlace = _Base(feature: null, story: null);

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
    Iterable<LabelDoc> docs, {
    required MergedSet set,
    required Map<String, MergedDocType> docTypes,
  }) : this._fromIndex(
         _readIndex(docs, set, docTypes),
         itemIdPrefixesOf(set.docTypes),
       );

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
    Iterable<LegacyLabelDoc> docs, {
    Map<String, MergedDocType> docTypes = const {},
    Map<String, String> featurePaths = const {},
  }) : itemPrefixes = itemIdPrefixesOf(docTypes.values),
       _docs = [
         for (final LegacyLabelDoc(:docPath, :legacyPath, :lf) in docs)
           ?_TreeDoc.parseLegacy(
             docPath,
             lf,
             docTypes[docPath],
           )?.withLegacyFolder(_legacyFolderOf(legacyPath)),
       ],
       _placeOf = ((path) =>
           _legacyPlaceOf(_atFeaturePath(path, featurePaths)));

  new _fromIndex(_Index index, this.itemPrefixes)
    : _docs = index.docs,
      _placeOf = index.placeOf;

  /// The item ID prefixes of the doc types the tree reads, which the labels
  /// of its docs read their item IDs by.
  final Set<String> itemPrefixes;

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
  /// for none or two or more.
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
  StoryFr? frNamedBy(String apiDocPath, String cell) {
    final place = _placeOf(apiDocPath);
    if (place == null) return null;
    final name = '${place.featureName}/$cell';
    for (final doc in _byFeature[place.feature] ?? const <_TreeDoc>[]) {
      if (doc.kind == _DocKind.fr && doc.name == name) {
        return StoryFr(story: doc.story!, fr: doc.fr!);
      }
    }
    return null;
  }

  String? _resolveFrom(NumberLabel label, _Base base, NumberLabel? before) {
    final readings = <_Base>[base];
    if (before != null && label.feature == null) {
      final prior = _partsOf(before, base);
      readings.add(_Base(feature: prior.feature, story: prior.story));
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
    return _Parts(feature: label.feature, story: label.story, fr: label.fr);
  }
  if (label.story != null) {
    return _Parts(feature: base.feature, story: label.story, fr: label.fr);
  }
  return _Parts(feature: base.feature, story: base.story, fr: label.fr);
}

_Base _baseOf(_Place? place) {
  return place == null
      ? _noPlace
      : _Base(feature: place.feature, story: place.story);
}

/// The place of a legacy doc path, read by the legacy tree's fixed layout.
_Place? _legacyPlaceOf(String docPath) {
  final located = _locateLegacy(docPath);
  return located == null
      ? null
      : _Place(
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
  return _Located(
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
final class _Index {
  const new({required this.docs, required this.placeOf});

  final List<_TreeDoc> docs;
  final _Place? Function(String docPath) placeOf;
}

/// The `{nn}` and `{slug}` of a doc's own path segment, and whether the doc is
/// a spec doc: a file with no placeholder of its own.
final class _Own {
  const new({required this.number, required this.slug, required this.isSpec});

  final int? number;
  final String? slug;
  final bool isSpec;
}

/// Reads each typed doc of [docs] as the index does: its place from its type
/// and parent chain in [set], never from the shape of its path.
_Index _readIndex(
  Iterable<LabelDoc> docs,
  MergedSet set,
  Map<String, MergedDocType> docTypes,
) {
  final typed = [
    for (final LabelDoc(:docPath, :lf) in docs)
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
  return _Index(
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
          : _Place(feature: number, featureName: at.name, story: story);
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
      : _Own(number: own.number, slug: own.slug, isSpec: isSpecDocShape(shape));
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

  /// The doc's name as a doc-name mention writes it.
  final String name;

  /// The slug of the folder or file a folder path ends with.
  final String slug;
}
