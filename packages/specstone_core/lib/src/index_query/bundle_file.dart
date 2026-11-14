import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/document_writing/journal_bounds.dart'
    show requireWritableTarget;
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/build_output.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

/// The most lines an index keeps its sections within, its header included.
const _indexLineCap = 200;

/// The most UTF-8 bytes an index keeps its sections within, its header
/// included.
const _indexByteCap = 8192;

/// The characters a file name writes as `-`: path separators and `:`.
const _nameSeparators = ['/', r'\', ':'];

// MARK: - Name

/// Returns the name a bare `--out` gives the bundle file, by the Name rule of
/// `index_query/get_task_bundle/write_bundle_to_file`.
///
/// - [target]: the call's target, as given; else [codePath], the `--code`
///   value as given, which takes `code-` before it.
/// - [codeTarget]: the `--target` value the call passes, or null.
String bundleFileName({
  String? target,
  String? codePath,
  required BundleMode mode,
  required bool summary,
  required bool noProject,
  String? codeTarget,
}) {
  assert(
    (target == null) != (codePath == null),
    'a bundle has a target or a code path',
  );
  var named = target ?? 'code-$codePath';
  for (final separator in _nameSeparators) {
    named = named.replaceAll(separator, '-');
  }
  final modePart = [
    mode.wire,
    if (summary) 'summary',
    if (noProject) 'no-project',
  ].join('-');
  final targetPart = codeTarget == null ? '' : '.$codeTarget';
  return '$named.$modePart$targetPart.txt';
}

/// Returns the file a bare `--out` writes: [name] under the project root's
/// `.specstone/bundles/`.
File bareBundleFile(Directory projectRoot, String name) {
  final separator = Platform.pathSeparator;
  return File(
    '${projectRoot.path}$separator.specstone${separator}bundles$separator$name',
  );
}

// MARK: - Write

/// Writes [answer]'s bundle text to [file] and returns the reply that indexes
/// it (`index_query/get_task_bundle/write_bundle_to_file`).
///
/// The reply names the file by the canonical path the docs-root check
/// compares. Throws `output_not_writable` for a path inside the docs root,
/// a bare ([isBare]) one outside the project or below `.git`, or a write
/// that fails.
ReadAnswer answerBundleFile(
  ContextAnswer answer,
  File file, {
  required DocsProject project,
  required bool isBare,
}) {
  assert(answer.exitStatus == 0, 'a bundle over budget is never written');
  final shownPath = canonicalPath(file.absolute.path);
  if (project.isInsideDocsRoot(File(shownPath))) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'the output path is inside the docs root',
      file: shownPath,
    );
  }
  if (isBare) {
    requireWritableTarget(shownPath, projectRoot: project.projectRoot);
  }
  writeBuildOutput(
    File(shownPath),
    utf8.encode(answer.text),
    displayPath: shownPath,
  );
  return ReadAnswer(
    text: bundleIndex(answer, shownPath),
    json: bundleIndexJson(answer, shownPath),
    warnings: answer.warnings,
  );
}

// MARK: - Index

/// Returns the stdout index of [answer]'s bundle saved at [shownPath]: the
/// header line, then one line per doc and appended part with its line range.
///
/// Each line lists its sections' first lines while the whole index stays
/// within 200 lines and 8 KiB, its header included; past either bound no
/// line lists a section, and every doc still prints (INV-16).
String bundleIndex(ContextAnswer answer, String shownPath) {
  final header =
      '==> bundle: ${_docCountOf(answer)} docs, ${answer.tokens} tokens, '
      '${_lineCountOf(answer.text)} lines · $shownPath <==\n';
  final full = [
    header,
    for (final entry in answer.entries) _indexLine(entry, withSections: true),
  ].join();
  final fits =
      answer.entries.length + 1 <= _indexLineCap &&
      utf8.encode(full).length <= _indexByteCap;
  if (fits) return full;
  return [
    header,
    for (final entry in answer.entries) _indexLine(entry, withSections: false),
  ].join();
}

/// Returns `--out`'s `--json` object for [answer]'s bundle saved at
/// [shownPath]; each doc lists its sections whatever the index's size.
Map<String, Object> bundleIndexJson(ContextAnswer answer, String shownPath) => {
  'out': shownPath,
  'tokens': answer.tokens,
  'lines': _lineCountOf(answer.text),
  'docs': [
    for (final entry in answer.entries)
      {
        'name': entry.doc.name,
        'docType': ?entry.doc.docTypeId,
        'docPath': entry.doc.docPath,
        'lines': [entry.first, entry.last],
        'summary': entry.summary,
        'cited': entry.cited,
        'sections': [
          for (final section in entry.sections)
            {'key': section.key, 'first': section.first},
        ],
      },
  ],
};

/// Returns `- <list name> · <first>-<last>`, then ` · <key> <first>, …` for
/// [entry]'s sections when [withSections] and it has any.
String _indexLine(BundleEntry entry, {required bool withSections}) {
  final range = '- ${entry.listName} · ${entry.first}-${entry.last}';
  if (!withSections || entry.sections.isEmpty) return '$range\n';
  final sections = [
    for (final section in entry.sections) '${section.key} ${section.first}',
  ];
  return '$range · ${sections.join(', ')}\n';
}

/// Returns the number of picked docs [answer] prints; appended parts aside.
int _docCountOf(ContextAnswer answer) =>
    answer.entries.where((entry) => !entry.cited).length;

int _lineCountOf(String text) => const LineSplitter().convert(text).length;
