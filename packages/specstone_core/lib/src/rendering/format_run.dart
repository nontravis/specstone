import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

/// What a format run did with one doc.
enum FileStatus {
  /// Changed, or under `check` would change.
  formatted,

  /// Already matches its template, line endings aside.
  unchanged,

  /// Not a doc the run can work on; a warning says why.
  skipped,

  /// Left alone because its headers or doc types are ambiguous.
  refused,
}

/// The outcome of one doc in a [FormatReport].
final class FileResult {
  const new({
    required this.path,
    required this.status,
    this.unknownHeaders = const [],
    this.duplicateHeaders = const [],
    this.docTypes = const [],
  });

  /// The doc's path, relative to the project root.
  final String path;

  /// What the run did with the doc.
  final FileStatus status;

  /// Headers the template does not define, as written.
  final List<String> unknownHeaders;

  /// Headers that occur more than once, in template form.
  final List<String> duplicateHeaders;

  /// The doc types its path matches, when two or more do.
  final List<String> docTypes;

  /// Returns the wire form; a list prints only when it is not empty.
  Map<String, Object> toJson() => {
    'path': path,
    'status': status.name,
    if (unknownHeaders.isNotEmpty) 'unknownHeaders': unknownHeaders,
    if (duplicateHeaders.isNotEmpty) 'duplicateHeaders': duplicateHeaders,
    if (docTypes.isNotEmpty) 'docTypes': docTypes,
  };

  String get _reasons => [
    for (final header in unknownHeaders) 'unknown header "$header"',
    for (final header in duplicateHeaders) 'duplicate header "$header"',
    if (docTypes.isNotEmpty) 'doc types ${docTypes.join(', ')} match this path',
  ].join('; ');
}

/// The result of a format run, in tree order.
final class FormatReport {
  const new({required this.check, required this.files, required this.warnings});

  /// Whether the run only checked and wrote nothing.
  final bool check;

  /// Every doc the run visited.
  final List<FileResult> files;

  /// Warnings as plain message text.
  final List<String> warnings;

  /// 1 when a doc is refused, or under [check] a doc would change; else 0.
  int get exitStatus {
    final failed = files.any(
      (file) =>
          file.status == FileStatus.refused ||
          (check && file.status == FileStatus.formatted),
    );
    return failed ? 1 : 0;
  }

  /// Returns one line per formatted or refused doc, `''` when none.
  String toText() {
    final out = StringBuffer();
    for (final file in files) {
      switch (file.status) {
        case FileStatus.formatted:
          out.writeln(check ? file.path : '${file.path}: formatted');
        case FileStatus.refused:
          out.writeln('${file.path}: refused: ${file._reasons}');
        case FileStatus.unchanged || FileStatus.skipped:
          break;
      }
    }
    return out.toString();
  }

  /// Returns the `--json` object: every file and the warnings.
  Map<String, Object> toJson() => {
    'files': [for (final file in files) file.toJson()],
    'warnings': warnings,
  };
}

/// Formats the docs under [target] to their templates.
///
/// A doc is written, atomically and in its own line-ending style, only when
/// its formatted text differs from its LF text and [check] is false.
///
/// Throws a [RenderFault] `output_not_writable` naming the doc when a write
/// fails; docs written before it stay written.
FormatReport runFormat(
  DocsProject project,
  Target target, {
  required bool check,
}) {
  final files = <FileResult>[];
  final warnings = <String>[];
  for (final docFile in collectDocFiles(target, project.matcher)) {
    switch (readDoc(project, docFile)) {
      case UnmatchedDoc(:final path, :final warning):
        files.add(FileResult(path: path, status: FileStatus.skipped));
        warnings.add(warning);
      case NotUtf8Doc(:final path, :final warning):
        files.add(FileResult(path: path, status: FileStatus.skipped));
        warnings.add(warning);
      case AmbiguousDoc(:final path, :final docTypeIds):
        files.add(
          FileResult(
            path: path,
            status: FileStatus.refused,
            docTypes: docTypeIds,
          ),
        );
      case final ReadableDoc read:
        files.add(_formatReadable(read, check: check));
    }
  }
  return FormatReport(check: check, files: files, warnings: warnings);
}

FileResult _formatReadable(ReadableDoc read, {required bool check}) {
  switch (formatDoc(read.doc, read.docType)) {
    case Refused(:final unknownHeaders, :final duplicateHeaders):
      return FileResult(
        path: read.path,
        status: FileStatus.refused,
        unknownHeaders: unknownHeaders,
        duplicateHeaders: duplicateHeaders,
      );
    case Formatted(:final text) when text == toLf(read.text):
      return FileResult(path: read.path, status: FileStatus.unchanged);
    case Formatted(:final text):
      if (!check) _write(read, text);
      return FileResult(path: read.path, status: FileStatus.formatted);
  }
}

void _write(ReadableDoc read, String text) {
  try {
    writeFileAtomic(read.file, utf8.encode(read.lineEnding.apply(text)));
  } on FileSystemException catch (error) {
    final reason = error.osError?.message ?? error.message;
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write the formatted doc: $reason',
      file: read.path,
    );
  }
}
