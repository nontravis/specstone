import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

const _fingerprintLength = 12;

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
/// The hash covers the UTF-8 bytes of [upstreamText]. F-04 owns this function
/// until F-01 and F-02 share one (F4-D17).
String fingerprintOf(String block) => sha256
    .convert(utf8.encode(upstreamText(block)))
    .toString()
    .substring(0, _fingerprintLength);
