import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/index_query/index_store.dart'
    show indexFilePath;
import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/git_repo.dart' show git;
import '../../../specstone_core/test/helpers/index_fixture.dart'
    show openSession;
import '../../../specstone_core/test/helpers/shape_matrix.dart'
    show headOf, makeWorkTree;
import '../../../specstone_core/test/helpers/write_fixture.dart' show testHome;
import 'baseline_tree.dart';

/// The baseline tree as a git work tree, written, committed, and indexed once,
/// that each write test puts back at its commit instead of building again.
final class BaselineWorkTree {
  const new _(this.root, this._base, this._docPaths);

  /// Writes the baseline tree and makes it a committed, indexed work tree.
  static Future<BaselineWorkTree> build() async {
    final root = makeWorkTree(await writeBaselineTree());
    return BaselineWorkTree._(root, headOf(root), _indexedPathsOf(root));
  }

  final Directory root;
  final String _base;
  final List<String> _docPaths;

  /// Puts [root] back at its commit and returns it: the gitignored index is
  /// kept, so it refreshes only the files the last writes touched.
  ///
  /// Expects the work tree to hold the commit's bytes and nothing else but
  /// the index, the refreshed index to list the commit's docs, and the test's
  /// home to hold no file, such as a journal record of [root].
  Directory reset() {
    expect(
      testHome().listSync(recursive: true).whereType<File>(),
      isEmpty,
      reason: 'no record of an earlier write is kept for the reused root',
    );
    expect(git(root, ['reset', '-q', '--hard', _base]).exitCode, 0);
    expect(
      git(root, ['clean', '-q', '-fdx', '-e', '$indexFilePath*']).exitCode,
      0,
    );
    expect(headOf(root), _base);
    final status = git(root, ['status', '--porcelain', '--ignored']);
    expect(status.exitCode, 0);
    expect(
      [
        for (final line in LineSplitter.split('${status.stdout}'))
          if (!line.startsWith('!! $indexFilePath')) line,
      ],
      isEmpty,
      reason: 'the work tree holds the commit and the index only',
    );
    expect(_indexedPathsOf(root), _docPaths);
    return root;
  }

  static List<String> _indexedPathsOf(Directory root) {
    final session = openSession(root);
    try {
      return [for (final doc in session.index.docs) doc.docPath];
    } finally {
      session.close();
    }
  }
}
