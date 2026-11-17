import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

const _summaryKey = 'summary';

/// The filters `specstone list` applies; a doc must pass every one given.
final class ListFilters {
  const new({
    this.status,
    this.draft = false,
    this.under,
    this.cites,
    this.slug,
    this.noImplements = false,
    this.codeTarget,
  });

  /// Keeps docs whose status, computed for a feature, equals this.
  final String? status;

  /// Keeps docs whose `draft` is `true`.
  final bool draft;

  /// Keeps the subtrees of the docs this name addresses.
  final String? under;

  /// Keeps docs whose frontmatter holds this value, equal as text.
  final String? cites;

  /// Keeps docs whose `slug` aliases hold this value.
  final String? slug;

  /// Keeps docs whose `implements` field holds no entry.
  final bool noImplements;

  /// The code target [status] and [noImplements] judge in, and [under] stays
  /// in; null judges the project's one unnamed target.
  final String? codeTarget;
}

/// Returns the docs of [docTypeId] that pass [filters], in tree order.
///
/// A doc holding a string `summary` ends its line with ` — <summary>` and
/// carries a `summary` key in JSON.
///
/// Throws a [TemplateFault] for a doc type id the set lacks, an
/// `IndexFault` `argument_missing` when [ListFilters.status] or
/// [ListFilters.noImplements] judges two or more code targets at once, and
/// an `IndexFault` `doc_not_found` when `under` addresses no doc. Untyped
/// docs never match.
ReadAnswer answerList(DocIndex index, String docTypeId, ListFilters filters) {
  if (index.set.lookup(docTypeId) == null) {
    throw TemplateFault(
      FaultCode.docTypeUnknown,
      'Could not find a doc type named "$docTypeId".',
    );
  }
  _refuseAmbiguousTarget(index, filters);
  index.checkCodeTarget(filters.codeTarget);
  final codeTarget = filters.codeTarget;
  final under = filters.under;
  final scope = under == null
      ? null
      : {
          for (final doc in index.under(under, codeTarget: codeTarget))
            doc.docPath,
        };
  final docs = [
    for (final doc in index.docs)
      if (doc.docTypeId == docTypeId && _passes(index, doc, filters, scope))
        doc,
  ];
  return ReadAnswer(
    text: [for (final doc in docs) _listLine(index, doc, codeTarget)].join(),
    json: {
      'docs': [for (final doc in docs) _listJson(index, doc, codeTarget)],
    },
  );
}

/// Returns [doc]'s `structure` line, ` — <summary>` and a line end after it.
String _listLine(DocIndex index, IndexedDoc doc, String? codeTarget) {
  final line = docLineWithStatus(doc, statusPartOf(index, doc, codeTarget));
  final summary = doc.stringValueOf(_summaryKey);
  return summary == null ? '$line\n' : '$line — $summary\n';
}

/// Returns [doc]'s JSON object with a `summary` key when it holds a string.
Map<String, Object> _listJson(
  DocIndex index,
  IndexedDoc doc,
  String? codeTarget,
) => {
  ...docJsonWithStatuses(index, doc, codeTarget),
  'summary': ?doc.stringValueOf(_summaryKey),
};

/// Throws `argument_missing` when a per-target filter would judge two or
/// more code targets at once with no target picked.
void _refuseAmbiguousTarget(DocIndex index, ListFilters filters) {
  final judgesTarget = filters.status != null || filters.noImplements;
  if (!judgesTarget || filters.codeTarget != null) return;
  if (!index.hasTwins) return;
  throw IndexFault(
    IndexFaultCode.argumentMissing,
    '--status and --no-implements need --target with two or more code '
    'targets; the targets are ${index.targetNames.join(', ')}',
  );
}

bool _passes(
  DocIndex index,
  IndexedDoc doc,
  ListFilters filters,
  Set<String>? scope,
) {
  final status = filters.status;
  final cites = filters.cites;
  final slug = filters.slug;
  return (status == null ||
          index.statusOf(doc, codeTarget: filters.codeTarget) == status) &&
      (!filters.draft || doc.isDraft) &&
      (scope == null || scope.contains(doc.docPath)) &&
      (cites == null || _cites(doc, cites)) &&
      (slug == null || doc.valuesOf('slug').contains(slug)) &&
      (!filters.noImplements || _namesNoCode(index, doc, filters.codeTarget));
}

/// Whether no record entry of [codeTarget] names code for the story or FR
/// [doc], no entry included; a set with no record doc type reads the doc's
/// own `implements` field instead.
bool _namesNoCode(DocIndex index, IndexedDoc doc, String? codeTarget) {
  if (index.set.recordDocType == null) {
    return doc.valuesOf('implements').isEmpty;
  }
  return index.recordEntryOf(doc, codeTarget: codeTarget)?.codePaths.isEmpty ??
      true;
}

bool _cites(IndexedDoc doc, String value) =>
    doc.frontmatter.keys.any((key) => doc.valuesOf(key).contains(value));
