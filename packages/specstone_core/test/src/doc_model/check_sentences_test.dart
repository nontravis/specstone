import 'package:specstone_core/src/doc_model/check_sentences.dart';
import 'package:test/test.dart';

List<CheckSentence> _plain(List<String> texts) => [
  for (final text in texts) (text: text, isHeading: false),
];

void main() {
  test('semicolon outside holders cuts a clause', () {
    expect(
      checkSentencesOf('A rule holds; another rule holds'),
      _plain(['A rule holds;', 'another rule holds']),
    );
    expect(
      checkSentencesOf('One；two؛three'),
      _plain(['One；', 'two؛', 'three']),
    );
  });

  test('semicolon in parentheses code span or link cuts nothing', () {
    expect(
      checkSentencesOf('A trace group (a; b) ends the item'),
      _plain(['A trace group (a; b) ends the item']),
    );
    expect(
      checkSentencesOf('Keep `a; b` whole and [x; y](z) too'),
      _plain(['Keep `a; b` whole and [x; y](z) too']),
    );
    expect(
      checkSentencesOf('A rule (nested (a); b) holds; next'),
      _plain(['A rule (nested (a); b) holds;', 'next']),
    );
  });

  test('code span holds every stop', () {
    expect(
      checkSentencesOf('Quote `a.b` and `?` and `。` and `a; b` once.'),
      _plain(['Quote `a.b` and `?` and `。` and `a; b` once.']),
    );
    expect(
      checkSentencesOf('Value ``a. b`` here. Next one.'),
      _plain(['Value ``a. b`` here.', 'Next one.']),
    );
  });

  test('link holds every stop', () {
    expect(
      checkSentencesOf('See [a. b](x.md) now. Then more.'),
      _plain(['See [a. b](x.md) now.', 'Then more.']),
    );
    expect(
      checkSentencesOf('See [a](x.md#e. 1) and [`b]`. c](y) now.'),
      _plain(['See [a](x.md#e. 1) and [`b]`. c](y) now.']),
    );
  });

  test('other script stops cut with no space', () {
    expect(checkSentencesOf('一つ目。二つ目！三つ目？'), _plain(['一つ目。', '二つ目！', '三つ目？']));
    expect(
      checkSentencesOf('एक।दो ثلاثة؟أربعة တစ်။နှစ် ១។២'),
      _plain(['एक।', 'दो ثلاثة؟', 'أربعة တစ်။', 'နှစ် ១។', '២']),
    );
    expect(checkSentencesOf('えっ！？本当。。次'), _plain(['えっ！？', '本当。。', '次']));
  });

  test('space arrow colon and dash cut nothing', () {
    expect(
      checkSentencesOf('E19 — A trigger → a response: done'),
      _plain(['E19 — A trigger → a response: done']),
    );
    expect(
      checkSentencesOf('Version 1.2 is out'),
      _plain(['Version 1.2 is out']),
    );
    expect(
      checkSentencesOf('First. Second? Third!'),
      _plain(['First.', 'Second?', 'Third!']),
    );
  });

  test('heading end cuts and is marked', () {
    expect(checkSentencesOf('### Scenario title\nThe body holds.'), [
      (text: 'Scenario title', isHeading: true),
      (text: 'The body holds.', isHeading: false),
    ]);
    expect(checkSentencesOf('### First. Second\n- item'), [
      (text: 'First.', isHeading: false),
      (text: 'Second', isHeading: true),
      (text: 'item', isHeading: false),
    ]);
  });

  test('blank text has no sentence', () {
    expect(checkSentencesOf(''), isEmpty);
    expect(checkSentencesOf('  \n'), isEmpty);
  });
}
