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

/// Letters that put a story or doc over the bound by a margin of 2,000 est.
/// tokens (characters / 4).
const int _overBound = (bundleTokenLimit + 2000) * 4;

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
}) {
  final files = _citedInvariants(linked: linked, unlinked: unlinked);
  return writeCheckProject(
    extra: {...nestedFiles(), ...files},
    unstamped: files.keys.toSet(),
  );
}

ContextAnswer _answerOf(DocIndex index, String name, {required bool summary}) =>
    answerContext(
      index,
      pickBundle(
        index,
        name,
        BundleMode.design,
        noProject: false,
        summary: summary,
      ),
      label: name,
      byCode: false,
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
      expect(actual, greaterThan(bundleTokenLimit));
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
      final chars = await _criteriaFor(bundleTokenLimit);
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
      expect(found.keys['actual'], bundleTokenLimit + 1);
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
      expect(found.keys['actual'], greaterThan(bundleTokenLimit));
      expect(
        _answerOf(session.index, 'shop/cart', summary: true).readFirst.tokens,
        lessThanOrEqualTo(bundleTokenLimit),
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
      expect(found.keys['actual'], greaterThan(bundleTokenLimit));
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
