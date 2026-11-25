import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/bundle_trim.dart'
    show SectionLine, lineCountOf;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/feature_pattern_parts.dart'
    show featurePatternDocAddress, featurePatternListName;
import 'package:specstone_core/src/index_query/indexed_doc.dart' show leadKey;
import 'package:specstone_core/src/index_query/models/bundle_entry.dart';
import 'package:specstone_core/src/index_query/models/bundle_text.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/review_parts.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';

const _sectionHeadingMark = '## ';

/// Writes the two files of a review: the read-first file at [readFirst], which
/// holds every part of [parts], and the refs file beside it, which holds the
/// design bundle of the refs docs; prints their index.
///
/// Every part is a must part: none moves to the refs file, and the read plan
/// reads the read-first file whole in as many ranges as it needs. The refs
/// file is the text `context <refs docs> --for design` prints. [noProject]
/// drops the docs that join the refs file's bundle through `bundle:`, and
/// [codeTarget] keeps its per-target docs to one code target.
///
/// Throws what the refs docs' design bundle throws, and `output_not_writable`
/// as [answerBundleFile] gives, before any file is written.
ReadAnswer answerReviewFiles(
  DocIndex index,
  ReviewParts parts,
  File readFirst, {
  required DocsProject project,
  required bool isBare,
  required bool noProject,
  String? codeTarget,
  Set<String> importedPaths = const {},
}) {
  final refs = answerContext(
    index,
    pickBundle(
      index,
      parts.refsDocs,
      BundleMode.design,
      noProject: noProject,
      codeTarget: codeTarget,
      importedPaths: importedPaths,
    ),
    targets: parts.refsDocs,
  );
  final text = _readFirstTextOf(index, parts.parts);
  return answerBundleFile(
    ContextAnswer(
      text: text.text,
      json: {'for': BundleMode.review.wire},
      warnings: refs.warnings,
      entries: text.entries,
      tokens: text.tokens,
      refs: BundleText(
        text: refs.text,
        entries: refs.entries,
        tokens: refs.tokens,
      ),
    ),
    readFirst,
    project: project,
    isBare: isBare,
  );
}

// MARK: - Read-first text

/// One part's printed block, and the `##` sections it prints whole with each
/// header's line in the block, counted from 0.
final class _Block {
  const new(this.text, this.sections);

  final String text;
  final List<SectionLine> sections;
}

/// Returns the read-first text of [parts]: the blocks joined by one blank
/// line, then the closing line and one list line per part.
BundleText _readFirstTextOf(DocIndex index, List<ReviewPart> parts) {
  final blocks = [for (final part in parts) _blockOf(index, part)];
  final entries = <BundleEntry>[];
  var line = 1;
  for (final (i, part) in parts.indexed) {
    final block = blocks[i];
    entries.add(_entryOf(part, block, first: line));
    line += lineCountOf(block.text) + 1;
  }
  final shown = blocks.isEmpty
      ? ''
      : '${[for (final block in blocks) block.text].join('\n\n')}\n';
  final listed = [for (final entry in entries) '- ${_listNameOf(entry)}\n']
      .join();
  final docs = docCountOf(entries);
  final tokens = wholeFileTokensOf(
    shown.runes.length + listed.runes.length,
    docs,
  );
  return BundleText(
    text: '$shown${closingLineOf(docs, tokens)}$listed',
    entries: entries,
    tokens: tokens,
  );
}

BundleEntry _entryOf(ReviewPart part, _Block block, {required int first}) =>
    BundleEntry(
      doc: part.doc,
      kind: _entryKindOf(part.kind),
      summary: false,
      sectionKey: part.sectionKey,
      itemId: part.itemId,
      featurePattern: part.featurePattern,
      first: first,
      last: first + lineCountOf(block.text) - 1,
      sections: [
        for (final SectionLine(:key, :line) in block.sections)
          EntrySection(key: key, first: first + line),
      ],
      cites: part.cites,
    );

BundleEntryKind _entryKindOf(ReviewPartKind kind) => switch (kind) {
  ReviewPartKind.changedUnit => BundleEntryKind.changedUnit,
  ReviewPartKind.removedUnit => BundleEntryKind.removedUnit,
  ReviewPartKind.citer => BundleEntryKind.citer,
  ReviewPartKind.summarySection => BundleEntryKind.summarySection,
  ReviewPartKind.wholeTarget => BundleEntryKind.doc,
  ReviewPartKind.pattern => BundleEntryKind.pattern,
};

/// Returns the closing-list name of [entry]: the doc's name with its doc type,
/// then the part's mark; a feature pattern part's is its list name.
String _listNameOf(BundleEntry entry) => switch (entry.featurePattern) {
  final id? => featurePatternListName(id),
  null => [nameWithType(entry.doc), ?reviewMarkOf(entry)].join(' · '),
};

// MARK: - Blocks

/// Returns the block of [part]: its naming line, then its text trimmed at its
/// end.
///
/// A section printed whole ends its header line in ` {#<key>}`, as every text
/// bundle prints one.
_Block _blockOf(DocIndex index, ReviewPart part) {
  final naming = _namingLineOf(part);
  if (part.kind == ReviewPartKind.wholeTarget) {
    return _wholeBlockOf(index, part, naming);
  }
  final lines = part.text.trimRight().split('\n');
  final key = part.sectionKey;
  final isSectionPart =
      part.itemId == null &&
      key != null &&
      key != leadKey &&
      lines.first.startsWith(_sectionHeadingMark);
  if (isSectionPart) lines[0] = _keyedHeading(lines.first, key);
  return _Block(
    [naming, if (part.text.isNotEmpty) ...lines].join('\n'),
    const [],
  );
}

/// Returns the block of the whole doc [part] holds, every section header line
/// keyed, with the header lines of its sections.
_Block _wholeBlockOf(DocIndex index, ReviewPart part, String naming) {
  final content = index.contentOf(part.doc);
  final lines = part.text.trimRight().split('\n');
  final sections = <SectionLine>[];
  for (final (i, section) in content.sections.indexed) {
    final line = content.lineFacts.sectionLines[i];
    if (line > lines.length ||
        !lines[line - 1].startsWith(_sectionHeadingMark)) {
      continue;
    }
    lines[line - 1] = _keyedHeading(lines[line - 1], section.key);
    sections.add(SectionLine(key: section.key, line: line));
  }
  return _Block([naming, ...lines].join('\n'), sections);
}

String _keyedHeading(String line, String key) => '${line.trimRight()} {#$key}';

/// Returns the naming line of [part]: `==> <name> (<doc type>) · <DocPath>`,
/// then `#<section key>`, ` · item <ID>` or ` · block <anchor>`, and the
/// part's kind, `changed`, `removed`, `citer of <unit>, …`, or `summary`; a
/// whole target's names the doc alone. A feature pattern part's is
/// `==> <id> (feature pattern) · <doc type>:<name> <==`, naming the doc that
/// lists it.
String _namingLineOf(ReviewPart part) {
  final doc = part.doc;
  if (part.featurePattern case final id?) {
    return '==> ${featurePatternListName(id)} · '
        '${featurePatternDocAddress(doc)} <==';
  }
  final key = part.sectionKey;
  final id = part.itemId;
  final path = key == null ? doc.docPath : '${doc.docPath}#$key';
  final place = id == null ? '' : ' · ${part.isBlock ? 'block' : 'item'} $id';
  final kind = switch (part.kind) {
    ReviewPartKind.wholeTarget || ReviewPartKind.pattern => '',
    ReviewPartKind.changedUnit => ' · changed',
    ReviewPartKind.removedUnit => ' · removed',
    ReviewPartKind.citer => ' · citer of ${part.cites.join(', ')}',
    ReviewPartKind.summarySection => ' · summary',
  };
  return '==> ${nameWithType(doc)} · $path$place$kind <==';
}
