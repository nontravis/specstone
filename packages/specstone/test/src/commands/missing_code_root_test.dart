import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test('every read command works in a checkout with no code folder, and check '
      'reports the code paths that do not resolve', () async {
    final root = await writeCheckProject();
    Directory('${root.path}/app').deleteSync(recursive: true);

    for (final args in [
      ['list', 'user_story'],
      ['get', 'user_story:login/email_login#use_case'],
      ['search', 'email'],
      ['context', 'user_story:login/email_login', '--for', 'implement'],
    ]) {
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(args), 0, reason: '$args: $err');
      expect(err.toString(), isEmpty, reason: '$args');
      expect(out.toString(), isNotEmpty, reason: '$args');
    }

    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['check']), 1, reason: '$err');
    expect(out.toString(), contains('covers_path_missing'));
    expect(out.toString(), contains('app/lib/ names nothing on disk'));
  });
}
