import 'dart:convert';

import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/shipped_pins.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';

typedef _Source = ({String title, String url, String? locator});

const _asvs = 'https://github.com/OWASP/ASVS/tree/v5.0.0';
const _cheats = 'https://cheatsheetseries.owasp.org/cheatsheets';
const _nistB = 'https://pages.nist.gov/800-63-4/sp800-63b.html';

/// The ten ids of the shipped feature patterns, in code point order.
const _patternIds = <String>[
  'audit_log',
  'auth',
  'crud',
  'file_upload',
  'import_export',
  'notification',
  'payment',
  'role_permission',
  'settings_profile',
  'signup',
];

/// The `reference:` entries the Sources table lists for each pattern.
const _sources = <String, List<_Source>>{
  'auth': [
    (
      title: 'OWASP ASVS 5.0',
      url: _asvs,
      locator:
          'V6 Authentication; V7 Session Management (V7.4 Session Termination)',
    ),
    (
      title: 'OWASP Authentication Cheat Sheet',
      url: '$_cheats/Authentication_Cheat_Sheet.html',
      locator: null,
    ),
    (
      title: 'OWASP Session Management Cheat Sheet',
      url: '$_cheats/Session_Management_Cheat_Sheet.html',
      locator: null,
    ),
    (
      title: 'OWASP Forgot Password Cheat Sheet',
      url: '$_cheats/Forgot_Password_Cheat_Sheet.html',
      locator: null,
    ),
    (title: 'NIST SP 800-63B', url: _nistB, locator: null),
  ],
  'signup': [
    (
      title: 'OWASP ASVS 5.0',
      url: _asvs,
      locator: 'V6.4 Authentication Factor Lifecycle and Recovery',
    ),
    (
      title: 'OWASP Credential Stuffing Prevention Cheat Sheet',
      url: '$_cheats/Credential_Stuffing_Prevention_Cheat_Sheet.html',
      locator: null,
    ),
    (title: 'NIST SP 800-63B', url: _nistB, locator: null),
  ],
  'crud': [
    (title: 'Google AIP-121', url: 'https://google.aip.dev/121', locator: null),
    (
      title: 'Google AIP-131 to AIP-135',
      url: 'https://google.aip.dev/131',
      locator: 'AIP-131 to AIP-135',
    ),
    (
      title: 'Google AIP-158 Pagination',
      url: 'https://google.aip.dev/158',
      locator: null,
    ),
    (
      title: 'Google AIP-164 Soft delete',
      url: 'https://google.aip.dev/164',
      locator: null,
    ),
    (
      title: 'Google AIP-154 Resource freshness validation',
      url: 'https://google.aip.dev/154',
      locator: null,
    ),
    (
      title: 'OWASP Mass Assignment Cheat Sheet',
      url: '$_cheats/Mass_Assignment_Cheat_Sheet.html',
      locator: null,
    ),
    (
      title: 'OWASP IDOR Prevention Cheat Sheet',
      url:
          '$_cheats/'
          'Insecure_Direct_Object_Reference_Prevention_Cheat_Sheet.html',
      locator: null,
    ),
  ],
  'file_upload': [
    (title: 'OWASP ASVS 5.0', url: _asvs, locator: 'V5 File Handling'),
    (
      title: 'OWASP File Upload Cheat Sheet',
      url: '$_cheats/File_Upload_Cheat_Sheet.html',
      locator: null,
    ),
  ],
  'notification': [
    (
      title: 'Apple HIG Notifications',
      url:
          'https://developer.apple.com/design/human-interface-guidelines/'
          'notifications',
      locator: null,
    ),
    (
      title: 'Android notifications',
      url: 'https://developer.android.com/develop/ui/views/notifications',
      locator: null,
    ),
    (
      title: 'RFC 8058',
      url: 'https://www.rfc-editor.org/rfc/rfc8058',
      locator: null,
    ),
  ],
  'role_permission': [
    (title: 'OWASP ASVS 5.0', url: _asvs, locator: 'V8 Authorization'),
    (
      title: 'OWASP Authorization Cheat Sheet',
      url: '$_cheats/Authorization_Cheat_Sheet.html',
      locator: null,
    ),
    (
      title: 'NIST RBAC',
      url: 'https://csrc.nist.gov/projects/role-based-access-control',
      locator: null,
    ),
  ],
  'settings_profile': [
    (
      title: 'OWASP User Privacy Protection Cheat Sheet',
      url: '$_cheats/User_Privacy_Protection_Cheat_Sheet.html',
      locator: null,
    ),
    (
      title: 'GDPR Art. 17',
      url: 'https://gdpr-info.eu/art-17-gdpr/',
      locator: null,
    ),
    (
      title: 'OWASP Mass Assignment Cheat Sheet',
      url: '$_cheats/Mass_Assignment_Cheat_Sheet.html',
      locator: null,
    ),
  ],
  'audit_log': [
    (
      title: 'OWASP ASVS 5.0',
      url: _asvs,
      locator: 'V16 Security Logging and Error Handling',
    ),
    (
      title: 'OWASP Logging Cheat Sheet',
      url: '$_cheats/Logging_Cheat_Sheet.html',
      locator: null,
    ),
    (
      title: 'OWASP Logging Vocabulary Cheat Sheet',
      url: '$_cheats/Logging_Vocabulary_Cheat_Sheet.html',
      locator: null,
    ),
  ],
  'import_export': [
    (
      title: 'RFC 4180',
      url: 'https://www.rfc-editor.org/rfc/rfc4180',
      locator: null,
    ),
    (
      title: 'OWASP CSV Injection',
      url: 'https://owasp.org/www-community/attacks/CSV_Injection',
      locator: null,
    ),
    (
      title: 'GDPR Art. 20',
      url: 'https://gdpr-info.eu/art-20-gdpr/',
      locator: null,
    ),
    (
      title: 'OWASP Input Validation Cheat Sheet',
      url: '$_cheats/Input_Validation_Cheat_Sheet.html',
      locator: null,
    ),
  ],
  'payment': [
    (
      title: 'OWASP Third Party Payment Gateway Integration Cheat Sheet',
      url: '$_cheats/Third_Party_Payment_Gateway_Integration_Cheat_Sheet.html',
      locator: null,
    ),
    (
      title: 'OWASP Transaction Authorization Cheat Sheet',
      url: '$_cheats/Transaction_Authorization_Cheat_Sheet.html',
      locator: null,
    ),
    (
      title: 'Stripe Payment Intents',
      url: 'https://docs.stripe.com/payments/payment-intents',
      locator: null,
    ),
    (
      title: 'Stripe Webhooks',
      url: 'https://docs.stripe.com/webhooks',
      locator: null,
    ),
    (
      title: 'Stripe Idempotent requests',
      url: 'https://docs.stripe.com/api/idempotent_requests',
      locator: null,
    ),
    (
      title: 'Stripe Refunds',
      url: 'https://docs.stripe.com/refunds',
      locator: null,
    ),
    (
      title: 'PCI DSS',
      url: 'https://www.pcisecuritystandards.org/standards/pci-dss/',
      locator: null,
    ),
  ],
};

const _maxItemChars = 160;
final _slug = RegExp(r'^[a-z][a-z0-9_]*$');
final _sentenceBreak = RegExp(r'[.!?](\s|$)');

YamlMap _fileOf(String id) {
  final bytes = shippedPackFiles['software-tech/patterns/$id.yaml'];
  expect(bytes, isNotNull, reason: id);
  return loadYaml(utf8.decode(bytes!)) as YamlMap;
}

List<YamlMap> _itemsOf(String id) => [
  for (final item in _fileOf(id)['items'] as YamlList) item as YamlMap,
];

/// The entries [id]'s own file writes: its list, or `add:` over an `extends`
/// target's list.
List<_Source> _writtenReference(String id) {
  final written = _fileOf(id)['reference'];
  final entries = written is YamlMap ? written['add'] : written;
  return [for (final entry in entries! as YamlList) _sourceOf(entry)];
}

_Source _sourceOf(Object? entry) {
  final map = entry! as YamlMap;
  return (
    title: map['title'] as String,
    url: map['url'] as String,
    locator: map['locator'] as String?,
  );
}

void main() {
  group('software-tech feature patterns', () {
    late MergedSet set;

    setUpAll(() async {
      set = await resolveSoftwareTech();
    });

    test('the pack holds exactly the ten pattern files, each with its own '
        'id', () {
      final files =
          shippedPackFiles.keys
              .where((k) => k.startsWith('software-tech/patterns/'))
              .toList()
            ..sort();
      expect(files, [
        for (final id in _patternIds) 'software-tech/patterns/$id.yaml',
      ]);
      for (final id in _patternIds) {
        expect(_fileOf(id)['id'], id, reason: id);
      }
    });

    test('only signup carries extends, and it extends auth', () {
      for (final id in _patternIds) {
        expect(
          _fileOf(id)['extends'],
          id == 'signup' ? 'auth' : isNull,
          reason: id,
        );
      }
      expect(set.featurePatterns.map((p) => p.id), _patternIds);
      expect(
        {
          for (final p in set.featurePatterns)
            if (p.extendsId != null) p.id: p.extendsId,
        },
        {'signup': 'auth'},
      );
    });

    test('each pattern states a one-sentence description', () {
      for (final id in _patternIds) {
        final description = (_fileOf(id)['description'] as String).trim();
        expect(description, isNotEmpty, reason: id);
        expect(description, endsWith('.'), reason: id);
        expect(
          _sentenceBreak.allMatches(description),
          hasLength(1),
          reason: id,
        );
      }
    });

    test('each file holds 5 to 15 items, each one sentence of at most 160 '
        'characters that names no class, file, or error code', () {
      for (final id in _patternIds) {
        final items = _itemsOf(id);
        expect(items.length, inInclusiveRange(5, 15), reason: id);
        final ids = [for (final item in items) item['id']! as String];
        expect(ids.toSet(), hasLength(ids.length), reason: '$id ids repeat');
        for (final item in items) {
          final where = '$id.${item['id']}';
          final text = (item['text']! as String).trim();
          expect(item['id'], matches(_slug), reason: where);
          expect(text.length, lessThanOrEqualTo(_maxItemChars), reason: where);
          expect(text, endsWith('.'), reason: where);
          expect(_sentenceBreak.allMatches(text), hasLength(1), reason: where);
          expect(text, isNot(matches(RegExp(r'[`/\\]|\.dart'))), reason: where);
        }
      }
    });

    test('signup repeats no item id of auth', () {
      final auth = {for (final item in _itemsOf('auth')) item['id']};
      for (final item in _itemsOf('signup')) {
        expect(auth, isNot(contains(item['id'])), reason: '${item['id']}');
      }
    });

    test('each pattern lists the entries of the Sources table and at most '
        'one more', () {
      expect(_sources.keys.toSet(), _patternIds.toSet());
      for (final MapEntry(key: id, value: expected) in _sources.entries) {
        final merged = [
          for (final entry in set.featurePattern(id)!.reference)
            (title: entry.title, url: entry.url, locator: entry.locator),
        ];
        for (final entry in expected) {
          expect(merged, contains(entry), reason: '$id: ${entry.title}');
        }
        final written = _writtenReference(id);
        final extra = written.where((e) => !expected.contains(e)).toList();
        expect(extra.length, lessThanOrEqualTo(1), reason: '$id: $extra');
        for (final entry in written) {
          expect(entry.url, startsWith('https://'), reason: id);
        }
      }
    });

    test('signup merges the items of auth, then its own', () {
      final auth = set.featurePattern('auth')!;
      final signup = set.featurePattern('signup')!;
      final own = [for (final item in _itemsOf('signup')) item['id']];
      expect(signup.items.map((i) => i.id), [
        ...auth.items.map((i) => i.id),
        ...own,
      ]);
      expect(
        signup.items.take(auth.items.length).map((i) => i.text),
        auth.items.map((i) => i.text),
      );
    });

    test('a project that lists only prd-core loads none of the ten', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
      });
      final resolved = TemplateResolver().resolve(
        workingDirectory: project,
        homeDirectory: await writeTree({}),
      );
      expect(resolved.featurePatterns, isEmpty);
    });
  });
}
