@Tags(['browser'])
@Timeout(Duration(seconds: 180))
library;

import 'dart:convert';

import 'package:specstone_core/src/rendering/browser_host.dart';
import 'package:specstone_core/src/rendering/browser_locator.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/html_build.dart';
import 'package:specstone_core/src/rendering/pdf_printer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

const _featureDir = 'docs/prds/features/f05_rendering';
const _feature =
    '# F-05 — Rendering\n\n## Feature name\n- **Human:** Rendering\n\n'
    '## Feature goal\n- **why:** share docs\n';
const _story =
    '# Story one\n\n## Summary\nFormat docs.\n\n'
    '```mermaid\ngraph TD; A-->B\n```\n\n'
    '## Acceptance Criteria\nDone.\n';

final _count = RegExp(r'/Count (\d+)');

void main() {
  test('f05/us03/s1: a built feature folder prints to a pdf with the toc page '
      'and one page per doc', () async {
    final host = BrowserHost.system();
    final String browser;
    try {
      browser = locateBrowser(host);
    } on RenderFault catch (fault) {
      if (fault.code != RenderFaultCode.browserNotFound) rethrow;
      markTestSkipped('no Chrome, Edge, or Chromium on this machine');
      return;
    }
    final root = await fixtureProject({
      '$_featureDir/FEATURE.md': _feature,
      '$_featureDir/us01_a/USER_STORY.md': _story,
    });
    final project = DocsProject.open(
      templates: TemplateResolver(shippedFiles: fixturePackFiles()),
      workingDirectory: root,
      homeDirectory: null,
    );
    final html = buildHtml(
      project,
      project.resolveTarget(
        _featureDir,
        workingDirectory: root,
        defaultsToDocsRoot: true,
      ),
    ).html;

    final bytes = await printPdf(html, browser: browser, host: host);

    final text = latin1.decode(bytes);
    expect(text, startsWith('%PDF-'));
    final largest = _count
        .allMatches(text)
        .map((match) => int.parse(match.group(1)!))
        .fold<int>(0, (a, b) => a > b ? a : b);
    printOnFailure('page count: $largest');
    // ignore: avoid_print, a live-browser run reports the page count it printed.
    print('browser=$browser pages=$largest');
    expect(largest, greaterThanOrEqualTo(3));
  });
}
