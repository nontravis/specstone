import 'package:specstone_core/src/setup_migration/claude_settings.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/setup_migration/models/rendered_file.dart';

/// The path of the Claude Code settings file a full run writes with the
/// Claude Code folder group.
const settingsFilePath = '.claude/settings.json';

/// The path of the Codex hooks file a full run writes with the Codex agents
/// folder group.
const codexHooksFilePath = '.codex/hooks.json';

/// The text of the settings file a full run creates, the hook groups alone.
String get settingsFileText => (settingsStateOf(null) as SettingsMissing).text;

/// The text of the Codex hooks file a full run creates, the hook group alone.
String get codexHooksFileText => (settingsStateOf(
  null,
  file: SpecstoneHookFile.codexHooks,
) as SettingsMissing).text;

/// The number of skill, agent, and hook files a full run writes at one root or
/// top.
int get skillFileCount => renderHostFiles().length + 2;

/// The path of every skill, agent, and hook file a full run writes under
/// [prefix], in plan order: by folder group, then by rendered order, the hook
/// file last in the Claude Code and Codex agents groups.
List<String> skillPaths([String prefix = '']) => [
  for (final group in AgentFolderGroup.values) ...[
    for (final file in renderHostFiles())
      if (group.folders.contains(file.folder)) '$prefix${file.path}',
    if (group == AgentFolderGroup.claudeCode) '$prefix$settingsFilePath',
    if (group == AgentFolderGroup.codexAgents) '$prefix$codexHooksFilePath',
  ],
];

/// The text of every skill, agent, and hook file under [prefix], keyed by
/// path, as a fixture that leaves a full run no file of them to write.
Map<String, String> skillFileTexts([String prefix = '']) => {
  for (final file in renderHostFiles()) '$prefix${file.path}': file.text,
  '$prefix$settingsFilePath': settingsFileText,
  '$prefix$codexHooksFilePath': codexHooksFileText,
};

/// The line `init` prints for each hook file, then the
/// `created <folder>: <n> files` line for each skill or agent folder at the
/// project root, in print order.
List<String> skillCountLines() {
  final rendered = renderHostFiles();
  int countIn(AgentFolder folder) =>
      rendered.where((file) => file.folder == folder).length;
  return [
    'created $settingsFilePath',
    'created $codexHooksFilePath',
    for (final folder in [
      AgentFolder.claudeSkills,
      AgentFolder.claudeAgents,
      AgentFolder.agentsSkills,
      AgentFolder.agentsAgents,
      AgentFolder.codexAgents,
      AgentFolder.cursorAgents,
    ])
      'created ${folder.path}: ${countIn(folder)} files',
  ];
}
