import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

const _domain = 'specs/f01_login/DOMAIN.md';

void main() {
  test('a whole-project check finds each old cite from the stored names and '
      'items, with every doc file gone from disk', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$_domain':
            '# Login domain\n\n## Entities\n\n- Account\n\n'
            '## Invariants\n\n- **INV-6** An account holds one email.\n',
        ...doc(
          loginFeature,
          'Users forget passwords.',
          'Users forget; `domain:login` INV-6.',
        ),
      },
    );
    final session = openSession(project);
    addTearDown(session.close);
    List<Finding> cites(Iterable<Finding> findings) => [
      for (final f in findings)
        if (f.kind == FindingKind.citeUnlinked) f,
    ];
    final before = cites((await runCheck(session)).findings);
    expect(before, hasLength(1));

    Directory('${project.path}/docs').deleteSync(recursive: true);
    final after = cites((await runCheck(session)).findings);

    expect(after.map((f) => f.toJson()), before.map((f) => f.toJson()));
  });
}
