import 'dart:io';

import 'package:test/test.dart';

import '../../helpers/read_fixture.dart';

void main() {
  test('context --out exits 0 with no message when an aged bundle file cannot '
      'be deleted, and prunes the others', () async {
    final project = await writeReadProject();
    final aged = DateTime.now().subtract(const Duration(days: 2));
    File aging(String path) => File('${project.path}/.specstone/bundles/$path')
      ..createSync(recursive: true)
      ..setLastModifiedSync(aged)
      ..setLastAccessedSync(aged);
    final locked = aging('locked/old.txt');
    final other = aging('old.txt');
    await Process.run('chmod', ['555', locked.parent.path]);
    addTearDown(() => Process.run('chmod', ['755', locked.parent.path]));
    final (:runner, :out, :err) = readRunner(project);

    final status = await runner.run([
      'context',
      'login/email_login',
      '--for',
      'implement',
      '--out',
    ]);

    expect(status, 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), isNot(contains('old.txt')));
    expect(locked.existsSync(), isTrue);
    expect(other.existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'a read-only folder is a POSIX rule' : null);
}
