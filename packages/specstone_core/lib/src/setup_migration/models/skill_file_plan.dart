import 'package:specstone_core/src/setup_migration/models/agent_write.dart';
import 'package:specstone_core/src/setup_migration/models/malformed_settings_file.dart';

/// The skill and agent file changes of one run, every path from the project
/// root with `/` separators.
///
/// `writes` holds `.claude/settings.json` beside the skill and agent files when
/// the Claude Code folder group takes part and the file is not current, and
/// `.codex/hooks.json` when the Codex agents group does;
/// `malformedSettings` holds, for each such file that no run can merge into,
/// its path and why it does not parse, a path that is no file included, and
/// plans no write for it.
///
/// `trash` lists each path to move to the trash: the folder or file of a
/// `specstone-*` entry the CLI ships nothing of, which moves whole, and each
/// unshipped file inside an entry it ships; `topTrash` holds those of it that
/// lie at a repository top. `skipped` holds the warning line
/// for each folder or file the run leaves because its real path lies outside
/// the project root or under `.git`.
final class SkillFilePlan {
  const new({
    required this.writes,
    required this.malformedSettings,
    required this.trash,
    required this.topTrash,
    required this.skipped,
    required this.writeSet,
  });

  final List<AgentWrite> writes;
  final List<MalformedSettingsFile> malformedSettings;
  final List<String> trash;
  final List<String> topTrash;
  final List<String> skipped;
  final Set<String> writeSet;
}
