@Tags(['baseline'])
@Timeout(Duration(minutes: 10))
library;

import 'package:test/test.dart';

import '../../specstone_core/test/helpers/shape_matrix.dart'
    show newFindingsOf, unallowedLines, writeCommands;
import 'helpers/baseline_work_tree.dart';

void main() {
  late BaselineWorkTree baselineWork;

  setUpAll(() async {
    baselineWork = await BaselineWorkTree.build();
  });

  // D8: every write command on the baseline tree adds only content waits.
  test(
    'every write command adds only content waits on the baseline tree',
    () async {
      final red = <String>[];
      for (final command in writeCommands) {
        final added = await newFindingsOf(baselineWork.reset(), command);
        red.addAll([
          for (final line in unallowedLines(command, added)) '$command $line',
        ]);
      }
      expect(red, isEmpty);
    },
  );
}
