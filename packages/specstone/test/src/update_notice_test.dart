import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/output_guard.dart';
import 'package:specstone/src/update_notice.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/shipped_pins.dart';
import '../helpers/temp_tree.dart';
import '../helpers/write_runner.dart';

const _running = '1.2.0';
const _newest = '1.3.0';
const _line =
    'specstone $_newest is out (this is $_running); run specstone upgrade';
final _now = DateTime.utc(2026, 11, 15, 10);
const _day = Duration(hours: 24);
final String _anHourAgo = _now
    .subtract(const Duration(hours: 1))
    .toIso8601String();

/// The OS error a write meets once the pipe's reader has gone.
final _readerGone = Platform.isWindows
    ? const OSError('The pipe is being closed.', 232)
    : const OSError('Broken pipe', 32);

/// A stand-in for the release site: counts the requests it gets and answers
/// each with [status] and [body], once [gate] opens when it is set.
final class _Site {
  new _(this.server) {
    server.listen(_answer);
  }

  static Future<_Site> open() async {
    final site = _Site._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(() async {
      if (!(site.gate?.isCompleted ?? true)) site.gate!.complete();
      await site.server.close(force: true);
    });
    return site;
  }

  final HttpServer server;
  final requests = <HttpRequest>[];
  final headers = <Map<String, List<String>>>[];

  int status = 200;
  String body = '{"tag_name":"v$_newest"}';
  Completer<void>? gate;
  void Function()? onRequest;

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/releases/latest');

  Future<void> _answer(HttpRequest request) async {
    requests.add(request);
    final seen = <String, List<String>>{};
    request.headers.forEach((name, values) => seen[name] = values);
    headers.add(seen);
    onRequest?.call();
    try {
      await gate?.future;
      request.response
        ..statusCode = status
        ..write(body);
      await request.response.close();
    } on Object {
      // The client left; nothing to answer.
    }
  }
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

File _record(Directory home) =>
    File('${home.path}/.specstone/update-check.json');

Map<String, Object?> _read(Directory home) =>
    jsonDecode(_record(home).readAsStringSync()) as Map<String, Object?>;

String _recordText(DateTime checkedAt, String? latest) =>
    jsonEncode({'checkedAt': checkedAt.toIso8601String(), 'latest': latest});

Future<Directory> _home({String? record}) => writeTree({
  '.specstone/bin/specstone': '',
  '.specstone/lib/.keep': '',
  '.specstone/update-check.json': ?record,
});

UpdateNotice _notice(
  Directory? home,
  _Site site, {
  Map<String, String> environment = const {},
  bool stdoutTerminal = true,
  bool stderrTerminal = true,
  String? executable,
  DateTime? now,
  String running = _running,
}) => UpdateNotice(
  console: FakeConsole(
    stdoutIsTerminal: stdoutTerminal,
    stderrIsTerminal: stderrTerminal,
  ),
  environment: environment,
  home: home,
  executable: executable ?? '${home?.path}/.specstone/bin/specstone',
  latestReleaseUrl: site.url,
  runningVersion: running,
  clock: () => now ?? _now,
);

void main() {
  group(
    'a no row of the Check conditions sends nothing and writes no record',
    () {
      final oldKept = _recordText(_now.subtract(_day * 2), _newest);

      Future<void> expectQuiet(
        UpdateNotice notice,
        _Site site,
        Directory home, {
        List<String> command = const ['folder'],
        String? before,
      }) async {
        notice.start(command);
        await _settle();
        expect(site.requests, isEmpty);
        expect(
          _record(home).existsSync() ? _record(home).readAsStringSync() : null,
          before,
        );
        expect(notice.lineAfter(), isNull);
      }

      for (final MapEntry(:key, :value) in {
        'SPECSTONE_NO_UPDATE_NOTIFIER non-empty': {
          'SPECSTONE_NO_UPDATE_NOTIFIER': '1',
        },
        'CI non-empty': {'CI': 'true'},
      }.entries) {
        test(key, () async {
          final home = await _home(record: oldKept);
          final site = await _Site.open();

          await expectQuiet(
            _notice(home, site, environment: value),
            site,
            home,
            before: oldKept,
          );
        });
      }

      test('stdout not a terminal', () async {
        final home = await _home(record: oldKept);
        final site = await _Site.open();

        await expectQuiet(
          _notice(home, site, stdoutTerminal: false),
          site,
          home,
          before: oldKept,
        );
      });

      test('stderr not a terminal', () async {
        final home = await _home(record: oldKept);
        final site = await _Site.open();

        await expectQuiet(
          _notice(home, site, stderrTerminal: false),
          site,
          home,
          before: oldKept,
        );
      });

      test('a binary outside the managed folder', () async {
        final home = await _home(record: oldKept);
        final elsewhere = await writeTree({'bin/specstone': ''});
        final site = await _Site.open();

        await expectQuiet(
          _notice(home, site, executable: '${elsewhere.path}/bin/specstone'),
          site,
          home,
          before: oldKept,
        );
      });

      test('no home folder', () async {
        final site = await _Site.open();
        final notice = _notice(
          null,
          site,
          executable: '/elsewhere/bin/specstone',
        )..start(const ['folder']);
        await _settle();

        expect(site.requests, isEmpty);
        expect(notice.lineAfter(), isNull);
      });

      test('a local build, build.txt in the binary lib folder', () async {
        final home = await _home(record: oldKept);
        File('${home.path}/.specstone/lib/build.txt')
            .writeAsStringSync('ref: x\n');
        final site = await _Site.open();

        await expectQuiet(_notice(home, site), site, home, before: oldKept);
      });

      for (final command in [
        ['upgrade'],
        ['mcp'],
        ['hook', 'post-edit'],
      ]) {
        test(command.join(' '), () async {
          final home = await _home(record: oldKept);
          final site = await _Site.open();

          await expectQuiet(
            _notice(home, site),
            site,
            home,
            command: command,
            before: oldKept,
          );
        });
      }

      test(
        'a record from less than 24 hours ago, kept latest or not',
        () async {
          final fresh = _recordText(
            _now.subtract(_day - const Duration(minutes: 1)),
            _newest,
          );
          final home = await _home(record: fresh);
          final site = await _Site.open();

          await expectQuiet(_notice(home, site), site, home, before: fresh);
        },
      );
    },
  );

  group('a yes run', () {
    test('writes the record before the request goes out, then the Version '
        'read with the same checkedAt', () async {
      final home = await _home(
        record: _recordText(_now.subtract(_day * 2), '1.1.0'),
      );
      final site = await _Site.open();
      Map<String, Object?>? atRequest;
      site.onRequest = () => atRequest = _read(home);
      final notice = _notice(home, site)..start(const ['folder']);
      await _until(() => _read(home)['latest'] == _newest);

      expect(atRequest, {
        'checkedAt': _now.toIso8601String(),
        'latest': '1.1.0',
      });
      expect(_read(home), {
        'checkedAt': _now.toIso8601String(),
        'latest': _newest,
      });
      expect(notice.lineAfter(), _line);
    });

    test(
      'a record from exactly 24 hours ago, or dated ahead, checks',
      () async {
        for (final at in [
          _now.subtract(_day),
          _now.add(const Duration(hours: 1)),
        ]) {
          final home = await _home(record: _recordText(at, null));
          final site = await _Site.open();

          _notice(home, site).start(const ['folder']);
          await _until(() => site.requests.isNotEmpty);
        }
      },
    );

    test('an empty switch value turns nothing off', () async {
      final home = await _home();
      final site = await _Site.open();

      _notice(
        home,
        site,
        environment: {'SPECSTONE_NO_UPDATE_NOTIFIER': '', 'CI': ''},
      ).start(const ['guide']);
      await _until(() => site.requests.isNotEmpty);
    });

    for (final bad in [
      'not json',
      '[]',
      '{}',
      '{"checkedAt":"$_anHourAgo"}',
      '{"latest":null}',
      '{"checkedAt":5,"latest":null}',
      '{"checkedAt":"yesterday","latest":null}',
      '{"checkedAt":"$_anHourAgo","latest":3}',
      '{"checkedAt":"$_anHourAgo","latest":"banana"}',
    ]) {
      test('the bad record $bad counts as none', () async {
        final home = await _home(record: bad);
        final site = await _Site.open();
        site.status = 500;
        final notice = _notice(home, site)..start(const ['folder']);
        await _until(() => site.requests.isNotEmpty);

        expect(_read(home), {
          'checkedAt': _now.toIso8601String(),
          'latest': null,
        });
        expect(notice.lineAfter(), isNull);
      });
    }

    test('a record that is a folder fails the start write: no request, no '
        'notice', () async {
      final home = await _home();
      Directory('${home.path}/.specstone/update-check.json').createSync();
      final site = await _Site.open();
      final notice = _notice(home, site)..start(const ['folder']);
      await _settle();

      expect(site.requests, isEmpty);
      expect(notice.lineAfter(), isNull);
    });

    test('a request that sends no project data and no identifier', () async {
      final home = await _home();
      final project = await writeTree({'.specstone/config.yaml': ''});
      final site = await _Site.open();

      await IOOverrides.runZoned(() async {
        _notice(home, site).start(const ['folder']);
        await _until(() => site.requests.isNotEmpty);
      }, getCurrentDirectory: () => project);

      expect(site.requests.single.method, 'GET');
      expect(site.requests.single.uri.toString(), '/releases/latest');
      expect(
        site.headers.single.keys.toSet().difference({
          'host',
          'user-agent',
          'accept-encoding',
        }),
        isEmpty,
      );
      for (final values in site.headers.single.values.expand((v) => v)) {
        expect(values, isNot(contains(project.path)));
        expect(values, isNot(contains(home.path)));
      }
    });
  });

  group('the notice line', () {
    Future<UpdateNotice> started({
      String? kept = _newest,
      String running = _running,
      void Function(_Site site)? setUpSite,
      bool waitForEnd = false,
    }) async {
      final home = await _home(
        record: _recordText(_now.subtract(_day * 2), kept),
      );
      final site = await _Site.open();
      setUpSite?.call(site);
      final notice = _notice(home, site, running: running)
        ..start(const ['folder']);
      await _until(() => site.requests.isNotEmpty);
      if (waitForEnd) await _until(() => _read(home)['latest'] != kept);
      return notice;
    }

    test('a Version read above the running one prints the notice', () async {
      final notice = await started(kept: null, waitForEnd: true);

      expect(notice.lineAfter(), _line);
    });

    test('E04: the running Version equals the latest, no notice', () async {
      final notice = await started(
        kept: null,
        running: _newest,
        waitForEnd: true,
      );

      expect(notice.lineAfter(), isNull);
    });

    test(
      'E03: a pre-release above the latest full release, no notice',
      () async {
        final notice = await started(
          kept: null,
          running: '1.3.0-beta.1',
          setUpSite: (site) => site.body = '{"tag_name":"v1.2.0"}',
          waitForEnd: true,
        );

        expect(notice.lineAfter(), isNull);
      },
    );

    test('E08: a Version read not above the running one wins over a kept '
        'latest that is above it', () async {
      final notice = await started(
        setUpSite: (site) => site.body = '{"tag_name":"v$_running"}',
        waitForEnd: true,
      );

      expect(notice.lineAfter(), isNull);
    });

    for (final failure in [
      (name: 'an HTTP 500', apply: (_Site s) => s.status = 500),
      (name: 'a redirect', apply: (_Site s) => s.status = 302),
      (name: 'a body that is not JSON', apply: (_Site s) => s.body = 'nope'),
      (
        name: 'a body with no tag_name',
        apply: (_Site s) => s.body = '{"name":"x"}',
      ),
      (
        name: 'a tag_name that is no Version',
        apply: (_Site s) => s.body = '{"tag_name":"latest"}',
      ),
    ]) {
      test(
        'a failed request, ${failure.name}, keeps the kept latest and writes '
        'no end write',
        () async {
          final home = await _home(
            record: _recordText(_now.subtract(_day * 2), _newest),
          );
          final site = await _Site.open();
          failure.apply(site);
          final notice = _notice(home, site, running: _running)
            ..start(const ['folder']);
          await _until(() => site.requests.isNotEmpty);
          await _settle();

          expect(_read(home), {
            'checkedAt': _now.toIso8601String(),
            'latest': _newest,
          });
          expect(notice.lineAfter(), _line);
        },
      );
    }

    test('a failed request with no kept latest prints nothing', () async {
      final notice = await started(
        kept: null,
        setUpSite: (site) => site.status = 500,
      );
      await _settle();

      expect(notice.lineAfter(), isNull);
    });

    test('a request still running is abandoned: the kept latest decides, the '
        'record keeps the start write, and the connection closes', () async {
      final home = await _home(
        record: _recordText(_now.subtract(_day * 2), _newest),
      );
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(silent.close);
      final closed = Completer<void>();
      silent.listen((socket) {
        socket.listen(null, onDone: closed.complete, onError: (Object _) {});
      });
      final notice = UpdateNotice(
        console: FakeConsole(stdoutIsTerminal: true, stderrIsTerminal: true),
        environment: const {},
        home: home,
        executable: '${home.path}/.specstone/bin/specstone',
        latestReleaseUrl: Uri.parse('http://127.0.0.1:${silent.port}/'),
        runningVersion: _running,
        clock: () => _now,
      )..start(const ['folder']);
      await _settle();

      expect(notice.lineAfter(), _line);
      await closed.future.timeout(const Duration(seconds: 10));
      expect(_read(home), {
        'checkedAt': _now.toIso8601String(),
        'latest': _newest,
      });
    });

    test(
      'an answer after the notice was decided writes nothing more',
      () async {
        final home = await _home(
          record: _recordText(_now.subtract(_day * 2), _newest),
        );
        final site = await _Site.open()
          ..gate = Completer<void>()
          ..body = '{"tag_name":"v9.0.0"}';
        final notice = _notice(home, site)..start(const ['folder']);
        await _until(() => site.requests.isNotEmpty);
        expect(notice.lineAfter(), _line);
        site.gate!.complete();
        await _settle();

        expect(_read(home)['latest'], _newest);
      },
    );

    test('a start that did not run has no notice', () async {
      final site = await _Site.open();
      final home = await _home();

      expect(_notice(home, site).lineAfter(), isNull);
    });
  });

  group('in the runner', () {
    late Directory home;
    late Directory project;
    late _Site site;

    setUp(() async {
      home = await _home(record: _recordText(_now.subtract(_day * 2), _newest));
      project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
      });
      site = await _Site.open();
    });

    SpecstoneCommandRunner runner(
      StringBuffer out,
      StringBuffer err, {
      Map<String, String> environment = const {},
      Future<void> Function(String line)? courtesy,
    }) => SpecstoneCommandRunner(
      out: out,
      err: err,
      templates: TemplateResolver(),
      workingDirectory: project,
      homeDirectory: home,
      console: FakeConsole(stdoutIsTerminal: true, stderrIsTerminal: true),
      environment: environment,
      updateNotice: _notice(home, site, environment: environment),
      courtesy: courtesy,
    );

    Future<({int status, String out, String err})> run(
      List<String> args, {
      Map<String, String> environment = const {},
      Future<void> Function(String line)? courtesy,
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final status = await runner(
        out,
        err,
        environment: environment,
        courtesy: courtesy,
      ).run(args);
      return (status: status, out: '$out', err: '$err');
    }

    const off = {'SPECSTONE_NO_UPDATE_NOTIFIER': '1'};

    test('prints the notice after the output, stdout and status the same as '
        'with the switch on', () async {
      final quiet = await run(['folder'], environment: off);
      final noisy = await run(['folder']);

      expect(quiet.err, isEmpty);
      expect(noisy.err, '$_line\n');
      expect(noisy.out, quiet.out);
      expect(noisy.status, quiet.status);
    });

    test('a failing command keeps its own status and stderr, then the '
        'line', () async {
      final quiet = await run(['get', 'nope'], environment: off);
      final noisy = await run(['get', 'nope']);

      expect(quiet.status, isNonZero);
      expect(noisy.status, quiet.status);
      expect(noisy.out, quiet.out);
      expect(noisy.err, '${quiet.err}$_line\n');
    });

    test('a command that ends before the site answers is not waited for and '
        'prints the kept latest', () async {
      site.gate = Completer<void>();

      final result = await run(['folder']).timeout(const Duration(seconds: 20));

      expect(result.err, '$_line\n');
      expect(result.status, 0);
    });

    test('a stderr reader that left before the line keeps the status and '
        'stdout', () async {
      final quiet = await run(['folder'], environment: off);
      final errSink = IOSink(_Consumer(_readerGone));
      final courtesy = CourtesyWrites(errSink);
      final out = StringBuffer();

      final status = await guardOutput(
        () => runner(
          out,
          StringBuffer(),
          courtesy: courtesy.writeln,
        ).run(['folder']),
        out: IOSink(_Consumer()),
        err: errSink,
        courtesy: courtesy,
      );

      expect(status, quiet.status);
      expect('$out', quiet.out);
    });

    test('a courtesy write that throws keeps the status and stdout', () async {
      final quiet = await run(['folder'], environment: off);

      final noisy = await run([
        'folder',
      ], courtesy: (_) async => throw const FileSystemException('closed'));

      expect(noisy.status, quiet.status);
      expect(noisy.out, quiet.out);
    });
  });
}

/// A stdio stand-in that fails its first write with [failure].
final class _Consumer implements StreamConsumer<List<int>> {
  new([this.failure]);

  final OSError? failure;
  final _received = BytesBuilder();

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    final added = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = stream.listen((data) {
      final failure = this.failure;
      if (failure == null) {
        _received.add(data);
        return;
      }
      unawaited(subscription.cancel());
      added.completeError(FileSystemException('writeFrom failed', '', failure));
    }, onDone: added.complete);
    return added.future;
  }

  @override
  Future<void> close() async {}
}
