import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Returns the doc `Limits:` line of [lint].
///
/// A set `max_lines` and `max_chars` print first; the item, sentence word, and
/// sentence character caps always print, each from its built-in default when
/// no layer writes it.
String docLimitsLine(MergedLint lint) {
  final clauses = [
    if (lint.maxLines case final lines?) 'at most ${countWord(lines, 'line')}',
    if (lint.maxChars case final chars?)
      'at most ${countWord(chars, 'character')}',
    'at most ${countWord(lint.itemCharLimit, 'character')} per item',
    _wordsClause(lint.sentenceWordCaps),
    _charsClause(lint.sentenceCharCaps),
  ];
  return 'Limits: ${clauses.join('; ')}.';
}

/// Returns the ` Limits: …` tail of [section]'s requirement line, or null when
/// the section sets no size key.
///
/// The section's own value only counts: a fallback to the doc's `max_lines` or
/// `max_chars` prints nothing.
String? sectionLimitsClause(MergedSection section) {
  final clauses = [
    if (section.minLines case final lines?)
      'at least ${countWord(lines, 'line')}',
    if (section.maxLines case final lines?)
      'at most ${countWord(lines, 'line')}',
    if (section.maxChars case final chars?)
      'at most ${countWord(chars, 'character')}',
    if (section.maxItemLines case final lines?)
      'at most ${countWord(lines, 'line')} per item',
    if (section.maxSubsections case final subsections?)
      'at most ${countWord(subsections, 'subsection')}',
    ..._itemCountClauses(section.itemCount),
    for (final limit in section.maxSentences ?? const <SentenceLimit>[])
      _sentenceLimitClause(limit),
  ];
  return clauses.isEmpty ? null : ' Limits: ${clauses.join('; ')}.';
}

/// Returns the indented `Limits:` line of a field's [caps], or null when [caps]
/// is null or sets no key.
String? fieldLimitsLine(FieldCaps? caps) {
  if (caps == null) return null;
  final clauses = [
    if (caps.maxSentences case final sentences?)
      'at most ${countWord(sentences, 'sentence')}',
    if (caps.maxSentenceWords case final words?)
      _wordsClause(SentenceCaps(words)),
    if (caps.maxSentenceChars case final chars?)
      _charsClause(SentenceCaps(chars)),
  ];
  return clauses.isEmpty ? null : '  Limits: ${clauses.join('; ')}.';
}

/// Returns [n] with a comma every three digits, then [unit], plural unless [n]
/// is 1.
String countWord(int n, String unit) => '${_grouped(n)} ${_plural(n, unit)}';

final _digitsBeforeGroup = RegExp(r'(\d)(?=(\d{3})+$)');

String _grouped(int n) =>
    '$n'.replaceAllMapped(_digitsBeforeGroup, (match) => '${match[1]},');

String _plural(int n, String unit) => n == 1 ? unit : '${unit}s';

String _wordsClause(SentenceCaps caps) =>
    'at most ${countWord(caps.capFor('default'), 'word')} per sentence'
    '${_languageList(caps)}';

String _charsClause(SentenceCaps caps) =>
    'at most ${countWord(caps.capFor('default'), 'character')} per sentence '
    'in a script with no spaces${_languageList(caps)}';

/// Returns the parenthesis listing every entry of [caps] but `default`, in map
/// order, or an empty string when none is left.
String _languageList(SentenceCaps caps) {
  final entries = [
    for (final MapEntry(:key, :value) in caps.entries.entries)
      if (key != 'default') '$key ${_grouped(value)}',
  ];
  return entries.isEmpty ? '' : ' (${entries.join(', ')})';
}

List<String> _itemCountClauses(ItemCountLint? lint) {
  if (lint == null) return const [];
  final suffix = lint.perSubsection ? ' in each subsection' : '';
  final range = switch ((lint.min, lint.max)) {
    (final min?, final max?) when min == max =>
      'exactly ${countWord(min, 'item')}',
    (final min?, final max?) => '${_grouped(min)} to ${countWord(max, 'item')}',
    (final min?, null) => 'at least ${countWord(min, 'item')}',
    (null, final max?) => 'at most ${countWord(max, 'item')}',
    (null, null) => null,
  };
  return [
    if (range != null) '$range$suffix',
    for (final (:linePrefix, :count) in lint.prefixes)
      _prefixClause(linePrefix, count, suffix),
  ];
}

String _prefixClause(String prefix, int count, String suffix) {
  final items = _plural(count, 'item');
  return 'exactly ${_grouped(count)} `$prefix` $items$suffix';
}

String _sentenceLimitClause(SentenceLimit limit) {
  final head = 'at most ${countWord(limit.count, 'sentence')}';
  final column = limit.column;
  final prefix = limit.linePrefix;
  return switch ((column, prefix)) {
    (null, null) => '$head per item',
    (null, final prefix?) => '$head per `$prefix` item',
    (final column?, null) => '$head per `$column` cell',
    (final column?, final prefix?) =>
      '$head per `$column` cell opening with `$prefix`',
  };
}
