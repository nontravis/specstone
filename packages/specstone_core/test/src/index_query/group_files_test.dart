// The test titles are row and edge case names kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/group_files.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show tokenSizeOf;
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/index_query/work_groups.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/target_fixture.dart';

/// Returns a story of about [tokens] est. tokens; [use] opens its use case.
String _paddedStory(String title, int tokens, {String use = ''}) =>
    '# $title\n\n## Use Case\n$use${'Pad words. ' * (tokens * 4 ~/ 11)}\n';

const _addItemToCard = 'Then [pay](../../f02_pay/us01_card/USER_STORY.md). ';
const _cardToAddItem =
    'Pay for the [added item](../../f01_cart/us01_add_item/USER_STORY.md). ';
const _cardToCheckStock =
    'Pay once the [stock](../../f01_cart/us01_add_item/fr01_check_stock.md) holds. ';

/// The three stories of about 20,000 est. tokens each, so `add_item` and
/// `drop_item` fill group 1 and `card` opens group 2.
Map<String, String> _largeStories({
  String addItemUse = '',
  String cardUse = '',
}) => {
  'docs/$cartAdd': _paddedStory('Agent adds an item', 20000, use: addItemUse),
  'docs/$cartDrop': _paddedStory('Agent drops an item', 20000),
  'docs/$payCard': _paddedStory('Agent pays by card', 20000, use: cardUse),
};

const _largeTargets = [
  'shop/pay/card',
  'shop/cart/add_item',
  'shop/cart/drop_item',
];

ReadSession _sessionOf(Directory project) {
  final session = openSession(project);
  addTearDown(session.close);
  return session;
}

/// Writes the group files of [targets] and returns the reply.
ReadAnswer _groupFiles(
  ReadSession session,
  List<String> targets, {
  BundleMode mode = BundleMode.implement,
  String? codeTarget,
  String? outPath,
}) => answerGroupFiles(
  session.index,
  pickWorkGroups(
    session.index,
    targets,
    mode,
    noProject: false,
    codeTarget: codeTarget,
  ),
  project: session.project,
  outPath: outPath,
);

/// Returns the bare read-first file of group [group] of [targets].
File _readFirstOf(Directory project, List<String> targets, int group) => File(
  '${project.path}/.specstone/bundles/${bundleFileName(targets: targets, mode: BundleMode.implement, summary: false, noProject: false, group: group)}',
);

/// Returns the `Cross-group links:` part that ends [text], after its doc list.
List<String> _crossGroupPartOf(String text) {
  final lines = const LineSplitter().convert(text);
  return lines.sublist(
    lines.lastIndexWhere((line) => line.startsWith('Cross-group links:')),
  );
}

void main() {
  test("E01: a group with no index link to another group's work units ends its read-first file with Cross-group links: none", () async {
    final project = await writeNestedProject(extra: _largeStories());
    _groupFiles(_sessionOf(project), _largeTargets);
    for (final group in [1, 2]) {
      final text = _readFirstOf(
        project,
        _largeTargets,
        group,
      ).readAsStringSync();
      expect(text, endsWith('\n\nCross-group links: none\n'), reason: '$group');
      final closing = const LineSplitter()
          .convert(text)
          .lastWhere((line) => line.startsWith('==> bundle: '));
      expect(closing, endsWith(' ${tokenSizeOf(text)} tokens <=='));
    }
  });

  test('cross-group line: two units joined both ways print one line in each group, naming the other group', () async {
    final project = await writeNestedProject(
      extra: _largeStories(addItemUse: _addItemToCard, cardUse: _cardToAddItem),
    );
    _groupFiles(_sessionOf(project), _largeTargets);
    final first = _readFirstOf(project, _largeTargets, 1).readAsStringSync();
    final second = _readFirstOf(project, _largeTargets, 2).readAsStringSync();
    expect(_crossGroupPartOf(first), [
      'Cross-group links:',
      '- user_story:shop/cart/add_item <-> user_story:shop/pay/card (group 2) · 1 links',
    ]);
    expect(_crossGroupPartOf(second), [
      'Cross-group links:',
      '- user_story:shop/pay/card <-> user_story:shop/cart/add_item (group 1) · 1 links',
    ]);
    final lines = const LineSplitter().convert(first);
    final partAt = lines.indexOf('Cross-group links:');
    expect(lines[partAt - 1], isEmpty);
    expect(lines[partAt - 2], startsWith('- '));
  });

  test('E02: two work units in two groups joined by several linked doc pairs print one line in each group, counting each pair once', () async {
    final checkStock = nestedFiles()['docs/$cartAddFr']!.replaceFirst(
      'Stock is finite.',
      'Stock is finite. See [card](../../f02_pay/us01_card/USER_STORY.md).',
    );
    final project = await writeNestedProject(
      extra: {
        ..._largeStories(cardUse: '$_cardToAddItem$_cardToCheckStock'),
        'docs/$cartAddFr': checkStock,
      },
    );
    _groupFiles(_sessionOf(project), _largeTargets);
    expect(
      _crossGroupPartOf(
        _readFirstOf(project, _largeTargets, 1).readAsStringSync(),
      ),
      [
        'Cross-group links:',
        '- user_story:shop/cart/add_item <-> user_story:shop/pay/card (group 2) · 2 links',
      ],
    );
    expect(
      _crossGroupPartOf(
        _readFirstOf(project, _largeTargets, 2).readAsStringSync(),
      ),
      [
        'Cross-group links:',
        '- user_story:shop/pay/card <-> user_story:shop/cart/add_item (group 1) · 2 links',
      ],
    );
  });

  test("E03: an index of every group past 200 lines or 8 KiB drops each doc line's sections; every group line, targets line, and read plan line still prints", () async {
    String fr(int n) =>
        '# Rule $n\n\n## Statement\nThe system shall keep rule $n.\n';
    String two(int n) => n.toString().padLeft(2, '0');
    final project = await writeNestedProject(
      extra: {
        'docs/$cartAdd': _paddedStory('Agent adds an item', 30000),
        'docs/$payCard': _paddedStory('Agent pays by card', 30000),
        for (var n = 2; n <= 71; n++)
          'docs/prds/features/f02_shop/f01_cart/us01_add_item/fr${two(n)}_rule_${two(n)}.md':
              fr(n),
        for (var n = 1; n <= 70; n++)
          'docs/prds/features/f02_shop/f02_pay/us01_card/fr${two(n)}_rule_${two(n)}.md':
              fr(n),
      },
    );
    final session = _sessionOf(project);
    const targets = ['shop/cart/add_item', 'shop/pay/card'];
    final pick = pickWorkGroups(
      session.index,
      targets,
      BundleMode.implement,
      noProject: false,
    );
    expect(pick.groups, hasLength(2));
    final alone = answerContext(
      session.index,
      pick.bundleOf(session.index, pick.groups.first),
      targets: pick.groups.first.targets,
      split: true,
    );
    final path = _readFirstOf(project, targets, 1).path;
    expect(
      bundleIndex(alone, path, refsPath: refsPathOf(path)),
      contains(' · statement '),
      reason: 'one group alone keeps its sections',
    );
    final reply = answerGroupFiles(
      session.index,
      pick,
      project: session.project,
    );
    final lines = const LineSplitter().convert(reply.text);
    expect(lines.where((line) => line.contains(' · statement ')), isEmpty);
    expect(lines.where((line) => line.startsWith('- ')), isNotEmpty);
    expect(lines, contains(startsWith('==> group 1 of 2: 1 units, ')));
    expect(lines, contains(startsWith('==> group 2 of 2: 1 units, ')));
    expect(
      lines,
      containsAll(['targets: shop/cart/add_item', 'targets: shop/pay/card']),
    );
    expect(
      lines.where((line) => line.startsWith('read whole, in ')),
      hasLength(4),
    );
  });

  test("file names: .g<k> follows the --target part of a bare name, and goes before an --out path's extension, or at its end, .refs after it", () async {
    final project = await writeTwinProject(
      extra: {
        'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md':
            _paddedStory('Agent resets a password', 30000),
        'docs/prds/features/f01_login/us03_sign_out/USER_STORY.md':
            _paddedStory('Agent signs out', 30000),
      },
    );
    final session = _sessionOf(project);
    const targets = ['login/reset_password', 'login/sign_out'];
    void groupFiles({String? outPath}) =>
        _groupFiles(session, targets, codeTarget: 'jaspr', outPath: outPath);
    bool exists(String path) => File('${project.path}/$path').existsSync();

    groupFiles();
    const bare =
        '.specstone/bundles/login-reset_password+login-sign_out.implement.jaspr';
    for (final suffix in [
      '.g1.txt',
      '.g1.refs.txt',
      '.g2.txt',
      '.g2.refs.txt',
    ]) {
      expect(exists('$bare$suffix'), isTrue, reason: suffix);
    }
    groupFiles(outPath: '${project.path}/out/work.txt');
    for (final name in [
      'work.g1.txt',
      'work.g1.refs.txt',
      'work.g2.txt',
      'work.g2.refs.txt',
    ]) {
      expect(exists('out/$name'), isTrue, reason: name);
    }
    groupFiles(outPath: '${project.path}/plain/work');
    for (final name in ['work.g1', 'work.g1.refs', 'work.g2', 'work.g2.refs']) {
      expect(exists('plain/$name'), isTrue, reason: name);
    }
  });

  test('cross-group links: the part counts in the read-first fill, so a tier part that fits only without it moves to refs and the file stays one read', () async {
    final index = await nestedIndexWith({
      'docs/$cartAdd': _paddedStory('Agent adds an item', 18500),
    });
    const targets = ['shop/cart/add_item'];
    ContextAnswer answerEnding(String end) => answerContext(
      index,
      pickBundle(index, targets, BundleMode.implement, noProject: false),
      targets: targets,
      split: true,
      readFirstEnd: end,
    );
    int movedOf(ContextAnswer answer) =>
        answer.refs!.entries.where((entry) => entry.moved).length;
    final without = answerEnding('');
    expect(without.tokens, lessThanOrEqualTo(readRangeTokenLimit));
    const line =
        '- user_story:shop/cart/add_item <-> user_story:shop/pay/card (group 2) · 1 links\n';
    final needed = (readRangeTokenLimit - without.tokens + 1) * 4;
    final part = '\nCross-group links:\n${line * (needed ~/ line.length + 1)}';
    final ending = answerEnding(part);
    expect(ending.text, endsWith(part));
    expect(movedOf(ending), greaterThan(movedOf(without)));
    expect(ending.tokens, lessThanOrEqualTo(readRangeTokenLimit));
    expect(ending.tokens, tokenSizeOf(ending.text));
    expect(readPlanOf(ending.readFirst).ranges, hasLength(1));
  });

  test('file names: a group name past 255 bytes is cut as one name, its --target and .g<k> parts after the hash', () {
    final first = 'a' * 150;
    final second = 'b' * 150;
    final name = bundleFileName(
      targets: [first, second],
      mode: BundleMode.implement,
      summary: false,
      noProject: false,
      codeTarget: 'jaspr',
      group: 2,
    );
    final uncut = '$first+$second.implement.jaspr.g2.txt';
    final hash = sha256.convert(utf8.encode(uncut)).toString().substring(0, 8);
    expect(utf8.encode(name).length, lessThanOrEqualTo(250));
    expect(name, endsWith('-$hash.implement.jaspr.g2.txt'));
    expect(name, startsWith('$first+b'));
  });
}
