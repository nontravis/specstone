import 'dart:io';

import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/models/renamed_names.dart';
import 'package:specstone_core/src/document_writing/models/typed_name.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PlannedRewrites, planRewrites;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:test/test.dart';

import '../../specstone_core/test/helpers/index_fixture.dart' show openSession;
import '../../specstone_core/test/helpers/project_shapes.dart';
import '../../specstone_core/test/helpers/shape_matrix.dart'
    show makeWorkTree, runsOn, writeShapeTree;
import '../../specstone_core/test/helpers/write_fixture.dart' show writeIn;
import 'helpers/baseline_tree.dart';

/// One change the planner plans rewrites for: its moves and its renames.
final class _Change {
  const new(
    this.label,
    this.moves, {
    this.renamed = const RenamedNames({}),
    this.movesStory = false,
  });

  final String label;
  final List<PathMove> moves;
  final RenamedNames renamed;

  /// Whether the story folder itself moves, so a link reaches it only by its
  /// own segment, as written or spelled.
  final bool movesStory;
}

/// The marks a link destination may spell a path character with, each in a
/// probe doc of its own.
const _spellings = {'escaped': '%5F', 'backslashed': r'\_', 'entity': '&#95;'};

String _folderOf(String docPath) =>
    '${docPath.substring(0, docPath.lastIndexOf('/'))}/';

String _lastSegmentOf(String folder) =>
    folder.split('/').where((s) => s.isNotEmpty).last;

/// Returns a move of the first story under another folder, a rename of it,
/// and a reorder of its feature, as the move, rename, and reorder commands
/// plan them.
List<_Change> _changesOf(DocIndex index) {
  final story = index.docs.firstWhere((doc) => doc.docTypeId == 'user_story');
  final storyFolder = _folderOf(story.docPath);
  final featureFolder = _folderOf(
    storyFolder.substring(0, storyFolder.length - 1),
  );
  final featureParent = _folderOf(
    featureFolder.substring(0, featureFolder.length - 1),
  );
  final reordered = _lastSegmentOf(featureFolder)
      .replaceFirst(RegExp('^f[0-9]+_'), 'f99_');
  return [
    _Change('move', [
      PathMove(
        from: storyFolder,
        to: '${featureParent}f98_elsewhere/us01_moved/',
      ),
    ], movesStory: true),
    _Change(
      'rename',
      [PathMove(from: storyFolder, to: '${featureFolder}us01_renamed_probe/')],
      renamed: RenamedNames({
        TypedName(typeId: 'user_story', name: story.name):
            '${story.name.substring(0, story.name.lastIndexOf('/') + 1)}'
            'renamed_probe',
      }),
      movesStory: true,
    ),
    _Change('reorder', [
      PathMove(from: featureFolder, to: '$featureParent$reordered/'),
    ]),
  ];
}

/// Writes docs under [docsRoot] that reach [storyFolder] in every written
/// form: plain, `./` and `../` relative, another case, and each mark of
/// [_spellings] alone in its doc, so no plain name keeps that doc.
void _writeProbes(Directory docsRoot, String storyFolder) {
  void write(String docPath, String text) =>
      File([docsRoot.path, ...docPath.split('/')].join(Platform.pathSeparator))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);

  final segment = _lastSegmentOf(storyFolder);
  final parentFolder = storyFolder.substring(
    0,
    storyFolder.length - segment.length - 1,
  );
  write(
    'mentions_probe.md',
    '# Mentions probe\n\n'
        'Plain `${storyFolder}USER_STORY.md` and ./${storyFolder}USER_STORY.md.\n'
        'Upper ${storyFolder.toUpperCase()}USER_STORY.md.\n'
        '[image](${storyFolder}diagram.png)\n',
  );
  for (final MapEntry(key: name, value: mark) in _spellings.entries) {
    final spelled = segment.replaceFirst('_', mark);
    write(
      '${name}_probe.md',
      '# Spelling probe\n\n[image]($parentFolder$spelled/diagram.png)\n',
    );
  }
  write(
    '${parentFolder}mentions_probe.md',
    '# Sibling probe\n\nSee $segment/USER_STORY.md and ./$segment/.\n',
  );
  write(
    '${storyFolder}mentions_probe.md',
    '# Inner probe\n\n'
        'Up ../../${_lastSegmentOf(parentFolder)}/mentions_probe.md and '
        '[self](./USER_STORY.md).\n',
  );
  write('${storyFolder}diagram.png', 'png');
}

/// The rewrites of [plan] by path from the project root: each new text after
/// the hash that guards it, then each create's text.
Map<String, String> _resultOf(PlannedRewrites plan) => {
  for (final step in plan.rewrites) step.path: '${step.before}\n${step.text}',
  for (final step in plan.creates) step.path: step.text,
};

/// Asserts that the planner with its prefilter returns the whole result the
/// planner without it returns, for each change of [root], and that each
/// spelling probe is among the rewrites of a change that moves the story.
void _expectSameRewrites(Directory root, String shape) {
  final setup = openSession(root);
  final changes = _changesOf(setup.index);
  final story = setup.index.docs.firstWhere(
    (doc) => doc.docTypeId == 'user_story',
  );
  _writeProbes(setup.project.docsRoot, _folderOf(story.docPath));
  setup.close();
  for (final change in changes) {
    Map<String, String> planned({required bool prefilter}) => writeIn(
      root,
      (s) => _resultOf(
        planRewrites(
          s,
          change.moves,
          renamed: change.renamed,
          prefilter: prefilter,
        ),
      ),
    );
    final unfiltered = planned(prefilter: false);
    final reason = '$shape ${change.label}';
    expect(unfiltered, isNotEmpty, reason: reason);
    if (change.movesStory) {
      for (final name in _spellings.keys) {
        expect(
          unfiltered.keys,
          contains(endsWith('/${name}_probe.md')),
          reason: '$reason rewrites the $name probe',
        );
      }
    }
    expect(planned(prefilter: true), unfiltered, reason: reason);
  }
}

void main() {
  // D17: the planner's prefilter drops only docs no rewrite reaches, so it
  // plans the same rewrites with and without it.
  test('a move, a rename, and a reorder plan the same rewrites with and '
      'without the prefilter in every project shape', () async {
    for (final shape in await projectShapes()) {
      if (!runsOn(shape, 'move')) continue;
      _expectSameRewrites(await writeShapeTree(shape), shape.name);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a move, a rename, and a reorder plan the same rewrites with and '
      'without the prefilter in the baseline tree', () async {
    _expectSameRewrites(makeWorkTree(await writeBaselineTree()), 'baseline');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
