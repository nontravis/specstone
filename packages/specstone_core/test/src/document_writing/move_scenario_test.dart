// Each test name states one behavior on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show MoveJournal;
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, fingerprintFor;
import '../../helpers/nested_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/write_fixture.dart';

const _addItem = 'user_story:shop/cart/add_item';
const _dropItem = 'user_story:shop/cart/drop_item';
const _payCardAddress = 'user_story:shop/pay/card';

String _scenario(int number, {String title = '', String tag = 'edge'}) =>
    '### Scenario $number — [$tag] Case $number$title\n\n'
    '- **Given** a cart in case $number\n'
    '- **When** the shopper acts\n'
    '- **Then** the shopper sees case $number';

/// The scenarios 1 to [count], each its own case.
List<String> _scenarios(int count) => [
  for (var n = 1; n <= count; n++) _scenario(n),
];

String _rule(int number) => '- **BR-0$number** — Rule $number holds.';

/// A story body: its scenarios, its rules, and a paragraph closing its
/// Acceptance Criteria.
String _storyBody(
  String title,
  List<String> scenarios, {
  List<String> rules = const [],
  String? closing,
}) {
  final rulesSection = rules.isEmpty
      ? ''
      : '## Rules\n\n${rules.join('\n')}\n\n';
  final closingText = closing == null ? '' : '\n\n$closing';
  return '# $title\n\n## Use Case\n\n'
      '- **As a** Agent who shops\n- **I want to** act\n'
      '- **so that** I finish an order\n\n'
      '$rulesSection## Acceptance Criteria\n\n'
      '${scenarios.join('\n\n')}$closingText\n';
}

String _story(
  String title,
  List<String> scenarios, {
  List<String> rules = const [],
  String? closing,
}) =>
    '---\ngoals:\n  - PG-01\n---\n\n'
    '${_storyBody(title, scenarios, rules: rules, closing: closing)}';

Future<Directory> _project({
  List<String>? add,
  List<String>? drop,
  List<String> addRules = const [],
  List<String> dropRules = const [],
  String? addClosing,
  String? dropClosing,
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeNestedProject(
  without: without,
  extra: {
    'docs/$cartAdd': _story(
      'Agent adds an item',
      add ?? _scenarios(3),
      rules: addRules,
      closing: addClosing,
    ),
    'docs/$cartDrop': _story(
      'Agent drops an item',
      drop ?? _scenarios(2),
      rules: dropRules,
      closing: dropClosing,
    ),
    ...extra,
  },
);

ReadAnswer _move(
  Directory root,
  List<String> addresses, {
  String? under = _dropItem,
  bool top = false,
  String? codeTarget,
  bool dryRun = false,
}) => writeIn(
  root,
  (session) => answerMove(
    session,
    addresses,
    under: under,
    top: top,
    codeTarget: codeTarget,
    dryRun: dryRun,
  ),
);

/// Every doc of [root] as bytes, so a test shows a refusal wrote none.
Map<String, List<int>> _docs(Directory root) => {
  for (final entry in treeBytes(root).entries)
    if (entry.key.startsWith('docs/')) entry.key: entry.value,
};

/// Runs the move and returns the fault it raised, asserting no doc changed.
Object _refusal(
  Directory root,
  List<String> addresses, {
  String? under = _dropItem,
  bool top = false,
  bool dryRun = false,
}) {
  final before = _docs(root);
  try {
    _move(root, addresses, under: under, top: top, dryRun: dryRun);
  } on Object catch (fault) {
    expect(_docs(root), before, reason: 'a refused move writes no doc');
    return fault;
  }
  return fail('no fault raised');
}

const _dropFr =
    'prds/features/f02_shop/f01_cart/us02_drop_item/fr01_keep_cart.md';
const _payFr = 'prds/features/f02_shop/f02_pay/us01_card/fr01_charge_card.md';
const _journey = 'prds/journeys/buy/JOURNEY.md';
const _toAddItem = '../../../prds/features/f02_shop/f01_cart/us01_add_item';
const _toDropItem = '../../../prds/features/f02_shop/f01_cart/us02_drop_item';

final String _fp1 = fingerprintFor(_scenario(1));
final String _fp2 = fingerprintFor(_scenario(2));

/// Scenario 2 as it lands renumbered to Scenario 3.
final String _fp2Landed = fingerprintFor(
  _scenario(2).replaceFirst('### Scenario 2', '### Scenario 3'),
);

/// A fingerprint no block of the fixture holds, so its entry is stale.
const _stale = '0123456789ab';

String _list(String key, List<String> entries) =>
    '$key:\n${[for (final entry in entries) '  - $entry\n'].join()}';

String _fr(String title, List<String> traced, List<String> confirmed) =>
    '---\n${_list('traced_from', traced)}verify_method: test\n'
    '${_list('confirmed', confirmed)}---\n\n'
    '# $title\n\n## Statement\nThe system shall $title.\n\n'
    '## Edge cases\n1. E01 — An empty cart → kept.\n\n'
    '## Rationale\nCarts matter.\n\n'
    '## Verification\nTest: it holds.\n';

/// A project whose docs name scenarios of `add_item` in every reference form.
Future<Directory> _citedProject() => _project(
  addClosing: 'Error cases: see S2.',
  extra: {
    'docs/$cartAddFr': _fr(
      'check the stock',
      ['S1', 'S2', 'shop/cart/add_item#S3'],
      ['S1 $_fp1', 'S2 $_fp2'],
    ),
    'docs/$_dropFr': _fr(
      'keep the cart',
      ['S2', 'cart/add_item#S02'],
      ['S2 $_fp2', 'shop/cart/add_item#S2 $_fp2'],
    ),
    'docs/$_payFr': _fr(
      'charge the card',
      ['S1', 'shop/cart/add_item#S2', 'shop/cart/add_item#S1'],
      ['shop/cart/add_item#S2 $_fp2'],
    ),
    'docs/$_journey':
        '---\n'
        '${_list('confirmed', ['shop/cart/add_item#S1 $_fp1', 'shop/cart/add_item#S2 $_fp2'])}'
        '---\n\n# Buy\n\n## Goal\nBuy.\n\n## Flow\n\n## Steps\n'
        '### 1. Add\nstep: shop/cart/add_item S1\n\n'
        '### 2. Again\nstep: shop/cart/add_item S2\nafter: 1\n',
    'docs/$cartDomain':
        '# Cart domain\n\n## Entities\n'
        '| Entity | Kind | Identity | Owns | Notes |\n'
        '|--------|------|----------|------|-------|\n'
        '| Order | Aggregate root | id | lines | — |\n\n'
        '## Invariants\n- **INV-1** An order holds at least one line.\n'
        '- **INV-2** As [Scenario 2]($_toAddItem/USER_STORY.md#scenario-2--edge-case-2) gives.\n'
        '- **INV-3** As [S2]($_toAddItem/USER_STORY.md#acceptance-criteria) gives.\n'
        '- **INV-4** As [S1]($_toAddItem/USER_STORY.md#acceptance-criteria) to [S3]($_toAddItem/USER_STORY.md#acceptance-criteria) give.\n'
        '- **INV-5** As `shop/cart/add_item#S2` gives.\n'
        '- **INV-6** As [Scenario 2][s2] gives.\n'
        '- **INV-7** As [Scenario 2](<$_toAddItem/USER_STORY.md#scenario-2--edge-case-2>) gives.\n'
        '- **INV-8** As [Scenario 2]($_toAddItem/USER_STORY.md?v=1#scenario-2--edge-case-2) gives.\n\n'
        '[s2]: $_toAddItem/USER_STORY.md#scenario-2--edge-case-2\n',
  },
);

/// The `suspect` findings `check` reports on [docPath], as their JSON.
List<Map<String, Object>> _suspects(Directory root, String docPath) => [
  for (final finding in checkOf(root, docPath: docPath).findings)
    if (finding.kind == FindingKind.suspect) finding.toJson(),
];

/// The doc text after its frontmatter, which carries the move's marks.
String _bodyOf(Directory root, String docPath) => readDoc(
  root,
  docPath,
).replaceFirst(RegExp(r'^---\n.*?\n---\n\n', dotAll: true), '');

void main() {
  test("a moved scenario ends the target story's acceptance criteria with its block whole, and its old number stays unused in the source", () async {
    final root = await _project();
    final answer = _move(root, ['$_addItem#S2']);
    expect(
      _bodyOf(root, cartDrop),
      _storyBody('Agent drops an item', [
        _scenario(1),
        _scenario(2),
        _scenario(2).replaceFirst('### Scenario 2', '### Scenario 3'),
      ]),
    );
    expect(
      _bodyOf(root, cartAdd),
      _storyBody('Agent adds an item', [_scenario(1), _scenario(3)]),
    );
    expect(
      answer.text,
      'moved $cartAdd#S2 to $cartDrop#S3\n'
      'renumbered $cartDrop S2 to S3\n'
      'rewrote $cartAdd\n'
      'rewrote $cartDrop\n',
    );
  });

  test('a scenario number reads by its value, so S02 names Scenario 2 and takes the next free number', () async {
    final root = await _project();
    final answer = _move(root, ['$_addItem#S02']);
    expect(
      _bodyOf(root, cartDrop),
      _storyBody('Agent drops an item', [
        ..._scenarios(2),
        _scenario(2).replaceFirst('### Scenario 2', '### Scenario 3'),
      ]),
    );
    expect(answer.text, startsWith('moved $cartAdd#S2 to $cartDrop#S3\n'));
  });

  test(
    'a number the target lacks is kept and prints no renumbered line',
    () async {
      final root = await _project(add: _scenarios(4));
      final answer = _move(root, ['$_addItem#S4']);
      expect(
        _bodyOf(root, cartDrop),
        _storyBody('Agent drops an item', [..._scenarios(2), _scenario(4)]),
      );
      expect(
        answer.text,
        'moved $cartAdd#S4 to $cartDrop#S4\n'
        'rewrote $cartAdd\n'
        'rewrote $cartDrop\n',
      );
    },
  );

  test('an under that is no user_story is argument_invalid', () async {
    final root = await _project(
      extra: {
        '.specstone/templates/feature.yaml':
            'max_depth: 3\nsections:\n  - id: acceptance_criteria\n'
            '    header: Acceptance Criteria\n',
      },
    );
    for (final (under, docPath) in [
      ('feature:shop/cart', cartFeature),
      ('domain:shop/cart', cartDomain),
      ('fr:shop/cart/add_item/check_stock', cartAddFr),
    ]) {
      final fault = _refusal(root, ['$_addItem#S2'], under: under);
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(fault.exitStatus, 64);
      expect(
        fault.message,
        '$docPath has no acceptance_criteria section for S items',
      );
    }
  });

  test('a number the story lacks is item_not_found', () async {
    final root = await _project();
    for (final addresses in [
      ['$_addItem#S9'],
      ['$_addItem#S2', '$_addItem#S9'],
    ]) {
      final fault = _refusal(root, addresses);
      expect((fault as WriteFault).code, WriteFaultCode.itemNotFound);
      expect(fault.exitStatus, 64);
      expect(fault.message, '$cartAdd holds no S9');
    }
  });

  test("a scenario parted from its title's rule is refused, dry run alike", () async {
    final root = await _project(
      add: [
        _scenario(1),
        _scenario(2),
        _scenario(3, title: ' (BR-02)'),
      ],
      addRules: [_rule(1), _rule(2)],
    );
    for (final dryRun in [false, true]) {
      final fault = _refusal(root, ['$_addItem#S3'], dryRun: dryRun);
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(fault.exitStatus, 64);
      expect(
        fault.message,
        'shop/cart/add_item#S3 names BR-02, which stays; move both in one call',
      );
    }
  });

  test("a scenario and its rule moved together land, and the title names the rule's new ID", () async {
    for (final addresses in [
      ['$_addItem#S3', '$_addItem#BR-02'],
      ['$_addItem#BR-02', '$_addItem#S3'],
    ]) {
      final root = await _project(
        add: [
          _scenario(1),
          _scenario(2),
          _scenario(3, title: ' (BR-02)'),
        ],
        addRules: [_rule(1), _rule(2)],
        dropRules: [_rule(1), _rule(2), _rule(3)],
      );
      _move(root, addresses);
      expect(
        _bodyOf(root, cartDrop),
        _storyBody(
          'Agent drops an item',
          [..._scenarios(2), _scenario(3, title: ' (BR-04)')],
          rules: [_rule(1), _rule(2), _rule(3), '- **BR-04** — Rule 2 holds.'],
        ),
        reason: addresses.join(' '),
      );
      expect(
        _bodyOf(root, cartAdd),
        _storyBody('Agent adds an item', _scenarios(2), rules: [_rule(1)]),
        reason: addresses.join(' '),
      );
    }
  });

  test('a rule that keeps its ID leaves the moved title as written', () async {
    final root = await _project(
      add: [
        _scenario(1),
        _scenario(2),
        _scenario(3, title: ' (BR-02)'),
      ],
      addRules: [_rule(1), _rule(2)],
      dropRules: [_rule(1)],
    );
    _move(root, ['$_addItem#S3', '$_addItem#BR-02']);
    expect(
      _bodyOf(root, cartDrop),
      contains('${_scenario(3, title: ' (BR-02)')}\n'),
    );
  });

  test('a target past its scenario count still takes the move', () async {
    final root = await _project(drop: _scenarios(6));
    final answer = _move(root, ['$_addItem#S2']);
    expect(
      _bodyOf(root, cartDrop),
      _storyBody('Agent drops an item', [
        ..._scenarios(6),
        _scenario(2).replaceFirst('### Scenario 2', '### Scenario 7'),
      ]),
    );
    expect(answer.text, startsWith('moved $cartAdd#S2 to $cartDrop#S7\n'));
    expect([
      for (final finding in checkOf(root, docPath: cartDrop).findings)
        finding.kind,
    ], contains(FindingKind.subsectionsOverLimit));
  });

  test('the source and target stories are marked draft and other rewritten docs keep their approval', () async {
    final root = await _project();
    String approvedOf(String docPath) => RegExp(
      r'^approved: "([^"]+)"$',
      multiLine: true,
    ).firstMatch(readDoc(root, docPath))!.group(1)!;
    final addApproved = approvedOf(cartAdd);
    final dropApproved = approvedOf(cartDrop);
    final untouched = {
      for (final docPath in [cartAddFr, payCard, shopApi])
        docPath: readDoc(root, docPath),
    };
    _move(root, ['$_addItem#S2']);
    for (final (docPath, approved) in [
      (cartAdd, addApproved),
      (cartDrop, dropApproved),
    ]) {
      final text = readDoc(root, docPath);
      expect(text, contains('draft: true\n'), reason: docPath);
      expect(text, contains('approved: "$approved"\n'), reason: docPath);
    }
    for (final MapEntry(key: docPath, value: text) in untouched.entries) {
      expect(readDoc(root, docPath), text, reason: docPath);
    }
  });

  test('a scenario beside a doc target, already in place, named twice, or with top is refused or skipped as the item move does', () async {
    final root = await _project(extra: {'docs/prds/notes.md': '# Notes\n'});
    final beside = _refusal(root, ['$_addItem#S2', _payCardAddress]);
    expect((beside as IndexFault).code, IndexFaultCode.argumentInvalid);
    expect(beside.message, 'move takes item targets or doc targets, not both');

    final top = _refusal(root, ['$_addItem#S2'], under: null, top: true);
    expect((top as IndexFault).code, IndexFaultCode.argumentInvalid);
    expect(top.message, 'move takes --top only with feature targets');

    final noUnder = _refusal(root, ['$_addItem#S2'], under: null);
    expect((noUnder as IndexFault).code, IndexFaultCode.argumentMissing);
    expect(
      noUnder.message,
      'move needs --under <doc address> for item targets',
    );

    final untyped = _refusal(root, ['prds/notes.md#S1']);
    expect((untyped as IndexFault).code, IndexFaultCode.untypedTarget);

    final before = _docs(root);
    final inPlace = _move(root, ['$_dropItem#S1']);
    expect(inPlace.text, isEmpty);
    expect(inPlace.json['moved'], isEmpty);
    expect(_docs(root), before);

    final answer = _move(root, [
      '$_dropItem#S1',
      '$_addItem#S2',
      'shop/cart/add_item#S2',
      '$_addItem#S02',
    ]);
    expect(
      answer.text,
      'moved $cartAdd#S2 to $cartDrop#S3\n'
      'renumbered $cartDrop S2 to S3\n'
      'rewrote $cartAdd\n'
      'rewrote $cartDrop\n',
    );
  });

  test(
    'two clashing scenarios take the next two free numbers in order',
    () async {
      final root = await _project(drop: _scenarios(4));
      final answer = _move(root, ['$_addItem#S3', '$_addItem#S2']);
      expect(
        _bodyOf(root, cartDrop),
        _storyBody('Agent drops an item', [
          ..._scenarios(4),
          _scenario(3).replaceFirst('### Scenario 3', '### Scenario 5'),
          _scenario(2).replaceFirst('### Scenario 2', '### Scenario 6'),
        ]),
      );
      expect(
        answer.text,
        startsWith(
          'moved $cartAdd#S3 to $cartDrop#S5\n'
          'moved $cartAdd#S2 to $cartDrop#S6\n'
          'renumbered $cartDrop S3 to S5\n'
          'renumbered $cartDrop S2 to S6\n',
        ),
      );
    },
  );

  test('a dry run prints moves and renumbers and writes nothing', () async {
    final root = await _project();
    final before = _docs(root);
    final answer = _move(root, ['$_addItem#S2'], dryRun: true);
    expect(
      answer.text,
      'moves $cartAdd#S2 to $cartDrop#S3\n'
      'renumbers $cartDrop S2 to S3\n'
      'rewrites $cartAdd\n'
      'rewrites $cartDrop\n'
      'dry run: nothing moved\n',
    );
    expect(answer.json['dryRun'], isTrue);
    expect(_docs(root), before);
    expect(
      File('${root.path}/${MoveJournal.journalPath}').existsSync(),
      isFalse,
      reason: 'a dry run writes no journal',
    );
  });

  test('a code target leaves the move as without one', () async {
    final root = await _project(
      without: {
        'docs/$shopDomain',
        'docs/$cartDomain',
        'docs/$shopArchitecture',
        'docs/$shopApi',
      },
      extra: {
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  app:\n    code_root: app_lib\n'
            '  server:\n    code_root: server_lib\n',
        'app_lib/.keep': '',
        'server_lib/.keep': '',
      },
    );
    final answer = _move(root, ['$_addItem#S2'], codeTarget: 'server');
    expect(
      answer.text,
      'moved $cartAdd#S2 to $cartDrop#S3\n'
      'renumbered $cartDrop S2 to S3\n'
      'rewrote $cartAdd\n'
      'rewrote $cartDrop\n',
    );
  });

  test(
    'a scenario lands at the end of the section, after a closing paragraph',
    () async {
      const closing = 'Error cases: N/A — dropping an item always succeeds.';
      final root = await _project(dropClosing: closing);
      _move(root, ['$_addItem#S3']);
      expect(
        _bodyOf(root, cartDrop),
        _storyBody('Agent drops an item', [
          ..._scenarios(2),
          closing,
          _scenario(3),
        ]),
      );
    },
  );

  test(
    'a moved last scenario carries the paragraph that closes its block',
    () async {
      const closing = 'Error cases: N/A — adding an item always succeeds.';
      final root = await _project(addClosing: closing);
      _move(root, ['$_addItem#S3']);
      expect(
        _bodyOf(root, cartAdd),
        _storyBody('Agent adds an item', _scenarios(2)),
      );
      expect(
        _bodyOf(root, cartDrop),
        _storyBody('Agent drops an item', [
          ..._scenarios(2),
          _scenario(3),
        ], closing: closing),
      );
    },
  );

  test('a confirmed trace of the moved scenario and of its new neighbour stays clean', () async {
    const closing = 'Error cases: N/A — dropping an item always succeeds.';
    const frPath =
        'prds/features/f02_shop/f01_cart/us02_drop_item/fr01_keep_cart.md';
    final neighbour = '${_scenario(2)}\n\n$closing';
    final root = await _project(
      add: _scenarios(4),
      dropClosing: closing,
      extra: {
        'docs/$frPath':
            '---\ntraced_from:\n  - S2\n  - S4\nverify_method: test\n'
            'confirmed:\n  - S2 ${fingerprintFor(neighbour)}\n'
            '  - S4 ${fingerprintFor(_scenario(4))}\n---\n\n'
            '# Keep the cart\n\n## Statement\nThe system shall keep the cart.\n\n'
            '## Edge cases\n1. E01 — An empty cart → kept.\n\n'
            '## Rationale\nCarts matter.\n\n'
            '## Verification\nTest: a cart is kept.\n',
      },
    );
    _move(root, ['$_addItem#S4']);
    final findings = checkOf(root, docPath: frPath).findings;
    expect([
      for (final finding in findings)
        if (finding.kind == FindingKind.suspect) finding.toJson(),
    ], isEmpty);
  });

  group('references', () {
    test("a source-story fr's bare trace and confirmed entry name the target story and new number, the landed fingerprint stamped, no draft", () async {
      final root = await _citedProject();
      _move(root, ['$_addItem#S2']);
      final text = readDoc(root, cartAddFr);
      expect(
        text,
        contains(
          _list('traced_from', [
            'S1',
            'shop/cart/drop_item#S3',
            'shop/cart/add_item#S3',
          ]),
        ),
      );
      expect(
        text,
        contains(
          _list('confirmed', [
            'S1 $_fp1',
            'shop/cart/drop_item#S3 $_fp2Landed',
          ]),
        ),
      );
      expect(text, isNot(contains('draft: true')));
    });

    test("a target-story fr's entry naming the source scenario turns bare with the new number", () async {
      final root = await _citedProject();
      _move(root, ['$_addItem#S2']);
      final text = readDoc(root, _dropFr);
      expect(text, contains(_list('traced_from', ['S2', 'S3'])));
      expect(
        text,
        contains(_list('confirmed', ['S2 $_fp2', 'S3 $_fp2Landed'])),
      );
    });

    test('every confirmed entry that matched the moved scenario checks clean after a renumbering move', () async {
      final root = await _citedProject();
      final traced = [cartAddFr, _dropFr, _payFr, _journey];
      for (final docPath in traced) {
        expect(_suspects(root, docPath), isEmpty, reason: 'before: $docPath');
      }
      _move(root, ['$_addItem#S2']);
      for (final docPath in traced) {
        expect(_suspects(root, docPath), isEmpty, reason: 'after: $docPath');
      }
    });

    test(
      'an entry stale before the move keeps its fingerprint and stays suspect',
      () async {
        final root = await _project(
          extra: {
            'docs/$cartAddFr': _fr(
              'check the stock',
              ['S1', 'S2'],
              ['S1 $_fp1', 'S2 $_stale'],
            ),
          },
        );
        expect(_suspects(root, cartAddFr), hasLength(1));
        _move(root, ['$_addItem#S2']);
        expect(
          readDoc(root, cartAddFr),
          contains(
            _list('confirmed', ['S1 $_fp1', 'shop/cart/drop_item#S3 $_stale']),
          ),
        );
        final suspects = _suspects(root, cartAddFr);
        expect(suspects, hasLength(1));
        expect(suspects.single['link'], 'shop/cart/drop_item#S3');
        expect(suspects.single['recorded'], _stale);
      },
    );

    test('a dry run of a renumbering move stamps no fingerprint', () async {
      final root = await _citedProject();
      final before = _docs(root);
      _move(root, ['$_addItem#S2'], dryRun: true);
      expect(_docs(root), before);
    });

    test('check and move end a scenario at one line: a ###x line stays inside, a bare ### line and a quoted ### line end it', () async {
      for (final (line, ends) in [
        ('###x is no heading', false),
        ('###', true),
        ('> ### a quoted aside', true),
      ]) {
        final tail = '$line\n\n- **Note** after it';
        final block = ends ? _scenario(2) : '${_scenario(2)}\n\n$tail';
        final root = await _project(
          add: [_scenario(1), '${_scenario(2)}\n\n$tail', _scenario(3)],
          extra: {
            'docs/$cartAddFr': _fr(
              'check the stock',
              ['S2'],
              ['S2 ${fingerprintFor(block)}'],
            ),
          },
        );
        expect(_suspects(root, cartAddFr), isEmpty, reason: 'before: $line');
        _move(root, ['$_addItem#S2']);
        expect(
          _bodyOf(root, cartDrop),
          _storyBody('Agent drops an item', [
            ..._scenarios(2),
            block.replaceFirst('### Scenario 2', '### Scenario 3'),
          ]),
          reason: line,
        );
        expect(
          _bodyOf(root, cartAdd),
          _storyBody('Agent adds an item', [
            _scenario(1),
            if (ends) tail,
            _scenario(3),
          ]),
          reason: line,
        );
        expect(_suspects(root, cartAddFr), isEmpty, reason: 'after: $line');
      }
    });

    test(
      "another story's fr entry names the target story and new number",
      () async {
        final root = await _citedProject();
        _move(root, ['$_addItem#S2']);
        final text = readDoc(root, _payFr);
        expect(
          text,
          contains(
            _list('traced_from', [
              'S1',
              'shop/cart/drop_item#S3',
              'shop/cart/add_item#S1',
            ]),
          ),
        );
        expect(
          text,
          contains(_list('confirmed', ['shop/cart/drop_item#S3 $_fp2Landed'])),
        );
      },
    );

    test('an entry naming a scenario that stays keeps its text', () async {
      final root = await _citedProject();
      final before = readDoc(root, _payFr);
      _move(root, ['$_addItem#S3']);
      expect(readDoc(root, _payFr), before);
      expect(
        readDoc(root, _dropFr),
        contains(_list('traced_from', ['S2', 'cart/add_item#S02'])),
      );
      expect(
        readDoc(root, cartAddFr),
        contains(_list('traced_from', ['S1', 'S2', 'shop/cart/drop_item#S3'])),
      );
      expect(
        readDoc(root, cartAddFr),
        contains(_list('confirmed', ['S1 $_fp1', 'S2 $_fp2'])),
      );
    });

    test(
      'a journey step and its confirmed entry name the new story and number',
      () async {
        final root = await _citedProject();
        _move(root, ['$_addItem#S2']);
        final text = readDoc(root, _journey);
        expect(
          text,
          contains(
            _list('confirmed', [
              'shop/cart/add_item#S1 $_fp1',
              'shop/cart/drop_item#S3 $_fp2Landed',
            ]),
          ),
        );
        expect(text, contains('step: shop/cart/add_item S1\n'));
        expect(text, contains('step: shop/cart/drop_item S3\nafter: 1\n'));
      },
    );

    test("a heading-anchor link reaches the target story at the new heading's anchor", () async {
      final root = await _citedProject();
      _move(root, ['$_addItem#S2']);
      expect(
        readDoc(root, cartDomain),
        contains(
          '- **INV-2** As [Scenario 2]($_toDropItem/USER_STORY.md#scenario-3--edge-case-2) gives.\n',
        ),
      );
    });

    test('a heading-anchor link in reference style, in angle brackets, or with a query reaches the new heading', () async {
      final root = await _citedProject();
      _move(root, ['$_addItem#S2']);
      final text = readDoc(root, cartDomain);
      for (final line in [
        '- **INV-6** As [Scenario 2][s2] gives.\n',
        '- **INV-7** As [Scenario 2](<$_toDropItem/USER_STORY.md#scenario-3--edge-case-2>) gives.\n',
        '- **INV-8** As [Scenario 2]($_toDropItem/USER_STORY.md?v=1#scenario-3--edge-case-2) gives.\n',
        '[s2]: $_toDropItem/USER_STORY.md#scenario-3--edge-case-2\n',
      ]) {
        expect(text, contains(line));
      }
    });

    test('a reference-style heading link carried with its scenario reaches the landed heading', () async {
      final root = await _project(
        add: [
          _scenario(1),
          _scenario(
            2,
          ).replaceFirst('sees case 2', 'sees case 2, as [here][self] gives'),
          _scenario(3),
        ],
        addClosing: '[self]: #scenario-2--edge-case-2',
      );
      _move(root, ['$_addItem#S2']);
      expect(
        readDoc(root, cartDrop),
        contains('as [here](#scenario-3--edge-case-2) gives'),
      );
    });

    test('a definition a staying link and a moved link share reaches the landed heading from both', () async {
      final root = await _project(
        add: [
          _scenario(1),
          _scenario(
            2,
          ).replaceFirst('sees case 2', 'sees case 2, as [here][self] gives'),
          _scenario(3),
        ],
        addClosing: 'See [there][self].\n\n[self]: #scenario-2--edge-case-2',
      );
      _move(root, ['$_addItem#S2']);
      expect(
        readDoc(root, cartDrop),
        contains('as [here](#scenario-3--edge-case-2) gives'),
      );
      final add = readDoc(root, cartAdd);
      expect(add, contains('See [there][self].\n'));
      expect(
        add,
        contains(
          '[self]: ../us02_drop_item/USER_STORY.md#scenario-3--edge-case-2\n',
        ),
      );
    });

    test("another reference form follows as an item's does", () async {
      final root = await _citedProject();
      _move(root, ['$_addItem#S2']);
      final text = readDoc(root, cartDomain);
      expect(
        text,
        contains(
          '- **INV-3** As [S3]($_toDropItem/USER_STORY.md#acceptance-criteria) gives.\n',
        ),
      );
      expect(
        text,
        contains(
          '- **INV-4** As [S1]($_toAddItem/USER_STORY.md#acceptance-criteria), '
          '[S3]($_toDropItem/USER_STORY.md#acceptance-criteria), '
          '[S3]($_toAddItem/USER_STORY.md#acceptance-criteria) give.\n',
        ),
      );
    });

    test('a bare S number outside a link is kept and prints one mentions line', () async {
      final root = await _citedProject();
      final answer = _move(root, ['$_addItem#S2']);
      final mentions = [
        for (final line in answer.text.split('\n'))
          if (line.startsWith('mentions ')) line,
      ];
      expect(mentions, hasLength(2));
      for (final (docPath, mention) in [
        (cartAdd, 'S2'),
        (cartDomain, 'shop/cart/add_item#S2'),
      ]) {
        final match = RegExp(
          '^mentions ${RegExp.escape(docPath)}:([0-9]+) ${RegExp.escape(mention)}\$',
        );
        final line = mentions.where(match.hasMatch).single;
        final number = int.parse(match.firstMatch(line)!.group(1)!);
        expect(
          readDoc(root, docPath).split('\n')[number - 1],
          contains(mention),
          reason: line,
        );
      }
      expect(readDoc(root, cartAdd), contains('Error cases: see S2.\n'));
    });

    test('a bare S number inside a landed scenario that names a co-moved renumbered scenario prints a mentions line', () async {
      final root = await _project(
        add: [
          _scenario(1),
          _scenario(2).replaceFirst('sees case 2', 'sees case 2, as S3 gives'),
          _scenario(3),
        ],
      );
      final answer = _move(root, ['$_addItem#S2', '$_addItem#S3']);
      final match = RegExp(
        '^mentions ${RegExp.escape(cartDrop)}:([0-9]+) S3\$',
        multiLine: true,
      ).firstMatch(answer.text);
      expect(match, isNotNull, reason: answer.text);
      expect(
        readDoc(root, cartDrop).split('\n')[int.parse(match!.group(1)!) - 1],
        contains('as S3 gives'),
      );
    });

    test(
      'only the two stories gain a draft mark among the rewritten docs',
      () async {
        final root = await _citedProject();
        final others = [cartAddFr, _dropFr, _payFr, _journey, cartDomain];
        String? approvedOf(String docPath) => RegExp(
          r'^approved: "([^"]+)"$',
          multiLine: true,
        ).firstMatch(readDoc(root, docPath))?.group(1);
        final before = {
          for (final docPath in others) docPath: approvedOf(docPath),
        };
        final answer = _move(root, ['$_addItem#S2']);
        final rewritten = [...answer.json['rewritten']! as List<Object?>];
        expect(rewritten, containsAll([cartAdd, cartDrop, ...others]));
        for (final docPath in rewritten.cast<String>()) {
          final isStory = docPath == cartAdd || docPath == cartDrop;
          expect(
            readDoc(root, docPath).contains('draft: true\n'),
            isStory,
            reason: docPath,
          );
        }
        for (final docPath in others) {
          final approved = approvedOf(docPath);
          expect(before[docPath], isNotNull, reason: docPath);
          expect(approved, isNot(before[docPath]), reason: docPath);
          expect(
            [
              for (final finding in checkOf(root, docPath: docPath).findings)
                finding.kind,
            ],
            isNot(contains(FindingKind.approvalStale)),
            reason: docPath,
          );
        }
      },
    );
  });
}
