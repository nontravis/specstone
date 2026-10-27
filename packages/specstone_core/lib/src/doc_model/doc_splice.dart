import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The base of empty text, which `get` prints for a section or field a doc
/// lacks.
const emptyBaseHash = 'e3b0c44298fc';

/// Returns the base of [text]: the first 12 hex characters of the SHA-256 of
/// its UTF-8 bytes.
///
/// A `set` call hands the base back, so it can tell the target changed since
/// `get`. It is a change check, not a security control.
String baseHashOf(String text) =>
    sha256.convert(utf8.encode(text)).toString().substring(0, 12);
