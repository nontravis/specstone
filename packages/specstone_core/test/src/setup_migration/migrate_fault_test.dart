import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:test/test.dart';

void main() {
  group('MigrateFaultCode', () {
    test('working_tree_dirty exits 75', () {
      expect(MigrateFaultCode.workingTreeDirty.wire, 'working_tree_dirty');
      expect(MigrateFaultCode.workingTreeDirty.exitStatus, 75);
    });

    test('git_work_tree_required exits 78', () {
      expect(
        MigrateFaultCode.gitWorkTreeRequired.wire,
        'git_work_tree_required',
      );
      expect(MigrateFaultCode.gitWorkTreeRequired.exitStatus, 78);
    });

    test('group_slug_duplicate exits 65', () {
      expect(MigrateFaultCode.groupSlugDuplicate.wire, 'group_slug_duplicate');
      expect(MigrateFaultCode.groupSlugDuplicate.exitStatus, 65);
    });

    test('upgrade_collision exits 65', () {
      expect(MigrateFaultCode.upgradeCollision.wire, 'upgrade_collision');
      expect(MigrateFaultCode.upgradeCollision.exitStatus, 65);
    });

    test('override_dangling exits 78', () {
      expect(MigrateFaultCode.overrideDangling.wire, 'override_dangling');
      expect(MigrateFaultCode.overrideDangling.exitStatus, 78);
    });

    test('config_exists exits 64', () {
      expect(MigrateFaultCode.configExists.wire, 'config_exists');
      expect(MigrateFaultCode.configExists.exitStatus, 64);
    });

    test('git_failed exits 75', () {
      expect(MigrateFaultCode.gitFailed.wire, 'git_failed');
      expect(MigrateFaultCode.gitFailed.exitStatus, 75);
    });

    test('ms-r11: plan_mismatch exits 75', () {
      expect(MigrateFaultCode.planMismatch.wire, 'plan_mismatch');
      expect(MigrateFaultCode.planMismatch.exitStatus, 75);
    });

    test('E05: '
        'agent_block_malformed exits 65', () {
      expect(
        MigrateFaultCode.agentBlockMalformed.wire,
        'agent_block_malformed',
      );
      expect(MigrateFaultCode.agentBlockMalformed.exitStatus, 65);
    });

    test('legacy_collision exits 65', () {
      expect(MigrateFaultCode.legacyCollision.wire, 'legacy_collision');
      expect(MigrateFaultCode.legacyCollision.exitStatus, 65);
    });
  });

  group('MigrateFault', () {
    test('setup_migration error envelope: a fault with a line prints '
        '<file>:<line>: <message> and carries line in its JSON', () {
      final fault = MigrateFault(
        MigrateFaultCode.agentBlockMalformed,
        'a',
        file: 'CLAUDE.md',
        line: 4,
        more: [
          MigrateFault(
            MigrateFaultCode.agentBlockMalformed,
            'b',
            file: 'AGENTS.md',
            line: 9,
          ),
        ],
      );

      expect(fault.toText(), 'CLAUDE.md:4: a\nAGENTS.md:9: b');
      expect(fault.toJson(), {
        'error': {
          'code': 'agent_block_malformed',
          'message': 'a',
          'file': 'CLAUDE.md',
          'line': 4,
        },
      });
      expect(fault.exitStatus, 65);
    });

    test('a fault with more entries prints one line '
        'each', () {
      final fault = MigrateFault(
        MigrateFaultCode.overrideDangling,
        'a',
        file: 'x.yaml',
        key: 'sections.s',
        more: [
          MigrateFault(
            MigrateFaultCode.overrideDangling,
            'b',
            file: 'y.yaml',
            key: 'fields.f',
          ),
        ],
      );

      expect(fault.toText(), 'x.yaml: sections.s: a\ny.yaml: fields.f: b');
    });

    test('a fault without a file prints the message '
        'alone', () {
      final fault = MigrateFault(MigrateFaultCode.workingTreeDirty, 'dirty');

      expect(fault.toText(), 'dirty');
      expect(fault.exitStatus, 75);
    });

    test('related files follow the located form', () {
      final fault = MigrateFault(
        MigrateFaultCode.groupSlugDuplicate,
        'twice',
        file: 'a.md',
        relatedFiles: ['b.md', 'c.md'],
      );

      expect(fault.toText(), 'a.md: twice; also b.md, c.md');
    });

    test('the envelope carries the first entry only', () {
      final fault = MigrateFault(
        MigrateFaultCode.overrideDangling,
        'a',
        file: 'x.yaml',
        key: 'sections.s',
        relatedFiles: ['z.md'],
        more: [MigrateFault(MigrateFaultCode.overrideDangling, 'b')],
      );

      expect(fault.toJson(), {
        'error': {
          'code': 'override_dangling',
          'message': 'a',
          'file': 'x.yaml',
          'key': 'sections.s',
          'relatedFiles': ['z.md'],
        },
      });
    });
  });
}
