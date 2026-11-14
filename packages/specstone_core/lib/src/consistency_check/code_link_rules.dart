import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/index_query/status_tree.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show PointerKind, RecordStatus;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Types

/// One code link of a doc whose code the check reads: its field id, its line,
/// the entry as written, and, for a record entry, the story or FR it names
/// (relative to its feature) with that item's status in the record's target,
/// both null for a `covers:` entry.
typedef CodeLink = ({
  String field,
  int line,
  String value,
  String? item,
  RecordStatus? status,
  String pointer,
  String path,
  String? recorded,
});

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
  final target = work.targetOf(doc);
  final type = context.typeOf(doc);
  if (target == null || type == null) return;
  final links = codeLinksOf(
    context.index.statusTree,
    work,
    doc,
    type: type,
    target: target,
    codeRoot: context.codeRootOf(target),
    linesOf: () => context.linesOf(doc),
  );
  for (final link in links) {
    final current = currentCodeFingerprint(
      link.path,
      codeRoot: context.codeRootOf(target),
      nestedRoots: context.nestedRootsOf(target),
      bytesOf: (file) => context.codeBytesOf(target, file),
      onUnlistable: (folder) => context.warn(
        '$folder: cannot list the folder; files under it are not checked for '
        'covers or fingerprints',
      ),
    );
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

/// Returns the state of a link that records [recorded] over code that now
/// fingerprints as [current].
_CodeLinkState _stateOf(String? recorded, String current) => switch (recorded) {
  null => const _Unconfirmed(),
  _ when recorded == current => const _Clean(),
  _ => _Suspect(recorded),
};

// MARK: - Link selection

/// Returns the code links of [doc], of [type] in [target], whose code the
/// check reads: a record's `implements` entries and every `covers:` entry.
///
/// The one selection `check` and the migrate stamp both read. [codeRoot] is
/// [target]'s code root; [linesOf] gives [doc]'s lines, read only when [doc]
/// holds a code-link field.
Iterable<CodeLink> codeLinksOf(
  StatusTree tree,
  ImplementedWork work,
  IndexedDoc doc, {
  required MergedDocType type,
  required CodeTarget target,
  required Directory codeRoot,
  required DocLines Function() linesOf,
}) sync* {
  yield* _entryLinks(tree, doc, codeRoot, linesOf);
  yield* _coversLinks(work, doc, target, type, codeRoot, linesOf);
}

/// Returns the `implements` entries of a record [doc] whose file is read.
Iterable<CodeLink> _entryLinks(
  StatusTree tree,
  IndexedDoc doc,
  Directory codeRoot,
  DocLines Function() linesOf,
) sync* {
  final read = recordDocIn(tree, doc, linesOf);
  final fieldId = read == null ? null : recordCodeFieldOf(read.type)?.id;
  if (read == null || fieldId == null) return;
  final items = recordItemsOf(read.feature, tree.childrenOf);
  for (final (:value, :line, text: _) in read.lines.entriesOf(fieldId)) {
    if (value is! String) continue;
    final parsed = recordCodeLineOf(value);
    final item = items[parsed?.item];
    if (parsed == null || item == null) continue;
    final entry = CodeLinkEntry(parsed.code);
    final status = tree.itemStatus(item, codeTarget: doc.target);
    if (!readsEntryCode(codeRoot, status, entry.pointer)) continue;
    yield (
      field: fieldId,
      line: line,
      value: value,
      item: parsed.item,
      status: status,
      pointer: entry.pointer,
      path: ImplementsEntry(entry.pointer).path,
      recorded: entry.fingerprint,
    );
  }
}

/// Returns the `covers:` entries of [doc], a prefix field of [type], that
/// the check reads.
Iterable<CodeLink> _coversLinks(
  ImplementedWork work,
  IndexedDoc doc,
  CodeTarget target,
  MergedDocType type,
  Directory codeRoot,
  DocLines Function() linesOf,
) sync* {
  final fields = [
    for (final field in type.fields)
      if (isCodeLinkField(field) && field.pointer == PointerKind.prefix) field,
  ];
  if (fields.isEmpty) return;
  final endsWait = work.endsWaitOf(doc, target);
  final lines = linesOf();
  for (final field in fields) {
    for (final (:value, :line, text: _) in lines.entriesOf(field.id)) {
      if (value is! String) continue;
      final entry = CodeLinkEntry(value);
      if (!readsCoversCode(codeRoot, entry.pointer, endsWait: endsWait)) {
        continue;
      }
      yield (
        field: field.id,
        line: line,
        value: value,
        item: null,
        status: null,
        pointer: entry.pointer,
        path: entry.pointer,
        recorded: entry.fingerprint,
      );
    }
  }
}

// MARK: - Fingerprint

/// Returns the current fingerprint of the file or folder at [path], null when
/// a file it reads cannot be read or a folder cannot be listed.
///
/// The one read `check` and the migrate stamp both hash by.
/// - [codeRoot]: the code root of the target [path] belongs to.
/// - [nestedRoots]: the code roots of the other targets nested in it, which
///   stay out.
/// - [bytesOf]: the bytes of a file from [codeRoot], null when unreadable.
/// - [onUnlistable]: told each folder that cannot be listed.
String? currentCodeFingerprint(
  String path, {
  required Directory codeRoot,
  required List<String> nestedRoots,
  required List<int>? Function(String file) bytesOf,
  required void Function(String folder) onUnlistable,
}) {
  final normal = normalCodeEntry(path);
  final isFile =
      FileSystemEntity.typeSync('${codeRoot.path}/$normal') ==
      FileSystemEntityType.file;
  if (isFile) {
    final bytes = bytesOf(normal);
    return bytes == null ? null : fileCodeFingerprint(bytes);
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
  final files = <({String path, String fingerprint})>[];
  for (final file in listed) {
    final bytes = bytesOf(file);
    if (bytes == null) {
      isReadable = false;
    } else {
      files.add((path: file, fingerprint: fileCodeFingerprint(bytes)));
    }
  }
  return isReadable ? folderCodeFingerprint(files) : null;
}
