import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/models/file_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show isEmptyCodeEntry, normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/index_query/status_tree.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

// MARK: - Types

/// One code link of a doc whose code the check reads.
final class CodeLink {
  const new({
    required this.field,
    required this.line,
    required this.value,
    required this.pointer,
    required this.path,
    required this.recorded,
    required this.root,
    required this.target,
    this.item,
    this.status,
  });

  /// The id of the field that holds the entry.
  final String field;

  /// The file line of the entry.
  final int line;

  /// The entry as written.
  final String value;

  /// The entry without its fingerprint.
  final String pointer;

  /// The file or folder the entry names, from [root].
  final String path;

  /// The fingerprint the entry ends in; null when it records none.
  final String? recorded;

  /// The folder [path] is read from: the code root of [target], or the
  /// project root for a `root: project` entry.
  final Directory root;

  /// The code target whose code the link reads; null for a `root: project`
  /// entry, which belongs to no target.
  final CodeTarget? target;

  /// The story or FR a record entry names, relative to its feature; null for
  /// a `covers:` entry.
  final String? item;

  /// That item's status in the record's target; null for a `covers:` entry.
  final RecordStatus? status;
}

/// What a code link's code reads as against its recorded fingerprint.
sealed class _CodeLinkState {
  const new();
}

final class _Clean extends _CodeLinkState {
  const new();
}

final class _Suspect extends _CodeLinkState {
  const new(this.recorded);

  final String recorded;
}

final class _Unconfirmed extends _CodeLinkState {
  const new();
}

// MARK: - Rule

/// Returns the `code_suspect` and `code_unconfirmed` findings of the code
/// links of [doc].
///
/// A link takes one state per run: `code_suspect` when its code changed since
/// its fingerprint was recorded, `code_unconfirmed` when it records none.
///
/// A record's `implements` entries and every `covers:` entry are read. A
/// state comes from the code and the entry alone, whatever the doc's draft
/// mark. A link whose code the check does not read, or cannot read, takes no
/// state.
Iterable<Finding> checkCodeLinks(
  CheckContext context,
  ImplementedWork work,
  IndexedDoc doc,
) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final links = codeLinksOf(
    context.index.statusTree,
    work,
    doc,
    type: type,
    projectRoot: context.projectRoot,
    codeRootOf: context.codeRootOf,
    linesOf: () => context.linesOf(doc),
  );
  for (final link in links) {
    final current = _currentOf(context, link);
    if (current == null) continue;
    final finding = switch (_stateOf(link.recorded, current)) {
      _Unconfirmed() => context.finding(
        doc,
        FindingKind.codeUnconfirmed,
        line: link.line,
        message: '${link.path} records no fingerprint',
        keys: {
          'entry': link.pointer,
          'path': link.path,
          'fingerprint': current,
        },
      ),
      _Suspect(:final recorded) => context.finding(
        doc,
        FindingKind.codeSuspect,
        line: link.line,
        message:
            '${link.path} changed since its fingerprint $recorded was recorded',
        keys: {
          'entry': link.pointer,
          'path': link.path,
          'recorded': recorded,
          'fingerprint': current,
        },
      ),
      _Clean() => null,
    };
    if (finding != null) yield finding;
  }
}

/// Returns the current fingerprint of [link]'s code, read from its root
/// through the run's shared reads; null when it cannot be read.
///
/// A `root: project` folder leaves out no nested root, since it belongs to no
/// target.
String? _currentOf(CheckContext context, CodeLink link) {
  final reason = link.item == null ? CodeRead.codeLink : CodeRead.symbols;
  final target = link.target;
  return currentCodeFingerprint(
    link.path,
    codeRoot: link.root,
    nestedRoots: target == null ? const [] : context.nestedRootsOf(target),
    bytesOf: (file) => target == null
        ? context.projectFileBytesOf(file, reason: reason)
        : context.codeBytesOf(target, file, reason: reason),
    onUnlistable: (folder) => context.warn(
      '$folder: cannot list the folder; files under it are not checked for '
      'covers or fingerprints',
    ),
  );
}

/// Returns the state of a link that records [recorded] over code that now
/// fingerprints as [current].
_CodeLinkState _stateOf(String? recorded, String current) => switch (recorded) {
  null => const _Unconfirmed(),
  _ when recorded == current => const _Clean(),
  _ => _Suspect(recorded),
};

// MARK: - Link selection

/// Returns the code links of [doc], of [type], whose code the check reads: a
/// record's `implements` entries and every `covers:` entry.
///
/// The one selection `check` and the migrate stamp both read. An entry of a
/// `root: project` field is read from [projectRoot] whatever [doc]'s target;
/// any other link only when [work] gives [doc] a target, from the folder
/// [codeRootOf] gives it. [linesOf] gives [doc]'s lines, read only when [doc]
/// holds a code-link field.
Iterable<CodeLink> codeLinksOf(
  StatusTree tree,
  ImplementedWork work,
  IndexedDoc doc, {
  required MergedDocType type,
  required Directory projectRoot,
  required Directory Function(CodeTarget target) codeRootOf,
  required DocLines Function() linesOf,
}) sync* {
  final target = work.targetOf(doc);
  if (target != null) {
    yield* _entryLinks(tree, doc, target, codeRootOf(target), linesOf);
  }
  final fields = coversFieldsOf(type);
  if (fields.isEmpty) return;
  final lines = linesOf();
  for (final field in fields) {
    if (readsFromProjectRoot(field)) {
      yield* _coversLinks(field, lines, projectRoot, null, endsWait: true);
    } else if (target != null) {
      yield* _coversLinks(
        field,
        lines,
        codeRootOf(target),
        target,
        endsWait: work.endsWaitOf(doc, target),
      );
    }
  }
}

/// Returns the `implements` entries of a record [doc] whose file is read.
Iterable<CodeLink> _entryLinks(
  StatusTree tree,
  IndexedDoc doc,
  CodeTarget target,
  Directory codeRoot,
  DocLines Function() linesOf,
) sync* {
  final read = recordDocIn(tree, doc, linesOf);
  final fieldId = read == null ? null : recordCodeFieldOf(read.type)?.id;
  if (read == null || fieldId == null) return;
  final items = recordItemsOf(read.feature, tree.childrenOf);
  for (final YamlEntry(:value, :line) in read.lines.entriesOf(fieldId)) {
    if (value is! String) continue;
    final parsed = recordCodeLineOf(value);
    final item = items[parsed?.item];
    if (parsed == null || item == null) continue;
    final entry = CodeLinkEntry(parsed.code);
    final status = tree.itemStatus(item, codeTarget: doc.target);
    if (!readsEntryCode(codeRoot, status, entry.pointer)) continue;
    yield CodeLink(
      field: fieldId,
      line: line,
      value: value,
      item: parsed.item,
      status: status,
      pointer: entry.pointer,
      path: ImplementsEntry(entry.pointer).path,
      recorded: entry.fingerprint,
      root: codeRoot,
      target: target,
    );
  }
}

/// Returns the entries of the `covers`-like [field] that the check reads
/// from [root], [target]'s code root or the project root when null.
///
/// An empty entry is no code link, so it takes no state: neither
/// `code_unconfirmed` nor `code_suspect` reads it.
Iterable<CodeLink> _coversLinks(
  MergedField field,
  DocLines lines,
  Directory root,
  CodeTarget? target, {
  required bool endsWait,
}) sync* {
  for (final YamlEntry(:value, :line) in lines.entriesOf(field.id)) {
    if (value is! String) continue;
    final entry = CodeLinkEntry(value);
    if (isEmptyCodeEntry(entry.pointer)) continue;
    if (!readsCoversCode(root, entry.pointer, endsWait: endsWait)) continue;
    yield CodeLink(
      field: field.id,
      line: line,
      value: value,
      pointer: entry.pointer,
      path: entry.pointer,
      recorded: entry.fingerprint,
      root: root,
      target: target,
    );
  }
}

// MARK: - Fingerprint

/// Returns the current fingerprint of the file or folder at [path], null when
/// a file it reads cannot be read or a folder cannot be listed.
///
/// The one read `check` and the migrate stamp both hash by.
/// - [codeRoot]: the folder [path] is read from, the code root of the target
///   it belongs to or the project root for a `root: project` entry.
/// - [nestedRoots]: the code roots of the other targets nested in it, which
///   stay out; none for the project root.
/// - [bytesOf]: the bytes of a file from [codeRoot], null when unreadable.
/// - [onUnlistable]: told each folder that cannot be listed.
/// - [fileHash]: the fingerprint of a file's bytes and its path from
///   [codeRoot]; the current rule when null.
String? currentCodeFingerprint(
  String path, {
  required Directory codeRoot,
  required List<String> nestedRoots,
  required List<int>? Function(String file) bytesOf,
  required void Function(String folder) onUnlistable,
  String Function(List<int> bytes, String path)? fileHash,
}) {
  final hashOf = fileHash ?? _currentFileHash;
  final normal = normalCodeEntry(path);
  final isFile =
      FileSystemEntity.typeSync('${codeRoot.path}/$normal') ==
      FileSystemEntityType.file;
  if (isFile) {
    final bytes = bytesOf(normal);
    return bytes == null ? null : hashOf(bytes, normal);
  }
  var isReadable = true;
  final listed = codeLinkFiles(
    codeRoot,
    path,
    nestedRoots: nestedRoots,
    onUnlistable: (folder) {
      isReadable = false;
      onUnlistable(folder);
    },
  );
  final files = <FileFingerprint>[];
  for (final file in listed) {
    final bytes = bytesOf(file);
    if (bytes == null) {
      isReadable = false;
    } else {
      files.add(FileFingerprint(path: file, fingerprint: hashOf(bytes, file)));
    }
  }
  return isReadable ? folderCodeFingerprint(files) : null;
}

String _currentFileHash(List<int> bytes, String path) =>
    fileCodeFingerprint(bytes, path: path);
