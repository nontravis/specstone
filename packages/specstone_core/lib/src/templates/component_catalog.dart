import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/sentences.dart' show sentencesOf;
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show relativeHref;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The kind of the block that lists the component docs.
const componentCatalogKind = 'component_catalog';

const _componentTypeId = 'component';
const _catalogSectionId = 'component_catalog';
const _purposeSectionId = 'purpose';
const _lifecycleKey = 'lifecycle';
const _noValue = '—';
const _tableHead =
    '| Component | Group | Purpose | Lifecycle | Doc |\n'
    '|---|---|---|---|---|';

final _lineBreak = RegExp(r'\s*\n\s*');
final _unescapedPipe = RegExp(r'(?<!\\)\|');

// MARK: - Generator

/// Returns the catalog block for the top of the `component_catalog` section of
/// the doc at [docPath].
List<GeneratedBlock> componentCatalogBlocks(
  Doc doc,
  String docPath,
  MergedDocType docType,
  DocIndex index,
) => [
  GeneratedBlock(
    kind: componentCatalogKind,
    sectionId: _catalogSectionId,
    place: const SectionTop(),
    text: componentCatalogText(index, docPath),
  ),
];

/// Returns the catalog without marker lines: a table with one row per
/// `component` doc in tree order.
///
/// A project with no component doc gets the header rows alone. Links reach the
/// component docs from the discovery doc at [discoveryDocPath].
String componentCatalogText(DocIndex index, String discoveryDocPath) => [
  _tableHead,
  for (final doc in index.docs)
    if (doc.docTypeId == _componentTypeId) _row(index, doc, discoveryDocPath),
].join('\n');

// MARK: - Rows

String _row(DocIndex index, IndexedDoc component, String discoveryDocPath) {
  final cells = [
    _cell(component.name),
    _cell(index.parentOf(component)?.name ?? ''),
    _cell(_purposeOf(index, component)),
    _cell(component.valuesOf(_lifecycleKey).firstOrNull ?? ''),
    _docLink(component, discoveryDocPath),
  ];
  return '| ${cells.map((c) => c.isEmpty ? _noValue : c).join(' | ')} |';
}

/// Returns the first sentence of the `## Purpose` of [component], or an empty
/// string when the section is missing or holds no sentence.
String _purposeOf(DocIndex index, IndexedDoc component) {
  for (final section in index.contentOf(component).sections) {
    if (section.key == _purposeSectionId) {
      return sentencesOf(section.body).firstOrNull ?? '';
    }
  }
  return '';
}

String _docLink(IndexedDoc component, String discoveryDocPath) {
  final href = relativeHref(discoveryDocPath, component.docPath);
  return '[${_cell(component.docPath)}]($href)';
}

/// Returns [text] as one table cell: line breaks become spaces and each `|` not
/// written `\|` is escaped.
String _cell(String text) =>
    text.trim().replaceAll(_lineBreak, ' ').replaceAll(_unescapedPipe, r'\|');
