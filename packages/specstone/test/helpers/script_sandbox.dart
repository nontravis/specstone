import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package_root.dart';

/// Returns the code repo root, two levels above the specstone package.
Directory repoRoot() => Directory.fromUri(packageRoot().uri.resolve('../../'));

/// Creates a [ScriptSandbox] under a new temp folder.
///
/// The folder is deleted by `addTearDown`. On POSIX a `uname` stub answers
/// `STUB_UNAME_S` (default `Linux`) for `-s` and `STUB_UNAME_M` (default
/// `x86_64`) for `-m`.
Future<ScriptSandbox> createScriptSandbox() async {
  final root = await Directory.systemTemp.createTemp('specstone_sandbox_');
  addTearDown(() => root.delete(recursive: true));
  final sandbox = ScriptSandbox._(root);
  for (final folder in [
    sandbox.home,
    sandbox.stubs,
    sandbox.archives,
    sandbox.logs,
    sandbox._tmp,
  ]) {
    await folder.create();
  }
  if (!Platform.isWindows) {
    sandbox.stub('uname', r'''
case "$1" in
  -s) echo "${STUB_UNAME_S:-Linux}" ;;
  -m) echo "${STUB_UNAME_M:-x86_64}" ;;
esac''');
  }
  return sandbox;
}

/// A temp home, PATH stubs, fake release archives, and script runs.
final class ScriptSandbox {
  new _(this.root)
    : home = Directory(_under(root, 'home')),
      stubs = Directory(_under(root, 'stubs')),
      archives = Directory(_under(root, 'archives')),
      logs = Directory(_under(root, 'logs')),
      _tmp = Directory(_under(root, 'tmp'));

  static final bool _windows = Platform.isWindows;
  static final String _separator = Platform.pathSeparator;

  static String _under(Directory parent, String name) =>
      '${parent.path}$_separator$name';

  final Directory root;
  final Directory home;
  final Directory stubs;
  final Directory archives;
  final Directory logs;
  final Directory _tmp;

  /// Returns the environment a script runs with, then applies [extra].
  ///
  /// A value of `''` in [extra] removes that key.
  Map<String, String> env([Map<String, String> extra = const {}]) {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final base = _windows
        ? {
            'HOME': home.path,
            'USERPROFILE': home.path,
            'PATH':
                '${stubs.path};$systemRoot\\System32;'
                '$systemRoot\\System32\\WindowsPowerShell\\v1.0',
            'SystemRoot': systemRoot,
            'TEMP': _tmp.path,
            'TMP': _tmp.path,
            'STUB_LOG_DIR': logs.path,
            'PROCESSOR_ARCHITECTURE': 'AMD64',
          }
        : {
            'HOME': home.path,
            'PATH': '${stubs.path}:/usr/bin:/bin:/usr/sbin:/sbin',
            'SHELL': '/bin/zsh',
            'TMPDIR': _tmp.path,
            'STUB_LOG_DIR': logs.path,
          };
    return {...base, ...extra}..removeWhere((_, value) => value.isEmpty);
  }

  /// Writes an executable [name] to the stubs folder that runs [body].
  void stub(String name, String body) {
    if (_windows) {
      File(_under(stubs, '$name.cmd'))
          .writeAsStringSync('@echo off\r\n$body\r\n');
      return;
    }
    final file = File(_under(stubs, name))
      ..writeAsStringSync('#!/bin/sh\n$body\n');
    _chmodExecutable(file);
  }

  /// Returns the lines of the `<name>.log` file in the logs folder.
  List<String> logOf(String name) {
    final file = File(_under(logs, '$name.log'));
    return file.existsSync() ? file.readAsLinesSync() : const [];
  }

  /// Writes the release archive for [target] and a `SHA256SUMS` beside it.
  ///
  /// The archive holds `bin/`, `lib/libfake.so`, `LICENSE`, and
  /// `THIRD_PARTY_NOTICES`; `bin/specstone` prints [version] unless [bundle],
  /// a `dart build cli` output folder, supplies `bin/` and `lib/`.
  /// [damaged] records the hash of other bytes; [withSumsLine] false records
  /// only another asset's line.
  Future<File> writeArchive(
    String target, {
    String version = '0.2.0',
    Directory? bundle,
    bool damaged = false,
    bool withSumsLine = true,
  }) async {
    final zip = target == 'windows-x64';
    final asset = 'specstone-$target.${zip ? 'zip' : 'tar.gz'}';
    final stage = await root.createTemp('stage_');
    await _fillStage(stage, version: version, bundle: bundle);
    final archive = File(_under(archives, asset));
    await _pack(stage, archive, zip: zip);

    final bytes = archive.readAsBytesSync();
    final hashed = damaged ? [...bytes, 0] : bytes;
    final sumsLine = withSumsLine
        ? '${sha256.convert(hashed)}  $asset'
        : '${sha256.convert(utf8.encode('other'))}  specstone-other.tar.gz';
    await File(_under(archives, 'SHA256SUMS')).writeAsString('$sumsLine\n');
    return archive;
  }

  /// Puts an installed binary and a library under `home/.specstone`.
  void installFake({String version = '0.1.0'}) {
    if (_windows) {
      throw UnsupportedError(
        'installFake is POSIX only until the Windows tests',
      );
    }
    final install = _under(home, '.specstone');
    final binary = File('$install/bin/specstone')
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\necho $version\n');
    _chmodExecutable(binary);
    File('$install/lib/libold.so')
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
  }

  /// Returns every file under [home] as a relative `/` path to its content.
  Map<String, String> snapshot() {
    final prefix = home.path.length + 1;
    return {
      for (final file in home.listSync(recursive: true).whereType<File>())
        file.path.substring(prefix).replaceAll(r'\', '/'): latin1.decode(
          file.readAsBytesSync(),
        ),
    };
  }

  /// Runs [script] with `env(extra)` and none of the parent environment.
  ///
  /// [script] is relative to [repoRoot] unless absolute; [args] follow it.
  /// POSIX runs it through [shell]; Windows runs it through PowerShell.
  Future<ProcessResult> run(
    String script, {
    List<String> args = const [],
    Map<String, String> extra = const {},
    String? stdinText,
    String shell = '/bin/sh',
  }) async {
    final path = _isAbsolute(script)
        ? script
        : '${repoRoot().path}$_separator$script';
    final process = await Process.start(
      _windows ? 'powershell' : shell,
      _windows
          ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path, ...args]
          : [path, ...args],
      environment: env(extra),
      includeParentEnvironment: false,
      workingDirectory: root.path,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    if (stdinText != null) process.stdin.write(stdinText);
    // A script that never reads stdin closes the pipe early; that is fine.
    await process.stdin.close().catchError((Object _) {});
    return ProcessResult(
      process.pid,
      await process.exitCode,
      await stdout,
      await stderr,
    );
  }

  static bool _isAbsolute(String path) =>
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

  static void _chmodExecutable(File file) {
    final result = Process.runSync('chmod', ['755', file.path]);
    if (result.exitCode != 0) {
      throw StateError('chmod ${file.path} failed: ${result.stderr}');
    }
  }

  static Future<void> _fillStage(
    Directory stage, {
    required String version,
    required Directory? bundle,
  }) async {
    if (bundle != null) {
      await _copyFolderContents(bundle, stage);
    } else {
      final binary = File(_under(Directory(_under(stage, 'bin')), 'specstone'))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho $version\n');
      File(_under(Directory(_under(stage, 'lib')), 'libfake.so'))
        ..createSync(recursive: true)
        ..writeAsStringSync('fake');
      if (!_windows) _chmodExecutable(binary);
    }
    File(_under(stage, 'LICENSE')).writeAsStringSync('license\n');
    File(_under(stage, 'THIRD_PARTY_NOTICES')).writeAsStringSync('notices\n');
  }

  static Future<void> _copyFolderContents(Directory from, Directory to) async {
    final result = _windows
        ? await Process.run('powershell', [
            '-NoProfile',
            '-Command',
            'Copy-Item -Path "${from.path}\\*" -Destination "${to.path}" -Recurse',
          ])
        : await Process.run('cp', ['-R', '${from.path}/.', to.path]);
    if (result.exitCode != 0) {
      throw StateError('copy of ${from.path} failed: ${result.stderr}');
    }
  }

  static Future<void> _pack(
    Directory stage,
    File archive, {
    required bool zip,
  }) async {
    final result = zip
        ? await Process.run('powershell', [
            '-NoProfile',
            '-Command',
            'Compress-Archive -Path ${stage.path}\\* -DestinationPath ${archive.path}',
          ])
        : await Process.run('tar', [
            '-czf',
            archive.path,
            '-C',
            stage.path,
            for (final entry in stage.listSync())
              entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
          ]);
    if (result.exitCode != 0) {
      throw StateError('packing ${archive.path} failed: ${result.stderr}');
    }
  }
}
