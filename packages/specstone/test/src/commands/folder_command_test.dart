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

/// [text] as it sits inside a JSON string, with backslashes escaped.
String _inJson(String text) {
  final encoded = jsonEncode(text);
  return encoded.substring(1, encoded.length - 1);
}

Map<String, String> _project() => {
  '.specstone/config.yaml': shippedPinsConfig(),
  'app/lib/main.dart': '',
};

void main() {
  late String binary;

  setUpAll(() async => binary = await buildSpecstone());

  Future<ProcessResult> run(String cwd, [List<String> args = const []]) =>
      runSpecstone(binary, ['folder', ...args], workingDirectory: cwd);

  group('folder', () {
    test('run at the project root prints the absolute '
        '.specstone path and exits 0', () async {
      final root = await writeTree(_project());

      final result = await run(root.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, '${_folderOf(root)}\n');
      expect(result.stderr, isEmpty);
    });

    test('--out saves the path line and prints only its header', () async {
      final root = await writeTree(_project());

      final result = await run(root.path, ['--out']);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final file = File('${_folderOf(root)}/reports/folder.all.txt');
      expect(file.readAsStringSync(), '${_folderOf(root)}\n');
      expect(
        result.stdout,
        matches(RegExp(r'^==> folder: 1 lines, \d+ tokens · .+ <==\n$')),
      );
      expect(result.stdout, contains(file.resolveSymbolicLinksSync()));
      expect(result.stderr, isEmpty);
    });

    test('--json --out saves the JSON reply and prints only '
        '{out, lines, tokens, warnings}', () async {
      final root = await writeTree(_project());
      final plain = await run(root.path, ['--json']);

      final result = await run(root.path, ['--json', '--out']);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final file = File('${_folderOf(root)}/reports/folder.all.json');
      expect(file.readAsStringSync(), plain.stdout);
      final printed =
          jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(printed.keys.toList(), ['out', 'lines', 'tokens', 'warnings']);
      expect(printed['out'], file.resolveSymbolicLinksSync());
      expect(result.stderr, isEmpty);
    });

    test('a missing reports/ is made before the path '
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

    test('a reports/ that cannot be made is '
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

    test('--json prints the error envelope on stderr, '
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

    test('no project above the working directory is '
        'project_not_found, exit 78', () async {
      final bare = await writeTree({'lib/main.dart': ''});

      final result = await run('${bare.path}/lib');

      expect(result.exitCode, 78, reason: '${result.stderr}');
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('no Specstone project'));
    });

    test('a .specstone link is unknown_value, exit 78, '
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

    test('folder refuses a linked config.yaml with exit 78', () async {
      final tree = await writeTree({
        'real/config.yaml': shippedPinsConfig(),
        'proj/.specstone/keep.txt': '',
      });
      createRelativeLink(
        '${tree.path}/proj/.specstone/config.yaml',
        '../../real/config.yaml',
      );

      final result = await run('${tree.path}/proj');

      expect(result.exitCode, 78, reason: '${result.stderr}');
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('.specstone/config.yaml'));
      expect(result.stderr, contains('not a link'));
    }, skip: _linksUnavailable);

    test('a positional argument is argument_invalid, '
        'exit 64', () async {
      final root = await writeTree(_project());

      final result = await run(root.path, ['login', '--json']);

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      final error =
          (jsonDecode(result.stderr as String) as Map)['error']! as Map;
      expect(error['code'], 'argument_invalid');
      expect(error['message'], 'folder takes no argument: login');
      expect(
        Directory('${root.path}/.specstone/reports').existsSync(),
        isFalse,
      );
    });

    test('--json prints folder and an empty warnings array', () async {
      final root = await writeTree(_project());

      final result = await run('${root.path}/app', ['--json']);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(jsonDecode(result.stdout as String), {
        'folder': _folderOf(root),
        'warnings': <Object>[],
      });
      expect(result.stderr, isEmpty);
    });

    test('--json outside a project names project_not_found and carries '
        'warnings', () async {
      final bare = await writeTree({'lib/main.dart': ''});

      final result = await run(bare.path, ['--json']);

      expect(result.exitCode, 78);
      final envelope = jsonDecode(result.stderr as String) as Map;
      expect((envelope['error']! as Map)['code'], 'project_not_found');
      expect(envelope['warnings'], <Object>[]);
    });

    test('it loads no templates and opens no index, so a '
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

    test('a .specstone regular file below a project lets the search go '
        'upward to that project', () async {
      final root = await writeTree({..._project(), 'app/.specstone': 'x'});

      final result = await run('${root.path}/app/lib');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, '${_folderOf(root)}\n');
      expect(File('${root.path}/app/.specstone').readAsStringSync(), 'x');
    });

    test('a .specstone regular file with no project '
        'above it is project_not_found, exit 78', () async {
      final tree = await writeTree({'.specstone': 'x', 'lib/main.dart': ''});

      final result = await run('${tree.path}/lib', ['--json']);

      expect(result.exitCode, 78, reason: '${result.stderr}');
      expect(result.stdout, isEmpty);
      final error =
          (jsonDecode(result.stderr as String) as Map)['error']! as Map;
      expect(error['code'], 'project_not_found');
      expect(File('${tree.path}/.specstone').readAsStringSync(), 'x');
    });
  });

  group('folder prunes', () {
    /// Writes [path] under [root], last modified [modified] ago and last
    /// read [read] ago (the same as [modified] by default), and returns it.
    File aged(
      Directory root,
      String path,
      Duration modified, {
      Duration? read,
    }) {
      final now = DateTime.now();
      return File('${root.path}/$path')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('old\n')
        ..setLastModifiedSync(now.subtract(modified))
        ..setLastAccessedSync(now.subtract(read ?? modified));
    }

    test('a report last used 8 days ago and a bundle last used 2 days ago '
        'are gone, and stdout holds the folder line alone', () async {
      final root = await writeTree(_project());
      final report = aged(
        root,
        '.specstone/reports/old.txt',
        const Duration(days: 8),
      );
      final bundle = aged(
        root,
        '.specstone/bundles/old.txt',
        const Duration(days: 2),
      );
      final fresh = aged(
        root,
        '.specstone/reports/fresh.txt',
        const Duration(minutes: 1),
      );

      final result = await run(root.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, '${_folderOf(root)}\n');
      expect(result.stderr, isEmpty);
      expect(report.existsSync(), isFalse);
      expect(bundle.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('a refused run, a positional argument or a reports/ that cannot be '
        'made, keeps every aged file', () async {
      final refusedArgument = await writeTree(_project());
      final report = aged(
        refusedArgument,
        '.specstone/reports/old.txt',
        const Duration(days: 8),
      );
      final bundle = aged(
        refusedArgument,
        '.specstone/bundles/old.txt',
        const Duration(days: 2),
      );
      final blocked = await writeTree({
        ..._project(),
        '.specstone/reports': 'a file where the folder goes',
      });
      final blockedBundle = aged(
        blocked,
        '.specstone/bundles/old.txt',
        const Duration(days: 2),
      );

      final argument = await run(refusedArgument.path, ['login']);
      final unwritable = await run(blocked.path);

      expect(argument.exitCode, 64);
      expect(unwritable.exitCode, 73);
      expect(report.existsSync(), isTrue);
      expect(bundle.existsSync(), isTrue);
      expect(blockedBundle.existsSync(), isTrue);
    });

    test('--json stdout of a run that prunes equals that of a run with '
        'nothing to prune', () async {
      final pruning = await writeTree(_project());
      final report = aged(
        pruning,
        '.specstone/reports/old.txt',
        const Duration(days: 8),
      );
      final idle = await writeTree(_project());

      final pruned = await run(pruning.path, ['--json']);
      final unpruned = await run(idle.path, ['--json']);

      expect(report.existsSync(), isFalse);
      expect(pruned.exitCode, 0, reason: '${pruned.stderr}');
      expect(jsonDecode(pruned.stdout as String), {
        'folder': _folderOf(pruning),
        'warnings': <Object>[],
      });
      expect(
        (pruned.stdout as String).replaceAll(_inJson(_folderOf(pruning)), ''),
        (unpruned.stdout as String).replaceAll(_inJson(_folderOf(idle)), ''),
      );
    });

    test('a cleanup map in the config keeps a report the default would '
        'delete', () async {
      final root = await writeTree({
        ..._project(),
        '.specstone/config.yaml':
            '${shippedPinsConfig()}cleanup:\n  reports_max_age_days: 30\n',
      });
      final report = aged(
        root,
        '.specstone/reports/old.txt',
        const Duration(days: 10),
      );

      final result = await run(root.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(report.existsSync(), isTrue);
    });
  });
}
