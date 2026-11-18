import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

const _doc = 'prds/PROJECT.md';

Map<String, Object?> _errorOf(StringBuffer err) =>
    (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
        as Map<String, Object?>;

void main() {
  test('delete in a project whose .specstone is a link exits 78 before it '
      'removes a doc', () async {
    final base = await writeTree({
      'x/config.yaml': shippedPinsConfig(),
      'proj/docs/$_doc': 'kept\n',
    });
    final project = Directory('${base.path}/proj');
    Link('${project.path}/.specstone').createSync('../x');
    final (:runner, :out, :err) = writeRunner(project);

    expect(await runner.run(['delete', 'project', '--json']), 78);

    expect(out.toString(), isEmpty);
    expect(_errorOf(err)['message'], contains('.specstone must be a real'));
    expect(File('${project.path}/docs/$_doc').readAsStringSync(), 'kept\n');
  }, skip: _linksUnavailable);

  test('delete in a folder whose .specstone is a regular file exits 78 as no '
      'project and leaves the file', () async {
    final root = await writeTree({'.specstone': 'x', 'docs/$_doc': 'kept\n'});
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['delete', 'project', '--json']), 78);

    expect(out.toString(), isEmpty);
    expect(_errorOf(err)['code'], 'project_not_found');
    expect(File('${root.path}/.specstone').readAsStringSync(), 'x');
    expect(File('${root.path}/docs/$_doc').readAsStringSync(), 'kept\n');
  });
}
