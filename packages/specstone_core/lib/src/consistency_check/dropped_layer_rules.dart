import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/layer_source.dart'
    show projectTemplatesFolder;

/// Yields one finding per project layer file of a doc type a pack folded.
///
/// The file is reported whatever it holds: the Owner moves its settings to the
/// doc type it folded into, or deletes it.
Iterable<Finding> droppedTypeLayers(CheckContext context) sync* {
  final folded = context.set.foldedDocTypes;
  for (final MapEntry(key: from, value: to) in folded.entries) {
    final path = '$projectTemplatesFolder/$from.yaml';
    if (!File('${context.projectRoot.path}/$path').existsSync()) continue;
    yield Finding(
      kind: FindingKind.layerDocTypeDropped,
      path: path,
      line: 1,
      message:
          'a pack folded doc type $from into $to; move the settings of this '
          'file to the $to doc type, or delete the file',
    );
  }
}
