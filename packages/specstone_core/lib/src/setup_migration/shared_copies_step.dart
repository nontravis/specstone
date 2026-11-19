import 'dart:math' as math;

import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldEntry, parseFieldEntry;
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show MergedDocType;
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:yaml/yaml.dart';

const _yamlSuffix = '.yaml';
const _descriptionKey = 'description';
const _fieldsKey = 'fields';

/// A list item marker with the whitespace around it, which opens the line of
/// a block list entry.
final _listMarker = RegExp(r'^\s*-\s+$');

/// A line that holds the key `fields` alone, a comment allowed.
final _fieldsKeyLine = RegExp(r'^\s*[\x27"]?fields[\x27"]?\s*:\s*(#.*)?$');

/// A project layer file the step reads, its text as LF.
final class ProjectLayerFile {
  const new({required this.path, required this.lf});

  /// The ProjectPath of the file, `/`-separated.
  final String path;

  /// The file's text, read as LF.
  final String lf;
}

/// A personal pack doc-type file the step reads, its text as LF.
final class PersonalPackFile {
  const new({required this.path, required this.lf});

  /// The file as the plan prints it, `~/.specstone/packs/<name>/<file>`.
  final String path;

  /// The file's text, read as LF.
  final String lf;
}

/// The copies of shared entries the `strip_shared_copies` step finds, with the
/// text each project layer file takes.
final class SharedCopiesStep {
  const new({
    required this.rewrites,
    required this.stripped,
    required this.left,
  });

  /// The LF text of each project layer file the step changes, by ProjectPath.
  final Map<String, String> rewrites;

  /// Each copy the step removes, `<path>:<line> <id>`.
  final List<String> stripped;

  /// Each copy the step keeps, `<path>:<line> <id>`.
  final List<String> left;

  /// The plan line printed after the step line, or null with no copy left.
  String? get leftLine =>
      left.isEmpty ? null : 'shared copies left: ${left.length}';
}

/// Plans the removal of each copy of a shared entry from [projectFiles].
///
/// A copy equals, in every property, a shared entry of [target] reaching its
/// doc type; every other byte of a file stays.
/// A copy stays in `left` when its removal cannot be checked, would empty a
/// description no lower layer defines, or changes a merged field that
/// [resolveWith] re-resolves; every copy in [personalFiles] stays.
SharedCopiesStep planSharedCopies({
  required List<ProjectLayerFile> projectFiles,
  required MergedSet target,
  required List<PersonalPackFile> personalFiles,
  required MergedSet Function(Map<String, String> projectTexts) resolveWith,
}) {
  final scans = {
    for (final file in projectFiles)
      file.path: _Scan.of(file.path, file.lf, target),
  };
  final keptFields = <String, Set<int>>{};
  while (true) {
    final removals = {
      for (final MapEntry(:key, :value) in scans.entries)
        if (value != null) key: value.removal(keptFields[key] ?? const {}),
    };
    final changed = _changedFieldCopies(
      removals,
      scans,
      target: target,
      resolveWith: () => resolveWith({
        for (final file in projectFiles)
          file.path: removals[file.path]?.text ?? file.lf,
      }),
    );
    if (changed.isEmpty) return _stepOf(removals, personalFiles, target);
    for (final MapEntry(:key, :value) in changed.entries) {
      (keptFields[key] ??= {}).addAll(value);
    }
  }
}

SharedCopiesStep _stepOf(
  Map<String, _Removal> removals,
  List<PersonalPackFile> personalFiles,
  MergedSet target,
) {
  final rewrites = <String, String>{};
  final stripped = <String>[];
  final left = <String>[];
  for (final MapEntry(:key, :value) in removals.entries) {
    if (value.text case final text?) rewrites[key] = text;
    stripped.addAll(value.stripped.map((copy) => copy.entry(key)));
    left.addAll(value.left.map((copy) => copy.entry(key)));
  }
  for (final file in personalFiles) {
    final scan = _Scan.of(file.path, file.lf, target);
    if (scan == null) continue;
    left.addAll(scan.copies.map((copy) => copy.entry(file.path)));
  }
  return SharedCopiesStep(rewrites: rewrites, stripped: stripped, left: left);
}

/// Returns, by path, the lines of the field copies in [removals] whose removal
/// changes the merged field of their doc type.
///
/// An intermediate layer that writes the same field id makes the shared
/// field's text stop printing once the project copy is gone. [resolveWith] is
/// called only when a field copy is stripped.
Map<String, Set<int>> _changedFieldCopies(
  Map<String, _Removal> removals,
  Map<String, _Scan?> scans, {
  required MergedSet target,
  required MergedSet Function() resolveWith,
}) {
  final hasFieldCopy = removals.values.any(
    (removal) => removal.stripped.any((copy) => copy.isField),
  );
  if (!hasFieldCopy) return const {};
  final after = resolveWith();
  return {
    for (final MapEntry(:key, :value) in removals.entries)
      key: {
        for (final copy in value.stripped)
          if (copy.isField &&
              _mergedFieldOf(target, scans[key]!.type.id, copy.id) !=
                  _mergedFieldOf(after, scans[key]!.type.id, copy.id))
            copy.line,
      },
  }..removeWhere((_, lines) => lines.isEmpty);
}

/// Returns the merged field [fieldId] of [typeId] as comparable text, or null.
String? _mergedFieldOf(MergedSet set, String typeId, String fieldId) {
  final field = set
      .lookup(typeId)
      ?.fields
      .where((field) => field.id == fieldId)
      .firstOrNull;
  return field == null ? null : _canonical(field.toJson());
}

/// One copy: its 1-based [line], the [id] of the shared entry it equals, and
/// whether it is a field entry.
final class _Copy {
  const new(this.line, this.id, {this.isField = false});

  final int line;
  final String id;
  final bool isField;

  String entry(String path) => '$path:$line $id';
}

/// What a file's copies leave: the text with them removed and the copies it
/// removes and keeps.
final class _Removal {
  const new({required this.text, required this.stripped, required this.left});

  /// A removal that keeps every copy in [left].
  const new keeping(List<_Copy> copies)
    : text = null,
      stripped = const [],
      left = copies;

  /// The new LF text, or null when nothing is removed.
  final String? text;
  final List<_Copy> stripped;
  final List<_Copy> left;
}

/// A run of text lines, 0-based and inclusive.
final class _LineRange {
  const new(this.start, this.end);

  final int start;
  final int end;
}

/// The `description` scalar of a file and the value lines of it that are
/// copies.
final class _DescriptionScan {
  const new({
    required this.keyLine,
    required this.endLine,
    required this.firstTextLine,
    required this.valueLines,
    required this.copyAt,
    required this.isEditable,
    required this.isLocatable,
  });

  /// The text line of the `description` key.
  final int keyLine;

  /// The last text line of the scalar.
  final int endLine;

  /// The text line holding the first value line.
  final int firstTextLine;

  /// The scalar's value, split into lines.
  final List<String> valueLines;

  /// The copy of each value line that is one, by value line.
  final Map<int, _Copy> copyAt;

  /// Whether the scalar maps each value line to one text line: a literal
  /// block scalar, or a one-line plain or quoted scalar.
  final bool isEditable;

  /// Whether each copy sits on the text line its value line maps to.
  final bool isLocatable;

  int textLineOf(int valueLine) => firstTextLine + valueLine;

  /// Each copy of the value, in line order.
  List<_Copy> get copies => [...copyAt.values];

  /// Whether the step may strip a copy of the value.
  bool get hasEditableCopy => isEditable && copyAt.isNotEmpty;

  /// Whether every non-blank line of the value is a copy.
  bool get isAllCopies =>
      copyAt.length == valueLines.where((l) => l.trim().isNotEmpty).length;
}

/// A field entry of the `fields` list that equals a shared field.
final class _FieldCopy {
  const new({required this.node, required this.index, required this.copy});

  final YamlMap node;

  /// The position of the entry in the `fields` list.
  final int index;

  final _Copy copy;
}

/// The copies of one doc-type file, read from its text.
final class _Scan {
  const new _({
    required this.path,
    required this.lf,
    required this.root,
    required this.isBlockRoot,
    required this.type,
    required this.description,
    required this.fieldCopies,
  });

  /// Returns the scan of [lf], or null when it holds no copy.
  static _Scan? of(String path, String lf, MergedSet target) {
    final root = _mapRootOf(lf);
    final type = target.lookup(_docTypeIdOf(path));
    if (root == null || type == null) return null;
    final lines = lf.split('\n');
    final scan = _Scan._(
      path: path,
      lf: lf,
      root: root,
      isBlockRoot: root.style == CollectionStyle.BLOCK,
      type: type,
      description: _scanDescription(root, lines, type),
      fieldCopies: _scanFields(root, path, target, type.id),
    );
    return scan.copies.isEmpty ? null : scan;
  }

  final String path;
  final String lf;
  final YamlMap root;

  /// Whether [root] is a block mapping, the only root the step rewrites.
  final bool isBlockRoot;

  final MergedDocType type;
  final _DescriptionScan? description;
  final List<_FieldCopy> fieldCopies;

  /// Every copy of the file, in line order.
  List<_Copy> get copies => _inLineOrder([
    ...?description?.copies,
    for (final field in fieldCopies) field.copy,
  ]);

  /// Plans which copies the file loses and the text it takes.
  ///
  /// The field copies at [keptFieldLines] stay. Every copy stays when the root
  /// is no block mapping, its lines cannot be located, or the text with the
  /// removals no longer reads as the file less the copies.
  _Removal removal(Set<int> keptFieldLines) {
    if (!isBlockRoot) return _Removal.keeping(copies);
    final plan = _plan(keptFieldLines);
    final text = plan.text;
    if (text == null || _isRemovalSafe(text, plan)) return plan;
    return _Removal.keeping(copies);
  }

  _Removal _plan(Set<int> keptFieldLines) {
    final lines = lf.split('\n');
    final drops = _Drops.of(this, keptFieldLines);
    final ranges = drops.ranges(lines);
    if (ranges == null) return _Removal.keeping(copies);
    if (ranges.isEmpty) {
      return _Removal(
        text: null,
        stripped: const [],
        left: _inLineOrder(drops.left),
      );
    }
    for (final range in ranges..sort((a, b) => b.start.compareTo(a.start))) {
      lines.removeRange(range.start, range.end + 1);
    }
    return _Removal(
      text: lines.join('\n'),
      stripped: _inLineOrder(drops.stripped),
      left: _inLineOrder(drops.left),
    );
  }

  bool _isRemovalSafe(String text, _Removal plan) {
    final after = _plainRootOf(text);
    return after != null && '$after' == '${_expectedAfter(plan)}';
  }

  /// The file's plain value with each stripped copy taken out.
  Map<String, Object?> _expectedAfter(_Removal plan) {
    final expected = _plain(root)! as Map<String, Object?>;
    final scan = description;
    final strippedLines = {for (final copy in plan.stripped) copy.line - 1};
    if (scan != null && scan.hasEditableCopy) {
      final kept = [
        for (final (i, line) in scan.valueLines.indexed)
          if (!strippedLines.contains(scan.textLineOf(i))) line,
      ];
      if (kept.length < scan.valueLines.length) {
        if (kept.any((line) => line.trim().isNotEmpty)) {
          expected[_descriptionKey] = kept.join('\n');
        } else {
          expected.remove(_descriptionKey);
        }
      }
    }
    final dropped = {
      for (final field in fieldCopies)
        if (plan.stripped.contains(field.copy)) field.index,
    };
    if (dropped.isNotEmpty) {
      final entries = expected[_fieldsKey]! as List<Object?>;
      final remaining = [
        for (final (i, entry) in entries.indexed)
          if (!dropped.contains(i)) entry,
      ];
      if (remaining.isEmpty) {
        expected.remove(_fieldsKey);
      } else {
        expected[_fieldsKey] = remaining;
      }
    }
    return expected;
  }
}

/// The copies a file loses and keeps, before any text edit.
final class _Drops {
  const new _({
    required this.scan,
    required this.dropsKey,
    required this.strippedFields,
    required this.stripped,
    required this.left,
  });

  /// Decides, for each copy of [scan], whether the step strips or keeps it.
  ///
  /// The field copies at [keptFieldLines] stay, as does every copy of a
  /// description the step cannot edit. A description whose every line
  /// is a copy loses its key when a lower layer defines the doc type, whose own
  /// description then shows; else its last copy stays, so the type keeps one.
  static _Drops of(_Scan scan, Set<int> keptFieldLines) {
    final description = scan.description;
    final strippedFields = [
      for (final field in scan.fieldCopies)
        if (!keptFieldLines.contains(field.copy.line)) field,
    ];
    final stripped = <_Copy>[for (final field in strippedFields) field.copy];
    final left = <_Copy>[
      for (final field in scan.fieldCopies)
        if (keptFieldLines.contains(field.copy.line)) field.copy,
      if (description != null && !description.isEditable) ...description.copies,
    ];
    var dropsKey = false;
    if (description != null && description.hasEditableCopy) {
      final copies = description.copies;
      final isEmptied = description.isAllCopies;
      final hasLowerLayer = scan.type.files.any((file) => file != scan.path);
      dropsKey = isEmptied && hasLowerLayer;
      if (isEmptied && !hasLowerLayer) {
        left.add(copies.removeLast());
      }
      stripped.addAll(copies);
    }
    return _Drops._(
      scan: scan,
      dropsKey: dropsKey,
      strippedFields: strippedFields,
      stripped: stripped,
      left: left,
    );
  }

  final _Scan scan;
  final bool dropsKey;
  final List<_FieldCopy> strippedFields;
  final List<_Copy> stripped;
  final List<_Copy> left;

  /// Returns the text lines to remove, or null when one cannot be located.
  List<_LineRange>? ranges(List<String> lines) {
    final description = scan.description;
    final strippedLines = {for (final copy in stripped) copy.line - 1};
    final result = <_LineRange>[];
    if (description != null && description.hasEditableCopy) {
      if (!description.isLocatable) return null;
      if (dropsKey) {
        result.add(_LineRange(description.keyLine, description.endLine));
      } else {
        for (final key in description.copyAt.keys) {
          final line = description.textLineOf(key);
          if (strippedLines.contains(line)) result.add(_LineRange(line, line));
        }
      }
    }
    if (strippedFields.isEmpty) return result;
    final fieldRanges = _fieldRanges(lines);
    return fieldRanges == null ? null : [...result, ...fieldRanges];
  }

  List<_LineRange>? _fieldRanges(List<String> lines) {
    final result = <_LineRange>[];
    for (final field in strippedFields) {
      final start = field.node.span.start;
      if (!_listMarker.hasMatch(lines[start.line].substring(0, start.column))) {
        return null;
      }
      result.add(_LineRange(start.line, _lastLineOf(field.node)));
    }
    final list = scan.root.nodes[_fieldsKey]! as YamlList;
    if (list.length > strippedFields.length) return result;
    final keyLine = _keyNodeOf(scan.root, _fieldsKey)!.span.start.line;
    if (!_fieldsKeyLine.hasMatch(lines[keyLine])) return null;
    return [...result, _LineRange(keyLine, keyLine)];
  }
}

String _docTypeIdOf(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return name.endsWith(_yamlSuffix)
      ? name.substring(0, name.length - _yamlSuffix.length)
      : name;
}

/// Returns [copies] ordered by line.
List<_Copy> _inLineOrder(List<_Copy> copies) =>
    [...copies]..sort((a, b) => a.line.compareTo(b.line));

/// Returns the root of [lf] when it is a mapping, else null.
YamlMap? _mapRootOf(String lf) {
  final YamlNode node;
  try {
    node = loadYamlNode(lf);
  } on YamlException {
    return null;
  }
  return node is YamlMap ? node : null;
}

/// Returns the plain value of [lf], `{}` for an empty file, or null when it
/// is not a mapping.
Map<String, Object?>? _plainRootOf(String lf) {
  final YamlNode node;
  try {
    node = loadYamlNode(lf);
  } on YamlException {
    return null;
  }
  return switch (node) {
    YamlMap() => _plain(node)! as Map<String, Object?>,
    YamlScalar(value: null) => <String, Object?>{},
    _ => null,
  };
}

/// Returns [node] as maps, lists, and scalars.
Object? _plain(YamlNode node) => switch (node) {
  YamlMap() => {
    for (final entry in node.nodes.entries) '${entry.key}': _plain(entry.value),
  },
  YamlList() => [for (final item in node.nodes) _plain(item)],
  YamlScalar() => node.value,
  _ => node.value,
};

YamlNode? _keyNodeOf(YamlMap map, String key) {
  for (final node in map.nodes.keys) {
    if (node is YamlNode && node.value == key) return node;
  }
  return null;
}

/// Returns the description scan of [root], or null when the key holds no
/// string.
///
/// The step edits a literal block scalar of any chomping or a one-line plain
/// or quoted scalar; a copy in any other scalar is listed at the text line
/// that reads it, else at the key line.
_DescriptionScan? _scanDescription(
  YamlMap root,
  List<String> textLines,
  MergedDocType type,
) {
  final key = _keyNodeOf(root, _descriptionKey);
  final scalar = root.nodes[_descriptionKey];
  if (key == null || scalar is! YamlScalar || scalar.value is! String) {
    return null;
  }
  final value = scalar.value as String;
  final isBlock = scalar.style == ScalarStyle.LITERAL;
  final isOneLine =
      scalar.style != ScalarStyle.FOLDED &&
      !isBlock &&
      !value.contains('\n') &&
      scalar.span.start.line == scalar.span.end.line;
  final isEditable = isBlock || isOneLine;
  final valueLines = value.split('\n');
  final firstTextLine = scalar.span.start.line + (isBlock ? 1 : 0);
  final copyIds = [
    for (final (i, line) in valueLines.indexed)
      if (_sharedLineIdOf(type, line) case final id?) MapEntry(i, id),
  ];
  final listedLines = isEditable
      ? [for (final MapEntry(key: i) in copyIds) firstTextLine + i]
      : _readingLines(
          textLines,
          [for (final MapEntry(key: i) in copyIds) valueLines[i]],
          from: scalar.span.start.line,
          to: scalar.span.end.line,
          quote: _quoteOf(scalar.style),
          fallback: key.span.start.line,
        );
  final copyAt = {
    for (final (n, MapEntry(key: i, value: id)) in copyIds.indexed)
      i: _Copy(listedLines[n] + 1, id),
  };
  return _DescriptionScan(
    keyLine: key.span.start.line,
    endLine: scalar.span.end.line,
    firstTextLine: firstTextLine,
    valueLines: valueLines,
    copyAt: copyAt,
    isEditable: isEditable,
    isLocatable: copyAt.keys.every(
      (i) =>
          isOneLine ||
          (firstTextLine + i < textLines.length &&
              textLines[firstTextLine + i].trimLeft() == valueLines[i]),
    ),
  );
}

/// Returns, for each of [texts] in order, the text line from [from] to [to],
/// both 0-based and inclusive, that reads it, else [fallback].
///
/// Each search starts after the previous match, so a text written twice maps
/// to two lines. A line reads a text once trimmed and stripped of one [quote]
/// at each end.
List<int> _readingLines(
  List<String> textLines,
  List<String> texts, {
  required int from,
  required int to,
  required String quote,
  required int fallback,
}) {
  final last = math.min(to, textLines.length - 1);
  final result = <int>[];
  var next = from;
  for (final text in texts) {
    var found = next;
    while (found <= last && _unquoted(textLines[found].trim(), quote) != text) {
      found++;
    }
    if (found > last) {
      result.add(fallback);
      continue;
    }
    result.add(found);
    next = found + 1;
  }
  return result;
}

/// Returns [text] without one [quote] at its start and one at its end.
String _unquoted(String text, String quote) {
  if (quote.isEmpty) return text;
  final start = text.startsWith(quote) ? quote.length : 0;
  final end = text.endsWith(quote) && text.length > start
      ? text.length - quote.length
      : text.length;
  return text.substring(start, end);
}

/// The quote character a quoted scalar [style] writes, or empty.
String _quoteOf(ScalarStyle style) => switch (style) {
  ScalarStyle.DOUBLE_QUOTED => '"',
  ScalarStyle.SINGLE_QUOTED => "'",
  _ => '',
};

/// Returns the id of the shared line of [type] that reads [text], the one
/// printed first when two do, or null.
String? _sharedLineIdOf(MergedDocType type, String text) {
  if (text.trim().isEmpty) return null;
  String? id;
  var rank = 0;
  for (final line in type.sharedLines) {
    if (line.text != text || (id != null && line.printRank >= rank)) continue;
    id = line.id;
    rank = line.printRank;
  }
  return id;
}

/// Returns the `fields` entries of [root] equal in every property to a shared
/// field that reaches [typeId].
List<_FieldCopy> _scanFields(
  YamlMap root,
  String path,
  MergedSet target,
  String typeId,
) {
  final shared = {
    for (final field in target.shared.fieldsNaming(typeId))
      field.id: _signature(field.entry),
  };
  final list = root.nodes[_fieldsKey];
  if (shared.isEmpty || list is! YamlList) return const [];
  return [
    for (final (i, node) in list.nodes.indexed)
      if (node case final YamlMap entry)
        if (parseFieldEntry(entry, index: i, file: path, keyPrefix: _fieldsKey)
            case final field when shared[field.id] == _signature(field))
          _FieldCopy(
            node: entry,
            index: i,
            copy: _Copy(
              entry.nodes['id']!.span.start.line + 1,
              field.id,
              isField: true,
            ),
          ),
  ];
}

/// Returns every property of [entry] as one comparable text.
String _signature(FieldEntry entry) => _canonical({
  'id': entry.id,
  'type': entry.type?.wire,
  'list': entry.list,
  'required': entry.required,
  'enum': entry.enumValues,
  'doc_types': entry.docTypes,
  'pointer': entry.pointer,
  'root': entry.root,
  'export': entry.export,
  'description': entry.description,
  'lint': entry.lint?.toJson(),
  'disabled': entry.disabled,
});

/// Returns [value] as text that is equal for equal values, map keys in code
/// point order and each scalar with its type.
String _canonical(Object? value) => switch (value) {
  Map() => _canonicalMap(value),
  List() => '[${value.map(_canonical).join(',')}]',
  _ => '${value.runtimeType}:$value',
};

String _canonicalMap(Map<Object?, Object?> map) {
  final entries = [
    for (final MapEntry(:key, :value) in map.entries)
      '$key:${_canonical(value)}',
  ]..sort();
  return '{${entries.join(',')}}';
}

/// Returns the last text line [node] holds, from its content: a block
/// collection's span runs on into the next entry's indentation.
int _lastLineOf(YamlNode node) {
  final children = switch (node) {
    YamlMap(style: CollectionStyle.BLOCK) => [
      for (final entry in node.nodes.entries) ...[
        entry.key as YamlNode,
        entry.value,
      ],
    ],
    YamlList(style: CollectionStyle.BLOCK) => node.nodes,
    _ => const <YamlNode>[],
  };
  if (children.isEmpty) return node.span.end.line;
  return children.map(_lastLineOf).reduce(math.max);
}
