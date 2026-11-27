import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/code_target.dart' show twinNamesOf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_floors.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/project_shapes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _numberValue = '1';
const _slugValue = 'a';

void main() {
  // D10: a path built from a shape matches its own doc type and parses back.
  test('every doc type path of every project shape round-trips', () async {
    final red = <String>[];
    var cells = 0;
    for (final shape in await projectShapes()) {
      final root = await writeTree(shape.allFiles);
      final set = _resolverOf(shape)
          .resolve(workingDirectory: root, homeDirectory: null);
      final targets = twinNamesOf(ProjectConfig.read(root).targetNames);
      final matcher = DocTypeMatcher(set, targetNames: targets);
      for (final docType in set.docTypes) {
        for (var depth = 0; depth < docType.paths.length; depth++) {
          for (final target
              in docType.isPerTarget && targets.isNotEmpty
                  ? targets
                  : const <String?>[null]) {
            final docShape = DocPathShape.of(
              docType,
              set,
              depth: depth,
              target: target,
            );
            if (docShape == null) {
              if (!_parentLacksDepth(docType, set, depth)) {
                red.add(
                  '${shape.name} ${docType.id} depth $depth target $target: '
                  'no shape',
                );
              }
              continue;
            }
            cells++;
            final values = _placeholderValues(docShape);
            final path = docShape.build(values);
            final label =
                '${shape.name} ${docType.id} depth $depth target $target: '
                '$path';
            final match = matcher.match(path);
            if (match is! MatchedDocType ||
                match.docType.id != docType.id ||
                match.target != target) {
              red.add('$label matched as $match');
            } else if (docShape.valuesOf(path)?.join('|') != values.join('|')) {
              red.add('$label read back as ${docShape.valuesOf(path)}');
            }
          }
        }
      }
    }
    expect(cells, greaterThan(0));
    expect(red, isEmpty);
  });
}

/// Whether [docType]'s parent has fewer paths than [depth] + 1, the one case
/// where a shape is rightly absent.
bool _parentLacksDepth(MergedDocType docType, MergedSet set, int depth) {
  if (depth > 0 && docType.id == set.nestingType?.id) return false;
  final parent = docType.parent;
  return parent != null && depth >= (set.lookup(parent)?.paths.length ?? 0);
}

TemplateResolver _resolverOf(ProjectShape shape) {
  if (shape.name != 'floor_pins') return TemplateResolver();
  final floors = PackFloors.shipped.byPack;
  return resolverCarrying({
    for (final pack in shippedPinsDefaultPacks)
      pack:
          '${floors[pack]!.major}.${floors[pack]!.minor}.'
          '${floors[pack]!.patch}',
  });
}

/// One value per placeholder of [shape], in pattern order.
List<String> _placeholderValues(DocPathShape shape) => [
  for (final segment in shape.segments)
    for (final token in PathSegment(segment).tokens)
      if (token == PathSegment.numberToken) _numberValue else _slugValue,
];
