import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// The most hits `specstone search` prints when `--limit` is absent.
const defaultSearchLimit = 20;

const _minQueryLength = 3;
final _whitespaceRun = RegExp(r'\s+');

/// The filters and cap `specstone search` applies to its hits.
final class SearchOptions {
  const new({this.docTypeId, this.under, this.limit = defaultSearchLimit});

  /// Keeps hits in docs of this doc type; untyped docs never match.
  final String? docTypeId;

  /// Keeps hits in the subtrees of the docs this name addresses.
  final String? under;

  /// The most hits the answer holds.
  final int limit;
}

/// Throws an [IndexFault] unless [query] holds at least 3 code points.
void checkQuery(String query) {
  if (query.runes.length < _minQueryLength) {
    throw IndexFault(
      IndexFaultCode.queryTooShort,
      'a search needs at least $_minQueryLength characters: $query',
    );
  }
}

/// Returns the hits for [query], best match first, at most `options.limit`.
///
/// The query matches as one substring, every FTS5 operator escaped. Throws an
/// `IndexFault` for a short query or an `under` no doc carries, and a
/// [TemplateFault] for a doc type id the set lacks.
ReadAnswer answerSearch(DocIndex index, String query, SearchOptions options) {
  checkQuery(query);
  final typeId = options.docTypeId;
  if (typeId != null && index.set.lookup(typeId) == null) {
    throw TemplateFault(
      FaultCode.docTypeUnknown,
      'Could not find a doc type named "$typeId".',
    );
  }
  final under = options.under;
  final scope = under == null
      ? null
      : {for (final doc in index.under(under)) doc.docPath};
  final hits = <({IndexedDoc doc, SearchRow row})>[];
  final seen = <String>{};
  for (final row in index.search('"${query.replaceAll('"', '""')}"')) {
    if (hits.length == options.limit) break;
    final doc = index.at(row.docPath);
    if (doc == null) continue;
    if (typeId != null && doc.docTypeId != typeId) continue;
    if (scope != null && !scope.contains(doc.docPath)) continue;
    if (seen.add('${row.docPath}\u0000${row.sectionKey}')) {
      hits.add((doc: doc, row: row));
    }
  }
  return ReadAnswer(
    text: [
      for (final (:doc, :row) in hits)
        '${_headLine(doc, row)}\n  ${_oneLine(row.snippet)}\n',
    ].join(),
    json: {
      'hits': [for (final (:doc, :row) in hits) _hitJson(doc, row)],
    },
  );
}

String _headLine(IndexedDoc doc, SearchRow row) {
  final key = row.sectionKey;
  final title = doc.title;
  final typeId = doc.docTypeId;
  return '${doc.name}${key == null ? '' : '#$key'}'
      '${typeId == null ? '' : ' ($typeId)'}'
      '${title == null ? '' : ' — $title'}';
}

Map<String, Object> _hitJson(IndexedDoc doc, SearchRow row) => {
  'name': doc.name,
  'docType': ?doc.docTypeId,
  'section': ?row.sectionKey,
  'title': ?doc.title,
  'snippet': row.snippet,
};

String _oneLine(String snippet) =>
    snippet.trim().replaceAll(_whitespaceRun, ' ');
