import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show withKeyBlock, withSectionAdded;
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show readDocAddress;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show sectionKeyOf;
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/models/pattern_move.dart';
import 'package:specstone_core/src/templates/nested_paths.dart'
    show movePatternsAtEveryDepth;
import 'package:yaml/yaml.dart';

const _defaultIndent = '  ';

// MARK: - Merge

/// A doc after a `merge_doc` step folded a doc into it.
final class MergedDoc {
  const new({
    required this.text,
    required this.movedHeaders,
    this.sectionGroups = const [],
    this.unmergedFields = const [],
    this.isLeadUnplaced = false,
  });

  /// The LF text of the `to` doc.
  final String text;

  /// The header of each section the merge added, in the order it added them.
  final List<String> movedHeaders;

  /// The indexes of the `from` sections joined under each of [movedHeaders].
  final List<List<int>> sectionGroups;

  /// The key of each `from` list field whose entries did not land, because
  /// the `to` doc's field of that key is no list or not valid YAML.
  final List<String> unmergedFields;

  /// Whether the `from` doc holds a lead but no section to place it in.
  final bool isLeadUnplaced;
}

/// Returns [toLf], the `to` doc of [step], with each `##` section and each
/// list field entry of [fromLf] folded in.
///
/// A section whose header matches a mapped `header` takes the header of the
/// `to` section its id names in [toHeaders]; every other section keeps its
/// header. Sections mapped to one id join under one header, at the place of
/// the first. The lead of [fromLf], the text between its title and its first
/// section, opens the body of the first section the merge adds. An entry the
/// `to` doc's field already holds is not added again.
/// An empty [toLf] means the `to` doc is absent: the result is the text of its
/// new draft.
MergedDoc mergeDocInto({
  required String toLf,
  required String fromLf,
  required MergeDoc step,
  required Map<String, String> toHeaders,
}) {
  final from = Doc.parse(fromLf);
  final sections = _mappedSections(from, step, toHeaders);
  final lead = _withoutBlankEnds(from.lead);
  if (lead.isNotEmpty && sections.isNotEmpty) {
    sections.first.bodies.insert(0, lead);
  }
  final isLeadUnplaced = lead.isNotEmpty && sections.isEmpty;
  final fields = _listFields(from);
  final unmerged = <String>[];
  final text = toLf.isEmpty
      ? _draftOf(from, sections, fields)
      : _foldedInto(toLf, sections, fields, unmerged);
  return MergedDoc(
    text: text,
    movedHeaders: [for (final section in sections) section.header],
    sectionGroups: [for (final section in sections) section.members],
    unmergedFields: unmerged,
    isLeadUnplaced: isLeadUnplaced,
  );
}

/// One section the merge adds: its header, the bodies joined under it, and
/// the index of each `from` section they come from.
final class _Out {
  new(this.header);

  final String header;
  final bodies = <String>[];
  final members = <int>[];

  String get body => bodies.where((body) => body.isNotEmpty).join('\n\n');
}

List<_Out> _mappedSections(
  Doc from,
  MergeDoc step,
  Map<String, String> toHeaders,
) {
  final mapped = _mappedHeadersOf(step, toHeaders);
  final out = <String, _Out>{};
  for (final (index, section) in from.sections.indexed) {
    final header = mapped[headerKey(section.headerText)] ?? section.headerText;
    (out[headerKey(header)] ??= _Out(header))
      ..bodies.add(_withoutBlankEnds(section.body))
      ..members.add(index);
  }
  return out.values.toList();
}

/// Returns the `to` header each mapped `from` header of [step] takes, by the
/// [headerKey] of the `from` header; null when [toHeaders] lacks its id.
Map<String, String?> _mappedHeadersOf(
  MergeDoc step,
  Map<String, String> toHeaders,
) => {
  for (final section in step.sections)
    headerKey(section.fromHeader): toHeaders[section.toId],
};

String _withoutBlankEnds(String body) {
  final lines = body.split('\n');
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}

String _draftOf(Doc from, List<_Out> sections, List<_ListField> fields) {
  final buffer = StringBuffer('---\ndraft: true\n');
  for (final field in fields) {
    buffer.write(field.block.text);
  }
  buffer.write('---\n');
  if (from.title case final title?) buffer.write('\n# $title\n');
  for (final section in sections) {
    buffer.write(_sectionText(section, leadingBlank: true));
  }
  return buffer.toString();
}

String _sectionText(_Out section, {required bool leadingBlank}) {
  final body = section.body;
  return '${leadingBlank ? '\n' : ''}## ${section.header}\n'
      '${body.isEmpty ? '' : '\n$body\n'}';
}

String _foldedInto(
  String toLf,
  List<_Out> sections,
  List<_ListField> fields,
  List<String> unmerged,
) {
  var text = toLf;
  for (final field in fields) {
    text = _withEntriesFolded(text, field, unmerged);
  }
  for (final section in sections) {
    final body = section.body;
    text = withSectionAdded(
      text,
      headerLine: '## ${section.header}',
      body: body.isEmpty ? '' : '\n$body\n',
    );
  }
  return text;
}

// MARK: - List fields

/// A list field of the `from` doc: its key block and its entries.
final class _ListField {
  const new(this.block, this.entries);

  final KeyBlock block;
  final List<_Entry> entries;
}

/// One list entry: its text at column 0 and its YAML value, canonical.
final class _Entry {
  const new(this.text, this.canon);

  final String text;
  final String canon;
}

List<_ListField> _listFields(Doc from) => [
  for (final block in from.frontmatter ?? const <KeyBlock>[])
    if (block.key.isNotEmpty)
      if (_entriesOf(block) case final entries? when entries.isNotEmpty)
        _ListField(block, entries),
];

/// Returns the entries of [block], or null when its value is no list or does
/// not parse.
List<_Entry>? _entriesOf(KeyBlock block) {
  final Object? value;
  try {
    value = loadYaml(block.indentedValueText);
  } on YamlException {
    return null;
  }
  if (value is! YamlList) return null;
  return _inlineValue(block).isEmpty
      ? _blockEntries(_linesAfterKey(block))
      : _jsonEntries(value);
}

List<_Entry> _jsonEntries(Iterable<Object?> values) => [
  for (final value in values) _Entry('- ${_canonOf(value)}\n', _canonOf(value)),
];

/// The text after `key:` on the key line, trimmed.
String _inlineValue(KeyBlock block) {
  final lines = block.text.split('\n');
  final at = lines.indexWhere((line) => !_isTrivia(line));
  if (at < 0) return '';
  final colon = lines[at].indexOf(':', block.key.length);
  final rest = colon < 0 ? '' : lines[at].substring(colon + 1).trim();
  return rest.startsWith('#') ? '' : rest;
}

/// The lines of [block] after its key line, comment lines dropped.
List<String> _linesAfterKey(KeyBlock block) {
  final lines = block.text.split('\n');
  final at = lines.indexWhere((line) => !_isTrivia(line));
  if (at < 0) return const [];
  return [
    for (final line in lines.skip(at + 1))
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) line,
  ];
}

List<_Entry> _blockEntries(List<String> lines) {
  if (lines.isEmpty) return const [];
  final indent = _indentOf(lines.first);
  final starts = RegExp('^${RegExp.escape(indent)}-(?: |\$)');
  final chunks = <List<String>>[];
  for (final line in lines) {
    if (starts.hasMatch(line)) {
      chunks.add([line.substring(indent.length)]);
    } else if (chunks.isNotEmpty) {
      chunks.last.add(
        line.startsWith(indent) ? line.substring(indent.length) : line,
      );
    }
  }
  final entries = <_Entry>[];
  for (final chunk in chunks) {
    final text = '${chunk.join('\n')}\n';
    try {
      final value = loadYaml(text);
      if (value is YamlList && value.length == 1) {
        entries.add(_Entry(text, _canonOf(value.first)));
      }
    } on YamlException {
      continue;
    }
  }
  return entries;
}

String _withEntriesFolded(String lf, _ListField field, List<String> unmerged) {
  final key = field.block.name;
  final held = (Doc.parse(lf).frontmatter ?? const <KeyBlock>[])
      .where((block) => block.name == key)
      .firstOrNull;
  if (held == null) return withKeyBlock(lf, key, field.block.text);
  final Object? value;
  try {
    value = loadYaml(held.indentedValueText);
  } on YamlException {
    unmerged.add(key);
    return lf;
  }
  if (value != null && value is! YamlList) {
    unmerged.add(key);
    return lf;
  }
  final heldEntries = value is YamlList ? value : const <Object?>[];
  final keep = {for (final entry in heldEntries) _canonOf(entry)};
  final added = <_Entry>[];
  for (final entry in field.entries) {
    if (keep.add(entry.canon)) added.add(entry);
  }
  if (added.isEmpty) return lf;
  final lines = _linesAfterKey(held);
  final inline = _inlineValue(held);
  final indent = lines.isEmpty || inline.isNotEmpty
      ? _defaultIndent
      : _indentOf(lines.first);
  final text = inline.isEmpty
      ? _blockAppended(held, indent, added)
      : _blockRebuilt(held, indent, value, added);
  return withKeyBlock(lf, key, text);
}

String _blockAppended(KeyBlock held, String indent, List<_Entry> added) {
  final text = held.text.endsWith('\n') ? held.text : '${held.text}\n';
  return text + _indented(added, indent);
}

/// Returns [held] as a block list: its key line, then the entries it held
/// and the [added] ones, each at [indent].
String _blockRebuilt(
  KeyBlock held,
  String indent,
  Object? value,
  List<_Entry> added,
) {
  final lines = held.text.split('\n');
  final at = lines.indexWhere((line) => !_isTrivia(line));
  final before = lines.take(at).map((line) => '$line\n').join();
  final heldEntries = _jsonEntries(value is YamlList ? value : const []);
  return '$before${held.key}:\n${_indented(heldEntries, indent)}'
      '${_indented(added, indent)}';
}

String _indented(List<_Entry> entries, String indent) => [
  for (final entry in entries)
    for (final line in entry.text.split('\n'))
      if (line.isNotEmpty) '$indent$line\n',
].join();

String _indentOf(String line) =>
    line.substring(0, line.length - line.trimLeft().length);

bool _isTrivia(String line) => line.startsWith('#') || line.trim().isEmpty;

/// Returns [value], a YAML value, as the JSON text that equals another value
/// of the same content.
String _canonOf(Object? value) => jsonEncode(_plain(value));

Object? _plain(Object? value) => switch (value) {
  final Map<Object?, Object?> map => {
    for (final entry in map.entries) '${entry.key}': _plain(entry.value),
  },
  final List<Object?> list => [for (final item in list) _plain(item)],
  _ => value,
};

// MARK: - From docs

/// One doc a `merge_doc` step folds: the path it is read at and the path of
/// the doc that takes it, both DocPaths, and the Name of each.
final class FoldSource {
  const new({
    required this.fromPath,
    required this.toPath,
    required this.fromName,
    required this.toName,
  });

  final String fromPath;
  final String toPath;
  final String fromName;
  final String toName;
}

/// Returns each doc of [docPaths] that [step] folds, in [docPaths]' order.
///
/// A doc is read at [fromPattern], or at the step's own pattern when it is
/// null, and takes its placeholder values to the `to` type's path in [set].
/// When the `to` type nests, the two paths pair once per nesting depth, as a
/// `move_file` step's do. With [twinNames] and a per-target `to` type, each
/// target reads both paths in its own folder, and the first target also reads
/// the `from` path at its one-target place, where the spec tree move leaves a
/// doc outside the target folders. A doc whose values the `to` path cannot
/// take is left out.
List<FoldSource> foldSourcesOf(
  MergeDoc step, {
  required List<String> docPaths,
  required MergedSet set,
  required List<String> twinNames,
  String? fromPattern,
}) {
  final toType = set.lookup(step.toId);
  final toPath = toType?.path;
  if (toType == null || toPath == null) return const [];
  final nesting = toType.nestedPaths == null ? null : set.nestingType;
  final pairs = nesting == null
      ? [PatternMove(from: fromPattern ?? step.fromPath, to: toPath)]
      : movePatternsAtEveryDepth(fromPattern ?? step.fromPath, toPath, nesting);
  final targets = toType.isPerTarget && twinNames.isNotEmpty
      ? twinNames
      : const <String?>[null];
  final sources = <FoldSource>[];
  for (final target in targets) {
    PathPattern read(String path) => target == null
        ? PathPattern(path)
        : PathPattern(path).forTarget(target);
    for (final pair in pairs) {
      final from = read(pair.from);
      final to = read(pair.to);
      // The spec tree move leaves a `from` doc, which no type holds, at its
      // one-target path; the first target's `to` doc takes it.
      final oneTarget = target != null && target == twinNames.first
          ? PathPattern(pair.from)
          : null;
      bool inTargetFolder(String docPath) => twinNames.any(
        (name) => PathPattern(pair.from).forTarget(name).matches(docPath),
      );
      for (final docPath in docPaths) {
        final reader = from.matches(docPath)
            ? from
            : (oneTarget != null && !inTargetFolder(docPath)
                  ? oneTarget
                  : null);
        final values = reader?.valuesOf(docPath);
        if (reader == null || values == null) continue;
        if (values.length != _placeholdersIn(to)) continue;
        final toDocPath = to.fill(values);
        sources.add(
          FoldSource(
            fromPath: docPath,
            toPath: toDocPath,
            fromName: _nameOf(reader.slugValues(docPath), step.fromId),
            toName: _nameOf(to.slugValues(toDocPath), step.toId),
          ),
        );
      }
    }
  }
  return sources;
}

/// Returns the Name a doc of type [id] whose path gives [slugs] answers to,
/// as `docNameOf` reads it.
String _nameOf(List<String>? slugs, String id) =>
    slugs == null || slugs.isEmpty ? id : slugs.join('/');

int _placeholdersIn(PathPattern pattern) =>
    PathSegment.placeholderCount(pattern.source);

// MARK: - Links

/// The typed name a folded doc's name takes: the last `to` doc's type id and
/// Name, and the section key each `from` section key takes there.
final class _TypedFold {
  const new(this.toId, this.toName, this.keys);

  final String toId;
  final String toName;
  final Map<String, String> keys;

  String get typedName => '$toId:$toName';

  /// Returns this fold carried on by a later step of its `to` doc, which
  /// leaves it as [nextName] of type [nextId] and maps its keys by [later].
  _TypedFold through(
    String nextId,
    String nextName,
    Map<String, String> later,
  ) => _TypedFold(nextId, nextName, _composed(keys, later));
}

/// Returns the key map [first] then [later] give: each key of [first] maps
/// through [later], and a key [first] keeps takes [later]'s value.
Map<String, String> _composed(
  Map<String, String> first,
  Map<String, String> later,
) => {
  for (final MapEntry(:key, :value) in later.entries)
    if (!first.containsKey(key)) key: value,
  for (final MapEntry(:key, :value) in first.entries)
    key: later[value] ?? value,
};

/// A link text a fold or a section rename retyped.
final class RetypedText {
  const new(this.text, {required this.isFolded});

  final String text;

  /// Whether a fold changed the text, not a section rename alone.
  final bool isFolded;
}

/// The typed names and section keys the run's folds and section renames
/// give, composed in step order.
final class FoldedDocs {
  new() : _folds = {}, _fromIds = {}, _renamedKeys = {};

  /// By `<from id>:<Name>`.
  final Map<String, _TypedFold> _folds;

  /// The `from` doc type id of each fold.
  final Set<String> _fromIds;

  /// The key each renamed section key of a doc type takes, by type id.
  final Map<String, Map<String, String>> _renamedKeys;

  bool get isEmpty => _folds.isEmpty && _renamedKeys.isEmpty;

  /// Records that [source] folds under [step], the `to` sections headed as
  /// [toHeaders] gives.
  ///
  /// An earlier fold whose `to` doc this folds follows it to the new `to`
  /// doc, its keys mapped through this fold's.
  void add(
    FoldSource source,
    MergeDoc step, {
    required Map<String, String> toHeaders,
  }) {
    final keys = _composed(_renamedKeys[step.fromId] ?? const {}, {
      for (final section in step.sections)
        if (toHeaders[section.toId] case final header?)
          sectionKeyOf(section.fromHeader): sectionKeyOf(header),
    });
    final from = '${step.fromId}:${source.fromName}';
    _folds.updateAll(
      (_, fold) => fold.typedName == from
          ? fold.through(step.toId, source.toName, keys)
          : fold,
    );
    _fromIds.add(step.fromId);
    _folds[from] = _TypedFold(step.toId, source.toName, keys);
  }

  /// Records that [step] renames a section of its doc type, for each fold
  /// landing on that type and each typed text naming it directly.
  ///
  /// The `from` section matches a key by its id or its header's key.
  void renamed(RenameSection step) {
    final to = sectionKeyOf(step.toHeader);
    final rename = {step.fromId: to, sectionKeyOf(step.fromHeader): to};
    _folds.updateAll(
      (_, fold) => fold.toId == step.docType
          ? fold.through(fold.toId, fold.toName, rename)
          : fold,
    );
    _renamedKeys[step.docType] = _composed(
      _renamedKeys[step.docType] ?? const {},
      rename,
    );
  }

  /// Whether [body] may hold a link text that starts with a folded doc's
  /// `<from id>:` or a renamed type's `<doc type>:`, so the link text pass
  /// needs its parse.
  bool mayRetype(String body) =>
      [..._fromIds, ..._renamedKeys.keys].any((id) => body.contains('[$id:'));

  /// Returns [text], a link text, as a folded doc's last typed name and key,
  /// else with the renamed key of the type it names; null when neither
  /// changes it.
  RetypedText? textOf(String text) {
    final address = readDocAddress(text);
    final typeId = address.typeId;
    if (typeId == null || !address.isName) return null;
    final key = address.sectionKey;
    if (_folds[address.docPart] case final fold?) {
      final mapped = key == null ? '' : '#${fold.keys[key] ?? key}';
      return RetypedText('${fold.typedName}$mapped', isFolded: true);
    }
    final renamed = key == null ? null : _renamedKeys[typeId]?[key];
    if (renamed == null || renamed == key) return null;
    return RetypedText('${address.docPart}#$renamed', isFolded: false);
  }
}
