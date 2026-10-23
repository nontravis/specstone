import 'dart:io';

import 'package:specstone_core/src/rendering/browser_host.dart';
import 'package:test/test.dart';

void main() {
  const needsShell = 'needs /bin/sh';
  final skipOnWindows = Platform.isWindows ? needsShell : null;

  group('HostOs.current', () {
    test('matches the running platform', () {
      final expected = Platform.isMacOS
          ? HostOs.macos
          : Platform.isWindows
          ? HostOs.windows
          : HostOs.linux;

      expect(HostOs.current, expected);
    });
  });

  group('BrowserHost.system', () {
    test('reads the process environment and the current OS', () {
      final host = BrowserHost.system();

      expect(host.environment, Platform.environment);
      expect(host.os, HostOs.current);
    });

    group('runProcess', () {
      final host = BrowserHost.system();

      test('returns the exit code of a short-lived process', () async {
        final code = await host.runProcess('/bin/sh', [
          '-c',
          'exit 3',
        ], timeout: const Duration(seconds: 30));

        expect(code, 3);
      }, skip: skipOnWindows);

      test('returns 0 for a process that succeeds and prints', () async {
        final code = await host.runProcess('/bin/sh', [
          '-c',
          'echo out; echo err >&2',
        ], timeout: const Duration(seconds: 30));

        expect(code, 0);
      }, skip: skipOnWindows);

      test('kills a process that outlives the timeout and yields -1', () async {
        final stopwatch = Stopwatch()..start();

        final code = await host.runProcess('/bin/sh', [
          '-c',
          'exec sleep 60',
        ], timeout: const Duration(milliseconds: 300));

        expect(code, -1);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 30)));
      }, skip: skipOnWindows);
    });

    group('isRunnable', () {
      late Directory dir;
      final host = BrowserHost.system();

      setUp(() => dir = Directory.systemTemp.createTempSync('browser_host_'));
      tearDown(() => dir.deleteSync(recursive: true));

      File makeFile(String name, {required bool executable}) {
        final file = File('${dir.path}/$name')
          ..writeAsStringSync('#!/bin/sh\n');
        if (!Platform.isWindows) {
          Process.runSync('chmod', [
            if (executable) '755' else '644',
            file.path,
          ]);
        }
        return file;
      }

      test('is true for an existing executable file', () {
        expect(host.isRunnable(makeFile('run', executable: true).path), isTrue);
      });

      test('is false for a missing path', () {
        expect(host.isRunnable('${dir.path}/missing'), isFalse);
      });

      test('is false for a folder', () {
        expect(host.isRunnable(dir.path), isFalse);
      });

      test('is false for a file without an execute bit', () {
        final file = makeFile('plain', executable: false);

        expect(host.isRunnable(file.path), isFalse);
      }, skip: skipOnWindows);

      test('is true for a file on Windows, which has no execute bit', () {
        final file = makeFile('plain.exe', executable: false);

        expect(host.isRunnable(file.path), isTrue);
      }, skip: Platform.isWindows ? null : 'Windows only');
    });
  });
}
