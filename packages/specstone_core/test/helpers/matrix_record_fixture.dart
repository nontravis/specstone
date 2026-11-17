import 'dart:io';

import 'check_fixture.dart' show loginRecord, writeCheckProject;

/// The one row of the matrix section a record project holds.
const matrixRow = '- email_login/check_password E01: `a wrong password`\n';

/// Writes the check project with a login record that holds a Verification
/// matrix section (unless [hasMatrix] is false) and a `notes` section, and
/// returns its folder.
///
/// The record reads approved, or a draft when [isDraft].
Future<Directory> writeMatrixRecordProject({
  bool isDraft = false,
  bool hasMatrix = true,
}) {
  final frontmatter =
      "---\n${isDraft ? 'draft: true\n' : ''}"
      "statuses:\n  - 'email_login:implemented'\n---\n\n";
  final matrixSection = hasMatrix
      ? '## Verification matrix\n\n$matrixRow\n'
      : '';
  return writeCheckProject(
    extra: {
      loginRecord:
          '$frontmatter# Login implementation\n\n$matrixSection'
          '## Notes\n\nSee the rows.\n',
      '.specstone/templates/implementation.yaml':
          'sections:\n  - id: notes\n    header: Notes\n',
    },
    unstamped: {if (isDraft) loginRecord},
  );
}
