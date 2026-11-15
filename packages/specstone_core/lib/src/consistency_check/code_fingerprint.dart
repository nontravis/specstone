import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show extensionOfCodePath, isCommentLine;
import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

const _fingerprintLength = 12;
const _bomChar = '\uFEFF';
const _bomFirst = 0xEF;
const _bomSecond = 0xBB;
const _bomThird = 0xBF;
const _space = 0x20;
const _tab = 0x09;

/// Returns the fingerprint of the code file at [path] whose content is
/// [bytes].
///
/// Strict UTF-8 text hashes as its BOM, if any, then its kept lines each with
/// one LF, after CRLF turns into LF and each whole comment line of [path]'s
/// extension and each blank line drops. Any other bytes hash raw.
String fileCodeFingerprint(List<int> bytes, {required String path}) {
  final text = _strictUtf8(bytes);
  if (text == null) return _rawHash(bytes);
  final extension = extensionOfCodePath(path);
  final kept = [
    for (final line in toLf(text).split('\n'))
      if (!_isDropped(line, extension)) '$line\n',
  ];
  return baseHashOf('${_bomPrefix(bytes)}${kept.join()}');
}

/// Returns the fingerprint [fileCodeFingerprint] gave before comment and
/// blank lines were dropped: the whole text, CRLF turned into LF.
String legacyFileCodeFingerprint(List<int> bytes) {
  final text = _strictUtf8(bytes);
  return text == null
      ? _rawHash(bytes)
      : baseHashOf('${_bomPrefix(bytes)}${toLf(text)}');
}

/// Returns [bytes] as text without its BOM, null when they are no strict
/// UTF-8.
String? _strictUtf8(List<int> bytes) {
  try {
    return const Utf8Decoder().convert(bytes);
  } on FormatException {
    return null;
  }
}

String _bomPrefix(List<int> bytes) => _startsWithBom(bytes) ? _bomChar : '';

String _rawHash(List<int> bytes) =>
    sha256.convert(bytes).toString().substring(0, _fingerprintLength);

bool _isDropped(String line, String extension) =>
    isCommentLine(line, extension) || _isBlank(line);

bool _isBlank(String line) =>
    line.codeUnits.every((unit) => unit == _space || unit == _tab);

/// Whether [bytes] open with the UTF-8 BOM, which `Utf8Decoder` drops.
bool _startsWithBom(List<int> bytes) =>
    bytes.length >= 3 &&
    bytes[0] == _bomFirst &&
    bytes[1] == _bomSecond &&
    bytes[2] == _bomThird;

/// Returns the fingerprint of a folder whose listed [files] are given in
/// list order.
///
/// Each file adds one `<path> <fingerprint>` line, each path relative to
/// the code target's code root. An empty list hashes as empty text.
String folderCodeFingerprint(List<({String path, String fingerprint})> files) =>
    baseHashOf(
      [for (final (:path, :fingerprint) in files) '$path $fingerprint\n']
          .join(),
    );

/// Returns the files a code link [path] names, as paths from [codeRoot],
/// sorted by code point.
///
/// [path] is a file or a folder, as written in a record entry or a `covers:`
/// entry, read from [codeRoot]. Leaves out each of [nestedRoots], the code
/// roots of the other targets nested in this one, and passes a folder that
/// cannot be listed to [onUnlistable]. The one lister the check and the
/// migrate stamp both read.
List<String> codeLinkFiles(
  Directory codeRoot,
  String path, {
  List<String> nestedRoots = const [],
  void Function(String folder)? onUnlistable,
}) => filesUnderCodeRoot(
  codeRoot,
  path,
  skipFolders: nestedRoots,
  onUnlistable: onUnlistable,
);
