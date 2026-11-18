import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/software_design_system.dart';

const _mockupType =
    'id: mockup\n'
    'description: A mockup.\n'
    'path: ops/mockups/{slug}.md\n'
    'fields:\n'
    '  - id: mockup\n'
    '    type: source_ref\n'
    '    list: true\n';
const _mockupDoc = 'ops/mockups/login.md';
const _componentGroupDoc = 'specs/design_system/components/button/GROUP.md';
const _componentDoc = 'specs/design_system/components/button/button.md';

/// Returns a project whose one `mockup` doc lists [entries] under `mockup:`,
/// with [extra] files beside it.
Future<Directory> _project(
  List<String> entries, {
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeCheckProject(
  without: without,
  extra: {
    '.specstone/templates/mockup.yaml': _mockupType,
    'docs/$_mockupDoc': _mockupText(entries),
    ...extra,
  },
);

String _mockupText(List<String> entries) =>
    '---\nmockup:\n${[for (final e in entries) "  - '$e'\n"].join()}---\n\n'
    '# Login\n';

/// Returns the finding line of [kind] on [entry] in [docPath], at the file
/// line [entry] sits on.
String _at(Directory project, String docPath, String kind, String entry) {
  final quoted = lineOfFirst(project, docPath, "'$entry'");
  final line = quoted > 0 ? quoted : lineOfFirst(project, docPath, '- $entry');
  return '$docPath: $kind $entry @$line';
}

/// Returns `<path>: <kind> <entry> @<line>` per design-source finding.
List<String> _sources(CheckReport report) => [
  for (final f in report.findings)
    if (f.kind == FindingKind.sourcePathMissing ||
        f.kind == FindingKind.sourcePathOutsideProject)
      '${f.path}: ${f.kind.wire} ${f.keys['entry']} @${f.line}',
];

void main() {
  test('a web URL is never checked, in any letter case', () async {
    final project = await _project([
      'https://www.figma.com/design/abc/Kit?node-id=12-34',
      'HTTP://example.com/kit.fig',
      'Https://example.com/x',
    ]);

    expect(_sources(await checkOf(project)), isEmpty);
  });

  test(
    'a file or folder under the project root gives no finding, with or '
    'without a trailing slash, a . or .. segment that stays inside',
    () async {
      final project = await _project(
        [
          'design/buttons.fig',
          'design/kit/',
          'design/kit',
          'design/./kit/',
          'design/other/../kit/',
          '.',
        ],
        extra: {'design/buttons.fig': 'x', 'design/kit/a.fig': 'x'},
      );

      expect(_sources(await checkOf(project)), isEmpty);
    },
  );

  test('a path that names nothing is source_path_missing at its line, key '
      'entry as written', () async {
    final project = await _project(['design/old/', 'design/gone.fig']);

    expect(_sources(await checkOf(project)), [
      _at(project, _mockupDoc, 'source_path_missing', 'design/old/'),
      _at(project, _mockupDoc, 'source_path_missing', 'design/gone.fig'),
    ]);
  });

  test('an entry with a scheme other than http or https is read as a path, '
      'so it is missing', () async {
    final project = await _project(['ftp://host/kit.fig']);

    expect(_sources(await checkOf(project)), [
      _at(project, _mockupDoc, 'source_path_missing', 'ftp://host/kit.fig'),
    ]);
  });

  test('a path that leaves the project root is source_path_outside_project, '
      'whether or not the file exists, also after normalizing', () async {
    final project = await _project(
      ['../kit.fig', 'design/../../kit.fig', '/etc/hosts', 'C:/kit.fig', '..'],
      extra: {'../kit.fig': 'x'},
    );

    expect(_sources(await checkOf(project)), [
      _at(project, _mockupDoc, 'source_path_outside_project', '../kit.fig'),
      _at(
        project,
        _mockupDoc,
        'source_path_outside_project',
        'design/../../kit.fig',
      ),
      _at(project, _mockupDoc, 'source_path_outside_project', '/etc/hosts'),
      _at(project, _mockupDoc, 'source_path_outside_project', 'C:/kit.fig'),
      _at(project, _mockupDoc, 'source_path_outside_project', '..'),
    ]);
  });

  test('a doc without the field gives no finding', () async {
    final project = await writeCheckProject(
      extra: {
        '.specstone/templates/mockup.yaml': _mockupType,
        'docs/$_mockupDoc': '# Login\n',
      },
    );

    expect(_sources(await checkOf(project)), isEmpty);
  });

  test('the entry resolves with no implemented record entry in any '
      'target', () async {
    final project = await _project(
      ['design/buttons.fig', 'design/gone.fig'],
      extra: {'design/buttons.fig': 'x'},
      without: {loginRecord},
    );

    expect(_sources(await checkOf(project)), [
      _at(project, _mockupDoc, 'source_path_missing', 'design/gone.fig'),
    ]);
  });

  test('a symbolic link to an existing file gives no finding', () async {
    final project = await _project(
      ['design/kit.fig'],
      extra: {'real.fig': 'x'},
    );
    Directory('${project.path}/design').createSync();
    Link('${project.path}/design/kit.fig')
        .createSync('${project.path}/real.fig');

    expect(_sources(await checkOf(project)), isEmpty);
  }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

  test('a symbolic link to nothing is source_path_missing', () async {
    final project = await _project(['design/kit.fig']);
    Directory('${project.path}/design').createSync();
    Link('${project.path}/design/kit.fig')
        .createSync('${project.path}/none.fig');

    expect(_sources(await checkOf(project)), [
      _at(project, _mockupDoc, 'source_path_missing', 'design/kit.fig'),
    ]);
  }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

  test('the field is found by its type, never its id', () async {
    final project = await writeCheckProject(
      extra: {
        '.specstone/templates/mockup.yaml': _mockupType.replaceAll(
          'id: mockup\n    type',
          'id: anything_else\n    type',
        ),
        'docs/$_mockupDoc': _mockupText(['design/gone.fig'])
            .replaceFirst('mockup:', 'anything_else:'),
      },
    );

    expect(_sources(await checkOf(project)), [
      _at(project, _mockupDoc, 'source_path_missing', 'design/gone.fig'),
    ]);
  });

  test('a component doc whose design_source names a missing file gives '
      'source_path_missing at the entry line, key entry', () async {
    final project = await writeCheckProject(
      extra: {
        '.specstone/config.yaml': softwareDesignSystemConfig(),
        'docs/$_componentGroupDoc': '# Buttons\n\n## Purpose\n\nButtons.\n',
        'docs/$_componentDoc':
            '---\nlifecycle: stable\ndesign_source:\n'
            '  - design/button.fig\n  - https://www.figma.com/design/a/B\n'
            '---\n\n# Button\n',
      },
    );

    expect(_sources(await checkOf(project)), [
      _at(project, _componentDoc, 'source_path_missing', 'design/button.fig'),
    ]);
  });
}
