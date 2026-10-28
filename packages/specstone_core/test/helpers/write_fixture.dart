// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

import 'index_fixture.dart';
import 'shipped_pins.dart';
import 'temp_tree.dart';

/// A `docs/`-relative path of a document in [writeProject].
const story1 = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
const story2 = 'prds/features/f01_login/us02_sign_out/USER_STORY.md';
const story3 = 'prds/features/f01_login/us03_reset_password/USER_STORY.md';
const fr11 =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const fr12 =
    'prds/features/f01_login/us01_email_login/fr02_lock_after_failures.md';
const fr31 =
    'prds/features/f01_login/us03_reset_password/fr01_send_reset_link.md';
const fr32 =
    'prds/features/f01_login/us03_reset_password/fr02_expire_reset_link.md';
const loginFeature = 'prds/features/f01_login/FEATURE.md';
const signupFeature = 'prds/features/f02_signup/FEATURE.md';
const loginArch = 'specs/f01_login/ARCHITECTURE.md';
const signupArch = 'specs/f02_signup/ARCHITECTURE.md';
const persona = 'prds/personas/buyer/PERSONA.md';
const antiPersona = 'prds/personas/buyer/ANTI_PERSONA.md';

/// The project every write test starts from.
///
/// Keys are paths relative to the project root; values use LF line ends.
/// Approved: [loginFeature], [fr11], [story2], [loginArch]. Untyped:
/// `prds/d01_context.md`. Inbound links: [fr12] into [story3], [fr32] into
/// [fr31], [story3] into [story2], `FEATURES.md` into both features,
/// `d01_context.md` into [signupFeature]. `doc_ref` values: [story1]'s
/// `persona: buyer`, [persona]'s `reference: login/email_login`.
final writeProject = <String, String>{
  '.specstone/config.yaml': shippedPinsConfig(),
  'docs/prds/FEATURES.md': '# Feature index\n\n## Systems\n- [Login](features/f01_login/FEATURE.md)\n- [Signup](features/f02_signup/FEATURE.md)\n',
  'docs/prds/d01_context.md': '# Context\n\n## Features\nSee [signup](features/f02_signup/FEATURE.md).\n',
  'docs/prds/personas/buyer/PERSONA.md': '---\ndraft: true\nreference:\n  - login/email_login\n---\n\n# Buyer\n\n## Profile\nBuys things.\n',
  'docs/prds/personas/buyer/ANTI_PERSONA.md':
      '---\ndraft: true\n---\n\n# Not a buyer\n',
  'docs/prds/features/f01_login/FEATURE.md': '---\nvision:\n  - PV-01\n---\n\n# Login\n\n## Problem\nUsers sign in with an email and a password.\n',
  'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
      '---\nstatus: planned\ndraft: true\nvision:\n  - PV-01\npersona:\n  - buyer\n---\n\n# Sign in with email\n\n'
      '## Use Case\nSign in with an email.\n\n## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n'
      '- **Given** a registered email\n',
  'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md':
      '---\nstatus: implemented\ntraced_from: US-01\nverify_method: test\nimplements:\n'
      '  - app/lib/src/login/credential_validator.dart:CredentialValidator\n---\n\n# Validate credentials\n\n'
      '## Statement\nThe system shall check the email and the password.\n',
  'docs/prds/features/f01_login/us01_email_login/fr02_lock_after_failures.md':
      '---\ndraft: true\ntraced_from: US-01\nverify_method: test\n---\n\n# Lock after failures\n\n'
      '## Statement\nThe system shall lock the account. See [reset](../us03_reset_password/USER_STORY.md#use-case).\n',
  'docs/prds/features/f01_login/us02_sign_out/USER_STORY.md':
      '---\nstatus: planned\napproved: true\n---\n\n# Sign out\n\n## Use Case\nSign out.\n\n'
      '## Acceptance Criteria\n- **Given** a signed-in user\n',
  'docs/prds/features/f01_login/us03_reset_password/USER_STORY.md':
      '---\nstatus: planned\ndraft: true\n---\n\n# Reset password\n\n## Use Case\nReset a password. See '
      '[sign out](../us02_sign_out/USER_STORY.md).\n\n## Acceptance Criteria\n- **Given** a forgotten password\n',
  'docs/prds/features/f01_login/us03_reset_password/fr01_send_reset_link.md':
      '---\ndraft: true\ntraced_from: US-03\nverify_method: test\n---\n\n# Send reset link\n\n'
      '## Statement\nThe system shall send a link.\n',
  'docs/prds/features/f01_login/us03_reset_password/fr02_expire_reset_link.md':
      '---\ndraft: true\ntraced_from: US-03\nverify_method: test\n---\n\n# Expire reset link\n\n'
      '## Statement\nThe system shall expire the link. See [send](fr01_send_reset_link.md).\n',
  'docs/prds/features/f02_signup/FEATURE.md': '---\ndraft: true\n---\n\n# Signup\n\n## Problem\nUsers create an account.\n',
  'docs/specs/f01_login/ARCHITECTURE.md':
      '---\ncovers:\n  - app/lib/src/login/\n---\n\n# Login architecture\n\n## Components\n'
      '| Component | Responsibility |\n|-----------|----------------|\n| Login form | Collects the email and the password |\n',
  'docs/specs/f02_signup/ARCHITECTURE.md':
      '---\ndraft: true\n---\n\n# Signup architecture\n\n## Components\n| Component | Responsibility |\n'
      '|-----------|----------------|\n| Signup form | Collects the email |\n',
};

/// Writes [writeProject] to a new temp folder and returns it.
///
/// A key in [extra] replaces or adds a file; a key in [without] drops one.
Future<Directory> writeWriteProject({
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeTree({
  for (final MapEntry(:key, :value) in writeProject.entries)
    if (!without.contains(key)) key: value,
  ...extra,
});

/// Opens the project at [root] with the shipped packs and no home folder.
DocsProject openProject(Directory root) => DocsProject.open(
  templates: TemplateResolver(),
  workingDirectory: root,
  homeDirectory: null,
);

/// Returns the file of [docPath], a path relative to `docs/`.
File docFile(Directory root, String docPath) =>
    File('${root.path}/docs/$docPath');

/// Returns the text of the doc at [docPath].
String readDoc(Directory root, String docPath) =>
    docFile(root, docPath).readAsStringSync();

/// Whether a file exists at [docPath].
bool hasDoc(Directory root, String docPath) =>
    docFile(root, docPath).existsSync();

/// Writes [steps] as the unfinished move journal of [root].
void writeJournal(Directory root, List<JournalStep> steps) {
  final file = File('${root.path}/${MoveJournal.journalPath}');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(MoveJournal(steps).toJson()));
}

/// Runs [body] in a [WriteSession] on [root] with the shipped packs.
T writeIn<T>(
  Directory root,
  T Function(WriteSession session) body, {
  Duration busyTimeout = indexBusyTimeout,
}) => WriteSession.run(
  body,
  templates: TemplateResolver(),
  workingDirectory: root,
  homeDirectory: null,
  busyTimeout: busyTimeout,
);

/// Returns the first doc object `get` prints for [address], as an Agent reads
/// a base.
Map<String, Object?> getDoc(Directory root, String address) {
  final session = openSession(root);
  try {
    final docs = answerGet(session.index, address).json['docs']! as List;
    return docs.first as Map<String, Object?>;
  } finally {
    session.close();
  }
}
