import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/models/indexed_link.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/work_groups.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';

const _crossGroupHeading = 'Cross-group links:';

/// What joins the two DocPaths of a linked pair in its key.
const _pairJoint = '\n';

/// The `--json` key of a group's size, which replaces the read-first file's.
const _tokensKey = 'tokens';

// MARK: - Answer

/// Writes one file pair per group of [pick], each from the group's own
/// targets, and prints each group's index under its group and `targets:` lines.
///
/// - Each read-first file ends with its `Cross-group links:` part.
/// - Every path is judged before any write, and the call prunes once.
/// - The 200-line and 8 KiB index bound counts every group's lines together.
///
/// - [outPath]: absolute, `.g<k>` before its extension; null names each file
///   by the Name rule with `.g<k>`.
ReadAnswer answerGroupFiles(
  DocIndex index,
  WorkGroupPick pick, {
  required DocsProject project,
  String? outPath,
}) {
  final groups = pick.groups;
  final linked = _CrossGroupLinks(index.links(), groups);
  final saved = [
    for (final group in groups)
      _savedGroup(
        index,
        pick,
        group,
        readFirstEnd: linked.partOf(group),
        project: project,
        outPath: outPath,
      ),
  ];
  writeSavedBundles(saved, project: project, isBare: outPath == null);
  String heads(WorkGroup group) =>
      '${_groupLine(group, groups.length)}${_targetsLine(group)}';
  final counted = [
    for (final (at, group) in groups.indexed)
      '${heads(group)}${saved[at].countedIndex()}',
  ].join();
  final withSections = fitsIndexBound(counted);
  return ReadAnswer(
    text: [
      for (final (at, group) in groups.indexed)
        '${heads(group)}${saved[at].index(withSections: withSections)}',
    ].join(),
    json: {
      'groups': [
        for (final (at, group) in groups.indexed)
          _groupJson(group, saved[at].indexJson()),
      ],
    },
    warnings: {for (final bundle in saved) ...bundle.warnings}.toList(),
  );
}

/// Returns [group]'s answer saved at its bare name, or at [outPath] with
/// `.g<k>`.
SavedBundle _savedGroup(
  DocIndex index,
  WorkGroupPick pick,
  WorkGroup group, {
  required String readFirstEnd,
  required DocsProject project,
  required String? outPath,
}) {
  final answer = answerContext(
    index,
    pick.bundleOf(index, group),
    targets: group.targets,
    split: true,
    readFirstEnd: readFirstEnd,
  );
  if (outPath != null) {
    return SavedBundle(
      answer,
      groupPathOf(outPath, group.number),
      refsAt: groupPathOf(outPath, group.number, isRefs: true),
    );
  }
  final name = bundleFileName(
    targets: pick.targets,
    mode: pick.bundle.mode,
    summary: false,
    noProject: pick.noProject,
    codeTarget: pick.bundle.codeTarget,
    group: group.number,
  );
  return SavedBundle(answer, bareBundleFile(project.projectRoot, name).path);
}

String _groupLine(WorkGroup group, int count) =>
    '==> group ${group.number} of $count: ${group.units.length} units, '
    '${group.tokens} tokens <==\n';

String _targetsLine(WorkGroup group) =>
    'targets: ${group.targets.join(', ')}\n';

/// Returns [group]'s `--json` entry: its number, unit addresses, targets, and
/// size, then the keys of its `--out --json` [index] but its file's `tokens`.
Map<String, Object> _groupJson(WorkGroup group, Map<String, Object> index) => {
  'group': group.number,
  'units': [for (final unit in group.units) unit.address],
  'targets': group.targets,
  _tokensKey: group.tokens,
  for (final MapEntry(:key, :value) in index.entries)
    if (key != _tokensKey) key: value,
};

// MARK: - Cross-group links

/// The linked doc pairs between work units of two groups, read from one pass
/// over the index links.
final class _CrossGroupLinks {
  new(List<IndexedLink> links, this._groups) {
    final groupOf = <WorkUnit, WorkGroup>{};
    final unitOf = <String, WorkUnit>{};
    for (final group in _groups) {
      for (final unit in group.units) {
        groupOf[unit] = group;
        for (final path in unit.docPaths) {
          unitOf[path] = unit;
        }
      }
    }
    for (final IndexedLink(:source, :target) in links) {
      final from = unitOf[source];
      final to = unitOf[target];
      if (from == null || to == null || groupOf[from] == groupOf[to]) continue;
      final pair = _pairKey(source, target);
      ((_pairs[from] ??= {})[to] ??= {}).add(pair);
      ((_pairs[to] ??= {})[from] ??= {}).add(pair);
    }
  }

  final List<WorkGroup> _groups;

  /// The distinct linked doc pairs, by unit and then by the other group's
  /// unit.
  final Map<WorkUnit, Map<WorkUnit, Set<String>>> _pairs = {};

  /// Returns the `Cross-group links:` part that ends [group]'s read-first
  /// file, a blank line before it: one line per pair of units, one in [group]
  /// and one in another, else `none`.
  String partOf(WorkGroup group) {
    final lines = [
      for (final unit in group.units)
        for (final other in _groups)
          if (other != group)
            for (final otherUnit in other.units)
              if (_pairs[unit]?[otherUnit]?.length case final count?)
                _crossGroupLine(unit, otherUnit, other, count),
    ];
    if (lines.isEmpty) return '\n$_crossGroupHeading none\n';
    return '\n$_crossGroupHeading\n${lines.join()}';
  }
}

/// Returns `- <unit address> <-> <unit address> (group <m>) · <n> links`.
String _crossGroupLine(
  WorkUnit unit,
  WorkUnit otherUnit,
  WorkGroup other,
  int count,
) =>
    '- ${unit.address} <-> ${otherUnit.address} '
    '(group ${other.number}) · $count links\n';

/// Returns one key for the doc pair of [a] and [b], whichever links the other.
String _pairKey(String a, String b) =>
    a.compareTo(b) < 0 ? '$a$_pairJoint$b' : '$b$_pairJoint$a';
