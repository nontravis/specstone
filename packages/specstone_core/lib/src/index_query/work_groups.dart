import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// The est. tokens one work group holds, one agent's work, bar a lone work
/// unit past it.
const int workGroupBudget = 50000;

/// The docs of one or more targets that always land in one group.
final class WorkUnit {
  const new({
    required this.address,
    required this.docPaths,
    required this.tokens,
  });

  /// `<doc type>:<name>` of the unit's highest doc, whose subtree holds the
  /// rest.
  final String address;

  /// The docs its targets' picks print whole, by DocPath.
  final Set<String> docPaths;

  /// The est. tokens of [docPaths] as the bundle prints them.
  final int tokens;
}

/// The work units one agent takes, with the target arguments they come from.
final class WorkGroup {
  const new({
    required this.number,
    required this.targets,
    required this.units,
    required this.tokens,
  });

  /// The group's number, counted from 1.
  final int number;

  /// The target arguments of [units], in the call's order.
  final List<String> targets;

  /// The work units, in docs-tree order.
  final List<WorkUnit> units;

  /// The sizes of [units] plus each chain doc above them, counted once.
  final int tokens;
}

/// The work groups of one `--groups` call, with the bundle of every target
/// they were sized from, so the call picks it once.
final class WorkGroupPick {
  new({
    required this.index,
    required this.groups,
    required this.targets,
    required this.bundle,
    required this.noProject,
    required this.importedPaths,
  });

  /// The index [answer] and each group's bundle read.
  final DocIndex index;

  /// The groups, numbered from 1 in docs-tree order.
  final List<WorkGroup> groups;

  /// The call's target arguments, in the order given.
  final List<String> targets;

  /// The bundle of every target, each picked as its work unit.
  final Bundle bundle;

  /// [bundle]'s split answer: what the call writes when it gives one group,
  /// rendered when first read.
  late final ContextAnswer answer = answerContext(
    index,
    bundle,
    targets: targets,
    split: true,
  );

  /// Whether the call passed `--no-project`.
  final bool noProject;

  /// The DocPaths the host already holds, as the call gave them.
  final Set<String> importedPaths;

  /// Returns the bundle of [group]'s own targets alone, picked as [bundle]
  /// was.
  Bundle bundleOf(DocIndex index, WorkGroup group) => pickBundle(
    index,
    group.targets,
    bundle.mode,
    noProject: noProject,
    codeTarget: bundle.codeTarget,
    importedPaths: importedPaths,
    picksWorkUnits: true,
  );
}

/// Splits [targets] into work groups of at most [workGroupBudget] est.
/// tokens each, next-fit in docs-tree order; links never decide a group.
///
/// Two targets whose work units share a doc form one unit, and a unit past
/// the budget alone forms a group of its own. Every other argument is
/// [pickBundle]'s, which throws as it does.
WorkGroupPick pickWorkGroups(
  DocIndex index,
  List<String> targets,
  BundleMode mode, {
  required bool noProject,
  String? codeTarget,
  Set<String> importedPaths = const {},
}) {
  final bundle = pickBundle(
    index,
    targets,
    mode,
    noProject: noProject,
    codeTarget: codeTarget,
    importedPaths: importedPaths,
    picksWorkUnits: true,
  );
  final printed = printedDocRunesOf(index, bundle);
  final units = _unitsOf(index, bundle);
  return WorkGroupPick(
    index: index,
    groups: _filledGroups(index, units, targets, printed),
    targets: targets,
    bundle: bundle,
    noProject: noProject,
    importedPaths: importedPaths,
  );
}

/// A work unit with the target arguments, by argument index, that give it.
final class _Unit {
  const new(this.docPaths, this.argumentAt, {required this.first});

  final Set<String> docPaths;
  final Set<int> argumentAt;

  /// The unit's first doc in print order, the one whose subtree holds the
  /// rest.
  final IndexedDoc first;

  int tokensOf(Map<String, int> printed) =>
      _runesOf(docPaths, printed) ~/ runesPerToken;

  /// The chain docs above the unit's docs that the bundle prints.
  Set<String> chainAbove(DocIndex index, Map<String, int> printed) => {
    for (final path in docPaths)
      if (index.at(path) case final doc?)
        for (final above in index.chainOf(doc).skip(1))
          if (!docPaths.contains(above.docPath) &&
              printed.containsKey(above.docPath))
            above.docPath,
  };

  WorkUnit toWorkUnit(Map<String, int> printed) => WorkUnit(
    address: '${first.docTypeId}:${first.name}',
    docPaths: docPaths,
    tokens: tokensOf(printed),
  );
}

int _runesOf(Iterable<String> paths, Map<String, int> printed) =>
    [for (final path in paths) printed[path] ?? 0]
        .fold(0, (sum, runes) => sum + runes);

/// Returns the work units of [bundle]'s target arguments, two that share a
/// doc joined, in print order of their first docs.
List<_Unit> _unitsOf(DocIndex index, Bundle bundle) {
  var joined = <({Set<String> docs, Set<int> arguments})>[];
  for (final (at, picks) in bundle.argumentPicks.indexed) {
    final docs = _argumentDocPaths(index, bundle.mode, picks);
    final arguments = {at};
    final shared = [
      for (final other in joined)
        if (other.docs.any(docs.contains)) other,
    ];
    for (final other in shared) {
      docs.addAll(other.docs);
      arguments.addAll(other.arguments);
    }
    joined = [
      for (final other in joined)
        if (!shared.contains(other)) other,
      (docs: docs, arguments: arguments),
    ];
  }
  final units = <_Unit>[];
  for (final doc in bundle.printOrder(index)) {
    final at = joined.indexWhere((unit) => unit.docs.contains(doc.docPath));
    if (at < 0) continue;
    final (:docs, :arguments) = joined.removeAt(at);
    units.add(_Unit(docs, arguments, first: doc));
  }
  return units;
}

/// Returns the docs one target argument's [picks] print whole within its
/// target subtree: its work unit's docs.
Set<String> _argumentDocPaths(
  DocIndex index,
  BundleMode mode,
  List<TargetPicks> picks,
) => {
  for (final pick in picks)
    ..._subtreeOf(index, mode, pick).intersection(pick.wholePaths),
};

/// Returns the target subtree of [pick]: in `implement`, an FR or nf target
/// keeps its own subtree, never its story's, as the implement row picks it.
Set<String> _subtreeOf(DocIndex index, BundleMode mode, TargetPicks pick) {
  final target = switch (pick.targetPath) {
    final path? => index.at(path),
    null => null,
  };
  if (mode != BundleMode.implement || target == null) return pick.subtreePaths;
  return {for (final doc in index.subtreeOf(target)) doc.docPath};
}

/// Fills groups next-fit: a unit joins the open group while its size stays
/// within [workGroupBudget], else it opens the next group.
List<WorkGroup> _filledGroups(
  DocIndex index,
  List<_Unit> units,
  List<String> targets,
  Map<String, int> printed,
) {
  final filled = <List<_Unit>>[];
  for (final unit in units) {
    final open = filled.lastOrNull;
    if (open != null &&
        _groupTokensOf(index, [...open, unit], printed) <= workGroupBudget) {
      open.add(unit);
    } else {
      filled.add([unit]);
    }
  }
  return [
    for (final (at, group) in filled.indexed)
      WorkGroup(
        number: at + 1,
        targets: [
          for (final argumentAt in {
            for (final unit in group) ...unit.argumentAt,
          }.toList()..sort())
            targets[argumentAt],
        ],
        units: [for (final unit in group) unit.toWorkUnit(printed)],
        tokens: _groupTokensOf(index, group, printed),
      ),
  ];
}

/// Returns the sizes of [units] plus each chain doc above them that no unit of
/// them holds, each counted once.
int _groupTokensOf(
  DocIndex index,
  List<_Unit> units,
  Map<String, int> printed,
) {
  final held = {for (final unit in units) ...unit.docPaths};
  final above = {for (final unit in units) ...unit.chainAbove(index, printed)}
      .difference(held);
  return [
    for (final unit in units) unit.tokensOf(printed),
    for (final path in above) (printed[path] ?? 0) ~/ runesPerToken,
  ].fold(0, (sum, tokens) => sum + tokens);
}
