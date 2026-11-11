import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

/// The cmdlets the install scripts call, by their module in Windows
/// PowerShell 5.1.
const _cmdletsOf = <String, List<String>>{
  'Microsoft.PowerShell.Core': [
    'Get-Command',
    'Import-Module',
    'ForEach-Object',
    'Where-Object',
    'Out-Null',
    'Set-StrictMode',
  ],
  'Microsoft.PowerShell.Management': [
    'Copy-Item',
    'Get-ChildItem',
    'Get-Content',
    'Get-Item',
    'Get-Process',
    'Join-Path',
    'Move-Item',
    'New-Item',
    'Remove-Item',
    'Split-Path',
    'Test-Path',
  ],
  'Microsoft.PowerShell.Utility': [
    'Add-Type',
    'Get-FileHash',
    'Invoke-WebRequest',
    'New-Object',
    'Remove-Variable',
    'Select-Object',
    'Write-Host',
  ],
  'Microsoft.PowerShell.Archive': ['Expand-Archive'],
  'CimCmdlets': ['Get-CimInstance'],
};

final Map<String, String> _moduleOf = {
  for (final MapEntry(key: module, value: cmdlets) in _cmdletsOf.entries)
    for (final cmdlet in cmdlets) cmdlet: module,
};

const _core = 'Microsoft.PowerShell.Core';

void main() {
  for (final (name, story) in [
    ('install.ps1', 'us01'),
    ('uninstall.ps1', 'us03'),
  ]) {
    group('f09/$story: $name', () {
      final lines = File('${repoRoot().path}/$name').readAsLinesSync();
      final code = [
        for (final line in lines)
          if (!line.trimLeft().startsWith('#')) line,
      ].join('\n');
      final defined = {
        for (final match in RegExp(
          'function ([A-Za-z]+-[A-Za-z]+)',
        ).allMatches(code))
          match[1]!,
      };
      final called = {
        for (final match in RegExp(
          r'(?<![\w$.\-])([A-Z][A-Za-z]+-[A-Z][A-Za-z]+)\b',
        ).allMatches(code))
          match[1]!,
      }..removeAll(defined);
      final imported = [
        for (final line in lines)
          if (line.trimLeft().startsWith('Import-Module -Name '))
            ...line
                .trimLeft()
                .substring('Import-Module -Name '.length)
                .split(',')
                .map((module) => module.trim()),
      ];

      test('knows the module of every cmdlet it calls', () {
        // A new cmdlet needs its 5.1 module added to the table above.
        expect(
          called.where((cmdlet) => !_moduleOf.containsKey(cmdlet)),
          isEmpty,
        );
      });

      test('imports by name every module a cmdlet it calls comes from', () {
        final needed = {
          for (final cmdlet in called)
            if (_moduleOf[cmdlet] case final module? when module != _core)
              module,
        };

        expect(imported, unorderedEquals(needed));
      });

      test('imports them before its first function', () {
        final import = lines.indexWhere(
          (line) => line.trimLeft().startsWith('Import-Module -Name '),
        );
        final function = lines.indexWhere(
          (line) => line.trimLeft().startsWith('function '),
        );

        expect(import, isNonNegative);
        expect(import, lessThan(function));
      });
    });
  }
}
