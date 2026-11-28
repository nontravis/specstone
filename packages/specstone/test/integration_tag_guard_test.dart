import 'dart:io';

import 'package:specstone_test_support/specstone_test_support.dart';
import 'package:test/test.dart';

import 'helpers/package_root.dart';

/// Test files that run real git or `node` only through `lib/`, each with a
/// one-line reason; never a file that reaches only the atomic-write `chmod`.
const _allowlist = <String, String>{};

/// Appends every entry, one per line, since the matcher truncates long lists.
String _reason(String hint, List<String> entries) =>
    '$hint\n${entries.join('\n')}';

void main() {
  late IntegrationTagReport report;

  setUpAll(() {
    report = scanIntegrationTags(
      packagesRoot: Directory.fromUri(packageRoot().uri.resolve('../')),
      package: 'specstone',
      followedPackages: const ['specstone', 'specstone_core'],
      libraryPackages: const ['specstone_test_support'],
      allowlist: _allowlist,
    );
  });

  test('every test file that spawns in its own code or test/ imports carries '
      'integration', () {
    expect(
      report.untaggedSpawning,
      isEmpty,
      reason: _reason(
        "add 'integration' to @Tags, or split the helper that spawns",
        report.untaggedSpawning,
      ),
    );
  });

  test('no test file carries integration without a spawn unless '
      'allowlisted', () {
    expect(
      report.taggedPure,
      isEmpty,
      reason: _reason(
        'drop the tag, or list the file in _allowlist with why it runs '
        'real git or node through lib/',
        report.taggedPure,
      ),
    );
  });

  test('every allowlist entry names an existing tagged test file', () {
    expect(
      report.staleAllowlist,
      isEmpty,
      reason: _reason(
        'fix or remove the _allowlist entry',
        report.staleAllowlist,
      ),
    );
  });
}
