import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// Returns [block] as LF text with its trailing blank lines dropped.
///
/// A last line with no line break gets one; an empty or all-blank [block]
/// stays empty (INV-3).
String upstreamText(String block) {
  final lines = toLf(block).split('\n');
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.isEmpty ? '' : '${lines.join('\n')}\n';
}

/// Returns the first 12 lowercase hex characters of the SHA-256 of [block].
///
/// The hash is [baseHashOf] over [upstreamText], so one function holds the
/// recipe (F4-D17).
String fingerprintOf(String block) => baseHashOf(upstreamText(block));
