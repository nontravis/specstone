import 'dart:io';

import 'package:specstone_core/src/portable_path.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

const _separator = '/';
const _parentSegment = '..';
const _dotSegment = '.';

/// The first code unit that can compose with the one before it; every unit
/// below it is already in NFC and leaves a name unchanged.
const _firstComposingUnit = 0x300;

/// What one code path entry names from a base folder.
enum CodePathKind {
  /// The entry holds a `\` or a name Windows trims, so it names no one place.
  notPortable,

  /// The entry holds a `..` segment, which it never resolves.
  parentSegment,

  /// The entry names the base itself: no segment is left once `.` and empty
  /// ones drop.
  empty,

  /// No disk name equals a segment, in letter case or not.
  missing,

  /// Each segment equals a disk name in Unicode NFC, a letter case difference
  /// apart in at least one.
  wrongCase,

  /// The entry names a regular file, each segment exactly.
  file,

  /// The entry names a folder, each segment exactly.
  folder,
}

/// The answer of [ExactCasePaths.resolve] for one entry.
final class CodePathVerdict {
  const new({required this.kind, this.diskPath});

  final CodePathKind kind;

  /// The `/`-joined path as the disk spells it; set for [CodePathKind.wrongCase],
  /// [CodePathKind.file], and [CodePathKind.folder].
  final String? diskPath;

  /// Whether the entry names a file or a folder exactly.
  bool get exists => kind == CodePathKind.file || kind == CodePathKind.folder;
}

/// Resolves code paths by exact letter case and Unicode NFC, on every platform.
///
/// `FileSystemEntity.typeSync` resolves `TOOL/build.dart` to `Tool/build.dart`
/// on a case-insensitive disk, and reads an NFC name as missing when the disk
/// holds the NFD one. This walks each segment against the folder's listing, so
/// the one answer holds on every disk. It reads each folder's listing once per
/// instance.
final class ExactCasePaths {
  new();

  final Map<String, _Listing?> _listings = {};

  /// Returns what [entry] names from [base]; [entry] is as written, with no
  /// fingerprint and no `:` tail.
  ///
  /// A segment equal to a disk name after NFC is matched, and the walk goes on
  /// by the disk's spelling. A final link is followed. A folder that cannot be
  /// listed, such as one searchable but not readable, cannot show a spelling
  /// difference, so the disk answers for its segment.
  CodePathVerdict resolve(Directory base, String entry) {
    final written = writtenVerdictOf(entry);
    if (written != null) return written;
    final segments = _segmentsOf(entry);
    var current = base.path;
    var isExact = true;
    final spelled = <String>[];
    for (final segment in segments) {
      final listing = _listingOf(current);
      final String name;
      if (listing == null) {
        name = segment;
        if (FileSystemEntity.typeSync('$current$_separator$name') ==
            FileSystemEntityType.notFound) {
          return const CodePathVerdict(kind: CodePathKind.missing);
        }
      } else if (listing.exact[_nfc(segment)] case final disk?) {
        name = disk;
      } else if (listing.folded[_folded(segment)] case final disk?) {
        name = disk;
        isExact = false;
      } else {
        return const CodePathVerdict(kind: CodePathKind.missing);
      }
      spelled.add(name);
      current = [current, name].join(_separator);
    }
    final diskPath = spelled.join(_separator);
    return switch (FileSystemEntity.typeSync(current)) {
      FileSystemEntityType.file when isExact => CodePathVerdict(
        kind: CodePathKind.file,
        diskPath: diskPath,
      ),
      FileSystemEntityType.directory when isExact => CodePathVerdict(
        kind: CodePathKind.folder,
        diskPath: diskPath,
      ),
      FileSystemEntityType.file || FileSystemEntityType.directory =>
        CodePathVerdict(kind: CodePathKind.wrongCase, diskPath: diskPath),
      _ => const CodePathVerdict(kind: CodePathKind.missing),
    };
  }

  /// Returns the verdict [entry] gives by how it is written alone, with no disk
  /// read: [CodePathKind.notPortable], [CodePathKind.parentSegment], or
  /// [CodePathKind.empty]; null when the disk decides.
  static CodePathVerdict? writtenVerdictOf(String entry) {
    if (!isPortablePath(entry)) {
      return const CodePathVerdict(kind: CodePathKind.notPortable);
    }
    if (entry.split(_separator).contains(_parentSegment)) {
      return const CodePathVerdict(kind: CodePathKind.parentSegment);
    }
    return _segmentsOf(entry).isEmpty
        ? const CodePathVerdict(kind: CodePathKind.empty)
        : null;
  }

  static List<String> _segmentsOf(String entry) => [
    for (final s in entry.split(_separator))
      if (s.isNotEmpty && s != _dotSegment) s,
  ];

  _Listing? _listingOf(String folder) => _listings.putIfAbsent(folder, () {
    try {
      return _Listing([
        for (final entity in Directory(folder).listSync(followLinks: false))
          _nameOf(entity.path),
      ]);
    } on FileSystemException {
      return null;
    }
  });

  static String _nameOf(String path) {
    final slash = path.lastIndexOf(_separator);
    final backslash = Platform.isWindows ? path.lastIndexOf(r'\') : -1;
    final cut = slash > backslash ? slash : backslash;
    return path.substring(cut + 1);
  }
}

/// The names of one folder, keyed by NFC and by NFC with letter case folded;
/// the first name wins a key.
final class _Listing {
  new(List<String> names) {
    for (final name in names) {
      exact.putIfAbsent(_nfc(name), () => name);
      folded.putIfAbsent(_folded(name), () => name);
    }
  }

  final Map<String, String> exact = {};
  final Map<String, String> folded = {};
}

String _nfc(String text) =>
    text.codeUnits.every((unit) => unit < _firstComposingUnit)
    ? text
    : unorm.nfc(text);

String _folded(String text) => _nfc(text).toLowerCase();
