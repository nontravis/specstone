import 'package:specstone_core/src/index_query/sync_task_closes.dart';
import 'package:test/test.dart';

const _candidates = {'ENG-40', 'ENG-41', 'ENG-42'};

void main() {
  test(
    'closes the candidates a keyword or command form names, and no mention',
    () {
      const cases = <String, Set<String>>{
        'Fixes ENG-42': {'ENG-42'},
        'fixes ENG-42.': {'ENG-42'},
        'CLOSED: ENG-42': {'ENG-42'},
        'resolve\tENG-42': {'ENG-42'},
        'Fixes ENG-40, ENG-41, and ENG-42.': {'ENG-40', 'ENG-41', 'ENG-42'},
        'Closes ENG-40 and ENG-41': {'ENG-40', 'ENG-41'},
        'Fixes ENG-40 so ENG-42 can start': {'ENG-40'},
        'Fixes the parser so ENG-42 can start': <String>{},
        'ENG-42 #resolve': {'ENG-42'},
        'ENG-42 #done': {'ENG-42'},
        'ENG-42 later #Fixed': {'ENG-42'},
        'ENG-42 #donezo': <String>{},
        'Fixes ENG-421': <String>{},
        'Fixes XENG-42': <String>{},
        'Fixes eng-42': <String>{},
        'Fixes ENG-42_a': <String>{},
        'See ENG-42 for the closing plan': <String>{},
        'Prefix fix ENG-42': {'ENG-42'},
        'pre-fix ENG-42': <String>{},
        'Fixing ENG-42': <String>{},
        'Fixes ENG-99': <String>{},
        'Fixes\nENG-42': <String>{},
        'Fixes ENG-40\nENG-42 stays a mention': {'ENG-40'},
      };
      for (final MapEntry(key: message, value: closed) in cases.entries) {
        expect(closedTasks(message, _candidates), closed, reason: message);
      }
    },
  );
}
