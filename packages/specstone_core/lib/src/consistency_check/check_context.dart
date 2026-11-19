import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/banned_words.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/models/fr_trace_row.dart';
import 'package:specstone_core/src/consistency_check/models/goal_block.dart';
import 'package:specstone_core/src/consistency_check/models/heading_block.dart';
import 'package:specstone_core/src/consistency_check/models/nfr_statement.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/consistency_check/tree_rules.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show generatedLineTest, leadBodyLinesOf, withGeneratedFenced;
import 'package:specstone_core/src/index_query/parents.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/matrix_mode.dart';

/// Why a rule reads a code file, which names what an unreadable file leaves
/// unchecked.
enum CodeRead {
  /// An `implements` Symbol is looked up in the file.
  symbols('implements Symbols in it are not checked'),

  /// A code link's fingerprint is taken from the file.
  codeLink('the code links that reach it are not checked');

  new(this.unchecked);

  /// What goes unchecked when the file cannot be read.
  final String unchecked;
}

/// What every rule of one check run reads: the index, per-doc caches, and the
/// warnings the findings have stated.
final class CheckContext {
  /// Reads [contents], by DocPath, in place of the index's content of those
  /// docs, as a write reads its planned texts.
  new(this._session, {Map<String, DocContent> contents = const {}})
    : _contents = {...contents};

  final ReadSession _session;
  final Map<String, DocContent> _contents;
  final Map<String, DocLines> _lines = {};
  final _codeReads = _CodeReads();
  final Set<String> _codeWarnings = {};
  final Set<String> _stated = {};
  final Map<String, Map<String, String>> _scenarioBlocks = {};
  final Map<String, RegExp> _bannedPatterns = {};
  final Map<String, List<MergedSection?>> _heldTemplates = {};
  final Map<String, bool Function(int)> _generatedLines = {};

  /// The index of the session's snapshot.
  DocIndex get index => _session.index;

  /// The project root folder.
  Directory get projectRoot => _session.project.projectRoot;

  /// The code targets of the project, in config order.
  List<CodeTarget> get targets => _session.project.targets;

  /// Returns the folder [target]'s code paths are written from.
  Directory codeRootOf(CodeTarget target) =>
      _session.project.codeRootOf(target);

  /// Returns the code roots of the other targets that lie inside [target]'s.
  List<String> nestedRootsOf(CodeTarget target) =>
      _session.project.nestedRootsOf(target);

  /// Whether the config pins a pack at or above the approval stamps.
  bool get stampsHaveRun => _session.project.stampsHaveRun;

  /// The Verification matrix mode the config names.
  MatrixMode get matrixMode => _session.project.matrixMode;

  /// The merged doc types of the project.
  MergedSet get set => _session.project.set;

  /// The docs root folder, `<project root>/docs/`.
  Directory get docsRoot => _session.project.docsRoot;

  /// The folder names on the path of any held doc, the docs root's own name
  /// included, built on first use.
  late final Set<String> folderNames = {
    docsRoot.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
    for (final doc in index.docs) ...doc.docPath.split('/').reversed.skip(1),
  };

  /// Returns the content of [doc], read once.
  DocContent contentOf(IndexedDoc doc) =>
      _contents.putIfAbsent(doc.docPath, () => index.contentOf(doc));

  /// Returns the line map of [doc], built on first use.
  DocLines linesOf(IndexedDoc doc) =>
      _lines.putIfAbsent(doc.docPath, () => DocLines.from(contentOf(doc)));

  /// Returns the text of the code file at [path] in [target], read once per
  /// run.
  ///
  /// [path] is relative to [target]'s code root. Malformed UTF-8 bytes decode
  /// to U+FFFD instead of failing. Returns null for a file that cannot be
  /// read, and records its unreadable-file warning.
  String? codeTextOf(CodeTarget target, String path) {
    final bytes = codeBytesOf(target, path, reason: CodeRead.symbols);
    return bytes == null
        ? null
        : const Utf8Decoder(allowMalformed: true).convert(bytes);
  }

  /// Returns the bytes of the code file at [path] in [target], read once per
  /// run, and states the warning of a file that cannot be read.
  ///
  /// [path] is relative to [target]'s code root. Returns null for a file that
  /// cannot be read; its warning is stated once per target and file, naming
  /// what [reason] leaves unchecked, [CodeRead.symbols] when any read of the
  /// file has that reason.
  List<int>? codeBytesOf(
    CodeTarget target,
    String path, {
    required CodeRead reason,
  }) => _bytesOf(target, path, reason);

  /// Returns the bytes of the file at [path] from the project root, read once
  /// per run, and states the warning of a file that cannot be read.
  ///
  /// The read of a `root: project` code link, which belongs to no target:
  /// keyed apart from every target's reads, its warning naming [path] alone.
  List<int>? projectFileBytesOf(String path, {required CodeRead reason}) =>
      _bytesOf(null, path, reason);

  List<int>? _bytesOf(CodeTarget? target, String path, CodeRead reason) {
    final bytes = _readBytes(target, path);
    if (bytes == null) {
      _codeReads.markUnreadable(
        _CodeFile(target: target, path: normalCodeEntry(path)),
        reason,
      );
    }
    return bytes;
  }

  /// Returns the bytes of the code file at [path] in [target], read once per
  /// run, or null when it cannot be read; the caller states its own warning.
  ///
  /// [path] is relative to [target]'s code root; `./a.dart` and `a.dart` are
  /// one file.
  List<int>? readCodeBytes(CodeTarget target, String path) =>
      _readBytes(target, path);

  /// Reads [path] from [target]'s code root, or from the project root when
  /// [target] is null, once per run.
  List<int>? _readBytes(CodeTarget? target, String path) {
    final file = _CodeFile(target: target, path: normalCodeEntry(path));
    return _codeReads.bytesOf(file, () {
      final root = target == null ? projectRoot : codeRootOf(target);
      try {
        return File('${root.path}/${file.path}').readAsBytesSync();
      } on FileSystemException {
        return null;
      }
    });
  }

  /// Adds [warning], which no finding states; a text already added is kept
  /// once, at its first place.
  void warn(String warning) => _codeWarnings.add(warning);

  /// How many code files this run has read.
  int get codeFilesRead => _codeReads.count;

  /// Returns the merged doc type of [doc], or null for an untyped doc.
  MergedDocType? typeOf(IndexedDoc doc) => index.typeOf(doc);

  /// Returns a finding on [doc]; an untyped doc carries no name.
  Finding finding(
    IndexedDoc doc,
    FindingKind kind, {
    required int line,
    required String message,
    WaitsFor? waitsFor,
    Map<String, Object> keys = const {},
  }) => Finding(
    kind: kind,
    path: doc.docPath,
    name: doc.isTyped ? doc.name : null,
    line: line,
    message: message,
    waitsFor: waitsFor,
    keys: keys,
  );

  /// Returns the pattern of the banned [word], built once per run.
  RegExp bannedPatternOf(String word) =>
      _bannedPatterns.putIfAbsent(word, () => bannedWordPattern(word));

  /// Returns the template section the held section [index] of [doc] maps to,
  /// or null.
  ///
  /// Both headers compare by `headerKey`, as the doc formatter matches them.
  MergedSection? templateSectionAt(IndexedDoc doc, int index) =>
      _heldTemplatesOf(doc)[index];

  List<MergedSection?> _heldTemplatesOf(IndexedDoc doc) =>
      _heldTemplates.putIfAbsent(
        doc.docPath,
        () => heldTemplatesOf(contentOf(doc).sections, typeOf(doc)),
      );

  /// Returns the first held section of [doc] that maps to [sectionId].
  IndexedSection? heldSection(IndexedDoc doc, String sectionId) {
    final index = heldIndexOf(doc, sectionId);
    return index == null ? null : contentOf(doc).sections[index];
  }

  /// Returns the index of the first held section of [doc] that maps to
  /// [sectionId], or null.
  int? heldIndexOf(IndexedDoc doc, String sectionId) =>
      heldSectionIndexIn(_heldTemplatesOf(doc), sectionId);

  /// Returns the body lines of the held section at [index] of [doc].
  List<BodyLine> bodyLinesOf(IndexedDoc doc, int index) {
    final content = contentOf(doc);
    return sectionBodyLines(content.sections, content.lineFacts, index);
  }

  /// Returns the items of the held section at [index] of [doc], as the index
  /// reads items: a closed generated block holds none.
  List<SectionItem> itemsIn(IndexedDoc doc, int index) => sectionItemsOf(
    withGeneratedFenced(bodyLinesOf(doc, index), _generatedLineTestOf(doc)),
  );

  /// Returns the items of the lead of [doc], the head after its title line,
  /// as the index reads items: a closed generated block holds none.
  ///
  /// The index stores no ID for a lead item, since the lead has no section.
  List<SectionItem> leadItemsOf(IndexedDoc doc) {
    final text = toLf(contentOf(doc).text);
    return sectionItemsOf(
      leadBodyLinesOf(
        Doc.parse(text),
        text,
        contentOf(doc).lineFacts,
        _generatedLineTestOf(doc),
      ),
    );
  }

  /// Whether file [line] of [doc] is a marker line or inner line of a closed
  /// generated block, the lines no prose rule reads.
  bool isGeneratedLine(IndexedDoc doc, int line) =>
      _generatedLineTestOf(doc)(line);

  bool Function(int line) _generatedLineTestOf(IndexedDoc doc) =>
      _generatedLines.putIfAbsent(doc.docPath, () {
        final text = toLf(contentOf(doc).text);
        return generatedLineTest(
          Doc.parse(text),
          text,
          typeOf(doc)?.listedGenerators.toSet() ?? const {},
        );
      });

  /// Whether [type] declares the field [fieldId].
  ///
  /// A rule that reads a named field runs only when this holds.
  bool typeHoldsField(MergedDocType? type, String fieldId) =>
      type != null && type.fields.any((field) => field.id == fieldId);

  /// Whether the merged doc type [typeId] declares the section [sectionId].
  ///
  /// A rule that reads a named section runs only when this holds.
  bool typeHoldsSection(String typeId, String sectionId) =>
      _session.project.set.docTypes.any(
        (type) =>
            type.id == typeId &&
            type.sections.any((section) => section.id == sectionId),
      );

  /// The first path segment of every doc type `path`, and the records folder
  /// for a records path.
  late final Set<String> checkedFolders = checkedFoldersOf(
    _session.project.set,
  );

  /// Whether [docPath] lies in a checked folder.
  bool isCheckedPath(String docPath) =>
      isInCheckedFolder(checkedFolders, docPath);

  /// Whether [doc] lies in a checked folder.
  bool isChecked(IndexedDoc doc) => isCheckedPath(doc.docPath);

  /// The folders, ending in `/`, of the untyped docs that read the nesting
  /// type's `path` past its `max_depth`.
  late final Set<String> overDeepFolders = {
    for (final doc in index.docs)
      if (depthPastLimitOf(doc) != null) _folderOf(doc.docPath),
  };

  /// Returns how many levels the untyped [doc] nests below a top doc of the
  /// nesting type, when that passes `max_depth`; null otherwise.
  int? depthPastLimitOf(IndexedDoc doc) =>
      doc.isTyped ? null : _session.project.matcher.depthPastLimit(doc.docPath);

  /// Whether [doc] lies in the folder of an over-deep doc other than itself.
  bool isUnderOverDeep(IndexedDoc doc) {
    final own = depthPastLimitOf(doc) == null ? null : _folderOf(doc.docPath);
    return overDeepFolders.any(
      (folder) => folder != own && doc.docPath.startsWith(folder),
    );
  }

  static String _folderOf(String docPath) =>
      docPath.substring(0, docPath.lastIndexOf('/') + 1);

  /// Whether [doc] takes a parent doc ([parentTypeOf]) and has none.
  bool hasNoParent(IndexedDoc doc) =>
      parentTypeOf(doc, _session.project.set) != null && doc.parentPath == null;

  /// Whether the merged set holds a gnfr doc type.
  bool get hasGnfr =>
      _session.project.set.docTypes.any((type) => type.id == _gnfrType);

  /// Returns the `### Scenario <N>` blocks of [story], keyed `S<N>`.
  ///
  /// Reads the `acceptance_criteria` section. A block runs from its heading
  /// line to the next [opensHeadingItem] line outside fenced code, or the
  /// section end. The first block of a repeated number wins.
  Map<String, String> scenarioBlocksOf(IndexedDoc story) =>
      _scenarioBlocks.putIfAbsent(story.docPath, () {
        final index = heldIndexOf(story, acceptanceSectionId);
        if (index == null) return const {};
        return scenarioBlocksIn(bodyLinesOf(story, index));
      });

  /// Whether the merged set holds a project doc type.
  bool get hasProject =>
      _session.project.set.docTypes.any((type) => type.id == _projectType);

  /// Whether the merged set holds a measurement doc type.
  bool get hasMeasurement =>
      _session.project.set.docTypes.any((type) => type.id == _measurementType);

  late final Set<String> _roleNames = {
    for (final doc in _projectDocs)
      if (heldIndexOf(doc, _rolesSection) case final index?)
        for (final line in bodyLinesOf(doc, index))
          if (!line.fenced)
            if (_roleEntry.firstMatch(line.text) case final entry?)
              entry.group(1)!,
  };

  /// Returns the Role names of every project doc.
  ///
  /// A name is the text in backticks that opens a `roles` section entry.
  Set<String> roleNames() => _roleNames;

  late final Set<String> _projectHeadingIds = {
    for (final doc in _projectDocs)
      for (final HeadingBlock(:key) in _itemHeadingBlocksOf(doc))
        if (key.startsWith(_visionIdPrefix)) key,
  };

  /// Returns the ID of each `### PV-` vision heading of every project doc, as
  /// [_itemHeadingBlocksOf] reads it.
  Set<String> projectHeadingIds() => _projectHeadingIds;

  /// Whether the merged set holds a goal doc type.
  bool get hasGoal =>
      _session.project.set.docTypes.any((type) => type.id == _goalType);

  late final List<GoalBlock> _goalBlocks = [
    for (final doc in index.docs)
      if (doc.docTypeId == _goalType)
        for (final (i, template) in _heldTemplatesOf(doc).indexed)
          if (_goalHorizons[template?.id] case final horizon?)
            for (final HeadingBlock(:key, :lines) in headingBlocksOf(
              bodyLinesOf(doc, i),
              goalKeyOf,
            ))
              GoalBlock(
                docPath: doc.docPath,
                key: key,
                horizon: horizon,
                lines: lines,
              ),
  ];

  /// Returns the goal blocks of every goal doc, in doc order.
  ///
  /// A block is a `### PG-` heading of the `long_term`, `mid_term`, or
  /// `short_term` section, keyed by the ID the grammar reads there; a lettered
  /// or unreadable ID keys no block, and a heading of any other section holds
  /// no goal. A block's horizon is its section's: 3, 2, or 1.
  List<GoalBlock> goalBlocks() => _goalBlocks;

  late final Set<String> _goalIds = {
    for (final block in _goalBlocks) block.key,
  };

  /// Returns the ID of each goal block of every goal doc.
  Set<String> goalIds() => _goalIds;

  /// Returns the `###` blocks of each held section of [doc], keyed by the ID
  /// the grammar reads at the heading; a lettered or unreadable ID keys no
  /// block.
  ///
  /// A section reads its `prefix_id`. A gnfr section with none reads the
  /// letters and hyphens before the heading's first digit as the prefix; any
  /// other doc skips a section with none.
  Iterable<HeadingBlock> _itemHeadingBlocksOf(IndexedDoc doc) sync* {
    final isGnfr = doc.docTypeId == _gnfrType;
    for (final (i, template) in _heldTemplatesOf(doc).indexed) {
      if (template == null) continue;
      final prefix = template.prefixId;
      if (prefix == null && !isGnfr) continue;
      yield* headingBlocksOf(
        bodyLinesOf(doc, i),
        (heading) => itemHeadingKeyOf(heading, prefix),
      );
    }
  }

  Iterable<IndexedDoc> get _projectDocs =>
      index.docs.where((doc) => doc.docTypeId == _projectType);

  /// Maps each NFR id of the gnfr docs to its DocPath and Statement line.
  ///
  /// The text is empty when the block has no `- **Statement:**` line.
  late final Map<String, NfrStatement> _nfrStatements = _readNfrStatements();

  /// Returns the NFR ids of the gnfr docs with their Statement lines.
  Map<String, NfrStatement> nfrStatements() => _nfrStatements;

  Map<String, NfrStatement> _readNfrStatements() {
    final statements = <String, NfrStatement>{};
    for (final doc in index.docs) {
      if (doc.docTypeId != _gnfrType) continue;
      for (final HeadingBlock(:key, :lines) in _itemHeadingBlocksOf(doc)) {
        statements.putIfAbsent(
          key,
          () => NfrStatement(path: doc.docPath, text: nfrStatementOf(lines)),
        );
      }
    }
    return statements;
  }

  /// Whether the merged set holds an `architecture` doc type.
  bool get hasArchitecture =>
      _session.project.set.docTypes.any((type) => type.id == _architectureType);

  late final Map<String, IndexedDoc> _frsByName = {
    for (final doc in index.docs)
      if (doc.docTypeId == _frType) doc.name: doc,
  };

  /// Returns the doc of type `fr` named [name], or null.
  IndexedDoc? frNamed(String name) => _frsByName[name];

  final Map<String, List<FrTraceRow>> _frTraceRows = {};

  /// Returns the FR cell and file line of each row of the `fr_trace` table
  /// of [api].
  ///
  /// A cell is the row's first cell, trimmed, with one pair of backticks
  /// dropped. The header row and the separator row are skipped.
  List<FrTraceRow> frTraceRowsOf(IndexedDoc api) =>
      _frTraceRows.putIfAbsent(api.docPath, () => _readFrTraceRows(api));

  List<FrTraceRow> _readFrTraceRows(IndexedDoc api) {
    final held = contentOf(api).sections;
    final type = typeOf(api);
    if (type == null) return const [];
    final rows = <FrTraceRow>[];
    for (var i = 0; i < held.length; i++) {
      if (templateSectionAt(api, i)?.id != _frTraceSection) continue;
      rows.addAll(readFrTraceRows(bodyLinesOf(api, i)));
    }
    return rows;
  }

  /// Every warning of the session, in session order.
  List<String> get sessionWarnings => _session.warnings;

  /// Marks [warning] as printed by a finding.
  void state(String warning) => _stated.add(warning);

  /// The session's warnings that no finding stated, in session order.
  ///
  /// A file read through its target and through the project root, when the
  /// code root is the project root, warns once.
  List<String> get unstatedWarnings => [
    for (final warning in _session.warnings)
      if (!_stated.contains(warning)) warning,
    ...{
      for (final MapEntry(key: _CodeFile(:target, :path), value: reason)
          in _codeReads.unreadable)
        _unreadableWarning(target, path, reason),
    },
    ..._codeWarnings,
  ];

  String _unreadableWarning(CodeTarget? target, String path, CodeRead reason) {
    final prefix = target != null && targets.length > 1
        ? '${target.name}: '
        : '';
    return '$prefix$path: cannot read the file; ${reason.unchecked}';
  }
}

const _gnfrType = 'gnfr';
const _projectType = 'project';
const _goalType = 'goal';
const _visionIdPrefix = 'PV-';
const _measurementType = 'measurement';
const _rolesSection = 'roles';
final _roleEntry = RegExp('^- `([^`]+)` — ');
const _architectureType = 'architecture';
const _frType = 'fr';
const _frTraceSection = 'fr_trace';

/// The horizon of each goal doc section that holds goals.
const _goalHorizons = {'long_term': 3, 'mid_term': 2, 'short_term': 1};

/// A code file one run reads: its target, null for a read from the project
/// root, and its path in `normalCodeEntry`'s form.
final class _CodeFile {
  const new({required this.target, required this.path});

  final CodeTarget? target;
  final String path;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is _CodeFile && other.target == target && other.path == path;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(target, path);
}

/// The code files one run has read, each once, and the reason each unreadable
/// one leaves code unchecked.
final class _CodeReads {
  final _bytes = <_CodeFile, List<int>?>{};
  final _unreadable = <_CodeFile, CodeRead>{};

  /// How many distinct code files this run has read.
  int get count => _bytes.length;

  /// Returns the bytes of [file], calling [read] once and caching its result,
  /// null included.
  List<int>? bytesOf(_CodeFile file, List<int>? Function() read) {
    if (_bytes.containsKey(file)) return _bytes[file];
    return _bytes[file] = read();
  }

  /// Records that [file] is unreadable for [reason]; a [CodeRead.symbols]
  /// reason is never replaced.
  void markUnreadable(_CodeFile file, CodeRead reason) {
    if (_unreadable[file] != CodeRead.symbols) _unreadable[file] = reason;
  }

  /// The unreadable files with their reasons, in the order first marked.
  Iterable<MapEntry<_CodeFile, CodeRead>> get unreadable => _unreadable.entries;
}
