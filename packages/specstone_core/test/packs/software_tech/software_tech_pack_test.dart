import 'dart:convert';

import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';

void main() {
  group('software-tech manifest', () {
    test(
      'f03/us07/fr01: software-tech ships at 1.0.0 and extends prd-core',
      () {
        final bytes = shippedPackFiles['software-tech/pack.yaml'];
        expect(bytes, isNotNull);
        final manifest = PackManifest.parse(
          utf8.decode(bytes!),
          file: 'packs/software-tech/pack.yaml',
        );
        expect(manifest.name, 'software-tech');
        expect(manifest.version.toString(), '1.0.0');
        expect(manifest.extendsPack, 'prd-core');
      },
    );

    test(
      'f03/us07/fr01: a project pinning both packs resolves with no fault',
      () {
        expect(resolveSoftwareTech(), completes);
      },
    );

    test('f03/us07/fr01/e03: software-tech listed without prd-core is '
        'prd_core_missing', () async {
      final project = await writeTree({
        '.specstone/config.yaml': 'packs:\n  software-tech: 1.0.0\n',
      });
      final home = await writeTree({});
      expect(
        () => TemplateResolver().resolve(
          workingDirectory: project,
          homeDirectory: home,
        ),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.prdCoreMissing,
          ),
        ),
      );
    });
  });
}
