import 'package:specstone/src/console.dart';
import 'package:test/test.dart';

void main() {
  test('an injected input is never a terminal', () {
    expect(SystemConsole(input: Stream.empty()).stdinIsTerminal, isFalse);
  });
}
