import 'dart:math';

import 'package:specstone_core/src/templates/guide_limits.dart';
import 'package:specstone_core/src/templates/models/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/merged_field.dart';
import 'package:specstone_core/src/templates/models/merged_section.dart';
import 'package:specstone_core/src/templates/models/required_when_lint.dart';

export 'package:specstone_core/src/templates/models/catalog_lint.dart';
export 'package:specstone_core/src/templates/models/diagram_lint.dart';
export 'package:specstone_core/src/templates/models/field_caps.dart';
export 'package:specstone_core/src/templates/models/item_count_lint.dart';
export 'package:specstone_core/src/templates/models/item_field_lint.dart';
export 'package:specstone_core/src/templates/models/item_field_when.dart';
export 'package:specstone_core/src/templates/models/line_prefix_count.dart';
export 'package:specstone_core/src/templates/models/max_code_blocks.dart';
export 'package:specstone_core/src/templates/models/merged_doc_type.dart';
export 'package:specstone_core/src/templates/models/merged_field.dart';
export 'package:specstone_core/src/templates/models/merged_lint.dart';
export 'package:specstone_core/src/templates/models/merged_section.dart';
export 'package:specstone_core/src/templates/models/merged_shared_line.dart';
export 'package:specstone_core/src/templates/models/pattern_entry.dart';
export 'package:specstone_core/src/templates/models/reference_entry.dart';
export 'package:specstone_core/src/templates/models/required_when_lint.dart';
export 'package:specstone_core/src/templates/models/sentence_caps.dart';
export 'package:specstone_core/src/templates/models/sentence_limit.dart';
export 'package:specstone_core/src/templates/models/summary_rows.dart';
export 'package:specstone_core/src/templates/models/when_field.dart';

/// The id of the record doc type's matrix section, the one section whose
/// lines are pointers.
const verificationMatrixKey = 'verification_matrix';

/// The `software-tech` version that adds the matrix section to the record doc
/// type.
const verificationMatrixPackVersion = '1.13.0';

/// The enabled matrix section of [recordType], or null.
///
/// Null when [recordType] holds no `record_status` field, so only the record
/// doc type has a matrix. Finds the section by [verificationMatrixKey], never
/// by [MergedSection.isOutputRef].
MergedSection? verificationMatrixOf(MergedDocType recordType) {
  if (!recordType.isRecordType) return null;
  for (final section in recordType.sections) {
    if (section.id == verificationMatrixKey) return section;
  }
  return null;
}

/// The language keys `max_sentence_words` takes.
const sentenceWordLanguages = {'default', 'ko', 'ar', 'he', 'hi', 'el'};

/// The language keys `max_sentence_chars` takes.
const sentenceCharLanguages = {'default', 'th', 'lo', 'km', 'my', 'zh', 'ja'};

/// Renders the writing guide of a [MergedDocType].
extension DocTypeGuide on MergedDocType {
  /// Returns the writing guide, each block set off by a blank line.
  ///
  /// The description with the shared lines under it, and the doc-level banned
  /// words, come first, then the `Frontmatter:` block of the declared
  /// non-built-in `fields`, then the doc `Limits:` line, then each section: a
  /// block of its header, its requirement line (`Required`, `Optional`, or a
  /// condition, with the limit clauses joined to it), and its description,
  /// then its own banned words as a block of its own, and its template fence
  /// on the line under the block before it. A banned word list drops the
  /// allowed words that apply there, as `check` does; a description, word
  /// list, template, or field set left empty adds no block. The `reference`
  /// list is not printed; `guide --json` keeps it.
  ///
  /// A shared line whose id is in [sharedOut] is left out, since the caller
  /// prints it once in a block shared by every guide of the call.
  String renderGuide({Set<String> sharedOut = const {}}) {
    final docAllowed = lint.allowedWords ?? const <String>[];
    final blocks = <String>[
      ?_descriptionWithout(sharedOut, withTitle: true),
      ?_bannedWordsLine(lint.bannedWords, allowed: docAllowed),
      ?_fieldsBlock(),
      docLimitsLine(lint),
      for (final section in sections)
        ..._sectionBlocks(section, docAllowed, lint.bannedWords),
    ];
    return '${blocks.join('\n\n')}\n';
  }

  /// Returns the blocks of [section]: header, banned words, and the template
  /// fence, which joins the block before it with no blank line.
  ///
  /// A word in [docBanned] is left out of the section's banned words, since
  /// the doc-level line already prints it.
  List<String> _sectionBlocks(
    MergedSection section,
    List<String> docAllowed,
    List<String>? docBanned,
  ) {
    final blocks = <String>[
      [
        '## ${section.header}',
        _requirementLine(section),
        ?_trimmedOrNull(section.description),
      ].join('\n'),
      ?_bannedWordsLine(
        section.bannedWords,
        allowed: [...docAllowed, ...?section.allowedWords, ...?docBanned],
        linePrefix: section.linePrefix,
      ),
    ];
    final template = _templateBlock(section.template);
    if (template != null) blocks.last = '${blocks.last}\n$template';
    return blocks;
  }

  /// Returns `descriptionWithSharedLines` without the lines whose ids are in
  /// [sharedOut], with a `Title:` line under the description when [withTitle]
  /// holds and the doc type sets a title.
  String? _descriptionWithout(Set<String> sharedOut, {bool withTitle = false}) {
    final lines = [
      ?_trimmedOrNull(description),
      if (withTitle && title != null) 'Title: $title',
      for (final line in sharedLines)
        if (!sharedOut.contains(line.id)) line.text,
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// Returns the line under [section]'s header that says when the section is
  /// required, optional, or left out.
  ///
  /// A `required_when` rule always makes the section required while it holds.
  /// The section's limit clauses join the line with `; `, before its period.
  String _requirementLine(MergedSection section) {
    final whenField = section.whenField;
    final requiredWhen = section.requiredWhen;
    final clauses = sectionLimitsClause(section);
    final limits = clauses == null ? '' : '; $clauses';
    if (whenField == null && requiredWhen == null) {
      final mark = section.required ? 'Required' : 'Optional';
      return '$mark$limits.';
    }
    final conditions = [
      if (whenField != null)
        '`${whenField.field}` is ${_valueList(whenField.values)}',
      if (requiredWhen != null) _itemCondition(requiredWhen),
    ];
    final mark = requiredWhen != null || section.required
        ? 'Required'
        : 'Optional';
    return '$mark when ${conditions.join(' and ')}; left out otherwise$limits.';
  }

  String _itemCondition(RequiredWhenLint rule) {
    final header = sections.firstWhere((s) => s.id == rule.section).header;
    return 'a `$header` item holds `${rule.field}: ${rule.value}`';
  }

  /// Returns [values] as backticked words joined by `or`, with a comma before
  /// the last of three or more.
  static String _valueList(List<String> values) {
    final quoted = [for (final value in values) '`$value`'];
    return switch (quoted) {
      [] => '',
      [final only] => only,
      [final first, final second] => '$first or $second',
      [...final init, final last] => '${init.join(', ')}, or $last',
    };
  }

  static const _fieldsHeading = 'Frontmatter:';

  /// Returns the `Frontmatter:` block of the non-built-in `fields`,
  /// or null when the type declares none.
  String? _fieldsBlock() {
    final declared = fields.where((field) => !field.isBuiltIn);
    if (declared.isEmpty) return null;
    return [_fieldsHeading, ...declared.map(_fieldLine)].join('\n');
  }

  /// Returns the guide line of [field]; a description line after the first is
  /// indented two spaces, and a `Limits:` line follows them.
  ///
  /// A `doc_ref` field with target doc types names them after its type.
  static String _fieldLine(MergedField field) {
    final flag = field.required ? 'required' : 'optional';
    final targets = field.docTypes ?? const <String>[];
    final type = '${field.type.wire}${field.list ? ' list' : ''}';
    final kind = [
      if (targets.isEmpty) type else '$type → ${targets.join(', ')}',
      ?field.enumValues?.join(', '),
    ];
    final head = '- `${field.id}` ($flag, ${kind.join(': ')})';
    final description = _trimmedOrNull(field.description);
    final line = description == null
        ? head
        : '$head — ${description.split('\n').join('\n  ')}';
    return [line, ?fieldLimitsLine(field.lint)].join('\n');
  }

  static final _backtickRun = RegExp('`+');

  /// The shortest fence a markdown code block takes.
  static const _minFence = 3;

  /// Returns the `Banned words:` line of [words] not in [allowed], or null
  /// when none is left.
  ///
  /// A [linePrefix] names the lines the words apply on.
  static String? _bannedWordsLine(
    List<String>? words, {
    required List<String> allowed,
    String? linePrefix,
  }) {
    final shown = [
      for (final word in {...?words})
        if (!allowed.contains(word)) '`$word`',
    ];
    if (shown.isEmpty) return null;
    final where = linePrefix == null ? '' : ' on `$linePrefix` lines';
    return 'Banned words$where: ${shown.join(', ')}';
  }

  /// Returns [template] as a code block, or null when it is empty.
  ///
  /// The fence is one backtick longer than the longest backtick run inside,
  /// so a fence the template holds never closes the block.
  static String? _templateBlock(String? template) {
    final body = _trimmedOrNull(template);
    if (body == null) return null;
    final longestRun = _backtickRun
        .allMatches(body)
        .fold(0, (longest, run) => max(longest, run.end - run.start));
    final fence = '`' * max(_minFence, longestRun + 1);
    return '$fence\n$body\n$fence';
  }

  /// Returns [text] without trailing whitespace, or null when nothing is left.
  static String? _trimmedOrNull(String? text) {
    final trimmed = text?.trimRight();
    return trimmed == null || trimmed.trim().isEmpty ? null : trimmed;
  }
}
