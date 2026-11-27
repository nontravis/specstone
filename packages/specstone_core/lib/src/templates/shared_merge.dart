import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_chain.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

const _linesKey = 'shared_lines';
const _fieldsKey = 'shared_fields';
const _forDocTypesKey = 'for_doc_types';
const _sectionsKey = 'sections';

/// Returns the lines every doc type of [types] holds with an equal id and
/// text, in the first type's print order.
///
/// A line a layer rewrites or disables for one type is not shared by all, so
/// each type that keeps it prints it in its own guide.
List<MergedSharedLine> sharedByAll(List<MergedDocType> types) {
  if (types.isEmpty) return const [];
  final [first, ...others] = types;
  return [
    for (final line in first.sharedLines)
      if (others.every(
        (type) => type.sharedLines.any(
          (held) => held.id == line.id && held.text == line.text,
        ),
      ))
        line,
  ];
}

/// A shared field after every layer merged.
final class MergedSharedField {
  const new({
    required this.entry,
    required this.forDocTypes,
    required this.declaringPack,
    required this.order,
  });

  /// The field with each property its layers wrote, never disabled.
  final FieldEntry entry;

  /// The doc type ids the field names.
  final List<String> forDocTypes;

  /// The pack whose layer first defined the field.
  final String declaringPack;

  /// The place of the field among the fields, set by its first defining layer.
  final int order;

  /// The id the layers matched the field by.
  String get id => entry.id;
}

/// A shared banned or required pattern after every layer merged.
final class MergedSharedPattern {
  const new({
    required this.entry,
    required this.kind,
    required this.forDocTypes,
    this.sections,
    required this.declaringPack,
  });

  /// The pattern with each key its layers wrote, never disabled; its regex
  /// is the shared pattern a `pattern_ref` named, when one was written.
  final PatternEntry entry;

  /// The list the pattern belongs to.
  final SharedPatternKind kind;

  /// The doc type ids the pattern names; empty for a source-only pattern.
  final List<String> forDocTypes;

  /// The section ids the pattern is limited to, or null for none.
  final List<String>? sections;

  /// The pack whose layer first defined the pattern.
  final String declaringPack;

  /// Whether the pattern reaches no doc type and no section, so it reports
  /// nothing and serves only a `pattern_ref`.
  bool get isSourceOnly => forDocTypes.isEmpty && sections == null;

  /// The id the layers matched the pattern by, within its [kind].
  String get id => entry.id;
}

/// The shared lines, fields, and patterns of one resolve, disabled entries
/// absent, in print order.
final class SharedSet {
  const new({
    required this.lines,
    required this.fields,
    required this.patterns,
    this.disabledLineIds = const {},
  });

  /// No shared entries.
  static const SharedSet empty = SharedSet(lines: [], fields: [], patterns: []);

  /// The merged lines.
  final List<MergedSharedLine> lines;

  /// The ids of lines a layer declared and a later layer disabled.
  final Set<String> disabledLineIds;

  /// The merged fields.
  final List<MergedSharedField> fields;

  /// The merged banned patterns, then the merged required patterns.
  final List<MergedSharedPattern> patterns;

  /// Returns the lines that name [docTypeId] or name no doc type.
  List<MergedSharedLine> linesNaming(String docTypeId) => [
    for (final line in lines)
      if (line.forDocTypes?.contains(docTypeId) ?? true) line,
  ];

  /// Returns the fields that name [docTypeId].
  List<MergedSharedField> fieldsNaming(String docTypeId) => [
    for (final field in fields)
      if (field.forDocTypes.contains(docTypeId)) field,
  ];

  /// Returns the patterns that name [docTypeId].
  List<MergedSharedPattern> patternsNaming(String docTypeId) => [
    for (final pattern in patterns)
      if (pattern.forDocTypes.contains(docTypeId)) pattern,
  ];
}

/// Merges the shared entries of [ordered] and [projectLines] by `id`.
///
/// [ordered] holds the packs in layer order, [projectLines] the `shared.yaml`
/// lines on top. [docTypeIdsByPack] holds the doc type ids each pack defines,
/// keyed by pack name, and [mergedDocTypeIds] every doc type of the merged
/// set.
///
/// Throws `unknown_value` for a pack entry naming a doc type outside its pack
/// chain, a `shared.yaml` line naming a doc type outside [mergedDocTypeIds],
/// and an id two packs declare with neither extending the other;
/// `override_id_not_found` for an entry that can neither change nor add; and
/// `missing_key` for a new shared field or pattern with no `for_doc_types`
/// and a new required pattern with no `sections`, a new pattern with neither
/// reach key excepted when a `pattern_ref` names it, and `pattern_ref_invalid`
/// for a shared `pattern_ref` that names no entry of its list or loops.
///
/// [bannedRefIds] and [requiredRefIds] hold the ids the doc-type layers'
/// `pattern_ref` entries name in each list.
SharedSet mergeSharedEntries({
  required List<LoadedPack> ordered,
  required List<SharedLine> projectLines,
  required Map<String, Set<String>> docTypeIdsByPack,
  required Set<String> mergedDocTypeIds,
  Set<String> bannedRefIds = const {},
  Set<String> requiredRefIds = const {},
}) {
  final extendsOf = extendsMapOf(ordered);
  for (final pack in ordered) {
    _checkPackReach(pack, ordered, docTypeIdsByPack, extendsOf);
  }
  _checkProjectReach(projectLines, mergedDocTypeIds);
  _checkNewFieldReach(ordered);
  final sources = _checkNewPatternReach(ordered);
  final merge = _SharedMerge(extendsOf);
  ordered.forEach(merge.addPack);
  merge.addProjectLines(projectLines);
  final set = merge.build();
  _checkSourcesNamed(
    sources,
    set,
    banned: {...bannedRefIds, ...merge.refIds(SharedPatternKind.banned)},
    required: {...requiredRefIds, ...merge.refIds(SharedPatternKind.required)},
  );
  return set;
}

/// Throws `missing_key` for the first complete new shared field, one no lower
/// pack holds, that writes no `for_doc_types`.
///
/// Runs before the merge pass, so it precedes any merge fault. A field a
/// lower layer disabled counts as new when a later layer adds it again.
void _checkNewFieldReach(List<LoadedPack> ordered) {
  final held = <String>{};
  for (final pack in ordered) {
    for (final field in pack.manifest.shared.fields) {
      final entry = field.entry;
      if (entry.disabled) {
        held.remove(entry.id);
      } else if (!held.contains(entry.id) && entry.type != null) {
        if (field.forDocTypes == null) throw _missingFieldReach(field);
        held.add(entry.id);
      }
    }
  }
}

/// Throws `missing_key` for the first complete new shared pattern, one no
/// lower pack holds in its list, that writes `sections` but no
/// `for_doc_types`, or, when required, `for_doc_types` but no `sections`.
///
/// Runs before the merge pass, as [_checkNewFieldReach] does. Returns the
/// complete new patterns that write neither reach key: each is a source only
/// when a `pattern_ref` names it, which [_checkSourcesNamed] checks.
List<SharedPattern> _checkNewPatternReach(List<LoadedPack> ordered) {
  final bannedIds = <String>{};
  final requiredIds = <String>{};
  final sources = <SharedPattern>[];
  for (final pack in ordered) {
    for (final pattern in pack.manifest.shared.patterns) {
      final ids = switch (pattern.kind) {
        SharedPatternKind.banned => bannedIds,
        SharedPatternKind.required => requiredIds,
      };
      if (pattern.disabled) {
        ids.remove(pattern.id);
      } else if (!ids.contains(pattern.id) && _isComplete(pattern)) {
        if (pattern.forDocTypes == null && pattern.sections == null) {
          sources.add(pattern);
        } else {
          final missing = _missingReachKey(pattern);
          if (missing != null) throw _missingPatternReach(pattern, missing);
        }
        ids.add(pattern.id);
      }
    }
  }
  return sources;
}

/// Throws `missing_key` at the `for_doc_types` of the first of [sources]
/// that still reaches nothing and that no `pattern_ref` names.
///
/// [banned] and [required] hold the ids the refs name in each list.
void _checkSourcesNamed(
  List<SharedPattern> sources,
  SharedSet set, {
  required Set<String> banned,
  required Set<String> required,
}) {
  for (final source in sources) {
    final named = switch (source.kind) {
      SharedPatternKind.banned => banned,
      SharedPatternKind.required => required,
    }.contains(source.id);
    final merged = set.patterns.where(
      (pattern) => pattern.kind == source.kind && pattern.id == source.id,
    );
    if (named || merged.isEmpty || !merged.single.isSourceOnly) continue;
    throw _missingPatternReach(source, _forDocTypesKey);
  }
}

bool _isComplete(SharedPattern pattern) =>
    (pattern.pattern != null || pattern.patternRef != null) &&
    pattern.message != null;

/// Returns the reach key a complete new [pattern] lacks, or null.
String? _missingReachKey(SharedPattern pattern) {
  if (pattern.forDocTypes == null) return _forDocTypesKey;
  if (pattern.kind == SharedPatternKind.required && pattern.sections == null) {
    return _sectionsKey;
  }
  return null;
}

TemplateFault _missingPatternReach(SharedPattern pattern, String key) =>
    TemplateFault(
      FaultCode.missingKey,
      'a new shared pattern requires $key',
      file: pattern.file,
      key: '${pattern.kind.listKey}[${pattern.index}].$key',
    );

TemplateFault _missingFieldReach(SharedField field) => TemplateFault(
  FaultCode.missingKey,
  'a new shared field requires $_forDocTypesKey',
  file: field.file,
  key: '$_fieldsKey[${field.index}].$_forDocTypesKey',
);

List<String>? _frozen(List<String>? list) =>
    list == null ? null : List.unmodifiable(list);

/// Throws `unknown_value` for the first `for_doc_types` id of [pack]'s shared
/// entries outside the doc types of [pack] and the packs it reaches.
void _checkPackReach(
  LoadedPack pack,
  List<LoadedPack> ordered,
  Map<String, Set<String>> docTypeIdsByPack,
  Map<String, String?> extendsOf,
) {
  final chain = <String>{
    ...?docTypeIdsByPack[pack.manifest.name],
    for (final other in ordered)
      if (reaches(pack, other, extendsOf: extendsOf))
        ...?docTypeIdsByPack[other.manifest.name],
  };
  final shared = pack.manifest.shared;
  for (final (i, line) in shared.lines.indexed) {
    _requireKnown(
      line.forDocTypes,
      chain,
      file: line.file,
      key: '$_linesKey[$i].$_forDocTypesKey',
      scope: 'the pack chain',
    );
  }
  for (final (i, field) in shared.fields.indexed) {
    _requireKnown(
      field.forDocTypes,
      chain,
      file: field.file,
      key: '$_fieldsKey[$i].$_forDocTypesKey',
      scope: 'the pack chain',
    );
  }
  for (final pattern in shared.patterns) {
    _requireKnown(
      pattern.forDocTypes,
      chain,
      file: pattern.file,
      key: '${pattern.kind.listKey}[${pattern.index}].$_forDocTypesKey',
      scope: 'the pack chain',
    );
  }
}

/// Throws `unknown_value` for the first `shared.yaml` line naming a doc type
/// outside [mergedDocTypeIds].
void _checkProjectReach(
  List<SharedLine> projectLines,
  Set<String> mergedDocTypeIds,
) {
  for (final line in projectLines) {
    _requireKnown(
      line.forDocTypes,
      mergedDocTypeIds,
      file: line.file,
      key: '$_linesKey[${line.index}].$_forDocTypesKey',
      scope: 'the merged set',
    );
  }
}

void _requireKnown(
  List<String>? named,
  Set<String> known, {
  required String file,
  required String key,
  required String scope,
}) {
  for (final id in named ?? const <String>[]) {
    if (known.contains(id)) continue;
    throw TemplateFault(
      FaultCode.unknownValue,
      'for_doc_types names no doc type of $scope: $id',
      file: file,
      key: key,
    );
  }
}

/// The pack and list position of one shared entry's declaration.
final class _Declarer {
  const new(this.pack, this.index);

  final LoadedPack pack;
  final int index;
}

/// Where a shared pattern takes its regex from while layers merge.
sealed class _Source {
  const new();
}

/// A regex a layer wrote in a `pattern` key.
final class _OwnSource extends _Source {
  const new(this.regex);

  final String regex;
}

/// A `pattern_ref` a layer wrote, at its [writer] entry.
final class _RefSource extends _Source {
  const new(this.ref, this.writer);

  /// The id of the shared pattern whose regex the entry takes.
  final String ref;

  /// The entry that wrote the ref, where a fault names it.
  final SharedPattern writer;
}

/// A shared pattern mid-merge, its regex still a ref when a layer wrote one.
final class _PatternDraft {
  const new({
    required this.id,
    required this.kind,
    required this.source,
    required this.message,
    required this.scope,
    required this.except,
    required this.perSubsection,
    required this.forDocTypes,
    required this.sections,
    required this.declaringPack,
  });

  final String id;
  final SharedPatternKind kind;
  final _Source source;
  final String message;
  final PatternScope scope;
  final List<String> except;
  final bool perSubsection;
  final List<String> forDocTypes;
  final List<String>? sections;
  final String declaringPack;
}

/// The running merge of one shared pattern list, its own id space.
final class _PatternList {
  final merged = <String, _PatternDraft>{};
  final disabledIds = <String>{};
  final declarers = <String, List<_Declarer>>{};
}

/// The running merge of shared lines, fields, and patterns, layer by layer.
///
/// The maps keep first-insertion order, so their values are in print order;
/// an entry a layer disables leaves its map, and one added again takes a new
/// place, as sections do.
final class _SharedMerge {
  new(this._extendsOf);

  final Map<String, String?> _extendsOf;
  final _lines = <String, MergedSharedLine>{};
  final _fields = <String, MergedSharedField>{};
  final _disabledLineIds = <String>{};
  final _disabledFieldIds = <String>{};
  final _lineDeclarers = <String, List<_Declarer>>{};
  final _fieldDeclarers = <String, List<_Declarer>>{};
  final _bannedPatterns = _PatternList();
  final _requiredPatterns = _PatternList();
  var _nextPlace = 0;

  /// Merges the lines, the fields, then the patterns of [pack]'s `pack.yaml`.
  void addPack(LoadedPack pack) {
    final shared = pack.manifest.shared;
    for (final line in shared.lines) {
      _claim(_lineDeclarers, pack, line.id, line.index, listKey: _linesKey);
      _mergeLine(line);
    }
    for (final field in shared.fields) {
      _claim(_fieldDeclarers, pack, field.id, field.index, listKey: _fieldsKey);
      _mergeField(field, pack.manifest.name);
    }
    for (final pattern in shared.patterns) {
      _claim(
        _patternsOf(pattern.kind).declarers,
        pack,
        pattern.id,
        pattern.index,
        listKey: pattern.kind.listKey,
      );
      _mergePattern(pattern, pack.manifest.name);
    }
  }

  /// Merges the `shared.yaml` lines on top of every pack.
  void addProjectLines(List<SharedLine> lines) => lines.forEach(_mergeLine);

  /// Returns the merged entries.
  SharedSet build() => SharedSet(
    lines: List.unmodifiable(_lines.values),
    fields: List.unmodifiable(_fields.values),
    patterns: List.unmodifiable([
      ..._resolved(_bannedPatterns),
      ..._resolved(_requiredPatterns),
    ]),
    disabledLineIds: Set.unmodifiable(_disabledLineIds),
  );

  /// Records [pack] as a declarer of [id], or throws `unknown_value` when a
  /// prior declarer and [pack] reach neither way.
  ///
  /// The fault names the entry of the pack whose name sorts later.
  void _claim(
    Map<String, List<_Declarer>> declarers,
    LoadedPack pack,
    String id,
    int index, {
    required String listKey,
  }) {
    final current = _Declarer(pack, index);
    final prior = declarers.putIfAbsent(id, () => []);
    for (final other in prior) {
      final related =
          reaches(pack, other.pack, extendsOf: _extendsOf) ||
          reaches(other.pack, pack, extendsOf: _extendsOf);
      if (related) continue;
      final later =
          compareCodePoints(pack.manifest.name, other.pack.manifest.name) > 0
          ? current
          : other;
      throw TemplateFault(
        FaultCode.unknownValue,
        'shared entry $id is declared by two packs, neither extending the '
        'other',
        file: later.pack.manifest.file,
        key: '$listKey[${later.index}].id',
      );
    }
    prior.add(current);
  }

  void _mergeLine(SharedLine line) {
    final held = _lines[line.id];
    if (held != null) {
      if (line.disabled) {
        _lines.remove(line.id);
        _disabledLineIds.add(line.id);
        return;
      }
      _lines[line.id] = MergedSharedLine(
        id: held.id,
        text: line.text ?? held.text,
        forDocTypes: _frozen(line.forDocTypes) ?? held.forDocTypes,
        printRank: held.printRank,
      );
      return;
    }
    if (line.disabled && _disabledLineIds.contains(line.id)) return;
    final text = line.text;
    if (line.disabled || text == null) {
      throw _notFound(
        kind: 'line',
        id: line.id,
        file: line.file,
        key: '$_linesKey[${line.index}].id',
        disabled: line.disabled,
        missing: 'text',
      );
    }
    _disabledLineIds.remove(line.id);
    _lines[line.id] = MergedSharedLine(
      id: line.id,
      text: text,
      forDocTypes: _frozen(line.forDocTypes),
      printRank: _nextPlace++,
    );
  }

  void _mergeField(SharedField field, String packName) {
    final entry = field.entry;
    final held = _fields[entry.id];
    if (held != null) {
      if (entry.disabled) {
        _fields.remove(entry.id);
        _disabledFieldIds.add(entry.id);
        return;
      }
      final overlaid = _overlay(held.entry, entry);
      _checkOutputRef(overlaid, field);
      _fields[entry.id] = MergedSharedField(
        entry: overlaid,
        forDocTypes: _frozen(field.forDocTypes) ?? held.forDocTypes,
        declaringPack: held.declaringPack,
        order: held.order,
      );
      return;
    }
    if (entry.disabled && _disabledFieldIds.contains(entry.id)) return;
    if (entry.disabled || entry.type == null) {
      throw _notFound(
        kind: 'field',
        id: entry.id,
        file: field.file,
        key: '$_fieldsKey[${field.index}].id',
        disabled: entry.disabled,
        missing: 'type',
      );
    }
    _disabledFieldIds.remove(entry.id);
    _fields[entry.id] = MergedSharedField(
      entry: entry,
      // `_checkNewFieldReach` refused a new field with no `for_doc_types`.
      forDocTypes: List.unmodifiable(field.forDocTypes!),
      declaringPack: packName,
      order: _nextPlace++,
    );
  }

  _PatternList _patternsOf(SharedPatternKind kind) => switch (kind) {
    SharedPatternKind.banned => _bannedPatterns,
    SharedPatternKind.required => _requiredPatterns,
  };

  void _mergePattern(SharedPattern pattern, String packName) {
    final list = _patternsOf(pattern.kind);
    final held = list.merged[pattern.id];
    if (held != null) {
      if (pattern.disabled) {
        list.merged.remove(pattern.id);
        list.disabledIds.add(pattern.id);
        return;
      }
      list.merged[pattern.id] = _overlayPattern(held, pattern);
      return;
    }
    if (pattern.disabled && list.disabledIds.contains(pattern.id)) return;
    final source = _sourceWritten(pattern);
    final message = pattern.message;
    if (pattern.disabled || source == null || message == null) {
      throw _notFound(
        kind: 'pattern',
        id: pattern.id,
        file: pattern.file,
        key: '${pattern.kind.listKey}[${pattern.index}].id',
        disabled: pattern.disabled,
        missing: source == null ? 'pattern' : 'message',
      );
    }
    list.disabledIds.remove(pattern.id);
    list.merged[pattern.id] = _PatternDraft(
      id: pattern.id,
      kind: pattern.kind,
      source: source,
      message: message,
      scope: pattern.scope ?? PatternScope.text,
      except: _frozen(pattern.except) ?? const [],
      perSubsection: pattern.perSubsection ?? false,
      // `_checkNewPatternReach` refused a new pattern writing `sections` or
      // one `for_doc_types` key alone; no reach key makes a source.
      forDocTypes: List.unmodifiable(pattern.forDocTypes ?? const []),
      sections: _frozen(pattern.sections),
      declaringPack: packName,
    );
  }

  /// Returns the regex source [pattern] writes, or null when it writes none.
  _Source? _sourceWritten(SharedPattern pattern) {
    final regex = pattern.pattern;
    if (regex != null) return _OwnSource(regex);
    final ref = pattern.patternRef;
    return ref == null ? null : _RefSource(ref, pattern);
  }

  /// Returns [lower] with each key [upper] writes replacing the same one.
  _PatternDraft _overlayPattern(_PatternDraft lower, SharedPattern upper) =>
      _PatternDraft(
        id: lower.id,
        kind: lower.kind,
        source: _sourceWritten(upper) ?? lower.source,
        message: upper.message ?? lower.message,
        scope: upper.scope ?? lower.scope,
        except: _frozen(upper.except) ?? lower.except,
        perSubsection: upper.perSubsection ?? lower.perSubsection,
        forDocTypes: _frozen(upper.forDocTypes) ?? lower.forDocTypes,
        sections: _frozen(upper.sections) ?? lower.sections,
        declaringPack: lower.declaringPack,
      );

  /// Returns the ids the `pattern_ref` of each merged pattern of [kind] names.
  Set<String> refIds(SharedPatternKind kind) => {
    for (final draft in _patternsOf(kind).merged.values)
      if (draft.source case _RefSource(:final ref)) ref,
  };

  /// Returns the merged patterns of [list] with each `pattern_ref` resolved
  /// to the regex of the entry it names, which resolves first.
  ///
  /// Throws `pattern_ref_invalid` at the `pattern_ref` of an entry that names
  /// no merged entry of [list], or of the first entry of a ref cycle.
  List<MergedSharedPattern> _resolved(_PatternList list) {
    final regexes = <String, String>{};
    return [
      for (final draft in list.merged.values)
        MergedSharedPattern(
          entry: PatternEntry(
            id: draft.id,
            pattern: _regexOf(draft, list, const [], regexes),
            message: draft.message,
            scope: draft.scope,
            except: draft.except,
            perSubsection: draft.perSubsection,
          ),
          kind: draft.kind,
          forDocTypes: draft.forDocTypes,
          sections: draft.sections,
          declaringPack: draft.declaringPack,
        ),
    ];
  }

  /// Returns the regex of [draft], following refs through [list].
  ///
  /// [via] holds the drafts being resolved above [draft]; [regexes] keeps
  /// each resolved regex by id.
  String _regexOf(
    _PatternDraft draft,
    _PatternList list,
    List<_PatternDraft> via,
    Map<String, String> regexes,
  ) {
    final known = regexes[draft.id];
    if (known != null) return known;
    final source = draft.source;
    final regex = switch (source) {
      _OwnSource(:final regex) => regex,
      _RefSource() => _regexOfRef(draft, source, list, via, regexes),
    };
    return regexes[draft.id] = regex;
  }

  /// Returns the regex of the entry [source], written by [draft], names.
  String _regexOfRef(
    _PatternDraft draft,
    _RefSource source,
    _PatternList list,
    List<_PatternDraft> via,
    Map<String, String> regexes,
  ) {
    final target = list.merged[source.ref];
    if (target == null) throw _refNamesNone(source.writer, source.ref);
    final path = [...via, draft];
    if (path.contains(target)) {
      throw _refCycle(path.sublist(path.indexOf(target)), list);
    }
    return _regexOf(target, list, path, regexes);
  }

  TemplateFault _refNamesNone(SharedPattern writer, String ref) => _refInvalid(
    writer,
    'pattern_ref names no shared ${writer.kind.name} '
    'pattern: $ref',
  );

  /// The fault at the `pattern_ref` of the entry of [cycle] that comes first
  /// in [list].
  TemplateFault _refCycle(List<_PatternDraft> cycle, _PatternList list) {
    final order = list.merged.keys.toList();
    final first = cycle.reduce(
      (a, b) => order.indexOf(a.id) <= order.indexOf(b.id) ? a : b,
    );
    final writer = switch (first.source) {
      _RefSource(:final writer) => writer,
      _OwnSource() => throw StateError('an own pattern is no cycle member'),
    };
    return _refInvalid(
      writer,
      'pattern_ref loops back to ${first.id}: '
      '${cycle.map((draft) => draft.id).join(', ')}',
    );
  }

  TemplateFault _refInvalid(SharedPattern writer, String message) =>
      TemplateFault(
        FaultCode.patternRefInvalid,
        message,
        file: writer.file,
        key: '${writer.kind.listKey}[${writer.index}].pattern_ref',
      );

  /// Throws `unknown_value` at [field]'s own entry for a pointer or root the
  /// `output_ref` [merged] cannot read.
  ///
  /// The doc-type format checks only what one entry writes, so a change entry
  /// over a lower `output_ref` field is checked here, keyed by its index.
  void _checkOutputRef(FieldEntry merged, SharedField field) {
    if (merged.type != FieldType.outputRef) return;
    final prefix = '$_fieldsKey[${field.index}].';
    PointerKind.read(merged.pointer, file: field.file, prefix: prefix);
    final root = merged.root;
    if (root == null) return;
    PointerRoot.read(root, file: field.file, prefix: prefix);
  }

  /// Returns [lower] with each property [upper] writes replacing the same one.
  FieldEntry _overlay(FieldEntry lower, FieldEntry upper) => FieldEntry(
    id: lower.id,
    type: upper.type ?? lower.type,
    list: upper.list ?? lower.list,
    required: upper.required ?? lower.required,
    enumValues: upper.enumValues ?? lower.enumValues,
    docTypes: upper.docTypes ?? lower.docTypes,
    pointer: upper.pointer ?? lower.pointer,
    root: upper.root ?? lower.root,
    bundleWith: upper.bundleWith ?? lower.bundleWith,
    description: upper.description ?? lower.description,
    lint: upper.lint == null
        ? lower.lint
        : (lower.lint?.mergedWith(upper.lint!) ?? upper.lint),
    disabled: false,
  );

  /// The fault for an entry that has nothing to disable, or lacks the
  /// [missing] key that would add it.
  TemplateFault _notFound({
    required String kind,
    required String id,
    required String file,
    required String key,
    required bool disabled,
    required String missing,
  }) => TemplateFault(
    FaultCode.overrideIdNotFound,
    disabled
        ? 'no shared $kind "$id" in the merged set to disable'
        : 'no shared $kind "$id" in the merged set and no $missing to add it',
    file: file,
    key: key,
  );
}
