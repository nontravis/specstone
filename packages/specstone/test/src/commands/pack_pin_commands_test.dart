@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/templates/pack_floors.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/version.dart';
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
      extra: {'.specstone/config.yaml': shippedPinsBelowFloor()},
    );
  });

  Future<ProcessResult> run(List<String> args) =>
      runSpecstone(binary, args, workingDirectory: project.path);

  const story = 'user_story:login/email_login';
  final forms = {
    'check': ['check', '--json'],
    'check <target>': ['check', story, '--json'],
    'check --repeats': ['check', '--repeats', '--json'],
    'context': ['context', story, '--for', 'implement', '--json'],
    'guide': ['guide', 'feature', '--json'],
  };

  for (final MapEntry(:key, :value) in forms.entries) {
    test('$key refuses a pin one minor below its floor', () async {
      final result = await run(value);
      final floor = _floor.toString();

      expect(result.exitCode, 78, reason: '${result.stdout}\n${result.stderr}');
      final envelope =
          jsonDecode(result.stderr as String) as Map<String, Object?>;
      final error = envelope['error']! as Map<String, Object?>;
      expect(error['code'], 'pack_pin_below_floor');
      expect(
        error['message'],
        allOf(
          contains('prd-core'),
          contains(floor),
          contains(_oneMinorBelow(floor)),
          contains(specstoneVersion),
          contains('migrate the project with Specstone 2.0.x first'),
        ),
      );
      expect(error['file'], '.specstone/config.yaml');
      expect(error['key'], 'packs.prd-core');
    });
  }

  final textForms = {
    'check': ['check'],
    'context': ['context', story, '--for', 'implement'],
  };

  for (final MapEntry(:key, :value) in textForms.entries) {
    test('$key without --json refuses the below-floor pin', () async {
      final result = await run(value);

      expect(result.exitCode, 78, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stderr,
        allOf(
          startsWith('.specstone/config.yaml: packs.prd-core: prd-core '),
          contains('migrate the project with Specstone 2.0.x first'),
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

  test('--version, --help, help, and a bare call answer with exit 0 beside a '
      'template fault, where check exits 78', () async {
    final broken = await writeCheckProject(
      extra: {'.specstone/config.yaml': 'packs: [prd-core\n'},
    );
    Future<ProcessResult> runIn(List<String> args) =>
        runSpecstone(binary, args, workingDirectory: broken.path);

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

  test('the document writing and rendering commands each refuse a pin below '
      'its floor with pack_pin_below_floor and exit 78', () async {
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
      expect(error['code'], 'pack_pin_below_floor', reason: key);
      expect(error['file'], '.specstone/config.yaml', reason: key);
      expect(error['key'], 'packs.prd-core', reason: key);
      expect(
        error['message'],
        contains('migrate the project with Specstone 2.0.x first'),
        reason: key,
      );
    }
  });

  test('a below-floor pin leaves every path and byte of the project as it '
      'was', () async {
    final before = _snapshot(project);

    for (final args in [
      writeAndRenderForms['format']!,
      writeAndRenderForms['set']!,
    ]) {
      final result = await run(args);
      expect(result.exitCode, 78, reason: '${result.stdout}\n${result.stderr}');
    }

    expect(_snapshot(project), before);
  });
}

String _oneMinorBelow(String version) {
  final [major, minor, _] = version.split('.');
  return '$major.${int.parse(minor) - 1}.0';
}

/// Maps each path under [root] to its bytes, a folder to null.
Map<String, List<int>?> _snapshot(Directory root) => {
  for (final entity in root.listSync(recursive: true, followLinks: false))
    entity.path: entity is File ? entity.readAsBytesSync() : null,
};

final PackVersion _floor = PackFloors.shipped.byPack['prd-core']!;
