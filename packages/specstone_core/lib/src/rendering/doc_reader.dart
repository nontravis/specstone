import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One doc file read and classified by [readDoc].
sealed class DocRead {
  const new(this.file, this.path);

  /// The file on disk.
  final File file;

  /// The path printed in results and warnings (`DocsProject.displayPath`).
  final String path;
}

/// A doc with exactly one doc type and UTF-8 text.
final class ReadableDoc extends DocRead {
  const new(
    super.file,
    super.path, {
    required this.text,
    required this.lineEnding,
    required this.docType,
    required this.doc,
  });

  /// The file text as written, with its own line endings.
  final String text;

  /// The line-break style of [text].
  final LineEnding lineEnding;

  /// The doc type its path matches.
  final MergedDocType docType;

  /// [text] with LF line endings, parsed.
  final Doc doc;
}

/// A doc no doc type matches.
final class UnmatchedDoc extends DocRead {
  const new(super.file, super.path);

  /// The warning for a run that skips the file.
  String get warning => '$path: no doc type matches this path; skipped';
}

/// A doc two or more doc types match.
final class AmbiguousDoc extends DocRead {
  const new(super.file, super.path, {required this.docTypeIds});

  /// The matching doc type ids, in code point order.
  final List<String> docTypeIds;
}

/// A doc a doc type matches whose bytes are not valid UTF-8.
final class NotUtf8Doc extends DocRead {
  const new(super.file, super.path);

  /// The warning for a run that skips the file.
  String get warning => '$path: not UTF-8 text; skipped';
}

/// Matches [docFile] to its doc type, then reads and parses it.
///
/// The bytes are read only for a file with one matching doc type.
DocRead readDoc(DocsProject project, DocFile docFile) {
  final file = docFile.file;
  final path = project.displayPath(file);
  switch (project.matcher.match(docFile.docPath)) {
    case NoDocType():
      return UnmatchedDoc(file, path);
    case AmbiguousDocType(:final docTypeIds):
      return AmbiguousDoc(file, path, docTypeIds: docTypeIds);
    case MatchedDocType(:final docType):
      final String text;
      try {
        text = utf8.decode(file.readAsBytesSync());
      } on FormatException {
        return NotUtf8Doc(file, path);
      }
      return ReadableDoc(
        file,
        path,
        text: text,
        lineEnding: LineEnding.of(text),
        docType: docType,
        doc: Doc.parse(toLf(text)),
      );
  }
}
