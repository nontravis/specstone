import 'package:markdown/markdown.dart' show HeaderSyntax;

// The pattern is the one `markdown` matches its ATX headings by, so an upgrade
// that changes it changes every reader with it.
final RegExp _atxHeading = const HeaderSyntax().pattern;

/// `markdown`'s `tablePattern` (`patterns.dart:53`), which `markdown.dart` does
/// not export: a line of hyphens separated by at least one pipe.
///
/// The pattern is the package's own, so every reader agrees with the renderer
/// on what a table is: a one-column row such as `|---` is no delimiter row.
final RegExp _tableDelimiterRow = RegExp(
  r'^[ ]{0,3}\|?([ \t]*:?\-+:?[ \t]*\|[ \t]*)+([ \t]|[ \t]*:?\-+:?[ \t]*)?$',
);

/// An ATX heading line: its level, 1 to 6, and its text without the marks.
typedef AtxHeading = ({int level, String text});

/// Returns the heading [line] is, or null when it is no ATX heading.
///
/// The text has no opening `#` run and no closing one, and is trimmed.
AtxHeading? atxHeadingOf(String line) {
  final match = _atxHeading.firstMatch(line);
  if (match == null) return null;
  final marks = match.group(1)!;
  final closing = match.group(2);
  var text = line.substring(line.indexOf(marks) + marks.length).trim();
  if (closing != null) {
    text = text.substring(0, text.length - closing.length).trimRight();
  } else if (text.isNotEmpty && text.replaceAll('#', '').isEmpty) {
    text = ''; // a lone closing run, as in `### ###`
  }
  return (level: marks.length, text: text);
}

/// Whether [line] is a table delimiter row, such as `|---|:-:|`.
bool isTableDelimiterRow(String line) => _tableDelimiterRow.hasMatch(line);
