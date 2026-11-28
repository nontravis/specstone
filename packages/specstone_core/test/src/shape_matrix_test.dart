@Tags(['integration'])
library;

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../helpers/git_repo.dart' show git;
import '../helpers/project_shapes.dart';
import '../helpers/shape_matrix.dart';

void main() {
  // D8: every write command on every project shape adds only the content
  // waits its own doc names.
  for (final command in writeCommands) {
    test('$command adds only content waits on every project shape', () async {
      final red = <String>[];
      for (final shape in await projectShapes()) {
        if (!runsOn(shape, command)) continue;
        final root = await writeShapeTree(shape);
        final head = headOf(root);
        final added = await newFindingsOf(root, command);
        if (command == 'migrate' &&
            (shape.name == 'plugin_era' || shape.name == 'floor_pins')) {
          expect(headOf(root), isNot(head), reason: '${shape.name} migrates');
        }
        red.addAll([
          for (final line in unallowedLines(command, added))
            '${shape.name} $command $line',
        ]);
      }
      expect(red, isEmpty);
    });
  }

  // D17: no write command leaves a block stale, so none waits on one.
  test('no write command allows a stale generated block', () {
    expect([
      for (final MapEntry(:key, :value) in allowedKinds.entries)
        if (value.contains(FindingKind.generatedBlockStale)) key,
    ], isEmpty);
  });

  // D8: a move inside the top feature leaves no api row of it unresolved.
  test('move inside one top feature adds only the probe sub-feature skeleton '
      'waits', () async {
    final shape = (await projectShapes()).singleWhere(
      (shape) => shape.name == 'nested',
    );
    final added = await newFindingsOf(
      await writeShapeTree(shape),
      'move_within',
    );

    expect(
      unallowedLines(
        'move_within',
        added,
        alsoAllowed: {
          FindingKind.subFeatureTooSmall,
          FindingKind.visionGoalWidened,
        },
      ),
      isEmpty,
    );
  });

  // D8: E01 waives only the row of an FR of the moved story.
  test('a row of an FR that did not move is not waived', () {
    final api = {'specs/f01_login/API.md'};
    const moved = {'email_login/check_password'};
    Finding row(String fr) => Finding(
      kind: FindingKind.frTraceUnresolved,
      path: 'specs/f01_login/API.md',
      line: 13,
      message: '$fr is no requirement of login',
      keys: {'fr': fr},
    );

    expect(isMovedFrRow(row('email_login/check_password'), api, moved), isTrue);
    expect(isMovedFrRow(row('email_login/other'), api, moved), isFalse);
    expect(
      isMovedFrRow(row('email_login/check_password'), const {}, moved),
      isFalse,
    );
  });

  // D8: bundle_size_rule.dart measures the largest file, which may change.
  test('a bundle over its limit is the same finding when its largest file '
      'changes, and a new one when it first goes over', () {
    Finding bundle(String doc, int actual) => Finding(
      kind: FindingKind.bundleOverLimit,
      path: 'prds/features/f30/FEATURE.md',
      line: 1,
      message:
          'the design read-first file of $doc holds $actual est. tokens; '
          'the limit is 20000',
      keys: {'doc': doc, 'limit': 20000, 'actual': actual},
    );

    expect(
      addedFindings(
        [bundle('user_story:a/s1', 30000)],
        [bundle('user_story:a/s2', 30006)],
      ),
      isEmpty,
    );
    expect(
      addedFindings(const [], [bundle('user_story:a/s1', 30000)]),
      hasLength(1),
    );
  });

  // D8: a doc a write pushes over its size limit is a new finding.
  test(
    'a write that pushes a story over its size limit adds a finding',
    () async {
      final shape = (await projectShapes()).singleWhere(
        (shape) => shape.name == 'nested',
      );
      final root = await writeShapeTree(shape);

      final added = await findingsAddedBy(
        root,
        () =>
            setFirstStoryUseCase(root, '${'Sign in with an email. ' * 1500}\n'),
      );

      expect([
        for (final f in added) f.kind,
      ], contains(FindingKind.charsOverLimit));
    },
  );

  // D8: a project pinned at its floor is refused by every command but migrate.
  test('a project pinned at the pack floors refuses each command but migrate '
      'and leaves the tree committed', () async {
    final shape = (await projectShapes()).singleWhere(
      (shape) => shape.name == 'floor_pins',
    );
    for (final command in writeCommands) {
      if (runsOn(shape, command)) continue;
      final root = await writeShapeTree(shape);

      expect(
        () => callCommand(root, command),
        throwsA(
          isA<TemplateFault>().having(
            (fault) => fault.code,
            'code',
            FaultCode.packPinOlder,
          ),
        ),
        reason: command,
      );
      expect(
        git(root, ['status', '--porcelain']).stdout,
        isEmpty,
        reason: command,
      );
    }
  });
}
