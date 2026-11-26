import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/layer_source.dart'
    show projectTemplatesFolder;

/// Yields one finding per project layer file of a doc type a pack folded,
/// then one per layer file of a doc type a pack dropped, then one per orphaned
/// layer file, an override of a doc type no loaded pack defines.
///
/// A folded or dropped type's file is reported whatever it holds, unread: the
/// Owner moves a folded file's settings to the doc type it folded into, or
/// deletes the file.
Iterable<Finding> droppedTypeLayers(CheckContext context) sync* {
  final folded = context.set.foldedDocTypes;
  for (final MapEntry(key: from, value: to) in folded.entries) {
    final path = '$projectTemplatesFolder/$from.yaml';
    if (!File('${context.projectRoot.path}/$path').existsSync()) continue;
    yield _dropped(
      path,
      'a pack folded doc type $from into $to; move the settings of this '
      'file to the $to doc type, or delete the file',
    );
  }
  for (final id in context.set.droppedDocTypes) {
    final path = '$projectTemplatesFolder/$id.yaml';
    if (!File('${context.projectRoot.path}/$path').existsSync()) continue;
    yield _dropped(
      path,
      'a pack dropped doc type $id, and no doc type takes its settings; '
      'delete the file',
    );
  }
  for (final id in context.set.orphanedDocTypes) {
    yield _dropped(
      '$projectTemplatesFolder/$id.yaml',
      'no loaded pack defines doc type $id; move the settings of this file '
          'to the doc type that took its place, or delete the file',
    );
  }
}

Finding _dropped(String path, String message) => Finding(
  kind: FindingKind.layerDocTypeDropped,
  path: path,
  line: 1,
  message: message,
);
