import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../specstone_core/test/helpers/git_repo.dart' show commitAll;
import '../../specstone_core/test/helpers/project_shapes.dart';
import '../../specstone_core/test/helpers/shape_matrix.dart';
import '../../specstone_core/test/helpers/write_fixture.dart' show testHome;
import 'helpers/built_cli.dart';

const _story = 'user_story:login/email_login';

Future<ProcessResult> _spawn(
  String exe,
  Directory root,
  List<String> args, {
  String stdin = '',
}) async {
  final process = await Process.start(
    exe,
    args,
    workingDirectory: root.path,
    environment: {'HOME': testHome().path, 'USERPROFILE': testHome().path},
  );
  process.stdin.write(stdin);
  await process.stdin.close();
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  return ProcessResult(
    process.pid,
    await process.exitCode,
    await out,
    await err,
  );
}

Future<Set<String>> _kindsOf(String exe, Directory root) async {
  final run = await _spawn(exe, root, ['check', '--json']);
  final json = jsonDecode(run.stdout as String) as Map<String, Object?>;
  return {
    for (final finding in json['findings']! as List)
      (finding as Map<String, Object?>)['kind']! as String,
  };
}

Future<void> _run(
  String exe,
  Directory root,
  List<String> args, {
  String stdin = '',
}) async {
  final run = await _spawn(exe, root, args, stdin: stdin);
  expect(run.exitCode, 0, reason: '${args.join(' ')}: ${run.stderr}');
}

Future<Map<String, Object?>> _docOf(
  String exe,
  Directory root,
  String address,
) async {
  final run = await _spawn(exe, root, ['get', address, '--json']);
  final json = jsonDecode(run.stdout as String) as Map<String, Object?>;
  return (json['docs']! as List).first as Map<String, Object?>;
}

void main() {
  late String exe;
  late ProjectShape flat;

  setUpAll(() async {
    exe = await buildSpecstone();
    flat = (await projectShapes()).first;
  });

  // D8: each write command through the built binary adds only the waits its
  // doc names.
  for (final command in writeCommands) {
    test('$command through the built binary adds only content waits', () async {
      final root = await writeShapeTree(flat);
      if (command != 'format' && command != 'migrate') {
        // The shape's own layout lags, which `format` and `migrate` settle
        // themselves; formatted first, a stale doc after the write is the
        // write's.
        await _run(exe, root, ['format']);
        commitAll(root, 'format');
      }
      var destination = '';
      if (command == 'move') {
        await _run(exe, root, ['new', 'feature', '--slug', 'destination']);
        destination = 'feature:destination';
        final bases = (await _docOf(exe, root, destination))['bases']! as Map;
        await _run(exe, root, [
          'set',
          destination,
          '--field',
          'vision',
          '--base',
          (bases['fields']! as Map)['vision']! as String,
        ], stdin: '- PV-01\n');
        commitAll(root, 'set up move');
      }
      if (command == 'delete' || command == 'reorder') {
        await _run(exe, root, [
          'new',
          'user_story',
          '--parent',
          'feature:login',
          '--slug',
          'probe',
        ]);
        commitAll(root, 'set up $command');
      }
      final before = await _kindsOf(exe, root);

      switch (command) {
        case 'new':
          await _run(exe, root, [
            'new',
            'user_story',
            '--parent',
            'feature:login',
            '--slug',
            'probe',
          ]);
        case 'set':
          final doc = await _docOf(exe, root, '$_story#use_case');
          await _run(exe, root, [
            'set',
            '$_story#use_case',
            '--base',
            doc['base']! as String,
          ], stdin: doc['text']! as String);
        case 'move':
          await _run(exe, root, ['move', _story, '--under', destination]);
        case 'rename':
          await _run(exe, root, ['rename', _story, '--to', 'renamed_probe']);
        case 'format':
          await _run(exe, root, ['format']);
          final second = await _spawn(exe, root, ['format', '--check']);
          expect(second.exitCode, 0, reason: '${second.stdout}');
          expect(
            second.stdout,
            isEmpty,
            reason: 'a second format changes nothing',
          );
        case 'migrate':
          final dry = await _spawn(exe, root, ['migrate', '--dry-run']);
          expect(dry.exitCode, 0, reason: '${dry.stderr}');
          final plan = LineSplitter.split(dry.stdout as String)
              .firstWhere((line) => line.startsWith('plan '))
              .substring('plan '.length);
          await _run(exe, root, ['migrate', '--yes', '--plan', plan]);
        case 'approve':
          final doc = await _docOf(exe, root, _story);
          await _run(exe, root, ['approve', '$_story@${doc['base']}', '--yes']);
        case 'delete':
          await _run(exe, root, ['delete', 'user_story:login/probe']);
        case 'reorder':
          await _run(exe, root, [
            'reorder',
            'user_story:login/probe',
            '--to',
            '1',
          ]);
      }

      // D17: no write leaves a generated block stale.
      final listed = await _spawn(exe, root, ['format', '--check']);
      expect(listed.exitCode, 0, reason: '$command: ${listed.stdout}');

      // One spawn per command: kinds, not counts, so a new finding of a kind
      // `before` held shows in the in-process matrix only.
      final added = (await _kindsOf(exe, root)).difference(before);
      final allowed = {
        for (final kind in {
          ...allowedKinds[command]!,
          if (command == 'new') ...skeletonKinds,
        })
          kind.wire,
      };
      expect(added.difference(allowed), isEmpty);
    });
  }
}
