import 'dart:math';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/models/sentence_measure.dart';
import 'package:specstone_core/src/doc_model/sentence_measure.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart';
import 'package:specstone_core/src/index_query/models/item_fact.dart';
import 'package:specstone_core/src/index_query/models/readability_facts.dart';
import 'package:specstone_core/src/index_query/models/sentence_fact.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The cite-note line of the shipped prd-core guides, which a trace-note
/// message names.
const citeNoteGuideLine = "Put a cite or an ownership note at the item's end.";

/// Returns the sentence-length and trace-note findings of a typed [doc]; an
/// untyped doc has none.
///
/// Each item's sentences and trace notes are the facts the index stores, so
/// nothing is recounted. A prose field's value is read as one item against its
/// own caps. A record's matrix section takes none of these findings.
Iterable<Finding> checkReadability(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final content = context.contentOf(doc);
  final facts = content.itemFacts;
  final matrixId = verificationMatrixOf(type)?.id;
  yield* _sectionFindings(context, doc, type.lint, leadKey, facts.leadItems);
  for (var i = 0; i < content.sections.length; i++) {
    final template = context.templateSectionAt(doc, i);
    if (matrixId != null && template?.id == matrixId) {
      continue;
    }
    final sectionKey = template?.id ?? content.sections[i].key;
    yield* _sectionFindings(
      context,
      doc,
      type.lint,
      sectionKey,
      facts.sectionItems[i],
    );
  }
  yield* _fieldFindings(context, doc, type, facts);
}

Iterable<Finding> _fieldFindings(
  CheckContext context,
  IndexedDoc doc,
  MergedDocType type,
  ItemFacts facts,
) sync* {
  final docLines = context.linesOf(doc);
  for (final field in type.fields) {
    final caps = field.lint;
    final fact = facts.fieldItems[field.id];
    final line = docLines.keyLine(field.id);
    if (caps == null || fact == null || line == null) continue;
    final keys = <String, Object>{'field': field.id};
    yield* _sentenceCountFindings(context, doc, caps, fact, line, keys);
    if (caps.capsLength) {
      yield* _lengthFindings(
        context,
        doc,
        line,
        fact.readability,
        _LengthCaps.ofField(caps),
        keys,
      );
    }
  }
}

Iterable<Finding> _sentenceCountFindings(
  CheckContext context,
  IndexedDoc doc,
  FieldCaps caps,
  FieldFact fact,
  int line,
  Map<String, Object> keys,
) sync* {
  final limit = caps.maxSentences;
  if (limit == null) return;
  final actual = fact.readability.cells
      .expand((cell) => cell)
      .where((sentence) => !sentence.isHeading)
      .length;
  if (actual <= limit) return;
  yield context.finding(
    doc,
    FindingKind.sentencesOverLimit,
    line: line,
    message: 'holds $actual sentences; the limit is $limit',
    keys: {...keys, 'limit': limit, 'actual': actual},
  );
}

Iterable<Finding> _sectionFindings(
  CheckContext context,
  IndexedDoc doc,
  MergedLint lint,
  String sectionKey,
  List<ItemFact> items,
) sync* {
  for (final item in items) {
    final keys = <String, Object>{'section': sectionKey, 'id': ?item.id};
    yield* _lengthFindings(
      context,
      doc,
      item.line,
      item.readability,
      _LengthCaps.ofDoc(lint),
      keys,
    );
    if (lint.isTraceNoteLast) yield* _noteFindings(context, doc, item, keys);
  }
}

Iterable<Finding> _lengthFindings(
  CheckContext context,
  IndexedDoc doc,
  int line,
  ReadabilityFacts readability,
  _LengthCaps caps,
  Map<String, Object> keys,
) sync* {
  for (final run in _lengthRunsOf(readability, caps)) {
    if (run.over == 0) continue;
    final unit = run.countsChars ? 'characters' : 'words';
    yield context.finding(
      doc,
      run.countsChars
          ? FindingKind.sentenceCharsOverLimit
          : FindingKind.wordsOverLimit,
      line: line,
      message:
          'the longest sentence holds ${run.longest} $unit; the limit is '
          '${run.limit} $unit for language ${run.language}',
      keys: {
        ...keys,
        'language': run.language,
        'limit': run.limit,
        'actual': run.longest,
        'sentences': run.over,
      },
    );
  }
}

Iterable<Finding> _noteFindings(
  CheckContext context,
  IndexedDoc doc,
  ItemFact item,
  Map<String, Object> keys,
) sync* {
  for (final note in item.readability.notes) {
    if (note.closes) continue;
    yield context.finding(
      doc,
      FindingKind.traceNoteNotLast,
      line: item.line,
      message:
          "the note ${note.text} comes before the item's end; "
          'guide line: $citeNoteGuideLine',
      keys: {...keys, 'note': note.text},
    );
  }
}

/// One sentence's size against the cap of its language.
final class _Sized {
  const new({
    required this.language,
    required this.countsChars,
    required this.limit,
    required this.size,
  });

  final String language;
  final bool countsChars;
  final int limit;
  final int size;
}

/// The sentences of one item that share a language.
///
/// `longest` is the most words or characters one holds; `over` counts the
/// sentences past `limit`.
final class _Run {
  const new({
    required this.language,
    required this.countsChars,
    required this.limit,
    required this.longest,
    required this.over,
  });

  final String language;
  final bool countsChars;
  final int limit;
  final int longest;
  final int over;
}

/// Returns one run per language of [facts]' sentences, in the order each
/// language first appears.
///
/// A `###` heading's sentence counts here, as it does in the sentence cut.
List<_Run> _lengthRunsOf(ReadabilityFacts facts, _LengthCaps caps) {
  final byLanguage = <String, List<_Sized>>{};
  for (final sentence in facts.cells.expand((cell) => cell)) {
    byLanguage
        .putIfAbsent(sentence.language, () => [])
        .add(_sizedOf(sentence, caps));
  }
  return [
    for (final sizes in byLanguage.values)
      _Run(
        language: sizes.first.language,
        countsChars: sizes.first.countsChars,
        limit: sizes.first.limit,
        longest: sizes.map((sized) => sized.size).reduce(max),
        over: sizes.where((sized) => sized.size > sized.limit).length,
      ),
  ];
}

/// The sentence caps one read holds its sentences to.
///
/// A doc's items weigh each other-script run at the character cap over 25; a
/// prose field's value, at its character cap over its own word cap.
final class _LengthCaps {
  new ofDoc(MergedLint lint)
    : words = lint.sentenceWordCaps,
      chars = lint.sentenceCharCaps,
      weighsRunsByWordCap = false;

  new ofField(FieldCaps caps)
    : words = SentenceCaps(caps.maxSentenceWords!),
      chars = SentenceCaps(caps.maxSentenceChars!),
      weighsRunsByWordCap = true;

  final SentenceCaps words;
  final SentenceCaps chars;
  final bool weighsRunsByWordCap;

  int runDivisorOf(String language) =>
      weighsRunsByWordCap ? words.capFor(language) : defaultRunWeightDivisor;
}

_Sized _sizedOf(SentenceFact sentence, _LengthCaps caps) {
  final limit = (sentence.countsChars ? caps.chars : caps.words).capFor(
    sentence.language,
  );
  final size = sentence.countsChars
      ? weightedChars(
          SentenceMeasure(
            language: sentence.language,
            countsChars: true,
            words: sentence.words,
            chars: sentence.chars,
            runs: sentence.runs,
          ),
          limit,
          divisor: caps.runDivisorOf(sentence.language),
        )
      : sentence.words;
  return _Sized(
    language: sentence.language,
    countsChars: sentence.countsChars,
    limit: limit,
    size: size,
  );
}
