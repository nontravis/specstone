import 'dart:math';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/sentence_measure.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The sentence-length line of the shipped prd-core guides, which a length
/// message names.
const sentenceLengthGuideLine =
    'Each sentence holds 25 words or fewer (Korean 17), or 100 characters in '
    'a script with no spaces (Japanese 60, Chinese 45).';

/// The cite-note line of the shipped prd-core guides, which a trace-note
/// message names.
const citeNoteGuideLine = "Put a cite or an ownership note at the item's end.";

/// Returns the sentence-length and trace-note findings of a typed [doc]; an
/// untyped doc has none.
///
/// Each item's sentences and trace notes are the facts the index stores, so
/// nothing is recounted.
Iterable<Finding> checkReadability(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final content = context.contentOf(doc);
  final facts = content.itemFacts;
  yield* _sectionFindings(context, doc, type.lint, leadKey, facts.leadItems);
  for (var i = 0; i < content.sections.length; i++) {
    final sectionKey =
        context.templateSectionAt(doc, i)?.id ?? content.sections[i].key;
    yield* _sectionFindings(
      context,
      doc,
      type.lint,
      sectionKey,
      facts.sectionItems[i],
    );
  }
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
    yield* _lengthFindings(context, doc, lint, item, keys);
    if (lint.isTraceNoteLast) yield* _noteFindings(context, doc, item, keys);
  }
}

Iterable<Finding> _lengthFindings(
  CheckContext context,
  IndexedDoc doc,
  MergedLint lint,
  ItemFact item,
  Map<String, Object> keys,
) sync* {
  for (final run in _lengthRunsOf(item.readability, lint)) {
    if (run.over == 0) continue;
    final unit = run.countsChars ? 'characters' : 'words';
    yield context.finding(
      doc,
      run.countsChars
          ? FindingKind.sentenceCharsOverLimit
          : FindingKind.wordsOverLimit,
      line: item.line,
      message:
          'the longest sentence holds ${run.longest} $unit; the limit is '
          '${run.limit} for language ${run.language}; '
          'guide line: $sentenceLengthGuideLine',
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
typedef _Sized = ({String language, bool countsChars, int limit, int size});

/// The sentences of one item that share a language.
///
/// `longest` is the most words or characters one holds; `over` counts the
/// sentences past `limit`.
typedef _Run = ({
  String language,
  bool countsChars,
  int limit,
  int longest,
  int over,
});

/// Returns one run per language of [facts]' sentences, in the order each
/// language first appears.
///
/// A `###` heading's sentence counts here, as it does in the sentence cut.
List<_Run> _lengthRunsOf(ReadabilityFacts facts, MergedLint lint) {
  final byLanguage = <String, List<_Sized>>{};
  for (final sentence in facts.cells.expand((cell) => cell)) {
    byLanguage
        .putIfAbsent(sentence.language, () => [])
        .add(_sizedOf(sentence, lint));
  }
  return [
    for (final sizes in byLanguage.values)
      (
        language: sizes.first.language,
        countsChars: sizes.first.countsChars,
        limit: sizes.first.limit,
        longest: sizes.map((sized) => sized.size).reduce(max),
        over: sizes.where((sized) => sized.size > sized.limit).length,
      ),
  ];
}

_Sized _sizedOf(SentenceFact sentence, MergedLint lint) {
  final caps = sentence.countsChars
      ? lint.sentenceCharCaps
      : lint.sentenceWordCaps;
  final limit = caps.capFor(sentence.language);
  final size = sentence.countsChars
      ? weightedChars((
          language: sentence.language,
          countsChars: true,
          words: sentence.words,
          chars: sentence.chars,
          runs: sentence.runs,
        ), limit)
      : sentence.words;
  return (
    language: sentence.language,
    countsChars: sentence.countsChars,
    limit: limit,
    size: size,
  );
}
