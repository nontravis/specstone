import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

const _base = 'https://raw.githubusercontent.com/nontravis/specstone/main';
const _shellLine = 'curl -fsSL $_base/uninstall.sh | sh';
const _powershellLine = 'irm $_base/uninstall.ps1 | iex';

List<String> _linesOf(String path) => const LineSplitter().convert(
  File('${repoRoot().path}/$path').readAsStringSync(),
);

void main() {
  test('the README gives the shell uninstall line for macOS and Linux and the '
      'PowerShell line for Windows', () {
    final lines = _linesOf('README.md');

    expect(lines.where((line) => line == _shellLine), hasLength(1));
    expect(lines.where((line) => line == _powershellLine), hasLength(1));
  });

  test('each uninstall script names the line that runs it', () {
    expect(_linesOf('uninstall.sh'), contains('#   $_shellLine'));
    expect(_linesOf('uninstall.ps1'), contains('#   $_powershellLine'));
  });
}
