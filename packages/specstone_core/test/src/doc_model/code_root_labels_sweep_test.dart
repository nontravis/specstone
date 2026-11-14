import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart';
import 'package:specstone_core/src/doc_model/number_label.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:test/test.dart';

/// The `code:` entries of the tech stack doc that Specstone's own
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

/// A kept label: `file` is relative to the repository root, `written` is the
/// label as the sweep reports it, `reason` says why it names no doc.
typedef _Allowed = ({String file, String written, String reason});

/// The kept labels, each with the reason it is no citation of a doc.
const _allowed = <_Allowed>[];

Directory _repositoryRoot() {
  var dir = Directory.current.absolute;
  while (!Directory.fromUri(dir.uri.resolve('packages/')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) fail('no repository root above the cwd');
    dir = parent;
  }
  return dir;
}

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  return dot <= path.lastIndexOf('/') ? '' : path.substring(dot);
}

List<String> _labelsOf(String path, String lf) {
  final extension = _extensionOf(path);
  if (extension == markdownExtension) {
    final body = Doc.parse(lf).afterFrontmatter;
    return [for (final label in numberLabelsInMarkdown(body)) label.written];
  }
  if (!readsNameMentions(extension)) return const [];
  return [
    for (final line in lf.split('\n'))
      if (isCommentLine(line, extension))
        for (final label in numberLabelsIn(line)) label.written,
  ];
}

void main() {
  test('code_root_labels: no comment line or markdown file under the code '
      'roots cites a doc by a number label', () {
    final root = _repositoryRoot();
    final found = <String>[];
    for (final path in codeRootFiles(root, _codeRoots)) {
      final String lf;
      try {
        lf = File.fromUri(root.uri.resolve(path))
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
      } on FormatException {
        continue;
      }
      for (final written in _labelsOf(path, lf)) {
        final kept = _allowed.any(
          (entry) => entry.file == path && entry.written == written,
        );
        if (!kept) found.add('$path: $written');
      }
    }
    expect(
      found,
      isEmpty,
      reason: '${found.length} number labels:\n${found.join('\n')}',
    );
  });
}
