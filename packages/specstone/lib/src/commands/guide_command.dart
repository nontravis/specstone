import 'dart:convert';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the doc type list, one doc type's writing guide, or its merged
/// schema.
///
/// The only command that resolves templates, so a template fault reaches no
/// other command (INV-11).
class GuideCommand extends SpecstoneCommand {
  new() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print JSON instead of text.',
    );
  }

  static const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

  @override
  String get name => 'guide';

  @override
  String get description =>
      "Print a doc type's writing guide, or list the doc types.";

  @override
  String get invocation => 'specstone guide [type] [--json]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length > 1) {
      usageException('Expected at most one doc type, got ${rest.length}.');
    }
    final runner = this.runner! as SpecstoneCommandRunner;
    final asJson = argResults!.flag('json');

    final MergedSet set;
    try {
      set = runner.templates.resolve(
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
      );
    } on TemplateFault catch (fault) {
      return _fail(runner, fault, asJson: asJson);
    }

    if (rest.isEmpty) {
      runner.out.write(
        asJson ? '${_pretty.convert(set.listJson())}\n' : set.listText(),
      );
      return 0;
    }

    final type = rest.single;
    final docType = set.lookup(type);
    if (docType == null) {
      final message = 'Could not find a doc type named "$type".';
      if (!asJson) usageException(message);
      return _fail(
        runner,
        TemplateFault(FaultCode.docTypeUnknown, message),
        asJson: true,
      );
    }
    runner.out.write(
      asJson ? '${_pretty.convert(docType.toJson())}\n' : docType.renderGuide(),
    );
    return 0;
  }

  /// Writes [fault] to `err` and returns its exit status.
  int _fail(
    SpecstoneCommandRunner runner,
    TemplateFault fault, {
    required bool asJson,
  }) {
    runner.err.writeln(asJson ? jsonEncode(fault.toJson()) : fault.toText());
    return fault.exitStatus;
  }
}
