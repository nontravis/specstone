import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show baseHashOf;
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/grouped_fixture.dart';
import '../../../../specstone_core/test/helpers/nested_fixture.dart';
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
  test('new feature with a group slug prints the grouped naming '
      'line', () async {
    final root = await writeGroupedProject();
    final (:runner, :out, :err) = writeRunner(root, console: FakeConsole());
    expect(await runner.run(['new', 'feature', '--slug', 'garden/herbs']), 0);
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> garden/herbs (feature) · prds/features/garden/f01_herbs/FEATURE.md '
      '<==\n',
    );
  });
  test(
    'new feature with a one-part slug in a grouped project exits 64',
    () async {
      final root = await writeGroupedProject();
      final (:runner, :out, :err) = writeRunner(root, console: FakeConsole());
      expect(
        await runner.run(['new', 'feature', '--slug', 'herbs', '--json']),
        64,
      );
      expect(out.toString(), isEmpty);
      final error = (jsonDecode(err.toString()) as Map)['error'] as Map;
      expect(error['code'], 'argument_missing');
      expect(error['message'], contains('--slug <slug>/<slug>'));
      expect(
        Directory('${root.path}/docs/prds/features/herbs').existsSync(),
        isFalse,
      );
    },
  );
  test('new with a slash in a one-slug segment exits 64', () async {
    final root = await writeWriteProject();
    final loginFolder = Directory('${root.path}/docs/prds/features/f01_login');
    final before = [
      for (final e in loginFolder.listSync(recursive: true)) e.path,
    ]..sort();
    final (:runner, :out, :err) = writeRunner(root, console: FakeConsole());
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'a/b',
        '--json',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      (jsonDecode(err.toString()) as Map)['error'],
      containsPair('code', 'argument_invalid'),
    );
    expect(
      [for (final e in loginFolder.listSync(recursive: true)) e.path]..sort(),
      before,
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
