import 'dart:io';

import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

import 'check_fixture.dart';
import 'shipped_pins.dart';

/// The DocPath of the flutter twin of the login architecture doc.
const flutterArchitecture = 'specs/flutter/f01_login/ARCHITECTURE.md';

/// The DocPath of the jaspr twin of the login architecture doc.
const jasprArchitecture = 'specs/jaspr/f01_login/ARCHITECTURE.md';

/// A sentence whose link points at no file: each doc that holds it has one
/// finding.
const brokenLink = ' See [x](../../../nowhere.md).';

/// Writes the two-target project and returns its folder.
///
/// The targets are `flutter` (`flutter_ws`) and `jaspr` (`jaspr_ws`), each with
/// a `login.dart`. `architecture` and `tech_stack` are per-target with one twin
/// each, since a shared doc with code paths is a finding; the API doc stays
/// shared. The feature, the API doc, and each twin hold one broken link,
/// so each finding names its doc. A key in [extra] replaces or adds a file; a
/// path in [without] drops one.
Future<Directory> writeTwinProject({
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) {
  // The twins read as approved: the helper's stamp skips a per-target path.
  final twin = withApprovalHash(
    toLf(
      checkProjectFiles()['docs/$loginArchitecture']!.replaceFirst(
        'One box.',
        'One box.$brokenLink',
      ),
    ),
    fixtureDocTypeOf(loginArchitecture),
  );
  final techTwin = withApprovalHash(
    toLf(checkProjectFiles()['docs/$techStack']!),
    fixtureDocTypeOf(techStack),
  );
  String code(String name) =>
      'class SignInPage {}\nclass ${name}SignIn {}\n'
      'bool checkPassword(String p) => p.isNotEmpty;\n';
  return writeCheckProject(
    without: {
      'docs/$loginArchitecture',
      'docs/$techStack',
      'app/lib/login.dart',
      ...without,
    },
    extra: {
      '.specstone/config.yaml':
          '${shippedPinsConfig()}targets:\n'
          '  flutter:\n    code_root: flutter_ws\n'
          '  jaspr:\n    code_root: jaspr_ws\n',
      '.specstone/templates/architecture.yaml':
          'id: architecture\nper_target: true\n',
      '.specstone/templates/implementation.yaml':
          'id: implementation\n'
          'description: One feature record per target.\n'
          'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
          'parent: feature\n'
          'per_target: true\n'
          'fields:\n'
          '  - id: statuses\n'
          '    type: record_status\n'
          '    list: true\n',
      '.specstone/templates/tech_stack.yaml':
          'id: tech_stack\nper_target: true\n',
      'docs/specs/flutter/TECH_STACK.md': techTwin,
      'docs/specs/jaspr/TECH_STACK.md': techTwin,
      'docs/$flutterArchitecture': twin,
      'docs/$jasprArchitecture': twin,
      // The record holds each item's status, so the shared docs write none.
      ...edit(loginStory, [('status: implemented\n', '')]),
      ...fr('status: implemented\n', ''),
      ...edit(loginApi, [
        ('Signs the Agent in.', 'Signs the Agent in.$brokenLink'),
      ]),
      ...edit(loginFeature, [
        ('Users forget passwords.', 'Users forget passwords.$brokenLink'),
      ]),
      'flutter_ws/app/lib/login.dart': code('Flutter'),
      'jaspr_ws/app/lib/login.dart': code('Jaspr'),
      ...extra,
    },
  );
}
