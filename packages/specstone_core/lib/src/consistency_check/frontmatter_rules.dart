import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _featureType = 'feature';
const _statusKey = 'status';
final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Returns the frontmatter findings of a typed [doc]; an untyped doc has none.
///
/// Invalid YAML is the only finding of its doc, and states its warning.
Iterable<Finding> checkFrontmatter(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final lines = context.linesOf(doc);
  final errorLine = lines.frontmatterErrorLine;
  if (errorLine != null) {
    final stated = '${doc.docPath}: frontmatter is not valid YAML; ';
    doc.warnings.where((w) => w.startsWith(stated)).forEach(context.state);
    yield context.finding(
      doc,
      FindingKind.frontmatterInvalid,
      line: errorLine,
      message: 'frontmatter is not valid YAML',
    );
    return;
  }
  // A null value counts as absent for the required and value rules only.
  final values = {
    for (final MapEntry(:key, :value) in doc.frontmatter.entries) key: ?value,
  };
  final fieldsById = {for (final field in type.fields) field.id: field};
  for (final field in type.fields) {
    if (field.required && !values.containsKey(field.id)) {
      yield context.finding(
        doc,
        FindingKind.requiredFieldMissing,
        line: 1,
        message: 'required field ${field.id} is missing',
        keys: {'field': field.id},
      );
    }
  }
  for (final MapEntry(:key, :value) in doc.frontmatter.entries) {
    // The key line reads the frontmatter YAML, so only a finding asks for it.
    int lineOf() => lines.keyLine(key) ?? 1;
    final field = fieldsById[key];
    if (key == _statusKey && doc.docTypeId == _featureType) {
      yield context.finding(
        doc,
        FindingKind.featureStatusWritten,
        line: lineOf(),
        message: 'a FEATURE takes its status from its stories; remove status',
      );
    } else if (field == null) {
      yield context.finding(
        doc,
        FindingKind.fieldUndeclared,
        line: lineOf(),
        message: '$key is not a field of the ${type.id} doc type',
        keys: {'field': key},
      );
    } else if (value != null && !_fits(field, value)) {
      yield context.finding(
        doc,
        FindingKind.fieldValueMismatch,
        line: lineOf(),
        message: '$key is ${_written(value)}; it takes ${_takes(field)}',
        keys: {'field': key, 'value': _written(value)},
      );
    }
  }
}

bool _fits(MergedField field, Object value) {
  if (!field.list) return value is! List && _itemFits(field, value);
  return value is List &&
      value.every((item) => item is Object && _itemFits(field, item));
}

bool _itemFits(MergedField field, Object item) => switch (field.type) {
  FieldType.string || FieldType.docRef || FieldType.outputRef => item is String,
  FieldType.integer => item is int,
  FieldType.boolean => item is bool,
  FieldType.date => item is String && _isRealDate(item),
  FieldType.enumType =>
    item is String && (field.enumValues ?? const []).contains(item),
};

bool _isRealDate(String text) {
  final match = _isoDate.firstMatch(text);
  if (match == null) return false;
  final [year, month, day] = [
    for (var i = 1; i <= 3; i++) int.parse(match[i]!),
  ];
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

String _written(Object value) =>
    value is List ? '[${value.join(', ')}]' : '$value';

String _takes(MergedField field) {
  final one = switch (field.type) {
    FieldType.string || FieldType.docRef || FieldType.outputRef => 'a string',
    FieldType.integer => 'an integer',
    FieldType.boolean => 'true or false',
    FieldType.date => 'a date written YYYY-MM-DD',
    FieldType.enumType => _orList(field.enumValues ?? const []),
  };
  return field.list ? 'a list of: $one' : one;
}

String _orList(List<String> values) => switch (values.length) {
  0 => 'no value',
  1 => values.single,
  2 => '${values[0]} or ${values[1]}',
  _ => '${values.sublist(0, values.length - 1).join(', ')}, or ${values.last}',
};
