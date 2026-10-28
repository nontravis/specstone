import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The UTF-8 byte order mark, which `utf8.decode` drops from a decoded text.
const utf8Bom = [0xEF, 0xBB, 0xBF];

/// Whether [bytes] begin with the UTF-8 byte order mark.
bool startsWithUtf8Bom(List<int> bytes) =>
    bytes.length >= utf8Bom.length &&
    utf8Bom.indexed.every((e) => bytes[e.$1] == e.$2);

/// One doc file read and classified by [readDoc].
sealed class DocRead {
  const new(this.path);

  /// The path printed in results and warnings (`DocsProject.displayPath`).
  final String path;
}

/// A doc with exactly one doc type and UTF-8 text.
final class ReadableDoc extends DocRead {
  const new(
    this.file,
    super.path, {
    required this.text,
    required this.lineEnding,
    required this.hasBom,
    required this.docType,
    required this.doc,
  });

  /// The file on disk.
  final File file;

  /// The file text as written, with its own line endings.
  final String text;

  /// The line-break style of [text].
  final LineEnding lineEnding;

  /// Whether the file starts with a UTF-8 byte order mark that [text] omits.
  final bool hasBom;

  /// The doc type its path matches.
  final MergedDocType docType;

  /// [text] with LF line endings, parsed.
  final Doc doc;
}

/// A doc no doc type matches.
final class UnmatchedDoc extends DocRead {
  const new(super.path);

  /// The warning for a run that skips the file.
  String get warning => '$path: no doc type matches this path; skipped';
}

/// A doc two or more doc types match.
final class AmbiguousDoc extends DocRead {
  const new(super.path, {required this.docTypeIds});

  /// The matching doc type ids, in code point order.
  final List<String> docTypeIds;

  /// The warning for a run that skips the file.
  String get warning =>
      '$path: doc types ${docTypeIds.join(', ')} match this path; skipped';
}

/// A doc a doc type matches whose bytes are not valid UTF-8.
final class NotUtf8Doc extends DocRead {
  const new(super.path);

  /// The warning for a run that skips the file.
  String get warning => '$path: not UTF-8 text; skipped';
}

/// A doc file or folder the run cannot read.
final class UnreadableDoc extends DocRead {
  const new(super.path, {required this.isFolder});

  /// Whether the path is a folder that could not be listed, not a file.
  final bool isFolder;

  /// The warning for a run that skips the path.
  String get warning => '$path: cannot be read; skipped';
}

/// Matches [entry] to its doc type, then reads and parses it.
///
/// The bytes are read only for a file with one matching doc type. A folder
/// the walk could not list, or a file whose bytes cannot be read, is an
/// [UnreadableDoc]; a folder path ends in `/`.
DocRead readDoc(DocsProject project, DocEntry entry) => switch (entry) {
  UnreadableFolder(:final folder) => UnreadableDoc(
    '${project.displayPath(folder)}/',
    isFolder: true,
  ),
  DocFile(:final file, :final docPath) => _readFile(project, file, docPath),
};

DocRead _readFile(DocsProject project, File file, String docPath) {
  final path = project.displayPath(file);
  switch (project.matcher.match(docPath)) {
    case NoDocType():
      return UnmatchedDoc(path);
    case AmbiguousDocType(:final docTypeIds):
      return AmbiguousDoc(path, docTypeIds: docTypeIds);
    case MatchedDocType(:final docType):
      final List<int> bytes;
      try {
        bytes = file.readAsBytesSync();
      } on FileSystemException {
        return UnreadableDoc(path, isFolder: false);
      }
      final String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        return NotUtf8Doc(path);
      }
      return ReadableDoc(
        file,
        path,
        text: text,
        lineEnding: LineEnding.of(text),
        hasBom: startsWithUtf8Bom(bytes),
        docType: docType,
        doc: Doc.parse(toLf(text)),
      );
  }
}
