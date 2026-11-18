import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/built_cli.dart';

void main() {
  late String binary;
  late Directory project;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  setUp(() async {
    project = await writeCheckProject(
      extra: {'.specstone/config.yaml': shippedPinsOneMinorBelow('prd-core')},
    );
  });

  Future<ProcessResult> run(List<String> args) =>
      Process.run(binary, args, workingDirectory: project.path);

  const story = 'user_story:login/email_login';
  final forms = {
    'check': ['check', '--json'],
    'check <target>': ['check', story, '--json'],
    'check --repeats': ['check', '--repeats', '--json'],
    'context': ['context', story, '--for', 'implement', '--json'],
  };

  for (final MapEntry(:key, :value) in forms.entries) {
    test('$key refuses a pin one minor below the shipped pack', () async {
      final result = await run(value);
      final shipped = shippedPackVersions()['prd-core']!;

      expect(result.exitCode, 78, reason: '${result.stdout}\n${result.stderr}');
      final envelope =
          jsonDecode(result.stderr as String) as Map<String, Object?>;
      final error = envelope['error']! as Map<String, Object?>;
      expect(error['code'], 'pack_pin_older');
      expect(
        error['message'],
        allOf(
          contains('prd-core'),
          contains(shipped),
          contains(_oneMinorBelow(shipped)),
          contains('specstone migrate --dry-run'),
        ),
      );
      expect(error['file'], '.specstone/config.yaml');
      expect(error['key'], 'packs.prd-core');
    });
  }

  test('every --json form prints the same refusal message', () async {
    final messages = <String>{};
    for (final args in forms.values) {
      final result = await run(args);
      final envelope =
          jsonDecode(result.stderr as String) as Map<String, Object?>;
      messages.add(
        (envelope['error']! as Map<String, Object?>)['message']! as String,
      );
    }

    expect(messages, hasLength(1));
  });

  final textForms = {
    'check': ['check'],
    'context': ['context', story, '--for', 'implement'],
  };

  for (final MapEntry(:key, :value) in textForms.entries) {
    test('$key without --json refuses the older pin', () async {
      final result = await run(value);

      expect(result.exitCode, 78, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stderr,
        allOf(
          startsWith('.specstone/config.yaml: packs.prd-core: Pack prd-core'),
          contains('specstone migrate --dry-run'),
        ),
      );
    });
  }

  const loadFree = {
    '--version': ['--version'],
    '--help': ['--help'],
    'help': ['help'],
    'bare': <String>[],
  };

  test('--help, help, and a bare call answer with exit 0 beside a pack pin '
      'fault, since they load no template', () async {
    for (final MapEntry(:key, :value) in loadFree.entries) {
      if (key == '--version') continue;
      final result = await run(value);

      expect(
        result.exitCode,
        0,
        reason: '$key\n${result.stdout}\n${result.stderr}',
      );
      expect(result.stderr, isEmpty, reason: key);
      expect(result.stdout, isNotEmpty, reason: key);
    }
  });

  test('--version, --help, help, and a bare call answer with exit 0 beside a '
      'template fault, where check exits 78', () async {
    final broken = await writeCheckProject(
      extra: {'.specstone/config.yaml': 'packs: [prd-core\n'},
    );
    Future<ProcessResult> runIn(List<String> args) =>
        Process.run(binary, args, workingDirectory: broken.path);

    final refused = await runIn(['check', '--json']);
    expect(
      refused.exitCode,
      78,
      reason: '${refused.stdout}\n${refused.stderr}',
    );
    for (final MapEntry(:key, :value) in loadFree.entries) {
      final result = await runIn(value);

      expect(
        result.exitCode,
        0,
        reason: '$key\n${result.stdout}\n${result.stderr}',
      );
      expect(result.stderr, isEmpty, reason: key);
      expect(result.stdout, isNotEmpty, reason: key);
    }
  });

  final writeAndRenderForms = {
    'approve': ['approve', '--dry-run', '--json'],
    'delete': ['delete', story, '--json'],
    'move': ['move', story, 'login', '--json'],
    'new': ['new', 'user_story', '--parent', 'login', '--slug', 'x', '--json'],
    'rename': ['rename', story, '--to', 'other', '--json'],
    'reorder': ['reorder', story, '--json'],
    'set': ['set', '$story#use_case', '--base', '3f9a1c0b7e21', '--json'],
    'format': ['format', '--json'],
    'build': ['build', '--json'],
  };

  test('the document writing and rendering commands each refuse an older pin '
      'with pack_pin_older and exit 78', () async {
    for (final MapEntry(:key, :value) in writeAndRenderForms.entries) {
      final result = await run(value);

      expect(
        result.exitCode,
        78,
        reason: '$key\n${result.stdout}\n${result.stderr}',
      );
      final envelope =
          jsonDecode(result.stderr as String) as Map<String, Object?>;
      final error = envelope['error']! as Map<String, Object?>;
      expect(error['code'], 'pack_pin_older', reason: key);
    }
  });

  test('--version exits 0 on the same project', () async {
    final result = await run(['--version']);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}

String _oneMinorBelow(String version) {
  final [major, minor, _] = version.split('.');
  return '$major.${int.parse(minor) - 1}.0';
}
