import 'dart:io';

import 'package:test/test.dart';

import 'git_repo.dart';
import 'temp_tree.dart';

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

| ID     | Requirement           |
|--------|-----------------------|
| NFR-01 | Login answers in 1 s. |

## Data integrity

| ID     | Requirement                  |
|--------|------------------------------|
| NFR-02 | A credential is never lost.  |
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
2. Meet the limits in [NFRs](../../d03_non_functional.md).

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
  'docs/prds/features/f01_login/us01_email_login/functional_requirements/'
      'fr01_validate_credentials.md': '''
---
name: Validate credentials
status: planned
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
  'docs/specs/shared/s01_architecture.md': '''
---
name: Shared architecture
---

# S-01 — Shared architecture
''',
};

/// A grouped legacy tree (brick_dartfrog shape): a folder above a group.
const groupedLegacy = <String, String>{
  'docs/prds/features/brick_module/README.md': '# Brick module\n',
  'docs/prds/features/brick_module/tool_module/tm01_stripe/FEATURE.md':
      '# F-01 — Stripe\n',
  'docs/prds/features/brick_module/tool_module/tm01_stripe/us01_pay/'
          'USER_STORY.md':
      '# US-01 — Pay\n',
  'docs/prds/features/ai_module/ai05_chat/FEATURE.md': '# F-05 — Chat\n',
};

/// A legacy tree with container features (stratum_ui shape).
const containerLegacy = <String, String>{
  'docs/prds/features/components/co01_utilities/FEATURE.md': '# Utilities\n',
  'docs/prds/features/components/co01_utilities/co01_01_slot/FEATURE.md':
      '# F-01 — Slot\n',
  'docs/prds/features/components/co07_navigation/FEATURE.md':
      '# F-07 — Navigation\n',
};

/// A legacy tree with a flat feature beside a grouped one.
const mixedLegacy = <String, String>{
  'docs/prds/features/f01_login/FEATURE.md': '# F-01 — Login\n',
  'docs/prds/features/ai_module/ai05_chat/FEATURE.md': '# F-05 — Chat\n',
};

/// A legacy tree whose two group folders give the group slug `utilities`.
const duplicateGroupLegacy = <String, String>{
  'docs/prds/features/components/co01_utilities/xx01_a/FEATURE.md':
      '# F-01 — A\n',
  'docs/prds/features/core/cr02_utilities/yy01_b/FEATURE.md': '# F-01 — B\n',
};

/// `acmeLegacy` plus a second feature and the spec files its rules must
/// place, leave, or refuse.
final specEdgeLegacy = <String, String>{
  ...acmeLegacy,
  'docs/prds/d04_glossary.md': '# Glossary\n',
  'docs/prds/features/f02_billing/FEATURE.md': '''
---
name: Billing
---

# F-02 — Billing
''',
  'docs/specs/INDEX.md': '''
# Spec index

## Global SoT files

| File | Holds |
|------|-------|
| `specs/schema.dbml` | schema |

## Spec map

| Code path | Spec path | feature_id | cross-cutting | Notes |
|-----------|-----------|------------|---------------|-------|
| `api/auth/` | `specs/api/auth/` | `f01_login` | — | auth API |
| `shared/` | `specs/shared/` | — | yes | shared code |
| `api/billing/` | `specs/api/billing/` | `f02_billing` | — | billing API |
| `web/billing_ui/` | `specs/web/billing_ui/` | `f02_billing` | — | billing UI |
| `two/` | `specs/two/` | `f01_login` | — | first owner |
| `two/` | `specs/two/` | `f02_billing` | — | second owner |
| `ghost/` | `specs/ghost/` | `f09_ghost` | — | no such feature |
''',
  'docs/specs/api/billing/s01_architecture.md': '''
---
name: Billing architecture
feature_id: f02_billing
---

# S-01 — Billing architecture
''',
  'docs/specs/web/billing_ui/s01_architecture.md': '''
---
name: Billing UI architecture
feature_id: f02_billing
---

# S-01 — Billing UI architecture

See [domain](../../api/billing/s04_domain.md).
''',
  'docs/specs/api/billing/s04_domain.md': '# S-04 — Billing domain\n',
  'docs/specs/api/billing/s02_errors.md': '# S-02 — Billing errors\n',
  'docs/specs/api/billing/s07_sequence.md': '# S-07 — Billing sequence\n',
  'docs/specs/orphan/s01_architecture.md': '# S-01 — Orphan\n',
  'docs/specs/two/s01_architecture.md': '# S-01 — Two owners\n',
  'docs/specs/ghost/s01_architecture.md': '# S-01 — Ghost\n',
  'docs/specs/schema.dbml': 'Table t {}\n',
  'docs/specs/architecture/caching.md': '''
---
name: Caching
applies_to:
  - api/auth/
  - api/billing/
---

# Caching
''',
  'docs/specs/architecture/caching.schema.json': '{}\n',
};

/// Two legacy projects in one repository: the root and `example-app/`.
final nestedLegacy = <String, String>{
  'docs/prds/d01_context.md': '# D-01 — Root context\n',
  'docs/prds/features/f01_login/FEATURE.md': '# F-01 — Login\n',
  'example-app/docs/prds/d01_context.md': '# D-01 — App context\n',
  'example-app/docs/prds/features/f01_cart/FEATURE.md': '# F-01 — Cart\n',
};

/// Writes [files] under a new temp folder and commits them in a git repo.
Future<Directory> gitFixture(Map<String, String> files) async {
  final root = await writeTree(files);
  expect(git(root, ['init', '-q']).exitCode, 0);
  expect(git(root, ['config', 'user.name', 't']).exitCode, 0);
  expect(git(root, ['config', 'user.email', 't@t']).exitCode, 0);
  expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
  commitAll(root, 'legacy');
  return root;
}
