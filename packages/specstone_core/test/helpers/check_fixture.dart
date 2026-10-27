// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';

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

String _fp(String text) =>
    sha256.convert(utf8.encode(text)).toString().substring(0, 12);

/// Returns the first 12 hex digits of the SHA-256 of [block] and a newline.
String fingerprintFor(String block) => _fp('$block\n');

/// The text of login scenario 1.
const loginScenario1 =
    '### Scenario 1 — [happy] Sign in\n- **Given** an account\n'
    '- **When** the Agent signs in\n- **Then** the Agent sees the home page';

/// The text of login scenario 2.
const loginScenario2 =
    '### Scenario 2 — [error] Wrong password\n- **Given** an account\n'
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
      '---\nowner: Owner\n---\n\n# Login demo\n\n## Project name\nLogin demo\n\n'
      '## Project vision\n### PV-01 — One sign-in\n> en: One sign-in for every app.\n\n'
      '## Project goals\n### PG-01 — Fewer resets\nHalve the password resets.\n\n'
      '## Role\n- `Agent` — the coding agent that writes the docs.\n- `Owner` — the person who approves them.\n\n'
      '## Out-of-scope\n- Billing — not planned\n',
  'docs/prds/FEATURES.md': '# Features\n\n## System interaction diagram\nOne system.\n\n## Systems\n- Login\n',
  'docs/$gnfrDoc':
      '# Project-wide requirements\n\n## Performance\n### NFR-P01 — Sign-in time\n'
      '$loginNfrStatement\n- **Rationale:** Users wait.\n\n'
      '${const ['Security', 'Reliability', 'Maintainability', 'Interface', 'Environment', 'Safety', 'Operability', 'Design standards'].map((h) => '## $h\nN/A — none applies.\n').join('\n')}',
  'docs/$loginFeature':
      '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\n---\n\n# Login\n\n'
      '## Problem\nUsers forget passwords.\n\n## Benefit hypothesis\nFewer resets.\n\n'
      '## Success measures\nResets per week.\n\n## Current alternatives\nEmail links.\n\n'
      '## Feature flow\nSign in, then work.\n\n## Out-of-scope\n- Social sign-in — not planned\n',
  'docs/$loginStory':
      '---\nstatus: implemented\ngoals:\n  - PG-01\nimplements:\n'
      '  - app/lib/login.dart:SignInPage\n---\n\n# Agent signs in with email\n\n## Use Case\n'
      '- **As a** Agent who signs in\n- **I want to** sign in with an email\n- **so that** I reach my work\n\n'
      '## Acceptance Criteria\n\n$loginScenario1\n\n$loginScenario2\n',
  'docs/$loginFr':
      '---\nstatus: implemented\ntraced_from:\n  - S2\nverify_method: test\nimplements:\n'
      '  - app/lib/login.dart:checkPassword\nconfirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n---\n\n'
      '# Check the password\n\n## Statement\n$checkPasswordStatement\n\n'
      '## Edge cases\n1. E01 — An empty password → refused.\n\n## Rationale\nA wrong password must not sign in.\n\n'
      '## Verification\nTest: a wrong password is refused.\n',
  'docs/$loginNf':
      '---\nkind: tighten\noverrides: NFR-P01\nverify_method: test\nconfirmed:\n'
      '  - NFR-P01 ${fingerprintFor(loginNfrStatement)}\n---\n\n# Sign-in time\n\n'
      '## Statement\nThe system shall sign in within 1 s.\n\n## Rationale\nUsers wait.\n\n'
      '## Verification\nTest: a timed sign-in.\n',
  'docs/$techStack':
      '---\ncode:\n  - app/lib/\n---\n\n# Tech stack\n\n## Stack\n| Slot | Choice |\n'
      '|------|--------|\n| Language | Dart |\n\n## Naming\n- snake_case file names\n',
  'docs/$loginArchitecture':
      '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
      '## Component diagram\nOne box.\n\n## Components\n- Sign-in page\n\n'
      '## Concerns\n- Errors: see Components\n- Rollout: N/A — one release\n',
  'docs/$loginApi':
      '---\nconfirmed:\n  - email_login/check_password ${fingerprintFor(checkPasswordStatement)}\n---\n\n'
      '# Login API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
      '| email_login/check_password | `signIn` |\n\n## Operations\n### signIn\nSigns the Agent in.\n',
  'app/lib/login.dart': 'class SignInPage {}\n\nbool checkPassword(String password) => password.isNotEmpty;\n',
};

/// Writes the fixture under a new temp folder and returns that folder.
///
/// A key in [extra] replaces or adds a file; a path in [without] drops one.
Future<Directory> writeCheckProject({
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeTree({
  for (final entry in {...checkProjectFiles(), ...extra}.entries)
    if (!without.contains(entry.key)) entry.key: entry.value,
});

/// Opens a session on [project], runs the check, closes the session.
CheckReport checkOf(Directory project, {String? target}) {
  final session = openSession(project);
  try {
    return runCheck(session, target: target);
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
  var text = checkProjectFiles()[key]!;
  for (final (from, to) in changes) {
    if (!text.contains(from)) {
      throw ArgumentError.value(from, 'from', 'does not occur in $docPath');
    }
    text = text.replaceFirst(from, to);
  }
  return {key: text};
}

/// Returns [edit] of [loginFr] with one change.
Map<String, String> fr(String from, String to) => edit(loginFr, [(from, to)]);

/// Returns [edit] of [docPath] with one change.
Map<String, String> doc(String docPath, String from, String to) =>
    edit(docPath, [(from, to)]);
