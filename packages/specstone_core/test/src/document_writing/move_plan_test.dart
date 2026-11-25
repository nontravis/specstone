import 'package:specstone_core/src/document_writing/move_plan.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:test/test.dart';

Matcher _argumentInvalid(String message) => isA<IndexFault>()
    .having((fault) => fault.code, 'code', IndexFaultCode.argumentInvalid)
    .having((fault) => fault.message, 'message', contains(message));

void main() {
  test('a new line reads a group slug', () {
    final plan = parseMovePlan('new feature --slug garden/herbs', path: 'p');

    expect((plan.lines.single as NewLine).slug, 'garden/herbs');
  });

  test('plan reads source, new, move, and keep lines', () {
    final plan = parseMovePlan(
      [
        'source feature:login abcdef012345',
        'new feature --slug account',
        'new user_story --parent feature:account --slug reset',
        'user_story:login/reset -> feature:account',
        'fr:login/reset/a -> top',
        'user_story:login/signin keep',
      ].join('\n'),
      path: 'plan.txt',
    );

    expect(plan.path, 'plan.txt');
    expect(plan.lines, hasLength(6));
    final source = plan.lines[0] as SourceLine;
    expect(source.lineNumber, 1);
    expect(source.address.typeId, 'feature');
    expect(source.address.body, 'login');
    expect(source.hash, 'abcdef012345');
    final created = plan.lines[1] as NewLine;
    expect(created.docType, 'feature');
    expect(created.parent, isNull);
    expect(created.slug, 'account');
    final story = plan.lines[2] as NewLine;
    expect(story.parent?.docPart, 'feature:account');
    expect(story.slug, 'reset');
    final moved = plan.lines[3] as MoveLine;
    expect(moved.lineNumber, 4);
    expect(moved.unit.docPart, 'user_story:login/reset');
    expect(moved.destination?.docPart, 'feature:account');
    final toTop = plan.lines[4] as MoveLine;
    expect(toTop.destination, isNull);
    final kept = plan.lines[5] as KeepLine;
    expect(kept.unit.docPart, 'user_story:login/signin');
  });

  test('blank and comment lines are skipped', () {
    final plan = parseMovePlan(
      '# header\n\n   \n  # indented\nuser_story:a/b keep\n',
      path: 'plan.txt',
    );

    expect(plan.lines, hasLength(1));
    expect(plan.lines.single.lineNumber, 5);
  });

  test('plan text with CRLF endings reads as LF', () {
    final plan = parseMovePlan(
      'user_story:a/b keep\r\nuser_story:a/c -> feature:d\r\n',
      path: 'plan.txt',
    );

    expect(plan.lines, hasLength(2));
    expect((plan.lines[1] as MoveLine).destination?.body, 'd');
  });

  test('a bad part after a valid group part is refused naming the part', () {
    for (final MapEntry(key: slug, value: named) in {
      'garden/Bad': 'Bad is no slug',
      'garden/': 'part 2 of --slug "garden/" is empty',
    }.entries) {
      expect(
        () => parseMovePlan('new feature --slug $slug\n', path: 'plan.txt'),
        throwsA(_argumentInvalid('plan.txt:1: ')),
        reason: slug,
      );
      expect(
        () => parseMovePlan('new feature --slug $slug\n', path: 'plan.txt'),
        throwsA(_argumentInvalid(named)),
        reason: slug,
      );
    }
  });

  test('unreadable line is argument_invalid with path and line', () {
    for (final text in [
      'user_story:a/b',
      'user_story:a/b -> ',
      'user_story:a/b -> x y',
      'user_story:a/b stay',
      'source feature:login nothex',
      'source feature:login',
      'new',
      'new feature --parent',
      'new feature --colour red',
      'new feature --slug Bad',
      'source feature:login#spec abcdef012345',
      'new user_story --parent feature:login#spec --slug x',
      'user_story:a/b -> feature:c#spec',
      'user_story:a# keep',
      'user_story:a# -> feature:c',
      '-> -> feature:c',
      'top keep',
      'keep -> feature:c',
      'user_story:a/b -> keep',
      'user_story:a/b -> new',
      'user_story:a/b -> source',
    ]) {
      expect(
        () => parseMovePlan('# ok\n$text\n', path: 'dir/plan.txt'),
        throwsA(_argumentInvalid('dir/plan.txt:2: ')),
        reason: text,
      );
    }
  });

  test(
    'one unit on two lines with different instructions names both lines',
    () {
      expect(
        () => parseMovePlan(
          'user_story:a/b -> feature:c\n# gap\nuser_story:a/b keep\n',
          path: 'plan.txt',
        ),
        throwsA(
          isA<IndexFault>()
              .having(
                (fault) => fault.code,
                'code',
                IndexFaultCode.argumentInvalid,
              )
              .having(
                (fault) => fault.message,
                'message',
                startsWith('plan.txt:3: '),
              )
              .having((fault) => fault.message, 'message', contains('line 1')),
        ),
      );
    },
  );

  test('same instruction twice counts once', () {
    final plan = parseMovePlan(
      'user_story:a/b -> feature:c\nuser_story:a/b -> feature:c\n',
      path: 'plan.txt',
    );

    expect(plan.lines, hasLength(1));
    expect(plan.lines.single.lineNumber, 1);
  });

  test('keyed unit line reads its suffix into the unit section key', () {
    final plan = parseMovePlan('fr:a/b#spec/key -> feature:c\n', path: 'p.txt');

    final unit = (plan.lines.single as MoveLine).unit;
    expect(unit.docPart, 'fr:a/b');
    expect(unit.sectionKey, 'spec/key');
  });
}
