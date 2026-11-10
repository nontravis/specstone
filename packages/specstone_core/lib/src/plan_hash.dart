import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

/// The name `PlanInputs.lines` gives the tracked-file listing.
const _listingName = 'git ls-files';

/// The `Zone` key the active recorder runs under.
final _recorderKey = Object();

/// Returns the hash a dry run prints on its `plan <hash>` line.
///
/// It is the [baseHashOf] of [planText] followed by [inputs]' lines, so a
/// change to the plan or to a file it read changes it, and a commit that
/// leaves every input as it was does not (`setup_migration` INV-4).
String planHashOf(String planText, PlanInputs inputs) =>
    baseHashOf('$planText${inputs.lines}');

/// Reads the bytes of [file] and records them when a [PlanInputs.collect] runs.
///
/// A path read twice keeps its first hash.
Uint8List readPlanInput(File file) {
  final bytes = file.readAsBytesSync();
  _activeRecorder?._record(file, bytes);
  return bytes;
}

/// Records [listing], the output of `git ls-files -z`, when a
/// [PlanInputs.collect] runs.
void recordTrackedListing(String listing) {
  _activeRecorder?._recordListing(listing);
}

PlanInputs? get _activeRecorder => Zone.current[_recorderKey] as PlanInputs?;

/// The files a plan read, each with the hash of its bytes.
///
/// The reads sit in layers that non-planner callers share, so a read records
/// through [readPlanInput] into the recorder the running `Zone` holds, with no
/// parameter threaded through those layers.
final class PlanInputs {
  new(this.projectRoot) : _rootPaths = _rootPathsOf(projectRoot);

  /// The project root; a recorded path under it is kept relative to it.
  final Directory projectRoot;

  final List<String> _rootPaths;
  final _files = <String, ({File file, String hash})>{};
  String? _listingHash;

  /// Runs [plan] with this recorder active and returns its result.
  T collect<T>(T Function() plan) =>
      Zone.current.fork(zoneValues: {_recorderKey: this}).run(plan);

  /// One `<path> <sha256 hex>` line per recorded file in code point order of
  /// path, then a `git ls-files <sha256 hex>` line when a listing was recorded.
  String get lines {
    final buffer = StringBuffer();
    for (final (:path, :hash, file: _) in _sortedEntries) {
      buffer.write('$path $hash\n');
    }
    final listing = _listingHash;
    if (listing != null) buffer.write('$_listingName $listing\n');
    return buffer.toString();
  }

  /// Returns the first recorded path whose bytes now differ or that is gone,
  /// or `git ls-files` when a fresh listing differs, else null.
  ///
  /// [runGit] lists the tracked files again, as the plan did.
  String? firstChangeIn(RunGit runGit) {
    for (final (:path, :hash, :file) in _sortedEntries) {
      if (_hashOf(file) != hash) return path;
    }
    final listing = _listingHash;
    if (listing != null && _listingNow(runGit) != listing) return _listingName;
    return null;
  }

  List<({String path, String hash, File file})> get _sortedEntries => [
    for (final entry
        in _files.entries.toList()
          ..sort((a, b) => compareCodePoints(a.key, b.key)))
      (path: entry.key, hash: entry.value.hash, file: entry.value.file),
  ];

  void _record(File file, Uint8List bytes) {
    _files.putIfAbsent(
      _keyOf(file),
      () => (file: file, hash: sha256.convert(bytes).toString()),
    );
  }

  void _recordListing(String listing) {
    _listingHash ??= sha256.convert(utf8.encode(listing)).toString();
  }

  /// Returns the `/`-separated path of [file] from the project root, or its
  /// absolute path when it lies outside.
  String _keyOf(File file) {
    final absolute = file.absolute.path;
    for (final root in _rootPaths) {
      if (!absolute.startsWith(root)) continue;
      return absolute.substring(root.length).replaceAll(r'\', '/');
    }
    return absolute;
  }

  String? _listingNow(RunGit runGit) {
    try {
      final result = runGit([
        'ls-files',
        '-z',
      ], workingDirectory: projectRoot.path);
      if (result.exitCode != 0) return null;
      return sha256.convert(utf8.encode(result.stdout as String)).toString();
    } on ProcessException {
      return null;
    }
  }
}

/// Returns the hash of the bytes of [file], or null when it cannot be read.
String? _hashOf(File file) {
  try {
    return sha256.convert(file.readAsBytesSync()).toString();
  } on FileSystemException {
    return null;
  }
}

/// Returns [root]'s absolute and canonical paths, each ending in a separator.
List<String> _rootPathsOf(Directory root) {
  final paths = {root.absolute.path};
  try {
    paths.add(root.resolveSymbolicLinksSync());
  } on FileSystemException {
    // A root that is gone keeps its absolute path alone.
  }
  return [
    for (final path in paths)
      if (path.endsWith(Platform.pathSeparator))
        path
      else
        '$path${Platform.pathSeparator}',
  ];
}
