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

/// A link of [text] to [anchor] of other.md, placed on file line 8.
LinkText _link(String text, String? anchor) => (
  line: 8,
  column: 0,
  endLine: 8,
  endColumn: text.length + 4,
  text: text,
  target: 'other.md',
  anchor: anchor,
);

/// The link of [text] to [anchor] as written in [line], as the scan places
/// it.
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

/// [cite] as a string a test compares by value.
String _show(LinkCite cite) => switch (cite) {
  DocCite() => 'doc',
  SectionCite(:final sectionKey) => 'section $sectionKey',
  ItemCite(:final sectionKey, :final itemId) => 'item $sectionKey $itemId',
  HeadingBlockCite(:final headingLine) => 'block $headingLine',
  UnresolvedCite() => 'unresolved',
  OtherAnchorCite() => 'other anchor',
};

/// [target] as a string a test compares by value.
String? _showTarget(AnchorTarget? target) => switch (target) {
  null => null,
  SectionTarget(:final sectionIndex) => 'section $sectionIndex',
  HeadingBlockTarget(:final headingLine) => 'block $headingLine',
  OtherAnchorTarget() => 'other',
};

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

/// The extent of [itemId] in [text] as `first-last`, or null.
String? _extent(
  String text,
  String itemId, {
  String? prefix,
  bool isAcceptanceCriteria = false,
}) {
  final extent = itemExtentOf(
    _body(text),
    itemId,
    prefixId: prefix ?? itemId.replaceFirst(RegExp(r'\d+$'), ''),
    isAcceptanceCriteria: isAcceptanceCriteria,
  );
  return extent == null ? null : '${extent.first}-${extent.last}';
}

void main() {
  group('classifyLink', () {
    const doc =
        '# T\n\n## Invariants\n\n- INV-1 one\n\n## Acceptance criteria\n\n'
        '### Scenario 6\n\nText.\n\n<a name="x"></a>\n';
    final facts = _factsOf('---\nx: 1\n---\n\n$doc');

    CitedSection? sectionAt(int index) => switch (index) {
      0 => (key: 'invariants', prefixId: 'INV-', isAcceptanceCriteria: false),
      1 => (
        key: 'acceptance_criteria',
        prefixId: null,
        isAcceptanceCriteria: true,
      ),
      _ => null,
    };

    String classify(
      String text,
      String? anchor, {
      LineFacts? on,
      CitedSection? Function(int)? at,
    }) {
      final target = anchor == null || anchor.isEmpty
          ? null
          : anchorTargetOf(on ?? facts, anchor);
      return _show(
        classifyLink(
          _link(text, anchor),
          target: target,
          sectionAt: at ?? sectionAt,
        ),
      );
    }

    test('f04/us02/fr09/e01: a link whose whole text is an item ID of the '
        'section its anchor names is an item link', () {
      expect(classify('INV-9', 'invariants'), 'item invariants INV-9');
    });

    test('f04/us02/fr09/e06: a link whose text is no item ID of that '
        'section is a section link', () {
      expect(classify('the rules', 'invariants'), 'section invariants');
    });

    test('topic:doc_model#rules RULE-33: a lettered form is no item ID', () {
      expect(classify('INV-9a', 'invariants'), 'section invariants');
    });

    test('f04/us02/fr09/e03: S<N> on an acceptance_criteria section names '
        'its Scenario block, by number value', () {
      expect(
        classify('S06', 'acceptance-criteria'),
        'item acceptance_criteria Scenario 6',
      );
    });

    test('f04/us02/fr09/e06: S<N> on any other section is no scenario', () {
      expect(classify('S6', 'invariants'), 'section invariants');
    });

    test('f01/us05/fr05/e06: a doc link with no fragment or an empty one '
        'is a doc cite', () {
      expect(classify('text', null), 'doc');
      expect(classify('text', ''), 'doc');
    });

    test('f01/us05/fr05/e03: a fragment naming a ### heading with no ID '
        'text is that heading block cite', () {
      expect(classify('the block', 'scenario-6'), 'block 13');
    });

    test('f04/us02/fr09/e07: a ### anchor is a heading block even when the '
        'text reads as an item ID', () {
      expect(classify('INV-1', 'scenario-6'), 'block 13');
    });

    test('f01/us05/fr05/e13: a fragment that matches no anchor of the '
        'target is unresolved, never a doc cite', () {
      expect(classify('INV-9', 'missing'), 'unresolved');
    });

    test('topic:doc_model#rules RULE-45: an html id and the title are '
        'anchors the doc holds, so no pointer is broken', () {
      expect(classify('INV-9', 'x'), 'other anchor');
      expect(classify('INV-9', 't'), 'other anchor');
    });

    test('topic:doc_model#rules RULE-45: a heading whose line the scan '
        'cannot pair is an anchor the doc holds, and a missing one on that '
        'doc is still missing', () {
      final setext = _factsOf('# T\n\nSetext\n------\n\n## A\n');
      expect(classify('INV-1', 'a', on: setext), 'other anchor');
      expect(classify('INV-1', 'nope', on: setext), 'unresolved');
    });

    test('topic:doc_model#rules RULE-45: a section the caller holds none '
        'of is no broken pointer', () {
      expect(classify('INV-1', 'invariants', at: (_) => null), 'other anchor');
    });
  });

  group('anchorTargetOf', () {
    test('f01/us05/fr05/e05: a ## anchor names its section', () {
      final facts = _factsOf('# T\n\n## Rules\n\n- RULE-1 one\n\n## More\n');
      expect(_showTarget(anchorTargetOf(facts, 'rules')), 'section 0');
      expect(_showTarget(anchorTargetOf(facts, 'more')), 'section 1');
    });

    test('f01/us05/fr05/e03: a ### anchor names its heading block line', () {
      final facts = _factsOf(
        '# T\n\n## Acceptance criteria\n\n### Scenario 6\n\nText.\n',
      );
      expect(_showTarget(anchorTargetOf(facts, 'scenario-6')), 'block 5');
    });

    test('topic:doc_model#rules RULE-13: unknown heading lines give no '
        'section or block, never a guess', () {
      final facts = _factsOf('# T\n\n## A\n\nSetext\n---\n\n## B\n');
      expect(facts.headingLines, isNull);
      expect(_showTarget(anchorTargetOf(facts, 'a')), 'other');
      expect(_showTarget(anchorTargetOf(facts, 'b')), 'other');
      expect(anchorTargetOf(facts, 'c'), isNull);
    });

    test('f01/us05/fr05/e13: an anchor the doc holds nowhere gives null', () {
      final facts = _factsOf('# T\n\n## Rules\n');
      expect(anchorTargetOf(facts, 'invariants'), isNull);
    });

    test('topic:doc_model#rules RULE-45: an html id and the title give '
        'the other-anchor target', () {
      final facts = _factsOf('# T\n\n## Rules\n\n<a name="x"></a>\n');
      expect(facts.anchors!.holds('x'), isTrue);
      expect(_showTarget(anchorTargetOf(facts, 'x')), 'other');
      expect(_showTarget(anchorTargetOf(facts, 't')), 'other');
    });
  });

  group('itemRangesOn', () {
    /// The ranges of [line], each link `(text, anchor)` of other.md cited as
    /// an item link of `rules` when its text starts `RULE-`, else a section
    /// link.
    List<String> rangesIn(String line, List<(String, String)> links) => [
      for (final r in itemRangesOn(line, [
        for (final (text, anchor) in links)
          (
            link: _linkIn(line, text, anchor),
            cite: text.startsWith('RULE-')
                ? ItemCite(sectionKey: anchor, itemId: text)
                : SectionCite(sectionKey: anchor),
          ),
      ]))
        '${r.first.cite.itemId}-${r.last.cite.itemId}',
    ];

    test('f01/us05/fr05/e04: two item links to one section joined by '
        '" to " pair into one range', () {
      const line = '[RULE-14](other.md#rules) to [RULE-19](other.md#rules)';
      expect(rangesIn(line, [('RULE-14', 'rules'), ('RULE-19', 'rules')]), [
        'RULE-14-RULE-19',
      ]);
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
      const line = '[RULE-14](other.md#rules) to [RULE-2](other.md#invariants)';
      expect(
        rangesIn(line, [('RULE-14', 'rules'), ('RULE-2', 'invariants')]),
        isEmpty,
      );
    });

    test('topic:doc_model#rules RULE-47: a link alone gives no range', () {
      expect(
        rangesIn('[RULE-14](other.md#rules)', [('RULE-14', 'rules')]),
        isEmpty,
      );
    });

    test('topic:doc_model#rules RULE-47: a middle link ends one range and '
        'starts the next', () {
      const line =
          '[RULE-14](other.md#rules) to [RULE-16](other.md#rules) to '
          '[RULE-19](other.md#rules)';
      expect(
        rangesIn(line, [
          ('RULE-14', 'rules'),
          ('RULE-16', 'rules'),
          ('RULE-19', 'rules'),
        ]),
        ['RULE-14-RULE-16', 'RULE-16-RULE-19'],
      );
    });

    test('topic:doc_model#rules RULE-47: a section link with a digit in its '
        'text joins no range', () {
      const line = '[v2](other.md#rules) to [RULE-19](other.md#rules)';
      expect(rangesIn(line, [('v2', 'rules'), ('RULE-19', 'rules')]), isEmpty);
    });

    test('topic:doc_model#rules RULE-47: links on two lines never pair', () {
      const line = '[RULE-14](other.md#rules) to';
      const second = (
        line: 9,
        column: 0,
        endLine: 9,
        endColumn: 10,
        text: 'RULE-19',
        target: 'other.md',
        anchor: 'rules',
      );
      final ranges = itemRangesOn(line, [
        (
          link: _linkIn(line, 'RULE-14', 'rules'),
          cite: const ItemCite(sectionKey: 'rules', itemId: 'RULE-14'),
        ),
        (
          link: second,
          cite: const ItemCite(sectionKey: 'rules', itemId: 'RULE-19'),
        ),
      ]);
      expect(ranges, isEmpty);
    });
  });

  group('itemExtentOf', () {
    test('f01/us05/fr05/e01: an item spans its nested items', () {
      expect(
        _extent(
          '- RULE-1 one\n  - Enforcer\n  - Consistency\n- RULE-2 two\n',
          'RULE-1',
        ),
        '20-22',
      );
    });

    test('f01/us05/fr05/e01: a bold ID, the form the docs use, is found '
        'with its nested items', () {
      expect(
        _extent(
          '- **INV-14** one\n  - Enforcer\n  - Consistency\n- **INV-15** two\n',
          'INV-14',
        ),
        '20-22',
      );
      expect(
        _extent('- **INV-14** one\n- **INV-15** two\n', 'INV-15'),
        '21-21',
      );
    });

    test('f01/us05/fr05/e01: the ID is read as the index reads it, so a '
        'lettered or longer ID is another item', () {
      const text = '- RULE-1a lettered\n- RULE-12 twelve\n- RULE-1 one\n';
      expect(_extent(text, 'RULE-1'), '22-22');
      expect(_extent(text, 'RULE-12'), '21-21');
    });

    test('f01/us05/fr05/e01: a nested ID item stops before its sibling '
        'nested items', () {
      const text = '- Group\n  - INV-1 a\n    - note\n  - INV-2 b\n- INV-3 c\n';
      expect(_extent(text, 'INV-1', prefix: 'INV-'), '21-22');
      expect(_extent(text, 'INV-2', prefix: 'INV-'), '23-23');
    });

    test('f01/us05/fr05/e01: an indented fence that closes a list item '
        'stays in its extent, an unindented one does not', () {
      const text =
          '- RULE-1 x\n  ```dart\n  code\n  ```\n- RULE-2 y\n```\nz\n```\n';
      expect(_extent(text, 'RULE-1'), '20-23');
      expect(_extent(text, 'RULE-2'), '24-24');
    });

    test('f01/us05/fr05/e01: a blank line before an indented fence keeps '
        'the code in the extent', () {
      const text = '- RULE-1 x\n\n  ```dart\n  code\n  ```\n\n- RULE-2 y\n';
      expect(_extent(text, 'RULE-1'), '20-24');
      expect(_extent(text, 'RULE-2'), '26-26');
    });

    test('f01/us05/fr05/e01: blank lines before an unindented fence, or '
        'before the next item, stay out of the extent', () {
      const text = '- RULE-1 x\n\n```\nz\n```\n- RULE-2 y\n';
      expect(_extent(text, 'RULE-1'), '20-20');
    });

    test('f01/us05/fr05/e02: an item an ID-headed ### heading starts spans '
        'its block up to the next heading of its level, blanks off', () {
      expect(
        _extent(
          '### NFR-P01 — Fast\n\n**Statement:** fast.\n\n'
              '### NFR-P02 — Cheap\n',
          'NFR-P01',
        ),
        '20-22',
      );
    });

    test('f01/us05/fr05/e02: a bold ID heading is found, and a deeper '
        'heading does not end the block', () {
      expect(
        _extent(
          '### **NFR-P01** — Fast\n\n#### Notes\n\ntext\n\n### Other\n',
          'NFR-P01',
        ),
        '20-24',
      );
    });

    test('f01/us05/fr05/e02: a quoted heading item ends at the next '
        'heading of its level', () {
      expect(
        _extent('> ### NFR-P01 — Fast\n>\n> text\n\n### Next\n', 'NFR-P01'),
        '20-22',
      );
    });

    test('topic:doc_model#rules RULE-46: a Scenario block spans its '
        'block, by number value, on an acceptance_criteria section', () {
      const text = '### Scenario 06\n\n- given\n\n### Scenario 7\n';
      expect(
        _extent(text, 'Scenario 6', prefix: null, isAcceptanceCriteria: true),
        '20-22',
      );
    });

    test('f04/us02/fr09/e02: an ID the section holds no item of gives no '
        'extent', () {
      expect(_extent('- RULE-1 one\n', 'RULE-9'), isNull);
    });

    test('topic:doc_model#rules RULE-19: an item that carries no ID gives '
        'no extent', () {
      expect(_extent('- plain text\n', 'RULE-1'), isNull);
    });
  });

  group('headingBlockExtentOf', () {
    test('f01/us05/fr05/e03: a ### heading with no ID spans its block up '
        'to the next heading of its level or above', () {
      final extent = headingBlockExtentOf(
        _body('### Notes\n\ntext\n\n#### Deeper\n\nmore\n\n### Next\n'),
        20,
      );
      expect(extent, (first: 20, last: 26));
    });

    test('f01/us05/fr05/e03: a heading inside fenced code ends nothing', () {
      final extent = headingBlockExtentOf(
        _body('### Notes\n```\n### no\n```\ntail\n'),
        20,
      );
      expect(extent, (first: 20, last: 24));
    });

    test('f01/us05/fr05/e03: a line that is no heading has no block', () {
      expect(headingBlockExtentOf(_body('text\n'), 20), isNull);
      expect(headingBlockExtentOf(_body('text\n'), 99), isNull);
    });
  });
}
