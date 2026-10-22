import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

/// Whether a layer holds a file at a layer-relative path.
///
/// Implemented by the disk and the shipped sources at load time.
abstract interface class LayerFiles {
  /// Whether the layer holds a file at [layerRelativePath].
  bool exists(String layerRelativePath);
}

/// One `reference:` entry of a doc type, as one layer writes it.
final class ReferenceEntry {
  new({required this.title, this.url, this.file, this.doc, this.locator});

  /// The source's name; a title-only entry is a book or standard.
  final String title;

  /// The link address, shown as written and never fetched.
  final String? url;

  /// The cited file, normalized to its layer-relative path.
  final String? file;

  /// The cited project doc identity; only the project layer may write it.
  final String? doc;

  /// The chapter, page, or appendix of the cited source.
  final String? locator;

  /// Parses one entry of a `reference` list, at fault key [key].
  ///
  /// [templateFolder] is the template file's folder relative to the layer
  /// folder, `''` at the top; a `file` is resolved against it.
  static ReferenceEntry parse(
    YamlMap entry, {
    required String file,
    required String key,
    required LayerKind kind,
    required String templateFolder,
    required LayerFiles files,
  }) {
    final title = requireValue<String>(
      entry,
      'title',
      file: file,
      prefix: '$key.',
    );
    checkKeys(
      entry,
      _entryKeys,
      file: file,
      format: 'doc-type',
      prefix: '$key.',
    );
    final prefix = '$key.';
    final url = optionalValue<String>(entry, 'url', file: file, prefix: prefix);
    final citedFile = optionalValue<String>(
      entry,
      'file',
      file: file,
      prefix: prefix,
    );
    final doc = optionalValue<String>(entry, 'doc', file: file, prefix: prefix);
    if ([?url, ?citedFile, ?doc].length > 1) {
      throw TemplateFault(
        FaultCode.referenceLinkConflict,
        'the entry must hold only one of url, file, or doc',
        file: file,
        key: key,
      );
    }
    return ReferenceEntry(
      title: title,
      url: url,
      file: citedFile == null
          ? null
          : _resolveFile(
              citedFile,
              templateFolder: templateFolder,
              file: file,
              key: key,
              files: files,
            ),
      doc: _checkedDoc(doc, kind: kind, file: file, key: key),
      locator: optionalValue<String>(
        entry,
        'locator',
        file: file,
        prefix: prefix,
      ),
    );
  }

  /// Returns the JSON object of this entry with only the keys set.
  Map<String, Object> toJson() => {
    'title': title,
    'url': ?url,
    'file': ?file,
    'doc': ?doc,
    'locator': ?locator,
  };
}

const _entryKeys = {'title', 'url', 'file', 'doc', 'locator'};

/// Resolves [written] against [templateFolder] and checks it exists.
///
/// [written] is a plain layer-relative path, never a URI reference, so names
/// keep their written characters. Throws `reference_file_outside` for a
/// scheme, a drive letter, a leading `/`, any `\` (reference paths use `/`),
/// or any `..` segment that pops above the template file's folder, and
/// `reference_file_missing` when the layer holds no file at the resolved path.
String _resolveFile(
  String written, {
  required String templateFolder,
  required String file,
  required String key,
  required LayerFiles files,
}) {
  final segments = _insideSegments(written, templateFolder);
  if (segments == null) {
    throw TemplateFault(
      FaultCode.referenceFileOutside,
      'the cited file $written must stay inside the template file folder',
      file: file,
      key: key,
    );
  }
  final normalized = segments.join('/');
  if (!files.exists(normalized)) {
    throw TemplateFault(
      FaultCode.referenceFileMissing,
      'the cited file $normalized does not exist',
      file: file,
      key: key,
    );
  }
  return normalized;
}

/// A scheme (`file:`, `https:`) or drive letter (`C:`) opening a path.
final _schemePrefix = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*:');

/// Returns the layer-relative segments of [written] under [templateFolder].
///
/// Returns null when [written] is not a path inside the template folder. Empty
/// and `.` segments drop out; a `..` that would pop above the folder fails.
List<String>? _insideSegments(String written, String templateFolder) {
  if (written.startsWith('/') ||
      written.contains(r'\') ||
      _schemePrefix.hasMatch(written)) {
    return null;
  }
  final inside = <String>[];
  for (final segment in written.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment != '..') {
      inside.add(segment);
    } else if (inside.isEmpty) {
      return null;
    } else {
      inside.removeLast();
    }
  }
  return [
    for (final segment in templateFolder.split('/'))
      if (segment.isNotEmpty) segment,
    ...inside,
  ];
}

String? _checkedDoc(
  String? doc, {
  required LayerKind kind,
  required String file,
  required String key,
}) {
  if (doc == null || kind == LayerKind.project) return doc;
  throw TemplateFault(
    FaultCode.referenceDocOutsideProject,
    'a doc reference is allowed only in the project layer',
    file: file,
    key: key,
  );
}
