import 'package:specstone_core/src/doc_model/check_sentences.dart';
import 'package:specstone_core/src/doc_model/sentence_measure.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

const _charCap = 100;

void main() {
  test('hyphenated word and code span count one word', () {
    expect(measureSentence('600-character').words, 1);
    expect(measureSentence('`a three word span`').words, 1);
    expect(measureSentence('[two words](x.md)').words, 2);
    expect(
      measureSentence(
        'Use 600-character with `a b c` and [link text](a.md) here',
      ).words,
      8,
    );
  });

  test('dash arrow pipe count no word', () {
    expect(measureSentence('— → |').words, 0);
    expect(measureSentence('one — two → three | four').words, 4);
  });

  test('thai tone and am marks add none', () {
    final tone = measureSentence('ต้อง');
    expect(tone.language, 'th');
    expect(tone.countsChars, isTrue);
    expect((tone.chars, tone.runs), (3, 0));
    expect(measureSentence('ทำ').chars, 1);
    expect(measureSentence('ຂໍ້ຄຳ').chars, 2);
  });

  test('latin word in thai weighs cap over 25', () {
    final latin = measureSentence('ใช้ check ทุกครั้ง');
    expect((latin.chars, latin.runs), (7, 1));
    expect(weightedChars(latin, _charCap), 11);
    final span = measureSentence('ใช้ `check` ทุกครั้ง');
    expect((span.chars, span.runs), (7, 1));
    expect(weightedChars(span, _charCap), 11);
  });

  test('weighted chars round the runs up', () {
    final measure = measureSentence('ใช้ check ทุกครั้ง');
    expect(weightedChars(measure, 60), 10);
    expect(weightedChars(measure, 45), 7 + 2);
  });

  test('kana takes ja and han alone takes zh', () {
    expect(measureSentence('これは日本語です').language, 'ja');
    expect(measureSentence('カタカナ').language, 'ja');
    expect(measureSentence('中文句子').language, 'zh');
    expect(measureSentence('中文句子').countsChars, isTrue);
    expect(measureSentence('漢字 ひら').language, 'ja');
  });

  test('korean with latin terms takes ko', () {
    final words = [...List.filled(17, '한국어'), 'API', 'CLI', 'SDK'];
    final measure = measureSentence(words.join(' '));
    expect(measure.language, 'ko');
    expect(measure.countsChars, isFalse);
    expect(measure.words, 20);
    expect(measureSentence('한 API CLI SDK commands').language, 'ko');
  });

  test('lao takes the default chars entry', () {
    final measure = measureSentence('ຂໍ້ຄວາມພາສາລາວ');
    expect(measure.language, 'lo');
    expect(measure.countsChars, isTrue);
    expect(builtInSentenceChars.capFor(measure.language), 100);
  });

  test('japanese full stop with no space cuts two', () {
    final sentences = checkSentencesOf('これは文です。これも文です。');
    expect(sentences, hasLength(2));
    for (final sentence in sentences) {
      expect(measureSentence(sentence.text).language, 'ja');
    }
  });

  test('thai spaces with no stop stay one sentence', () {
    final sentences = checkSentencesOf('ใช้ คำสั่ง นี้ ทุกครั้ง');
    expect(sentences, hasLength(1));
    expect(measureSentence(sentences.single.text).language, 'th');
  });

  test('code span letters take no vote', () {
    final measure = measureSentence('Run `ตรวจสอบ` first');
    expect(measure.language, 'default');
    expect(measure.countsChars, isFalse);
    expect(measure.words, 3);
    final onlySpan = measureSentence('`ตรวจสอบ`');
    expect(onlySpan.language, 'default');
    expect(onlySpan.words, 1);
  });

  test('thai code span in thai counts as one run', () {
    final measure = measureSentence('ใช้ `ตรวจสอบ` ทุกครั้ง');
    expect(measure.language, 'th');
    expect((measure.chars, measure.runs), (7, 1));
    expect(weightedChars(measure, _charCap), 11);
  });

  test('arabic sentence with latin terms takes ar', () {
    final measure = measureSentence('هذا الجهاز with the CLI and `API` tools');
    expect(measure.language, 'ar');
    expect(measure.countsChars, isFalse);
    expect(measure.words, 8);
  });

  test('bidi marks count no word', () {
    expect(measureSentence('مرحبا \u200F بالعالم').words, 2);
    expect(measureSentence('\u200F \u200E').words, 0);
  });

  test('each word script takes its language', () {
    expect(measureSentence('यह एक वाक्य है').language, 'hi');
    expect(measureSentence('αυτό είναι μια πρόταση').language, 'el');
    expect(measureSentence('זה משפט קצר').language, 'he');
    expect(measureSentence('это длинное предложение').language, 'default');
  });

  test('tie goes to the first letter script', () {
    expect(measureSentence('אב يب').language, 'he');
    expect(measureSentence('يب אב').language, 'ar');
    expect(measureSentence('กข ກຂ').language, 'th');
    expect(measureSentence('ກຂ กข').language, 'lo');
  });

  test('more letters of a script beat an earlier one', () {
    expect(measureSentence('אב يبتث').language, 'ar');
    expect(measureSentence('ກ กขค').language, 'th');
  });

  test('link text votes and its address does not', () {
    expect(measureSentence('[ใช้ตรวจสอบ](ตรวจ.md)').chars, 9);
    expect(measureSentence('See [docs](https://x.test/a_(b)) now').words, 3);
  });

  test('bold and italic marks drop', () {
    expect(measureSentence('**bold** and _it_ and *em* too').words, 6);
    expect(measureSentence('**ต้อง**').chars, 3);
    expect(measureSentence('snake_case stays').words, 2);
  });

  test('blank sentence measures zero', () {
    for (final blank in ['', '   ', '\t\n']) {
      final measure = measureSentence(blank);
      expect(measure.language, 'default');
      expect(measure.countsChars, isFalse);
      expect((measure.words, measure.chars, measure.runs), (0, 0, 0));
      expect(weightedChars(measure, _charCap), 0);
    }
    expect(measureSentence('`only`').words, 1);
  });

  test('language codes name a key of their cap map', () {
    const samples = [
      'plain English',
      '한국어 문장',
      'هذا اختبار',
      'זה משפט',
      'यह वाक्य',
      'αυτό είναι',
      'ใช้ทุกครั้ง',
      'ຂໍ້ຄວາມ',
      'ភាសាខ្មែរ',
      'မြန်မာစာ',
      '中文',
      'ひらがな',
    ];
    for (final sample in samples) {
      final measure = measureSentence(sample);
      final languages = measure.countsChars
          ? sentenceCharLanguages
          : sentenceWordLanguages;
      expect(languages, contains(measure.language), reason: sample);
    }
  });

  test('a noncharacter in the text counts no word', () {
    expect(measureSentence('one \uFDD0 two').words, 2);
  });
}
