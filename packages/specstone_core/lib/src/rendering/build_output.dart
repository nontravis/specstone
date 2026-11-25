import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

/// A format `build` writes.
///
/// The wire value and the file extension are the [name].
enum OutputFormat {
  html;

  /// Returns the format [value] names; null gives [html].
  ///
  /// Throws `argument_invalid` when [value] names no format.
  static OutputFormat parse(String? value) {
    if (value == null || value == 'html') return html;
    throw RenderFault(
      RenderFaultCode.argumentInvalid,
      '--format takes html, not $value',
    );
  }
}

/// Returns the output file name of [target]: its path relative to the project
/// root, `/`-separated, plus the [format] extension.
///
/// The docs root is `docs`; any other target is `docs/<docPath>`, a file
/// keeping its `.md`. So `x.md` and a folder `x` never share a name.
String outputName(Target target, OutputFormat format) {
  final path = target.isDocsRoot ? 'docs' : 'docs/${target.docPath}';
  return '$path.${format.name}';
}

/// Returns the default output file: [target]'s path mirrored under
/// `<project root>/.specstone/build/`.
File defaultOutputFile(
  DocsProject project,
  Target target,
  OutputFormat format,
) {
  final separator = Platform.pathSeparator;
  final relative = outputName(target, format).split('/').join(separator);
  return File(
    '${project.projectRoot.path}$separator.specstone$separator'
    'build$separator$relative',
  );
}

/// Throws `output_not_writable` carrying [displayPath] when [output] lies
/// inside the docs root or the records root of [project], where a build
/// would overwrite a doc.
///
/// [output] may not exist yet; links and `..` segments resolve first.
void requireOutputOutsideDocRoots(
  DocsProject project,
  File output, {
  required String displayPath,
}) {
  final root = project.isInsideDocsRoot(output)
      ? 'docs'
      : isInsideRecordsRoot(
          canonicalPath(output.absolute.path),
          projectRoot: project.projectRoot,
        )
      ? 'records'
      : null;
  if (root == null) return;
  throw RenderFault(
    RenderFaultCode.outputNotWritable,
    'the output path is inside the $root root',
    file: displayPath,
  );
}

/// Writes [bytes] to [output], creating missing parent folders.
///
/// The write is atomic, so a reader never sees a partial file. With a
/// [within] project, the default output under `.specstone/build/`, [output]
/// must land inside that project and below no `.git` entry; a path the Owner
/// names with `--output` is not judged.
///
/// Throws `output_not_writable` carrying [displayPath] when a folder cannot be
/// created or the file cannot be written, and for a [within] output that
/// leads outside the project.
void writeBuildOutput(
  File output,
  List<int> bytes, {
  required String displayPath,
  DocsProject? within,
}) {
  within?.requireWritablePath(output.path);
  try {
    output.parent.createSync(recursive: true);
    writeFileAtomic(output, bytes);
  } on FileSystemException {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'the output path is not writable',
      file: displayPath,
    );
  }
}

/// The path a build wrote and the warnings raised while building.
final class BuildResult {
  const new({required this.output, required this.warnings});

  /// The output path as printed.
  final String output;

  /// One message per doc skipped or rendered off its template.
  final List<String> warnings;

  /// Returns `{'output': ..., 'warnings': [...]}`.
  Map<String, Object> toJson() => {'output': output, 'warnings': warnings};
}
