import 'dart:io';

import 'package:test/test.dart';

import 'git_repo.dart';
import 'relative_link.dart';
import 'temp_tree.dart';

/// The ProjectPath of the legacy FR of [acmeLegacy].
const legacyFrPath =
    'docs/prds/features/f01_login/us01_email_login/functional_requirements/'
    'fr01_validate_credentials.md';

/// Links `ws/code/docs` to `../docs` under [tree], as stratum_ui does.
///
/// Returns false, marking the test skipped, where links need privileges.
bool linkCodeDocs(Directory tree) {
  try {
    createRelativeLink('${tree.path}/ws/code/docs', '../docs');
    return true;
  } on FileSystemException {
    markTestSkipped('symbolic links need privileges on this machine');
    return false;
  }
}

/// The flat legacy tree of the `specstone migrate --dry-run` example.
const acmeLegacy = <String, String>{
  'docs/prds/d01_context.md': '''
---
name: Acme project context
---

# D-01 — Project context

## Project vision

- **เพื่ออะไร (why):** Let owners log in.
- **แก้ปัญหาอะไร (problem):** Sign-in is slow.
- **แก้ให้ใคร (audience):** Acme staff.
''',
  'docs/prds/d02_features.md': '''
---
name: Acme feature index
---

# D-02 — Feature index
''',
  'docs/prds/d03_non_functional.md': '''
---
name: Acme non-functional requirements
---

# D-03 — Project-wide non-functional requirements

## Performance

| ID | Requirement |
|---|---|
| NFR-01 | Login answers in 1 s. |

## Data integrity

| ID | Requirement |
|---|---|
| NFR-02 | A credential is never lost. |
''',
  'docs/prds/features/f01_login/FEATURE.md': '''
---
name: Login
---

# F-01 — Login

## Feature name

- **Human:** Login
- **Code:** `login`

## Feature goal

Let a user sign in.

## Feature flow

1. Validate the credentials: [FR-01](us01_email_login/functional_requirements/fr01_validate_credentials.md).
2. Meet the limits in [NFRs](../../d03_non_functional.md), last listed in
   `../../d02_features.md`.

## User stories index

| Story | Title       |
|-------|-------------|
| US-01 | Email login |

## US ↔ FR rollup

| Story | FRs   |
|-------|-------|
| US-01 | FR-01 |
''',
  'docs/prds/features/f01_login/us01_email_login/USER_STORY.md': '''
---
name: Email login
---

# US-01 — Email login
''',
  legacyFrPath: '''
---
name: Validate credentials
---

# FR-01 — Validate credentials

## Statement

The system checks the credentials.
''',
  'docs/specs/INDEX.md': '''
# Spec index

## Global SoT files

_None._

## Spec map

| Code path | Spec path        | feature_id | cross-cutting | Notes |
|-----------|------------------|------------|---------------|-------|
| `api/auth/` | `specs/api/auth/` | `f01_login` | — | auth API |
| `shared/` | `specs/shared/` | — | yes | shared code |
''',
  'docs/specs/api/auth/s01_architecture.md': '''
---
name: Login architecture
feature_id: f01_login
---

# S-01 — Login architecture

## Tier-2 decisions

None yet.
''',
  'docs/specs/api/auth/s02_api_login.md': '''
---
name: Login API
---

# S-02 — Login API
''',
  'docs/specs/api/auth/s02_api_session.md': '''
---
name: Session API
---

# S-02 — Session API
''',
  'docs/specs/f01_login/INTEGRATION.md': '''
---
name: Login integrations
---

# Login integrations

## External systems

| System | Purpose     | Protocol | Owned by |
|--------|-------------|----------|----------|
| Mailer | Send emails | SMTP     | vendor   |
''',
  'docs/specs/shared/s01_architecture.md': '''
---
name: Shared architecture
---

# S-01 — Shared architecture
''',
};

/// Writes [files] under a new temp folder and commits them in a git repo.
Future<Directory> gitFixture(Map<String, String> files) async {
  final root = await writeTree(files);
  commitRepo(root);
  return root;
}

/// Makes [root] a git repo and commits every file under it.
void commitRepo(Directory root) {
  expect(git(root, ['init', '-q']).exitCode, 0);
  expect(git(root, ['config', 'user.name', 't']).exitCode, 0);
  expect(git(root, ['config', 'user.email', 't@t']).exitCode, 0);
  expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
  commitAll(root, 'legacy');
}
