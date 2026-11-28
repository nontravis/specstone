@Tags(['integration'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'built_cli.dart';
import 'temp_tree.dart';

void main() {
  const workspace = {
    'pubspec.yaml': 'name: w\n',
    'pubspec.lock': 'packages: {}\n',
    'packages/specstone/bin/specstone.dart': 'void main() {}\n',
    'packages/specstone/lib/a.dart': 'int a = 1;\n',
    'packages/specstone/test/a_test.dart': 'void main() {}\n',
    'packages/specstone/.dart_tool/cache': 'x\n',
    'packages/specstone_core/lib/c.dart': 'int c = 1;\n',
    'packages/specstone_core/coverage/lcov.info': 'x\n',
    'README.md': 'x\n',
  };

  Future<String> keyWith(Map<String, String> changes) async =>
      sourceKey(await writeTree({...workspace, ...changes}));

  test('two checkouts of one source share a key', () async {
    expect(await keyWith({}), await keyWith({}));
  });

  for (final path in [
    'packages/specstone/test/a_test.dart',
    'packages/specstone/.dart_tool/cache',
    'packages/specstone_core/coverage/lcov.info',
    'README.md',
  ]) {
    test('a change to $path keeps the key', () async {
      expect(await keyWith({path: 'changed\n'}), await keyWith({}));
    });
  }

  for (final path in [
    'pubspec.lock',
    'packages/specstone/lib/a.dart',
    'packages/specstone/lib/new.dart',
    'packages/specstone_core/lib/c.dart',
  ]) {
    test('a change to $path changes the key', () async {
      expect(await keyWith({path: 'changed\n'}), isNot(await keyWith({})));
    });
  }

  test('a missing build package fails the key', () async {
    final tree = await writeTree({'pubspec.yaml': '', 'pubspec.lock': ''});
    expect(() => sourceKey(tree), throwsA(isA<FileSystemException>()));
  });
}
