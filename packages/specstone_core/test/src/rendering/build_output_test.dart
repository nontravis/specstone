import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/rendering/build_output.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

const _featureDir = 'docs/prds/features/f05_rendering';
const _feature = '# F-05\n\n## Feature name\n- **Human:** Rendering\n';

Future<(DocsProject, Directory)> _open(Map<String, String> files) async {
  final root = await fixtureProject(files);
  final project = DocsProject.open(
    templates: TemplateResolver(shippedFiles: fixturePackFiles()),
    workingDirectory: root,
    homeDirectory: null,
  );
  return (project, root);
}

Target _target(DocsProject project, Directory root, String? path) => project
    .resolveTarget(path, workingDirectory: root, defaultsToDocsRoot: true);

void main() {
  group('outputName', () {
    test('f05/us02/fr04/e01: a folder target keeps its path under docs and '
        'gains the format extension', () async {
      final (project, root) = await _open({
        '$_featureDir/FEATURE.md': _feature,
      });

      expect(
        outputName(_target(project, root, _featureDir), OutputFormat.html),
        '$_featureDir.html',
      );
    });

    test('f05/us02/fr04/e02: a file target keeps its .md', () async {
      final (project, root) = await _open({
        '$_featureDir/FEATURE.md': _feature,
      });

      expect(
        outputName(
          _target(project, root, '$_featureDir/FEATURE.md'),
          OutputFormat.html,
        ),
        '$_featureDir/FEATURE.md.html',
      );
    });

    test('f05/us02/fr04/e03: the docs root is named docs', () async {
      final (project, root) = await _open({
        '$_featureDir/FEATURE.md': _feature,
      });

      expect(
        outputName(_target(project, root, 'docs'), OutputFormat.html),
        'docs.html',
      );
    });

    test('f05/us02/fr04/e04, s03/inv14: a file x.md and a folder x get two '
        'names', () async {
      final (project, root) = await _open({
        'docs/x.md': '# x\n',
        'docs/x/y.md': '# y\n',
      });

      expect(
        outputName(_target(project, root, 'docs/x.md'), OutputFormat.html),
        'docs/x.md.html',
      );
      expect(
        outputName(_target(project, root, 'docs/x'), OutputFormat.html),
        'docs/x.html',
      );
    });
  });

  group('defaultOutputFile', () {
    test('f05/us02/fr04: mirrors the target under .specstone/build', () async {
      final (project, root) = await _open({
        '$_featureDir/FEATURE.md': _feature,
      });
      final separator = Platform.pathSeparator;

      final file = defaultOutputFile(
        project,
        _target(project, root, _featureDir),
        OutputFormat.html,
      );

      expect(
        file.path,
        '${project.projectRoot.path}$separator.specstone${separator}build'
        '${separator}docs${separator}prds${separator}features'
        '${separator}f05_rendering.html',
      );
      expect(project.displayPath(file), '.specstone/build/$_featureDir.html');
    });
  });

  group('OutputFormat', () {
    test('wire value and extension are the name', () {
      expect(OutputFormat.html.name, 'html');
    });

    test('f05/us02/fr04/e05, DP5: parse takes null and html, refuses the '
        'rest', () {
      expect(OutputFormat.parse(null), OutputFormat.html);
      expect(OutputFormat.parse('html'), OutputFormat.html);
      expect(
        () => OutputFormat.parse('pdf'),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                '--format takes html, not pdf',
              ),
        ),
      );
    });
  });

  group('BuildResult', () {
    test('f05/us02/fr04/e07: toJson holds output and warnings', () {
      const result = BuildResult(output: 'a.html', warnings: ['w']);

      expect(result.toJson(), {
        'output': 'a.html',
        'warnings': ['w'],
      });
    });
  });

  group('writeBuildOutput', () {
    test('NFR-DI01: writes the bytes, creates missing parents, and leaves '
        'no temp file', () async {
      final root = await Directory.systemTemp.createTemp('specstone_out_');
      addTearDown(() => root.delete(recursive: true));
      final output = File('${root.path}/a/b/page.html');

      writeBuildOutput(output, utf8.encode('<p>é</p>'), displayPath: 'x');

      expect(output.readAsStringSync(), '<p>é</p>');
      final names = output.parent
          .listSync()
          .map((entity) => entity.uri.pathSegments.last)
          .toList();
      expect(names, ['page.html']);
    });

    test('f05/us02/fr04/e06: a parent that is a file is output_not_writable '
        'with the display path', () async {
      final root = await Directory.systemTemp.createTemp('specstone_out_');
      addTearDown(() => root.delete(recursive: true));
      File('${root.path}/blocker').writeAsStringSync('x');

      expect(
        () => writeBuildOutput(
          File('${root.path}/blocker/x.html'),
          utf8.encode('x'),
          displayPath: 'blocker/x.html',
        ),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having(
                (f) => f.message,
                'message',
                'the output path is not writable',
              )
              .having((f) => f.file, 'file', 'blocker/x.html'),
        ),
      );
    });
  });
}
