import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
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
    this.unclosedFence = false,
    this.openBlock,
    this.openBlockKind,
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

  /// Whether the doc ends inside a fenced code block.
  final bool unclosedFence;

  /// The opening marker, as written, of a generated block with no end marker.
  final String? openBlock;

  /// The generator kind that [openBlock] names.
  final String? openBlockKind;

  /// Returns the wire form; a list prints only when it is not empty,
  /// `unclosedFence` only when true, and `openBlock` only when set.
  Map<String, Object> toJson() => {
    'path': path,
    'status': status.name,
    if (unknownHeaders.isNotEmpty) 'unknownHeaders': unknownHeaders,
    if (duplicateHeaders.isNotEmpty) 'duplicateHeaders': duplicateHeaders,
    if (docTypes.isNotEmpty) 'docTypes': docTypes,
    if (unclosedFence) 'unclosedFence': true,
    'openBlock': ?openBlock,
  };

  String get _reasons => [
    for (final header in unknownHeaders) 'unknown header "$header"',
    for (final header in duplicateHeaders) 'duplicate header "$header"',
    if (docTypes.isNotEmpty) 'doc types ${docTypes.join(', ')} match this path',
    if (unclosedFence) 'unclosed code fence',
    if (openBlockKind != null) 'open generated block $openBlockKind',
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

/// The generators of a format run and the way to open what they read from.
final class GeneratorRun<R> {
  const new({required this.registry, required this.open});

  /// The generators, keyed by kind.
  final GeneratorRegistry<R> registry;

  /// Opens the resolver the generators read from.
  ///
  /// Called at most once per run, and only when a doc under the target has a
  /// doc type that lists generators. `close` runs after the last write.
  final ({R resolver, void Function() close}) Function() open;
}

/// Formats the docs under [target] to their templates.
///
/// A doc is written, atomically and in its own line-ending style, only when
/// its formatted text differs from its LF text and [check] is false. With
/// [generators], a doc whose type lists generators also gets its generated
/// blocks written; the resolver opens before the first write.
///
/// Throws a [RenderFault] `output_not_writable` naming the doc when a write
/// fails; docs written before it stay written. A fault from
/// [GeneratorRun.open] propagates and no doc is written.
FormatReport runFormat<R>(
  DocsProject project,
  Target target, {
  required bool check,
  GeneratorRun<R>? generators,
}) {
  final reads = [
    for (final docFile in collectDocEntries(target, project.matcher))
      readDoc(project, docFile),
  ];
  final run = generators;
  final needsResolver = reads.whereType<ReadableDoc>().any(
    (read) => read.docType.listedGenerators.isNotEmpty,
  );
  final opened = run != null && needsResolver ? run.open() : null;
  try {
    return _formatReads(
      reads,
      check: check,
      blocks: run == null || opened == null
          ? null
          : (run: run, resolver: opened.resolver),
    );
  } finally {
    opened?.close();
  }
}

FormatReport _formatReads<R>(
  List<DocRead> reads, {
  required bool check,
  required ({GeneratorRun<R> run, R resolver})? blocks,
}) {
  final files = <FileResult>[];
  final warnings = <String>[];
  for (final read in reads) {
    switch (read) {
      case UnmatchedDoc(:final path, :final warning):
        files.add(FileResult(path: path, status: FileStatus.skipped));
        warnings.add(warning);
      case NotUtf8Doc(:final path, :final warning):
        files.add(FileResult(path: path, status: FileStatus.skipped));
        warnings.add(warning);
      case UnreadableDoc(:final path, :final isFolder, :final warning):
        // A folder has no file entry, only its warning (s02_api_format).
        if (!isFolder) {
          files.add(FileResult(path: path, status: FileStatus.skipped));
        }
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
        files.add(_formatReadable(read, check: check, blocks: blocks));
    }
  }
  return FormatReport(check: check, files: files, warnings: warnings);
}

FileResult _formatReadable<R>(
  ReadableDoc read, {
  required bool check,
  required ({GeneratorRun<R> run, R resolver})? blocks,
}) {
  switch (formatDoc(read.doc, read.docType)) {
    case Refused(
      :final unknownHeaders,
      :final duplicateHeaders,
      :final unclosedFence,
    ):
      return FileResult(
        path: read.path,
        status: FileStatus.refused,
        unknownHeaders: unknownHeaders,
        duplicateHeaders: duplicateHeaders,
        unclosedFence: unclosedFence,
      );
    case Formatted(:final text):
      var finalText = text;
      if (blocks != null && read.docType.listedGenerators.isNotEmpty) {
        final generated = runGenerators(
          Doc.parse(text),
          read.docType,
          blocks.run.registry,
          blocks.resolver,
        );
        switch (writeGeneratedBlocks(text, read.docType, generated)) {
          case OpenBlock(:final kind, :final marker):
            return FileResult(
              path: read.path,
              status: FileStatus.refused,
              openBlock: marker,
              openBlockKind: kind,
            );
          case BlocksWritten(:final lfText):
            finalText = lfText;
        }
      }
      if (finalText == toLf(read.text)) {
        return FileResult(path: read.path, status: FileStatus.unchanged);
      }
      if (!check) _write(read, finalText);
      return FileResult(path: read.path, status: FileStatus.formatted);
  }
}

void _write(ReadableDoc read, String text) {
  if (isReadOnly(read.file)) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'the doc is read-only',
      file: read.path,
    );
  }
  try {
    final bytes = utf8.encode(read.lineEnding.apply(text));
    writeFileAtomic(read.file, [if (read.hasBom) ...utf8Bom, ...bytes]);
  } on FileSystemException catch (error) {
    final reason = error.osError?.message ?? error.message;
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write the formatted doc: $reason',
      file: read.path,
    );
  }
}
