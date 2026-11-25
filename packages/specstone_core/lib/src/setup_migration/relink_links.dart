import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart'
    show headingSlugOf;
import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, resolveDocLink;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show readDocAddress;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show LinkPlace, withLinkPlaces;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show sectionKeyOf;
import 'package:specstone_core/src/index_query/link_places.dart'
    show sourceHrefsOf;
import 'package:specstone_core/src/index_query/link_scan.dart' show linkScanOf;
import 'package:specstone_core/src/index_query/models/link_scan.dart';
import 'package:specstone_core/src/index_query/models/link_source.dart';
import 'package:specstone_core/src/setup_migration/followed_links.dart';
import 'package:specstone_core/src/setup_migration/models/relink_rules.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';

/// One doc a relink pass may reach, as the run leaves it.
final class RelinkDoc {
  const new({
    required this.typeId,
    required this.name,
    required this.headingSlugs,
    required this.sectionHeaders,
    this.htmlIds = const {},
  });

  final String typeId;

  /// The Name the doc answers to, as a typed link text names it.
  final String name;

  /// One slug per heading, in file order, a repeat suffixed `-1`, `-2`.
  final List<String> headingSlugs;

  /// The header of each section of the doc's merged type, by section id.
  final Map<String, String> sectionHeaders;

  /// The doc's html ids, which a link anchor may name as it names a heading.
  final Set<String> htmlIds;

  /// Whether [anchor] names a heading slug or an html id of this doc.
  bool holds(String anchor) =>
      headingSlugs.contains(anchor) || htmlIds.contains(anchor);
}

/// The docs a relink pass may reach, by DocPath.
final class RelinkTargets {
  new(this._byDocPath);

  final Map<String, RelinkDoc> _byDocPath;

  RelinkDoc? at(String docPath) => _byDocPath[docPath];
}

/// What one link becomes: a new place, or its text alone.
final class _Fate {
  const new(this.change, {this.place}) : unwraps = place == null;

  final LinkChange change;
  final LinkPlace? place;
  final bool unwraps;
}

/// One replacement in a body: the units from [start] up to [end] take [text].
final class _Edit {
  const new(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

const _openBracket = 0x5B;

/// The segment that names a doc's own folder in a path.
const _hereSegment = './';

/// Returns [lf], the doc at [docPath], with each link an earlier run's
/// `merge_doc`, `drop_section`, or `rename_section` step left broken set
/// right by [rules], judged against [targets] as they stand.
///
/// A typed link text naming a folded type takes the `to` type and the name of
/// the doc its destination reaches; a self link once naming the folded doc
/// takes the first mapped heading; an anchor a drop took loses it, and an old
/// renamed anchor takes the new slug. Only text after the frontmatter is read,
/// and a link in a code span or a fenced block keeps every byte.
FollowedLinks relinkLinks(
  String lf,
  String docPath, {
  required RelinkRules rules,
  required RelinkTargets targets,
}) {
  if (rules.isEmpty) return FollowedLinks(lf, const []);
  final body = Doc.parse(lf).afterFrontmatter;
  final changes = <LinkChange>{};
  final fates = <String, _Fate?>{};
  _Fate? fateOf(String href) => fates.putIfAbsent(
    href,
    () => _noted(_anchorFateOf(href, docPath, rules, targets), changes),
  );
  final selfLinked = _withSelfLinksRelinked(
    body,
    docPath,
    folds: rules.folds,
    targets: targets,
    changes: changes,
  );
  final edited = withLinkPlaces(
    selfLinked,
    (href) => fateOf(href)?.place,
    textOf: _mayNameFolded(selfLinked, rules.folds)
        ? (href, text) =>
              _typedText(href, text, docPath, rules, targets, changes)
        : null,
    unwraps: (href) => fateOf(href)?.unwraps ?? false,
  );
  return FollowedLinks(
    edited == body ? lf : lf.substring(0, lf.length - body.length) + edited,
    [
      for (final change in LinkChange.values)
        if (changes.contains(change)) change,
    ],
  );
}

_Fate? _noted(_Fate? fate, Set<LinkChange> changes) {
  if (fate != null) changes.add(fate.change);
  return fate;
}

/// Whether [body] may hold a link text that starts with a folded type's
/// `<from id>:`, so the link text pass needs its parse.
bool _mayNameFolded(String body, List<MergeDoc> folds) =>
    folds.any((fold) => body.contains('[${fold.fromId}:'));

/// Returns the fate of [href], written in the doc at [docPath], at an anchor
/// its target lacks that a drop took or a rename moved, or null when it
/// keeps its target.
_Fate? _anchorFateOf(
  String href,
  String docPath,
  RelinkRules rules,
  RelinkTargets targets,
) {
  if (resolveDocLink(href, docPath)
      case DocTarget(docPath: final target, anchor: final anchor?)
      when anchor.isNotEmpty) {
    final reached = targets.at(target);
    if (reached == null || reached.holds(anchor)) return null;
    if (_isDropped(anchor, reached, rules.drops)) {
      return target == docPath
          ? const _Fate(LinkChange.dropped)
          : const _Fate(
              LinkChange.dropped,
              place: LinkPlace(dropsAnchor: true),
            );
    }
    if (_renamedSlug(anchor, reached, rules.renames) case final slug?) {
      return _Fate(
        LinkChange.renamed,
        place: LinkPlace(anchor: Uri.encodeComponent(slug)),
      );
    }
  }
  return null;
}

/// Whether [anchor] is the header slug of a drop of [reached]'s type.
bool _isDropped(String anchor, RelinkDoc reached, List<DropSection> drops) =>
    drops.any(
      (drop) =>
          drop.docTypes.contains(reached.typeId) &&
          headingSlugOf(drop.sectionHeader) == anchor,
    );

/// Returns the new slug a rename of [reached]'s type gives its old slug
/// [anchor], or null when none does or [reached] lacks that new slug.
String? _renamedSlug(
  String anchor,
  RelinkDoc reached,
  List<RenameSection> renames,
) {
  for (final rename in renames) {
    final slug = headingSlugOf(rename.toHeader);
    if (rename.docType == reached.typeId &&
        headingSlugOf(rename.fromHeader) == anchor &&
        reached.headingSlugs.contains(slug)) {
      return slug;
    }
  }
  return null;
}

/// Returns [text], a link text whose [href] is written in the doc at
/// [docPath], as `T:<name>` when it names a folded type F and its destination
/// reaches a doc of type T, or null when it keeps its text.
String? _typedText(
  String href,
  String text,
  String docPath,
  RelinkRules rules,
  RelinkTargets targets,
  Set<LinkChange> changes,
) {
  final address = readDocAddress(text);
  final typeId = address.typeId;
  if (typeId == null || !address.isName) return null;
  final reached = switch (resolveDocLink(href, docPath)) {
    DocTarget(docPath: final target) => targets.at(target),
    _ => null,
  };
  if (reached == null) return null;
  final fold = _foldOf(rules.folds, fromId: typeId, toId: reached.typeId);
  if (fold == null) return null;
  changes.add(LinkChange.merged);
  return '${fold.toId}:${reached.name}${_mappedKey(fold, address.sectionKey)}';
}

MergeDoc? _foldOf(
  List<MergeDoc> folds, {
  required String fromId,
  required String toId,
}) => folds
    .where((fold) => fold.fromId == fromId && fold.toId == toId)
    .firstOrNull;

/// Returns `#<key>` with [key] set to the `to` id a section of [fold] maps
/// it to, kept when none does; empty for a null [key].
String _mappedKey(MergeDoc fold, String? key) =>
    key == null ? '' : '#${_sectionOf(fold, key)?.toId ?? key}';

/// Returns the section of [fold] that maps the `from` section keyed [key], by
/// its id or its header's section key, or null.
MergeSection? _sectionOf(MergeDoc fold, String key) => fold.sections
    .where(
      (section) =>
          section.fromId == key || sectionKeyOf(section.fromHeader) == key,
    )
    .firstOrNull;

/// What one self link a fold left becomes: its text after the typed text row,
/// and the `to` section whose heading it takes.
final class _SelfLink {
  const new(this.text, this.toId);

  final String text;

  /// The id of the `to` section; null when the fold maps none.
  final String? toId;
}

/// Returns [body], the doc at [docPath], with each anchorless self link a
/// fold left, by its text, set to the slug of the heading that text maps to,
/// or unwrapped to its new text when the doc lacks that heading.
///
/// The choice reads each link's text, so it edits link sources one by one
/// where [withLinkPlaces] places every link of one href alike.
String _withSelfLinksRelinked(
  String body,
  String docPath, {
  required List<MergeDoc> folds,
  required RelinkTargets targets,
  required Set<LinkChange> changes,
}) {
  final here = targets.at(docPath);
  if (here == null) return body;
  final ownFolds = [
    for (final fold in folds)
      if (fold.toId == here.typeId) fold,
  ];
  if (ownFolds.isEmpty || !_mayNameSelf(body, here, ownFolds)) return body;
  final scan = linkScanOf(body, firstLine: 1);
  final hrefs = sourceHrefsOf(body, scan.sources);
  if (hrefs == null) return body;
  final edits = [
    for (final (index, source) in scan.sources.indexed)
      if (_selfLinkOf(body, source, hrefs[index], docPath, here, ownFolds)
          case final link?)
        ..._selfLinkEdits(scan, index, here, link),
  ];
  if (edits.isNotEmpty) changes.add(LinkChange.merged);
  return _withEdits(body, edits);
}

/// Whether [body], the doc [here], may hold a self link a fold of [folds]
/// left: a link text that starts with `<from id>:` or `<to id>:`, or holds the
/// `from` path's file name.
bool _mayNameSelf(String body, RelinkDoc here, List<MergeDoc> folds) =>
    _mayNameFolded(body, folds) ||
    body.contains('[${here.typeId}:') ||
    folds.any((fold) => body.contains(_fileNameOf(fold)));

/// The file name of [fold]'s `from` path pattern, such as `ERROR.md`.
String _fileNameOf(MergeDoc fold) => fold.fromPath.split('/').last;

/// Returns what [source], an anchorless self link of the doc at [docPath],
/// [here], becomes when a fold of [folds] left it, or null.
///
/// A fold left it when its text is `F:<name>`, `F:<name>#<key>`, or the file
/// name of F's `from` path, in a code span or not, or `T:<name>` naming
/// [here], which an earlier fold retyped and left whole.
_SelfLink? _selfLinkOf(
  String body,
  LinkSource source,
  String? href,
  String docPath,
  RelinkDoc here,
  List<MergeDoc> folds,
) {
  final textEnd = source.textEnd;
  if (href == null ||
      textEnd == null ||
      body.codeUnitAt(source.offset) != _openBracket) {
    return null;
  }
  if (resolveDocLink(href, docPath)
      case DocTarget(docPath: final target, anchor: null)
      when target == docPath) {
    final text = body.substring(source.offset + 1, textEnd);
    return _typedSelfLink(text, here, folds) ??
        _fileSelfLink(text, folds) ??
        _ownSelfLink(text, here);
  }
  return null;
}

/// Returns the self link of [text] when it is `T:<name>` naming [here]: it
/// takes no heading, so it unwraps to its text.
_SelfLink? _ownSelfLink(String text, RelinkDoc here) {
  final address = readDocAddress(text);
  final isOwn =
      address.typeId == here.typeId &&
      address.body == here.name &&
      address.sectionKey == null;
  return isOwn ? _SelfLink(text, null) : null;
}

/// Returns the self link of [text] when it is `F:<name>` or `F:<name>#<key>`
/// of a fold of [folds]: the `<key>`'s mapped section, else the first one.
_SelfLink? _typedSelfLink(String text, RelinkDoc here, List<MergeDoc> folds) {
  final address = readDocAddress(text);
  if (address.typeId == null || !address.isName) return null;
  final fold = folds.where((fold) => fold.fromId == address.typeId).firstOrNull;
  if (fold == null) return null;
  final key = address.sectionKey;
  return _SelfLink(
    '${fold.toId}:${here.name}${_mappedKey(fold, key)}',
    (key == null ? null : _sectionOf(fold, key))?.toId ??
        fold.sections.firstOrNull?.toId,
  );
}

/// Returns the self link of [text] when it is the file name of a fold's
/// `from` path, in a code span or not, `./` before it or not: its text kept,
/// the first section.
_SelfLink? _fileSelfLink(String text, List<MergeDoc> folds) {
  final isSpan = text.length > 2 && text.startsWith('`') && text.endsWith('`');
  final written = isSpan ? text.substring(1, text.length - 1) : text;
  final name = written.startsWith(_hereSegment)
      ? written.substring(_hereSegment.length)
      : written;
  final fold = folds.where((fold) => _fileNameOf(fold) == name).firstOrNull;
  return fold == null ? null : _SelfLink(text, fold.sections.firstOrNull?.toId);
}

/// Returns the edits that set the self link at [index] of [scan] to
/// `[<text>](#<slug>)`, or to its text alone when [here] lacks the slug.
List<_Edit> _selfLinkEdits(
  LinkScan scan,
  int index,
  RelinkDoc here,
  _SelfLink link,
) {
  final source = scan.sources[index];
  final text = link.text;
  final slug = _slugOf(link.toId, here);
  if (slug == null) return [_Edit(source.offset, source.end, text)];
  final anchor = '#${Uri.encodeComponent(slug)}';
  final destination = scan.destinations
      .where((destination) => destination.link == index)
      .firstOrNull;
  // A reference link's destination is its definition's, shared with others.
  if (destination == null) {
    return [_Edit(source.offset, source.end, '[$text]($anchor)')];
  }
  return [
    _Edit(source.offset + 1, source.textEnd!, text),
    _Edit(destination.start, destination.end, anchor),
  ];
}

/// Returns the slug of the heading of [here] for the section [toId], or null
/// when [here] lacks it.
String? _slugOf(String? toId, RelinkDoc here) {
  final header = here.sectionHeaders[toId];
  if (header == null) return null;
  final slug = headingSlugOf(header);
  return here.headingSlugs.contains(slug) ? slug : null;
}

/// Returns [body] with each of [edits], which never overlap, applied.
String _withEdits(String body, List<_Edit> edits) {
  final rightFirst = [...edits]..sort((a, b) => b.start.compareTo(a.start));
  var result = body;
  for (final edit in rightFirst) {
    result = result.replaceRange(edit.start, edit.end, edit.text);
  }
  return result;
}
