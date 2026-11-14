import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/relative_link.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/temp_tree.dart';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

String _folderOf(Directory root) =>
    '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}.specstone';

Map<String, String> _project() => {
  '.specstone/config.yaml': shippedPinsConfig(),
  'app/lib/main.dart': '',
};

void main() {
  late String binary;

  setUpAll(() async => binary = await buildSpecstone());

  Future<ProcessResult> run(String cwd, [List<String> args = const []]) =>
      Process.run(binary, ['folder', ...args], workingDirectory: cwd);

  group('folder', () {
    test('f01/us08/fr01/e01: run at the project root prints the absolute '
        '.specstone path and exits 0', () async {
      final root = await writeTree(_project());

      final result = await run(root.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, '${_folderOf(root)}\n');
      expect(result.stderr, isEmpty);
    });

    test('f01/us08/fr01/e02: run in a nested folder prints the same line '
        'the root gets', () async {
      final root = await writeTree(_project());

      final nested = await run('${root.path}/app/lib');

      expect(nested.exitCode, 0, reason: '${nested.stderr}');
      expect(nested.stdout, '${_folderOf(root)}\n');
      expect(nested.stdout, (await run(root.path)).stdout);
    });

    test('f01/us08/fr01/e03: a folder whose docs link stands for another '
        "project prints that project's .specstone", () async {
      final tree = await writeTree({
        'ws/.specstone/config.yaml': shippedPinsConfig(),
        'ws/example/.specstone/config.yaml': shippedPinsConfig(),
        'ws/example/docs/prds/FEATURES.md': '# Features\n',
        'ws/code/example/keep.txt': '',
      });
      createRelativeLink(
        '${tree.path}/ws/code/example/docs',
        '../../example/docs',
      );

      final result = await run('${tree.path}/ws/code/example');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        '${_folderOf(Directory('${tree.path}/ws/example'))}\n',
      );
    }, skip: _linksUnavailable);

    test('f01/us08/fr01/e04: a missing reports/ is made before the path '
        'prints', () async {
      final root = await writeTree(_project());
      final reports = Directory('${root.path}/.specstone/reports');
      expect(reports.existsSync(), isFalse);

      final first = await run(root.path);
      final second = await run(root.path);

      expect(first.exitCode, 0, reason: '${first.stderr}');
      expect(reports.existsSync(), isTrue);
      expect(second.exitCode, 0, reason: '${second.stderr}');
      expect(second.stdout, first.stdout);
    });

    test('f01/us08/fr01/e05: a reports/ that cannot be made is '
        'output_not_writable, exit 73, with nothing on stdout', () async {
      final root = await writeTree({
        ..._project(),
        '.specstone/reports': 'a file where the folder goes',
      });

      final result = await run(root.path);

      expect(result.exitCode, 73);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('cannot make'));
    });

    test('f01/us08/fr01/e05: --json prints the error envelope on stderr, '
        'nothing on stdout', () async {
      final root = await writeTree({
        ..._project(),
        '.specstone/reports': 'a file where the folder goes',
      });

      final result = await run(root.path, ['--json']);

      expect(result.exitCode, 73);
      expect(result.stdout, isEmpty);
      final error =
          (jsonDecode(result.stderr as String) as Map)['error']! as Map;
      expect(error['code'], 'output_not_writable');
    });

    test('f01/us08/fr01/e06: no project above the working directory is '
        'project_not_found, exit 78', () async {
      final bare = await writeTree({'lib/main.dart': ''});

      final result = await run('${bare.path}/lib');

      expect(result.exitCode, 78, reason: '${result.stderr}');
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('no Specstone project'));
    });

    test('f01/us08/fr01/e06: --json names project_not_found', () async {
      final bare = await writeTree({'lib/main.dart': ''});

      final result = await run(bare.path, ['--json']);

      expect(result.exitCode, 78);
      final error =
          (jsonDecode(result.stderr as String) as Map)['error']! as Map;
      expect(error['code'], 'project_not_found');
    });

    test('f01/us08/fr01/e07: a .specstone link is unknown_value, exit 78, '
        'and makes no reports/', () async {
      final tree = await writeTree({
        'real/config.yaml': shippedPinsConfig(),
        'proj/keep.txt': '',
      });
      createRelativeLink('${tree.path}/proj/.specstone', '../real');

      final result = await run('${tree.path}/proj', ['--json']);

      expect(result.exitCode, 78, reason: '${result.stderr}');
      expect(result.stdout, isEmpty);
      final error =
          (jsonDecode(result.stderr as String) as Map)['error']! as Map;
      expect(error['code'], 'unknown_value');
      expect(error['file'], '.specstone');
      expect(Directory('${tree.path}/real/reports').existsSync(), isFalse);
    }, skip: _linksUnavailable);

    test('f01/us08/fr01/e08: a positional argument is argument_invalid, '
        'exit 64', () async {
      final root = await writeTree(_project());

      final result = await run(root.path, ['login', '--json']);

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      final error =
          (jsonDecode(result.stderr as String) as Map)['error']! as Map;
      expect(error['code'], 'argument_invalid');
      expect(
        Directory('${root.path}/.specstone/reports').existsSync(),
        isFalse,
      );
    });

    test(
      'f01/us08/fr01/e09: --json prints {"folder": ...} on stdout',
      () async {
        final root = await writeTree(_project());

        final result = await run('${root.path}/app', ['--json']);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(jsonDecode(result.stdout as String), {
          'folder': _folderOf(root),
        });
        expect(result.stderr, isEmpty);
      },
    );

    test('f01/us08/fr01/e10: it reads no config and opens no index, so a '
        'config no read accepts still prints and the folder gains only '
        'reports/', () async {
      final root = await writeTree({
        '.specstone/config.yaml': 'unknown_key: 1\n',
      });

      final result = await run(root.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, '${_folderOf(root)}\n');
      final names = {
        for (final entity in Directory('${root.path}/.specstone').listSync())
          entity.uri.pathSegments.where((s) => s.isNotEmpty).last,
      };
      expect(names, {'config.yaml', 'reports'});
    });
  });
}
