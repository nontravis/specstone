import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/code_target.dart';

const _fingerprintLength = 12;
const _bomChar = '\uFEFF';
const _bomFirst = 0xEF;
const _bomSecond = 0xBB;
const _bomThird = 0xBF;

/// Returns the fingerprint of the code file whose content is [bytes].
///
/// Strict UTF-8 text hashes with each CRLF turned into LF and a BOM kept, so
/// a checkout that changes line ends leaves it alone; any other bytes hash
/// raw.
String fileCodeFingerprint(List<int> bytes) {
  try {
    final text = const Utf8Decoder().convert(bytes);
    return baseHashOf(toLf(_startsWithBom(bytes) ? '$_bomChar$text' : text));
  } on FormatException {
    return sha256.convert(bytes).toString().substring(0, _fingerprintLength);
  }
}

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

/// Returns the files a code link [path] of [target] names, as paths from the
/// target's code root, sorted by code point.
///
/// [path] is a file or a folder, as written in a record entry or a `covers:`
/// entry. Leaves out the code root of every other target of [targets] nested
/// in [target]'s, and passes a folder that cannot be listed to [onUnlistable].
/// The one lister the check and the migrate stamp both read.
List<String> codeLinkFiles(
  Directory projectRoot,
  CodeTarget target,
  String path, {
  List<CodeTarget> targets = const [],
  void Function(String folder)? onUnlistable,
}) => filesUnderCodeRoot(
  codeRootFolderOf(projectRoot, target),
  path,
  skipFolders: nestedRootsOf(projectRoot, target, targets),
  onUnlistable: onUnlistable,
);
