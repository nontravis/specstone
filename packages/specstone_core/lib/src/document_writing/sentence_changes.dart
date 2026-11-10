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
}) => (
  dropped: _notHeldIn(
    approved == null ? const [] : sentencesOf(approved),
    tree,
  ),
  added: _notHeldIn(sentencesOf(draft), runCopies),
);

List<String> _notHeldIn(Iterable<String> sentences, String held) => [
  for (final sentence in {...sentences})
    if (!held.contains(sentence)) sentence,
];
