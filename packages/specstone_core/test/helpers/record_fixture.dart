import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

import 'shipped_pins.dart';
import 'write_fixture.dart';

/// The layer that adds the per-target `implementation` record doc type.
const recordLayer =
    'id: implementation\n'
    'description: One feature record per target.\n'
    'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
    'parent: feature\n'
    'per_target: true\n'
    'fields:\n'
    '  - id: statuses\n'
    '    type: record_status\n'
    '    list: true\n'
    '  - id: implements\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_exact\n'
    '  - id: tests\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_test\n';

/// The config that names the targets `flutter` and `jaspr`.
String twinConfig() =>
    '${shippedPinsConfig()}targets:\n'
    '  flutter:\n    code_root: flutter_ws\n'
    '  jaspr:\n    code_root: jaspr_ws\n';

/// The config of a project with one unnamed code target.
String oneTargetConfig() => '${shippedPinsConfig()}code_root: app\n';

/// Returns a record: [front], then `statuses`, `implements`, and `tests`, one
/// quoted line each; a key with no line is left out.
String recordText({
  String front = '',
  List<String> statuses = const [],
  List<String> code = const [],
  List<String> tests = const [],
}) {
  String list(String key, List<String> lines) => lines.isEmpty
      ? ''
      : "$key:\n${[for (final l in lines) "  - '$l'\n"].join()}";
  final fields = [
    list('statuses', statuses),
    list('implements', code),
    list('tests', tests),
  ].join();
  return '---\n$front$fields---\n\n# Record\n';
}

/// Stamps the doc at [docPath] under [root] with the approval hash of its
/// content, as `approve` leaves it.
void stampApproved(Directory root, String docPath) {
  final file = docFile(root, docPath);
  writeIn(root, (session) {
    final stamped = withApprovalHash(
      toLf(file.readAsStringSync()),
      session.docTypeAt(docPath),
      statusesOutside: session.project.statusesOutsideApproval,
    );
    file.writeAsStringSync(stamped);
  });
}

/// Whether the doc at [docPath] under [root] is no draft and holds the
/// approval hash of its content.
bool holdsApproval(Directory root, String docPath) {
  final text = toLf(readDoc(root, docPath));
  return writeIn(root, (session) {
    final fields = ApprovalFields.of(Doc.parse(text));
    return !fields.isDraft &&
        fields.approvedValue ==
            approvalHashOf(
              text,
              session.docTypeAt(docPath),
              statusesOutside: session.project.statusesOutsideApproval,
            );
  });
}
