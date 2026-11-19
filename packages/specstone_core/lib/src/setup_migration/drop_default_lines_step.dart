import 'package:specstone_core/src/consistency_check/section_fields.dart'
    show readFieldHead;
import 'package:specstone_core/src/doc_model/default_enforcer.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show docStructureOf;
import 'package:specstone_core/src/index_query/item_facts.dart'
    show sectionItemsAt;
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;

const _consistencyField = 'Consistency';
const _enforcerField = 'Enforcer';
const _immediate = 'immediate';

/// Returns [lf] without the nested lines of the `##` section [invariantsHeader]
/// that state only the default, or [lf] when it holds none.
///
/// A default line is a nested `- **Consistency:** immediate` line, or a nested
/// `- **Enforcer:**` line that names [defaultEnforcer]; with a null
/// [defaultEnforcer] every Enforcer line stays. Matches the header as
/// [headerKey] does and reads items as the check does, so a fenced line, a
/// line outside the section, and a line not nested under an item stay.
String withDefaultLinesDropped(
  String lf, {
  required String invariantsHeader,
  required String? defaultEnforcer,
}) {
  final doc = Doc.parse(lf);
  final key = headerKey(invariantsHeader);
  final index = doc.sections.indexWhere((s) => headerKey(s.headerText) == key);
  if (index < 0) return lf;
  final items = sectionItemsAt(docStructureOf(lf, null), index, null);
  final dropped = {
    for (final item in _defaultItemsOf(items, defaultEnforcer)) item.line - 1,
  };
  if (dropped.isEmpty) return lf;
  final lines = lf.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (!dropped.contains(i)) lines[i],
  ].join('\n');
}

/// Returns the default enforcer of the doc at the head of [texts], read from
/// the first table of each text's `##` section [entitiesHeader].
///
/// [texts] holds the doc's own LF text first, then each ancestor's of the same
/// doc type and target, nearest first. Gives null when none applies, as
/// [defaultEnforcerOf] does.
String? defaultEnforcerAmong(
  List<String> texts, {
  required String entitiesHeader,
}) => defaultEnforcerOf([
  for (final text in texts) _entityRowsIn(text, entitiesHeader),
]);

List<EntityRow> _entityRowsIn(String lf, String header) {
  final key = headerKey(header);
  for (final section in Doc.parse(lf).sections) {
    if (headerKey(section.headerText) == key) {
      return entityRowsOf(section.body.split('\n'));
    }
  }
  return const [];
}

/// Yields each one-line nested item under an open item of [items] that
/// [_statesDefault] accepts.
///
/// A heading or a top-level paragraph closes the open item, as the check's
/// field reader has it; a nested line that runs past one line, or that holds a
/// deeper bullet of its own, states more than the default.
Iterable<SectionItem> _defaultItemsOf(
  List<SectionItem> items,
  String? defaultEnforcer,
) sync* {
  var isUnderItem = false;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final closesItem =
        item.kind == SectionItemKind.heading ||
        (item.kind == SectionItemKind.paragraph && !item.nested);
    if (closesItem) {
      isUnderItem = false;
    } else if (!item.nested) {
      isUnderItem = true;
    } else if (isUnderItem &&
        !item.text.contains('\n') &&
        !_holdsDeeperItem(item, i + 1 < items.length ? items[i + 1] : null) &&
        _statesDefault(item.head, defaultEnforcer)) {
      yield item;
    }
  }
}

bool _holdsDeeperItem(SectionItem item, SectionItem? next) =>
    next != null && next.nested && _indentOf(next) > _indentOf(item);

int _indentOf(SectionItem item) =>
    item.firstLine.length - item.firstLine.trimLeft().length;

bool _statesDefault(String head, String? defaultEnforcer) {
  final field = readFieldHead(head);
  if (field == null) return false;
  return switch (field.name) {
    _consistencyField => field.value == _immediate,
    _enforcerField =>
      defaultEnforcer != null &&
          namesDefaultEnforcer(field.value, defaultEnforcer),
    _ => false,
  };
}
