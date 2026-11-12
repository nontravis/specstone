import 'package:specstone_core/src/document_writing/sentence_changes.dart';
import 'package:test/test.dart';

const _name = 'document_writing/approve_drafts/show_changes_since_approval';

String _doc(String body) => '---\nverify_method: test\n---\n\n# T\n\n$body';

/// Returns the changes of [draft] against [approved], the way a run reads
/// them: [tree] holds every doc under the docs root and [runCopies] the
/// approved copy of each draft shown, as LF texts.
SentenceChanges _changes({
  required String draft,
  String? approved,
  List<String> tree = const [],
  List<String> runCopies = const [],
}) => sentenceChangesOf(
  draft: _doc(draft),
  approved: approved == null ? null : _doc(approved),
  tree: heldTextsOf([_doc(draft), ...tree]),
  runCopies: heldTextsOf(runCopies.map(_doc)),
);

void main() {
  group('$_name E23', () {
    test('a dropped, a moved, and an added sentence list the first and the '
        'third', () {
      final changes = _changes(
        approved: '## Statement\nKept one. Dropped one. Moved one.\n',
        draft: '## Statement\nKept one. Added one.\n',
        tree: [_doc('## Statement\nMoved one.\n')],
        runCopies: ['## Statement\nKept one. Dropped one. Moved one.\n'],
      );

      expect(changes.dropped, ['Dropped one.']);
      expect(changes.added, ['Added one.']);
    });
  });

  group('$_name E24', () {
    test('a sentence moved to an untyped doc is not dropped', () {
      final changes = _changes(
        approved: '## Statement\nStays. Goes to notes.\n',
        draft: '## Statement\nStays.\n',
        tree: ['# Notes\n\nGoes to notes.\n'],
      );

      expect(changes.dropped, isEmpty);
    });

    test('a sentence the draft itself still holds in another place is not '
        'dropped', () {
      final changes = _changes(
        approved: '## Statement\nOne. Two.\n',
        draft: '## Rationale\nTwo.\n\n## Statement\nOne.\n',
      );

      expect(changes.dropped, isEmpty);
    });

    test('a draft with no approved copy drops none', () {
      final changes = _changes(approved: null, draft: '## Statement\nOne.\n');

      expect(changes.dropped, isEmpty);
    });

    test('a sentence held in a doc wrapped over lines and joined to the next '
        'sentence counts as held', () {
      final changes = _changes(
        approved: '## Statement\nIt shall wrap cleanly.\n',
        draft: '## Statement\nNothing here.\n',
        tree: ['## Statement\nBefore. It shall\nwrap   cleanly. After.\n'],
      );

      expect(changes.dropped, isEmpty);
    });

    test('a sentence held in a block quote wrapped over two > lines counts as '
        'held', () {
      final changes = _changes(
        approved: '## Statement\nIt shall wrap cleanly.\n',
        draft: '## Statement\nNothing here.\n',
        tree: ['## Statement\n> It shall\n> wrap cleanly.\n'],
      );

      expect(changes.dropped, isEmpty);
    });

    test('a sentence cut at an abbreviation is held where it is written, and '
        'one repeated lists once', () {
      final changes = _changes(
        approved: '## Statement\nUse a tool, e.g. a pen. Gone. Gone.\n',
        draft: '## Statement\nNothing here.\n',
        tree: ['## Statement\nUse a tool, e.g. a pen.\n'],
      );

      expect(changes.dropped, ['Gone.']);
    });

    test('a sentence does not join the last of one doc to the first of the '
        'next', () {
      final changes = _changes(
        approved: '## Statement\nEnds here Starts there.\n',
        draft: '## Statement\nNothing.\n',
        tree: [
          '## Statement\nBefore. Ends here',
          '## Statement\nStarts there.',
        ],
      );

      expect(changes.dropped, ['Ends here Starts there.']);
    });
  });

  group('$_name E25', () {
    test('a sentence moved between two drafts of the run is neither dropped '
        'nor new', () {
      const first = '## Statement\nStays. Moves.\n';
      const second = '## Statement\nOther.\n';

      final changes = _changes(
        approved: first,
        draft: '## Statement\nStays.\n',
        tree: ['## Statement\nOther. Moves.\n'],
        runCopies: [first, second],
      );
      final other = _changes(
        approved: second,
        draft: '## Statement\nOther. Moves.\n',
        tree: ['## Statement\nStays.\n'],
        runCopies: [first, second],
      );

      expect(changes.dropped, isEmpty);
      expect(changes.added, isEmpty);
      expect(other.dropped, isEmpty);
      expect(other.added, isEmpty);
    });

    test('a draft with no approved copy adds each sentence unless another '
        'copy of the run holds it', () {
      final changes = _changes(
        approved: null,
        draft: '## Statement\nFresh. Known.\n',
        runCopies: ['## Statement\nKnown.\n'],
      );

      expect(changes.added, ['Fresh.']);
    });

    test('a sentence copied from a doc the run does not show counts new', () {
      final changes = _changes(
        approved: '## Statement\nStays.\n',
        draft: '## Statement\nStays. Copied.\n',
        tree: ['## Statement\nCopied.\n'],
        runCopies: ['## Statement\nStays.\n'],
      );

      expect(changes.added, ['Copied.']);
    });

    test('a sentence of the draft that a copy holds in a wrapped block quote '
        'is not new', () {
      final changes = _changes(
        approved: '## Statement\n> It shall\n> wrap cleanly.\n',
        draft: '## Statement\nIt shall wrap cleanly.\n',
        runCopies: ['## Statement\n> It shall\n> wrap cleanly.\n'],
      );

      expect(changes.added, isEmpty);
    });
  });

  group('$_name E26', () {
    test('a draft with no sentence dropped and none new lists none', () {
      final changes = _changes(
        approved: '## Statement\nSame.\n',
        draft: '## Statement\nSame.\n',
        runCopies: ['## Statement\nSame.\n'],
      );

      expect(changes.dropped, isEmpty);
      expect(changes.added, isEmpty);
    });
  });

  group('$_name run lookup', () {
    test('a tree answer that also holds the sentences of other drafts drops '
        'the same sentences as one for this draft alone', () {
      final approved = _doc('## Statement\nKept. Gone.\n');
      final tree = heldTextsOf([_doc('## Statement\nKept. Other draft.\n')]);
      final own = sentenceChangesOf(
        draft: _doc('## Statement\nKept.\n'),
        approved: approved,
        tree: tree,
        runCopies: '',
      );

      final shared = sentenceChangesGiven(
        draft: _doc('## Statement\nKept.\n'),
        approvedSentences: ['Kept.', 'Gone.'],
        treeHeld: heldSentencesIn(['Kept.', 'Gone.', 'Other draft.'], tree),
        runCopies: '',
      );

      expect(shared.dropped, own.dropped);
      expect(shared.dropped, ['Gone.']);
    });
  });
}
