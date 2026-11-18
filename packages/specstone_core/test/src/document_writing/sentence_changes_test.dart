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
  tree: sentenceSetOf([_doc(draft), ...tree]),
  runCopies: sentenceSetOf(runCopies.map(_doc)),
);

void main() {
  group('a dropped, a moved, and an added sentence', () {
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

  group('a dropped sentence', () {
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

  group('a new sentence', () {
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

  group('a code span holding sentence marks', () {
    test('a sentence holding a code span with marks counts once as dropped '
        'and once as new', () {
      const approved = '## Statement\nKept. Old `v. w` tail. Gone.\n';
      final changes = _changes(
        approved: approved,
        draft: '## Statement\nKept. New `x? y!` tail.\n',
        tree: [_doc('## Statement\nNothing here.\n')],
        runCopies: [approved],
      );

      expect(changes.dropped, ['Old `v. w` tail.', 'Gone.']);
      expect(changes.added, ['New `x? y!` tail.']);
    });
  });

  group('a draft with no change', () {
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
    test('a tree set that also holds the sentences of other drafts drops the '
        'same sentences as one for this draft alone', () {
      final approved = _doc('## Statement\nKept. Gone.\n');
      final draft = _doc('## Statement\nKept.\n');
      final own = sentenceChangesOf(
        draft: draft,
        approved: approved,
        tree: sentenceSetOf([draft]),
        runCopies: const {},
      );

      final shared = sentenceChangesOf(
        draft: draft,
        approved: approved,
        tree: sentenceSetOf([draft, _doc('## Statement\nOther draft.\n')]),
        runCopies: const {},
      );

      expect(shared.dropped, own.dropped);
      expect(shared.dropped, ['Gone.']);
    });
  });

  group('a sentence is held only by an equal sentence', () {
    test('a removed item whose text sits only in frontmatter is dropped', () {
      final changes = _changes(
        approved: '## Statement\n- lib/core.dart\n- Kept.\n',
        draft: '## Statement\n- Kept.\n',
        tree: ['---\ncovers:\n  - lib/core.dart\n---\n\n# A\n'],
      );
      expect(changes.dropped, ['lib/core.dart']);
    });

    test(
      'a removed item whose text sits inside a longer sentence is dropped',
      () {
        final changes = _changes(
          approved: '## Statement\n- ci.yaml\n- Kept.\n',
          draft: '## Statement\n- Kept.\n',
          tree: ['## Rules\nRun `ci.yaml` on each push.\n'],
        );
        expect(changes.dropped, ['ci.yaml']);
      },
    );

    test(
      'labelled lines split into a label and nested items list each side',
      () {
        const approved =
            '## Verification\n'
            '- **Pass criteria:** A holds.\n'
            '- **Pass criteria:** B holds.\n';
        final changes = _changes(
          approved: approved,
          draft:
              '## Verification\n- **Pass criteria:**\n  - A holds.\n'
              '  - B holds.\n',
          runCopies: [approved],
        );
        expect(changes.dropped, [
          '**Pass criteria:** A holds.',
          '**Pass criteria:** B holds.',
        ]);
        expect(changes.added, ['**Pass criteria:**', 'A holds.', 'B holds.']);
      },
    );

    test('two items with no closing mark joined into one paragraph', () {
      const approved = '## Statement\n- First item\n- Second item\n';
      final changes = _changes(
        approved: approved,
        draft: '## Statement\nFirst item Second item\n',
        runCopies: [approved],
      );
      expect(changes.dropped, ['First item', 'Second item']);
      expect(changes.added, ['First item Second item']);
    });

    test('a sentence moved into a ## header elsewhere is dropped', () {
      final changes = _changes(
        approved: '## Statement\nMoved here. Kept.\n',
        draft: '## Statement\nKept.\n',
        tree: ['## Moved here.\n'],
      );
      expect(changes.dropped, ['Moved here.']);
    });

    test('a sentence moved into fenced code elsewhere is dropped', () {
      final changes = _changes(
        approved: '## Statement\nMoved here. Kept.\n',
        draft: '## Statement\nKept.\n',
        tree: ['## Notes\n```\nMoved here.\n```\n'],
      );
      expect(changes.dropped, ['Moved here.']);
    });

    test('a sentence moved into a ### heading elsewhere is held', () {
      final changes = _changes(
        approved: '## Statement\nMoved here. Kept.\n',
        draft: '## Statement\nKept.\n',
        tree: ['## Notes\n### Moved here.\n'],
      );
      expect(changes.dropped, isEmpty);
    });
  });
}
