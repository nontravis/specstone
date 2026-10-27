import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One reference as printed: its text line and its JSON object.
final class _Ref {
  const new({required this.text, required this.json});

  /// Returns the reference of [kind] that targets [doc].
  factory toDoc(String kind, IndexedDoc doc) => _Ref(
    text: '- $kind: ${nameWithType(doc)}',
    json: {'kind': kind, 'name': doc.name, 'docType': ?doc.docTypeId},
  );

  /// Returns the reference of [kind] that points at [pointer] as written.
  factory toPointer(String kind, String pointer) =>
      _Ref(text: '- $kind: $pointer', json: {'kind': kind, 'pointer': pointer});

  /// The line `- <kind>: <target>` this reference prints as.
  final String text;

  /// The JSON object with either `name` and `docType` or `pointer`.
  final Map<String, Object> json;
}

/// Returns the references of each doc [address] names, outbound and inbound.
///
/// Outbound holds each `doc_ref` field value that resolves, each doc the doc
/// links to, and the `implements` and `covers` pointers as written. Inbound
/// holds the docs whose `doc_ref` value reaches the doc, then those linking
/// to it, each group in tree order of the referring docs. Throws an
/// [IndexFault] when no doc carries the name.
ReadAnswer answerRefs(DocIndex index, String address) {
  final inboundByPath = _inboundByPath(index);
  final answers = [
    for (final doc in index.resolve(address))
      _answerFor(index, doc, inboundByPath),
  ];
  return ReadAnswer(
    text: [for (final answer in answers) answer.text].join(),
    json: {
      'docs': [for (final answer in answers) answer.json],
    },
  );
}

({String text, Map<String, Object> json}) _answerFor(
  DocIndex index,
  IndexedDoc doc,
  Map<String, List<_Ref>> inboundByPath,
) {
  final outbound = _outbound(index, doc);
  final inbound = [
    ...?inboundByPath[doc.docPath],
    for (final from in index.linkingTo(doc)) _Ref.toDoc('link', from),
  ];
  final text = StringBuffer('${namingLine(doc)}\n')
    ..writeln('Outbound')
    ..write(_groupLines(outbound))
    ..writeln('Inbound')
    ..write(_groupLines(inbound));
  return (
    text: text.toString(),
    json: {
      'name': doc.name,
      'docType': ?doc.docTypeId,
      'path': doc.docPath,
      'outbound': [for (final ref in outbound) ref.json],
      'inbound': [for (final ref in inbound) ref.json],
    },
  );
}

/// Returns the outbound references of [doc]: its `doc_ref` fields in field
/// order, the docs it links to, then the `implements` and `covers` pointers.
List<_Ref> _outbound(DocIndex index, IndexedDoc doc) {
  final refs = <_Ref>[];
  for (final field in _docRefFields(index, doc)) {
    for (final value in doc.valuesOf(field.id)) {
      refs.addAll([
        for (final target in _carrying(index, field, value))
          _Ref.toDoc(field.id, target),
      ]);
    }
  }
  refs.addAll([
    for (final target in index.linkedFrom(doc)) _Ref.toDoc('link', target),
  ]);
  for (final id in const ['implements', 'covers']) {
    refs.addAll([
      for (final value in doc.valuesOf(id)) _Ref.toPointer(id, value),
    ]);
  }
  return refs;
}

/// Returns each doc's inbound `doc_ref` references, in tree order of the
/// referring docs.
Map<String, List<_Ref>> _inboundByPath(DocIndex index) {
  final inbound = <String, List<_Ref>>{};
  for (final doc in index.docs) {
    for (final field in _docRefFields(index, doc)) {
      for (final value in doc.valuesOf(field.id)) {
        for (final target in _carrying(index, field, value)) {
          (inbound[target.docPath] ??= []).add(_Ref.toDoc(field.id, doc));
        }
      }
    }
  }
  return inbound;
}

/// Returns the `doc_ref` fields of [doc]'s type, in field order.
Iterable<MergedField> _docRefFields(DocIndex index, IndexedDoc doc) sync* {
  for (final field in index.typeOf(doc)?.fields ?? const <MergedField>[]) {
    if (field.type == FieldType.docRef) yield field;
  }
}

/// Returns the typed docs carrying [value] whose type [field] names, in tree
/// order; every typed doc carrying it when the field names none.
Iterable<IndexedDoc> _carrying(
  DocIndex index,
  MergedField field,
  String value,
) sync* {
  for (final doc in index.docs) {
    final typeId = doc.docTypeId;
    if (typeId != null &&
        doc.name == value &&
        (field.docTypes?.contains(typeId) ?? true)) {
      yield doc;
    }
  }
}

/// Returns the one line per reference of [refs], or `- none` when empty.
String _groupLines(List<_Ref> refs) => refs.isEmpty
    ? '- none\n'
    : '${[for (final ref in refs) ref.text].join('\n')}\n';

/// Returns the docs that refer to [doc]: first those whose `doc_ref` value
/// reaches it, then those linking to it, each once and in tree order.
///
/// These are the inbound references `answerRefs` prints for [doc].
List<IndexedDoc> referrersOf(DocIndex index, IndexedDoc doc) {
  final byValue = [
    for (final from in index.docs)
      if (_refersTo(index, from, doc)) from,
  ];
  final seen = {for (final from in byValue) from.docPath};
  return [
    ...byValue,
    for (final from in index.linkingTo(doc))
      if (seen.add(from.docPath)) from,
  ];
}

/// Whether a `doc_ref` value of [from] reaches [doc].
bool _refersTo(DocIndex index, IndexedDoc from, IndexedDoc doc) {
  for (final field in _docRefFields(index, from)) {
    for (final value in from.valuesOf(field.id)) {
      if (value != doc.name) continue;
      if (_carrying(index, field, value).any((t) => t.docPath == doc.docPath)) {
        return true;
      }
    }
  }
  return false;
}
