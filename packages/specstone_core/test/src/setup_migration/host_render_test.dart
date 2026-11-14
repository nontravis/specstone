import 'dart:convert';

import 'package:specstone_core/src/setup_migration/agent_assets.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _tomlBody =
    '# Body\n'
    '\n'
    'Line with triple quotes """ and \'\'\' here.\n'
    'A Windows path C:\\temp\\new and a trailing backslash \\\n'
    '[not-a-table]\n'
    'Read `.agents/skills/specstone-expert-sdd/SKILL.md`.\n';

final _fixtureAssets = <AgentAsset>[
  (path: 'specstone-demo/SKILL.md', text: 'skill text\n'),
  (path: 'specstone-demo/references/more.md', text: 'more text\n'),
  (
    path: 'specstone-looker.md',
    text:
        '---\n'
        'name: specstone-looker\n'
        'description: \'Looks: "only" at things\'\n'
        'tools: Bash, Read, Grep\n'
        'skills:\n'
        '  - specstone:expert-sdd\n'
        '---\n'
        '\n'
        '# Looker\n'
        '\n'
        'Read `.agents/skills/specstone-demo/SKILL.md` and '
        '`.agents/skills/specstone-demo/references/more.md`.\n',
  ),
  (
    path: 'specstone-reader.md',
    text:
        '---\n'
        'name: specstone-reader\n'
        'description: Reads and edits\n'
        'tools: Bash, Read, Write\n'
        '---\n'
        '\n'
        'Body keeps `.agents/skills/specstone-demo/SKILL.md`.\n',
  ),
  (
    path: 'specstone-planner.md',
    text:
        '---\n'
        'name: specstone-planner\n'
        'description: Plans\n'
        'disallowedTools: Agent, NotebookEdit\n'
        '---\n'
        '\n'
        'Plan body.\n',
  ),
  (
    path: 'specstone-quoter.md',
    text: '---\nname: specstone-quoter\ndescription: Quotes\n---\n$_tomlBody',
  ),
];

Map<String, Object?> _frontmatterOf(String text) {
  final end = text.indexOf('\n---\n', 4);
  final map = loadYaml(text.substring(4, end)) as YamlMap;
  return {for (final entry in map.entries) entry.key as String: entry.value};
}

String _bodyOf(String text) => text.substring(text.indexOf('\n---\n', 4) + 5);

String _unescape(String raw) {
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final char = raw[i];
    if (char != r'\') {
      out.write(char);
      continue;
    }
    final next = raw[++i];
    switch (next) {
      case 'n':
        out.write('\n');
      case 'r':
        out.write('\r');
      case 't':
        out.write('\t');
      case 'u':
        out.writeCharCode(int.parse(raw.substring(i + 1, i + 5), radix: 16));
        i += 4;
      default:
        out.write(next);
    }
  }
  return out.toString();
}

/// Decodes a basic string value of `key = "..."` or `key = """\n..."""`.
String _tomlValue(String toml, String key) {
  final multi = '$key = """\n';
  final multiStart = toml.indexOf(multi);
  if (multiStart >= 0) {
    final start = multiStart + multi.length;
    return _unescape(toml.substring(start, toml.indexOf('"""', start)));
  }
  final single = '$key = "';
  final start = toml.indexOf(single) + single.length;
  var end = start;
  while (toml[end] != '"') {
    end += toml[end] == r'\' ? 2 : 1;
  }
  return _unescape(toml.substring(start, end));
}

Map<AgentFolder, List<RenderedFile>> _byFolder(List<RenderedFile> files) => {
  for (final folder in AgentFolder.values)
    folder: [
      for (final file in files)
        if (file.folder == folder) file,
    ],
};

RenderedFile _file(List<RenderedFile> files, AgentFolder folder, String name) =>
    files.singleWhere((f) => f.folder == folder && f.entry == name);

void main() {
  group('folders', () {
    test('give the paths and groups of the six agent folders', () {
      expect(
        {for (final f in AgentFolder.values) f: f.path},
        {
          AgentFolder.claudeSkills: '.claude/skills',
          AgentFolder.agentsSkills: '.agents/skills',
          AgentFolder.claudeAgents: '.claude/agents',
          AgentFolder.cursorAgents: '.cursor/agents',
          AgentFolder.codexAgents: '.codex/agents',
          AgentFolder.agentsAgents: '.agents/agents',
        },
      );
      expect(AgentFolderGroup.claudeCode.folders, [
        AgentFolder.claudeSkills,
        AgentFolder.claudeAgents,
      ]);
      expect(AgentFolderGroup.shared.folders, [
        AgentFolder.agentsSkills,
        AgentFolder.agentsAgents,
      ]);
      expect(AgentFolderGroup.codexAgents.folders, [AgentFolder.codexAgents]);
      expect(AgentFolderGroup.cursorAgents.folders, [AgentFolder.cursorAgents]);
      for (final folder in AgentFolder.values) {
        expect(folder.group.folders, contains(folder));
      }
    });
  });

  group('renderHostFilesOf', () {
    final files = renderHostFilesOf(_fixtureAssets);

    test('writes each skill file byte-equal into both skill folders', () {
      for (final folder in [
        AgentFolder.claudeSkills,
        AgentFolder.agentsSkills,
      ]) {
        final skillFiles = _byFolder(files)[folder]!;
        expect(
          {for (final f in skillFiles) f.path: f.text},
          {
            '${folder.path}/specstone-demo/SKILL.md': 'skill text\n',
            '${folder.path}/specstone-demo/references/more.md': 'more text\n',
          },
        );
        expect(skillFiles.map((f) => f.entry).toSet(), {'specstone-demo'});
      }
    });

    test('writes each agent once per agent folder', () {
      for (final folder in [
        AgentFolder.claudeAgents,
        AgentFolder.cursorAgents,
        AgentFolder.agentsAgents,
      ]) {
        final agentFiles = _byFolder(files)[folder]!;
        expect(agentFiles.map((f) => f.entry).toList(), [
          'specstone-looker.md',
          'specstone-reader.md',
          'specstone-planner.md',
          'specstone-quoter.md',
        ]);
        expect(
          agentFiles.map((f) => f.path),
          everyElement(startsWith('${folder.path}/specstone-')),
        );
      }
      expect(_byFolder(files)[AgentFolder.codexAgents]!.map((f) => f.entry), [
        'specstone-looker.toml',
        'specstone-reader.toml',
        'specstone-planner.toml',
        'specstone-quoter.toml',
      ]);
    });

    test('gives the Claude Code render its keys and drops the preload', () {
      final looker = _file(
        files,
        AgentFolder.claudeAgents,
        'specstone-looker.md',
      );
      expect(_frontmatterOf(looker.text), {
        'name': 'specstone-looker',
        'description': 'Looks: "only" at things',
        'tools': 'Bash, Read, Grep',
      });
      final planner = _file(
        files,
        AgentFolder.claudeAgents,
        'specstone-planner.md',
      );
      expect(_frontmatterOf(planner.text), {
        'name': 'specstone-planner',
        'description': 'Plans',
        'disallowedTools': 'Agent, NotebookEdit',
      });
    });

    test(
      'gives the Cursor render no tools key and a readonly flag by tools',
      () {
        final looker = _file(
          files,
          AgentFolder.cursorAgents,
          'specstone-looker.md',
        );
        expect(_frontmatterOf(looker.text), {
          'name': 'specstone-looker',
          'description': 'Looks: "only" at things',
          'readonly': true,
        });
        for (final name in ['reader', 'planner', 'quoter']) {
          final other = _file(
            files,
            AgentFolder.cursorAgents,
            'specstone-$name.md',
          );
          expect(_frontmatterOf(other.text), isNot(contains('readonly')));
          expect(_frontmatterOf(other.text), isNot(contains('tools')));
        }
      },
    );

    test('gives the host-neutral render a name and a description alone', () {
      for (final file in _byFolder(files)[AgentFolder.agentsAgents]!) {
        expect(_frontmatterOf(file.text).keys.toSet(), {'name', 'description'});
      }
    });

    test('swaps the skill path in the Claude Code body alone', () {
      const source = '.agents/skills/specstone-demo/SKILL.md';
      final claude = _file(
        files,
        AgentFolder.claudeAgents,
        'specstone-looker.md',
      );
      expect(claude.text, isNot(contains('.agents/skills/')));
      expect(
        claude.text,
        contains('.claude/skills/specstone-demo/references/more.md'),
      );
      for (final folder in [
        AgentFolder.cursorAgents,
        AgentFolder.agentsAgents,
      ]) {
        final other = _file(files, folder, 'specstone-looker.md');
        expect(other.text, contains(source));
        expect(other.text, isNot(contains('.claude/skills/')));
        expect(
          _bodyOf(other.text).replaceAll('.agents/', '.claude/'),
          _bodyOf(claude.text),
        );
      }
      final codex = _file(
        files,
        AgentFolder.codexAgents,
        'specstone-looker.toml',
      );
      expect(codex.text, contains(source));
      expect(codex.text, isNot(contains('.claude/skills/')));
    });

    test('keeps a description with a colon and quotes round-trippable', () {
      final codex = _file(
        files,
        AgentFolder.codexAgents,
        'specstone-looker.toml',
      );
      expect(_tomlValue(codex.text, 'name'), 'specstone-looker');
      expect(_tomlValue(codex.text, 'description'), 'Looks: "only" at things');
      expect(codex.text, isNot(contains('tools')));
      expect(codex.text, isNot(contains('skills:')));
    });

    test('renders a TOML value that decodes back to a hard body', () {
      final codex = _file(
        files,
        AgentFolder.codexAgents,
        'specstone-quoter.toml',
      );
      expect(_tomlValue(codex.text, 'developer_instructions'), _tomlBody);
      expect(
        codex.text.split('\n').where((l) => l == '[not-a-table]'),
        hasLength(1),
      );
    });

    test('puts each path under its folder with slashes only', () {
      for (final file in files) {
        expect(file.path, startsWith('${file.folder.path}/${file.entry}'));
        expect(file.path, isNot(contains(r'\')));
      }
    });
  });

  group('renderHostFiles', () {
    final files = renderHostFiles();
    final assets = shippedAgentAssets();
    final skillFiles = assets.where((a) => a.path.contains('/')).length;
    final agentFiles = assets.length - skillFiles;

    test('covers all six folders with each shipped file', () {
      final byFolder = _byFolder(files);
      for (final folder in [
        AgentFolder.claudeSkills,
        AgentFolder.agentsSkills,
      ]) {
        expect(byFolder[folder], hasLength(skillFiles));
      }
      for (final folder in [
        AgentFolder.claudeAgents,
        AgentFolder.cursorAgents,
        AgentFolder.codexAgents,
        AgentFolder.agentsAgents,
      ]) {
        expect(byFolder[folder], hasLength(agentFiles));
      }
      expect(files, hasLength(2 * skillFiles + 4 * agentFiles));
    });

    test('gives Cursor readonly to the reader alone', () {
      final readonly = [
        for (final file in files)
          if (file.folder == AgentFolder.cursorAgents &&
              _frontmatterOf(file.text)['readonly'] == true)
            file.entry,
      ];
      expect(readonly, ['specstone-sdd-reader.md']);
    });

    test('renders text that is valid UTF-8 with LF lines', () {
      for (final file in files) {
        expect(file.text, isNot(contains('\r')));
        expect(utf8.decode(utf8.encode(file.text)), file.text);
      }
    });
  });
}
