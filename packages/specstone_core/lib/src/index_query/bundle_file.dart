import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_prune.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/feature_pattern_parts.dart'
    show featurePatternDocAddress, featurePatternListName;
import 'package:specstone_core/src/index_query/out_file.dart';
import 'package:specstone_core/src/index_query/read_answer.dart'
    show ReadAnswer, nameWithType;
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

/// What a refs file's name carries before its extension.
const _refsMark = '.refs';

/// The `/`-separated path of the bundles folder below a project root.
const _bundlesBelowRoot = '.specstone/bundles';

const _refsIsReadFirst = 'the refs file is the read-first file';

// MARK: - Name

/// Returns the name a bare `--out` gives the bundle file.
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

/// Returns the folder under [projectRoot] that holds the files a bare `--out`
/// writes.
Directory bundlesFolderOf(Directory projectRoot) {
  final separator = Platform.pathSeparator;
  return Directory(
    '${projectRoot.path}$separator.specstone${separator}bundles',
  );
}

/// Returns the file a bare `--out` writes: [name] under the project root's
/// `.specstone/bundles/`.
File bareBundleFile(Directory projectRoot, String name) =>
    File('${bundlesFolderOf(projectRoot).path}${Platform.pathSeparator}$name');

/// Returns the refs file of the read-first file at [path]: `.refs` before the
/// extension of its name, or at its end when the name has none.
///
/// A dot that opens the name or lies in a folder name is no extension.
String refsPathOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot <= _nameStartOf(path)) return '$path$_refsMark';
  return '${path.substring(0, dot)}$_refsMark${path.substring(dot)}';
}

int _nameStartOf(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = Platform.isWindows ? path.lastIndexOf(r'\') : -1;
  return (slash > backslash ? slash : backslash) + 1;
}

// MARK: - Write

/// Writes [answer]'s bundle text to [file], and its refs text to the refs file
/// beside it when the answer is split, then prunes old bundle files.
///
/// The reply names each file by its canonical path. Throws
/// `output_not_writable` for a path [requireOutPath] refuses, judged for both
/// files before either is written, or for a write that fails; a call that
/// throws prunes nothing.
ReadAnswer answerBundleFile(
  ContextAnswer answer,
  File file, {
  required DocsProject project,
  required bool isBare,
}) {
  assert(answer.exitStatus == 0, 'a bundle over budget is never written');
  final shownPath = canonicalPath(file.absolute.path);
  final refs = answer.refs;
  final refsPath = refs == null ? null : canonicalPath(refsPathOf(shownPath));
  if (refsPath == shownPath) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      _refsIsReadFirst,
      file: shownPath,
    );
  }
  final writes = {shownPath: answer.text, ?refsPath: ?refs?.text};
  for (final path in writes.keys) {
    requireOutPath(
      path,
      projectRoot: project.projectRoot,
      docsRoot: project.docsRoot,
      isBare: isBare,
    );
  }
  for (final MapEntry(key: path, value: text) in writes.entries) {
    writeBuildOutput(File(path), utf8.encode(text), displayPath: path);
  }
  _pruneBundlesOf(project.projectRoot, keep: writes.keys.toSet());
  return ReadAnswer(
    text: bundleIndex(answer, shownPath, refsPath: refsPath),
    json: bundleIndexJson(answer, shownPath, refsPath: refsPath),
    warnings: answer.warnings,
  );
}

/// Prunes the project's `.specstone/bundles/`, keeping [keep].
///
/// A `bundles/` that is a link, or lies below one, is left alone: its real
/// folder is not the project's own.
void _pruneBundlesOf(Directory projectRoot, {required Set<String> keep}) {
  final real = canonicalPath(bundlesFolderOf(projectRoot).path);
  if (!isBundlesFolderOf(canonicalPath(projectRoot.path), real)) return;
  pruneBundles(Directory(real), keep: keep, now: DateTime.now());
}

/// Whether [path] is `.specstone/bundles` right below [root], both canonical.
///
/// [isWindows] picks the path style; it defaults to the running platform.
bool isBundlesFolderOf(String root, String path, {bool? isWindows}) =>
    pathInside(root, path, isWindows: isWindows) == _bundlesBelowRoot;

// MARK: - Index

/// Returns the stdout index of [answer]'s bundle saved at [shownPath] and, for
/// a split answer, of its refs file saved at [refsPath].
///
/// It prints the code target line when the answer has one, then per file, the
/// read-first file's first, a header line and one line per doc, appended
/// part, cited-by part, names block, and feature pattern part with its line
/// range in that file. Each line lists its sections' first lines while the
/// whole index stays within 200 lines and 8 KiB, both files, header lines, and
/// the code target line counted together; past either bound no line lists a
/// section, and every doc still prints.
String bundleIndex(ContextAnswer answer, String shownPath, {String? refsPath}) {
  final files = _filesOf(answer, shownPath, refsPath);
  String index({required bool withSections}) => [
    codeTargetLine(answer.codeTarget),
    for (final (:file, :path) in files)
      _fileIndex(file, path, withSections: withSections),
  ].join();
  final full = index(withSections: true);
  final fits =
      _lineCountOf(full) <= _indexLineCap &&
      utf8.encode(full).length <= _indexByteCap;
  return fits ? full : index(withSections: false);
}

/// Returns `--out`'s `--json` object for [answer]'s bundle saved at
/// [shownPath], with its `codeTarget` when it has one; each doc lists its
/// sections whatever the index's size.
///
/// The object describes the read-first file. A split answer adds a `refs`
/// object of the same shape, `{out, tokens, lines, docs}`, for the file saved
/// at [refsPath]. A design answer also lists its feature pattern parts under
/// `featurePatterns`, as `{id, doc, lines}`; `docs` lists no part but an
/// appended one.
Map<String, Object> bundleIndexJson(
  ContextAnswer answer,
  String shownPath, {
  String? refsPath,
}) {
  final [readFirst, ...refs] = _filesOf(answer, shownPath, refsPath);
  return {
    ..._fileJson(readFirst.file, readFirst.path, codeTarget: answer.codeTarget),
    if (answer.json['for'] == BundleMode.design.wire)
      'featurePatterns': [
        for (final entry in answer.entries)
          if (entry.featurePattern case final id?)
            {
              'id': id,
              'doc': featurePatternDocAddress(entry.doc),
              'lines': [entry.first, entry.last],
            },
      ],
    for (final file in refs) 'refs': _fileJson(file.file, file.path),
  };
}

/// Returns each file [answer] saves, the read-first file first, with its
/// path; the refs file's is [refsPath], which a split answer needs.
List<({BundleText file, String path})> _filesOf(
  ContextAnswer answer,
  String shownPath,
  String? refsPath,
) {
  assert(
    (answer.refs == null) == (refsPath == null),
    'a split answer names its refs path, an unsplit one none',
  );
  return [
    (file: answer.readFirst, path: shownPath),
    if ((answer.refs, refsPath) case (final refs?, final path?))
      (file: refs, path: path),
  ];
}

/// Returns the header line of [file] saved at [path], then one index line per
/// entry.
String _fileIndex(BundleText file, String path, {required bool withSections}) {
  final lines = [
    for (final entry in file.entries)
      _indexLine(entry, withSections: withSections),
  ];
  return '==> bundle: ${docCountOf(file.entries)} docs, ${file.tokens} tokens, '
      '${_lineCountOf(file.text)} lines · $path <==\n'
      '${lines.join()}';
}

/// Returns `{out, tokens, lines, docs}` for [file] saved at [path], with
/// `codeTarget` after `out` when [codeTarget] is given.
Map<String, Object> _fileJson(
  BundleText file,
  String path, {
  String? codeTarget,
}) => {
  'out': path,
  'codeTarget': ?codeTarget,
  'tokens': file.tokens,
  'lines': _lineCountOf(file.text),
  'docs': [
    for (final entry in file.entries)
      if (entry.kind case BundleEntryKind.doc || BundleEntryKind.cited)
        {
          'name': entry.doc.name,
          'docType': ?entry.doc.docTypeId,
          'docPath': entry.doc.docPath,
          'lines': [entry.first, entry.last],
          'summary': entry.summary,
          'cited': entry.kind == BundleEntryKind.cited,
          'sections': [
            for (final section in entry.sections)
              {'key': section.key, 'first': section.first},
          ],
        },
  ],
};

/// Returns `- <name> (<doc type>) · <first>-<last>`, then ` · summary`, the
/// kind's mark, and ` · <key> <first>, …` for [entry]'s sections when
/// [withSections].
///
/// The kind's mark is `cited <section key> [<ID>]` for an appended part,
/// `cited by [<ID>]`, `cited by [#<section key>]`, or `cited by` for a
/// cited-by part, and `names` for a names block. A
/// feature pattern part's line is its list name, then ` · <first>-<last>`.
String _indexLine(BundleEntry entry, {required bool withSections}) {
  if (entry.featurePattern case final id?) {
    return '- ${featurePatternListName(id)} · ${entry.first}-${entry.last}\n';
  }
  final fields = [
    nameWithType(entry.doc),
    '${entry.first}-${entry.last}',
    if (entry.summary) 'summary',
    ?_kindMark(entry),
    if (withSections && entry.sections.isNotEmpty)
      [for (final section in entry.sections) '${section.key} ${section.first}']
          .join(', '),
  ];
  return '- ${fields.join(' · ')}\n';
}

String? _kindMark(BundleEntry entry) => switch (entry.kind) {
  BundleEntryKind.cited => _citedField(entry),
  BundleEntryKind.citedBy => _citedByField(entry),
  BundleEntryKind.names => 'names',
  BundleEntryKind.doc || BundleEntryKind.pattern => null,
};

/// Returns `cited`, with the section key and `[<ID>]` [entry] names.
String _citedField(BundleEntry entry) => [
  'cited',
  ?entry.sectionKey,
  if (entry.itemId != null) '[${entry.itemId}]',
].join(' ');

/// Returns `cited by`, with the `[<ID>]` of the item or block [entry] follows,
/// or the `[#<section key>]` of the section; none for a whole doc.
String _citedByField(BundleEntry entry) => [
  'cited by',
  if (entry.itemId case final id?)
    '[$id]'
  else if (entry.sectionKey case final key?)
    '[#$key]',
].join(' ');

int _lineCountOf(String text) => const LineSplitter().convert(text).length;
