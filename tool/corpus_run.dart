// Diffs the findings of two builds over one pinned docs snapshot.
//
// Usage: dart run tool/corpus_run.dart --project <dir> --ref <commit>
//   --old <binary> --new <binary> --out <file>
//
// <dir> is a git work tree of a Specstone project, <ref> the pinned snapshot,
// each binary a built `specstone`. Each build runs `migrate`, `format`, and
// `check` on its own copy of the snapshot. Exit 0 when the new build adds no
// finding, 1 when it adds one or more, 2 (no out file) when a step breaks.
import 'dart:convert';
import 'dart:io';

const int _addedExit = 1;
const int _brokenExit = 2;
const String _refusedKind = 'format_refused';
final RegExp _planLine = RegExp(r'^plan (\S+)\s*$', multiLine: true);
const List<String> _commitIdentity = [
  '-c',
  'user.name=corpus',
  '-c',
  'user.email=corpus@localhost',
];

/// One finding of a build, keyed as `<kind> <path>:<line>`.
final class _Finding {
  const new({required this.kind, required this.path, required this.line});

  final String kind;
  final String path;
  final int line;

  String get key => '$kind $path:$line';
}

/// A broken run: printed as `corpus_run: <message>` on stderr, exit 2.
final class _Failure implements Exception {
  new(this.message);

  final String message;
}

Future<void> main(List<String> arguments) async {
  try {
    exitCode = await _run(_Options.parse(arguments));
  } on _Failure catch (failure) {
    stderr.writeln('corpus_run: ${failure.message}');
    exitCode = _brokenExit;
  } on FileSystemException catch (error) {
    stderr.writeln('corpus_run: ${error.message}: ${error.path}');
    exitCode = _brokenExit;
  }
}

/// The five required options.
final class _Options {
  const new({
    required this.project,
    required this.ref,
    required this.oldBinary,
    required this.newBinary,
    required this.out,
  });

  factory parse(List<String> arguments) {
    const names = ['project', 'ref', 'old', 'new', 'out'];
    final values = <String, String>{};
    for (var i = 0; i < arguments.length; i += 2) {
      final name = arguments[i].startsWith('--')
          ? arguments[i].substring(2)
          : '';
      if (!names.contains(name) || i + 1 >= arguments.length) {
        throw _Failure('usage: ${_usage()}');
      }
      values[name] = arguments[i + 1];
    }
    if (!names.every(values.containsKey)) throw _Failure('usage: ${_usage()}');
    return _Options(
      project: _absolute(values['project']!),
      ref: values['ref']!,
      oldBinary: _absolute(values['old']!),
      newBinary: _absolute(values['new']!),
      out: _absolute(values['out']!),
    );
  }

  /// Resolves [path] against the working directory once, since every step
  /// runs in a folder of its own.
  static String _absolute(String path) => File(path).absolute.path;

  final String project;
  final String ref;
  final String oldBinary;
  final String newBinary;
  final String out;

  static String _usage() =>
      'dart run tool/corpus_run.dart --project <dir> --ref <commit> '
      '--old <binary> --new <binary> --out <file>';
}

Future<int> _run(_Options options) async {
  final outFile = File(options.out);
  if (outFile.existsSync()) outFile.deleteSync();
  final old = await _sideRun('old', options.oldBinary, options);
  final fresh = await _sideRun('new', options.newBinary, options);
  final header = [
    'old: ${options.oldBinary} ${old.version}',
    'new: ${options.newBinary} ${fresh.version}',
    'ref: ${options.ref}',
  ];
  final diff = _diffOf(old.findings, fresh.findings);
  await outFile.writeAsString('${header.join('\n')}\n$diff');
  return _onlyIn(fresh.findings, old.findings).isEmpty ? 0 : _addedExit;
}

/// What one build reported on its copy of the snapshot.
final class _SideRun {
  const new(this.version, this.findings);

  final String version;
  final List<_Finding> findings;
}

Future<_SideRun> _sideRun(String side, String binary, _Options options) async {
  final tmp = await Directory.systemTemp.createTemp('corpus_run_$side');
  try {
    final work = await _snapshotCopy(side, tmp, options);
    return await _runBuild(side, binary, work);
  } finally {
    await tmp.delete(recursive: true);
  }
}

/// Extracts the snapshot into `<tmp>/<side>` as a repo with one clean commit,
/// so `migrate` meets a clean tree; returns that folder's path.
Future<String> _snapshotCopy(
  String side,
  Directory tmp,
  _Options options,
) async {
  final work = Directory('${tmp.path}/$side')..createSync();
  await _step(side, 'git', [
    '-C',
    options.project,
    'archive',
    '--format=tar',
    '-o',
    '${tmp.path}/snapshot.tar',
    options.ref,
  ], workingDirectory: tmp.path);
  await _step(side, 'tar', [
    '-xf',
    '${tmp.path}/snapshot.tar',
    '-C',
    work.path,
  ], workingDirectory: tmp.path);
  for (final args in [
    ['init', '-q'],
    ['add', '-A'],
    [..._commitIdentity, 'commit', '-q', '-m', 'snapshot'],
  ]) {
    await _step(side, 'git', args, workingDirectory: work.path);
  }
  return work.path;
}

Future<_SideRun> _runBuild(String side, String binary, String work) async {
  final version = await _step(side, binary, [
    '--version',
  ], workingDirectory: work);
  await _migrate(side, binary, work);
  final format = await _step(
    side,
    binary,
    ['format', '--json'],
    workingDirectory: work,
    okExits: const {0, 1},
  );
  final check = await _step(
    side,
    binary,
    ['check', '--json'],
    workingDirectory: work,
    okExits: const {0, 1},
  );
  return _SideRun('${version.stdout}'.trim(), [
    ..._refusedOf(side, '${format.stdout}'),
    ..._findingsOf('${check.stdout}'),
  ]);
}

/// Runs `migrate --dry-run`, then applies the plan its `plan` line names.
Future<void> _migrate(String side, String binary, String work) async {
  final dryRun = await _step(side, binary, [
    'migrate',
    '--dry-run',
  ], workingDirectory: work);
  final hash = _planLine.firstMatch('${dryRun.stdout}')?.group(1);
  if (hash == null) return;
  await _step(side, binary, [
    'migrate',
    '--yes',
    '--plan',
    hash,
  ], workingDirectory: work);
}

/// Runs [executable] in [workingDirectory]; a step ending outside [okExits]
/// is a [_Failure] naming [side], the step, and its `stderr`.
Future<ProcessResult> _step(
  String side,
  String executable,
  List<String> args, {
  required String workingDirectory,
  Set<int> okExits = const {0},
}) async {
  final step = '${executable.split('/').last} ${args.join(' ')}';
  final ProcessResult result;
  try {
    result = await Process.run(
      executable,
      args,
      workingDirectory: workingDirectory,
    );
  } on ProcessException catch (error) {
    throw _Failure('$side: $step did not start: ${error.message}');
  }
  if (okExits.contains(result.exitCode)) return result;
  throw _Failure(
    '$side: $step exited ${result.exitCode}: ${'${result.stderr}'.trim()}',
  );
}

/// Reads the findings of one `check --json` object.
List<_Finding> _findingsOf(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    throw _Failure('check --json printed no JSON: $json');
  }
  if (decoded is! Map || decoded['findings'] is! List) {
    throw _Failure('check --json held no findings list: $json');
  }
  return [
    for (final finding in decoded['findings'] as List)
      _Finding(
        kind: (finding as Map)['kind'] as String,
        path: finding['path'] as String,
        line: finding['line'] as int,
      ),
  ];
}

/// Reads each refused doc of one `format --json` object as a finding.
///
/// A refused doc is drift to read, so `format` exit 1 is data, not a failure.
List<_Finding> _refusedOf(String side, String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    throw _Failure('$side: format --json printed no JSON: $json');
  }
  if (decoded is! Map || decoded['files'] is! List) {
    throw _Failure('$side: format --json held no files list: $json');
  }
  return [
    for (final file in decoded['files'] as List)
      if ((file as Map)['status'] == 'refused')
        _Finding(kind: _refusedKind, path: file['path'] as String, line: 0),
  ];
}

/// Returns the sorted keys [from] holds and [other] does not.
List<String> _onlyIn(List<_Finding> from, List<_Finding> other) {
  final otherKeys = {for (final f in other) f.key};
  return {
    for (final f in from)
      if (!otherKeys.contains(f.key)) f.key,
  }.toList()..sort();
}

/// Returns each key only [fresh] holds as `+ <key>` and each key only [old]
/// holds as `- <key>`, sorted.
String _diffOf(List<_Finding> old, List<_Finding> fresh) => [
  for (final key in _onlyIn(fresh, old)) '+ $key\n',
  for (final key in _onlyIn(old, fresh)) '- $key\n',
].join();
