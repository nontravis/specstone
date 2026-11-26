// The test names and expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/dropped_layer_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _layerPath = '.specstone/templates/x.yaml';

/// A personal pack whose migration folds `x` into `fr`.
const _packFiles = {
  '.specstone/packs/acme/pack.yaml':
      'name: acme\nversion: 1.2.0\nextends: software-tech\n'
      'migrations:\n  - from: 1.0.0\n    steps:\n'
      '      - merge_doc: {from: {id: x, path: specs/X.md}, to: fr, '
      'sections: [{from: {id: moves, header: Moves}, to: statement}]}\n',
};

/// A personal pack whose migration drops the doc type `x`.
const _dropPackFiles = {
  '.specstone/packs/acme/pack.yaml':
      'name: acme\nversion: 1.2.0\nextends: software-tech\n'
      'migrations:\n  - from: 1.0.0\n    steps:\n'
      '      - drop_doc_type: {id: x, path: specs/X.md}\n',
};

/// Returns the findings of the rule over a project holding [layers] under
/// `.specstone/templates/`, the acme pack ([packFiles]) loaded from a
/// personal home.
Future<List<Finding>> _findings(
  Map<String, String> layers, {
  Map<String, String> packFiles = _packFiles,
}) async {
  final project = await writeCheckProject(
    extra: {
      '.specstone/config.yaml': '${shippedPinsConfig()}  acme: 1.2.0\n',
      for (final entry in layers.entries)
        '.specstone/templates/${entry.key}.yaml': entry.value,
    },
  );
  final home = await writeTree(packFiles);
  final session = ReadSession.open(
    templates: TemplateResolver(),
    workingDirectory: project,
    homeDirectory: home,
  );
  addTearDown(session.close);
  return droppedTypeLayers(CheckContext(session)).toList();
}

void main() {
  test('a layer file of a folded doc type with no path is one layer_doc_type_dropped at line 1 for the Owner', () async {
    final findings = await _findings({'x': 'sections: [{id: moves}]\n'});

    expect(findings, hasLength(1));
    final finding = findings.single;
    expect(finding.kind, FindingKind.layerDocTypeDropped);
    expect(finding.path, _layerPath);
    expect(finding.line, 1);
    expect(finding.name, isNull);
    expect(finding.keys, isEmpty);
    expect(finding.waitsFor, WaitsFor.owner);
    expect(finding.message, contains(' fr '));
    expect(finding.toJson()['kind'], 'layer_doc_type_dropped');
  });

  test(
    'a folded doc type layer file that writes path is reported all the same',
    () async {
      final findings = await _findings({'x': 'path: specs/{slug}/X.md\n'});

      expect(
        [for (final f in findings) '${f.path}:${f.line}: ${f.kind.wire}'],
        ['$_layerPath:1: layer_doc_type_dropped'],
      );
    },
  );

  test(
    'a project with no layer file of the folded doc type holds no finding',
    () async {
      expect(await _findings({}), isEmpty);
    },
  );

  test('a layer file with no id over a doc type no loaded pack defines is one layer_doc_type_dropped', () async {
    final findings = await _findings({'auth': 'path: specs/{slug}/AUTH.md\n'});

    expect(
      [for (final f in findings) '${f.path}:${f.line}: ${f.kind.wire}'],
      ['.specstone/templates/auth.yaml:1: layer_doc_type_dropped'],
    );
    expect(findings.single.message, contains(' auth;'));
  });

  test('a layer file of a doc type no step folds holds no finding', () async {
    expect(await _findings({'user_story': 'description: A story.\n'}), isEmpty);
  });

  test(
    'a layer file of a dropped doc type is one finding naming no successor',
    () async {
      final findings = await _findings({
        'x': 'path: specs/{slug}/X.md\n',
      }, packFiles: _dropPackFiles);

      expect(findings, hasLength(1));
      final finding = findings.single;
      expect(finding.kind, FindingKind.layerDocTypeDropped);
      expect(finding.path, _layerPath);
      expect(finding.line, 1);
      expect(finding.waitsFor, WaitsFor.owner);
      expect(finding.message, contains(' x,'));
      expect(finding.message, isNot(contains('no loaded pack defines')));
    },
  );

  for (final MapEntry(:key, value: content) in {
    'extends': 'extends: fr\n',
    'id': 'id: x\npath: specs/{slug}/X.md\ndescription: X.\n',
  }.entries) {
    test(
      'a dropped doc type file that writes $key is reported all the same',
      () async {
        final findings = await _findings({
          'x': content,
        }, packFiles: _dropPackFiles);

        expect(
          [for (final f in findings) '${f.path}:${f.line}: ${f.kind.wire}'],
          ['$_layerPath:1: layer_doc_type_dropped'],
        );
      },
    );
  }
}
