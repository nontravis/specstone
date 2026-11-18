import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show isFingerprint;
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _folderBelowRoot = '.specstone/approved';
const _copyExtension = '.md';

/// The approved copies kept under `.specstone/approved/`, one file per
/// ApprovalHash, holding the LF text of a doc as it was approved.
///
/// A copy is named by the hash its own `approved:` mark carries, so a doc that
/// moves or is renamed keeps its copy.
final class ApprovedCopyStore {
  const new(this.projectRoot);

  final Directory projectRoot;

  /// Saves [lfApproved], a doc written with its `approved:` mark, under that
  /// mark.
  ///
  /// A text whose mark is not an ApprovalHash saves nothing. A copy that
  /// cannot be saved is skipped, so the view reads git history instead.
  void save(String lfApproved) {
    final hash = _markOf(lfApproved);
    if (hash == null) return;
    try {
      _folder.createSync(recursive: true);
      writeFileAtomic(_fileOf(hash), utf8.encode(lfApproved));
    } on FileSystemException {
      // The approval is already written; the copy only speeds the view up.
    }
  }

  /// Returns the saved copy named by [approvedValue], the `approved:` value a
  /// doc carries on disk, or null when it counts as none.
  ///
  /// A copy counts only when its own mark is [approvedValue] and
  /// [countsAsApprovedCopy] holds for it under [docType], so an edited or
  /// stale file is never read.
  SavedApprovedCopy? find(Object? approvedValue, MergedDocType? docType) {
    if (approvedValue is! String || !isFingerprint(approvedValue)) return null;
    final String text;
    try {
      text = toLf(utf8.decode(_fileOf(approvedValue).readAsBytesSync()));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
    final isNamedCopy = _markOf(text) == approvedValue;
    return isNamedCopy && countsAsApprovedCopy(text, docType)
        ? SavedApprovedCopy(text)
        : null;
  }

  /// Deletes each saved copy whose hash is not in [carried].
  ///
  /// A file that is no copy, or that cannot be deleted, stays.
  void prune(Set<String> carried) {
    final List<FileSystemEntity> entries;
    try {
      entries = _folder.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entry in entries) {
      if (entry is! File) continue;
      final hash = _hashNamed(entry.uri.pathSegments.last);
      if (hash == null || carried.contains(hash)) continue;
      try {
        entry.deleteSync();
      } on FileSystemException {
        // A copy left behind is read only when a doc still carries its hash.
      }
    }
  }

  Directory get _folder => Directory('${projectRoot.path}/$_folderBelowRoot');

  File _fileOf(String hash) => File('${_folder.path}/$hash$_copyExtension');
}

String? _hashNamed(String fileName) {
  if (!fileName.endsWith(_copyExtension)) return null;
  final stem = fileName.substring(0, fileName.length - _copyExtension.length);
  return isFingerprint(stem) ? stem : null;
}

String? _markOf(String lfText) {
  final value = ApprovalFields.of(Doc.parse(lfText)).approvedValue;
  return value is String && isFingerprint(value) ? value : null;
}
