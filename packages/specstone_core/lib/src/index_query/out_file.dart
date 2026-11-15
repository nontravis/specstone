import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/document_writing/journal_bounds.dart'
    show isGitEntry, pathFromProjectRoot, requireWritableTarget;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show tokenSizeOf;
import 'package:specstone_core/src/index_query/read_answer.dart'
    show ReadAnswer;
import 'package:specstone_core/src/rendering/build_output.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

/// The characters a file name writes as `-`.
const _nameSeparators = ['/', r'\', ':', '#', '@'];

/// The folders under the project's `.specstone/` an `--out` file may live in.
const _outFolders = {'bundles', 'reports'};

const _specstoneFolder = '.specstone';

const _insideDocsRoot = 'the output path is inside the docs root';

const _insideSpecstone =
    'the output path is inside .specstone/ but outside its bundles/ and '
    'reports/';

const _bareNeedsProject = 'a bare --out names its file under a project';

// MARK: - Name

/// Returns the file name a bare `--out` of [command] gives its file.
///
/// - [flags]: the long names, with no dashes, of the flags the call passes
///   but `--out`, `--json`, and `--target`.
/// - [args]: the positional arguments, in order.
/// - [codeTarget]: the `--target` value the call passes, or null.
String outFileName({
  required String command,
  List<String> flags = const [],
  required List<String> args,
  String? codeTarget,
  required bool asJson,
}) {
  final flagPart = [
    for (final flag in [...flags]..sort()) '-$flag',
  ].join();
  final argPart = args.isEmpty ? 'all' : args.map(_written).join('.');
  final targetPart = codeTarget == null ? '' : '.$codeTarget';
  return '$command$flagPart.$argPart$targetPart.${asJson ? 'json' : 'txt'}';
}

String _written(String arg) {
  var named = arg;
  for (final separator in _nameSeparators) {
    named = named.replaceAll(separator, '-');
  }
  return named;
}

/// Returns the file a bare `--out` writes: [name] under the project root's
/// `.specstone/reports/`.
File bareOutFile(Directory projectRoot, String name) {
  final separator = Platform.pathSeparator;
  return File(
    '${projectRoot.path}$separator$_specstoneFolder${separator}reports'
    '$separator$name',
  );
}

// MARK: - Refuse

/// Throws `output_not_writable` when [realPath], an `--out` path with every
/// link on its way resolved, may not be written.
///
/// It refuses a path inside [docsRoot], below a `.git` entry, under
/// [projectRoot]'s `.specstone/` but outside its `bundles/` and `reports/`,
/// and a bare ([isBare]) path outside the project or with no [projectRoot].
/// With no [projectRoot] a named path is judged for `.git` alone.
void requireOutPath(
  String realPath, {
  Directory? projectRoot,
  Directory? docsRoot,
  required bool isBare,
}) {
  if (projectRoot == null) {
    _requireOutsideProject(realPath, isBare: isBare);
    return;
  }
  final shown = pathFromProjectRoot(realPath, projectRoot, docsRoot);
  if (docsRoot != null && _isBelow(realPath, _realOf(docsRoot))) {
    throw _refusal(_insideDocsRoot, shown);
  }
  if (_isInsideSpecstoneFolder(realPath, _realOf(projectRoot))) {
    throw _refusal(_insideSpecstone, shown);
  }
  requireWritableTarget(
    realPath,
    projectRoot: projectRoot,
    docsRoot: docsRoot,
    mayLeaveProject: !isBare,
  );
}

void _requireOutsideProject(String realPath, {required bool isBare}) {
  if (isBare) throw _refusal(_bareNeedsProject, realPath);
  if (realPath.split(Platform.pathSeparator).any(isGitEntry)) {
    throw _refusal('it lies under .git', realPath, prefix: 'cannot write');
  }
}

String _realOf(Directory root) =>
    root.existsSync() ? root.resolveSymbolicLinksSync() : root.absolute.path;

bool _isBelow(String path, String root) =>
    path.startsWith('$root${Platform.pathSeparator}');

/// Whether [realPath] lies in [projectRoot]'s `.specstone/` anywhere but in a
/// file or folder below `bundles/` or `reports/`.
bool _isInsideSpecstoneFolder(String realPath, String projectRoot) {
  if (!_isBelow(realPath, projectRoot)) return false;
  final below = realPath
      .substring(projectRoot.length + 1)
      .split(Platform.pathSeparator);
  if (below.first != _specstoneFolder) return false;
  return below.length < 3 || !_outFolders.contains(below[1]);
}

RenderFault _refusal(String message, String file, {String? prefix}) =>
    RenderFault(
      RenderFaultCode.outputNotWritable,
      prefix == null ? message : '$prefix $file: $message',
      file: file,
    );

// MARK: - Write

/// Writes [text] to [file] and returns the reply that names it.
///
/// [text] is the whole file, the JSON text when the caller writes `--json`'s
/// form; [asJson] picks the reply: the header line, or `{out, lines, tokens}`.
/// The reply names the canonical absolute path of [file]; [warnings] and
/// [exitStatus] pass through to the reply.
///
/// Throws `output_not_writable` as [requireOutPath] and for a write that
/// fails, before any file changes.
ReadAnswer answerOutFile({
  required String command,
  required String text,
  required File file,
  Directory? projectRoot,
  Directory? docsRoot,
  required bool isBare,
  required bool asJson,
  List<String> warnings = const [],
  int exitStatus = 0,
}) {
  final shownPath = canonicalPath(file.absolute.path);
  requireOutPath(
    shownPath,
    projectRoot: projectRoot,
    docsRoot: docsRoot,
    isBare: isBare,
  );
  writeBuildOutput(File(shownPath), utf8.encode(text), displayPath: shownPath);
  final lines = const LineSplitter().convert(text).length;
  final tokens = tokenSizeOf(text);
  return ReadAnswer(
    text: '==> $command: $lines lines, $tokens tokens · $shownPath <==\n',
    json: {'out': shownPath, 'lines': lines, 'tokens': tokens},
    warnings: warnings,
    exitStatus: exitStatus,
  );
}
