// The titles are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/nested_fixture.dart';
import '../helpers/read_fixture.dart';
import '../helpers/write_runner.dart';

const usageLine = 'Usage: specstone <command> [arguments]';

void main() {
  group('SpecstoneCommandRunner', () {
    late StringBuffer out;
    late StringBuffer err;
    late SpecstoneCommandRunner runner;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
      runner = SpecstoneCommandRunner(
        out: out,
        err: err,
        console: FakeConsole(),
      );
    });

    test('the injected resolver and folders come back from the getters', () {
      final templates = TemplateResolver();
      final working = Directory('work');
      final home = Directory('home');

      final injected = SpecstoneCommandRunner(
        console: FakeConsole(),
        templates: templates,
        workingDirectory: working,
        homeDirectory: home,
      );

      expect(injected.templates, same(templates));
      expect(injected.workingDirectory, same(working));
      expect(injected.homeDirectory, same(home));
    });

    test(
      'a deleted working folder does not stop --version or --help',
      () async {
        final exits = await IOOverrides.runZoned(
          () async => [
            await SpecstoneCommandRunner(
              out: out,
              err: err,
              console: FakeConsole(),
            ).run(['--version']),
            await SpecstoneCommandRunner(
              out: out,
              err: err,
              console: FakeConsole(),
            ).run(['--help']),
          ],
          getCurrentDirectory: () => throw const FileSystemException('gone'),
        );

        expect(exits, [0, 0]);
        expect(err.toString(), isEmpty);
      },
    );

    test('--version prints the core version and exits 0', () async {
      expect(await runner.run(['--version']), 0);
      expect(out.toString(), '$specstoneVersion\n');
      expect(err.toString(), isEmpty);
    });

    test('no arguments prints the usage and exits 0', () async {
      expect(await runner.run([]), 0);
      expect(out.toString(), contains(usageLine));
    });

    test('--help prints the generated usage and exits 0', () async {
      expect(await runner.run(['--help']), 0);
      expect(out.toString(), contains(usageLine));
      expect(out.toString(), contains('--version'));
      expect(out.toString(), contains('guide'));
      expect(out.toString(), contains('upgrade'));
    });

    test("--help lists folder as `Print the project's "
        '.specstone folder.`', () async {
      expect(await runner.run(['--help']), 0);
      expect(
        out.toString(),
        matches(
          RegExp(
            r"^\s+folder\s+Print the project's \.specstone folder\.$",
            multiLine: true,
          ),
        ),
      );
    });

    test("the help command lists folder as `Print the project's "
        '.specstone folder.`', () async {
      expect(await runner.run(['help']), 0);
      expect(
        out.toString(),
        matches(
          RegExp(
            r"^\s+folder\s+Print the project's \.specstone folder\.$",
            multiLine: true,
          ),
        ),
      );
    });

    test(
      'mcp is no command: mcp --help prints usage to stderr and exits 64',
      () async {
        expect(await runner.run(['mcp', '--help']), usageExitCode);
        expect(
          err.toString(),
          contains('Could not find a command named "mcp"'),
        );
        expect(err.toString(), contains(usageLine));
        expect(out.toString(), isEmpty);
      },
    );

    test('an unknown command prints usage to stderr and exits 64', () async {
      expect(await runner.run(['nope']), usageExitCode);
      expect(err.toString(), contains('Could not find a command named "nope"'));
      expect(err.toString(), contains(usageLine));
      expect(out.toString(), isEmpty);
    });

    test('an unknown option prints usage to stderr and exits 64', () async {
      expect(await runner.run(['--bogus']), usageExitCode);
      expect(
        err.toString(),
        contains('Could not find an option named "--bogus"'),
      );
      expect(out.toString(), isEmpty);
    });

    test('--version with a trailing unknown command exits 64, not 0', () async {
      expect(await runner.run(['--version', 'nope']), usageExitCode);
      expect(err.toString(), contains('Could not find a command named "nope"'));
      expect(out.toString(), isEmpty);
    });
  });

  group('--out of a reply command', () {
    const journeyDoc = 'docs/prds/journeys/sign_in/JOURNEY.md';
    const journeyText =
        '# Sign in\n\n## Goal\nReach home.\n\n## Flow\n\n## Steps\n'
        '### 1. Open the page\nstep: login/email_login S1\n';

    test('a bare --out names the file by the command, its flags, and its arguments', () async {
      final project = await writeReadProject(extra: {journeyDoc: journeyText});
      for (final (args, name) in [
        (['get', 'sign_in', '--paths'], 'get-paths.sign_in.txt'),
        (['check', '--repeats'], 'check-repeats.all.txt'),
        (['guide', '--pattern', 'crud'], 'guide-pattern.crud.txt'),
      ]) {
        final (:runner, :out, :err) = readRunner(project);
        expect(await runner.run([...args, '--out']), 0, reason: err.toString());
        expect(
          File('${project.path}/.specstone/reports/$name').existsSync(),
          isTrue,
          reason: name,
        );
        expect(out.toString(), startsWith('==> ${args.first}: '));
      }

      final nested = await writeNestedProject();
      final (:runner, :out, :err) = writeRunner(nested);
      expect(
        await runner.run([
          'move',
          '--plan-out',
          'user_story:shop/cart/add_item',
          '--out',
        ]),
        0,
        reason: err.toString(),
      );
      expect(
        File(
          '${nested.path}/.specstone/reports/'
          'move-plan-out.user_story-shop-cart-add_item.txt',
        ).existsSync(),
        isTrue,
      );
    });

    test('a command that writes files takes no --out', () async {
      final project = await writeReadProject();
      for (final command in ['hook', 'init']) {
        final (:runner, :out, :err) = readRunner(project);
        expect(await runner.run([command, '--out']), usageExitCode);
        expect(
          err.toString(),
          contains('Could not find an option named "--out"'),
        );
        expect(out.toString(), isEmpty);
      }
    });
  });

  group('homeFrom', () {
    test('returns the folder in HOME', () {
      expect(
        homeFrom({'HOME': '/home/a', 'USERPROFILE': r'C:\\a'})?.path,
        '/home/a',
      );
    });

    test('treats an empty HOME as unset and falls back to USERPROFILE', () {
      expect(homeFrom({'HOME': '', 'USERPROFILE': r'C:\\a'})?.path, r'C:\\a');
    });

    test('returns null when both are unset or empty', () {
      expect(homeFrom({}), isNull);
      expect(homeFrom({'HOME': '', 'USERPROFILE': ''}), isNull);
    });
  });
}
