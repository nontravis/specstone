import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

/// The `Zone` key the active recorders run under, outermost first.
final _recorderKey = Object();

/// Returns the hash a dry run prints on its `plan <hash>` line.
///
/// It is the [baseHashOf] of [planText] followed by [inputs]' lines, so a
/// change to the plan or to an input it used changes it, and a commit that
/// leaves every input as it was does not (`setup_migration` INV-4).
String planHashOf(String planText, PlanInputs inputs) =>
    baseHashOf('$planText${inputs.lines}');

/// Reads the bytes of [file] and records them when a [PlanInputs.collect] runs.
///
/// A path read twice keeps its first hash. A read that throws a
/// [FileSystemException] is recorded as [PlanInputs.firstUnreadable] on every
/// active recorder, then rethrown.
Uint8List readPlanInput(File file) {
  final Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } on FileSystemException {
    for (final recorder in _activeRecorders) {
      recorder._recordUnreadable(file);
    }
    rethrow;
  }
  _activeRecorder?._record(file, bytes);
  return bytes;
}

/// Records whether git tracks [path], a `/`-separated path from the project
/// root, when a [PlanInputs.collect] runs.
///
/// A path answered twice keeps its first answer.
void recordTrackedAnswer(String path, {required bool isTracked}) {
  _activeRecorder?._recordTracked(path, isTracked: isTracked);
}

List<PlanInputs> get _activeRecorders =>
    Zone.current[_recorderKey] as List<PlanInputs>? ?? const [];

PlanInputs? get _activeRecorder => _activeRecorders.lastOrNull;

/// What a plan used: each file it read with the hash of its bytes, and each
/// path it asked git about with the answer.
///
/// The reads sit in layers that non-planner callers share, so a read records
/// through [readPlanInput] into the recorder the running `Zone` holds, with no
/// parameter threaded through those layers. A plan that gained, lost, or
/// changed an input of any kind has different [lines].
final class PlanInputs {
  new(this.projectRoot) : _rootPaths = _rootPathsOf(projectRoot);

  /// The project root; a recorded path under it is kept relative to it.
  final Directory projectRoot;

  final List<String> _rootPaths;
  final _hashes = <String, String>{};
  final _tracked = <String, bool>{};
  String? _firstUnreadable;

  /// Runs [plan] with this recorder active and returns its result.
  ///
  /// A plan that collects for itself while another recorder runs leaves that
  /// recorder active, so it still learns of a read that failed.
  T collect<T>(T Function() plan) => Zone.current
      .fork(
        zoneValues: {
          _recorderKey: [..._activeRecorders, this],
        },
      )
      .run(plan);

  /// The path of the first file a read could not read, from the project root as
  /// a recorded path is, or null when no read failed.
  ///
  /// A failed read adds no line to [lines]; the plan that hit it throws.
  String? get firstUnreadable => _firstUnreadable;

  /// One `<path> <sha256 hex>` line per recorded file in code point order of
  /// path, then one `<path> tracked|untracked` line per path asked of git in
  /// the same order.
  String get lines {
    final buffer = StringBuffer();
    for (final path in _sorted(_hashes.keys)) {
      buffer.write('$path ${_hashes[path]}\n');
    }
    for (final path in _sorted(_tracked.keys)) {
      buffer.write('$path ${_tracked[path]! ? 'tracked' : 'untracked'}\n');
    }
    return buffer.toString();
  }

  /// Returns the path of the first line in code point order that [other] and
  /// this hold differently, or null when their [lines] are equal.
  ///
  /// A path one holds and the other lacks counts as a difference.
  String? firstDifferenceFrom(PlanInputs other) {
    final mine = lines.split('\n').toSet();
    final theirs = other.lines.split('\n').toSet();
    final differing = mine.difference(theirs).union(theirs.difference(mine))
      ..remove('');
    if (differing.isEmpty) return null;
    final first = _sorted(differing).first;
    return first.substring(0, first.lastIndexOf(' '));
  }

  void _record(File file, Uint8List bytes) {
    _hashes.putIfAbsent(_keyOf(file.absolute.path), () {
      return sha256.convert(bytes).toString();
    });
  }

  void _recordUnreadable(File file) {
    _firstUnreadable ??= _keyOf(file.absolute.path);
  }

  void _recordTracked(String path, {required bool isTracked}) {
    _tracked.putIfAbsent(path, () => isTracked);
  }

  /// Returns the `/`-separated path of [absolute] from the project root, or
  /// [absolute] itself when it lies outside.
  String _keyOf(String absolute) {
    for (final root in _rootPaths) {
      if (!absolute.startsWith(root)) continue;
      final relative = absolute.substring(root.length);
      return Platform.isWindows ? relative.replaceAll(r'\', '/') : relative;
    }
    return absolute;
  }
}

List<String> _sorted(Iterable<String> items) =>
    items.toList()..sort(compareCodePoints);

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
