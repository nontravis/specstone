import 'dart:io';

import 'package:specstone_core/src/doc_model/name_mentions.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/shipped_pins.dart';

/// The `code:` entries of the workspace's `tech_stack` that Specstone's own
/// repository holds, as paths from the repository root.
const _codeRoots = [
  'packages/specstone_core/lib/',
  'packages/specstone_core/packs/',
  'packages/specstone_core/assets/',
  'packages/specstone_core/tool/',
  'packages/specstone/lib/',
  'packages/specstone/bin/',
  'plugin/',
  'tool/',
  '.github/workflows/',
  'install.sh',
  'install.ps1',
  'uninstall.sh',
  'uninstall.ps1',
];

const _configFile = '.specstone/config.yaml';
const _docsFolder = 'docs';

Directory _repositoryRoot() {
  var dir = Directory.current.absolute;
  while (!Directory.fromUri(dir.uri.resolve('packages/')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) fail('no repository root above the cwd');
    dir = parent;
  }
  return dir;
}

/// The nearest folder above [repository] that holds a project config and a
/// docs folder, or null when none does, as in a checkout without the docs.
Directory? _workspaceAbove(Directory repository) {
  for (
    var dir = repository.parent;
    dir.parent.path != dir.path;
    dir = dir.parent
  ) {
    final hasConfig = File.fromUri(dir.uri.resolve(_configFile)).existsSync();
    final hasDocs = Directory.fromUri(dir.uri.resolve(_docsFolder))
        .existsSync();
    if (hasConfig && hasDocs) return dir;
  }
  return null;
}

/// Copies the docs of [workspace] into a temp folder under a config that pins
/// the shipped packs, so the index the test builds never lands in the
/// workspace and a workspace pinned to an older pack still reads.
Directory _copyOf(Directory workspace) {
  final copy = Directory.systemTemp.createTempSync('specstone_sweep_');
  addTearDown(() => copy.deleteSync(recursive: true));
  File('${copy.path}/$_configFile')
    ..createSync(recursive: true)
    ..writeAsStringSync(shippedPinsConfig());
  final docs = Directory('${workspace.path}/$_docsFolder');
  for (final entity in docs.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(docs.path.length);
    File('${copy.path}/$_docsFolder$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(entity.readAsBytesSync());
  }
  return copy;
}

String? _readLf(File file) {
  try {
    return toLf(file.readAsStringSync());
  } on FormatException {
    return null;
  }
}

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  return dot <= path.lastIndexOf('/') ? '' : path.substring(dot);
}

/// Whether [mention] names a doc of [index], by Name or by path.
bool _namesDoc(DocIndex index, NameMention mention) {
  final address = mention.address;
  if (!address.isName) {
    final path = mention.text;
    const prefix = '$_docsFolder/';
    return index.at(path) != null ||
        (path.startsWith(prefix) &&
            index.at(path.substring(prefix.length)) != null);
  }
  final typeId = address.typeId;
  return typeId == null
      ? index.docs.any((doc) => doc.name == address.body)
      : index.ofTypeNamed(typeId, address.body).isNotEmpty;
}

void main() {
  final workspace = _workspaceAbove(_repositoryRoot());

  test(
    'code_root_docs: no comment line or markdown file under the code roots '
    'names a doc of the workspace',
    () {
      final root = _repositoryRoot();
      final session = openSession(_copyOf(workspace!));
      addTearDown(session.close);
      final found = <String>[];
      for (final path in codeRootFiles(root, _codeRoots)) {
        final extension = _extensionOf(path);
        if (!readsNameMentions(extension)) continue;
        final lf = _readLf(File.fromUri(root.uri.resolve(path)));
        if (lf == null) continue;
        for (final mention in docMentionsInFile(lf, extension)) {
          if (_namesDoc(session.index, mention)) {
            found.add('$path:${mention.line}: ${mention.text}');
          }
        }
      }
      expect(
        found,
        isEmpty,
        reason: '${found.length} doc mentions:\n${found.join('\n')}',
      );
    },
    skip: workspace == null
        ? 'no workspace docs above the repository, as in the public checkout'
        : false,
  );
}
