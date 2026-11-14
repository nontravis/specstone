import 'dart:convert';

import 'package:specstone_core/src/doc_model/body_line.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:test/test.dart';

/// The line facts of [text], as refresh computes them.
LineFacts _factsOf(String text) => parseIndexedDoc(
  docPath: 'doc.md',
  bytes: utf8.encode(text),
  match: const NoDocType(),
).content.lineFacts;

/// A link of text [text] pointing at [anchor] of [target], at [column] of
/// file line [line].
LinkText _link(
  String text,
  String? anchor, {
  String target = 'other.md',
  int line = 8,
  int column = 0,
}) => (
  line: line,
  column: column,
  endLine: line,
  endColumn: column + text.length + 4,
  text: text,
  target: target,
  anchor: anchor,
);

/// [cite] as a string a test compares by value.
String _show(LinkCite cite) => switch (cite) {
  DocCite() => 'doc',
  SectionCite(:final sectionKey) => 'section $sectionKey',
  ItemCite(:final sectionKey, :final itemId) => 'item $sectionKey $itemId',
  HeadingBlockCite(:final headingAnchor) => 'block $headingAnchor',
};

/// [target] as a string a test compares by value.
String? _showTarget(AnchorTarget? target) => switch (target) {
  null => null,
  SectionTarget(:final sectionIndex) => 'section $sectionIndex',
  HeadingBlockTarget(:final headingLine) => 'block $headingLine',
};

/// The link of [text] to [anchor] as written in [line], as the scan places it.
LinkText _linkIn(String line, String text, String anchor) {
  final column = line.indexOf('[$text](');
  return (
    line: 8,
    column: column,
    endLine: 8,
    endColumn: line.indexOf(')', column) + 1,
    text: text,
    target: 'other.md',
    anchor: anchor,
  );
}

/// The body lines of [text], numbered from line 20, fence lines and the
/// lines between them fenced.
List<BodyLine> _body(String text) {
  var inFence = false;
  return [
    for (final (k, line) in text.split('\n').indexed)
      (
        text: line,
        line: 20 + k,
        fenced: () {
          final isFence = line.trimLeft().startsWith('```');
          final fenced = inFence || isFence;
          if (isFence) inFence = !inFence;
          return fenced;
        }(),
      ),
  ];
}

void main() {
  group('classifyLink', () {
    const doc =
        '# T\n\n## Invariants\n\n- INV-1 one\n\n## Acceptance criteria\n\n'
        '### Scenario 6\n\nText.\n';
    final facts = _factsOf('---\nx: 1\n---\n\n$doc');

    String classify(
      String text,
      String? anchor, {
      String? prefixId = 'INV-',
      bool isAcceptanceCriteria = false,
    }) {
      final target = anchor == null || anchor.isEmpty
          ? null
          : anchorTargetOf(facts, anchor);
      return _show(
        classifyLink(
          _link(text, anchor),
          target: target,
          sectionKey: switch (target) {
            SectionTarget(:final sectionIndex) => 'section$sectionIndex',
            _ => null,
          },
          prefixId: prefixId,
          isAcceptanceCriteria: isAcceptanceCriteria,
        ),
      );
    }

    test('f04/us02/fr09 E01: a link whose whole text is an item ID of the '
        'section its anchor names is an item link', () {
      expect(classify('INV-9', 'invariants'), 'item section0 INV-9');
    });

    test('f04/us02/fr09 E06: a link whose text is no item ID of that '
        'section is a section link', () {
      expect(classify('the rules', 'invariants'), 'section section0');
    });

    test('topic:doc_model#rules RULE-33: a lettered form is no item ID', () {
      expect(classify('INV-9a', 'invariants'), 'section section0');
    });

    test('f04/us02/fr09 E03: S<N> on an acceptance_criteria section names '
        'its Scenario block, by number value', () {
      expect(
        classify(
          'S06',
          'acceptance-criteria',
          prefixId: null,
          isAcceptanceCriteria: true,
        ),
        'item section1 Scenario 6',
      );
    });

    test('f04/us02/fr09 E06: S<N> on any other section is no scenario', () {
      expect(classify('S6', 'invariants'), 'section section0');
    });

    test('topic:doc_model#rules RULE-45: a doc link with no fragment or an '
        'empty one is a doc cite', () {
      expect(classify('text', null), 'doc');
      expect(classify('text', ''), 'doc');
    });

    test('topic:doc_model#rules RULE-46: a fragment naming a ### heading '
        'with no ID text is that heading block cite', () {
      expect(classify('the block', 'scenario-6'), 'block scenario-6');
    });

    test('f04/us02/fr09 E04: an anchor that names no heading is a doc '
        'cite, since no section is named', () {
      expect(classify('INV-9', 'missing'), 'doc');
    });
  });

  group('anchorTargetOf', () {
    test('f01/us05/fr05 E05: a ## anchor names its section', () {
      final facts = _factsOf('# T\n\n## Rules\n\n- RULE-1 one\n\n## More\n');
      final target = anchorTargetOf(facts, 'rules');
      expect(_showTarget(target), 'section 0');
    });

    test('topic:doc_model#rules RULE-46: a ### anchor names its heading '
        'block line', () {
      final facts = _factsOf(
        '# T\n\n## Acceptance criteria\n\n### Scenario 6\n\nText.\n',
      );
      final target = anchorTargetOf(facts, 'scenario-6');
      expect(_showTarget(target), 'block 5');
    });

    test('f01/us05/fr05 E16: unknown heading lines give no target, never a '
        'guess', () {
      final facts = _factsOf('# T\n\n## A\n\nSetext\n---\n\n## B\n');
      expect(facts.headingLines, isNull);
      expect(anchorTargetOf(facts, 'a'), isNull);
      expect(anchorTargetOf(facts, 'b'), isNull);
    });

    test('f04/us02/fr09 E04: an anchor of no heading gives no target', () {
      final facts = _factsOf('# T\n\n## Rules\n');
      expect(anchorTargetOf(facts, 'invariants'), isNull);
    });

    test('f01/us05/fr05 E05: an html id of no heading gives no target', () {
      final facts = _factsOf('# T\n\n## Rules\n\n<a name="x"></a>\n');
      expect(facts.anchors!.holds('x'), isTrue);
      expect(anchorTargetOf(facts, 'x'), isNull);
    });
  });

  group('itemRangesOn', () {
    List<ItemRange> rangesIn(String line, List<(String, String)> links) =>
        itemRangesOn(line, [
          for (final (text, anchor) in links) _linkIn(line, text, anchor),
        ]);

    test('topic:doc_model#rules RULE-47: two item links to one section '
        'joined by " to " pair into one range', () {
      const line = '[RULE-14](other.md#rules) to [RULE-19](other.md#rules)';
      final ranges = rangesIn(line, [
        ('RULE-14', 'rules'),
        ('RULE-19', 'rules'),
      ]);
      expect(
        [for (final r in ranges) (r.first.text, r.last.text)],
        [('RULE-14', 'RULE-19')],
      );
    });

    test('topic:doc_model#rules RULE-47: text other than " to " between '
        'the links gives no range', () {
      const line = '[RULE-14](other.md#rules) and [RULE-19](other.md#rules)';
      expect(
        rangesIn(line, [('RULE-14', 'rules'), ('RULE-19', 'rules')]),
        isEmpty,
      );
    });

    test('topic:doc_model#rules RULE-47: links of two sections never pair', () {
      const line = '[RULE-14](other.md#rules) to [INV-2](other.md#invariants)';
      expect(
        rangesIn(line, [('RULE-14', 'rules'), ('INV-2', 'invariants')]),
        isEmpty,
      );
    });

    test('topic:doc_model#rules RULE-47: a link alone gives no range', () {
      const line = '[RULE-14](other.md#rules)';
      expect(rangesIn(line, [('RULE-14', 'rules')]), isEmpty);
    });

    test('topic:doc_model#rules RULE-47: a middle link ends one range and '
        'starts the next', () {
      const line =
          '[RULE-14](other.md#rules) to [RULE-16](other.md#rules) to '
          '[RULE-19](other.md#rules)';
      final ranges = rangesIn(line, [
        ('RULE-14', 'rules'),
        ('RULE-16', 'rules'),
        ('RULE-19', 'rules'),
      ]);
      expect(
        [for (final r in ranges) (r.first.text, r.last.text)],
        [('RULE-14', 'RULE-16'), ('RULE-16', 'RULE-19')],
      );
    });

    test('f04/us02/fr09 E08: links on two lines never pair', () {
      const line = '[RULE-14](other.md#rules) to';
      final first = _linkIn(line, 'RULE-14', 'rules');
      const last = (
        line: 9,
        column: 0,
        endLine: 9,
        endColumn: 10,
        text: 'RULE-19',
        target: 'other.md',
        anchor: 'rules',
      );
      expect(itemRangesOn(line, [first, last]), isEmpty);
    });
  });

  group('itemExtentOf', () {
    test('f01/us05/fr05 E01: an item spans its nested items', () {
      final extent = itemExtentOf(
        _body(
          '- RULE-1 one\n'
          '  - Enforcer\n'
          '  - Consistency\n'
          '- RULE-2 two\n',
        ),
        'RULE-1',
      );
      expect(extent, (first: 20, last: 22));
    });

    test('f01/us05/fr05 E02: an item an ID-headed ### heading starts spans '
        'its block up to the next heading of its level or above', () {
      final extent = itemExtentOf(
        _body(
          '### NFR-P01 — Fast\n'
          '\n'
          '**Statement:** fast.\n'
          '\n'
          '### NFR-P02 — Cheap\n',
        ),
        'NFR-P01',
      );
      expect(extent, (first: 20, last: 22));
    });

    test('f01/us05/fr05 E02: a deeper heading under the block does not end '
        'it', () {
      final extent = itemExtentOf(
        _body(
          '### NFR-P01 — Fast\n'
          '\n'
          '#### Notes\n'
          '\n'
          'text\n'
          '\n'
          '## Next section\n',
        ),
        'NFR-P01',
      );
      expect(extent, (first: 20, last: 24));
    });

    test('f04/us02/fr09 E03: a Scenario block is a heading block', () {
      final extent = itemExtentOf(
        _body(
          '### Scenario 6\n'
          '\n'
          '- given\n'
          '\n'
          '### Scenario 7\n',
        ),
        'Scenario 6',
      );
      expect(extent, (first: 20, last: 22));
    });

    test('f04/us02/fr09 E02: an ID the section holds no item of gives no '
        'extent', () {
      expect(itemExtentOf(_body('- RULE-1 one\n'), 'RULE-9'), isNull);
    });

    test('topic:doc_model#rules RULE-19: an item that carries no ID gives '
        'no extent', () {
      expect(itemExtentOf(_body('- plain text\n'), 'RULE-1'), isNull);
    });
  });
}
