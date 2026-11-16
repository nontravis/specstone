import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, resolveDocLink;
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show NameMention, docMentionsInFile, extensionOfCodePath, readsNameMentions;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:specstone_core/src/document_writing/item_landing.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show relativeHref;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show TextEdit;
import 'package:specstone_core/src/document_writing/stale_mentions.dart'
    show MentionScope, StaleMention;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show ProjectPathReader;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/link_places.dart' show LinkText;
import 'package:specstone_core/src/index_query/link_scan.dart'
    show LinkSource, linkScanOf;
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/plan_hash.dart' show readPlanInput;
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show byteOrderMark;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show codeFilesOf;
import 'package:specstone_core/src/setup_migration/renumber_entries.dart'
    show withBlockValues;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

// MARK: - Edits

const _overridesKey = 'overrides';
const _separator = ', ';

/// Returns, by DocPath, the edit of every doc an item move writes: the
/// landing of [landings] and each reference that names a moved item.
///
/// A reference follows its item to the target doc and the new ID: an item
/// link, a range that holds the item, an `Overrides:` line and its `overrides`
/// entry, and a task ref. A link or range inside a moved item is read as it
/// sits in the target doc, so one that names an item of the source doc still
/// reaches it. Every doc edit refuses a doc that changed since the plan.
///
/// Throws [RenderFault] `output_not_writable` for entries that are not valid
/// YAML.
Map<String, TextEdit> itemRefEdits(
  WriteSession session,
  List<ItemLanding> landings,
) {
  if (landings.isEmpty) return const {};
  final index = session.index;
  final moves = _Moves(index, landings);
  final rewritten = {
    for (final doc in index.docs) doc: ?_linkBodyOf(index, doc, moves),
  };
  final landed = itemLandingEdits(
    session,
    landings,
    bodies: {
      for (final MapEntry(:key, :value) in rewritten.entries)
        key.docPath: value.after,
    },
  );
  final entries = _entryEdits(index, moves);
  final paths = {
    for (final doc in rewritten.keys) doc.docPath,
    ...landed.keys,
    ...entries.keys,
  };
  return {
    for (final path in paths)
      path: _composed(
        index.at(path),
        [
          for (final MapEntry(:key, :value) in rewritten.entries)
            if (key.docPath == path) value,
        ].firstOrNull,
        landed[path],
        entries[path],
      ),
  };
}

/// Returns the edit that runs the landing, or the link rewrite when the doc
/// has none, then the entry rewrite.
TextEdit _composed(
  IndexedDoc? doc,
  _Rewritten? body,
  TextEdit? landing,
  String Function(String lfText)? entries,
) => (lfText) {
  final String text;
  if (landing != null) {
    text = landing(lfText) ?? lfText;
  } else if (body != null && doc != null) {
    requireUnchanged(doc, body.before, lfText);
    text = body.after;
  } else {
    text = lfText;
  }
  final result = entries?.call(text) ?? text;
  return result == lfText ? null : result;
};

/// A doc text as the index holds it, and with its links set to their new
/// place.
final class _Rewritten {
  const new(this.before, this.after);

  final String before;
  final String after;
}

// MARK: - Moved items

/// The lines of one moved item in its source doc.
final class _Span {
  const new({required this.first, required this.last, required this.landing});

  final int first;
  final int last;
  final ItemLanding landing;
}

/// One item as a reference names it: its doc and its ID there.
final class _Named {
  const new(this.docPath, this.id);

  final String docPath;
  final String id;
}

/// Where each moved item sits and lands, as every rewrite reads it.
final class _Moves {
  new(this.index, this.landings) {
    for (final landing in landings) {
      final docPath = landing.from.doc.docPath;
      final span = itemSpanOf(index, landing);
      byKey[_keyOf(docPath, landing.from.id)] = landing;
      (spans[docPath] ??= []).add(
        _Span(first: span.first, last: span.last, landing: landing),
      );
      prefixes.add(span.located.prefix);
      if (ownOverrideOf(index, span.located) case final own?) {
        (ownLines[docPath] ??= {}).add(own.cite.line);
      }
    }
  }

  final DocIndex index;
  final List<ItemLanding> landings;

  /// Each landing by its source doc's DocPath and the ID it moves.
  final byKey = <String, ItemLanding>{};
  final spans = <String, List<_Span>>{};
  final ownLines = <String, Set<int>>{};
  final prefixes = <String>{};

  static String _keyOf(String docPath, String id) => '$docPath#$id';

  ItemLanding? landingOf(String docPath, String id, {String? sectionKey}) {
    final landing = byKey[_keyOf(docPath, id)];
    if (landing == null) return null;
    return sectionKey == null || landing.sectionKey == sectionKey
        ? landing
        : null;
  }

  /// The span of a moved item that holds file [line] of [docPath].
  _Span? spanAt(String docPath, int line) {
    for (final span in spans[docPath] ?? const <_Span>[]) {
      if (span.first <= line && line <= span.last) return span;
    }
    return null;
  }

  /// The DocPath of the doc the text of [docPath]'s file [line] sits in once
  /// the items have moved.
  String placeOf(String docPath, int line) =>
      spanAt(docPath, line)?.landing.to.docPath ?? docPath;

  /// Whether file [line] of [docPath] is the `Overrides:` line of a moved
  /// item, which lands with its link rebased.
  bool isOwnLine(String docPath, int line) =>
      ownLines[docPath]?.contains(line) ?? false;
}

// MARK: - Links

/// A link of a doc and what it reads against the doc it reaches.
final class _ReadLink {
  const new(this.link, this.read);

  final LinkText link;
  final OverrideLinkRead read;

  ItemCite? get cite => switch (read.cite) {
    final ItemCite cite => cite,
    _ => null,
  };
}

/// One replacement in a line: the characters from [start] up to [end] take
/// [text].
final class _Edit {
  const new(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

/// What one line of a doc is read against.
final class _Line {
  const new({
    required this.index,
    required this.doc,
    required this.moves,
    required this.number,
    required this.text,
  });

  final DocIndex index;
  final IndexedDoc doc;
  final _Moves moves;

  /// The file line.
  final int number;
  final String text;

  /// The DocPath of the doc this line's text sits in after the moves.
  String get place => moves.placeOf(doc.docPath, number);
}

/// Returns the LF text of [doc] with each link and range that names a moved
/// item set to its new place; null when none changes.
///
/// Every line keeps its place in the file, so the landing cuts the same lines.
_Rewritten? _linkBodyOf(DocIndex index, IndexedDoc doc, _Moves moves) {
  final content = index.contentOf(doc);
  final texts = content.lineFacts.linkTexts;
  if (texts.isEmpty) return null;
  final byLine = <int, List<_ReadLink>>{};
  for (final link in texts) {
    if (moves.isOwnLine(doc.docPath, link.line)) continue;
    final read = readOverrideLink(index, link);
    if (read != null) (byLine[link.line] ??= []).add(_ReadLink(link, read));
  }
  final lf = toLf(content.text);
  final lines = lf.split('\n');
  var changed = false;
  for (final MapEntry(key: number, value: links) in byLine.entries) {
    final line = _Line(
      index: index,
      doc: doc,
      moves: moves,
      number: number,
      text: lines[number - 1],
    );
    final edits = _editsOn(line, links);
    if (edits.isEmpty) continue;
    lines[number - 1] = _withEdits(line.text, edits);
    changed = true;
  }
  return changed ? _Rewritten(lf, lines.join('\n')) : null;
}

String _withEdits(String text, List<_Edit> edits) {
  var result = text;
  for (final edit in [...edits]..sort((a, b) => b.start.compareTo(a.start))) {
    result = result.replaceRange(edit.start, edit.end, edit.text);
  }
  return result;
}

/// Returns the edits of the links of one [line]: one per range and one per
/// link outside a range, in no order.
List<_Edit> _editsOn(_Line line, List<_ReadLink> links) {
  links.sort((a, b) => a.link.column.compareTo(b.link.column));
  final byLink = {for (final read in links) read.link: read};
  final ranges = itemRangesOn(line.text, [
    for (final read in links) (link: read.link, cite: read.read.cite),
  ]);
  final edits = <_Edit>[];
  final consumed = <LinkText>{};
  for (final range in ranges) {
    if (consumed.contains(range.first.link)) continue;
    final first = byLink[range.first.link]!;
    final ids = _spannedIds(line.index, range, first.read);
    if (ids == null) continue;
    consumed
      ..add(range.first.link)
      ..add(range.last.link);
    if (_rangeEdit(line, range, first, ids) case final edit?) edits.add(edit);
  }
  for (final read in links) {
    if (consumed.contains(read.link) || read.cite == null) continue;
    if (_linkEdit(line, read) case final edit?) edits.add(edit);
  }
  return edits;
}

/// Returns the item [id] of [target] as it reads after the moves, with the
/// path the link to it takes from [line]; null when the link keeps its text.
///
/// A link names a moved item at its landing. A link inside a moved item names
/// an item of its source doc that stays where it was, now from the target doc.
_Named? _afterOf(_Line line, String target, String sectionKey, String id) {
  if (line.moves.landingOf(target, id, sectionKey: sectionKey)
      case final landing?) {
    return _Named(landing.to.docPath, landing.newId);
  }
  final isMovedText = line.place != line.doc.docPath;
  return isMovedText && target == line.doc.docPath ? _Named(target, id) : null;
}

_Edit? _linkEdit(_Line line, _ReadLink read) {
  final link = read.link;
  final cite = read.cite!;
  final after = _afterOf(
    line,
    read.read.target.docPath,
    cite.sectionKey,
    cite.itemId,
  );
  if (after == null || !_isPlain(line.text, link)) return null;
  final written = _writtenOf(link.shown);
  final isSamePlace =
      after.docPath == read.read.target.docPath &&
      line.place == line.doc.docPath;
  final path = isSamePlace ? written.path : _pathBetween(line.place, after);
  final text = '[${after.id}]($path${written.suffix}';
  final old = '[${link.text}](${link.shown}';
  return text == old
      ? null
      : _Edit(link.column, link.column + old.length, text);
}

/// Whether [link] is written `[text](destination` at its column.
bool _isPlain(String line, LinkText link) =>
    line.startsWith('[${link.text}](${link.shown}', link.column) &&
    link.shown.contains(RegExp('[?#]'));

/// A link destination as written, split before its `?` or `#`.
final class _Written {
  const new(this.path, this.suffix);

  final String path;
  final String suffix;
}

_Written _writtenOf(String shown) {
  final at = shown.indexOf(RegExp('[?#]'));
  return _Written(shown.substring(0, at), shown.substring(at));
}

String _pathBetween(String place, _Named after) => place == after.docPath
    ? ''
    : relativeHref(
        place,
        after.docPath,
      ).split('/').map(Uri.encodeComponent).join('/');

/// Returns the IDs [range] spans in the doc it reaches, null when it spans
/// none that can be read.
List<String>? _spannedIds(
  DocIndex index,
  ItemRange range,
  OverrideLinkRead read,
) {
  final at = switch (read.anchorTarget) {
    SectionTarget(:final sectionIndex) => sectionIndex,
    _ => null,
  };
  if (at == null || at >= read.sections.length) return null;
  final ids = itemIdsInRange(
    range,
    read.sections[at],
    index.contentOf(read.target).itemFacts.sectionItems[at],
  );
  return ids.isEmpty ? null : ids;
}

/// Returns the edit that sets the range to the links and ranges that name the
/// same items after the moves; null when it keeps its text.
_Edit? _rangeEdit(
  _Line line,
  ItemRange range,
  _ReadLink first,
  List<String> ids,
) {
  final firstLink = range.first.link;
  final lastLink = range.last.link;
  if (!_isExact(line.text, firstLink) || !_isExact(line.text, lastLink)) {
    return null;
  }
  final target = first.read.target.docPath;
  final sectionKey = range.first.cite.sectionKey;
  final afters = [for (final id in ids) _afterOf(line, target, sectionKey, id)];
  if (afters.every((after) => after == null)) return null;
  final named = [
    for (final (at, id) in ids.indexed) afters[at] ?? _Named(target, id),
  ];
  final written = _writtenOf(firstLink.shown);
  final prefix = first.read.sections[_sectionAt(first.read)].prefixId;
  final pieces = [
    for (final run in _runs(named))
      ..._pieces(line, run, written, target, sectionKey, prefix),
  ];
  final text = pieces.join(_separator);
  final old = line.text.substring(firstLink.column, lastLink.endColumn);
  return text == old ? null : _Edit(firstLink.column, lastLink.endColumn, text);
}

int _sectionAt(OverrideLinkRead read) =>
    (read.anchorTarget! as SectionTarget).sectionIndex;

/// Whether the text of [link] is exactly `[text](destination)`.
bool _isExact(String line, LinkText link) =>
    link.endLine == link.line &&
    _isPlain(line, link) &&
    line.substring(link.column, link.endColumn) ==
        '[${link.text}](${link.shown})';

/// Splits [named] into runs of items that sit in one doc.
List<List<_Named>> _runs(List<_Named> named) {
  final runs = <List<_Named>>[];
  for (final item in named) {
    if (runs.isNotEmpty && runs.last.last.docPath == item.docPath) {
      runs.last.add(item);
    } else {
      runs.add([item]);
    }
  }
  return runs;
}

/// Returns the link, or the range, that names the items of [run].
List<String> _pieces(
  _Line line,
  List<_Named> run,
  _Written written,
  String target,
  String sectionKey,
  String? prefix,
) {
  final docPath = run.first.docPath;
  final path = docPath == target && line.place == line.doc.docPath
      ? written.path
      : _pathBetween(line.place, run.first);
  String linkTo(_Named item) => '[${item.id}]($path${written.suffix})';
  if (run.length > 1 && _isExactRange(line, run, sectionKey, prefix)) {
    return ['${linkTo(run.first)} to ${linkTo(run.last)}'];
  }
  return [for (final item in run) linkTo(item)];
}

/// Whether a range from the first to the last of [run] names exactly [run] in
/// its doc once the items have moved.
bool _isExactRange(
  _Line line,
  List<_Named> run,
  String sectionKey,
  String? prefix,
) {
  if (prefix == null) return false;
  final numbers = [for (final item in run) _numberOf(item.id, prefix)];
  if (numbers.any((number) => number == null)) return false;
  final low = numbers.reduce((a, b) => a! < b! ? a : b)!;
  final high = numbers.reduce((a, b) => a! > b! ? a : b)!;
  final held = _idsAfterMove(line, run.first.docPath, sectionKey, prefix);
  final between = {
    for (final id in held)
      if (_numberOf(id, prefix) case final number?)
        if (low <= number && number <= high) id,
  };
  return between.length == run.length &&
      between.containsAll([for (final item in run) item.id]);
}

BigInt? _numberOf(String id, String prefix) {
  final read = readItemId(id, prefix);
  return read is ItemId && read.written == id ? read.number : null;
}

/// Returns the IDs the section [sectionKey] of [docPath] holds after the
/// moves: its own less the items that leave it, and the IDs that land in it.
Set<String> _idsAfterMove(
  _Line line,
  String docPath,
  String sectionKey,
  String prefix,
) {
  final ids = {..._sectionIdsOf(line.index, docPath, sectionKey, prefix)};
  for (final landing in line.moves.landings) {
    if (landing.sectionKey != sectionKey) continue;
    if (landing.from.doc.docPath == docPath) ids.remove(landing.from.id);
    if (landing.to.docPath == docPath) ids.add(landing.newId);
  }
  return ids;
}

Iterable<String> _sectionIdsOf(
  DocIndex index,
  String docPath,
  String sectionKey,
  String prefix,
) {
  final doc = index.at(docPath);
  if (doc == null) return const [];
  final content = index.contentOf(doc);
  final sections = citedSectionsOf(content, index.typeOf(doc));
  final at = sections.indexWhere(
    (section) => section.key == sectionKey && section.prefixId == prefix,
  );
  if (at < 0) return const [];
  return [for (final fact in content.itemFacts.sectionItems[at]) ?fact.id];
}

// MARK: - Entries

/// Returns, by DocPath, the edit of each doc's frontmatter entries that follow
/// a moved item: an `overrides` entry that names it, and a task ref that
/// leaves its source doc for the target doc.
Map<String, String Function(String lfText)> _entryEdits(
  DocIndex index,
  _Moves moves,
) {
  final renames = <String, Map<String, String>>{};
  for (final doc in index.docs) {
    final renamed = _renamedEntries(index, doc, moves);
    if (renamed.isNotEmpty) renames[doc.docPath] = renamed;
  }
  final tasks = _taskMoves(index, moves);
  return {
    for (final path in {...renames.keys, ...tasks.keys})
      path: (lfText) {
        final renamed = renames[path];
        var text = renamed == null
            ? lfText
            : withBlockValues(
                lfText,
                _overridesKey,
                (value) => _renamedEntry(value, renamed),
              );
        if (index.at(path) case final doc?) {
          text = tasks[path]?.applyTo(text, index.typeOf(doc), path) ?? text;
        }
        return text;
      },
  };
}

/// Returns, by the identity of the label an `overrides` entry of [doc] holds,
/// the label of the moved item it names after the moves.
Map<String, String> _renamedEntries(
  DocIndex index,
  IndexedDoc doc,
  _Moves moves,
) {
  final renamed = <String, String>{};
  for (final cite in overrideCitesOf(index, doc)) {
    final landing = moves.landingOf(cite.upstream.docPath, cite.itemId);
    final typeId = landing?.to.docTypeId;
    if (landing == null || typeId == null) continue;
    renamed[linkIdentityOf(cite.entryLabel)] =
        '$typeId:${landing.to.name}#${landing.newId}';
  }
  return renamed;
}

String? _renamedEntry(String value, Map<String, String> renamed) {
  final space = value.indexOf(' ');
  final label = space < 0 ? value : value.substring(0, space);
  final to = renamed[linkIdentityOf(label)];
  if (to == null || to == label) return null;
  return space < 0 ? to : '$to${value.substring(space)}';
}

/// The task refs of one doc that leave it, and those it gains, by field.
final class _TaskMoves {
  final drops = <String, Set<String>>{};
  final adds = <String, List<String>>{};

  /// Returns [lfText] without the refs that leave and with those that join.
  String applyTo(String lfText, MergedDocType? type, String docPath) {
    var text = lfText;
    for (final field in {...drops.keys, ...adds.keys}) {
      text = _withTaskRefs(
        text,
        type,
        docPath,
        field,
        drops[field] ?? const {},
        adds[field] ?? const [],
      );
    }
    return text;
  }
}

Map<String, _TaskMoves> _taskMoves(DocIndex index, _Moves moves) {
  final byDoc = <String, _TaskMoves>{};
  for (final landing in moves.landings) {
    final source = landing.from.doc;
    final fields = [
      for (final field in index.typeOf(source)?.fields ?? const <MergedField>[])
        if (field.type == FieldType.taskRef) field.id,
    ];
    for (final field in fields) {
      if (!_holdsTaskField(index, landing.to, field)) continue;
      for (final entry in source.valuesOf(field)) {
        final ref = TaskRef.parse(entry);
        if (ref == null || ref.item != landing.from.id) continue;
        (byDoc[source.docPath] ??= _TaskMoves()).drops
            .putIfAbsent(field, () => {})
            .add(entry);
        (byDoc[landing.to.docPath] ??= _TaskMoves()).adds
            .putIfAbsent(field, () => [])
            .add('${landing.newId}:${ref.task}');
      }
    }
  }
  return byDoc;
}

bool _holdsTaskField(DocIndex index, IndexedDoc doc, String fieldId) =>
    index
        .typeOf(doc)
        ?.fields
        .any(
          (field) => field.id == fieldId && field.type == FieldType.taskRef,
        ) ??
    false;

String _withTaskRefs(
  String lfText,
  MergedDocType? type,
  String docPath,
  String field,
  Set<String> drop,
  List<String> add,
) {
  final block = (Doc.parse(lfText).frontmatter ?? const <KeyBlock>[])
      .where((candidate) => candidate.name == field)
      .firstOrNull;
  final held = block == null ? const <Object?>[] : listEntriesOf(block);
  if (held == null) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $docPath: its $field is not valid YAML',
    );
  }
  final kept = [
    for (final entry in held)
      if (!(entry is String && drop.contains(entry))) entry,
  ];
  final joined = [
    ...kept,
    for (final entry in add)
      if (!kept.contains(entry)) entry,
  ];
  if (joined.length == held.length && drop.isEmpty) return lfText;
  return withKeyBlock(
    lfText,
    field,
    joined.isEmpty ? null : listBlockOf(field, joined, onDisk: block),
    fieldOrder: [
      for (final field in type?.fields ?? const <MergedField>[]) field.id,
    ],
  );
}

// MARK: - Mentions

/// Returns the mentions an item move leaves, by file path then line: each bare
/// ID that names a moved item in its source doc, or right after that doc's
/// address, in any file; and each bare ID inside a moved item that names an
/// item of its source doc that stays or that the move renumbers.
///
/// A mention in a code file or an agent file reads as a doc address and an ID.
/// Lines are those the files hold before the move. Nothing is written.
List<StaleMention> itemMentions(
  WriteSession session,
  List<ItemLanding> landings,
) {
  if (landings.isEmpty) return const [];
  final index = session.index;
  final moves = _Moves(index, landings);
  final found = <StaleMention>[];
  for (final doc in index.docs) {
    final lf = toLf(index.contentOf(doc).text);
    found
      ..addAll(_addressMentions(index, moves, doc.docPath, lf, '.md'))
      ..addAll(_bareMentions(index, moves, doc, lf));
  }
  final scope = MentionScope.of(session);
  final files = _mentionFiles(scope);
  for (final projectPath in files.keys) {
    final lf = _lfTextOf(files[projectPath]!);
    if (lf == null) continue;
    found.addAll(
      _addressMentions(
        index,
        moves,
        projectPath,
        lf,
        extensionOfCodePath(projectPath),
      ),
    );
  }
  found.sort((a, b) {
    final byPath = compareCodePoints(a.path, b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });
  return found;
}

/// The mentions of [lf] that read `<doc address>#<ID>` and name a moved item.
List<StaleMention> _addressMentions(
  DocIndex index,
  _Moves moves,
  String path,
  String lf,
  String extension,
) => [
  for (final mention in docMentionsInFile(lf, extension))
    if (_namesMovedItem(index, moves, mention))
      (path: path, line: mention.line, mention: mention.text),
];

bool _namesMovedItem(DocIndex index, _Moves moves, NameMention mention) {
  final key = mention.address.sectionKey;
  if (key == null || key.isEmpty) return false;
  return [
    for (final doc in _resolved(index, mention.address.docPart))
      if (moves.landingOf(doc.docPath, key) != null) doc,
  ].isNotEmpty;
}

List<IndexedDoc> _resolved(DocIndex index, String address) {
  try {
    return index.resolve(address);
  } on IndexFault {
    return const [];
  } on TemplateFault {
    return const [];
  }
}

/// The bare IDs of the prose of [doc] that name a moved item.
List<StaleMention> _bareMentions(
  DocIndex index,
  _Moves moves,
  IndexedDoc doc,
  String lf,
) {
  final body = Doc.parse(lf).afterFrontmatter;
  final firstLine =
      '\n'.allMatches(lf.substring(0, lf.length - body.length)).length + 1;
  final scan = linkScanOf(body, firstLine: firstLine);
  final prose = _outsideLinks(scan.prose, [
    for (final source in scan.sources) (start: source.offset, end: source.end),
  ]);
  final lines = body.split('\n');
  final starts = _lineStartsOf(body);
  final skippedHeads = <_Span>{};
  final mentions = <StaleMention>[];
  for (final (:at, :id) in itemIdsInProse(prose, prefixes: moves.prefixes)) {
    final lineIndex = starts.lastIndexWhere((start) => start <= at);
    final column = at - starts[lineIndex];
    final number = firstLine + lineIndex;
    final span = moves.spanAt(doc.docPath, number);
    if (span != null &&
        number == span.first &&
        id.written == span.landing.from.id &&
        skippedHeads.add(span)) {
      continue;
    }
    final cited = _citedBefore(
      index,
      doc,
      scan.sources,
      lines[lineIndex],
      column,
      starts[lineIndex],
    );
    if (_namesMoved(index, moves, doc, cited, id.written, span)) {
      mentions.add((path: doc.docPath, line: number, mention: id.written));
    }
  }
  return mentions;
}

/// Whether the bare ID [id], cited by the doc at [cited] or by none, is one
/// the move leaves a mention for.
bool _namesMoved(
  DocIndex index,
  _Moves moves,
  IndexedDoc doc,
  String? cited,
  String id,
  _Span? span,
) {
  final named = cited ?? doc.docPath;
  final landing = moves.landingOf(named, id);
  if (cited != null) return landing != null;
  if (span == null) return landing != null;
  if (landing != null) return landing.newId != id;
  return _holdsItem(index, doc, id);
}

/// Whether some section of [doc] holds the item [id].
bool _holdsItem(DocIndex index, IndexedDoc doc, String id) => index
    .contentOf(doc)
    .itemFacts
    .sectionItems
    .any((items) => items.any((fact) => fact.id == id));

/// Returns [prose] with each range of [ranges] blanked, line ends kept.
String _outsideLinks(String prose, List<({int start, int end})> ranges) {
  final units = prose.codeUnits.toList();
  for (final (:start, :end) in ranges) {
    for (var at = start; at < end && at < units.length; at++) {
      if (units[at] != 0x0A) units[at] = 0x20;
    }
  }
  return String.fromCharCodes(units);
}

List<int> _lineStartsOf(String text) => [
  0,
  for (var at = 0; at < text.length; at++)
    if (text.codeUnitAt(at) == 0x0A) at + 1,
];

/// Returns the DocPath the nearest doc address or doc link before [column] of
/// [line] names, the empty string for one that names no doc, or null when none
/// precedes it.
String? _citedBefore(
  DocIndex index,
  IndexedDoc doc,
  List<LinkSource> sources,
  String line,
  int column,
  int lineStart,
) {
  String? cited;
  var nearest = -1;
  for (final (:start, :end, :ticks) in codeSpansOf(line)) {
    if (start >= column || start < nearest) continue;
    final address = readDocAddress(line.substring(start + ticks, end - ticks));
    if (address.sectionKey != null || !address.isReferenceWithoutLookup) {
      continue;
    }
    final docs = _resolved(index, address.docPart);
    cited = docs.length == 1 ? docs.single.docPath : '';
    nearest = start;
  }
  for (final source in sources) {
    final shown = source.shown;
    final start = source.offset - lineStart;
    if (shown == null || start < 0 || start >= column || start < nearest) {
      continue;
    }
    if (source.offset >= lineStart + line.length) continue;
    cited = switch (resolveDocLink(shown, doc.docPath)) {
      DocTarget(:final docPath) => docPath,
      _ => '',
    };
    nearest = start;
  }
  return cited;
}

/// Returns the code files and agent files whose mentions are read, by their
/// path from the project root.
Map<String, File> _mentionFiles(MentionScope scope) {
  final files = <String, File>{};
  final paths = ProjectPathReader(
    projectRoot: scope.projectRoot,
    docsRoot: scope.docsRoot,
  );
  for (final (root: codeRoot, path: codePath) in codeFilesOf(
    scope.projectRoot,
    scope.set,
    targets: scope.targets,
    moves: scope.docMoves,
  )) {
    if (!readsNameMentions(extensionOfCodePath(codePath))) continue;
    final projectPath = paths.projectPathOf(codePath, codeRoot);
    if (projectPath == null) continue;
    files[projectPath] = _fileIn(codeRoot, codePath);
  }
  for (final path in agentFilesOf(
    scope.projectRoot,
    scope.agentFileRoots,
    scope.runGit,
  )) {
    if (!readsNameMentions(extensionOfCodePath(path))) continue;
    if (scope.listedPathOf(path) != path) continue;
    files.putIfAbsent(path, () => _fileIn(scope.projectRoot, path));
  }
  return files;
}

File _fileIn(Directory folder, String path) => File(
  '${folder.path}${Platform.pathSeparator}'
  '${path.split('/').join(Platform.pathSeparator)}',
);

/// Returns the text of [file] with LF line ends and no byte-order mark, or
/// null when it cannot be read or is not UTF-8.
String? _lfTextOf(File file) {
  try {
    final text = utf8.decode(readPlanInput(file));
    return toLf(text.startsWith(byteOrderMark) ? text.substring(1) : text);
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}
