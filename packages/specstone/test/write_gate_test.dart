import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../specstone_core/test/helpers/temp_tree.dart';
import '../../specstone_core/test/helpers/write_fixture.dart';
import 'helpers/write_runner.dart';

const _gate = 'document_writing/delete_doc_subtree/finish_interrupted_move';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

/// The commands that open the index and the path they refuse.
const _commands = {
  'check': ['check'],
  'new': ['new', 'user_story', '--parent', 'login', '--slug', 'forgot_email'],
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

    setUp(() async {
      root = await writeWriteProject();
      outside = await writeTree({'keep.txt': 'mine\n'});
    });

    for (final MapEntry(:key, :value) in _commands.entries) {
      test('$_gate: $key refuses 73 when the link leads to a path that '
          'does not exist outside the project, and creates nothing', () async {
        final target = File('${outside.path}/not-yet.sqlite');
        Link('${root.path}/.specstone/index.sqlite').createSync(target.path);
        final before = _snapshot(outside);

        final (status, printed) = await _run(root, value);

        expect(status, 73, reason: printed);
        expect(
          (jsonDecode(printed) as Map)['error'],
          containsPair('code', 'output_not_writable'),
        );
        expect(_snapshot(outside), before);
        expect(target.existsSync(), isFalse);
      }, skip: _linksUnavailable);
    }
  });
}
