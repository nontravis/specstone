import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/release_version.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/models/agent_drift.dart';
import 'package:specstone_core/src/setup_migration/models/skill_file_drift.dart';
import 'package:specstone_core/src/setup_migration/skill_agent_files.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/version.dart';

/// What a drift says: `lead` names the fault and, unless `isHandRepair`, the
/// fix is appended; a hand repair is the whole message.
///
/// [targetPath] is the project path of a file the lead names that is no
/// finding's own file.
final class _Text {
  const new({required this.lead, required this.isHandRepair, this.targetPath});

  final String lead;
  final bool isHandRepair;
  final String? targetPath;
}

_Text _command(String lead, {String? targetPath}) =>
    _Text(lead: lead, isHandRepair: false, targetPath: targetPath);

_Text _handRepair(String message) => _Text(lead: message, isHandRepair: true);

_Text _textOf(AgentDriftKind kind) => switch (kind) {
  AgentDriftKind.blockStale => _command(
    'the Specstone block differs from what the running CLI writes',
  ),
  AgentDriftKind.agentMdStale => _command(
    '$agentMdPath differs from what the running CLI writes',
  ),
  AgentDriftKind.agentMdMissing => _command(
    'the block imports $agentMdPath, which is missing',
    targetPath: agentMdPath,
  ),
  AgentDriftKind.topUnlisted => _command(
    'the repository top is not in agent_file_roots yet',
  ),
  AgentDriftKind.markersMalformed => _handRepair(
    'the Specstone marker lines are malformed and `specstone migrate` '
    'refuses the file; repair the block by hand',
  ),
  AgentDriftKind.codeFenceOpen => _handRepair(
    'a code fence is still open at the end of the file and `specstone '
    'migrate` refuses the file; close the code fence that opens on this '
    'line',
  ),
};

_Text _skillTextOf(SkillFileDriftKind kind, String path) => switch (kind) {
  SkillFileDriftKind.differs => _command(
    'the Specstone skill or agent file differs from what the running CLI '
    'writes',
  ),
  SkillFileDriftKind.missing => _command(
    'the Specstone skill or agent file is missing',
  ),
  SkillFileDriftKind.unshipped => _command(
    'the running CLI does not ship this Specstone file',
  ),
  SkillFileDriftKind.settingsStale => _command(
    '${_hookFilePathOf(path)} lacks the Specstone hook or holds one that '
    'differs from what the running CLI writes',
  ),
  SkillFileDriftKind.settingsMissing => _command(
    '${_hookFilePathOf(path)} is missing',
  ),
  SkillFileDriftKind.settingsMalformed => _handRepair(
    '${_hookFilePathOf(path)} is not one JSON object and `specstone migrate` '
    'refuses the file; repair it by hand',
  ),
};

/// Returns the hook file's own path for a `settings*` drift at [path], which
/// the drift predicate only reports for a hook file.
String _hookFilePathOf(String path) => hookFileOf(path)!.path;

/// Returns the fix a message ends with for [direction].
///
/// [stamp] is non-null whenever [direction] is `upgrade`.
String _fixTextOf(AgentFixDirection direction, ReleaseVersion? stamp) =>
    switch (direction) {
      AgentFixDirection.migrate => 'run `specstone migrate`',
      AgentFixDirection.upgrade =>
        'the files come from specstone $stamp, newer than this specstone '
            '$runningVersion; run `specstone upgrade`',
    };

/// Returns one `agent_block_stale` finding per drift `agentFileDrifts` and
/// `skillAndAgentFileDrifts` find.
///
/// Each finding carries the file's path from the project root and no `name`;
/// a skill or agent file's sits on line 1.
/// The code roots come from `codeFoldersOf`, as `migrate` reads them.
Iterable<Finding> staleAgentBlocks(CheckContext context) sync* {
  final config = ProjectConfig.read(context.projectRoot);
  final inputs = AgentFileInputs(
    projectRoot: context.projectRoot,
    cliVersion: specstoneVersion,
    codeRootFolders: codeFoldersOf(
      context.projectRoot,
      context.set,
      targets: config.targets,
    ),
    agentFileRoots: config.agentFileRoots,
  );
  final stamp = config.agentFilesVersion;
  final direction = agentFixDirectionOf(stamp);
  Finding findingOf(String path, int line, _Text text) => Finding(
    kind: FindingKind.agentBlockStale,
    path: path,
    line: line,
    message: text.isHandRepair
        ? text.lead
        : '${text.lead}; ${_fixTextOf(direction, stamp)}',
    waitsFor: text.isHandRepair ? WaitsFor.agent : WaitsFor.owner,
    keys: {'targetPath': ?text.targetPath},
  );
  final drifts = agentFileDrifts(inputs);
  for (final AgentDrift(:path, :line, :kind) in drifts) {
    yield findingOf(path, line, _textOf(kind));
  }
  // An unlisted top is one finding whatever its files hold.
  final unlistedTops = {
    for (final drift in drifts)
      if (drift.kind == AgentDriftKind.topUnlisted) '${drift.path}/',
  };
  for (final SkillFileDrift(:path, :kind) in skillAndAgentFileDrifts(inputs)) {
    if (unlistedTops.any(path.startsWith)) continue;
    yield findingOf(path, 1, _skillTextOf(kind, path));
  }
}
