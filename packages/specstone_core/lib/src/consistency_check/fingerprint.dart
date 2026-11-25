import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/rendering/layout.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// Returns [block] as LF text laid out as `format` writes it.
///
/// Leading and trailing blank lines are dropped, so a section body hashes the
/// same with or without the gap under its heading; a last line with no line
/// break gets one; an empty or all-blank [block] stays empty.
String upstreamText(String block) =>
    _withoutLeadingBlanks(_withoutTrailingBlanks(layOutText(toLf(block))));

String _withoutLeadingBlanks(String lf) => lf.replaceFirst(_leadingBlanks, '');

final _leadingBlanks = RegExp(r'^(?:[ \t]*\n)+');

String _withoutTrailingBlanks(String lf) {
  final lines = lf.split('\n');
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.isEmpty ? '' : '${lines.join('\n')}\n';
}

/// Returns the first 12 lowercase hex characters of the SHA-256 of [block].
///
/// The hash is [baseHashOf] over [upstreamText], so one function holds the
/// recipe.
String fingerprintOf(String block) => baseHashOf(upstreamText(block));
