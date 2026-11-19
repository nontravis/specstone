import 'package:specstone_core/src/doc_model/default_enforcer.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show sectionItemsOf;
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;

const _consistencyField = 'Consistency';
const _enforcerField = 'Enforcer';
const _immediate = 'immediate';

final _fieldItem = RegExp(r'^\*\*(.+?)\:\*\*\s*(.*)$');

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
  final lines = doc.afterFrontmatter.split('\n');
  final fenced = fencedLines(lines);
  final end = index + 1 < doc.sections.length
      ? doc.sectionLineIndexes[index + 1]
      : lines.length;
  final body = [
    for (var i = doc.sectionLineIndexes[index] + 1; i < end; i++)
      BodyLine(text: lines[i], line: i + 1, fenced: fenced[i]),
  ];
  final dropped = {
    for (final item in _defaultItemsOf(body, defaultEnforcer)) item.line - 1,
  };
  if (dropped.isEmpty) return lf;
  final frontmatterLength = lf.length - doc.afterFrontmatter.length;
  return lf.substring(0, frontmatterLength) +
      [
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

/// Yields each one-line nested item under an open item of [body] that
/// [_statesDefault] accepts.
///
/// A heading or a top-level paragraph closes the open item, as the check's
/// field reader has it; a nested line that runs past one line, or that holds a
/// deeper bullet of its own, states more than the default.
Iterable<SectionItem> _defaultItemsOf(
  List<BodyLine> body,
  String? defaultEnforcer,
) sync* {
  final items = sectionItemsOf(body);
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
  final match = _fieldItem.firstMatch(head);
  if (match == null) return false;
  final value = match.group(2)!.trim();
  return switch (match.group(1)) {
    _consistencyField => value == _immediate,
    _enforcerField =>
      defaultEnforcer != null && namesDefaultEnforcer(value, defaultEnforcer),
    _ => false,
  };
}
