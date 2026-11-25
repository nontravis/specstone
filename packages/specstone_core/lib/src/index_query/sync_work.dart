import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/check_scope.dart';
import 'package:specstone_core/src/consistency_check/code_link_rules.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/code_bundle.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/folder_prune.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/out_file.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/index_query/record_entries.dart'
    show recordItemsOf;
import 'package:specstone_core/src/index_query/sync_diff_base.dart';
import 'package:specstone_core/src/index_query/sync_feature.dart';
import 'package:specstone_core/src/index_query/sync_group_file.dart';
import 'package:specstone_core/src/rendering/build_output.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

/// The most changed lines, added plus removed, a small group holds.
const _smallLineLimit = 40;

const _featureScope = 'feature';
const _separator = ':';
const _diffHunkMark = '@@';
const _diffFileMark = 'diff --git ';
const _diffBinaryMark = 'Binary files ';
const _noWorkLine = 'no code changed since its docs were compared';
const _lineSeparator = ' · ';

/// Who judges a sync group.
enum SyncRoute {
  /// Main, in one `set --sync`.
  small,

  /// An engineer, dispatched at once beside the other groups.
  engineer,
}

/// One code link of a sync group and the commit its diff is taken from.
final class SyncLinkWork {
  new({
    required this.doc,
    required this.link,
    required this.owner,
    required this.base,
    required this.coveringDocs,
    this.nestedRoots = const [],
  });

  /// The doc that holds the link's entry.
  final IndexedDoc doc;

  final CodeLink link;

  /// The doc the link is judged against: the story or FR a record entry names,
  /// else [doc]; null when a record entry's item no longer resolves.
  final IndexedDoc? owner;

  /// Null when no commit of the link's history gives its recorded fingerprint,
  /// or it records none.
  final SyncDiffBase? base;

  /// The docs whose entries name the link's code, as `coveringDocsOf` gives.
  ///
  /// The folder-wide set the small route, the task-ref candidates, and the
  /// `set --sync` draft guard read; the group file prints none of it.
  final List<IndexedDoc> coveringDocs;

  /// The code roots of the other targets nested in the link's, which a folder
  /// entry leaves out.
  final List<String> nestedRoots;

  /// The diff of the link's code since [base], read from git once; null with
  /// no base or when git fails.
  late final String? diff = _readDiff();

  /// The untracked files under a folder entry, read from git once; none for a
  /// file entry, null when git fails.
  late final List<String>? untracked = _readUntracked();

  String? _readDiff() {
    final base = this.base;
    if (base == null) return null;
    try {
      return diffSince(base);
    } on ProcessException {
      return null;
    }
  }

  List<String>? _readUntracked() {
    if (!FileSystemEntity.isDirectorySync('${link.root.path}/${link.path}')) {
      return const [];
    }
    try {
      return untrackedUnder(link.root, link.path, nestedRoots: nestedRoots);
    } on ProcessException {
      return null;
    }
  }
}

/// The findings and code links of one scope of a sync's work list.
final class SyncGroup {
  const new({
    required this.scope,
    required this.route,
    required this.findings,
    required this.links,
  });

  /// `feature:<name>` for a top-level feature, `<type>:<name>` for a doc under
  /// no feature.
  final String scope;

  final SyncRoute route;

  final List<Finding> findings;

  /// The code links the group compares, each with its diff base.
  final List<SyncLinkWork> links;
}

// MARK: - Groups

/// Returns the sync groups of [report]'s work list, by scope.
///
/// The work list is the code-pointer, test-pointer, and agent-waiting
/// matrix-row findings of the check; a [feature] names one top-level feature,
/// whose group then holds every code link that takes a state, findings or
/// not. [codeTarget] names the one code target the links are read for; null
/// reads every target. The groups sort by scope.
List<SyncGroup> syncGroupsOf(
  CheckContext context,
  CheckReport report, {
  String? feature,
  String? codeTarget,
}) {
  final index = context.index;
  final featureScope = feature == null
      ? null
      : '$_featureScope$_separator$feature';
  final findingsByScope = <String, List<Finding>>{?featureScope: []};
  for (final finding in report.findings) {
    final scope = _scopeOfFinding(context, finding);
    if (scope == null || (featureScope != null && scope != featureScope)) {
      continue;
    }
    findingsByScope.putIfAbsent(scope, () => []).add(finding);
  }
  final work = ImplementedWork(
    context,
    CheckScope.project(context, codeTarget: codeTarget).targets,
  );
  final linksByScope = {
    for (final MapEntry(key: scope, value: findings) in findingsByScope.entries)
      scope: [
        for (final doc
            in featureScope == null
                ? _docsOfCodeFindings(index, findings)
                : _docsOfScope(index, scope))
          for (final link in _linksOf(context, work, doc))
            if (featureScope != null || _isFound(findings, doc, link))
              (doc: doc, link: link),
      ],
  };
  final facts = _LinkFacts(context, [
    for (final links in linksByScope.values)
      for (final (doc: _, :link) in links) link,
  ]);
  final groups = <SyncGroup>[];
  for (final MapEntry(key: scope, value: findings) in findingsByScope.entries) {
    final links = [
      for (final (:doc, :link) in linksByScope[scope]!) facts.workOf(doc, link),
    ];
    if (findings.isEmpty && links.isEmpty) continue;
    groups.add(
      SyncGroup(
        scope: scope,
        route: _routeOf(
          context,
          findings,
          links,
          isFeatureTarget: featureScope != null,
        ),
        findings: findings,
        links: links,
      ),
    );
  }
  return groups..sort(_byScope);
}

int _byScope(SyncGroup a, SyncGroup b) => compareCodePoints(a.scope, b.scope);

/// Returns the scope [finding] joins, null when it joins no group.
String? _scopeOfFinding(CheckContext context, Finding finding) {
  if (!finding.isForAgent || !_isWorkKind(context, finding)) {
    return null;
  }
  final doc = context.index.at(finding.path);
  return doc == null ? null : _scopeOfDoc(context.index, doc);
}

/// Whether [finding] is a code-pointer, test-pointer, or matrix-row finding
/// of the work list.
///
/// A `suspect` or `unconfirmed` finding counts only on a record's matrix row;
/// on any other doc it belongs to the confirmed links, not to a sync.
bool _isWorkKind(CheckContext context, Finding finding) =>
    switch (finding.kind) {
      FindingKind.codeSuspect ||
      FindingKind.codeUnconfirmed ||
      FindingKind.implementsPathUnresolved ||
      FindingKind.implementsSymbolUnresolved ||
      FindingKind.coversPathMissing ||
      FindingKind.testsUnresolved ||
      FindingKind.matrixTestUnresolved => true,
      FindingKind.matrixRowMalformed => _isRefusedFormRow(finding),
      FindingKind.suspect ||
      FindingKind.unconfirmed => _isOnRecord(context, finding),
      _ => false,
    };

/// Whether the `matrix_row_malformed` [finding] is a refused-form row, which
/// parses as a row, not a line that is no row at all.
bool _isRefusedFormRow(Finding finding) => switch (finding.keys['row']) {
  final String row => parseMatrixLine(row, finding.line) is! MalformedRow,
  _ => false,
};

bool _isOnRecord(CheckContext context, Finding finding) {
  final doc = context.index.at(finding.path);
  return doc != null && recordDocOf(context, doc) != null;
}

/// Returns the scope of [doc]: its top-level feature, else its top doc.
String? _scopeOfDoc(DocIndex index, IndexedDoc doc) {
  final top = index.chainOf(doc).last;
  final type = top.docTypeId;
  return type == null ? null : '$type$_separator${top.name}';
}

/// Returns the docs of the top-level feature [scope] names, its own and every
/// doc nested under it.
List<IndexedDoc> _docsOfScope(DocIndex index, String scope) => [
  for (final doc in index.docs)
    if (_scopeOfDoc(index, doc) == scope) doc,
];

List<IndexedDoc> _docsOfCodeFindings(DocIndex index, List<Finding> findings) {
  final docs = <IndexedDoc>{};
  for (final finding in findings) {
    if (finding.kind != FindingKind.codeSuspect &&
        finding.kind != FindingKind.codeUnconfirmed) {
      continue;
    }
    if (index.at(finding.path) case final doc?) docs.add(doc);
  }
  return docs.toList();
}

Iterable<CodeLink> _linksOf(
  CheckContext context,
  ImplementedWork work,
  IndexedDoc doc,
) {
  final type = context.typeOf(doc);
  if (type == null) return const [];
  return codeLinksOf(
    context.index.statusTree,
    work,
    doc,
    type: type,
    projectRoot: context.projectRoot,
    codeRootOf: context.codeRootOf,
    linesOf: () => context.linesOf(doc),
  );
}

bool _isFound(List<Finding> findings, IndexedDoc doc, CodeLink link) =>
    findings.any(
      (finding) =>
          finding.path == doc.docPath &&
          finding.line == link.line &&
          (finding.kind == FindingKind.codeSuspect ||
              finding.kind == FindingKind.codeUnconfirmed),
    );

/// The diff base and covering docs of each code link of a sync, each read once
/// per code path however many entries name it.
final class _LinkFacts {
  new(this._context, List<CodeLink> links) : _bases = SyncDiffBases(links);

  final CheckContext _context;
  final SyncDiffBases _bases;
  final Map<String, List<IndexedDoc>> _coveringDocs = {};

  SyncLinkWork workOf(IndexedDoc doc, CodeLink link) {
    final nestedRoots = _nestedRootsOf(_context, link);
    // A `root: project` link has no target, unlike one of the unnamed target.
    final target = link.target;
    final code = [
      if (target == null) '' else 'target ${target.name}',
      link.root.path,
      normalCodeEntry(link.path),
    ].join('\u0000');
    return SyncLinkWork(
      doc: doc,
      link: link,
      owner: syncOwnerOf(_context, doc, link.item),
      base: _bases.of(link, nestedRoots: nestedRoots),
      coveringDocs: _coveringDocs.putIfAbsent(
        code,
        () => coveringDocsOf(_context.index, link),
      ),
      nestedRoots: nestedRoots,
    );
  }
}

/// Returns the doc an entry of [doc] is judged against: the story or FR
/// [item] names on a record, else [doc]; null when [item] no longer resolves.
IndexedDoc? syncOwnerOf(CheckContext context, IndexedDoc doc, String? item) {
  if (item == null) return doc;
  final feature = recordDocOf(context, doc)?.feature;
  if (feature == null) return null;
  return recordItemsOf(feature, context.index.childrenOf)[item];
}

List<String> _nestedRootsOf(CheckContext context, CodeLink link) =>
    switch (link.target) {
      final target? => context.nestedRootsOf(target),
      _ => const [],
    };

// MARK: - Routes

SyncRoute _routeOf(
  CheckContext context,
  List<Finding> findings,
  List<SyncLinkWork> links, {
  required bool isFeatureTarget,
}) {
  if (isFeatureTarget || !_isSmall(context, findings, links)) {
    return SyncRoute.engineer;
  }
  return SyncRoute.small;
}

/// Whether the group is only `code_suspect` findings on `covers` entries of
/// docs that are no draft, each link with a diff base and no draft among its
/// covering docs, within the line limit and with no untracked file under a
/// folder entry.
bool _isSmall(
  CheckContext context,
  List<Finding> findings,
  List<SyncLinkWork> links,
) {
  if (findings.isEmpty ||
      findings.any((finding) => finding.kind != FindingKind.codeSuspect) ||
      findings.any(
        (finding) => context.index.at(finding.path)?.isDraft ?? true,
      )) {
    return false;
  }
  if (links.isEmpty ||
      links.any(
        (work) =>
            work.link.item != null ||
            work.base == null ||
            work.coveringDocs.any((doc) => doc.isDraft),
      )) {
    return false;
  }
  var changed = 0;
  final seen = <String>{};
  for (final work in links) {
    if (!seen.add('${work.link.root.path}/${work.link.path}')) continue;
    if (work.untracked?.isNotEmpty ?? true) return false;
    final lines = _changedLinesOf(work.diff);
    if (lines == null) return false;
    changed += lines;
    if (changed > _smallLineLimit) return false;
  }
  return true;
}

/// Returns the lines added plus removed in [diff]; null when git failed or the
/// diff holds a binary file.
int? _changedLinesOf(String? diff) {
  if (diff == null) return null;
  var count = 0;
  var isInHunk = false;
  for (final line in const LineSplitter().convert(diff)) {
    if (line.startsWith(_diffBinaryMark)) return null;
    if (line.startsWith(_diffFileMark)) {
      isInHunk = false;
    } else if (line.startsWith(_diffHunkMark)) {
      isInHunk = true;
    } else if (isInHunk && (line.startsWith('+') || line.startsWith('-'))) {
      count++;
    }
  }
  return count;
}

// MARK: - Answer

/// Runs the check once, groups its work list, and writes one file per group
/// under the reports folder; returns the stdout index.
///
/// [feature] names the one top-level feature to sync, else every group of the
/// project is listed. [codeTarget] names the one code target the work is read
/// for. An empty work list writes no file. Throws `argument_invalid` for a
/// [feature] that is no top-level feature, and `output_not_writable` for a
/// file that may not be written, before any file is written.
Future<ReadAnswer> answerSyncWork(
  ReadSession session, {
  String? feature,
  String? codeTarget,
}) async {
  final name = feature == null
      ? null
      : syncFeatureOf(session.index, feature, codeTarget: codeTarget).name;
  final report = await runCheck(session, codeTarget: codeTarget);
  final groups = syncGroupsOf(
    CheckContext(session),
    report,
    feature: name,
    codeTarget: codeTarget,
  );
  if (groups.isEmpty) {
    return ReadAnswer(
      text: '$_noWorkLine\n',
      json: {'groups': <Object>[]},
      warnings: report.warnings,
    );
  }
  final paths = _writeGroupFiles(session, groups, codeTarget: codeTarget);
  return ReadAnswer(
    text: [
      for (final (i, group) in groups.indexed)
        [group.scope, group.route.name, paths[i]].join(_lineSeparator),
    ].map((line) => '$line\n').join(),
    json: {
      'groups': [
        for (final (i, group) in groups.indexed)
          {'scope': group.scope, 'route': group.route.name, 'out': paths[i]},
      ],
    },
    warnings: report.warnings,
  );
}

/// Writes one file per group of [groups] under the reports folder, each whole,
/// and returns their canonical paths in order.
///
/// Every path is judged before any file is written, and old reports are
/// pruned once all are.
List<String> _writeGroupFiles(
  ReadSession session,
  List<SyncGroup> groups, {
  String? codeTarget,
}) {
  final project = session.project;
  final paths = [
    for (final group in groups)
      canonicalPath(
        bareOutFile(
          project.projectRoot,
          bundleFileName(
            targets: [group.scope],
            mode: BundleMode.sync,
            summary: false,
            noProject: false,
            codeTarget: codeTarget,
          ),
        ).absolute.path,
      ),
  ];
  for (final path in paths) {
    requireOutPath(
      path,
      projectRoot: project.projectRoot,
      docsRoot: project.docsRoot,
      isBare: true,
    );
  }
  for (final (i, group) in groups.indexed) {
    writeBuildOutput(
      File(paths[i]),
      utf8.encode(syncGroupText(session, group)),
      displayPath: paths[i],
    );
  }
  pruneSpecstoneFolder(
    project.projectRoot,
    keep: paths.toSet(),
    bounds: project.cleanup,
    now: DateTime.now(),
  );
  return paths;
}
