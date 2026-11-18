import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/rendering/skill_references.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

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

  /// A reference file under a skill's `references/` that no Sources doc maps
  /// to; only `check` reports it, and `format` never deletes it.
  leftover,
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
    this.changesStructure = false,
    this.skillRefusal,
    this.skillRefusalMessage,
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

  /// Whether laying the doc out would change its frontmatter or its sections.
  final bool changesStructure;

  /// Why the run refuses the skill doc's reference files, which leaves the
  /// skill doc unwritten too.
  final SkillRefusalCode? skillRefusal;

  /// The message naming the case of [skillRefusal].
  final String? skillRefusalMessage;

  /// Returns the wire form; a list prints only when it is not empty,
  /// `unclosedFence` and `changesStructure` only when true, and `openBlock`
  /// and `skillRefusal` only when set.
  Map<String, Object> toJson() => {
    'path': path,
    'status': status.name,
    if (unknownHeaders.isNotEmpty) 'unknownHeaders': unknownHeaders,
    if (duplicateHeaders.isNotEmpty) 'duplicateHeaders': duplicateHeaders,
    if (docTypes.isNotEmpty) 'docTypes': docTypes,
    if (unclosedFence) 'unclosedFence': true,
    'openBlock': ?openBlock,
    if (changesStructure) 'changesStructure': true,
    'skillRefusal': ?skillRefusal?.wire,
  };

  String get _reasons => [
    for (final header in unknownHeaders) 'unknown header "$header"',
    for (final header in duplicateHeaders) 'duplicate header "$header"',
    if (docTypes.isNotEmpty) 'doc types ${docTypes.join(', ')} match this path',
    if (unclosedFence) 'unclosed code fence',
    if (openBlockKind != null) 'open generated block $openBlockKind',
    if (changesStructure) 'layout would change the doc structure',
    if (skillRefusal case final code?) '${code.wire}: $skillRefusalMessage',
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

  /// 1 when a doc is refused or a reference file is left over, or under
  /// [check] a doc would change; else 0.
  int get exitStatus {
    final failed = files.any(
      (file) =>
          file.status == FileStatus.refused ||
          file.status == FileStatus.leftover ||
          (check && file.status == FileStatus.formatted),
    );
    return failed ? 1 : 0;
  }

  /// Returns one line per formatted, refused, or leftover file, `''` when
  /// none.
  String toText() {
    final out = StringBuffer();
    for (final file in files) {
      switch (file.status) {
        case FileStatus.formatted:
          out.writeln(check ? file.path : '${file.path}: formatted');
        case FileStatus.refused:
          out.writeln('${file.path}: refused: ${file._reasons}');
        case FileStatus.leftover:
          out.writeln('${file.path}: leftover');
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

/// Formats the docs under [target] to their templates; a [target] that is the
/// docs root takes in the records root too.
///
/// A doc is written, atomically and in its own line-ending style, only when
/// its formatted text differs from its LF text and [check] is false. With
/// [generators], a doc whose type lists generators also gets its generated
/// blocks written; the resolver opens before the first write.
///
/// With [rewriteLinks], each `skill` doc under [target] gets its reference
/// files (see [SkillReferences.plan]). A refused skill doc is left unwritten.
/// After the docs, each reference file that differs from the file on disk is
/// written, unless [check], and listed right after its skill doc.
///
/// Throws a [RenderFault] `output_not_writable` naming the doc or reference
/// file when a write fails; files written before it stay written. A fault
/// from [GeneratorRun.open] propagates and no doc is written.
FormatReport runFormat<R>(
  DocsProject project,
  Target target, {
  required bool check,
  GeneratorRun<R>? generators,
  LinkRewriter? rewriteLinks,
}) {
  final targets = [target, if (target.isDocsRoot) ?project.recordsTarget];
  final reads = [
    for (final target in targets)
      for (final entry in collectDocEntries(target, project.matcher))
        readDoc(project, entry),
  ];
  SkillReferences? planSkills() => rewriteLinks == null
      ? null
      : SkillReferences.plan(project, target, rewriteLinks: rewriteLinks);
  final skills = planSkills();
  final run = generators;
  final needsResolver = reads.whereType<ReadableDoc>().any(
    (read) => read.docType.listedGenerators.isNotEmpty,
  );
  final opened = run != null && needsResolver ? run.open() : null;
  try {
    final report = _formatReads(
      project,
      reads,
      check: check,
      blocks: run == null || opened == null
          ? null
          : (run: run, resolver: opened.resolver),
      skills: skills,
    );
    if (skills == null || !skills.skills.any((s) => s is ExportedSkill)) {
      return report;
    }
    // A Sources doc this run wrote is read again, as it now is on disk.
    final wroteDocs =
        !check && report.files.any((f) => f.status == FileStatus.formatted);
    return _withReferences(project, report, wroteDocs ? planSkills()! : skills);
  } finally {
    opened?.close();
  }
}

/// Returns [report] with a result for each reference file of [skills] that
/// differs from its file on disk, right after its skill doc's result, in path
/// order; each is written unless the run only checks. A check also lists each
/// leftover file of the skill's `references/` folder.
FormatReport _withReferences(
  DocsProject project,
  FormatReport report,
  SkillReferences skills,
) {
  final check = report.check;
  final warnings = [...report.warnings];
  final files = [
    for (final result in report.files) ...[
      result,
      if (result.skillRefusal == null)
        if (skills.of(result.path) case final ExportedSkill skill)
          ..._referenceResults(
            project,
            skill,
            check: check,
            warnings: warnings,
          ),
    ],
  ];
  return FormatReport(check: check, files: files, warnings: warnings);
}

List<FileResult> _referenceResults(
  DocsProject project,
  ExportedSkill skill, {
  required bool check,
  required List<String> warnings,
}) {
  final results = [
    for (final reference in skill.files)
      if (_differsOnDisk(reference))
        _referenceResult(project, reference, check: check),
  ];
  if (check) {
    try {
      for (final path in skill.leftoverPaths) {
        results.add(FileResult(path: path, status: FileStatus.leftover));
      }
    } on FileSystemException {
      // Like an unlistable doc folder: skipped with a warning, never silent.
      final folder = skill.referencesPath;
      results.add(FileResult(path: folder, status: FileStatus.skipped));
      warnings.add('$folder: cannot be read; skipped');
    }
  }
  return results..sort((a, b) => compareCodePoints(a.path, b.path));
}

bool _differsOnDisk(ReferenceFile reference) {
  try {
    final text = utf8.decode(reference.file.readAsBytesSync());
    return toLf(text) != reference.text;
  } on FileSystemException {
    return true;
  } on FormatException {
    return true;
  }
}

FileResult _referenceResult(
  DocsProject project,
  ReferenceFile reference, {
  required bool check,
}) {
  if (!check) _writeReference(project, reference);
  return FileResult(path: reference.path, status: FileStatus.formatted);
}

void _writeReference(DocsProject project, ReferenceFile reference) {
  final file = reference.file;
  project.requireWritablePath(file.path);
  if (isReadOnly(file)) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'the reference file is read-only',
      file: reference.path,
    );
  }
  try {
    file.parent.createSync(recursive: true);
    writeFileAtomic(file, reference.bytes);
  } on FileSystemException catch (error) {
    final reason = error.osError?.message ?? error.message;
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write the reference file: $reason',
      file: reference.path,
    );
  }
}

FormatReport _formatReads<R>(
  DocsProject project,
  List<DocRead> reads, {
  required bool check,
  required ({GeneratorRun<R> run, R resolver})? blocks,
  required SkillReferences? skills,
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
        files.add(
          _formatReadable(
            project,
            read,
            check: check,
            blocks: blocks,
            refusal: switch (skills?.of(read.path)) {
              final RefusedSkill refused => refused,
              _ => null,
            },
          ),
        );
    }
  }
  return FormatReport(check: check, files: files, warnings: warnings);
}

/// Formats [read]; a skill doc with a [refusal] is refused and never written.
FileResult _formatReadable<R>(
  DocsProject project,
  ReadableDoc read, {
  required bool check,
  required ({GeneratorRun<R> run, R resolver})? blocks,
  required RefusedSkill? refusal,
}) {
  switch (formatDoc(read.doc, read.docType)) {
    case Refused(
      :final unknownHeaders,
      :final duplicateHeaders,
      :final unclosedFence,
      :final openBlock,
      :final openBlockKind,
      :final changesStructure,
    ):
      return FileResult(
        path: read.path,
        status: FileStatus.refused,
        unknownHeaders: unknownHeaders,
        duplicateHeaders: duplicateHeaders,
        unclosedFence: unclosedFence,
        openBlock: openBlock,
        openBlockKind: openBlockKind,
        changesStructure: changesStructure,
        skillRefusal: refusal?.code,
        skillRefusalMessage: refusal?.message,
      );
    case Formatted() when refusal != null:
      return FileResult(
        path: read.path,
        status: FileStatus.refused,
        skillRefusal: refusal.code,
        skillRefusalMessage: refusal.message,
      );
    case Formatted(:final text):
      var finalText = text;
      if (blocks != null && read.docType.listedGenerators.isNotEmpty) {
        // The formatted text is laid out, and the inserted pair carries its
        // own layout whitespace, so no second layout pass runs here.
        finalText = fillGeneratedBlocks(
          text,
          read.docType,
          blocks.run.registry,
          blocks.resolver,
          docPath: read.docPath,
        );
      }
      if (finalText == toLf(read.text)) {
        return FileResult(path: read.path, status: FileStatus.unchanged);
      }
      if (!check) _write(project, read, finalText);
      return FileResult(path: read.path, status: FileStatus.formatted);
  }
}

void _write(DocsProject project, ReadableDoc read, String text) {
  project.requireWritablePath(read.file.path);
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
