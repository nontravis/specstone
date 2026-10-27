// The file contents mirror the core fixture; one link has no space.
// ignore_for_file: lines_longer_than_80_chars, missing_whitespace_between_adjacent_strings

import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';

import '../../../specstone_core/test/helpers/posix_modes.dart';
import '../../../specstone_core/test/helpers/shipped_pins.dart';
import 'temp_tree.dart';

// The entries mirror `loginProject` in specstone_core's test/helpers/index_fixture.dart.
final _readProject = <String, String>{
  '.specstone/config.yaml': shippedPinsConfig(),
  'docs/prds/features/f01_login/FEATURE.md':
      '---\nvision:\n  - PV-01\nslug:\n  - sign-in\n---\n\n# Login\n\n'
      '## Problem\nUsers sign in with an email and a password.\n\n## Out-of-scope\n- Social sign-in — not planned\n',
  'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
      '---\nstatus: planned\ndraft: true\ngoals:\n'
      '  - PG-01\npersona:\n  - buyer\nimplements:\n  - app/lib/src/login/sign_in_page.dart:SignInPage\n---\n\n'
      '# Agent signs in with email\n\n## Use Case\nSign in with an email. See [password rules]'
      '(../../../references/password_rules/REFERENCE.md).\n\n## Acceptance Criteria\n'
      '- Given the system will lock the account after five failed sign-ins\n',
  'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md':
      '---\nstatus: implemented\n'
      'implements:\n  - app/lib/src/login/credential_validator.dart:CredentialValidator\n---\n\n'
      '# Validate credentials\n\n## Statement\nThe system shall check the email and the password. See the '
      '[story](USER_STORY.md).\n\n## Edge cases\n<!-- fill in later -->\n1. E01 — A wrong password → refused.\n',
  'docs/specs/f01_login/ARCHITECTURE.md':
      '---\ncovers:\n  - app/lib/src/login/\n---\n\n# Login architecture\n\n'
      '## Components\n| Component | Responsibility |\n|-----------|----------------|\n'
      '| Login form | Collects the email and the password |\n\n## Tier-2 decisions\nN/A — one local user\n',
  'docs/prds/d01_context.md':
      '# D-01 — Project context\n\n## Project name\n- **Human:** Specstone\n'
      '- **Code:** `specstone`\n\n## Project vision\nOne SDD system; ค้นหา เอกสาร\n',
};

/// Writes a project pinning both shipped packs under a temp folder.
///
/// A key in [extra] replaces or adds a file.
Future<Directory> writeReadProject({Map<String, String> extra = const {}}) =>
    writeTree({..._readProject, ...extra});

/// Returns a runner on [workingDirectory] and the sinks it prints to.
///
/// The runner reads the built-in doc types and no user-level ones.
({SpecstoneCommandRunner runner, StringBuffer out, StringBuffer err})
readRunner(
  Directory workingDirectory, {
  Duration busyTimeout = indexBusyTimeout,
}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = SpecstoneCommandRunner(
    out: out,
    err: err,
    templates: TemplateResolver(),
    workingDirectory: workingDirectory,
    homeDirectory: null,
    busyTimeout: busyTimeout,
  );
  return (runner: runner, out: out, err: err);
}

/// Returns why a read-only folder cannot stop a write here, else null.
String? readOnlySkipReason() => unreadablePathSkipReason();
