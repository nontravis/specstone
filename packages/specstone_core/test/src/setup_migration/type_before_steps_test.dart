import 'package:specstone_core/src/setup_migration/type_before_steps.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

void main() {
  test('typeBeforeSteps keeps the nested paths of a sub-feature doc type', () {
    final fr = TemplateResolver()
        .resolveCarried(
          packNames: const ['prd-core', 'software-tech'],
          homeDirectory: null,
        )
        .lookup('fr')!;
    expect(fr.paths.length, greaterThan(1));

    final before = typeBeforeSteps(
      fr,
      const <MigrationStep>[],
      lf: '# Check\n',
      statusesOutside: true,
    );

    expect(before.paths, fr.paths);
  });
}
