import 'package:specstone_core/src/doc_model/sentences.dart';

/// The sentences a draft dropped since its approved copy and the ones it
/// added, each in doc order.
final class SentenceChanges {
  const new({required this.dropped, required this.added});

  final List<String> dropped;
  final List<String> added;
}

/// Returns the sentences of every text in [lfTexts], as one set.
Set<String> sentenceSetOf(Iterable<String> lfTexts) => {
  for (final text in lfTexts) ...sentencesOf(text),
};

/// Returns the sentences [approved] lost and [draft] gained.
///
/// A dropped sentence is one of [approved], the draft's approved copy, that
/// [tree] does not hold; a new one is a sentence of [draft] that [runCopies]
/// does not hold. A sentence is held when the set holds an equal sentence.
/// [draft] and [approved] are LF texts; [tree] is the sentences of every doc
/// under the docs root and [runCopies] those of the approved copy of each
/// draft the run shows, each built by [sentenceSetOf]. A null [approved] has no
/// sentence to drop. A sentence a doc repeats lists once.
SentenceChanges sentenceChangesOf({
  required String draft,
  required String? approved,
  required Set<String> tree,
  required Set<String> runCopies,
}) => SentenceChanges(
  dropped: approved == null ? const [] : _notIn(tree, sentencesOf(approved)),
  added: _notIn(runCopies, sentencesOf(draft)),
);

List<String> _notIn(Set<String> held, List<String> sentences) => [
  for (final sentence in {...sentences})
    if (!held.contains(sentence)) sentence,
];
