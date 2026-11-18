import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

void main() {
  test('a url reference entry is shown as written and the guide opens no '
      'network connection', () async {
    final project = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      '.specstone/templates/note.yaml':
          'id: note\ndescription: A note.\npath: notes/{slug}.md\n'
          'reference:\n  - title: Soft delete\n    url: https://google.aip.dev/164\n',
    });
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = SpecstoneCommandRunner(
      out: out,
      err: err,
      templates: TemplateResolver(),
      workingDirectory: project,
      homeDirectory: await writeTree({}),
    );
    var connections = 0;

    final status = await IOOverrides.runZoned(
      () => runner.run(['guide', 'note']),
      socketConnect: (host, port, {sourceAddress, sourcePort = 0, timeout}) {
        connections++;
        throw const SocketException('no network in this test');
      },
    );

    expect(status, 0, reason: '$err');
    expect(out.toString(), contains('https://google.aip.dev/164'));
    expect(connections, 0);
  });
}
