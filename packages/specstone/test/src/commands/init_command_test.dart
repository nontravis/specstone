import 'dart:io';

import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

String _configLine() {
  final versions = shippedPackVersions();
  return 'created .specstone/config.yaml: '
      'prd-core ${versions['prd-core']}, '
      'software-tech ${versions['software-tech']}\n';
}

void main() {
  test("f06/us03/s2: an Agent's shell sets up the same files", () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);

    final status = await runner.run(['init']);

    expect(status, 0);
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith('created docs/prds/PROJECT.md (draft)\n'),
    );
    expect(out.toString(), endsWith(_configLine()));
    expect(
      File('${root.path}/.specstone/config.yaml').readAsStringSync(),
      shippedPinsConfig(),
    );
  });

  test(
    'f06/us03/fr02/e07: list --draft lists every doc init created',
    () async {
      final root = await writeTree({'keep.txt': 'x\n'});
      final (:runner, :out, :err) = writeRunner(root);
      await runner.run(['init']);
      expect(out.toString(), endsWith(_configLine()));

      final listed = writeRunner(root);
      final listRunner = listed.runner;
      final listOut = listed.out;
      final listErr = listed.err;
      for (final type in ['project', 'features', 'gnfr', 'tech_stack']) {
        expect(
          await listRunner.run(['list', type, '--draft']),
          0,
          reason: type,
        );
        expect(
          listOut.toString(),
          contains('$type ($type) — $type · draft · '),
        );
        listOut.clear();
      }
      expect(listErr.toString(), isEmpty);
    },
  );

  test('f06/us03/s5: init in a configured folder prints the config_exists '
      'line', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
    });
    final (:runner, :out, :err) = writeRunner(root);

    final status = await runner.run(['init']);

    expect(status, 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      '.specstone/config.yaml: this folder is already a Specstone project; '
      'run specstone migrate to upgrade its packs\n',
    );
  });

  test('f06/us03/fr01: init takes no argument', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['init', 'extra']), 64);
    expect(out.toString(), isEmpty);
  });
}
