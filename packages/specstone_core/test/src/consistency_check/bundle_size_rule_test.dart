import 'dart:io';

import 'package:specstone_core/src/consistency_check/bundle_size_rule.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/skill_doc_fixture.dart';

/// Letters that put a story or doc over the bound by a margin of 2,000 est.
/// tokens (characters / 4).
const int _overBound = (readRangeTokenLimit + 2000) * 4;

const _otherStory = 'prds/features/f01_login/us02_reset_password/USER_STORY.md';
const _emptyFeature = 'prds/features/f03_empty/FEATURE.md';

/// Returns a story whose Acceptance Criteria hold [criteria] letters.
String _storyText(int criteria) =>
    '---\ngoals:\n  - PG-01\n---\n\n# Agent resets a password\n\n'
    '## Use Case\n\n- **As a** Agent who resets\n- **I want to** reset\n'
    '- **so that** I sign in again\n\n'
    '## Acceptance Criteria\n\n${'a' * criteria}\n';

/// Returns the files of a login feature with two stories and an empty feature
/// beside it, each padded by the given number of letters.
Map<String, String> _padded({
  int story = 0,
  int otherStory = 0,
  int empty = 0,
}) => {
  ...edit(loginStory, [
    (
      '## Acceptance Criteria\n\n',
      '## Acceptance Criteria\n\n${'a' * story}\n\n',
    ),
  ]),
  'docs/$_otherStory': _storyText(otherStory),
  'docs/$_emptyFeature': '# Empty\n\n## Problem\n\n${'a' * empty}\n',
};

/// Returns the nested project's files with [letters] added to the Problem of
/// the feature `shop`, which holds sub-features and no story.
Map<String, String> _bigShop(int letters) => {
  'docs/$shopFeature': nestedFiles()['docs/$shopFeature']!.replaceFirst(
    '## Problem\n',
    '## Problem\n${'a' * letters}\n',
  ),
};

List<String> _filesUnder(Directory project) => [
  for (final entity in project.listSync(recursive: true))
    if (entity is File) entity.path,
];

const _toDomain = '../../../../../specs/f02_shop/DOMAIN.md';

/// Returns the nested project's files where the story `shop/cart/drop_item`
/// cites the invariant INV-2 of the parent domain doc and the story
/// `shop/cart/add_item` cites INV-3, each of [linked] letters, while INV-9
/// holds [unlinked] letters and no doc of the subtree cites it.
Map<String, String> _citedInvariants({
  required int linked,
  required int unlinked,
}) => {
  'docs/$cartDrop':
      '# Agent drops an item\n\n## Use Case\n'
      'Drops [INV-2]($_toDomain#invariants).\n',
  'docs/$cartAdd':
      '# Agent adds an item\n\n## Use Case\n'
      'Adds [INV-3]($_toDomain#invariants).\n',
  'docs/$cartAddFr': '# Check the stock\n\n## Statement\nRefuses.\n',
  'docs/$shopApi': '# Shop API\n\n## Operations\nNone.\n',
  'docs/$shopDomain':
      '# Shop domain\n\n## Invariants\n'
      '- **INV-1** An order holds a line.\n'
      '- **INV-2** ${'a' * linked}\n'
      '- **INV-3** ${'b' * linked}\n'
      '- **INV-9** ${'c' * unlinked}\n',
};

/// Returns the domain doc of the sub-feature `shop/cart`, a must part of its
/// own file alone, over the bound.
Map<String, String> _bigCartDomain() => {
  'docs/$cartDomain': '# Cart domain\n\n## Entities\n${'a' * _overBound}\n',
};

Future<Directory> _writeCitedInvariants({
  required int linked,
  required int unlinked,
  Map<String, String> extra = const {},
}) {
  final files = _citedInvariants(linked: linked, unlinked: unlinked);
  return writeCheckProject(
    extra: {...nestedFiles(), ...files, ...extra},
    unstamped: {...files.keys, ...extra.keys},
  );
}

ContextAnswer _answerOf(DocIndex index, String name, {required bool summary}) =>
    answerContext(
      index,
      pickBundle(
        index,
        [name],
        BundleMode.design,
        noProject: false,
        summary: summary,
      ),
      targets: [name],
      split: true,
    );

/// Returns the size `context <name> --for design --out` prints in its header.
int _headerSizeOf(
  ReadSession session,
  Directory project,
  String name, {
  required bool summary,
}) {
  final reply = answerBundleFile(
    _answerOf(session.index, name, summary: summary),
    File('${project.path}/out/${name.replaceAll('/', '_')}.txt'),
    project: session.project,
    isBare: false,
  );
  final header = RegExp(r'==> bundle: \d+ docs, (\d+) tokens, ');
  return int.parse(header.firstMatch(reply.text)!.group(1)!);
}

List<Finding> _sizeFindings(ReadSession session, String docPath) => [
  ...checkBundleSize(CheckContext(session), session.index.at(docPath)!),
];

/// Returns the letters of Acceptance Criteria that make the story file of
/// `login/email_login` hold exactly [target] est. tokens.
Future<int> _criteriaFor(int target) async {
  var chars = target * 4;
  for (var attempt = 0; attempt < 6; attempt++) {
    final session = openSession(
      await writeCheckProject(extra: _padded(story: chars)),
    );
    final size = _answerOf(
      session.index,
      'login/email_login',
      summary: false,
    ).readFirst.tokens;
    session.close();
    if (size == target) return chars;
    chars += (target - size) * 4;
  }
  throw StateError('no padding gives exactly $target tokens');
}

/// Returns the nested project where an agent doc of [joined] letters names the
/// feature `shop/cart` in its `feature` field, and the story `shop/cart/add_item`
/// holds [story] letters of Acceptance Criteria.
Map<String, String> _withJoinedAgent({
  required int story,
  required int joined,
}) => {
  '.specstone/config.yaml': skillPinsConfig(),
  'docs/$agentDoc':
      '---\nfeature:\n  - shop/cart\n---\n\n# reviewer\n\n'
      '## Role\n\n${'a' * joined}\n',
  'docs/$cartAdd': nestedFiles()['docs/$cartAdd']!.replaceFirst(
    '## Acceptance Criteria\n',
    '## Acceptance Criteria\n${'b' * story}\n',
  ),
};

/// Returns the story letters that leave `shop/cart/add_item` at [target] est.
/// tokens before any join.
Future<int> _storyLettersFor(int target) async {
  final session = openSession(
    await writeNestedProject(extra: _withJoinedAgent(story: 0, joined: 0)),
  );
  addTearDown(session.close);
  final base = _answerOf(
    session.index,
    'shop/cart/add_item',
    summary: false,
  ).readFirst.tokens;
  return (target - base) * 4;
}

/// Expects [readFirstOverLimitOf] to give [readFirstTokensOf] for each design
/// file [checkBundleSize] sizes in [index] that passes the limit, else null;
/// returns how many passed it.
int _expectOverLimitSizes(DocIndex index) {
  final nesting = index.set.nestingType!;
  var over = 0;
  for (final feature in index.docs.where((d) => d.docTypeId == nesting.id)) {
    final children = index.childrenOf(feature);
    for (final (doc, summary) in [
      (feature, children.isNotEmpty),
      for (final story in children)
        if (index.isChainDoc(story) && story.docTypeId != nesting.id)
          (story, false),
    ]) {
      final bundle = pickBundle(
        index,
        [doc.docPath],
        BundleMode.design,
        noProject: false,
        summary: summary,
      );
      final tokens = readFirstTokensOf(index, bundle);
      final isOver = tokens > readRangeTokenLimit;
      if (isOver) over++;
      expect(
        readFirstOverLimitOf(index, bundle),
        isOver ? tokens : null,
        reason: doc.docPath,
      );
    }
  }
  return over;
}

void main() {
  test('the over-limit size is the read-first size past the limit, else '
      'none', () async {
    final projects = [
      await writeNestedProject(extra: _bigShop(_overBound)),
      await writeNestedProject(
        extra: _withJoinedAgent(
          story: await _storyLettersFor(readRangeTokenLimit - 2000),
          joined: 3257 * 4,
        ),
      ),
      await writeNestedProject(
        extra: _withJoinedAgent(
          story: await _storyLettersFor(22000),
          joined: 3257 * 4,
        ),
      ),
      await _writeCitedInvariants(
        linked: _overBound ~/ 2,
        unlinked: _overBound * 4,
      ),
      await _writeCitedInvariants(
        linked: 400,
        unlinked: 1000,
        extra: _bigCartDomain(),
      ),
    ];
    var over = 0;
    for (final project in projects) {
      final session = openSession(project);
      addTearDown(session.close);
      over += _expectOverLimitSizes(session.index);
    }
    expect(over, greaterThanOrEqualTo(3));
  });

  group('checkBundleSize', () {
    test('a feature over the bound gets one finding on line 1, waiting for the '
        'Owner', () async {
      final session = openSession(
        await writeNestedProject(extra: _bigShop(_overBound)),
      );
      addTearDown(session.close);

      final found = _sizeFindings(session, shopFeature);

      final actual = _answerOf(
        session.index,
        'shop',
        summary: true,
      ).readFirst.tokens;
      expect(actual, greaterThan(readRangeTokenLimit));
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.bundleOverLimit);
      expect(found.single.path, shopFeature);
      expect(found.single.line, 1);
      expect(found.single.waitsFor, WaitsFor.owner);
      expect(found.single.toJson(), {
        'kind': 'bundle_over_limit',
        'path': shopFeature,
        'name': 'shop',
        'line': 1,
        'message':
            'the design read-first file of feature:shop holds $actual est. '
            'tokens; the limit is 20000',
        'waitsFor': 'owner',
        'doc': 'feature:shop',
        'limit': 20000,
        'actual': actual,
      });
    });

    test("a bundle_over_limit finding names the largest file's doc by its "
        'address', () async {
      final story = openSession(
        await writeNestedProject(
          extra: {
            'docs/$cartAdd': nestedFiles()['docs/$cartAdd']!.replaceFirst(
              '## Acceptance Criteria\n',
              '## Acceptance Criteria\n${'a' * _overBound}\n',
            ),
          },
        ),
      );
      addTearDown(story.close);
      final feature = openSession(
        await writeNestedProject(extra: _bigShop(_overBound)),
      );
      addTearDown(feature.close);

      final byStory = _sizeFindings(story, cartFeature).single;
      final byFeature = _sizeFindings(feature, shopFeature).single;

      expect(byStory.keys['doc'], 'user_story:shop/cart/add_item');
      expect(byStory.message, contains('of user_story:shop/cart/add_item '));
      expect(byFeature.keys['doc'], 'feature:shop');
      expect(byFeature.message, contains('of feature:shop '));
    });

    test('one finding per feature, naming the largest file', () async {
      final session = openSession(
        await writeCheckProject(
          extra: _padded(story: _overBound, otherStory: _overBound + 40000),
        ),
      );
      addTearDown(session.close);

      final found = _sizeFindings(session, loginFeature);

      expect(found, hasLength(1));
      expect(found.single.keys['doc'], 'user_story:login/reset_password');
      expect(
        found.single.keys['actual'],
        _answerOf(
          session.index,
          'login/reset_password',
          summary: false,
        ).readFirst.tokens,
      );
      expect(_sizeFindings(session, loginStory), isEmpty);
    });

    test('exactly the bound gets none, and one more token gets one', () async {
      final chars = await _criteriaFor(readRangeTokenLimit);
      final exact = openSession(
        await writeCheckProject(extra: _padded(story: chars)),
      );
      addTearDown(exact.close);

      expect(_sizeFindings(exact, loginFeature), isEmpty);

      final over = openSession(
        await writeCheckProject(extra: _padded(story: chars + 4)),
      );
      addTearDown(over.close);
      final found = _sizeFindings(over, loginFeature).single;
      expect(found.keys['doc'], 'user_story:login/email_login');
      expect(found.keys['actual'], readRangeTokenLimit + 1);
    });

    test('the size equals the context --out header', () async {
      final withStory = await writeCheckProject(
        extra: _padded(story: _overBound, empty: _overBound),
      );
      final storySession = openSession(withStory);
      addTearDown(storySession.close);
      final story = _sizeFindings(storySession, loginFeature).single;
      final withNone = _sizeFindings(storySession, _emptyFeature).single;

      expect(story.keys['doc'], 'user_story:login/email_login');
      expect(
        story.keys['actual'],
        _headerSizeOf(
          storySession,
          withStory,
          'login/email_login',
          summary: false,
        ),
      );
      expect(withNone.keys['doc'], 'feature:empty');
      expect(
        withNone.keys['actual'],
        _headerSizeOf(storySession, withStory, 'empty', summary: false),
      );

      final nested = await writeNestedProject(extra: _bigShop(_overBound));
      final nestedSession = openSession(nested);
      addTearDown(nestedSession.close);
      expect(
        _sizeFindings(nestedSession, shopFeature).single.keys['actual'],
        _headerSizeOf(nestedSession, nested, 'shop', summary: true),
      );

      final cited = await _writeCitedInvariants(
        linked: 400,
        unlinked: 1000,
        extra: _bigCartDomain(),
      );
      final citedSession = openSession(cited);
      addTearDown(citedSession.close);
      final citing = _sizeFindings(citedSession, cartFeature).single;
      expect(citing.keys['doc'], 'feature:shop/cart');
      expect(
        citing.keys['actual'],
        _headerSizeOf(citedSession, cited, 'shop/cart', summary: true),
      );
    });

    test(
      'joined docs move to refs and leave a story within the limit',
      () async {
        final session = openSession(
          await writeNestedProject(
            extra: _withJoinedAgent(
              story: await _storyLettersFor(readRangeTokenLimit - 2000),
              joined: 3257 * 4,
            ),
          ),
        );
        addTearDown(session.close);

        expect(_sizeFindings(session, cartFeature), isEmpty);
        final answer = _answerOf(
          session.index,
          'shop/cart/add_item',
          summary: false,
        );
        expect(answer.text, isNot(contains('==> reviewer (agent) · ')));
        expect(answer.refs!.text, contains('==> reviewer (agent) · '));
      },
    );

    test(
      'bundle_over_limit fires only for an over-budget target set',
      () async {
        const mustTokens = 22000;
        final letters = await _storyLettersFor(mustTokens);
        final alone = openSession(
          await writeNestedProject(
            extra: _withJoinedAgent(story: letters, joined: 0),
          ),
        );
        addTearDown(alone.close);
        final withJoined = await writeNestedProject(
          extra: _withJoinedAgent(story: letters, joined: 3257 * 4),
        );
        final session = openSession(withJoined);
        addTearDown(session.close);

        final found = _sizeFindings(session, cartFeature).single;

        expect(found.keys['doc'], 'user_story:shop/cart/add_item');
        expect(
          found.keys['actual'],
          _answerOf(
            alone.index,
            'shop/cart/add_item',
            summary: false,
          ).readFirst.tokens,
        );
        expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
        expect(
          found.keys['actual'],
          _headerSizeOf(
            session,
            withJoined,
            'shop/cart/add_item',
            summary: false,
          ),
        );
      },
    );

    test(
      'the size is taken with no doc file read and no file written',
      () async {
        final project = await writeNestedProject(extra: _bigShop(_overBound));
        final session = openSession(project);
        addTearDown(session.close);
        final before = _sizeFindings(session, shopFeature).single.toJson();
        final files = _filesUnder(project);
        final docs = Directory('${project.path}/docs');
        final underDocs =
            '${project.path}${Platform.pathSeparator}docs'
            '${Platform.pathSeparator}';

        docs.deleteSync(recursive: true);
        final after = _sizeFindings(session, shopFeature).single.toJson();

        expect(after, before);
        expect(
          _filesUnder(project).toSet(),
          files.where((path) => !path.startsWith(underDocs)).toSet(),
        );
      },
    );

    test('a story file over the bound names the story as doc', () async {
      final project = await writeNestedProject(
        extra: {
          'docs/$cartAdd': nestedFiles()['docs/$cartAdd']!.replaceFirst(
            '## Acceptance Criteria\n',
            '## Acceptance Criteria\n${'a' * _overBound}\n',
          ),
        },
      );
      final session = openSession(project);
      addTearDown(session.close);

      final found = _sizeFindings(session, cartFeature).single;

      expect(found.path, cartFeature);
      expect(found.keys['doc'], 'user_story:shop/cart/add_item');
      expect(
        found.keys['actual'],
        _headerSizeOf(session, project, 'shop/cart/add_item', summary: false),
      );
      expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
      expect(
        _answerOf(session.index, 'shop/cart', summary: true).readFirst.tokens,
        lessThanOrEqualTo(readRangeTokenLimit),
      );
    });

    test('a sub-feature whose pieces of the parent spec docs pass the bound '
        'moves them and gets no finding', () async {
      final project = await _writeCitedInvariants(
        linked: _overBound ~/ 2,
        unlinked: _overBound * 4,
      );
      final session = openSession(project);
      addTearDown(session.close);

      expect(_sizeFindings(session, cartFeature), isEmpty);
      expect(
        _headerSizeOf(session, project, 'shop/cart', summary: true),
        lessThanOrEqualTo(readRangeTokenLimit),
      );
    });

    test('an ancestor spec doc no link of the subtree cites adds nothing to '
        'the size', () async {
      final session = openSession(
        await _writeCitedInvariants(linked: 400, unlinked: _overBound * 4),
      );
      addTearDown(session.close);

      expect(_sizeFindings(session, cartFeature), isEmpty);
    });

    test('a feature whose children are sub-features keeps the finding, its fix '
        'no story split but moves of the items one sub-feature uses', () async {
      final project = await writeNestedProject(extra: _bigShop(_overBound));
      final session = openSession(project);
      addTearDown(session.close);
      final shop = session.index.at(shopFeature)!;
      final children = session.index.childrenOf(shop);
      expect(children.map((c) => c.docTypeId), isNot(contains('user_story')));
      expect(
        children.map((c) => c.docPath),
        containsAll([cartFeature, payFeature]),
      );

      final found = _sizeFindings(session, shopFeature).single;

      expect(found.waitsFor, WaitsFor.owner);
      expect(found.keys, {
        'doc': 'feature:shop',
        'limit': 20000,
        'actual': _headerSizeOf(session, project, 'shop', summary: true),
      });
      expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
    });

    test('a sub-feature over the bound is its own finding, its fix a split of '
        'its stories', () async {
      final project = await _writeCitedInvariants(
        linked: 400,
        unlinked: 1000,
        extra: {
          ..._bigCartDomain(),
          for (final slug in ['edit_item', 'move_item'])
            'docs/prds/features/f02_shop/f01_cart/us03_$slug/USER_STORY.md':
                nestedFiles()['docs/$cartAdd']!,
        },
      );
      final session = openSession(project);
      addTearDown(session.close);
      final cartDoc = session.index.at(cartFeature)!;
      expect(
        session.index.childrenOf(cartDoc).where(session.index.isChainDoc),
        hasLength(4),
      );

      final found = _sizeFindings(session, cartFeature).single;
      final actual = _headerSizeOf(
        session,
        project,
        'shop/cart',
        summary: true,
      );

      expect(found.path, cartFeature);
      expect(found.waitsFor, WaitsFor.owner);
      expect(found.keys, {
        'doc': 'feature:shop/cart',
        'limit': 20000,
        'actual': actual,
      });
      expect(actual, greaterThan(readRangeTokenLimit));
    });

    test('a feature at the nesting depth limit keeps the finding with no '
        'split', () async {
      const express = 'prds/features/f02_shop/f01_cart/f01_express/FEATURE.md';
      const expressStory =
          'prds/features/f02_shop/f01_cart/f01_express/us01_rush/USER_STORY.md';
      final project = await _writeCitedInvariants(
        linked: 400,
        unlinked: 1000,
        extra: {
          'docs/$express': nestedFiles()['docs/$cartFeature']!,
          'docs/specs/f02_shop/f01_cart/f01_express/DOMAIN.md':
              '# Express domain\n\n## Entities\n${'a' * _overBound}\n',
          'docs/$expressStory': nestedFiles()['docs/$cartAdd']!,
        },
      );
      final session = openSession(project);
      addTearDown(session.close);

      final found = _sizeFindings(session, express).single;

      expect(found.keys['doc'], 'feature:shop/cart/express');
      expect(found.waitsFor, WaitsFor.owner);
      expect(found.keys.keys, unorderedEquals(['doc', 'limit', 'actual']));
      expect(
        found.keys['actual'],
        _headerSizeOf(session, project, 'shop/cart/express', summary: true),
      );
      expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
      expect(
        session.index
            .childrenOf(session.index.at(express)!)
            .where(session.index.isChainDoc),
        hasLength(1),
      );
    });

    test('an FR, NFR, or spec doc gets no size', () async {
      final session = openSession(
        await writeCheckProject(
          extra: edit(loginFr, [
            ('## Rationale\n\n', '## Rationale\n\n${'a' * _overBound}\n\n'),
          ]),
        ),
      );
      addTearDown(session.close);

      for (final docPath in [
        loginFr,
        loginNf,
        loginArchitecture,
        loginApi,
        techStack,
        projectDoc,
      ]) {
        expect(_sizeFindings(session, docPath), isEmpty, reason: docPath);
      }
    });
  });
}
