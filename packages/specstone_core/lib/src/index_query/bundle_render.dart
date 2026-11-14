import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_follow.dart';
import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';

const _summaryNextStep =
    'Read a summary doc whole with: specstone context <name> --for implement';

String _overBudgetLine(String listName, int tokens) =>
    '- $listName · $tokens tokens\n';

/// Returns the closing-list name of [doc], marked ` · summary` when [summary].
String _listName(IndexedDoc doc, bool summary) =>
    summary ? '${nameWithType(doc)} · summary' : nameWithType(doc);

/// Returns the closing-list name of [part],
/// `<name> (<doc type>) · cited <section key> [<ID>]`; a summary doc's is
/// marked ` · summary` before ` · cited` (`trim_and_order_bundle` E15).
String _partListName(AppendedPart part) =>
    '${_listName(part.doc, part.summary)} · cited'
    '${part.sectionKey == null ? '' : ' ${part.sectionKey}'}'
    '${part.itemId == null ? '' : ' [${part.itemId}]'}';

/// Returns the block of [part]: its naming line, `<DocPath>#<section key>`
/// with ` · item <ID>` for an item, or `<DocPath> · summary` for a doc, then
/// ` · cited`, then its text.
String _partBlock(AppendedPart part) {
  final doc = part.doc;
  final key = part.sectionKey;
  final path = key == null ? doc.docPath : '${doc.docPath}#$key';
  final item = part.itemId == null ? '' : ' · item ${part.itemId}';
  final summary = part.summary ? ' · summary' : '';
  return '==> ${nameWithType(doc)} · $path$item$summary · cited <==\n'
      '${part.text}';
}

/// Returns the JSON keys that mark [part], after its `text` or `tokens`.
Map<String, Object> _partKeys(AppendedPart part) => {
  if (part.summary) 'summary': true,
  'cited': true,
  'section': ?part.sectionKey,
  'item': ?part.itemId,
};

/// Returns the header line that names the code target a `--code` path lies
/// in, or '' when there is none to name (one target).
String _codeTargetLine(String? name) =>
    name == null ? '' : '==> code target: $name <==\n';

/// Renders [bundle]'s docs as one `context` answer (`index_query/get_task_bundle/trim_and_order_bundle`).
///
/// The parts the bundle's links cite print after its docs
/// (`index_query/get_task_bundle/follow_cited_links`). [label] is the target
/// as given, or the code path for `--code`; [byCode] prints it under the JSON
/// key `code` instead of `target`, with the picked `codeTarget` when the
/// project has two or more. A bundle larger than [budget] prints its sizes
/// and the next step instead of doc text, with exit status 1
/// (`index_query/get_task_bundle/refuse_bundle_over_budget`); an equal one prints whole.
ReadAnswer answerContext(
  DocIndex index,
  Bundle bundle, {
  required String label,
  required bool byCode,
  int? budget,
}) {
  final ordered = bundle.printOrder(index);
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
  final parts = followLinks(index, bundle);
  final partBlocks = [for (final part in parts) _partBlock(part)];
  final shown = [
    ...docBlocks,
    ...mapBlocks,
    ...namesBlocks,
    ...partBlocks,
  ].join('\n\n');
  final tokens = tokenSizeOf(shown);
  final named = byCode && index.hasTwins ? bundle.codeTarget : null;
  if (budget != null && tokens > budget) {
    return _overBudget(
      ordered,
      docBlocks,
      summaryOnly,
      bundle,
      parts: parts,
      partBlocks: partBlocks,
      label: label,
      byCode: byCode,
      budget: budget,
      tokens: tokens,
      codeTarget: named,
    );
  }
  final list = [
    for (final doc in ordered) '- ${_listName(doc, inSummary(doc))}\n',
    for (final part in parts) '- ${_partListName(part)}\n',
  ];
  final listsSummary =
      summaryOnly.isNotEmpty || parts.any((part) => part.summary);
  final text =
      '${_codeTargetLine(named)}'
      '$shown\n'
      '==> bundle: ${ordered.length} docs, $tokens tokens <==\n'
      '${list.join()}'
      '${listsSummary ? '$_summaryNextStep\n' : ''}';
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
      for (final (i, part) in parts.indexed)
        {
          ..._partDocJson(part, partBlocks[i]),
          'text': _blockBody(partBlocks[i]),
          ..._partKeys(part),
        },
    ],
    ..._mapJson(index, bundle.mapTops, bundle.codeTarget),
    ..._namesJson(index, bundle.nameListTops, bundle.codeTarget),
  };
  return ReadAnswer(text: text, json: json, warnings: [...bundle.warnings]);
}

/// Returns the name, doc type, path, and printed size of [part], whose block
/// is [block].
Map<String, Object> _partDocJson(AppendedPart part, String block) => {
  'name': part.doc.name,
  'docType': ?part.doc.docTypeId,
  'path': part.doc.docPath,
  'tokens': tokenSizeOf(block),
};

/// Returns the reply for a bundle of [tokens] est. tokens that exceeds
/// [budget]: each doc's and part's size, no doc text, and the next step (`index_query/get_task_bundle/refuse_bundle_over_budget`).
ReadAnswer _overBudget(
  List<IndexedDoc> ordered,
  List<String> docBlocks,
  Set<String> summaryOnly,
  Bundle bundle, {
  required List<AppendedPart> parts,
  required List<String> partBlocks,
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
      _overBudgetLine(
        _listName(doc, summaryOnly.contains(doc.docPath)),
        sizes[i],
      ),
    for (final (i, part) in parts.indexed)
      _overBudgetLine(_partListName(part), tokenSizeOf(partBlocks[i])),
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
      for (final (i, part) in parts.indexed)
        {..._partDocJson(part, partBlocks[i]), ..._partKeys(part)},
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
  if (summary) {
    return '${namingLine(doc, summary: true)}\n'
        '${summaryBodyOf(doc, content, docType, mode)}';
  }
  final parts = <String>[];
  if (mode != BundleMode.query) {
    final frontmatter = content.frontmatterText;
    if (frontmatter != null) parts.add(frontmatter.trimRight());
    final head = removeHtmlComments(content.head);
    if (head.trim().isNotEmpty) parts.add(head.trimRight());
  }
  for (final section in keptSectionsOf(content, docType, mode)) {
    parts.add(sectionBlockOf(section));
  }
  return '${namingLine(doc)}\n${parts.join('\n\n')}';
}

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
