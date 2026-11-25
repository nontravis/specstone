import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show baseHashOf, isFingerprint;
import 'package:specstone_core/src/document_writing/journal_bounds.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

const _folderBelowRoot = '.specstone/audited';
const _copyExtension = '.md';
const _docExtension = '.md';
const _ignoreFileName = '.gitignore';
const _ignoreEverything = '*\n';

/// The audited copies kept under `.specstone/audited/<DocPath>/`, one file per
/// `base` hash, holding the LF text of a draft as a dry run listed it.
///
/// The folder is apart from the approved copy store, whose prune reads
/// `approved:` marks. It ignores itself in git, so no shared ignore list
/// changes.
final class AuditedCopyStore {
  const new(this.projectRoot);

  final Directory projectRoot;

  /// Saves [lfText], the text of the draft at [docPath], under its base hash.
  ///
  /// A copy that cannot be saved is skipped, so the later compare reads the
  /// draft as wholly changed.
  void save(String docPath, String lfText) {
    final folder = _folderOf(docPath);
    if (folder == null) return;
    final file = File('${folder.path}/${baseHashOf(lfText)}$_copyExtension');
    try {
      _requireWritable(file);
      folder.createSync(recursive: true);
      _ensureSelfIgnore();
      writeFileAtomic(file, utf8.encode(lfText));
    } on FileSystemException {
      // A dry run changes no doc; a missing copy only costs a re-read.
    } on RenderFault {
      // A path that leads outside the project is never written.
    }
  }

  /// Returns the LF text saved for [docPath] at [baseHash], or null when none
  /// is saved or the file does not hash to [baseHash].
  String? find(String docPath, String baseHash) {
    final folder = _folderOf(docPath);
    if (folder == null || !isFingerprint(baseHash)) return null;
    final String text;
    try {
      final file = File('${folder.path}/$baseHash$_copyExtension');
      text = toLf(utf8.decode(file.readAsBytesSync()));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
    return baseHashOf(text) == baseHash ? text : null;
  }

  /// Deletes every copy of each doc for which [stillAwaitsApproval] is false.
  ///
  /// A file that is no copy, or that cannot be deleted, stays.
  void prune(bool Function(String docPath) stillAwaitsApproval) {
    for (final _DocFolder(:docPath, :folder) in _docFolders(_root, '')) {
      if (!stillAwaitsApproval(docPath)) _deleteCopiesIn(folder);
    }
  }

  Directory get _root => Directory('${projectRoot.path}/$_folderBelowRoot');

  Directory? _folderOf(String docPath) {
    final segments = docPath.split('/');
    final isSafe =
        docPath.endsWith(_docExtension) &&
        segments.every((s) => s.isNotEmpty && s != '.' && s != '..');
    return isSafe ? Directory('${_root.path}/$docPath') : null;
  }

  void _requireWritable(File file) =>
      requireWritableTarget(file.path, projectRoot: projectRoot);

  void _ensureSelfIgnore() {
    final ignore = File('${_root.path}/$_ignoreFileName');
    if (ignore.existsSync()) return;
    _requireWritable(ignore);
    writeFileAtomic(ignore, utf8.encode(_ignoreEverything));
  }

  void _deleteCopiesIn(Directory folder) {
    try {
      for (final entry in folder.listSync(followLinks: false)) {
        if (entry is File && _isCopyName(entry.uri.pathSegments.last)) {
          entry.deleteSync();
        }
      }
      _deleteEmptyUp(folder);
    } on FileSystemException {
      // A copy left behind is read only for a draft that waits again.
    }
  }

  void _deleteEmptyUp(Directory folder) {
    var current = folder;
    while (current.path != _root.path && current.path.startsWith(_root.path)) {
      try {
        current.deleteSync();
      } on FileSystemException {
        return;
      }
      current = current.parent;
    }
  }
}

/// A folder holding the copies of one doc, and that doc's DocPath.
final class _DocFolder {
  const new(this.docPath, this.folder);

  final String docPath;
  final Directory folder;
}

/// Lists the folders below [folder] named as a doc, with their DocPaths.
List<_DocFolder> _docFolders(Directory folder, String docPath) {
  final List<FileSystemEntity> entries;
  try {
    entries = folder.listSync(followLinks: false);
  } on FileSystemException {
    return const [];
  }
  return [
    for (final entry in entries.whereType<Directory>())
      ..._docFoldersOf(entry, docPath),
  ];
}

List<_DocFolder> _docFoldersOf(Directory entry, String parentDocPath) {
  final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
  final docPath = parentDocPath.isEmpty ? name : '$parentDocPath/$name';
  return name.endsWith(_docExtension)
      ? [_DocFolder(docPath, entry)]
      : _docFolders(entry, docPath);
}

bool _isCopyName(String fileName) {
  if (!fileName.endsWith(_copyExtension)) return false;
  final stem = fileName.substring(0, fileName.length - _copyExtension.length);
  return isFingerprint(stem);
}
