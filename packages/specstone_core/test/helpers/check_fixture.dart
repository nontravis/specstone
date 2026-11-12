// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

import 'index_fixture.dart';
import 'shipped_pins.dart';
import 'temp_tree.dart';

/// The DocPath of the project doc.
const projectDoc = 'prds/PROJECT.md';

/// The DocPath of the project-wide requirements doc.
const gnfrDoc = 'prds/GNFR.md';

/// The DocPath of the login feature.
const loginFeature = 'prds/features/f01_login/FEATURE.md';

/// The DocPath of the login story.
const loginStory = 'prds/features/f01_login/us01_email_login/USER_STORY.md';

/// The DocPath of the login functional requirement.
const loginFr =
    'prds/features/f01_login/us01_email_login/fr01_check_password.md';

/// The DocPath of the login non-functional requirement.
const loginNf = 'prds/features/f01_login/us01_email_login/nf01_sign_in_time.md';

/// The DocPath of the tech stack doc.
const techStack = 'specs/TECH_STACK.md';

/// The DocPath of the login architecture doc.
const loginArchitecture = 'specs/f01_login/ARCHITECTURE.md';

/// The DocPath of the login API doc.
const loginApi = 'specs/f01_login/API.md';

/// Returns the fingerprint of [block], as the library takes it.
String fingerprintFor(String block) => fingerprintOf(block);

/// Returns [block] laid out, less the one line break that ends it: the `text`
/// of a `suspect` finding.
String printedBlockOf(String block) {
  final text = upstreamText(block);
  return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
}

/// The text of login scenario 1.
const loginScenario1 =
    '### Scenario 1 — [happy] Sign in\n\n- **Given** an account\n'
    '- **When** the Agent signs in\n- **Then** the Agent sees the home page';

/// The text of login scenario 2.
const loginScenario2 =
    '### Scenario 2 — [error] Wrong password\n\n- **Given** an account\n'
    '- **When** the Agent types a wrong password\n- **Then** the Agent sees the sign-in refused';

/// The statement of the project-wide sign-in time requirement.
const loginNfrStatement =
    '- **Statement:** The system shall answer a sign-in within 2 s.';

/// The statement of the check-password requirement.
const checkPasswordStatement =
    'The system shall refuse a wrong password within 1 s.';

/// Returns the fixture project: every rule of US-01 to US-04 passes on it.
///
/// Keys are paths from the project root.
Map<String, String> checkProjectFiles() => {
  '.specstone/config.yaml': shippedPinsConfig(),
  'docs/$projectDoc':
      '---\nowner: Owner\n---\n\n# Login demo\n\n## Project name\n\nLogin demo\n\n'
      '## Project vision\n\n### PV-01 — One sign-in\n\n> en: One sign-in for every app.\n\n'
      '## Project goals\n\n### PG-01 — Fewer resets\n\n**Serves:** PV-01\nHalve the password resets.\n\n'
      '## Role\n\n- `Agent` — the coding agent that writes the docs.\n- `Owner` — the person who approves them.\n\n'
      '## Out-of-scope\n\n- Billing — not planned\n',
  'docs/prds/FEATURES.md': '# Features\n\n## System interaction diagram\n\nOne system.\n\n## Systems\n\n- Login\n',
  'docs/$gnfrDoc':
      '# Project-wide requirements\n\n## Performance\n\n### NFR-P01 — Sign-in time\n\n'
      '$loginNfrStatement\n- **Rationale:** Users wait.\n\n'
      '${const ['Security', 'Reliability', 'Maintainability', 'Interface', 'Environment', 'Safety', 'Operability', 'Design standards'].map((h) => '## $h\n\nN/A — none applies.\n').join('\n')}',
  'docs/$loginFeature':
      '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\n---\n\n# Login\n\n'
      '## Problem\n\nUsers forget passwords.\n\n## Benefit hypothesis\n\nFewer resets.\n\n'
      '## Success measures\n\nResets per week.\n\n## Current alternatives\n\nEmail links.\n\n'
      '## Feature flow\n\nSign in, then work.\n\n## Out-of-scope\n\n- Social sign-in — not planned\n',
  'docs/$loginStory':
      '---\nstatus: implemented\ngoals:\n  - PG-01\nimplements:\n'
      '  - app/lib/login.dart:SignInPage\n---\n\n# Agent signs in with email\n\n## Use Case\n\n'
      '- **As a** Agent who signs in\n- **I want to** sign in with an email\n- **so that** I reach my work\n\n'
      '## Acceptance Criteria\n\n$loginScenario1\n\n$loginScenario2\n',
  'docs/$loginFr':
      '---\nstatus: implemented\ntraced_from:\n  - S2\nverify_method: test\n'
      'confirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n'
      'implements:\n  - app/lib/login.dart:checkPassword\n---\n\n'
      '# Check the password\n\n## Statement\n\n$checkPasswordStatement\n\n'
      '## Edge cases\n\n1. E01 — An empty password → refused.\n\n## Rationale\n\nA wrong password must not sign in.\n\n'
      '## Verification\n\nTest: a wrong password is refused.\n',
  'docs/$loginNf':
      '---\nkind: tighten\noverrides: NFR-P01\nverify_method: test\nconfirmed:\n'
      '  - NFR-P01 ${fingerprintFor(loginNfrStatement)}\n---\n\n# Sign-in time\n\n'
      '## Statement\n\nThe system shall sign in within 1 s.\n\n## Rationale\n\nUsers wait.\n\n'
      '## Verification\n\nTest: a timed sign-in.\n',
  'docs/$techStack':
      '---\ncode:\n  - app/lib/\n---\n\n# Tech stack\n\n## Stack\n\n| Slot | Choice |\n'
      '|---|---|\n| Language | Dart |\n\n## Naming\n\n- snake_case file names\n',
  'docs/$loginArchitecture':
      '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
      '## Component diagram\n\nOne box.\n\n## Components\n\n- Sign-in page\n\n'
      '## Concerns\n\n- Errors: see Components\n- Rollout: N/A — one release\n',
  'docs/$loginApi':
      '---\nconfirmed:\n  - email_login/check_password ${fingerprintFor('\n$checkPasswordStatement')}\n---\n\n'
      '# Login API\n\n## FR trace\n\n| FR | Operation |\n|---|---|\n'
      '| email_login/check_password | `signIn` |\n\n## Operations\n\n### signIn\n\nSigns the Agent in.\n',
  'app/lib/login.dart': 'class SignInPage {}\n\nbool checkPassword(String password) => password.isNotEmpty;\n',
};

/// Writes the fixture under a new temp folder and returns that folder.
///
/// A key in [extra] replaces or adds a file; a path in [without] drops one.
/// Every typed doc carries the approval hash of its text, but a key in
/// [unstamped], which holds a file as written.
Future<Directory> writeCheckProject({
  Map<String, String> extra = const {},
  Set<String> without = const {},
  Set<String> unstamped = const {},
}) => writeTree(
  withApprovalHashes({
    for (final entry in {...checkProjectFiles(), ...extra}.entries)
      if (!without.contains(entry.key)) entry.key: entry.value,
  }, unstamped: unstamped),
);

/// Returns [files] with `approved: "<hash>"` on every typed doc that carries
/// neither `draft` nor `approved:`, so the fixture reads as approved.
///
/// A key in [unstamped] stays as written.
Map<String, String> withApprovalHashes(
  Map<String, String> files, {
  Set<String> unstamped = const {},
}) {
  final DocTypeMatcher matcher;
  try {
    matcher = docTypeMatcherOf(files);
  } on TemplateFault {
    // A config that resolves to no doc type has no hash to write.
    return files;
  }
  return {
    for (final MapEntry(:key, :value) in files.entries)
      key: unstamped.contains(key) ? value : _stamped(matcher, key, value),
  };
}

/// Returns the matcher of the doc types [files] resolve to.
///
/// Resolves them in a scratch project holding the files under `.specstone/`,
/// so no hash is typed by hand.
DocTypeMatcher docTypeMatcherOf(Map<String, String> files) {
  final scratch = Directory.systemTemp.createTempSync('specstone_check_');
  try {
    for (final MapEntry(:key, :value) in files.entries) {
      if (!key.startsWith('.specstone/')) continue;
      File('${scratch.path}/$key')
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    return DocTypeMatcher(
      TemplateResolver().resolve(
        workingDirectory: scratch,
        homeDirectory: null,
      ),
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

/// Returns the doc type the fixture gives [docPath].
///
/// Throws a [StateError] when none matches.
MergedDocType fixtureDocTypeOf(String docPath) =>
    switch (docTypeMatcherOf(checkProjectFiles()).match(docPath)) {
      MatchedDocType(:final docType) => docType,
      _ => throw StateError('no doc type matches $docPath'),
    };

String _stamped(DocTypeMatcher matcher, String path, String text) {
  if (!path.startsWith('docs/')) return text;
  final fields = ApprovalFields.of(Doc.parse(toLf(text)));
  if (fields.isDraft || fields.approvedValue != null) return text;
  // The check reports an invalid frontmatter alone; a stamp would mend it.
  if (DocLines.of(text).frontmatterErrorLine != null) return text;
  return switch (matcher.match(path.substring('docs/'.length))) {
    MatchedDocType(:final docType) => _withEndings(
      text,
      withApprovalHash(toLf(text), docType),
    ),
    _ => text,
  };
}

// The writers hash LF text; a CRLF fixture keeps its line ends.
String _withEndings(String original, String lf) =>
    original.contains('\r\n') ? lf.replaceAll('\n', '\r\n') : lf;

/// Opens a session on [project], runs the check, closes the session.
///
/// A [docPath] limits the run to that one doc.
CheckReport checkOf(Directory project, {String? target, String? docPath}) {
  final session = openSession(project);
  try {
    return runCheck(session, target: target, docPath: docPath);
  } finally {
    session.close();
  }
}

/// Returns `<path>:<line>: <kind>` per finding, of [kind] only when given.
List<String> spots(CheckReport report, [FindingKind? kind]) => [
  for (final f in report.findings)
    if (kind == null || f.kind == kind) '${f.path}:${f.line}: ${f.kind.wire}',
];

/// Returns the fixture file of [docPath] with each change applied once.
///
/// The key is `docs/<docPath>`. Throws an [ArgumentError] naming the anchor
/// when a `from` text does not occur, so a negative test cannot pass vacuously.
Map<String, String> edit(String docPath, List<(String, String)> changes) {
  final key = 'docs/$docPath';
  return {key: _changed(checkProjectFiles()[key]!, docPath, changes)};
}

/// Returns the fixture file of [docPath] approved as it stands, then changed.
///
/// The doc carries the approval hash of its text before [changes], as a doc
/// edited in an editor after the Owner's approval does.
Map<String, String> editedAfterApproval(
  String docPath,
  List<(String, String)> changes,
) {
  final key = 'docs/$docPath';
  final approved = withApprovalHashes(checkProjectFiles())[key]!;
  return {key: _changed(approved, docPath, changes)};
}

String _changed(String text, String docPath, List<(String, String)> changes) {
  var changed = text;
  for (final (from, to) in changes) {
    if (!changed.contains(from)) {
      throw ArgumentError.value(from, 'from', 'does not occur in $docPath');
    }
    changed = changed.replaceFirst(from, to);
  }
  return changed;
}

/// Returns [edit] of [loginFr] with one change.
Map<String, String> fr(String from, String to) => edit(loginFr, [(from, to)]);

/// Returns [edit] of [docPath] with one change.
Map<String, String> doc(String docPath, String from, String to) =>
    edit(docPath, [(from, to)]);
