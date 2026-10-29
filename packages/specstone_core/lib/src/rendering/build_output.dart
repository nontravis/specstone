import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
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

/// Writes [bytes] to [output], creating missing parent folders.
///
/// The write is atomic, so a reader never sees a partial file.
///
/// Throws `output_not_writable` carrying [displayPath] when a folder cannot be
/// created or the file cannot be written.
void writeBuildOutput(
  File output,
  List<int> bytes, {
  required String displayPath,
}) {
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
