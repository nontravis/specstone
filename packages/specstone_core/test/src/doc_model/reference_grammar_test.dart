import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:test/test.dart';

/// A default no test asserts on: lets `anchor: null` differ from "unchecked".
const _sentinel = Object();

void main() {
  group('readDocAddress', () {
    void check(
      String text, {
      String? typeId,
      required String body,
      String? sectionKey,
      bool name = false,
      bool referenceWithoutLookup = false,
    }) {
      test('reads $text', () {
        final address = readDocAddress(text);
        expect(address.typeId, typeId);
        expect(address.body, body);
        expect(address.sectionKey, sectionKey);
        expect(address.isName, name);
        expect(address.isReferenceWithoutLookup, referenceWithoutLookup);
      });
    }

    check('gnfr', typeId: null, body: 'gnfr', name: true);
    check('gnfr#_lead', body: 'gnfr', sectionKey: '_lead', name: true);
    check(
      'gnfr:gnfr#performance',
      typeId: 'gnfr',
      body: 'gnfr',
      sectionKey: 'performance',
      name: true,
      referenceWithoutLookup: true,
    );
    check(
      'login/email_login',
      body: 'login/email_login',
      name: true,
      referenceWithoutLookup: true,
    );
    check(
      'user_story:login/email_login',
      typeId: 'user_story',
      body: 'login/email_login',
      name: true,
      referenceWithoutLookup: true,
    );
    check('prds/GNFR.md', body: 'prds/GNFR.md', name: false);
    check('docs/prds/GNFR.md', body: 'docs/prds/GNFR.md', name: false);
    check(
      'feature:prds/features/f01_login/FEATURE.md',
      typeId: 'feature',
      body: 'prds/features/f01_login/FEATURE.md',
      name: false,
    );
    check('gnfr#', body: 'gnfr', sectionKey: '', name: true);
    check('#x', body: '', sectionKey: 'x');

    test('a Name may hold 2 or more slugs, and a one-slug Name marks a '
        'reference only when typed (R62)', () {
      expect(
        readDocAddress('feature:index_query').isReferenceWithoutLookup,
        isTrue,
      );
      expect(
        readDocAddress('affiliate_module/profile').isReferenceWithoutLookup,
        isTrue,
      );
      expect(
        readDocAddress('fr:index_query/read_doc_section/resolve_doc_name')
            .isReferenceWithoutLookup,
        isTrue,
      );
      expect(readDocAddress('user_id').isReferenceWithoutLookup, isFalse);
      expect(readDocAddress('doc_model.dart').isName, isFalse);
      expect(readDocAddress('parseDoc()').isName, isFalse);
    });

    test('docPart drops any section key', () {
      expect(readDocAddress('gnfr:gnfr#performance').docPart, 'gnfr:gnfr');
      expect(readDocAddress('login/email_login').docPart, 'login/email_login');
      expect(readDocAddress('gnfr#_lead').docPart, 'gnfr');
    });
  });

  group('readItemId', () {
    test('reads plain digits after the prefix', () {
      final id = readItemId('RULE-7 x', 'RULE-');
      expect(id, isA<ItemId>());
      expect(id!.prefix, 'RULE-');
      expect(id.digits, '7');
      expect(id.written, 'RULE-7');
      expect((id as ItemId).number, BigInt.from(7));
    });

    test('reads past one optional **', () {
      final id = readItemId('**RULE-7** x', 'RULE-');
      expect(id!.written, 'RULE-7');
    });

    test('a letter after the digits reads as a LetteredId, not an ItemId', () {
      final id = readItemId('RULE-7a x', 'RULE-');
      expect(id, isA<LetteredId>());
      expect(id!.prefix, 'RULE-');
      expect(id.digits, '7');
      expect(id.written, 'RULE-7a');
      expect((id as LetteredId).letters, 'a');
    });

    test('a digit after the digits stays in the digits', () {
      final id = readItemId('RULE-12', 'RULE-');
      expect(id, isA<ItemId>());
      expect(id!.digits, '12');
    });

    test('an underscore after the digits ends them', () {
      final id = readItemId('RULE-7_x', 'RULE-');
      expect(id, isA<ItemId>());
      expect(id!.digits, '7');
    });

    test('no digit after the prefix reads as null', () {
      expect(readItemId('RULE- x', 'RULE-'), isNull);
    });

    test('a letter in the prefix position reads as null', () {
      // NFR-P03 with prefix NFR- holds a letter P before the digits.
      expect(readItemId('NFR-P03', 'NFR-'), isNull);
    });
  });

  group('readScenarioHeading', () {
    test('reads ### Scenario <N>', () {
      final id = readScenarioHeading('### Scenario 6 — x');
      expect(id, isA<ItemId>());
      expect(id!.prefix, 'Scenario ');
      expect(id.digits, '6');
      expect((id as ItemId).number, BigInt.from(6));
    });

    test('a lettered scenario number reads as a LetteredId', () {
      final id = readScenarioHeading('### Scenario 6a — x');
      expect(id, isA<LetteredId>());
      expect(id!.written, 'Scenario 6a');
    });

    test('a heading with no text still reads', () {
      final id = readScenarioHeading('### Scenario 10');
      expect(id, isA<ItemId>());
      expect(id!.digits, '10');
    });

    test('#### Scenario 6 reads as null; only ### opens a scenario', () {
      expect(readScenarioHeading('#### Scenario 6'), isNull);
    });

    test('no digit after the prefix reads as null', () {
      expect(readScenarioHeading('### Scenario x'), isNull);
    });
  });

  group('nextFreeIds', () {
    test('RULE-12: digits past 64 bits read and count without a throw', () {
      final ids = [
        readItemId('RULE-1234567890123456789012345', 'RULE-')!,
        readItemId('RULE-3a', 'RULE-')!,
        readItemId('RULE-4b', 'RULE-')!,
      ];

      expect(nextFreeIds(ids), {
        1: 'RULE-1234567890123456789012346',
        2: 'RULE-1234567890123456789012347',
      });
    });

    test('RULE-12 example: highest S7, then S6a and S6b give S8 and S9', () {
      final ids = [
        readScenarioHeading('### Scenario 6')!,
        readScenarioHeading('### Scenario 7')!,
        readScenarioHeading('### Scenario 6a')!,
        readScenarioHeading('### Scenario 6b')!,
      ];
      expect(nextFreeIds(ids), {2: 'Scenario 8', 3: 'Scenario 9'});
    });

    test('check_item_ids E05: RULE-7a under highest RULE-30 gets RULE-31', () {
      final ids = [
        readItemId('**RULE-30** Rule text', 'RULE-')!,
        readItemId('**RULE-7a** Rule text', 'RULE-')!,
      ];
      expect(nextFreeIds(ids), {1: 'RULE-31'});
    });

    test('check_item_ids E06: Scenario 6a under highest Scenario 8 gets '
        'Scenario 9', () {
      final ids = [
        readScenarioHeading('### Scenario 8')!,
        readScenarioHeading('### Scenario 6a — [edge] Renew early')!,
      ];
      expect(nextFreeIds(ids), {1: 'Scenario 9'});
    });

    test('each prefix counts only its own; zero-pad to the highest digits '
        'count', () {
      final ids = [
        readItemId('BR-9', 'BR-')!,
        readItemId('PV-099', 'PV-')!,
        readItemId('BR-10a', 'BR-')!,
        readItemId('PV-100a', 'PV-')!,
      ];
      expect(nextFreeIds(ids), {2: 'BR-10', 3: 'PV-100'});
    });

    test('FR-09 with one lettered FR-03a gives FR-10', () {
      final ids = [readItemId('FR-09', 'FR-')!, readItemId('FR-03a', 'FR-')!];
      expect(nextFreeIds(ids), {1: 'FR-10'});
    });
  });

  group('readScenarioRef', () {
    test('reads S<N> of the own story', () {
      final ref = readScenarioRef('S1');
      expect(ref, isNotNull);
      expect(ref!.number.digits, '1');
      expect(ref.number.prefix, 'S');
      expect(ref.storyName, isNull);
      expect(ref.scenario, BigInt.from(1));
      expect(ref.label, 'S1');
    });

    test('S6a reads; its number names no scenario', () {
      final ref = readScenarioRef('S6a');
      expect(ref, isNotNull);
      expect(ref!.number, isA<LetteredId>());
      expect(ref.scenario, isNull);
      expect(ref.label, 'S6a');
    });

    test('reads <story Name>#S<N> of another story', () {
      final ref = readScenarioRef('login/reset_password#S3');
      expect(ref, isNotNull);
      expect(ref!.storyName, 'login/reset_password');
      expect(ref.scenario, BigInt.from(3));
      expect(ref.label, 'login/reset_password#S3');
    });

    test('Scenario 2 reads as null; only S<N> is a scenario ref', () {
      expect(readScenarioRef('Scenario 2'), isNull);
    });

    test('login# reads as null; the story part is a Name', () {
      expect(readScenarioRef('login#'), isNull);
    });

    test('#S3 reads as null; no empty story name', () {
      expect(readScenarioRef('#S3'), isNull);
    });

    test('text after the ID reads as null; the ref is the whole text', () {
      expect(readScenarioRef('S1 x'), isNull);
      expect(readScenarioRef('login#S3 tail'), isNull);
    });

    test('a story name holding a space reads as null', () {
      expect(readScenarioRef('login x#S3'), isNull);
    });

    test('an astral-plane letter after the digits reads as a LetteredId', () {
      // U+104B0 DESERET CAPITAL LETTER LONG I: outside the BMP.
      final id = readItemId('FR-9\u{104B0}', 'FR-');
      expect(id, isA<LetteredId>());
      expect((id! as LetteredId).letters, '\u{104B0}');
      expect(readScenarioRef('S9\u{104B0}')!.number, isA<LetteredId>());
    });
  });

  group('readStepTargetValue', () {
    test('reads <story Name> S<N>, one space between', () {
      final ref = readStepTargetValue('login/reset_password S3');
      expect(ref, isNotNull);
      expect(ref!.storyName, 'login/reset_password');
      expect(ref.scenario, BigInt.from(3));
      expect(ref.label, 'login/reset_password#S3');
    });

    test('reads a lettered step number', () {
      final ref = readStepTargetValue('setup_migration/set_up_new_project S1a');
      expect(ref, isNotNull);
      expect(ref!.scenario, isNull);
      expect(ref.label, 'setup_migration/set_up_new_project#S1a');
    });

    test('two spaces read as null', () {
      expect(readStepTargetValue('login/reset_password  S3'), isNull);
    });
  });

  group('readLinkLabel', () {
    test('reads S<N>', () {
      final label = readLinkLabel('S1');
      expect(label, isA<ScenarioLabel>());
      expect((label! as ScenarioLabel).ref.scenario, BigInt.from(1));
      expect(label.written, 'S1');
    });

    test('reads an NFR id', () {
      final label = readLinkLabel('NFR-P01');
      expect(label, isA<NfrLabel>());
      expect((label! as NfrLabel).id, 'NFR-P01');
      expect(label.written, 'NFR-P01');
    });

    test('reads an FR ref, a Name of 2 or more slugs', () {
      final label = readLinkLabel('login/email_login');
      expect(label, isA<FrRefLabel>());
      expect((label! as FrRefLabel).name, 'login/email_login');
    });

    test('reads a deeper FR ref and other NFR ids', () {
      expect(
        (readLinkLabel('cart/add_item/check_stock')! as FrRefLabel).name,
        'cart/add_item/check_stock',
      );
      expect((readLinkLabel('NFR-P01')! as NfrLabel).id, 'NFR-P01');
    });

    test('an astral-plane letter in an NFR id reads as an NfrLabel', () {
      // U+10428 DESERET SMALL LETTER LONG I: outside the BMP.
      expect(readLinkLabel('NFR-\u{10428}01'), isA<NfrLabel>());
    });

    test('reads <story Name>#S<N>', () {
      final label = readLinkLabel('login/reset_password#S3');
      expect(label, isA<ScenarioLabel>());
      expect((label! as ScenarioLabel).ref.storyName, 'login/reset_password');
    });

    test('a one-slug name reads as null', () {
      expect(readLinkLabel('login'), isNull);
    });

    test('NFR- with no letters reads as null', () {
      expect(readLinkLabel('NFR-01'), isNull);
    });

    test('plain digits read as null', () {
      expect(readLinkLabel('01'), isNull);
    });
  });

  group('readLinkTarget', () {
    void check(
      String href, {
      required Matcher form,
      String? scheme,
      List<String>? segments,
      Object? anchor = _sentinel,
    }) {
      test('reads $href', () {
        final target = readLinkTarget(href);
        expect(target, form);
        if (target case SchemeLink()) expect(target.scheme, scheme);
        if (target case RelativeLink()) {
          if (segments != null) expect(target.segments, segments);
          if (!identical(anchor, _sentinel)) expect(target.anchor, anchor);
        }
      });
    }

    // R65: a scheme needs a letter first, so these are relative.
    check('1:x.md', form: isA<RelativeLink>(), segments: ['1:x.md']);
    check(':x.md', form: isA<RelativeLink>(), segments: [':x.md']);
    check('HTTP://x/', form: isA<SchemeLink>(), scheme: 'http');
    check('mailto:a@b', form: isA<SchemeLink>(), scheme: 'mailto');
    check('//h/x.md', form: isA<AuthorityLink>());
    check('/x.md', form: isA<RootedLink>());
    check('#a%20b', form: isA<RelativeLink>(), segments: [], anchor: 'a b');
    check(
      'a.md?x=1#sec',
      form: isA<RelativeLink>(),
      segments: ['a.md'],
      anchor: 'sec',
    );
    // RULE-7: a `%` two hex digits do not follow stays as written.
    check('a%zz.md', form: isA<RelativeLink>(), segments: ['a%zz.md']);
    // An escape that is not UTF-8 reads as U+FFFD.
    check('%DB.md', form: isA<RelativeLink>(), segments: ['\u{FFFD}.md']);
    // RULE-7: an encoded slash stays inside its segment, decoded, so one
    // segment `a/b.md`, which `_resolveSegments` then rejects.
    check('a%2Fb.md', form: isA<RelativeLink>(), segments: ['a/b.md']);

    test('a query with no fragment keeps null anchor', () {
      expect(readLinkTarget('a.md?x=1'), isA<RelativeLink>());
      final target = readLinkTarget('a.md?x=1') as RelativeLink;
      expect(target.segments, ['a.md']);
      expect(target.anchor, isNull);
    });

    test('an empty fragment names the doc top (RULE-13)', () {
      final target = readLinkTarget('#') as RelativeLink;
      expect(target.segments, const <String>[]);
      expect(target.anchor, '');
    });

    test('a WHATWG failure is unreadable (RULE-11, E21)', () {
      expect(readLinkTarget('http://h:abc/x.md'), isA<UnreadableLink>());
    });

    test('R65: a missing host, an out-of-range port, and a forbidden host '
        'code point are unreadable', () {
      expect(readLinkTarget('http://'), isA<UnreadableLink>());
      expect(readLinkTarget('http://h:99999/'), isA<UnreadableLink>());
      expect(
        readLinkTarget('https://exa mple.com/x.md'),
        isA<UnreadableLink>(),
      );
    });
  });
}
