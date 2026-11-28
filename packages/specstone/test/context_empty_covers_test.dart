@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../specstone_core/test/helpers/check_fixture.dart';
import '../../specstone_core/test/helpers/skill_doc_fixture.dart';
import 'helpers/built_cli.dart';
import 'helpers/temp_tree.dart';

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  Future<Directory> project(String covers) => writeTree({
    ...checkProjectFiles(),
    '.specstone/config.yaml': '${skillPinsConfig()}code_root: specstone\n',
    'specstone/keep.txt': '',
    ...skillDocFile([covers]),
    skillFile: skillText,
  });

  Future<ProcessResult> contextOf(Directory root, String path) => runSpecstone(
    binary,
    ['context', '--code', path, '--for', 'implement', '--json'],
    workingDirectory: root.path,
  );

  test('a path outside every code root that only an empty covers entry '
      'reaches exits 64 as code_path_outside_project', () async {
    final result = await contextOf(await project('./'), skillFile);

    expect(result.exitCode, 64, reason: '${result.stdout}\n${result.stderr}');
    final error = (jsonDecode(result.stderr as String) as Map)['error']! as Map;
    expect(error['code'], 'code_path_outside_project');
    expect(result.stdout, isEmpty);
  });

  test('the same path is bundled once a non-empty entry reaches it', () async {
    final result = await contextOf(
      await project('.claude/skills/review/'),
      skillFile,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
