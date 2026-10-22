import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/pack_chain.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _configFile = '.specstone/config.yaml';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// A shipped pack built in memory: `name`, `version`, optional `extends`.
LoadedPack shipped(String name, String? extendsPack) =>
    loadShippedPackManifest(name, {
      '$name/pack.yaml': _bytes(
        'name: $name\nversion: 1.0.0\n'
        '${extendsPack == null ? '' : 'extends: $extendsPack\n'}',
      ),
    });

/// A personal pack written under a temp home folder, then read back.
Future<LoadedPack> personal(String name, String? extendsPack) async {
  final home = await writeTree({
    '.specstone/packs/$name/pack.yaml':
        'name: $name\nversion: 1.0.0\n'
        '${extendsPack == null ? '' : 'extends: $extendsPack\n'}',
  });
  return loadPersonalPackManifest(name, home);
}

void main() {
  group('orderPacks', () {
    test(
      'f03/us04/fr01: shipped packs stay first by name, personal last',
      () async {
        final ordered = orderPacks([
          await personal('nont-b', null),
          shipped('software-tech', null),
          shipped('prd-core', null),
          await personal('nont-a', null),
        ], configFile: _configFile);

        expect(ordered.map((p) => p.manifest.name), [
          'prd-core',
          'software-tech',
          'nont-a',
          'nont-b',
        ]);
      },
    );

    test('f03/us04/fr01/e10: a personal pack sits above every pack its chain '
        'reaches', () async {
      final ordered = orderPacks([
        await personal('nont-flutter', 'nont-software'),
        shipped('software-tech', null),
        await personal('nont-software', 'software-tech'),
      ], configFile: _configFile);

      expect(ordered.map((p) => p.manifest.name), [
        'software-tech',
        'nont-software',
        'nont-flutter',
      ]);
    });

    test('f03/us03/fr04/e02: an extends naming no loaded pack is '
        'extends_target_unknown', () async {
      final pack = await personal('nont-a', 'missing-pack');
      expect(
        () => orderPacks([pack], configFile: _configFile),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsTargetUnknown)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-a/pack.yaml',
              )
              .having((f) => f.key, 'key', 'extends')
              .having((f) => f.message, 'message', contains('missing-pack')),
        ),
      );
    });

    test(
      'f03/us03/fr04/e01: a chain back to its start is extends_cycle',
      () async {
        final nontA = await personal('nont-a', 'nont-b');
        final nontB = await personal('nont-b', 'nont-a');
        expect(
          () => orderPacks([nontA, nontB], configFile: _configFile),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.extendsCycle)
                .having(
                  (f) => f.file,
                  'file',
                  '~/.specstone/packs/nont-b/pack.yaml',
                )
                .having((f) => f.relatedFiles, 'relatedFiles', [
                  '~/.specstone/packs/nont-a/pack.yaml',
                ]),
          ),
        );
      },
    );

    test('f03/us04/fr01/e09: two personal packs with one extends target are '
        'personal_pack_conflict', () async {
      final nontA = await personal('nont-a', 'prd-core');
      final nontB = await personal('nont-b', 'prd-core');
      expect(
        () => orderPacks([
          shipped('prd-core', null),
          nontA,
          nontB,
        ], configFile: _configFile),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.personalPackConflict)
              .having((f) => f.file, 'file', _configFile)
              .having((f) => f.key, 'key', 'packs')
              .having(
                (f) => f.message,
                'message',
                allOf(
                  contains('nont-a'),
                  contains('nont-b'),
                  contains('prd-core'),
                ),
              ),
        ),
      );
    });
  });

  group('reaches', () {
    test(
      'f03/us04/fr02/e05: true along a chain, false across branches',
      () async {
        final flutter = await personal('nont-flutter', 'nont-software');
        final software = await personal('nont-software', 'software-tech');
        final tech = shipped('software-tech', null);
        final other = await personal('nont-x', null);
        final extendsOf = extendsMapOf([flutter, software, tech, other]);

        expect(reaches(flutter, software, extendsOf: extendsOf), isTrue);
        expect(reaches(flutter, tech, extendsOf: extendsOf), isTrue);
        expect(reaches(software, tech, extendsOf: extendsOf), isTrue);
        expect(reaches(tech, flutter, extendsOf: extendsOf), isFalse);
        expect(reaches(other, tech, extendsOf: extendsOf), isFalse);
        expect(reaches(flutter, flutter, extendsOf: extendsOf), isFalse);
      },
    );

    test(
      'f03/inv4: a loop that never returns to the start ends, not hangs',
      () async {
        final a = await personal('nont-a', 'nont-b');
        final b = await personal('nont-b', 'nont-c');
        final c = await personal('nont-c', 'nont-b');
        final target = await personal('nont-x', null);
        final extendsOf = extendsMapOf([a, b, c, target]);

        expect(reaches(a, target, extendsOf: extendsOf), isFalse);
      },
    );
  });
}
