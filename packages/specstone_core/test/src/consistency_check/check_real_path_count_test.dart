import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/counting_io.dart';
import '../../helpers/index_fixture.dart';

/// Returns the real-path resolves of one check of a project with [folders]
/// code folders of [filesPerFolder] files each and [docs] extra requirement
/// docs.
Future<int> _resolvesOfCheck({
  int folders = 1,
  int filesPerFolder = 0,
  int docs = 0,
}) async {
  final project = await writeCheckProject(
    extra: {
      for (var folder = 0; folder < folders; folder++)
        for (var file = 0; file < filesPerFolder; file++)
          'app/lib/gen$folder/file_$file.dart': '// plain code file\n',
      for (var i = 0; i < docs; i++)
        'docs/prds/features/f01_login/us01_email_login/fr${i + 2}_extra.md':
            checkProjectFiles()['docs/$loginFr']!,
    },
  );
  final session = openSession(project);
  addTearDown(session.close);
  return countRealPathResolves(() => runCheck(session));
}

void main() {
  test('one check resolves real paths as often for twice the files in '
      'each folder', () async {
    final base = await _resolvesOfCheck(folders: 5, filesPerFolder: 10);
    final doubled = await _resolvesOfCheck(folders: 5, filesPerFolder: 20);

    expect(doubled, base);
  });

  test('one check resolves real paths at most once more for each extra '
      'code folder', () async {
    final base = await _resolvesOfCheck(folders: 5, filesPerFolder: 3);
    final more = await _resolvesOfCheck(folders: 15, filesPerFolder: 3);

    expect(more, lessThanOrEqualTo(base + 10));
  });

  test('one check resolves real paths as often for twice the docs', () async {
    final base = await _resolvesOfCheck(docs: 10);
    final doubled = await _resolvesOfCheck(docs: 20);

    expect(doubled, base);
  });
}
