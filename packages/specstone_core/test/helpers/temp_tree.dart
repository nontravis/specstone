import 'dart:io';

import 'package:test/test.dart';

/// Writes [files] under a new temp folder and returns that folder.
///
/// Keys are `/`-separated paths relative to the folder; parent folders are
/// created. The folder is deleted by `addTearDown`.
Future<Directory> writeTree(Map<String, String> files) async {
  final root = await Directory.systemTemp.createTemp('specstone_test_');
  addTearDown(() => root.delete(recursive: true));
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File.fromUri(root.uri.resolve(key));
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }
  return root;
}
