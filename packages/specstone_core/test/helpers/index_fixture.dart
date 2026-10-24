// The file contents are plan literals kept as written; one link has no space.
// ignore_for_file: lines_longer_than_80_chars, missing_whitespace_between_adjacent_strings

import 'dart:io';

import 'temp_tree.dart';

/// The project every index and query test reads.
///
/// Keys are paths relative to the project root; values use LF line ends.
const loginProject = <String, String>{
  '.specstone/config.yaml':
      'packs:\n  prd-core: 1.1.0\n  software-tech: 1.1.0\n',
  'docs/prds/PROJECT.md':
      '---\nowner: Owner\n---\n\n# Project context\n\n## Project name\nLogin demo\n\n'
      '## Role\n- `Owner` — the solo builder who owns the docs.\n\n## Out-of-scope\n- Billing — not planned\n\n'
      '## Domain glossary\n- **Doc** — one markdown file under the docs root\n',
  'docs/prds/FEATURES.md': '# Feature index\n\n## Systems\n- Login\n',
  'docs/prds/GNFR.md':
      '# Global non-functional requirements\n\n## Performance\nN/A — no budget yet\n\n'
      '## Security\n- Store no password in plain text.\n',
  'docs/specs/TECH_STACK.md': '# Tech stack\n\n## Stack\n| Slot | Choice |\n|------|--------|\n| Language | Dart |\n',
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
  'docs/prds/features/f01_login/us01_email_login/fr02_lock_after_failures.md':
      '---\nstatus: planned\n---\n\n'
      '# Lock after failures\n\n## Statement\nThe system shall lock the account for 15 minutes after five failed '
      'sign-ins.\n\n## Rationale\nN/A\n',
  'docs/prds/features/f01_login/us01_email_login/nf01_login_latency.md':
      '# Login latency\n\n## Statement\n'
      'The system shall answer a sign-in within 300 ms.\n',
  'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md':
      '---\nstatus: planned\n---\n\n'
      '# Agent resets a password\n\n## Use Case\nReset it.\n',
  'docs/prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md':
      '# Send a reset link\n\n'
      '## Statement\nThe system shall mail a link.\n',
  'docs/specs/f01_login/ARCHITECTURE.md':
      '---\ncovers:\n  - app/lib/src/login/\n---\n\n# Login architecture\n\n'
      '## Components\n| Component | Responsibility |\n|-----------|----------------|\n'
      '| Login form | Collects the email and the password |\n\n## Tier-2 decisions\nN/A — one local user\n',
  'docs/specs/f01_login/API.md': '# Login API\n\n## Operations\n- sign in\n',
  'docs/specs/f01_login/DOMAIN.md':
      '# Login domain\n\n## Entities\n- Account\n',
  'docs/specs/f01_login/ERROR.md':
      '# Login errors\n\n## Error catalog\n- locked\n',
  'docs/prds/features/f02_signup/FEATURE.md':
      '---\nstatus: planned\n---\n\n# Sign up\n\n## Problem\nNew users.\n',
  'docs/prds/features/f02_signup/us01_create_account/USER_STORY.md':
      '---\nstatus: implemented\n---\n\n'
      '# Agent creates an account\n\n## Use Case\nCreate one.\n',
  'docs/prds/features/f02_signup/us01_create_account/fr01_store_account.md':
      '---\nstatus: implemented\n'
      'implements:\n  - app/lib/src/signup/account_store.dart:AccountStore\n---\n\n# Store the account\n\n'
      '## Statement\nThe system shall store it.\n',
  'docs/specs/f02_signup/ARCHITECTURE.md':
      '---\ncovers:\n  - app/lib/src/signup/\n---\n\n# Sign-up architecture\n\n'
      '## Components\n- Form\n',
  'docs/specs/topics/auth_tokens.md':
      '---\ncovers:\n  - app/lib/src/tokens/\n---\n\n# Auth tokens\n\n## Purpose\n'
      'Hold tokens.\n',
  'docs/prds/personas/buyer/PERSONA.md':
      '---\nrole: Buyer\npriority: primary\nbasis: proto\n---\n\n# Buyer\n\n'
      '## Snapshot\nBuys things.\n',
  'docs/prds/personas/buyer/ANTI_PERSONA.md':
      '# Buyer anti-persona\n\n## Snapshot\nAbuses refunds.\n',
  'docs/prds/references/password_rules/REFERENCE.md':
      '# Password rules\n\n## Summary\nTwelve characters at least.\n',
  'docs/prds/d01_context.md':
      '# D-01 — Project context\n\n## Project name\n- **Human:** Specstone\n'
      '- **Code:** `specstone`\n\n## Project vision\nOne SDD system; ค้นหา เอกสาร\n',
  'docs/README.md': '# Readme\n\nStart here.\n',
  'docs/specs/schema.dbml': 'Table accounts {}\n',
  'docs/specs/api.apidog.json': '{}\n',
  'app/lib/main.dart': '',
  'app/lib/src/login/credential_validator.dart': '',
  'app/lib/src/login/sign_in_page.dart': '',
  'app/lib/src/login/login_form.dart': '',
  'app/lib/src/signup/account_store.dart': '',
  'app/lib/src/tokens/token_store.dart': '',
};

/// Writes [loginProject] under a new temp folder and returns that folder.
///
/// A key in [extra] replaces or adds a file.
Future<Directory> writeLoginProject({Map<String, String> extra = const {}}) =>
    writeTree({...loginProject, ...extra});

/// The FEATURE.md of `f01_login`, relative to the project root.
const featureKey = 'docs/prds/features/f01_login/FEATURE.md';

/// The DocPath of [featureKey].
const featureDoc = 'prds/features/f01_login/FEATURE.md';
