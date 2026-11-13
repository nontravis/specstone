import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _htmlComment = RegExp(r'<!--[\s\S]*?-->');

const _summaryNextStep =
    'Read a summary doc whole with: specstone context <name> --for implement';

String _overBudgetLine(IndexedDoc doc, bool summary, int tokens) =>
    '- ${_listName(doc, summary)} · $tokens tokens\n';

/// Returns the closing-list name of [doc], marked ` · summary` when [summary].
String _listName(IndexedDoc doc, bool summary) =>
    summary ? '${nameWithType(doc)} · summary' : nameWithType(doc);

/// Returns the header line that names the code target a `--code` path lies
/// in, or '' when there is none to name (one target).
String _codeTargetLine(String? name) =>
    name == null ? '' : '==> code target: $name <==\n';

/// Renders [bundle]'s docs as one `context` answer (`index_query/get_task_bundle/trim_and_order_bundle`).
///
/// [label] is the target as given, or the code path for `--code`; [byCode]
/// prints it under the JSON key `code` instead of `target`, with the picked
/// `codeTarget` when the project has two or more. A bundle larger than [budget]
/// prints its sizes and the next step instead of doc text, with exit status 1
/// (`index_query/get_task_bundle/refuse_bundle_over_budget`); an equal one prints whole.
ReadAnswer answerContext(
  DocIndex index,
  Bundle bundle, {
  required String label,
  required bool byCode,
  int? budget,
}) {
  final ordered = _orderedDocs(index, bundle);
  final summaryOnly = bundle.summaryOnly;
  bool inSummary(IndexedDoc doc) => summaryOnly.contains(doc.docPath);
  final docBlocks = [
    for (final doc in ordered)
      _docBlock(index, doc, bundle.mode, summary: inSummary(doc)),
  ];
  final mapBlocks = [
    for (final top in _byTreeOrder(index, bundle.mapTops))
      _mapBlock(index, index.at(top)!, bundle.codeTarget),
  ];
  final namesBlocks = [
    for (final top in _byTreeOrder(index, bundle.nameListTops))
      _namesBlock(index, index.at(top)!, bundle.codeTarget),
  ];
  final shown = [...docBlocks, ...mapBlocks, ...namesBlocks].join('\n\n');
  final tokens = tokenSizeOf(shown);
  final named = byCode && index.targetNames.length > 1
      ? bundle.codeTarget
      : null;
  if (budget != null && tokens > budget) {
    return _overBudget(
      ordered,
      docBlocks,
      summaryOnly,
      bundle,
      label: label,
      byCode: byCode,
      budget: budget,
      tokens: tokens,
      codeTarget: named,
    );
  }
  final list = [
    for (final doc in ordered) '- ${_listName(doc, inSummary(doc))}\n',
  ];
  final text =
      '${_codeTargetLine(named)}'
      '$shown\n'
      '==> bundle: ${ordered.length} docs, $tokens tokens <==\n'
      '${list.join()}'
      '${summaryOnly.isEmpty ? '' : '$_summaryNextStep\n'}';
  final json = <String, Object>{
    byCode ? 'code' : 'target': label,
    'codeTarget': ?named,
    'for': bundle.mode.wire,
    'tokens': tokens,
    'docs': [
      for (final (doc, block) in docBlocks.indexed)
        {
          'name': ordered[doc].name,
          'docType': ?ordered[doc].docTypeId,
          'path': ordered[doc].docPath,
          'tokens': tokenSizeOf(block),
          'text': _blockBody(block),
          if (inSummary(ordered[doc])) 'summary': true,
        },
    ],
    ..._mapJson(index, bundle.mapTops, bundle.codeTarget),
    ..._namesJson(index, bundle.nameListTops, bundle.codeTarget),
  };
  return ReadAnswer(text: text, json: json, warnings: [...bundle.warnings]);
}

/// Returns the reply for a bundle of [tokens] est. tokens that exceeds
/// [budget]: each doc's size, no doc text, and the next step (`index_query/get_task_bundle/refuse_bundle_over_budget`).
ReadAnswer _overBudget(
  List<IndexedDoc> ordered,
  List<String> docBlocks,
  Set<String> summaryOnly,
  Bundle bundle, {
  required String label,
  required bool byCode,
  required int budget,
  required int tokens,
  required String? codeTarget,
}) {
  final handOver = bundle.summary ? '$label with --summary' : label;
  final next = 'narrow the target, or hand $handOver to specstone:sdd-reader';
  final sizes = [for (final block in docBlocks) tokenSizeOf(block)];
  final lines = [
    for (final (i, doc) in ordered.indexed)
      _overBudgetLine(doc, summaryOnly.contains(doc.docPath), sizes[i]),
  ];
  final text =
      '${_codeTargetLine(codeTarget)}'
      'The bundle holds $tokens est. tokens, over the budget of $budget; '
      'no doc text is printed.\n'
      'Docs it would hold:\n'
      '${lines.join()}'
      'Next step: $next.\n';
  final json = <String, Object>{
    byCode ? 'code' : 'target': label,
    'codeTarget': ?codeTarget,
    'for': bundle.mode.wire,
    'budget': budget,
    'tokens': tokens,
    'overBudget': true,
    'docs': [
      for (final (i, doc) in ordered.indexed)
        {
          'name': doc.name,
          'docType': ?doc.docTypeId,
          'path': doc.docPath,
          'tokens': sizes[i],
          if (summaryOnly.contains(doc.docPath)) 'summary': true,
        },
    ],
    'next': next,
  };
  return ReadAnswer(
    text: text,
    json: json,
    warnings: [...bundle.warnings],
    exitStatus: 1,
  );
}

/// Returns [bundle]'s docs in bundle order: the joined docs in tree order,
/// then a pre-order walk from each doc of `docPaths` and `summaryPaths` whose
/// parent is outside both, children inside both sorted by chain type first,
/// then doc type id, then DocPath, by code point (INV-15). The walk drops a
/// joined doc, which prints once, whole.
List<IndexedDoc> _orderedDocs(DocIndex index, Bundle bundle) {
  final inDocPaths = {...bundle.docPaths, ...bundle.summaryPaths};
  final roots = [
    for (final doc in index.docs)
      if (inDocPaths.contains(doc.docPath) &&
          (doc.parentPath == null || !inDocPaths.contains(doc.parentPath)))
        doc,
  ];
  final walkOrder = <IndexedDoc>[];
  for (final root in roots) {
    _walk(index, root, inDocPaths, walkOrder);
  }
  return [
    for (final doc in index.docs)
      if (bundle.joinedPaths.contains(doc.docPath)) doc,
    for (final doc in walkOrder)
      if (!bundle.joinedPaths.contains(doc.docPath)) doc,
  ];
}

void _walk(
  DocIndex index,
  IndexedDoc doc,
  Set<String> inDocPaths,
  List<IndexedDoc> out,
) {
  out.add(doc);
  final children = [
    for (final child in index.childrenOf(doc))
      if (inDocPaths.contains(child.docPath)) child,
  ]..sort(_compareSiblings(index));
  for (final child in children) {
    _walk(index, child, inDocPaths, out);
  }
}

int Function(IndexedDoc, IndexedDoc) _compareSiblings(DocIndex index) =>
    (a, b) {
      final aChain = index.isChainDoc(a) ? 0 : 1;
      final bChain = index.isChainDoc(b) ? 0 : 1;
      if (aChain != bChain) return aChain - bChain;
      final byType = compareCodePoints(a.docTypeId ?? '', b.docTypeId ?? '');
      if (byType != 0) return byType;
      return compareCodePoints(a.docPath, b.docPath);
    };

/// Returns the doc block of [doc] for [mode]: its naming line, then its
/// frontmatter text, head, and kept sections, each trimmed at its end and
/// joined by one blank line (Plan decision 21, INV-14).
String _docBlock(
  DocIndex index,
  IndexedDoc doc,
  BundleMode mode, {
  required bool summary,
}) {
  final content = index.contentOf(doc);
  final docType = index.typeOf(doc);
  final parts = <String>[];
  if (summary) {
    final title = doc.title;
    if (title != null) parts.add('# $title');
    parts.addAll(_summaryBlocks(content, docType, mode));
    return '${namingLine(doc, summary: true)}\n${parts.join('\n\n')}';
  }
  if (mode != BundleMode.query) {
    final frontmatter = content.frontmatterText;
    if (frontmatter != null) parts.add(frontmatter.trimRight());
    final head = _removeComments(content.head);
    if (head.trim().isNotEmpty) parts.add(head.trimRight());
  }
  for (final section in _keptSections(content, docType, mode)) {
    parts.add(_sectionBlock(section));
  }
  return '${namingLine(doc)}\n${parts.join('\n\n')}';
}

/// Returns the kept sections of a summary doc whose merged section is a
/// summary section, in section order (INV-25).
Iterable<String> _summaryBlocks(
  DocContent content,
  MergedDocType? docType,
  BundleMode mode,
) {
  final summaryIds = {
    for (final section in docType?.sections ?? const <MergedSection>[])
      if (section.summary == true) section.id,
  };
  return [
    for (final section in _keptSections(content, docType, mode))
      if (summaryIds.contains(section.key)) _sectionBlock(section),
  ];
}

String _sectionBlock(IndexedSection section) =>
    '${section.headerLine}\n${_removeComments(section.body).trimRight()}';

/// Returns the sections [content] keeps for [mode], in its doc type's section
/// order, a section the type does not define after them in file order
/// (INV-15). A section is kept unless, with HTML comments removed and both
/// ends trimmed, its body equals its merged section's `template` likewise
/// cleaned, or is `N/A`, or starts with `N/A —`; in `query` only the sections
/// whose merged section is a query section stay (INV-14).
List<IndexedSection> _keptSections(
  DocContent content,
  MergedDocType? docType,
  BundleMode mode,
) {
  final merged = {
    for (final section in docType?.sections ?? const <MergedSection>[])
      section.id: section,
  };
  final kept = <IndexedSection>[];
  final undefined = <IndexedSection>[];
  for (final section in content.sections) {
    if (_kept(section, merged[section.key], mode)) {
      (merged.containsKey(section.key) ? kept : undefined).add(section);
    }
  }
  final inTemplateOrder = [
    for (final section in docType?.sections ?? const <MergedSection>[])
      for (final candidate in kept)
        if (candidate.key == section.id) candidate,
  ];
  return [...inTemplateOrder, ...undefined];
}

bool _kept(IndexedSection section, MergedSection? merged, BundleMode mode) {
  if (mode == BundleMode.query && merged?.query != true) return false;
  if (merged == null) return _naChecked(section.body);
  final body = _cleaned(section.body);
  final template = merged.template;
  if (template != null && body == _cleaned(template)) return false;
  return _naChecked(section.body);
}

bool _naChecked(String body) {
  final cleaned = _cleaned(body);
  return cleaned != 'N/A' && !cleaned.startsWith('N/A —');
}

/// Returns [text] with every HTML comment removed, except one whose `<!--`
/// sits in fenced code or an inline code span.
///
/// A comment runs to the first `-->` whatever it holds, so a backtick or a
/// fence line inside a comment never hides it.
String _removeComments(String text) {
  final code = _codeRanges(text);
  final kept = StringBuffer();
  var from = 0;
  var search = 0;
  while (true) {
    final comment = _htmlComment.allMatches(text, search).firstOrNull;
    if (comment == null) break;
    if (code.any((r) => r.start <= comment.start && comment.start < r.end)) {
      search = comment.start + 1;
      continue;
    }
    kept.write(text.substring(from, comment.start));
    from = search = comment.end;
  }
  return (kept..write(text.substring(from))).toString();
}

/// Returns the offsets of each fenced line and each inline code span of [text].
List<({int start, int end})> _codeRanges(String text) {
  final lines = text.split('\n');
  final fenced = fencedLines([
    for (final line in lines) line.replaceFirst(RegExp(r'\r$'), ''),
  ]);
  final ranges = <({int start, int end})>[];
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    if (fenced[i]) {
      ranges.add((start: offset, end: offset + lines[i].length));
    } else {
      for (final (:start, :end, ticks: _) in codeSpansOf(lines[i])) {
        ranges.add((start: offset + start, end: offset + end));
      }
    }
    offset += lines[i].length + 1;
  }
  return ranges;
}

/// Returns [text] with HTML comments removed and both ends trimmed.
String _cleaned(String text) => _removeComments(text).trim();

/// Returns the map block of [top]: its subtree, one line per doc with its
/// name, doc type, and token size, indented two spaces per depth below [top]
/// (Plan decision 13); [codeTarget] keeps that target's per-target docs alone.
String _mapBlock(DocIndex index, IndexedDoc top, String? codeTarget) {
  final lines = [
    for (final member in index.subtreeOf(top))
      if (member.inTarget(codeTarget)) _mapLine(index, top, member),
  ];
  return '==> map: ${nameWithType(top)} <==\n${lines.join('\n')}';
}

String _mapLine(DocIndex index, IndexedDoc top, IndexedDoc member) =>
    '${' ' * (2 * _depthBelow(index, top, member))}'
    '- ${nameWithType(member)} · ${member.tokens} tokens';

/// Returns the names block of [top]: one `- <name> (<doc type>) · <n> tokens`
/// line per ChainType child of [top] (Plan decision 13); [codeTarget] keeps
/// that target's per-target children alone.
String _namesBlock(DocIndex index, IndexedDoc top, String? codeTarget) {
  final lines = [
    for (final child in index.childrenOf(top))
      if (index.isChainDoc(child) && (child.inTarget(codeTarget)))
        '- ${nameWithType(child)} · ${child.tokens} tokens',
  ];
  return '==> names: ${nameWithType(top)} <==\n${lines.join('\n')}';
}

int _depthBelow(DocIndex index, IndexedDoc top, IndexedDoc doc) {
  var depth = 0;
  for (
    var member = doc;
    member.docPath != top.docPath;
    member = index.parentOf(member)!
  ) {
    depth++;
  }
  return depth;
}

/// Returns each DocPath of [paths] in tree order.
List<String> _byTreeOrder(DocIndex index, Set<String> paths) => [
  for (final doc in index.docs)
    if (paths.contains(doc.docPath)) doc.docPath,
];

/// Returns the block after its naming line, trimmed at both ends: the doc's
/// JSON `text`.
String _blockBody(String block) =>
    block.substring(block.indexOf('\n') + 1).trim();

Map<String, Object> _mapJson(
  DocIndex index,
  Set<String> tops,
  String? codeTarget,
) => {
  if (tops.isNotEmpty)
    'map': [
      for (final top in _byTreeOrder(index, tops))
        _docJson(index, index.at(top)!, codeTarget),
    ],
};

Map<String, Object> _docJson(
  DocIndex index,
  IndexedDoc doc,
  String? codeTarget,
) => {
  'name': doc.name,
  'docType': ?doc.docTypeId,
  'path': doc.docPath,
  'tokens': doc.tokens,
  'children': [
    for (final child in index.childrenOf(doc))
      if (child.inTarget(codeTarget)) _docJson(index, child, codeTarget),
  ],
};

Map<String, Object> _namesJson(
  DocIndex index,
  Set<String> tops,
  String? codeTarget,
) => {
  if (tops.isNotEmpty)
    'names': [
      for (final top in _byTreeOrder(index, tops))
        for (final child in index.childrenOf(index.at(top)!))
          if (index.isChainDoc(child) && (child.inTarget(codeTarget)))
            {
              'name': child.name,
              'docType': ?child.docTypeId,
              'path': child.docPath,
              'tokens': child.tokens,
            },
    ],
};
