import 'package:specstone_core/src/doc_model/name_mentions.dart';
import 'package:test/test.dart';

void main() {
  group('nameMentionsInMarkdown', () {
    test('doc_model RULE-11: a code span of a name or a typed name is a '
        'mention, its section key kept apart', () {
      final mentions = nameMentionsInMarkdown(
        'See `feature:login#goal` and `login/email_login`.\n',
      );
      expect(
        [for (final m in mentions) (m.line, m.column, m.text)],
        [(1, 5, 'feature:login#goal'), (1, 30, 'login/email_login')],
      );
      expect(mentions.first.address.typeId, 'feature');
      expect(mentions.first.address.body, 'login');
      expect(mentions.first.address.sectionKey, 'goal');
    });

    test('doc_model RULE-11: a bare one-slug span is no mention', () {
      expect(nameMentionsInMarkdown('Say `login` or `user_id`.\n'), isEmpty);
    });

    test('doc_model RULE-11: a span inside fenced code is no mention', () {
      expect(
        nameMentionsInMarkdown(
          'Run:\n\n```sh\necho `login/email_login`\n```\n\n'
          '`login/email_login`\n',
        ).map((m) => m.line),
        [7],
      );
    });

    test('doc_model RULE-11: a span of prose text or a plain name is no '
        'mention', () {
      expect(
        nameMentionsInMarkdown(
          '`check architecture:login` and login/email_login\n',
        ),
        isEmpty,
      );
    });

    test('doc_model RULE-11: each line is read alone, so a span split across '
        'two lines is no mention', () {
      expect(nameMentionsInMarkdown('`login/\nemail_login`\n'), isEmpty);
    });

    test('doc_model RULE-11: a double-backtick span is read by its text, its '
        'column after the opening run', () {
      final mentions = nameMentionsInMarkdown('x ``login/email_login`` y\n');
      expect(
        [for (final m in mentions) (m.column, m.text)],
        [(4, 'login/email_login')],
      );
    });

    test('doc_model RULE-11: a backslash-escaped backtick opens no span, so '
        'no mention', () {
      expect(
        nameMentionsInMarkdown('Write \\`login/email_login\\` as is.\n'),
        isEmpty,
      );
    });
  });
}
