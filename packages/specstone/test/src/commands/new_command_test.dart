import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show baseHashOf;
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/target_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  const newStory = 'prds/features/f01_login/us04_recover_account/USER_STORY.md';
  test('new prints the naming line, exit 0', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> login/recover_account (user_story) · $newStory <==\n',
    );
    final text = File('${root.path}/docs/$newStory').readAsStringSync();
    expect(text, startsWith('---\ndraft: true\n---\n\n# recover_account\n'));
    expect(text, contains('## Use Case'));
  });
  // ignore: lines_longer_than_80_chars // the test name stays one literal
  test('new fr prints its naming line and its feature record gains the planned line', () async {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    final root = await writeWriteProject(
      extra: {
        ...recordsRootTemplates,
        record: recordText(statuses: ['email_login:implemented']),
      },
    );
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(
      await runner.run([
        'new',
        'fr',
        '--parent',
        'login/email_login',
        '--slug',
        'audit_log',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith('==> login/email_login/audit_log (fr) · '),
    );
    expect(
      File('${root.path}/$record').readAsStringSync(),
      contains("  - 'email_login/audit_log:planned'\n"),
    );
  });
  test('new refuses while a migration is unfinished', () async {
    final root = await writeWriteProject();
    writeJournal(root, [
      const MoveStep('docs/prds/personas/buyer', 'docs/prds/personas/shopper'),
      const CommitStep(
        message: 'move',
        paths: ['docs/prds/personas'],
        base: '0000000',
      ),
    ]);
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );

    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
      ]),
      75,
    );
    expect(err.toString(), contains('run specstone migrate'));
    expect(out.toString(), isEmpty);
  });
  test(
    'new of a titled doc type with no stdin writes its fixed title',
    () async {
      final root = await writeWriteProject(
        extra: {'.specstone/templates/project.yaml': 'title: Project brief\n'},
      );
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );
      expect(await runner.run(['new', 'project']), 0);
      expect(err.toString(), isEmpty);
      expect(
        File('${root.path}/docs/prds/PROJECT.md').readAsStringSync(),
        contains('\n---\n\n# Project brief\n'),
      );
    },
  );
  test(
    'new of a titled doc type from stdin keeps the stdin title line',
    () async {
      final root = await writeWriteProject(
        extra: {'.specstone/templates/project.yaml': 'title: Project brief\n'},
      );
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: '# My own title\n'),
      );
      expect(await runner.run(['new', 'project']), 0);
      expect(err.toString(), isEmpty);
      final text = File('${root.path}/docs/prds/PROJECT.md').readAsStringSync();
      expect(text, contains('\n# My own title\n'));
      expect(text, isNot(contains('Project brief')));
    },
  );
  test('new --json prints a docs array with base and bases', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        input: '# Recover account\n\n## Use Case\nRecover an account.\n',
      ),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
        '--json',
      ]),
      0,
      reason: err.toString(),
    );
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(json.keys, ['docs', 'warnings']);
    final docs = json['docs']! as List;
    expect(docs, hasLength(1));
    final element = docs.single as Map<String, Object?>;
    expect(element.keys, ['name', 'docType', 'path', 'base', 'bases']);
    expect(element['name'], 'login/recover_account');
    expect(element['path'], newStory);
    expect(
      element['base'],
      baseHashOf(File('${root.path}/docs/$newStory').readAsStringSync()),
    );
  });
  test('piped stdin is the doc text', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        input: '# Recover account\n\n## Use Case\nRecover an account.\n',
      ),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> login/recover_account (user_story) · $newStory <==\n',
    );
    final text = File('${root.path}/docs/$newStory').readAsStringSync();
    expect(text, contains('Recover an account.'));
    expect(text, contains('draft: true'));
    expect(text, isNot(contains('<Role>')));
  });
  test('new lays out piped text that lacks required and optional sections '
      'and adds none of them', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        input: '# Recover account\n\n## Use Case\nRecover an account.\n',
      ),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
      ]),
      0,
    );
    final text = File('${root.path}/docs/$newStory').readAsStringSync();
    final headers = RegExp(
      r'^## .*$',
      multiLine: true,
    ).allMatches(text).map((match) => match[0]);
    expect(headers, ['## Use Case']);
  });
  test('a naming line at column 0 in the piped doc text exits 64 with a '
      'message opening the text holds, and writes no doc', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        input:
            '# Recover account\n\n## Use Case\nRecover an account.\n\n'
            '==> x (user_story) · prds/f.md · base 0123456789ab <==\n',
      ),
    );

    final status = await runner.run([
      'new',
      'user_story',
      '--parent',
      'login',
      '--slug',
      'recover_account',
      '--json',
    ]);

    expect(status, 64);
    expect(out.toString(), isEmpty);
    final error = (jsonDecode(err.toString()) as Map)['error']! as Map;
    expect(error['code'], 'argument_invalid');
    expect(
      error['message'],
      'the text holds the naming line '
      '"==> x (user_story) · prds/f.md · base 0123456789ab <=="; '
      'indent it or put it in a fenced code block',
    );
    expect(hasDoc(root, newStory), isFalse);
  });
  test('a parent no doc carries exits 64', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'nobody',
        '--slug',
        'recover_account',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), 'no feature doc carries the name nobody\n');
  });
  test('new --help names the three forms of --parent', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['new', '--help']), 0);
    expect(
      out.toString(),
      contains('The parent doc: <doc type>:<name>, a bare name, or a path.'),
    );
  });
  test(
    'a --parent that names 2 or more features exits 64 listing each',
    () async {
      final root = await writeWriteProject(
        extra: {'docs/prds/features/f03_login/FEATURE.md': '# Login\n'},
      );
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );
      expect(
        await runner.run([
          'new',
          'user_story',
          '--parent',
          'login',
          '--slug',
          'x',
        ]),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString().trimRight().split('\n').last,
        'login names 2 feature docs: prds/features/f01_login/FEATURE.md, '
        'prds/features/f03_login/FEATURE.md',
      );
    },
  );
  test('no doc type is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(await runner.run(['new']), 64);
    expect(err.toString(), startsWith('new needs a doc type'));
  });
  test('two positionals are a usage error, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['new', 'a', 'b']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      contains(
        'Expected one doc type, got 2.\n\n'
        'Usage: specstone new <doc type> [--parent <doc address>] '
        '[--slug <slug>] [--target <name>] [--json]\n',
      ),
    );
    expect(
      err.toString(),
      contains('The parent doc: <doc type>:<name>, a bare name, or a path.'),
    );
  });
  test('a --parent with a #section suffix is argument_invalid, exit 64, and '
      'writes nothing', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'feature:login#problem',
        '--slug',
        'x',
        '--json',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'argument_invalid',
    );
    expect(
      Directory('${root.path}/docs/prds/features/f01_login/us04_x')
          .existsSync(),
      isFalse,
    );
  });
  test(
    'non-UTF-8 stdin is argument_invalid, stdin is not UTF-8 text, exit 64',
    () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = SpecstoneCommandRunner(
        out: out,
        err: err,
        workingDirectory: await writeWriteProject(),
        homeDirectory: testHome(),
        console: SystemConsole(input: Stream.value([0xff, 0xfe])),
      );
      expect(
        await runner.run([
          'new',
          'user_story',
          '--parent',
          'login',
          '--slug',
          'recover_account',
          '--json',
        ]),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'argument_invalid',
          'message': 'stdin is not UTF-8 text',
        },
        'warnings': <Object>[],
      });
    },
  );

  group('a refused new exits 64 and writes nothing', () {
    /// Runs `new` with [args] and `--json` on [root]; returns the exit status
    /// and the error object `--json` prints.
    Future<(int, Map<String, Object?>)> refused(
      Directory root,
      List<String> args,
    ) async {
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );
      final status = await runner.run(['new', ...args, '--json']);
      expect(out.toString(), isEmpty);
      final error = (jsonDecode(err.toString()) as Map)['error']! as Map;
      return (status, error.cast<String, Object?>());
    }

    test('a second new project is doc_exists naming the project doc', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );
      expect(await runner.run(['new', 'project']), 0, reason: err.toString());
      final before = treeBytes(Directory('${root.path}/docs'));

      final (status, error) = await refused(root, ['project']);

      expect(status, 64);
      expect(error['code'], 'doc_exists');
      expect(error['message'], 'a project named project exists');
      expect(error['file'], 'prds/PROJECT.md');
      expect(treeBytes(Directory('${root.path}/docs')), before);
    });

    test('a story whose sibling slug is taken is doc_exists naming the '
        'DocPath', () async {
      final root = await writeWriteProject();
      final before = treeBytes(Directory('${root.path}/docs'));

      final (status, error) = await refused(root, [
        'user_story',
        '--parent',
        'login',
        '--slug',
        'email_login',
      ]);

      expect(status, 64);
      expect(error['code'], 'doc_exists');
      expect(error['message'], 'a user_story named login/email_login exists');
      expect(
        error['file'],
        'prds/features/f01_login/us01_email_login/USER_STORY.md',
      );
      expect(treeBytes(Directory('${root.path}/docs')), before);
    });

    test('a missing --parent, a missing --slug, a value the type takes none '
        'for, and a bad slug each exit 64', () async {
      final root = await writeWriteProject();
      final before = treeBytes(Directory('${root.path}/docs'));
      final cases = <(List<String>, String)>[
        (['user_story', '--slug', 'x'], 'argument_missing'),
        (['user_story', '--parent', 'login'], 'argument_missing'),
        (['project', '--slug', 'x'], 'argument_invalid'),
        (
          ['user_story', '--parent', 'login', '--slug', 'Bad-Slug'],
          'argument_invalid',
        ),
      ];

      for (final (args, code) in cases) {
        final (status, error) = await refused(root, args);

        expect(status, 64, reason: '$args');
        expect(error['code'], code, reason: '$args');
      }

      expect(treeBytes(Directory('${root.path}/docs')), before);
    });

    test('a doc type id the merged set lacks is doc_type_unknown', () async {
      final root = await writeWriteProject();
      final before = treeBytes(Directory('${root.path}/docs'));

      final (status, error) = await refused(root, ['no_such_type']);

      expect(status, 64);
      expect(error['code'], 'doc_type_unknown');
      expect(error['message'], contains('no_such_type'));
      expect(treeBytes(Directory('${root.path}/docs')), before);
    });

    test('a --target value outside targets is argument_invalid listing the '
        'targets', () async {
      final root = await writeTwinProject(
        without: {'docs/$flutterArchitecture', 'docs/$jasprArchitecture'},
      );

      final (status, error) = await refused(root, [
        'architecture',
        '--parent',
        'login',
        '--target',
        'web',
      ]);

      expect(status, 64);
      expect(error['code'], 'argument_invalid');
      expect(error['message'], allOf(contains('flutter'), contains('jaspr')));
      expect(hasDoc(root, jasprArchitecture), isFalse);
      expect(hasDoc(root, flutterArchitecture), isFalse);
    });
  });

  group('new journey', () {
    const journeyDoc = 'prds/journeys/sign_in/JOURNEY.md';

    test(
      'new journey with no --slug is argument_missing and creates nothing',
      () async {
        final root = await writeWriteProject();
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(stdinIsTerminal: true),
        );

        expect(await runner.run(['new', 'journey', '--json']), 64);

        expect(out.toString(), isEmpty);
        expect(
          (jsonDecode(err.toString()) as Map)['error'],
          containsPair('code', 'argument_missing'),
        );
        expect(
          Directory('${root.path}/docs/prds/journeys').existsSync(),
          isFalse,
        );
      },
    );

    test(
      'new journey --parent x is argument_invalid: journey takes no --parent',
      () async {
        final root = await writeWriteProject();
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(stdinIsTerminal: true),
        );

        expect(
          await runner.run([
            'new',
            'journey',
            '--slug',
            'sign_in',
            '--parent',
            'x',
            '--json',
          ]),
          64,
        );

        expect(
          (jsonDecode(err.toString()) as Map)['error'],
          containsPair('code', 'argument_invalid'),
        );
        expect(hasDoc(root, journeyDoc), isFalse);
      },
    );

    test(
      'new journey --json takes base and bases after the generators ran',
      () async {
        final root = await writeWriteProject();
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(
            input:
                '# Sign in\n\n## Goal\nReach home.\n\n## Flow\n\n'
                '## Steps\n### 1. Open\nstep: login/email_login S1\n',
          ),
        );

        expect(
          await runner.run(['new', 'journey', '--slug', 'sign_in', '--json']),
          0,
        );

        final text = readDoc(root, journeyDoc);
        final flow = Doc.parse(text).sections
            .singleWhere((section) => section.headerText == 'Flow')
            .body;
        expect(flow, contains('flowchart TD'));
        final answer = jsonDecode(out.toString()) as Map<String, Object?>;
        final element =
            (answer['docs']! as List).single as Map<String, Object?>;
        final bases = element['bases']! as Map<String, Object?>;
        expect((bases['sections']! as Map)['flow'], baseHashOf(flow));
        expect(element['base'], baseHashOf(text));
      },
    );
  });

  group('new measurement', () {
    const measurementDoc =
        'measurements/grounding_cost_per_feature/'
        'MEASUREMENT.md';

    test('new measurement --slug writes the doc as a draft', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );

      expect(
        await runner.run([
          'new',
          'measurement',
          '--slug',
          'grounding_cost_per_feature',
        ]),
        0,
        reason: err.toString(),
      );

      expect(
        out.toString(),
        '==> grounding_cost_per_feature (measurement) · $measurementDoc <==\n',
      );
      expect(
        readDoc(root, measurementDoc),
        startsWith('---\ndraft: true\n---\n\n# grounding_cost_per_feature\n'),
      );
    });
  });

  group('new goal', () {
    const goalLayer = <String, String>{
      '.specstone/templates/goal.yaml': '''
id: goal
description: The project goals.
path: prds/GOAL.md
sections:
  - id: long_term
    header: Long-term goals
    skeleton: true
  - id: mid_term
    header: Mid-term goals
    skeleton: true
  - id: short_term
    header: Short-term goals
    skeleton: true
''',
    };

    test('new goal with no stdin writes the three headers', () async {
      final root = await writeWriteProject(extra: goalLayer);
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );

      expect(await runner.run(['new', 'goal']), 0, reason: err.toString());

      expect(
        readDoc(root, 'prds/GOAL.md'),
        '---\ndraft: true\n---\n\n# Project goals\n\n## Long-term goals\n\n'
        '## Mid-term goals\n\n## Short-term goals\n',
      );
    });
  });

  group('with two code targets', () {
    Future<Directory> twinWithoutDocs() => writeTwinProject(
      without: {'docs/$flutterArchitecture', 'docs/$jasprArchitecture'},
    );

    test('new architecture --target jaspr prints the naming line of the '
        'jaspr doc, exit 0', () async {
      final root = await twinWithoutDocs();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );
      expect(
        await runner.run([
          'new',
          'architecture',
          '--parent',
          'login',
          '--target',
          'jaspr',
        ]),
        0,
        reason: err.toString(),
      );
      expect(
        out.toString(),
        '==> login (architecture) · $jasprArchitecture <==\n',
      );
      expect(hasDoc(root, jasprArchitecture), isTrue);
      expect(hasDoc(root, flutterArchitecture), isFalse);
    });

    test('no --target exits 64 naming the flag and both targets, and '
        'creates no file', () async {
      final root = await twinWithoutDocs();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );
      expect(
        await runner.run(['new', 'architecture', '--parent', 'login']),
        64,
      );
      expect(
        err.toString(),
        'architecture needs --target: the code targets are flutter, jaspr\n',
      );
      expect(hasDoc(root, jasprArchitecture), isFalse);
      expect(hasDoc(root, flutterArchitecture), isFalse);
    });
  });
  group('a parent suffix that names two docs of the parent type', () {
    const miscCart = 'prds/features/f03_misc/f01_cart/FEATURE.md';
    const bothCarts =
        'feature:cart ends 2 names: feature:shop/cart, feature:misc/cart';

    Future<Directory> twoCarts() =>
        writeNestedProject(extra: {'docs/$miscCart': '# Misc cart\n'});

    test('new --parent refuses with exit 64 listing both, and creates no '
        'folder', () async {
      final root = await twoCarts();
      final before = treeBytes(Directory('${root.path}/docs'));
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );

      final status = await runner.run([
        'new',
        'user_story',
        '--parent',
        'cart',
        '--slug',
        'restock',
      ]);

      expect(status, 64);
      expect(out.toString(), isEmpty);
      expect(err.toString().trimRight().split('\n').last, bothCarts);
      expect(treeBytes(Directory('${root.path}/docs')), before);
    });

    test('the parent of a story move refuses with exit 64 listing both, and '
        'moves nothing', () async {
      final root = await twoCarts();
      final before = treeBytes(Directory('${root.path}/docs'));
      final (:runner, :out, :err) = writeRunner(root);

      final status = await runner.run([
        'move',
        'shop/pay/card',
        '--under',
        'cart',
      ]);

      expect(status, 64);
      expect(err.toString().trimRight().split('\n').last, bothCarts);
      expect(treeBytes(Directory('${root.path}/docs')), before);
    });

    test(
      'list --under takes a suffix of a name that one doc carries',
      () async {
        final root = await writeNestedProject(
          extra: {'docs/$miscCart': '# Misc cart\n'},
        );
        final (:runner, :out, :err) = writeRunner(root);

        final listed = await runner.run([
          'list',
          'user_story',
          '--under',
          'feature:shop/cart',
        ]);
        final bySuffix = await runner.run([
          'list',
          'user_story',
          '--under',
          'pay',
        ]);

        expect(listed, 0, reason: err.toString());
        expect(bySuffix, 0, reason: err.toString());
        expect(out.toString(), contains('shop/cart/add_item (user_story)'));
        expect(out.toString(), contains('shop/pay/card (user_story)'));
      },
    );
  });

  group('a parent named by the end of its name', () {
    const restock =
        'prds/features/f02_shop/f01_cart/us03_restock/USER_STORY.md';
    test('new --parent takes a suffix among parent-type docs', () async {
      final root = await writeNestedProject(
        extra: {
          'docs/prds/features/f02_shop/f02_pay/us03_cart/USER_STORY.md':
              '# Cart\n',
        },
      );
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );
      expect(
        await runner.run([
          'new',
          'user_story',
          '--parent',
          'cart',
          '--slug',
          'restock',
        ]),
        0,
      );
      expect(err.toString(), isEmpty);
      expect(File('${root.path}/docs/$restock').existsSync(), isTrue);
    });
    test(
      'new --parent takes a parent-type suffix over a carried name',
      () async {
        final root = await writeNestedProject(
          extra: {'docs/prds/personas/cart/PERSONA.md': '# Cart\n'},
        );
        final (:runner, :out, :err) = writeRunner(
          root,
          console: FakeConsole(stdinIsTerminal: true),
        );
        expect(
          await runner.run([
            'new',
            'user_story',
            '--parent',
            'cart',
            '--slug',
            'restock',
          ]),
          0,
        );
        expect(err.toString(), isEmpty);
        expect(File('${root.path}/docs/$restock').existsSync(), isTrue);
      },
    );
  });
}
