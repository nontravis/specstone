import 'package:test/test.dart';

final _yamlKeyLine = RegExp(r'^[a-z_]+:(?: |$)', multiLine: true);

/// Fails when [text] holds a line that reads as a YAML key.
void expectNoYamlKeyLine(String? text, {String? reason}) {
  expect(text ?? '', isNot(contains(_yamlKeyLine)), reason: reason);
}
