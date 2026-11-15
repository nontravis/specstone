import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

const _oldMarker = '==> old <==';
const _newMarker = '==> new <==';

/// Reads the stdin of `set --replace`, as written, as the old and the new
/// passage.
///
/// The first line is the old marker and exactly one later line is the new
/// marker; a marker line may end in CR. Each passage is the text between or
/// after the marker lines with its last line end dropped. The old passage
/// keeps any other CR, so it matches only text with the same line ends; the
/// new passage is read in LF line ends.
/// Throws [IndexFault] `argument_invalid` for a first line that is not the old
/// marker, a missing or repeated marker line, and an empty old passage.
({String oldPassage, String newPassage}) parseReplaceStdin(String stdin) {
  final lines = stdin.split('\n');
  if (_withoutCr(lines.first) != _oldMarker) {
    throw _invalid('the first line must be exactly "$_oldMarker"');
  }
  final markerAt = [
    for (var i = 1; i < lines.length; i++)
      if (_withoutCr(lines[i]) == _newMarker ||
          _withoutCr(lines[i]) == _oldMarker)
        i,
  ];
  if (markerAt.isEmpty || _withoutCr(lines[markerAt.first]) != _newMarker) {
    throw _invalid('stdin needs one "$_newMarker" line after the old passage');
  }
  if (markerAt.length > 1) {
    throw _invalid('stdin holds a second marker line; send one old, one new');
  }
  final newAt = markerAt.single;
  final oldPassage = _withoutCr(lines.sublist(1, newAt).join('\n'));
  if (oldPassage.isEmpty) throw _invalid('the old passage is empty');
  final newText = toLf(lines.sublist(newAt + 1).join('\n'));
  return (
    oldPassage: oldPassage,
    newPassage: newText.endsWith('\n')
        ? newText.substring(0, newText.length - 1)
        : newText,
  );
}

/// Returns [body] with the one match of [oldPassage] replaced by [newPassage].
///
/// Matches exactly: no trim, no case fold, no whitespace fold. [current], with
/// [key], is what a `replace_unmatched` fault carries so the caller can merge
/// and retry. Throws [WriteFault] `replace_unmatched` when [oldPassage] is not
/// in [body] and `replace_ambiguous`, naming the count, when it occurs twice
/// or more.
String replacedBody(
  String body,
  String oldPassage,
  String newPassage, {
  required String docPath,
  String? key,
  CurrentTarget? current,
}) {
  final at = body.indexOf(oldPassage);
  if (at < 0) {
    throw WriteFault(
      WriteFaultCode.replaceUnmatched,
      'the old passage is not in the section',
      file: docPath,
      key: key,
      current: current,
    );
  }
  final count = _occurrencesOf(body, oldPassage);
  if (count > 1) {
    throw WriteFault(
      WriteFaultCode.replaceAmbiguous,
      'the old passage occurs $count times in the section; send a longer '
      'passage that occurs once',
      file: docPath,
      key: key,
    );
  }
  return body.substring(0, at) +
      newPassage +
      body.substring(at + oldPassage.length);
}

String _withoutCr(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

int _occurrencesOf(String text, String passage) {
  var count = 0;
  for (
    var at = text.indexOf(passage);
    at >= 0;
    at = text.indexOf(passage, at + passage.length)
  ) {
    count++;
  }
  return count;
}

IndexFault _invalid(String reason) =>
    IndexFault(IndexFaultCode.argumentInvalid, 'set --replace: $reason');
