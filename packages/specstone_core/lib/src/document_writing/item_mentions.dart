import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, resolveDocLink;
import 'package:specstone_core/src/doc_model/models/code_span.dart';
import 'package:specstone_core/src/doc_model/models/item_id_at.dart';
import 'package:specstone_core/src/doc_model/models/name_mention.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show extensionOfCodePath, nameMentionsInFile, readsNameMentions;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:specstone_core/src/document_writing/body_scan.dart';
import 'package:specstone_core/src/document_writing/item_moves.dart';
import 'package:specstone_core/src/document_writing/models/text_edit.dart';
import 'package:specstone_core/src/document_writing/move_item.dart'
    show ItemLanding;
import 'package:specstone_core/src/document_writing/rewrite_item_refs.dart'
    show ItemRefs, ListedRef, planItemRefs;
import 'package:specstone_core/src/document_writing/scenario_items.dart'
    show scenarioKeyOfId;
import 'package:specstone_core/src/document_writing/stale_mentions.dart'
    show MentionScope, StaleMention;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show ProjectPathReader;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart'
    show sectionBodyLines;
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/item_words.dart'
    show itemIdPrefixesOf;
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/index_query/models/link_source.dart';
import 'package:specstone_core/src/plan_hash.dart' show readPlanInput;
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show byteOrderMark;
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show codeFilesOf;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// Returns the mentions an item move leaves, by file path then line: each bare
/// ID that names a moved item in its source doc, or right after that doc's
/// address, in any file; each bare ID inside a moved item that names an item
/// of its source doc that stays or that the move renumbers; and each reference
/// definition left because it serves items that part ways.
///
/// A mention in a code file or an agent file reads as a doc address and an ID.
/// A doc the move writes is read as it reads after the write, so a line is
/// where the text then lives. Nothing is written.
List<StaleMention> itemMentions(
  WriteSession session,
  List<ItemLanding> landings, {
  ItemRefs? refs,
}) {
  if (landings.isEmpty) return const [];
  final index = session.index;
  final moves = ItemMoves(index, landings);
  final planned = refs ?? planItemRefs(session, landings);
  final afters = {
    for (final doc in index.docs)
      doc.docPath: _textAfterWrite(session, doc, planned.edits[doc.docPath]),
  };
  final landed = {
    for (final doc in index.docs)
      doc.docPath: _landedSpans(index, moves, doc, afters[doc.docPath]!),
  };
  final found = <StaleMention>[];
  for (final doc in index.docs) {
    final after = afters[doc.docPath]!;
    found
      ..addAll(_addressMentions(index, moves, doc.docPath, after, '.md'))
      ..addAll(_bareMentions(index, moves, doc, after, landed[doc.docPath]!))
      ..addAll(
        _listedMentions(
          index,
          moves,
          doc,
          planned.listed[doc.docPath],
          afters,
          landed,
        ),
      );
  }
  return found
    ..addAll(_fileMentions(MentionScope.of(session), index, moves))
    ..sort((a, b) {
      final byPath = compareCodePoints(a.path, b.path);
      return byPath != 0 ? byPath : a.line.compareTo(b.line);
    });
}

/// Returns the LF text [doc] holds after [edit] writes it: laid out only when
/// the edit writes, else as the file holds it.
String _textAfterWrite(WriteSession session, IndexedDoc doc, TextEdit? edit) {
  final before = toLf(session.index.contentOf(doc).text);
  final edited = edit?.call(before);
  return edited == null
      ? before
      : layOutDoc(edited, session.docTypeAt(doc.docPath));
}

/// The mentions of the code files and agent files in [scope].
List<StaleMention> _fileMentions(
  MentionScope scope,
  DocIndex index,
  ItemMoves moves,
) {
  final files = _mentionFiles(scope);
  return [
    for (final projectPath in files.keys)
      if (_lfTextOf(files[projectPath]!) case final lf?)
        ..._addressMentions(
          index,
          moves,
          projectPath,
          lf,
          extensionOfCodePath(projectPath),
        ),
  ];
}

/// Returns the lines each item that lands in [doc] spans in [lf], the doc as
/// it reads after the write.
List<MovedSpan> _landedSpans(
  DocIndex index,
  ItemMoves moves,
  IndexedDoc doc,
  String lf,
) {
  final landings = [
    for (final landing in moves.landings)
      if (landing.to.docPath == doc.docPath) landing,
  ];
  if (landings.isEmpty) return const [];
  final type = index.typeOf(doc);
  final content = docStructureOf(lf, type);
  final sections = citedSectionsOf(content, type);
  final spans = <MovedSpan>[];
  final extentsAt = <int, Map<String, LineRange>>{};
  for (final landing in landings) {
    final at = sections.indexWhere(
      (section) => section.key == landing.sectionKey,
    );
    if (at < 0) continue;
    final extents = extentsAt[at] ??= itemExtentsOf(
      sectionBodyLines(content.sections, content.lineFacts, at),
      prefixId: sections[at].prefixId,
      isAcceptanceCriteria: landing.isScenario,
    );
    final extent =
        extents[landing.isScenario
            ? scenarioKeyOfId(landing.newId)
            : landing.newId];
    if (extent != null) {
      spans.add(
        MovedSpan(first: extent.first, last: extent.last, landing: landing),
      );
    }
  }
  return spans;
}

/// The references [doc] keeps as written, each at the line its text sits on
/// after the write: in the doc it stayed in, or in the target doc when it sat
/// inside a moved item.
///
/// A line is found by the place of its text among the lines that hold it in
/// its region, so a repeated text lands on its own line.
List<StaleMention> _listedMentions(
  DocIndex index,
  ItemMoves moves,
  IndexedDoc doc,
  List<ListedRef>? listed,
  Map<String, String> afters,
  Map<String, List<MovedSpan>> landed,
) {
  if (listed == null) return const [];
  final before = toLf(index.contentOf(doc).text).split('\n');
  final movedBefore = _linesOf(moves.spans[doc.docPath] ?? const []);
  final afterLines = <String, List<String>>{};
  final landedLines = <String, Set<int>>{};
  final mentions = <StaleMention>[];
  for (final ref in listed) {
    final span = moves.spanAt(doc.docPath, ref.line);
    final path = span?.landing.to.docPath ?? doc.docPath;
    final after = afterLines[path] ??= afters[path]!.split('\n');
    final landedAfter = landedLines[path] ??= _linesOf(landed[path]!);
    final region = span == null
        ? null
        : landed[path]!.where((s) => s.landing == span.landing).firstOrNull;
    final nth = _linesHolding(
      before,
      ref.textBefore,
      span?.first ?? 1,
      span?.last ?? before.length,
      (line) => span != null || !movedBefore.contains(line),
    ).where((line) => line < ref.line).length;
    final lines = _linesHolding(
      after,
      ref.text,
      region?.first ?? 1,
      region?.last ?? after.length,
      (line) => span != null || !landedAfter.contains(line),
    );
    final line = nth < lines.length
        ? lines[nth]
        : lines.lastOrNull ?? region?.first ?? ref.line;
    mentions.add(StaleMention(path: path, line: line, mention: ref.text));
  }
  return mentions;
}

/// Returns every file line [spans] cover.
Set<int> _linesOf(List<MovedSpan> spans) => {
  for (final span in spans)
    for (var at = span.first; at <= span.last; at++) at,
};

/// Returns the file lines from [first] to [last] of [lines] that hold [text]
/// and that [isKept] keeps.
List<int> _linesHolding(
  List<String> lines,
  String text,
  int first,
  int last,
  bool Function(int line) isKept,
) => [
  for (var at = first; at <= last && at <= lines.length; at++)
    if (lines[at - 1].contains(text) && isKept(at)) at,
];

/// The mentions of [lf] that read `<doc address>#<ID>` and name a moved item.
List<StaleMention> _addressMentions(
  DocIndex index,
  ItemMoves moves,
  String path,
  String lf,
  String extension,
) => [
  for (final mention in nameMentionsInFile(lf, extension))
    if (_namesMovedItem(index, moves, mention))
      StaleMention(path: path, line: mention.line, mention: mention.text),
];

bool _namesMovedItem(DocIndex index, ItemMoves moves, NameMention mention) {
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

/// The bare IDs of the prose of [doc], as [lf] reads after the write, that
/// name a moved item; [spans] are the lines of the moved items [doc] holds.
List<StaleMention> _bareMentions(
  DocIndex index,
  ItemMoves moves,
  IndexedDoc doc,
  String lf,
  List<MovedSpan> spans,
) {
  final body = BodyScan(lf);
  final prose = _outsideLinks(body.scan.prose, body.scan.sources);
  final lines = body.body.split('\n');
  final skippedHeads = <MovedSpan>{};
  final mentions = <StaleMention>[];
  final runPrefixes = itemIdPrefixesOf(index.set.docTypes);
  for (final ItemIdAt(:at, :id) in itemIdsInProse(
    prose,
    prefixes: moves.prefixes,
  )) {
    final number = body.fileLineOf(at);
    final span = spans
        .where((span) => span.first <= number && number <= span.last)
        .firstOrNull;
    if (span != null &&
        number == span.first &&
        id.written == span.landing.newId &&
        skippedHeads.add(span)) {
      continue;
    }
    final lineIndex = number - body.firstLine;
    final cited = _citedBy(
      index,
      doc,
      body.scan.sources,
      lines[lineIndex],
      body.columnOf(at),
      body.starts[lineIndex],
      runPrefixes,
    );
    if (_namesMoved(index, moves, doc, cited, id.written, span)) {
      mentions.add(
        StaleMention(path: doc.docPath, line: number, mention: id.written),
      );
    }
  }
  return mentions;
}

/// Whether the bare ID [id], cited by the doc at [cited] or by none, is one
/// the move leaves a mention for; [span] is the moved item that holds it.
bool _namesMoved(
  DocIndex index,
  ItemMoves moves,
  IndexedDoc doc,
  String? cited,
  String id,
  MovedSpan? span,
) {
  final authored = span?.landing.from.doc ?? doc;
  final landing = moves.landingOf(cited ?? authored.docPath, id);
  if (cited != null || span == null) return landing != null;
  if (landing != null) return landing.newId != id;
  return _holdsItem(index, authored, id);
}

/// Whether some section of [doc] holds the item [id].
bool _holdsItem(DocIndex index, IndexedDoc doc, String id) => index
    .contentOf(doc)
    .itemFacts
    .sectionItems
    .any((items) => items.any((fact) => fact.id == id));

/// Returns [prose] with each of [sources] blanked, line ends kept.
String _outsideLinks(String prose, List<LinkSource> sources) {
  final units = prose.codeUnits.toList();
  for (final source in sources) {
    for (var at = source.offset; at < source.end && at < units.length; at++) {
      if (units[at] != 0x0A) units[at] = 0x20;
    }
  }
  return String.fromCharCodes(units);
}

/// Returns the DocPath of the doc address or doc link whose item-ID run holds
/// the ID at [column] of [line], the empty string for one that names no doc,
/// or null when no run holds it.
String? _citedBy(
  DocIndex index,
  IndexedDoc doc,
  List<LinkSource> sources,
  String line,
  int column,
  int lineStart,
  Set<String> prefixes,
) {
  bool runHolds(int end) => itemIdRunAt(
    line,
    end,
    prefixes: prefixes,
  ).any((item) => item.at == column);
  for (final CodeSpan(:start, :end, :ticks) in codeSpansOf(line)) {
    if (end > column || !runHolds(end)) continue;
    final address = readDocAddress(line.substring(start + ticks, end - ticks));
    if (address.sectionKey != null || !address.isReferenceWithoutLookup) {
      continue;
    }
    final docs = _resolved(index, address.docPart);
    return docs.length == 1 ? docs.single.docPath : '';
  }
  for (final source in sources) {
    final shown = source.shown;
    final start = source.offset - lineStart;
    if (shown == null ||
        start < 0 ||
        source.offset >= lineStart + line.length) {
      continue;
    }
    if (source.end - lineStart > column || !runHolds(source.end - lineStart)) {
      continue;
    }
    return switch (resolveDocLink(shown, doc.docPath)) {
      DocTarget(:final docPath) => docPath,
      _ => '',
    };
  }
  return null;
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
