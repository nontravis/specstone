import 'package:specstone_core/src/setup_migration/heading_ledger.dart';
import 'package:test/test.dart';

/// The landing of [anchor] of [docPath], as `doc#slug`, `doc` for the doc
/// whole, `lost doc`, or null.
String? _landed(FinalAnchors anchors, String docPath, String? anchor) =>
    switch (anchors.landingOf(docPath, anchor)) {
      null => null,
      LinkLanding(isLost: true, :final docPath) => 'lost $docPath',
      LinkLanding(:final docPath, slug: null) => docPath,
      LinkLanding(:final docPath, :final slug) => '$docPath#$slug',
    };

void main() {
  test('a renamed heading lands at its new slug, and a doc no step '
      'touched keeps every link', () {
    const after = '# A\n\n## Procedure\n';
    final ledger = HeadingLedger()
      ..renamed('a.md', before: '# A\n\n## Steps\n', after: after);

    final anchors = ledger.resolve({'a.md': after});

    expect(_landed(anchors, 'a.md', 'steps'), 'a.md#procedure');
    expect(_landed(anchors, 'b.md', 'steps'), isNull);
  });

  test('a dropped heading is lost while a kept one its drop renumbers '
      'lands at its new slug', () {
    const before = '# A\n\n## Q\n\n### Dup\n\n## G\n\n### Dup\n';
    const after = '# A\n\n## G\n\n### Dup\n';
    final ledger = HeadingLedger()
      ..dropped('a.md', before: before, after: after, header: 'Q');

    final anchors = ledger.resolve({'a.md': after});

    expect(_landed(anchors, 'a.md', 'dup'), 'lost a.md');
    expect(_landed(anchors, 'a.md', 'dup-1'), 'a.md#dup');
    expect(_landed(anchors, 'a.md', 'q'), 'lost a.md');
  });

  test('a folded doc lands in its to doc: a joined section under its '
      'group header, the doc whole under its first section', () {
    const from = '# P\n\n## Moves\n\n## Steps\n\n### Sub\n';
    const toBefore = '# R\n\n## Goals\n';
    const toAfter = '# R\n\n## Goals\n\n## Procedure\n\n### Sub\n';
    final ledger = HeadingLedger()
      ..folded(
        fromPath: 'p.md',
        fromLf: from,
        toPath: 'r.md',
        toBefore: toBefore,
        toAfter: toAfter,
        groups: [
          [0, 1],
        ],
      );

    final anchors = ledger.resolve({'r.md': toAfter});

    expect(_landed(anchors, 'p.md', null), 'r.md#procedure');
    expect(_landed(anchors, 'p.md', 'steps'), 'r.md#procedure');
    expect(_landed(anchors, 'p.md', 'sub'), 'r.md#sub');
    expect(_landed(anchors, 'r.md', 'goals'), 'r.md#goals');
  });

  test('a dropped heading keeps its slug only when a fold brought that slug '
      'into the doc the link names', () {
    const toAfter = '# R\n\n## Goals\n\n## Procedure\n\n## Notes\n';
    final ledger = HeadingLedger()
      ..dropped(
        'p.md',
        before: '# P\n\n## Moves\n\n## Notes\n',
        after: '# P\n\n## Moves\n',
        header: 'Notes',
      )
      ..dropped(
        'r.md',
        before: '# R\n\n## Goals\n\n## Notes\n',
        after: '# R\n\n## Goals\n',
        header: 'Notes',
      )
      ..folded(
        fromPath: 'q.md',
        fromLf: '# Q\n\n## Procedure\n\n## Notes\n',
        toPath: 'r.md',
        toBefore: '# R\n\n## Goals\n',
        toAfter: toAfter,
        groups: [
          [0],
          [1],
        ],
      )
      ..folded(
        fromPath: 'p.md',
        fromLf: '# P\n\n## Moves\n',
        toPath: 's.md',
        toBefore: '# S\n\n## Notes\n',
        toAfter: '# S\n\n## Notes\n\n## Moves\n',
        groups: [
          [0],
        ],
      );

    final anchors = ledger.resolve({
      'r.md': toAfter,
      's.md': '# S\n\n## Notes\n\n## Moves\n',
    });

    expect(_landed(anchors, 'r.md', 'notes'), 'r.md#notes');
    expect(_landed(anchors, 'p.md', 'notes'), 'lost s.md');
  });

  test('a final text whose headings the track cannot explain keeps every '
      'anchor', () {
    final ledger = HeadingLedger()
      ..renamed('a.md', before: '# A\n\n## Steps\n', after: '# A\n\n## B\n');

    final anchors = ledger.resolve({'a.md': '# A\n\n## B\n\n## Extra\n'});

    expect(_landed(anchors, 'a.md', 'steps'), 'a.md#steps');
  });
}
