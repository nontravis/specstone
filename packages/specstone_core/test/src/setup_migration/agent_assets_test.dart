import 'dart:io';

import 'package:specstone_core/src/setup_migration/agent_assets.dart';
import 'package:test/test.dart';

import '../../helpers/package_root.dart';

void main() {
  group('shippedAgentAssets', () {
    final assets = shippedAgentAssets();
    final paths = [for (final asset in assets) asset.path];

    test('holds each skill and each agent file', () {
      for (final skill in [
        'bootstrap-prd',
        'bootstrap-spec',
        'brainstorming-sdd',
        'expert-sdd',
        'init',
        'plan-sdd',
        'read-sdd',
        'sync-sdd',
        'update-sdd',
      ]) {
        expect(paths, contains('specstone-$skill/SKILL.md'));
      }
      expect(
        paths,
        containsAll([
          'specstone-plan-engineer.md',
          'specstone-sdd-auditor.md',
          'specstone-sdd-engineer.md',
          'specstone-sdd-reader.md',
        ]),
      );
    });

    test('holds every file on disk under assets/agent but AGENT.md', () {
      final base = packageRoot().uri.resolve('assets/agent/');
      final onDisk = [
        for (final file in Directory.fromUri(
          base,
        ).listSync(recursive: true).whereType<File>())
          file.uri.path.substring(base.path.length),
      ]..remove('AGENT.md');
      expect(paths, unorderedEquals(onDisk));
    });

    test('leaves out AGENT.md', () {
      expect(paths, isNot(contains('AGENT.md')));
    });

    test('is sorted by path in code point order', () {
      expect(paths, [...paths]..sort());
    });

    test('no shipped skill file asks for a design_references row', () {
      for (final asset in assets) {
        expect(
          asset.text,
          isNot(contains('design_references')),
          reason: asset.path,
        );
      }
    });

    test('decodes each file to LF text', () {
      for (final asset in assets) {
        expect(asset.text, isNotEmpty, reason: asset.path);
        expect(asset.text, isNot(contains('\r')), reason: asset.path);
      }
    });
  });
}
