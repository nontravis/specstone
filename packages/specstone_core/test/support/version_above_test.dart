// D18: tests need a stamp above the running version; a literal breaks once the
// CLI reaches it, so one helper derives it from specstoneVersion.
import 'package:specstone_core/src/version.dart';
import 'package:specstone_test_support/specstone_test_support.dart';
import 'package:test/test.dart';

void main() {
  test('gives the next major of a version, pre-release dropped', () {
    expect(versionAbove('2.1.0-dev.2'), '3.0.0');
    expect(versionAbove('2.0.0'), '3.0.0');
  });

  test('gives a higher major than the running version', () {
    final running = int.parse(specstoneVersion.split('.').first);
    final above = int.parse(versionAbove(specstoneVersion).split('.').first);

    expect(above, greaterThan(running));
  });
}
