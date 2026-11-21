import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/bundle_size_rule.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/setup_migration/agent_text.g.dart';
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

final String _sizeFix = utf8.decode(
  base64Decode(
    agentAssetsBase64['specstone-expert-sdd/references/size-fix.md']!,
  ),
);

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

void main() {
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
        'docPath': shopFeature,
        'name': 'shop',
        'line': 1,
        'message':
            'the design read-first file of shop holds $actual est. tokens; '
            'the limit is 24000',
        'waitsFor': 'owner',
        'doc': 'shop',
        'limit': 24000,
        'actual': actual,
      });
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
      expect(found.single.keys['doc'], 'login/reset_password');
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
      expect(found.keys['doc'], 'login/email_login');
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

      expect(story.keys['doc'], 'login/email_login');
      expect(
        story.keys['actual'],
        _headerSizeOf(
          storySession,
          withStory,
          'login/email_login',
          summary: false,
        ),
      );
      expect(withNone.keys['doc'], 'empty');
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
        linked: _overBound ~/ 2,
        unlinked: 1000,
      );
      final citedSession = openSession(cited);
      addTearDown(citedSession.close);
      final citing = _sizeFindings(citedSession, cartFeature).single;
      expect(citing.keys['doc'], 'shop/cart');
      expect(
        citing.keys['actual'],
        _headerSizeOf(citedSession, cited, 'shop/cart', summary: true),
      );
    });

    test("joined docs push a story's read-first file over the limit", () async {
      const ownTokens = 22000;
      const joinedTokens = 3257;
      final story = await _storyLettersFor(ownTokens);
      final alone = openSession(
        await writeNestedProject(
          extra: _withJoinedAgent(story: story, joined: 0),
        ),
      );
      addTearDown(alone.close);
      expect(_sizeFindings(alone, cartFeature), isEmpty);

      final session = openSession(
        await writeNestedProject(
          extra: _withJoinedAgent(story: story, joined: joinedTokens * 4),
        ),
      );
      addTearDown(session.close);

      final found = _sizeFindings(session, cartFeature).single;

      expect(found.kind, FindingKind.bundleOverLimit);
      expect(found.path, cartFeature);
      expect(found.waitsFor, WaitsFor.owner);
      expect(found.keys['doc'], 'shop/cart/add_item');
      expect(found.keys['limit'], readRangeTokenLimit);
      expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
      expect(found.keys['actual'], closeTo(ownTokens + joinedTokens, 100));
    });

    test(
      "the checked size equals the --out header's count with joined docs",
      () async {
        final project = await writeNestedProject(
          extra: _withJoinedAgent(
            story: await _storyLettersFor(22000),
            joined: 3257 * 4,
          ),
        );
        final session = openSession(project);
        addTearDown(session.close);

        final found = _sizeFindings(session, cartFeature).single;

        expect(
          found.keys['actual'],
          _headerSizeOf(session, project, 'shop/cart/add_item', summary: false),
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

        Directory('${project.path}/docs').deleteSync(recursive: true);
        final after = _sizeFindings(session, shopFeature).single.toJson();

        expect(after, before);
        expect(
          _filesUnder(project).toSet(),
          files.where((path) => !path.contains('/docs/')).toSet(),
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
      expect(found.keys['doc'], 'shop/cart/add_item');
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

    test('a sub-feature sized by its pieces of the parent spec docs gets the '
        'finding', () async {
      final project = await _writeCitedInvariants(
        linked: _overBound ~/ 2,
        unlinked: _overBound * 4,
      );
      final session = openSession(project);
      addTearDown(session.close);

      final found = _sizeFindings(session, cartFeature).single;

      expect(found.keys['doc'], 'shop/cart');
      expect(
        found.keys['actual'],
        _headerSizeOf(session, project, 'shop/cart', summary: true),
      );
      expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
      expect(found.keys['actual'], lessThan(_overBound));
    });

    test('an ancestor spec doc no link of the subtree cites adds nothing to '
        'the size', () async {
      final session = openSession(
        await _writeCitedInvariants(linked: 400, unlinked: _overBound * 4),
      );
      addTearDown(session.close);

      expect(_sizeFindings(session, cartFeature), isEmpty);
    });

    test('a story file filled by its own text or by its linked spec pieces '
        'names the story as doc, its fix a story split', () async {
      final ownText = await writeNestedProject(
        extra: {
          'docs/$cartAdd': nestedFiles()['docs/$cartAdd']!.replaceFirst(
            '## Acceptance Criteria\n',
            '## Acceptance Criteria\n${'a' * _overBound}\n',
          ),
        },
      );
      final pieces = await _writeCitedInvariants(
        linked: _overBound,
        unlinked: 1000,
        extra: {
          'docs/$cartDrop':
              '# Agent drops an item\n\n## Use Case\nDrops an item.\n',
        },
      );
      for (final (name, project) in [
        ('own text', ownText),
        ('pieces', pieces),
      ]) {
        final session = openSession(project);
        addTearDown(session.close);

        final found = _sizeFindings(session, cartFeature).single;

        expect(found.path, cartFeature, reason: name);
        expect(found.waitsFor, WaitsFor.owner, reason: name);
        expect(found.keys['doc'], 'shop/cart/add_item', reason: name);
        expect(
          found.keys['actual'],
          _headerSizeOf(session, project, 'shop/cart/add_item', summary: false),
          reason: name,
        );
        expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
      }
      final fix = _sizeFix.split('## A bundle over its limit').last;
      expect(
        fix,
        contains(
          '- `doc` is a story: split it in its feature into two stories, '
          'one `specstone new user_story --parent <feature> --slug\n'
          '  <slug>`, then one `specstone move <fr> … --under <new story>` '
          'per FR and nf that goes to it, so the FRs and nfs are\n'
          '  shared between the two stories.',
        ),
      );
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
        'doc': 'shop',
        'limit': 24000,
        'actual': _headerSizeOf(session, project, 'shop', summary: true),
      });
      expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
      final fix = _sizeFix.split('## A bundle over its limit').last;
      expect(
        fix,
        contains(
          '- `doc` is a feature whose children are sub-features: one '
          '`specstone move <doc>#<ID> … --under <sub-feature>` per\n'
          '  spec item that one sub-feature alone uses. With no such item, no '
          'fix applies.',
        ),
      );
    });

    test('a sub-feature over the bound is its own finding, its fix a split of '
        'its stories', () async {
      final project = await _writeCitedInvariants(
        linked: _overBound ~/ 2,
        unlinked: 1000,
        extra: {
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
        'doc': 'shop/cart',
        'limit': 24000,
        'actual': actual,
      });
      expect(actual, greaterThan(readRangeTokenLimit));
      final fix = _sizeFix.split('## A bundle over its limit').last;
      expect(
        fix,
        contains(
          '- `doc` is a feature whose children are stories: the sub-feature '
          'split above',
        ),
      );
    });

    test('a feature at the nesting depth limit keeps the finding with no '
        'split', () async {
      const express = 'prds/features/f02_shop/f01_cart/f01_express/FEATURE.md';
      const expressStory =
          'prds/features/f02_shop/f01_cart/f01_express/us01_rush/USER_STORY.md';
      final project = await _writeCitedInvariants(
        linked: _overBound ~/ 2,
        unlinked: 1000,
        extra: {
          'docs/$express': nestedFiles()['docs/$cartFeature']!.replaceFirst(
            '## Problem\n',
            '## Problem\nBuilds on [INV-2]($_toDomain#invariants) and '
                '[INV-3]($_toDomain#invariants).\n',
          ),
          'docs/$expressStory': nestedFiles()['docs/$cartAdd']!,
        },
      );
      final session = openSession(project);
      addTearDown(session.close);

      final found = _sizeFindings(session, express).single;

      expect(found.keys['doc'], 'shop/cart/express');
      expect(found.waitsFor, WaitsFor.owner);
      expect(found.keys.keys, unorderedEquals(['doc', 'limit', 'actual']));
      expect(
        found.keys['actual'],
        _headerSizeOf(session, project, 'shop/cart/express', summary: true),
      );
      expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
      expect(
        session.index.childrenOf(session.index.at(express)!),
        hasLength(1),
      );
      final fix = _sizeFix.split('## A bundle over its limit').last;
      expect(
        fix,
        contains("No fix applies to a feature at its doc type's `max_depth`"),
      );
    });

    test(
      'a sub-feature of three stories keeps the finding with no split',
      () async {
        const thirdStory =
            'prds/features/f02_shop/f01_cart/us03_edit_item/USER_STORY.md';
        final project = await _writeCitedInvariants(
          linked: _overBound ~/ 2,
          unlinked: 1000,
          extra: {'docs/$thirdStory': nestedFiles()['docs/$cartAdd']!},
        );
        final session = openSession(project);
        addTearDown(session.close);

        final found = _sizeFindings(session, cartFeature).single;

        expect(found.keys['doc'], 'shop/cart');
        expect(found.waitsFor, WaitsFor.owner);
        expect(found.keys.keys, unorderedEquals(['doc', 'limit', 'actual']));
        final cart = session.index.at(cartFeature)!;
        expect(
          session.index.childrenOf(cart).where(session.index.isChainDoc),
          hasLength(3),
        );
        expect(found.keys['actual'], greaterThan(readRangeTokenLimit));
        final fix = _sizeFix.split('## A bundle over its limit').last;
        expect(fix, contains('whose children are fewer than 4 stories'));
      },
    );

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
