import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show PointerKind;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One code link of a doc whose code the check reads.
typedef _CodeLink = ({int line, String pointer, String path, String? recorded});

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
  final links = [
    ..._entryLinks(context, doc, target),
    ..._coversLinks(context, work, doc, target, type),
  ];
  for (final link in links) {
    final current = _currentFingerprint(context, target, link.path);
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

/// Returns the `implements` entries of a record [doc] whose file is read.
Iterable<_CodeLink> _entryLinks(
  CheckContext context,
  IndexedDoc doc,
  CodeTarget target,
) sync* {
  final read = recordDocOf(context, doc);
  final fieldId = read == null ? null : recordCodeFieldOf(read.type)?.id;
  if (read == null || fieldId == null) return;
  final items = recordItemsOf(read.feature, context.index.childrenOf);
  final codeRoot = context.codeRootOf(target);
  for (final (:value, :line, text: _) in read.lines.entriesOf(fieldId)) {
    if (value is! String) continue;
    final parsed = recordCodeLineOf(value);
    final item = items[parsed?.item];
    if (parsed == null || item == null) continue;
    final entry = CodeLinkEntry(parsed.code);
    final status = context.index.itemStatus(item, codeTarget: doc.target);
    if (!readsEntryCode(codeRoot, status, entry.pointer)) continue;
    yield (
      line: line,
      pointer: entry.pointer,
      path: ImplementsEntry(entry.pointer).path,
      recorded: entry.fingerprint,
    );
  }
}

/// Returns the `covers:` entries of [doc], a prefix field of [type], that
/// the check reads.
Iterable<_CodeLink> _coversLinks(
  CheckContext context,
  ImplementedWork work,
  IndexedDoc doc,
  CodeTarget target,
  MergedDocType type,
) sync* {
  final codeRoot = context.codeRootOf(target);
  final endsWait = work.endsWaitOf(doc, target);
  for (final field in type.fields) {
    if (!isCodeLinkField(field) || field.pointer != PointerKind.prefix) {
      continue;
    }
    for (final (:value, :line, text: _)
        in context.linesOf(doc).entriesOf(field.id)) {
      if (value is! String) continue;
      final entry = CodeLinkEntry(value);
      if (!readsCoversCode(codeRoot, entry.pointer, endsWait: endsWait)) {
        continue;
      }
      yield (
        line: line,
        pointer: entry.pointer,
        path: entry.pointer,
        recorded: entry.fingerprint,
      );
    }
  }
}

/// Returns the current fingerprint of the file or folder at [path], null when
/// a file it reads cannot be read.
///
/// A folder's files are all read, so each unreadable one states its warning.
String? _currentFingerprint(
  CheckContext context,
  CodeTarget target,
  String path,
) {
  final normal = normalCodeEntry(path);
  final isFile =
      FileSystemEntity.typeSync('${context.codeRootOf(target).path}/$normal') ==
      FileSystemEntityType.file;
  if (!isFile) return _folderFingerprint(context, target, path);
  final bytes = context.codeBytesOf(target, normal);
  return bytes == null ? null : fileCodeFingerprint(bytes);
}

String? _folderFingerprint(
  CheckContext context,
  CodeTarget target,
  String path,
) {
  var isReadable = true;
  final files = <({String path, String fingerprint})>[];
  final listed = codeLinkFiles(
    context.projectRoot,
    target,
    path,
    targets: context.targets,
    onUnlistable: (folder) {
      isReadable = false;
      context.warn(
        '$folder: cannot list the folder; files under it are not checked '
        'for covers',
      );
    },
  );
  for (final file in listed) {
    final bytes = context.codeBytesOf(target, file);
    if (bytes == null) {
      isReadable = false;
    } else {
      files.add((path: file, fingerprint: fileCodeFingerprint(bytes)));
    }
  }
  return isReadable ? folderCodeFingerprint(files) : null;
}
