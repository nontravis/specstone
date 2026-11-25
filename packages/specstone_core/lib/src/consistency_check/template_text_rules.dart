import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/section_rules.dart'
    show titleLineOf;
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show MergedSection;

const _titleKey = '_title';
const _specsRoot = 'specs/';
final _angleSpan = RegExp('<[^<>]+>');
final _whitespaceRun = RegExp(r'\s+');
final _listMarker = RegExp(r'^(?:[-*+]|\d+[.)])\s+');

/// The placeholder lines of one merged section, read once per section.
final _placeholderLines = Expando<Set<String>>('placeholder lines');

/// Returns a finding at each line of a typed [doc] that equals a placeholder
/// line of its section's template, and one at a title equal to the doc's
/// file slug.
///
/// A placeholder line is a template line holding an angle span outside code
/// spans; both lines read with whitespace runs as one space and no list marker.
Iterable<Finding> checkTemplateText(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (context.typeOf(doc) == null) return;
  yield* _leftoverLines(context, doc);
  yield* _slugTitle(context, doc);
}

/// Returns the ids of the sections of [doc] that keep a template line, so
/// [checkTemplateText] reports them.
Set<String> sectionsKeepingTemplateText(CheckContext context, IndexedDoc doc) =>
    {
      for (final finding in _leftoverLines(context, doc))
        finding.keys['section']! as String,
    };

Iterable<Finding> _leftoverLines(CheckContext context, IndexedDoc doc) sync* {
  final held = context.contentOf(doc).sections;
  for (var i = 0; i < held.length; i++) {
    final template = context.templateSectionAt(doc, i);
    if (template == null) continue;
    final placeholders = _placeholdersOf(template);
    if (placeholders.isEmpty) continue;
    for (final line in context.bodyLinesOf(doc, i)) {
      if (line.fenced ||
          !_mayEqualPlaceholder(line.text) ||
          !placeholders.contains(_normalized(line.text))) {
        continue;
      }
      yield context.finding(
        doc,
        FindingKind.templateTextLeft,
        line: line.line,
        message: 'section ${template.id} keeps a template line',
        keys: {'section': template.id},
      );
    }
  }
}

/// Reports the title of a PRD doc named by `{slug}` that is its file slug; a
/// spec doc or a record, titled with its feature's slug by design, has none.
Iterable<Finding> _slugTitle(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc)!;
  if (type.isRecordType || doc.docPath.startsWith(_specsRoot)) return;
  final shape = DocPathShape.ofDoc(
    type,
    context.set,
    doc.docPath,
    target: doc.target,
  );
  if (shape == null) return;
  final slug = shape.matchOwn(doc.docPath.split('/')[shape.ownIndex])?.slug;
  if (slug == null || doc.title?.trim() != slug) return;
  yield context.finding(
    doc,
    FindingKind.templateTextLeft,
    line: titleLineOf(context, doc),
    message: 'the title is the file slug',
    keys: {'section': _titleKey},
  );
}

Set<String> _placeholdersOf(MergedSection section) =>
    _placeholderLines[section] ??= {
      for (final line in (section.template ?? '').split('\n'))
        if (_holdsAngleSpan(line)) _normalized(line),
    };

bool _holdsAngleSpan(String line) {
  final spans = codeSpansOf(line);
  return _angleSpan
      .allMatches(line)
      .any(
        (match) =>
            !spans.any((s) => match.start >= s.start && match.start < s.end),
      );
}

/// Whether [line] can equal a placeholder line once normalized.
///
/// Every placeholder holds an angle span, and normalizing keeps each `<`, so a
/// line with none skips the costly normalizing.
bool _mayEqualPlaceholder(String line) => line.contains('<');

String _normalized(String line) => line
    .trim()
    .replaceFirst(_listMarker, '')
    .replaceAll(_whitespaceRun, ' ')
    .trim();
