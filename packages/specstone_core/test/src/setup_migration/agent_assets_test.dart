import 'package:specstone_core/src/setup_migration/agent_assets.dart';
import 'package:test/test.dart';

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
          'specstone-sdd-engineer.md',
          'specstone-sdd-reader.md',
          'specstone-sdd-sweeper.md',
        ]),
      );
    });

    test('leaves out AGENT.md', () {
      expect(paths, isNot(contains('AGENT.md')));
    });

    test('is sorted by path in code point order', () {
      expect(paths, [...paths]..sort());
    });

    test('decodes each file to LF text', () {
      for (final asset in assets) {
        expect(asset.text, isNotEmpty, reason: asset.path);
        expect(asset.text, isNot(contains('\r')), reason: asset.path);
      }
    });
  });
}
