import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart'
    show anchorsOfBody;
import 'package:specstone_core/src/doc_model/models/doc_anchors.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;

/// One heading anchor of a doc the run plans: the doc's planned DocPath and
/// the heading's slug there.
final class HeadingAt {
  const new(this.docPath, this.slug);

  final String docPath;
  final String slug;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is HeadingAt && other.docPath == docPath && other.slug == slug;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(docPath, slug);
}

/// Follows each heading of the run's docs, by its pre-run anchor, through the
/// steps that rename, drop, or fold sections.
///
/// A doc's track lists the pre-run anchor of each heading it holds now, in
/// file order. A step whose heading count the track cannot explain loses the
/// track; links to its headings then keep their anchors.
final class HeadingLedger {
  final _tracks = <String, List<HeadingAt>?>{};
  final _preRun = <String, DocAnchors>{};
  final _aliases = <HeadingAt, HeadingAt>{};
  final _folded = <String, String>{};
  final _wholeDoc = <String, HeadingAt?>{};
  final _unknown = <HeadingAt>{};

  /// Records that a `rename_section` step turned [before], the doc at
  /// [docPath], into [after]; each heading keeps its place.
  void renamed(
    String docPath, {
    required String before,
    required String after,
  }) {
    final track = _trackOf(docPath, before);
    if (track != null && _headingCountOf(after) != track.length) {
      _lose(docPath);
    }
  }

  /// Records that a `drop_section` step of [header] turned [before], the doc
  /// at [docPath], into [after].
  void dropped(
    String docPath, {
    required String before,
    required String after,
    required String header,
  }) {
    final track = _trackOf(docPath, before);
    if (track == null) return;
    final chunks = _chunksOf(before, track);
    if (chunks == null) return _lose(docPath);
    final key = headerKey(header);
    final sections = Doc.parse(before).sections;
    final kept = [
      ...chunks.first,
      for (final (index, section) in sections.indexed)
        if (headerKey(section.headerText) != key) ...chunks[index + 1],
    ];
    _tracks[docPath] = kept;
    if (_headingCountOf(after) != kept.length) _lose(docPath);
  }

  /// Records that a `merge_doc` step folded [fromLf], the doc at [fromPath],
  /// into the doc at [toPath], turning [toBefore] into [toAfter].
  ///
  /// [groups] lists, per section the fold adds in order, the indexes of the
  /// `from` sections joined under it.
  void folded({
    required String fromPath,
    required String fromLf,
    required String toPath,
    required String toBefore,
    required String toAfter,
    required List<List<int>> groups,
  }) {
    _folded[fromPath] = toPath;
    final from = _trackOf(fromPath, fromLf);
    final to = _trackOf(toPath, toBefore);
    _tracks.remove(fromPath);
    final chunks = from == null ? null : _chunksOf(fromLf, from);
    if (to == null || chunks == null) {
      _unknown.addAll(from ?? const []);
      return _lose(toPath);
    }
    final hasTitle = _hasTitle(fromLf) && chunks.first.isNotEmpty;
    // A `to` doc the run creates takes the folded doc's title.
    final title = hasTitle && toBefore.isEmpty ? chunks.first.first : null;
    final added = _addedHeadings(chunks, groups, hasTitle: hasTitle);
    _wholeDoc[fromPath] = groups.isEmpty ? null : added.first;
    if (title != null) _aliases.remove(title);
    final track = [...to, ?title, ...added];
    _tracks[toPath] = track;
    if (_headingCountOf(toAfter) != track.length) _lose(toPath);
  }

  /// Returns the anchors each followed heading has in the run's final texts,
  /// which [finalTexts] gives by planned DocPath.
  FinalAnchors resolve(Map<String, String> finalTexts) {
    final places = <HeadingAt, HeadingAt>{};
    final finalIds = <String, Set<String>>{};
    for (final MapEntry(key: docPath, value: track) in _tracks.entries) {
      if (track == null) continue;
      final text = finalTexts[docPath];
      final anchors = text == null
          ? null
          : anchorsOfBody(Doc.parse(text).afterFrontmatter);
      if (anchors == null || anchors.headingSlugs.length != track.length) {
        _unknown.addAll(track);
        continue;
      }
      finalIds[docPath] = anchors.htmlIds;
      for (final (index, origin) in track.indexed) {
        places[origin] = HeadingAt(docPath, anchors.headingSlugs[index]);
      }
    }
    return FinalAnchors._(this, places, finalIds);
  }

  /// Returns the pre-run anchors of each heading the fold adds, in order, and
  /// aliases each heading the fold joins or drops to the one it lands under.
  List<HeadingAt> _addedHeadings(
    List<List<HeadingAt>> chunks,
    List<List<int>> groups, {
    required bool hasTitle,
  }) {
    final lead = chunks.first;
    final added = <HeadingAt>[];
    for (final (groupIndex, group) in groups.indexed) {
      final header = chunks[group.first + 1].first;
      added.add(header);
      if (groupIndex == 0) added.addAll(hasTitle ? lead.skip(1) : lead);
      for (final member in group) {
        final [joined, ...subheadings] = chunks[member + 1];
        if (joined != header) _aliases[joined] = header;
        added.addAll(subheadings);
      }
    }
    if (hasTitle && added.isNotEmpty) _aliases[lead.first] = added.first;
    return added;
  }

  /// Returns the track of [docPath], started from [lf] the first time, or
  /// null when it is lost.
  List<HeadingAt>? _trackOf(String docPath, String lf) {
    if (_tracks.containsKey(docPath)) return _tracks[docPath];
    final anchors = anchorsOfBody(Doc.parse(lf).afterFrontmatter);
    _preRun[docPath] =
        anchors ??
        const DocAnchors(headingSlugs: [], headingLevels: [], htmlIds: {});
    return _tracks[docPath] = anchors == null
        ? null
        : [for (final slug in anchors.headingSlugs) HeadingAt(docPath, slug)];
  }

  void _lose(String docPath) {
    _unknown.addAll(_tracks[docPath] ?? const []);
    _tracks[docPath] = null;
  }

  /// Returns [track], the headings of [lf], split by the text before the
  /// first `##` section and by each section, each section's first its own
  /// header, or null when the split parse counts other headings.
  List<List<HeadingAt>>? _chunksOf(String lf, List<HeadingAt> track) {
    final doc = Doc.parse(lf);
    final lines = doc.afterFrontmatter.split('\n');
    final starts = [0, ...doc.sectionLineIndexes, lines.length];
    final chunks = <List<HeadingAt>>[];
    var at = 0;
    for (var i = 0; i + 1 < starts.length; i++) {
      final chunk = lines.sublist(starts[i], starts[i + 1]).join('\n');
      final count = anchorsOfBody(chunk)?.headingSlugs.length;
      final isSection = i > 0;
      if (count == null ||
          (isSection && count == 0) ||
          at + count > track.length) {
        return null;
      }
      chunks.add(track.sublist(at, at += count));
    }
    return at == track.length ? chunks : null;
  }
}

/// Where each link target of the run's docs is in the final texts.
final class FinalAnchors {
  const new _(this._ledger, this._places, this._finalIds);

  final HeadingLedger _ledger;
  final Map<HeadingAt, HeadingAt> _places;
  final Map<String, Set<String>> _finalIds;

  bool get isEmpty => _ledger._preRun.isEmpty;

  /// Whether a `merge_doc` step folded a doc into the doc at [docPath].
  bool isFoldTarget(String docPath) => _ledger._folded.containsValue(docPath);

  /// Whether a step followed the headings of the doc at [docPath].
  bool follows(String docPath) => _ledger._preRun.containsKey(docPath);

  /// Whether a `merge_doc` step folded the doc at [docPath].
  bool isFolded(String docPath) => _ledger._folded.containsKey(docPath);

  /// Returns where a link to [anchor] of the doc at [docPath] lands in the
  /// final texts, a null [anchor] naming the doc whole, or null when the
  /// link keeps its target.
  LinkLanding? landingOf(String docPath, String? anchor) {
    if (!follows(docPath)) return null;
    final doc = _finalDocOf(docPath);
    if (anchor == null) return isFolded(docPath) ? _wholeDocOf(docPath) : null;
    final preRun = _ledger._preRun[docPath]!;
    if (preRun.headingSlugs.contains(anchor)) {
      return _headingLanding(HeadingAt(docPath, anchor), doc);
    }
    final ids = _finalIds[doc];
    if (preRun.htmlIds.contains(anchor) &&
        ids != null &&
        !ids.contains(anchor)) {
      return LinkLanding.lost(doc);
    }
    return LinkLanding(doc, anchor);
  }

  LinkLanding _wholeDocOf(String docPath) {
    final first = _ledger._wholeDoc[docPath];
    final at = first == null ? null : _placeOf(first);
    return LinkLanding(at?.docPath ?? _finalDocOf(docPath), at?.slug);
  }

  LinkLanding _headingLanding(HeadingAt origin, String doc) {
    final heading = _aliasOf(origin);
    if (_ledger._unknown.contains(heading)) {
      return LinkLanding(doc, origin.slug);
    }
    final at = _places[heading];
    if (at != null) return LinkLanding(at.docPath, at.slug);
    // A link to the doc it names keeps a slug a fold brought into that doc;
    // a heading the doc held, or a dropped heading of a folded doc, lost it.
    final holder = _places.entries
        .where((entry) => entry.value == HeadingAt(doc, origin.slug))
        .firstOrNull;
    return holder != null && origin.docPath == doc && holder.key.docPath != doc
        ? LinkLanding(doc, origin.slug)
        : LinkLanding.lost(doc);
  }

  HeadingAt? _placeOf(HeadingAt origin) => _places[_aliasOf(origin)];

  HeadingAt _aliasOf(HeadingAt origin) {
    var heading = origin;
    for (final seen = <HeadingAt>{heading}; ;) {
      final next = _ledger._aliases[heading];
      if (next == null || !seen.add(next)) return heading;
      heading = next;
    }
  }

  String _finalDocOf(String docPath) {
    var doc = docPath;
    for (final seen = <String>{doc}; ;) {
      final next = _ledger._folded[doc];
      if (next == null || !seen.add(next)) return doc;
      doc = next;
    }
  }
}

/// Where a link lands in the final texts: a doc and a heading slug in it,
/// a null slug naming the doc whole, or a doc whose anchor is gone.
final class LinkLanding {
  const new(this.docPath, this.slug) : isLost = false;

  const new lost(this.docPath) : slug = null, isLost = true;

  final String docPath;
  final String? slug;
  final bool isLost;
}

int _headingCountOf(String lf) =>
    anchorsOfBody(Doc.parse(lf).afterFrontmatter)?.headingSlugs.length ?? -1;

bool _hasTitle(String lf) => Doc.parse(lf).title != null;
