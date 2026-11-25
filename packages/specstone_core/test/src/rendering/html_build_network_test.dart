import 'dart:async';
import 'dart:io';

import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/html_build.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

const _featurePath = 'prds/features/f05_rendering/FEATURE.md';

/// An [HttpOverrides] that counts every client a build asks for.
final class _CountingHttp extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('the build opened an http client');
  }
}

Future<HtmlBuild> _buildWithLink(String link) async {
  final root = await fixtureProject({
    'docs/$_featurePath':
        '# F-05 — Rendering\n\n## Feature name\n\n- **Human:** Rendering\n\n'
        'See [the spec]($link).\n',
  });
  final project = DocsProject.open(
    templates: TemplateResolver(shippedFiles: fixturePackFiles()),
    workingDirectory: root,
    homeDirectory: null,
  );
  return buildHtml(
    project,
    project.resolveTarget(
      null,
      workingDirectory: root,
      defaultsToDocsRoot: true,
    ),
  );
}

void main() {
  test('a web link to a listening server stays a link and gets no '
      'connection', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var connections = 0;
    server.listen((socket) {
      connections++;
      socket.destroy();
    });
    final link = 'http://127.0.0.1:${server.port}/spec';
    final counting = _CountingHttp();

    final build = await HttpOverrides.runZoned(
      () => _buildWithLink(link),
      createHttpClient: counting.createHttpClient,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(build.html, contains('<a href="$link">the spec</a>'));
    expect(connections, 0);
    expect(counting.clients, 0);
  });

  test('a web link with a port that is not digits stays a link and the '
      'build asks for no http client', () async {
    const link = 'http://h:abc/x.md';
    final counting = _CountingHttp();

    final build = await HttpOverrides.runZoned(
      () => _buildWithLink(link),
      createHttpClient: counting.createHttpClient,
    );

    expect(build.html, contains('<a href="$link">the spec</a>'));
    expect(build.warnings, isEmpty);
    expect(counting.clients, 0);
  });
}
