import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
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

/// Runs `specstone <args>` in [root] like [_run], with [console] and, when
/// given, [home] as the home folder.
///
/// A null [home] leaves the runner with no home folder at all, as an
/// environment with neither `HOME` nor `USERPROFILE` does.
Future<({int status, String out, String err})> _runWith(
  Directory root,
  List<String> args, {
  required FakeConsole console,
  Directory? home,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = SpecstoneCommandRunner(
    out: out,
    err: err,
    templates: TemplateResolver(),
    workingDirectory: root,
    homeDirectory: home,
    console: console,
    environment: const {},
  );
  final status = await runner.run(args);
  return (status: status, out: out.toString(), err: err.toString());
}

/// Writes a workspace whose root holds the config and the docs, and whose
/// code folder `code/` holds a `docs` link to `../docs` and a folder `sub/`.
Future<({Directory ws, Directory code})> _workspace() async {
  final base = await writeTree({
    for (final MapEntry(:key, :value) in writeProject.entries) 'ws/$key': value,
    'ws/code/sub/keep.txt': '',
  });
  createRelativeLink('${base.path}/ws/code/docs', '../docs');
  return (
    ws: Directory(Directory('${base.path}/ws').resolveSymbolicLinksSync()),
    code: Directory('${base.path}/ws/code'),
  );
}

/// The text `trust` prints for roots that need no record.
String _noRecordNeeded(String docsRoot, String projectRoot) =>
    'no record needed: the docs folder $docsRoot lies inside the project '
    'folder $projectRoot\n';

String _roots(String projectRoot, String docsRoot) =>
    'project root: $projectRoot\ndocs root: $docsRoot\n';

const _prompt = 'trust these folders for writes? [y/N] ';

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

    test('a layout the Owner already trusted says so and exits 0, even with '
        'no terminal', () async {
      final (:clone, :ext) = await _clone();
      await _run(clone, ['trust'], terminal: true, answers: ['y']);

      final run = await _run(clone, ['trust']);

      expect(run.status, 0, reason: run.err);
      expect(
        run.out,
        'already trusted: the project folder '
        '${clone.resolveSymbolicLinksSync()} and the docs folder '
        '${ext.resolveSymbolicLinksSync()}\n',
      );
      expect(run.err, isEmpty);
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

  group('trust edge cases', () {
    test('stdin alone or stdout alone not a terminal refuses with exit 77 '
        'after the roots, and records nothing', () async {
      final (:clone, :ext) = await _clone();

      for (final (stdin, stdout) in [(true, false), (false, true)]) {
        final run = await _runWith(
          clone,
          ['trust'],
          console: FakeConsole(
            stdinIsTerminal: stdin,
            stdoutIsTerminal: stdout,
            answers: ['y'],
          ),
          home: testHome(),
        );

        final reason = 'stdin $stdin, stdout $stdout';
        expect(run.status, 77, reason: reason);
        expect(
          run.out,
          _roots(
            clone.resolveSymbolicLinksSync(),
            ext.resolveSymbolicLinksSync(),
          ),
          reason: reason,
        );
        expect(
          run.err,
          'trust runs only at an interactive terminal\n',
          reason: reason,
        );
        expect(_records.existsSync(), isFalse, reason: reason);
      }
    }, skip: _linksUnavailable);

    test('another option or an argument is a usage error with exit 64 and '
        'no record, even at a terminal', () async {
      final (:clone, ext: _) = await _clone();

      for (final args in [
        ['trust', '--other'],
        ['trust', 'extra'],
      ]) {
        final run = await _run(clone, args, terminal: true, answers: ['y']);

        expect(run.status, 64, reason: '$args');
        expect(run.out, isNot(contains('trusted')), reason: '$args');
        expect(_records.existsSync(), isFalse, reason: '$args');
      }
    }, skip: _linksUnavailable);

    test('an empty line and the end of input write no record and exit '
        '0', () async {
      final (:clone, :ext) = await _clone();
      final roots = _roots(
        clone.resolveSymbolicLinksSync(),
        ext.resolveSymbolicLinksSync(),
      );

      for (final answers in [
        <String?>[''],
        <String?>[],
      ]) {
        final run = await _run(
          clone,
          ['trust'],
          terminal: true,
          answers: answers,
        );

        expect(run.status, 0, reason: '$answers ${run.err}');
        expect(run.out, '$roots$_prompt', reason: '$answers');
        expect(_records.existsSync(), isFalse, reason: '$answers');
      }
    }, skip: _linksUnavailable);

    test('no record needed prints its whole message, with a terminal or '
        'without one, and asks nothing', () async {
      final root = await writeWriteProject();
      final project = root.resolveSymbolicLinksSync();
      final docs = Directory('$project${Platform.pathSeparator}docs')
          .resolveSymbolicLinksSync();

      final without = await _run(root, ['trust']);
      final atTerminal = await _run(
        root,
        ['trust'],
        terminal: true,
        answers: ['y'],
      );

      for (final run in [without, atTerminal]) {
        expect(run.status, 0, reason: run.err);
        expect(run.out, _noRecordNeeded(docs, project));
        expect(run.err, isEmpty);
      }
      expect(_records.existsSync(), isFalse);
    });

    test('in the code folder of a workspace trust asks, and after the y '
        'writes work from that folder and from below it', () async {
      final (:ws, :code) = await _workspace();
      final docs = '${ws.path}${Platform.pathSeparator}docs';
      final sub = Directory('${code.path}/sub');

      final refused = await _run(sub, ['new', 'persona', '--slug', 'early']);
      final trusted = await _run(
        code,
        ['trust'],
        terminal: true,
        answers: ['y'],
      );
      final fromCode = await _run(code, ['new', 'persona', '--slug', 'one']);
      final fromBelow = await _run(sub, ['new', 'persona', '--slug', 'two']);
      final fromParent = await _run(ws, ['trust']);

      expect(refused.status, 73, reason: refused.err);
      expect(
        refused.err,
        contains(
          'the project folder ${ws.path} was reached through the docs link '
          'in ${Directory(code.path).resolveSymbolicLinksSync()}',
        ),
      );
      expect(trusted.status, 0, reason: trusted.err);
      expect(trusted.out, '${_roots(ws.path, docs)}${_prompt}trusted\n');
      expect(fromCode.status, 0, reason: fromCode.err);
      expect(fromBelow.status, 0, reason: fromBelow.err);
      for (final slug in ['one', 'two']) {
        expect(
          File('$docs/prds/personas/$slug/PERSONA.md').existsSync(),
          isTrue,
        );
      }
      expect(fromParent.status, 0, reason: fromParent.err);
      expect(fromParent.out, _noRecordNeeded(docs, ws.path));
    }, skip: _linksUnavailable);

    test(
      'before a config exists the roots come from the nearest legacy '
      'context doc or pending journal, else the working folder itself',
      () async {
        final base = await writeTree({
          'legacy/docs/prds/d01_context.md': '# Context\n',
          'legacy/sub/deep/keep.txt': '',
          'journal/.specstone/trash/journal.json': '{}',
          'journal/sub/keep.txt': '',
          'bare/docs/keep.md': '# Keep\n',
          'bare/child/keep.txt': '',
        });
        final top = Directory(base.path).resolveSymbolicLinksSync();
        String at(String relative) =>
            '$top${Platform.pathSeparator}'
            '${relative.replaceAll('/', Platform.pathSeparator)}';

        for (final (start, project) in [
          ('legacy/sub/deep', 'legacy'),
          ('journal/sub', 'journal'),
          ('bare/child', 'bare/child'),
        ]) {
          final run = await _run(Directory(at(start)), ['trust']);

          expect(run.status, 0, reason: '$start ${run.err}');
          expect(
            run.out,
            _noRecordNeeded(at('$project/docs'), at(project)),
            reason: start,
          );
        }
      },
    );

    test('no usable home exits 73 after the roots and the terminal check, '
        'before the prompt', () async {
      final (:clone, :ext) = await _clone();
      final inProject = Directory('${clone.path}/home')..createSync();
      final project = clone.resolveSymbolicLinksSync();
      final docs = ext.resolveSymbolicLinksSync();

      for (final (label, home) in [
        ('no home folder', null),
        ('a home inside the project root', inProject),
        ('a home that is the docs root', ext),
      ]) {
        final run = await _runWith(
          clone,
          ['trust'],
          console: FakeConsole(
            stdinIsTerminal: true,
            stdoutIsTerminal: true,
            answers: ['y'],
          ),
          home: home,
        );

        expect(run.status, 73, reason: label);
        expect(run.out, _roots(project, docs), reason: label);
        expect(
          run.err,
          'cannot record the trust: no home folder to keep it in\n',
          reason: label,
        );
      }
    }, skip: _linksUnavailable);

    test(
      'a record the disk refuses exits 73 and names the record path',
      () async {
        final (:clone, ext: _) = await _clone();
        final home = await writeTree({
          '.specstone/trusted': 'a file, not a folder',
        });

        final run = await _runWith(
          clone,
          ['trust'],
          console: FakeConsole(
            stdinIsTerminal: true,
            stdoutIsTerminal: true,
            answers: ['y'],
          ),
          home: home,
        );

        expect(run.status, 73, reason: run.err);
        expect(run.err, startsWith('cannot write ${home.path}'));
        expect(run.err, contains('${Platform.pathSeparator}.specstone'));
        expect(run.out, isNot(contains('trusted\n')));
      },
      skip: _linksUnavailable,
    );

    test('a docs link to a project below the folder holding it needs no '
        'record', () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          'ws/sub/$key': value,
      });
      createRelativeLink('${base.path}/ws/docs', 'sub/docs');
      final project = Directory('${base.path}/ws/sub')
          .resolveSymbolicLinksSync();

      final run = await _run(Directory('${base.path}/ws'), ['trust']);

      expect(run.status, 0, reason: run.err);
      expect(
        run.out,
        _noRecordNeeded('$project${Platform.pathSeparator}docs', project),
      );
      expect(_records.existsSync(), isFalse);
    }, skip: _linksUnavailable);

    test('a layout already trusted at a terminal prints one line, asks '
        'nothing, and writes no new record', () async {
      final (:clone, :ext) = await _clone();
      await _run(clone, ['trust'], terminal: true, answers: ['y']);
      final record = _records.listSync().single as File;
      final recorded = record.readAsStringSync();
      var reads = 0;

      final run = await _runWith(
        clone,
        ['trust'],
        console: FakeConsole(
          stdinIsTerminal: true,
          stdoutIsTerminal: true,
          answers: ['y'],
          onReadLine: (_) => reads++,
        ),
        home: testHome(),
      );

      expect(run.status, 0, reason: run.err);
      expect(
        run.out,
        'already trusted: the project folder '
        '${clone.resolveSymbolicLinksSync()} and the docs folder '
        '${ext.resolveSymbolicLinksSync()}\n',
      );
      expect(reads, 0);
      expect(_records.listSync().single.path, record.path);
      expect(record.readAsStringSync(), recorded);
    }, skip: _linksUnavailable);

    test(
      'a read command without a record refreshes the index and exits 0',
      () async {
        final (:clone, ext: _) = await _clone();
        final index = File('${clone.path}/.specstone/index.sqlite');
        expect(index.existsSync(), isFalse);

        final run = await _run(clone, ['list', 'persona']);

        expect(run.status, 0, reason: run.err);
        expect(index.existsSync(), isTrue);
        expect(_records.existsSync(), isFalse);
      },
      skip: _linksUnavailable,
    );
  });
}
