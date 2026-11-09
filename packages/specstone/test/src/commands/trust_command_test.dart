import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/relative_link.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

/// Writes a clone whose committed `docs` link leads to the sibling folder
/// `ext/`, which holds the docs.
Future<({Directory clone, Directory ext})> _clone() async {
  final base = await writeTree({
    for (final MapEntry(:key, :value) in writeProject.entries)
      if (key.startsWith('docs/'))
        'ext/${key.substring(5)}': value
      else
        'src/clone/$key': value,
  });
  createRelativeLink('${base.path}/src/clone/docs', '../../ext');
  return (
    clone: Directory('${base.path}/src/clone'),
    ext: Directory('${base.path}/ext'),
  );
}

/// Runs `specstone <args>` in [root] and returns the status and what it
/// printed; [terminal] with [answers] makes the run interactive.
Future<({int status, String out, String err})> _run(
  Directory root,
  List<String> args, {
  List<String?> answers = const [],
  bool terminal = false,
}) async {
  final (:runner, :out, :err) = writeRunner(
    root,
    console: FakeConsole(
      stdinIsTerminal: terminal,
      stdoutIsTerminal: terminal,
      answers: answers,
    ),
  );
  final status = await runner.run(args);
  return (status: status, out: out.toString(), err: err.toString());
}

Directory get _records => Directory('${testHome().path}/.specstone/trusted');

void main() {
  group('trust', () {
    test('lists itself in the usage', () async {
      final root = await writeWriteProject();

      final help = await _run(root, ['--help']);

      expect(help.out, contains('trust'));
    });

    test('without a terminal prints the roots, refuses owner_terminal_required '
        'with exit 77, and records nothing', () async {
      final (:clone, :ext) = await _clone();

      final run = await _run(clone, ['trust']);

      expect(run.status, 77, reason: run.err);
      expect(
        run.out,
        'project root: ${clone.resolveSymbolicLinksSync()}\n'
        'docs root: ${ext.resolveSymbolicLinksSync()}\n',
      );
      expect(run.err, 'trust runs only at an interactive terminal\n');
      expect(_records.existsSync(), isFalse);
    }, skip: _linksUnavailable);

    test('takes no --yes, so an agent cannot trust for the Owner', () async {
      final (:clone, ext: _) = await _clone();

      final run = await _run(clone, ['trust', '--yes']);

      expect(run.status, 64);
      expect(_records.existsSync(), isFalse);
    }, skip: _linksUnavailable);

    test('at a terminal asks, and a y records both roots', () async {
      final (:clone, :ext) = await _clone();

      final run = await _run(clone, ['trust'], terminal: true, answers: ['y']);

      expect(run.status, 0, reason: run.err);
      expect(
        run.out,
        'project root: ${clone.resolveSymbolicLinksSync()}\n'
        'docs root: ${ext.resolveSymbolicLinksSync()}\n'
        'trust these folders for writes? [y/N] trusted\n',
      );
      final record = _records.listSync().single as File;
      expect(jsonDecode(record.readAsStringSync()), {
        'projectRoot': clone.resolveSymbolicLinksSync(),
        'docsRoot': ext.resolveSymbolicLinksSync(),
      });
    }, skip: _linksUnavailable);

    test('at a terminal an answer other than y records nothing', () async {
      final (:clone, ext: _) = await _clone();

      final run = await _run(clone, ['trust'], terminal: true, answers: ['n']);

      expect(run.status, 0, reason: run.err);
      expect(_records.existsSync(), isFalse);
    }, skip: _linksUnavailable);

    test('a project whose docs folder lies inside it needs no record, even '
        'with no terminal', () async {
      final root = await writeWriteProject();

      final run = await _run(root, ['trust']);

      expect(run.status, 0, reason: run.err);
      expect(run.out, startsWith('no record needed: '));
      expect(_records.existsSync(), isFalse);
    });

    test(
      'outside a project asks nothing, since init there needs no record',
      () async {
        final root = await writeTree({'keep.txt': ''});

        final run = await _run(root, ['trust']);

        expect(run.status, 0, reason: run.err);
        expect(run.out, startsWith('no record needed: '));
      },
    );

    test('before a config exists records the roots init would write into, so '
        'init then runs', () async {
      final base = Directory(
        (await writeTree({
          'victim/docs/prds/keep.md': '# Keep\n',
          'clone/keep.txt': '',
        })).resolveSymbolicLinksSync(),
      );
      createRelativeLink('${base.path}/clone/docs', '../victim/docs');
      final clone = Directory('${base.path}/clone');

      final refused = await _run(clone, ['init']);
      final trusted = await _run(
        clone,
        ['trust'],
        terminal: true,
        answers: ['y'],
      );
      final init = await _run(clone, ['init']);

      expect(refused.status, 73, reason: refused.err);
      expect(refused.err, contains('run specstone trust at a terminal'));
      expect(
        trusted.out,
        startsWith(
          'project root: ${base.path}/victim\n'
          'docs root: ${base.path}/victim/docs\n',
        ),
      );
      expect(init.status, 0, reason: init.err);
      expect(
        File('${base.path}/victim/.specstone/config.yaml').existsSync(),
        isTrue,
      );
    }, skip: _linksUnavailable);
  });

  group('a write command after trust', () {
    test('new refuses, with the exact message, until the Owner trusts the '
        'roots; then it writes', () async {
      final (:clone, :ext) = await _clone();
      const args = ['new', 'persona', '--slug', 'team', '--json'];
      const shown = 'docs/prds/personas/team/PERSONA.md';

      final refused = await _run(clone, args);

      expect(refused.status, 73, reason: refused.err);
      expect(jsonDecode(refused.err), {
        'error': {
          'code': 'output_not_writable',
          'message':
              'cannot write $shown: the docs folder '
              '${ext.resolveSymbolicLinksSync()} lies outside the project; '
              'run specstone trust at a terminal to allow it',
          'file': shown,
        },
      });
      expect(
        File('${ext.path}/prds/personas/team/PERSONA.md').existsSync(),
        isFalse,
      );

      await _run(clone, ['trust'], terminal: true, answers: ['y']);
      final written = await _run(clone, args);

      expect(written.status, 0, reason: written.err);
      expect(
        File('${ext.path}/prds/personas/team/PERSONA.md').existsSync(),
        isTrue,
      );
    }, skip: _linksUnavailable);

    test('read commands work without the record', () async {
      final (:clone, ext: _) = await _clone();

      final check = await _run(clone, ['list', 'persona']);

      expect(check.status, 0, reason: check.err);
    }, skip: _linksUnavailable);
  });
}
