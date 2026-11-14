// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:yaml/yaml.dart';

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

/// The DocPath of the login record, the story's and the FR's status and code.
const loginRecord = 'specs/f01_login/IMPLEMENTATION.md';

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
      '---\ngoals:\n  - PG-01\n---\n\n# Agent signs in with email\n\n## Use Case\n\n'
      '- **As a** Agent who signs in\n- **I want to** sign in with an email\n- **so that** I reach my work\n\n'
      '## Acceptance Criteria\n\n$loginScenario1\n\n$loginScenario2\n',
  'docs/$loginFr':
      '---\ntraced_from:\n  - S2\nverify_method: test\n'
      'confirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n---\n\n'
      '# Check the password\n\n## Statement\n\n$checkPasswordStatement\n\n'
      '## Edge cases\n\n1. E01 — An empty password → refused.\n\n## Rationale\n\nA wrong password must not sign in.\n\n'
      '## Verification\n\nTest: a wrong password is refused.\n',
  'docs/$loginRecord':
      "---\nstatuses:\n  - 'email_login:implemented'\n"
      "  - 'email_login/check_password:implemented'\nimplements:\n"
      "  - 'email_login:app/lib/login.dart:SignInPage'\n"
      "  - 'email_login/check_password:app/lib/login.dart:checkPassword'\n"
      "tests:\n  - 'email_login/check_password:app/lib/login.dart'\n"
      '---\n\n# Login implementation\n',
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
      '## Component diagram\n\nOne box.\n\n## Components\n\n'
      '| Component | Responsibility |\n|---|---|\n| Sign-in page | Takes the form |\n\n'
      '## Concerns\n\n- Integration: N/A — no outside call\n- Errors: see Components\n'
      '- Auth: N/A — one local user\n- Lifecycle: N/A — no states\n- Events: N/A — no events\n'
      '- Rollout: N/A — one release\n- Observability: N/A — no telemetry\n',
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
/// [unstamped], which holds a file as written. Every code link of a doc
/// records the fingerprint of the code it names, so the fixture reads as
/// compared, but a key in [unfingerprinted] keeps its code links as written.
Future<Directory> writeCheckProject({
  Map<String, String> extra = const {},
  Set<String> without = const {},
  Set<String> unstamped = const {},
  Set<String> unfingerprinted = const {},
}) => writeTree(
  withApprovalHashes(
    withCodeFingerprints({
      for (final entry in {...checkProjectFiles(), ...extra}.entries)
        if (!without.contains(entry.key)) entry.key: entry.value,
    }, unfingerprinted: unfingerprinted),
    unstamped: unstamped,
  ),
);

/// Returns [files] with the fingerprint of the code each `implements` and
/// `covers` entry names recorded after it, for a doc not in [unfingerprinted].
///
/// An entry that records one, or names no file or folder of [files], stays as
/// written. The code is every file outside `docs/` and `.specstone/`; an entry
/// reads from the code root of its doc's target under `targets:`, else from
/// the config's `code_root:`, else from the project root.
Map<String, String> withCodeFingerprints(
  Map<String, String> files, {
  Set<String> unfingerprinted = const {},
}) {
  final codeFiles = {
    for (final MapEntry(:key, :value) in files.entries)
      if (!key.startsWith('docs/') && !key.startsWith('.specstone/'))
        key: fileCodeFingerprint(utf8.encode(value)),
  };
  final config = _configOf(files);
  final codeByRoot = <String, Map<String, String>>{};
  String stamped(String docKey, String text) {
    final root = _codeRootOf(docKey, config);
    final code = root == null
        ? null
        : codeByRoot.putIfAbsent(root, () => _codeUnder(root, codeFiles));
    return _withCodeFingerprints(docKey, text, code);
  }

  return {
    for (final MapEntry(:key, :value) in files.entries)
      key: key.startsWith('docs/') && !unfingerprinted.contains(key)
          ? stamped(key, value)
          : value,
  };
}

Map<Object?, Object?> _configOf(Map<String, String> files) {
  final text = files['.specstone/config.yaml'];
  if (text == null) return const {};
  try {
    return switch (loadYaml(text)) {
      final Map<Object?, Object?> config => config,
      _ => const {},
    };
  } on YamlException {
    // A fixture may hold a config the loader refuses; it names no code root.
    return const {};
  }
}

/// Returns the code root [docKey] reads its entries from, `''` for the
/// project root, null for a root outside the project, which holds no fixture
/// file.
String? _codeRootOf(String docKey, Map<Object?, Object?> config) {
  final targets = config['targets'];
  if (targets is! Map) return _normalRoot(config['code_root']);
  for (final MapEntry(:key, :value) in targets.entries) {
    if (!docKey.startsWith('docs/specs/$key/')) continue;
    return switch (value) {
      null => '',
      final Map<Object?, Object?> target => _normalRoot(target['code_root']),
      _ => throw StateError('target $key holds no mapping: $value'),
    };
  }
  return '';
}

/// Returns [root] as a `/`-separated path under the project root, `''` for
/// the project root itself or an absent root, null for a root outside it.
String? _normalRoot(Object? root) {
  if (root == null) return '';
  final segments = '$root'.split('/').where((s) => s.isNotEmpty && s != '.');
  if (segments.contains('..') || '$root'.startsWith('/')) return null;
  return segments.join('/');
}

/// Returns the fingerprints of the files under [root], by path from [root].
Map<String, String> _codeUnder(String root, Map<String, String> codeFiles) {
  if (root.isEmpty) return codeFiles;
  return {
    for (final MapEntry(:key, :value) in codeFiles.entries)
      if (key.startsWith('$root/')) key.substring(root.length + 1): value,
  };
}

final _codeLinkLine = RegExp(r"^(  - )('?)(.+?)\2$");

/// Throws a [StateError] when [code] is null, a root outside the project,
/// and [text] holds an entry to stamp: list the doc in `unfingerprinted`.
String _withCodeFingerprints(
  String docKey,
  String text,
  Map<String, String>? code,
) {
  if (!text.startsWith('---\n')) return text;
  var field = '';
  final lines = text.split('\n');
  for (var i = 1; i < lines.length && lines[i] != '---'; i++) {
    final key = RegExp(r'^(\w+):$').firstMatch(lines[i])?.group(1);
    if (key != null) field = key;
    final link = _codeLinkLine.firstMatch(lines[i]);
    if (link == null || (field != 'implements' && field != 'covers')) continue;
    if (code == null) {
      throw StateError(
        '$docKey holds a code link under a code_root outside the project; '
        'list it in unfingerprinted',
      );
    }
    final [indent, quote, value] = [link[1]!, link[2]!, link[3]!];
    final stamped = field == 'covers'
        ? _stampedEntry(value, code)
        : _stampedRecordEntry(value, code);
    lines[i] = '$indent$quote$stamped$quote';
  }
  return lines.join('\n');
}

String _stampedRecordEntry(String value, Map<String, String> code) {
  final parsed = recordCodeLineOf(value);
  if (parsed == null) return value;
  final path = parsed.code.split(':').first;
  return '${parsed.item}:${_stampedEntry(parsed.code, code, path: path)}';
}

String _stampedEntry(String entry, Map<String, String> code, {String? path}) {
  if (CodeLinkEntry(entry).fingerprint != null) return entry;
  final target = path ?? entry;
  final fingerprint = target.endsWith('/')
      ? _folderFingerprint(target, code)
      : code[target];
  return fingerprint == null ? entry : codeLinkEntryOf(entry, fingerprint);
}

String? _folderFingerprint(String folder, Map<String, String> code) {
  final names = code.keys.where((k) => k.startsWith(folder)).toList()..sort();
  if (names.isEmpty) return null;
  return folderCodeFingerprint([
    for (final name in names) (path: name, fingerprint: code[name]!),
  ]);
}

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
      targetNames: const [],
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
      // The matcher resolves the shipped packs, so their rule applies.
      withApprovalHash(
        toLf(text),
        docType,
        statusesOutside: shippedStatusesOutside,
      ),
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
