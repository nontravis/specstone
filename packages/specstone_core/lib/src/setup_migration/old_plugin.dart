import 'dart:convert';
import 'dart:io';

const _pluginKey = 'specstone@specstone';
const _configDirVariable = 'CLAUDE_CONFIG_DIR';

/// Whether any Claude Code settings file turns the old Specstone plugin on.
///
/// Reads the user settings (`$CLAUDE_CONFIG_DIR/settings.json`, else
/// `.claude/settings.json` under [home]) and the project's
/// `.claude/settings.json` and `.claude/settings.local.json`. A file that is
/// missing or does not parse holds no key.
bool oldPluginEnabled({
  required Directory projectRoot,
  required Map<String, String> environment,
  required Directory? home,
}) {
  final configDir = environment[_configDirVariable];
  final userFile = configDir != null && configDir.isNotEmpty
      ? _under(Directory(configDir), 'settings.json')
      : home == null
      ? null
      : _under(home, '.claude/settings.json');
  return [
    ?userFile,
    _under(projectRoot, '.claude/settings.json'),
    _under(projectRoot, '.claude/settings.local.json'),
  ].any(_enablesPlugin);
}

File _under(Directory folder, String relative) =>
    File.fromUri(folder.uri.resolve(relative));

bool _enablesPlugin(File file) {
  try {
    final root = jsonDecode(utf8.decode(file.readAsBytesSync()));
    if (root is! Map<String, Object?>) return false;
    final plugins = root['enabledPlugins'];
    return plugins is Map<String, Object?> && plugins[_pluginKey] == true;
  } on FileSystemException {
    return false;
  } on FormatException {
    return false;
  }
}
