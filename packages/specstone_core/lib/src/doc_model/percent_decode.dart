import 'dart:convert';

// MARK: - Public

/// Decodes the percent escapes of [text]: each `%` followed by two hex
/// digits becomes that byte, every other character its UTF-8 bytes, and the
/// bytes decode as UTF-8 with U+FFFD for a sequence that is not UTF-8.
///
/// A `%` not followed by two hex digits stays as written.
String percentDecoded(String text) {
  final bytes = _percentDecodedBytes(text);
  return bytes == null ? text : utf8.decode(bytes, allowMalformed: true);
}

/// Whether the escapes of [text] decode to valid UTF-8, so [percentDecoded]
/// writes no U+FFFD that [text] did not hold.
///
/// A caller that re-encodes the decoded text must keep [text] when this is
/// false, or the original bytes are lost.
bool percentDecodesCleanly(String text) {
  final bytes = _percentDecodedBytes(text);
  if (bytes == null) return true;
  try {
    utf8.decode(bytes);
    return true;
  } on FormatException {
    return false;
  }
}

// MARK: - Internal

/// Returns the bytes [text] stands for once each escape is a byte, or null
/// when [text] holds no escape.
List<int>? _percentDecodedBytes(String text) {
  final firstPercent = text.indexOf('%');
  // A text with no escape decodes to itself, so most hrefs pay nothing.
  if (firstPercent < 0) return null;
  final bytes = <int>[];
  // Literal text is encoded a run at a time: a character outside the BMP is
  // two code units, and encoding each alone would turn it into two U+FFFD.
  var runStart = 0;
  for (var i = firstPercent; i < text.length; i++) {
    if (text.codeUnitAt(i) != 0x25 || i + 2 >= text.length) continue;
    final byte = _hexByteAt(text, i + 1);
    if (byte == null) continue;
    bytes
      ..addAll(utf8.encode(text.substring(runStart, i)))
      ..add(byte);
    i += 2;
    runStart = i + 1;
  }
  bytes.addAll(utf8.encode(text.substring(runStart)));
  return bytes;
}

/// Returns the byte the two hex digits at [start] and [start] + 1 name, or
/// null when either is not a hex digit.
int? _hexByteAt(String text, int start) {
  var byte = 0;
  for (var i = start; i < start + 2; i++) {
    final digit = text.codeUnitAt(i);
    final value = switch (digit) {
      >= 0x30 && <= 0x39 => digit - 0x30,
      >= 0x41 && <= 0x46 => digit - 0x37,
      >= 0x61 && <= 0x66 => digit - 0x57,
      _ => null,
    };
    if (value == null) return null;
    byte = byte * 16 + value;
  }
  return byte;
}
