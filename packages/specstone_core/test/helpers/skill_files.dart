import 'package:specstone_core/src/setup_migration/host_render.dart';

/// The number of skill and agent files a full run writes at one root or top.
int get skillFileCount => renderHostFiles().length;

/// The path of every skill and agent file a full run writes under [prefix],
/// in plan order: by folder group, then by rendered order.
List<String> skillPaths([String prefix = '']) => [
  for (final group in AgentFolderGroup.values)
    for (final file in renderHostFiles())
      if (group.folders.contains(file.folder)) '$prefix${file.path}',
];

/// The text of every skill and agent file under [prefix], keyed by path, as a
/// fixture that leaves a full run no skill or agent file to write.
Map<String, String> skillFileTexts([String prefix = '']) => {
  for (final file in renderHostFiles()) '$prefix${file.path}': file.text,
};

/// The `created <folder>: <n> files` line `init` prints for each skill or agent
/// folder at the project root, in print order.
List<String> skillCountLines() {
  final rendered = renderHostFiles();
  int countIn(AgentFolder folder) =>
      rendered.where((file) => file.folder == folder).length;
  return [
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
