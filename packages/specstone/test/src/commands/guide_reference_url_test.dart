import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

/// Counts every socket connection and HTTP client the code under test opens.
final class _NetworkWatch extends IOOverrides {
  int opened = 0;

  @override
  Future<Socket> socketConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    opened++;
    return super.socketConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    );
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) {
    opened++;
    return super.socketStartConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
    );
  }
}

final class _HttpWatch extends HttpOverrides {
  int created = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    return super.createHttpClient(context);
  }
}

void main() {
  test('a url entry shows in guide --json and opens no network', () async {
    final project = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      '.specstone/templates/note.yaml':
          'id: note\ndescription: A note.\npath: notes/{slug}.md\n'
          'reference:\n  - title: Soft delete\n    url: https://google.aip.dev/164\n',
    });
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = SpecstoneCommandRunner(
      console: FakeConsole(),
      out: out,
      err: err,
      templates: TemplateResolver(),
      workingDirectory: project,
      homeDirectory: await writeTree({}),
    );
    final sockets = _NetworkWatch();
    final clients = _HttpWatch();

    final status = await HttpOverrides.runWithHttpOverrides(
      () => IOOverrides.runWithIOOverrides(
        () => runner.run(['guide', 'note', '--json']),
        sockets,
      ),
      clients,
    );

    expect(status, 0, reason: '$err');
    expect(out.toString(), contains('https://google.aip.dev/164'));
    expect(sockets.opened, 0);
    expect(clients.created, 0);
  });

  test(
    'the text guide holds no reference entry that guide --json keeps',
    () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.specstone/templates/refs/handbook.md': '# Handbook\n',
        '.specstone/templates/note.yaml':
            'id: note\ndescription: A note.\npath: notes/{slug}.md\n'
            'reference:\n'
            '  - {title: Url entry, url: "https://google.aip.dev/164"}\n'
            '  - {title: File entry, file: refs/handbook.md}\n'
            '  - {title: Doc entry, doc: prd/feature}\n'
            '  - {title: Title only entry}\n'
            '  - {title: Located entry, locator: Appendix C}\n',
      });
      final home = await writeTree({});
      Future<String> guide(List<String> args) async {
        final out = StringBuffer();
        final runner = SpecstoneCommandRunner(
          console: FakeConsole(),
          out: out,
          err: StringBuffer(),
          templates: TemplateResolver(),
          workingDirectory: project,
          homeDirectory: home,
        );
        expect(await runner.run(['guide', 'note', ...args]), 0);
        return out.toString();
      }

      final json = jsonDecode(await guide(['--json'])) as Map<String, Object?>;
      final entries = (json['reference']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final text = await guide([]);

      expect(entries, hasLength(5));
      for (final entry in entries) {
        expect(text, isNot(contains(entry['title'])));
        for (final key in ['url', 'file', 'doc', 'locator']) {
          final value = entry[key];
          if (value != null) expect(text, isNot(contains(value)));
        }
      }
      expect(text, isNot(contains('sources')));
    },
  );

  test('the network watch sees an HTTP request to a local port', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) => request.response.close());
    final sockets = _NetworkWatch();
    final clients = _HttpWatch();

    await HttpOverrides.runWithHttpOverrides(
      () => IOOverrides.runWithIOOverrides(() async {
        final client = HttpClient();
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/'),
        );
        await (await request.close()).drain<void>();
        client.close();
      }, sockets),
      clients,
    );

    expect(sockets.opened, greaterThan(0));
    expect(clients.created, 1);
  });
}
