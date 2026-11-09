import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:test/test.dart';

import '../../specstone_core/test/helpers/relative_link.dart';
import '../../specstone_core/test/helpers/temp_tree.dart';
import '../../specstone_core/test/helpers/write_fixture.dart';
import 'helpers/write_runner.dart';

const _gate = 'document_writing/delete_doc_subtree/finish_interrupted_move';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

const _new = [
  'new',
  'user_story',
  '--parent',
  'login',
  '--slug',
  'forgot_email',
];

/// The commands that open the index, as an Owner or an Agent runs them; [base]
/// is the current base of the use case of the login story.
Map<String, List<String>> _commands(String base) => {
  'check': ['check'],
  'context': ['context', 'login/email_login', '--for', 'implement'],
  'get': ['get', 'user_story:login/email_login'],
  'set': ['set', 'user_story:login/email_login#use_case', '--base', base],
  'new': _new,
};

/// Returns every entry under [root] as text: a file by its bytes, a link by
/// its target, a folder by its name; nothing is followed.
Map<String, String> _snapshot(Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return {
    for (final entity in root.listSync(recursive: true, followLinks: false))
      entity.path.substring(prefix.length): switch (entity) {
        File() => 'file:${base64Encode(entity.readAsBytesSync())}',
        Link() => 'link:${entity.targetSync()}',
        _ => 'dir',
      },
  };
}

/// Runs [args] on [root] and returns the exit status and what it printed.
Future<(int, String)> _run(Directory root, List<String> args) async {
  final (:runner, :out, :err) = writeRunner(
    root,
    console: FakeConsole(input: 'x\n', stdinIsTerminal: args.first == 'new'),
  );
  final status = await runner.run([...args, '--json']);
  return (status, '$out$err');
}

void main() {
  group('$_gate: a committed link at .specstone/index.sqlite', () {
    late Directory outside;
    late Directory root;
    late Map<String, List<String>> commands;

    setUp(() async {
      root = await writeWriteProject();
      outside = await writeTree({'keep.txt': 'mine\n'});
      final base =
          ((getDoc(root, 'user_story:login/email_login')['bases']!
                      as Map)['sections']!
                  as Map)['use_case']!
              as String;
      commands = _commands(base);
      for (final name in ['index.sqlite', '.gitignore']) {
        File('${root.path}/.specstone/$name').deleteSync();
      }
    });

    for (final key in _commands('').keys) {
      test('$_gate E08: $key refuses 73 when the link leads to a path that '
          'does not exist outside the project', () async {
        final target = File('${outside.path}/not-yet.sqlite');
        Link('${root.path}/.specstone/index.sqlite').createSync(target.path);
        final before = _snapshot(outside);

        final (status, printed) = await _run(root, commands[key]!);

        expect(status, 73, reason: printed);
        expect(
          (jsonDecode(printed) as Map)['error'],
          containsPair('code', 'output_not_writable'),
        );
        expect(_snapshot(outside), before);
        expect(target.existsSync(), isFalse);
      }, skip: _linksUnavailable);

      test('$_gate E08: $key refuses 73 when the link leads to a valid index '
          'outside the project, and the index keeps its bytes', () async {
        IndexStore.open(root).close();
        final index = File('${root.path}/.specstone/index.sqlite');
        final copy = index.copySync('${outside.path}/copy.sqlite');
        index.deleteSync();
        Link(index.path).createSync(copy.path);
        final before = _snapshot(outside);

        final (status, printed) = await _run(root, commands[key]!);

        expect(status, 73, reason: printed);
        expect(_snapshot(outside), before);
      }, skip: _linksUnavailable);

      test('$_gate E08: $key refuses 73 when .specstone/.gitignore is a '
          'link out of the project', () async {
        final victim = File('${outside.path}/keep.txt');
        Link('${root.path}/.specstone/.gitignore').createSync(victim.path);
        final before = _snapshot(outside);

        final (status, printed) = await _run(root, commands[key]!);

        expect(status, 73, reason: printed);
        expect(_snapshot(outside), before);
      }, skip: _linksUnavailable);
    }
  });

  group('$_gate: other writes that lead out or into .git', () {
    late Directory outside;
    late Directory root;

    setUp(() async {
      root = await writeWriteProject();
      outside = await writeTree({'keep.txt': 'mine\n', 'doc/keep.md': 'k\n'});
    });

    test('$_gate E08: build refuses 73 when .specstone/build is a link out '
        'of the project', () async {
      Link('${root.path}/.specstone/build').createSync(outside.path);
      final before = _snapshot(outside);

      final (status, printed) = await _run(root, [
        'build',
        'docs/$loginFeature',
      ]);

      expect(status, 73, reason: printed);
      expect(_snapshot(outside), before);
    }, skip: _linksUnavailable);

    test('$_gate E08: build refuses 73 when .specstone/build is a link into '
        '.git', () async {
      Directory('${root.path}/.git/hooks').createSync(recursive: true);
      Link('${root.path}/.specstone/build').createSync('../.git/hooks');

      final (status, printed) = await _run(root, [
        'build',
        'docs/$loginFeature',
      ]);

      expect(status, 73, reason: printed);
      expect(Directory('${root.path}/.git/hooks').listSync(), isEmpty);
    }, skip: _linksUnavailable);

    test('$_gate E08: new refuses 73 when its doc folder is a link out of '
        'the project', () async {
      const folder = 'prds/features/f01_login/us04_forgot_email';
      Link('${root.path}/docs/$folder').createSync('${outside.path}/doc');
      final before = _snapshot(outside);

      final (status, printed) = await _run(root, _new);

      expect(status, 73, reason: printed);
      expect(_snapshot(outside), before);
    }, skip: _linksUnavailable);
  });

  group('$_gate: the layout of a docs link to a folder beside the project', () {
    test('$_gate E08: new and check still write', () async {
      final base = await writeTree({
        '.keep': '',
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/'))
            'ext/${key.substring(5)}': value
          else
            'proj/$key': value,
      });
      createRelativeLink('${base.path}/proj/docs', '../ext');
      final project = Directory('${base.path}/proj');

      final (newStatus, newPrinted) = await _run(project, _new);
      final (checkStatus, checkPrinted) = await _run(project, ['check']);

      expect(newStatus, 0, reason: newPrinted);
      expect(checkStatus, anyOf(0, 1), reason: checkPrinted);
      expect(
        Directory('${base.path}/ext/prds/features/f01_login')
            .listSync()
            .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty)),
        contains(contains('forgot_email')),
      );
    }, skip: _linksUnavailable);
  });
}
