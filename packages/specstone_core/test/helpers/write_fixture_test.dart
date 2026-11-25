import 'dart:io';

import 'package:test/test.dart';

import 'posix_modes.dart';
import 'temp_tree.dart';
import 'write_fixture.dart';

void main() {
  test(
    'treeBytes lists the files outside .git and never reads inside it',
    () async {
      final root = await writeTree({
        'docs/a.md': 'a\n',
        '.git/objects/maintenance.lock': '',
      });
      Directory('${root.path}/docs/empty').createSync();
      Process.runSync('chmod', [
        '000',
        '${root.path}/.git/objects/maintenance.lock',
      ]);

      expect(
        treeBytes(root).keys,
        unorderedEquals(['docs', 'docs/a.md', 'docs/empty']),
      );
    },
    skip: unreadablePathSkipReason(),
  );
}
