import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

/// Records every path the code under test opens as a file, folder, or link,
/// or asks the type of.
final class _PathRecorder extends IOOverrides {
  final paths = <String>[];

  @override
  File createFile(String path) {
    paths.add(path);
    return super.createFile(path);
  }

  @override
  Directory createDirectory(String path) {
    paths.add(path);
    return super.createDirectory(path);
  }

  @override
  Link createLink(String path) {
    paths.add(path);
    return super.createLink(path);
  }

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) {
    paths.add(path);
    return super.fseGetTypeSync(path, followLinks);
  }
}

void main() {
  test('a command that loads no templates walks no folder, while guide walks '
      'to the project config', () async {
    final project = await writeTree({'.specstone/config.yaml': 'packs: [\n'});
    final home = await writeTree({});

    for (final (args, loadsTemplates) in [
      (['guide'], true),
      (['--version'], false),
      (['help'], false),
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
      final recorder = _PathRecorder();

      final status = await IOOverrides.runWithIOOverrides(
        () => runner.run(args),
        recorder,
      );

      final walked = recorder.paths.where(
        (path) => path.endsWith('config.yaml'),
      );
      if (loadsTemplates) {
        expect(status, 78, reason: '$args: $err');
        expect(walked, isNotEmpty, reason: '$args');
      } else {
        expect(status, 0, reason: '$args: $err');
        expect(walked, isEmpty, reason: '$args');
      }
    }
  });
}
