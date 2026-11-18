import 'dart:convert';

import 'package:test/test.dart';

import '../../helpers/read_fixture.dart';

void main() {
  for (final (label, args) in [
    ('no target', ['context', '--for', 'implement', '--json']),
    ('no --for', ['context', 'login', '--json']),
  ]) {
    test(
      'context with $label gives the code argument_missing, exit 64',
      () async {
        final (:runner, :out, :err) = readRunner(await writeReadProject());
        expect(await runner.run(args), 64);
        final error = (jsonDecode(err.toString()) as Map)['error']! as Map;
        expect(error['code'], 'argument_missing');
      },
    );
  }
}
