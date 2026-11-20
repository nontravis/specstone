import 'dart:convert';

import 'package:specstone_core/src/setup_migration/agent_assets.dart';
import 'package:specstone_core/src/setup_migration/models/agent_asset.dart';
import 'package:specstone_core/src/setup_migration/models/rendered_file.dart';
import 'package:yaml/yaml.dart';

const _sourceSkillPrefix = '.agents/skills/';
const _claudeSkillPrefix = '.claude/skills/';
const _markdownSuffix = '.md';
const _frontmatterFence = '---\n';
const _frontmatterEnd = '\n---\n';
const _writeToolNames = {'Write', 'Edit'};

/// Renders every embedded skill and agent file for each host's folders.
List<RenderedFile> renderHostFiles() => renderHostFilesOf(shippedAgentAssets());

/// Renders [assets] for each host's folders; a skill file is the same bytes in
/// both skill folders, an agent file takes its host's keys and skill paths.
List<RenderedFile> renderHostFilesOf(List<AgentAsset> assets) {
  final skills = [
    for (final asset in assets)
      if (asset.path.contains('/')) asset,
  ];
  final agents = [
    for (final asset in assets)
      if (!asset.path.contains('/')) _Agent.parse(asset),
  ];
  return [
    for (final folder in AgentFolder.values)
      ...switch (folder) {
        AgentFolder.claudeSkills || AgentFolder.agentsSkills => [
          for (final skill in skills) _skillFile(folder, skill),
        ],
        _ => [for (final agent in agents) _agentFile(folder, agent)],
      },
  ];
}

RenderedFile _skillFile(AgentFolder folder, AgentAsset skill) => RenderedFile(
  folder: folder,
  entry: skill.path.substring(0, skill.path.indexOf('/')),
  path: '${folder.path}/${skill.path}',
  text: skill.text,
);

RenderedFile _agentFile(AgentFolder folder, _Agent agent) {
  final isToml = folder == AgentFolder.codexAgents;
  final entry = '${agent.name}${isToml ? '.toml' : '.md'}';
  return RenderedFile(
    folder: folder,
    entry: entry,
    path: '${folder.path}/$entry',
    text: switch (folder) {
      AgentFolder.claudeAgents => agent.claudeCodeText(),
      AgentFolder.cursorAgents => agent.cursorText(),
      AgentFolder.codexAgents => agent.codexText(),
      _ => agent.neutralText(),
    },
  );
}

class _Agent {
  const new({
    required this.name,
    required this.description,
    required this.tools,
    required this.disallowedTools,
    required this.memory,
    required this.skills,
    required this.body,
  });

  factory parse(AgentAsset asset) {
    final text = asset.text.replaceAll('\r\n', '\n');
    final end = text.indexOf(_frontmatterEnd);
    if (!text.startsWith(_frontmatterFence) || end < 0) {
      throw FormatException('No frontmatter in ${asset.path}');
    }
    final fields = loadYaml(text.substring(_frontmatterFence.length, end));
    if (fields is! YamlMap) {
      throw FormatException('Frontmatter is not a map in ${asset.path}');
    }
    final name = asset.path.substring(
      0,
      asset.path.length - _markdownSuffix.length,
    );
    if (fields['name'] != name) {
      throw FormatException(
        'The name of ${asset.path} is not its file name: ${fields['name']}',
      );
    }
    final skills = _toolsOf(fields['skills']);
    return _Agent(
      name: name,
      description: '${fields['description']}',
      tools: _toolsOf(fields['tools']),
      disallowedTools: _toolsOf(fields['disallowedTools']),
      memory: fields['memory'] as String?,
      skills: skills == null || skills.isEmpty ? null : skills,
      body: text.substring(end + _frontmatterEnd.length),
    );
  }

  final String name;
  final String description;
  final List<String>? tools;
  final List<String>? disallowedTools;

  /// The Claude Code memory scope, such as `project`; null for none.
  final String? memory;

  /// The skills a Claude Code agent preloads; null for none.
  final List<String>? skills;
  final String body;

  bool get isReadOnly => tools != null && !tools!.any(_writeToolNames.contains);

  String claudeCodeText() => _markdown({
    'name': name,
    'description': description,
    'tools': ?tools?.join(', '),
    'disallowedTools': ?disallowedTools?.join(', '),
    'memory': ?memory,
    'skills': ?skills,
  }, body.replaceAll(_sourceSkillPrefix, _claudeSkillPrefix));

  String cursorText() => _markdown({
    'name': name,
    'description': description,
    if (isReadOnly) 'readonly': true,
  }, body);

  String neutralText() =>
      _markdown({'name': name, 'description': description}, body);

  String codexText() =>
      'name = ${_tomlString(name)}\n'
      'description = ${_tomlString(description)}\n'
      'developer_instructions = """\n${_tomlEscape(body)}"""\n';
}

List<String>? _toolsOf(Object? value) => switch (value) {
  null => null,
  YamlList() => [for (final tool in value) '$tool'.trim()],
  _ => [for (final tool in '$value'.split(',')) tool.trim()],
};

String _markdown(Map<String, Object> fields, String body) {
  final lines = [
    for (final MapEntry(:key, :value) in fields.entries)
      if (value is List<String>) ...[
        '$key:',
        for (final item in value) '  - ${_yamlScalar(item)}',
      ] else
        '$key: ${_yamlScalar(value)}',
  ];
  return '$_frontmatterFence${lines.join('\n')}$_frontmatterEnd$body';
}

String _yamlScalar(Object value) => switch (value) {
  String() when _isPlainYamlString(value) => value,
  String() => jsonEncode(value),
  _ => '$value',
};

/// Reports whether [value] written bare reads back as the same string.
///
/// A host that does not decode quotes keeps them in the value, so a quoted
/// scalar is the fallback, never the default.
bool _isPlainYamlString(String value) {
  if (value.runes.any(_isNonPrintable)) return false;
  try {
    final parsed = loadYaml('key: $value');
    return parsed is YamlMap && parsed['key'] == value;
  } on YamlException {
    return false;
  }
}

bool _isNonPrintable(int rune) =>
    rune < 0x20 || rune == 0x85 || rune == 0x2028 || rune == 0x2029;

String _tomlString(String value) =>
    '"${_tomlEscape(value, keepNewlines: false)}"';

String _tomlEscape(String value, {bool keepNewlines = true}) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    switch (rune) {
      case 0x5C:
        out.write(r'\\');
      case 0x22:
        out.write(r'\"');
      case 0x09:
        out.writeCharCode(rune);
      case 0x0A when keepNewlines:
        out.writeCharCode(rune);
      case < 0x20 || 0x7F:
        out.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
      default:
        out.writeCharCode(rune);
    }
  }
  return out.toString();
}
