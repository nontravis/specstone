import 'package:specstone_core/src/doc_model/needle_search.dart';
import 'package:specstone_core/src/doc_model/sentences.dart';

/// The sentences a draft dropped since its approved copy and the ones it
/// added, each in doc order.
typedef SentenceChanges = ({List<String> dropped, List<String> added});

/// Separates the docs of a held text, so no sentence reads across two docs.
const _docBreak = '\u0000';

/// Returns [heldTexts], each a [heldTextOf] result, as one text for
/// [sentenceChangesOf], with no sentence able to span two of them.
String joinHeldTexts(Iterable<String> heldTexts) => heldTexts.join(_docBreak);

/// Returns [lfTexts], each read by [heldTextOf], joined by [joinHeldTexts].
String heldTextsOf(Iterable<String> lfTexts) =>
    joinHeldTexts(lfTexts.map(heldTextOf));

/// Returns the sentences of [sentences] that [held] holds.
///
/// A sentence is held when its text occurs in [held]. One pass over [held]
/// answers for any number of sentences, so a run asks once for every draft
/// and not once per sentence.
Set<String> heldSentencesIn(Iterable<String> sentences, String held) =>
    needlesFoundIn(sentences, held);

/// Returns the sentences [approved] lost and [draft] gained.
///
/// A dropped sentence is one of [approved], the draft's approved copy, that
/// [tree] does not hold; a new one is a sentence of [draft] that [runCopies]
/// does not hold. A sentence is held when its text occurs in the held text.
/// [draft] and [approved] are LF texts; [tree] is every doc under the docs
/// root and [runCopies] the approved copy of each draft the run shows, each
/// built by [heldTextsOf]. A null [approved] has no sentence to drop. A
/// sentence a doc repeats lists and counts once: held is by text, so the same
/// text twice tells the Owner nothing new.
SentenceChanges sentenceChangesOf({
  required String draft,
  required String? approved,
  required String tree,
  required String runCopies,
}) {
  final approvedSentences = approved == null
      ? const <String>[]
      : sentencesOf(approved);
  return sentenceChangesGiven(
    draft: draft,
    approvedSentences: approvedSentences,
    treeHeld: heldSentencesIn(approvedSentences, tree),
    runCopies: runCopies,
  );
}

/// Returns the sentences of [approvedSentences] lost and of [draft] gained,
/// the tree's answer being [treeHeld] already.
///
/// [treeHeld] holds the sentences of [approvedSentences] that the tree holds
/// (see [heldSentencesIn]); it may hold more, such as those of other drafts of
/// the run. The rest reads as [sentenceChangesOf] does.
SentenceChanges sentenceChangesGiven({
  required String draft,
  required Iterable<String> approvedSentences,
  required Set<String> treeHeld,
  required String runCopies,
}) {
  final added = sentencesOf(draft);
  final addedHeld = heldSentencesIn(added, runCopies);
  return (
    dropped: [
      for (final sentence in {...approvedSentences})
        if (!treeHeld.contains(sentence)) sentence,
    ],
    added: [
      for (final sentence in {...added})
        if (!addedHeld.contains(sentence)) sentence,
    ],
  );
}
