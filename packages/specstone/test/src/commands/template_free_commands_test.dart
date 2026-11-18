import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

void main() {
  test('a command that loads no templates reads no project config, so a '
      'broken config faults guide and not version or help', () async {
    final project = await writeTree({'.specstone/config.yaml': 'packs: [\n'});
    final home = await writeTree({});

    for (final (args, status) in [
      (['guide'], 78),
      (['--version'], 0),
      (['help'], 0),
    ]) {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = SpecstoneCommandRunner(
        out: out,
        err: err,
        templates: TemplateResolver(),
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(await runner.run(args), status, reason: '$args: $err');
      if (status == 0) {
        expect(err.toString(), isEmpty, reason: '$args');
        expect(out.toString(), isNotEmpty, reason: '$args');
      }
    }
  });
}
