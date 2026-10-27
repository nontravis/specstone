import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import 'prd_core.dart';
import 'shipped_pins.dart';
import 'temp_tree.dart';

/// The `software-tech` doc type ids, in code point order (US-07 FR-01).
const softwareTechIds = <String>[
  'api',
  'architecture',
  'auth',
  'domain',
  'error',
  'integration',
  'tech_stack',
  'topic',
];

/// Each doc type's `reference:` entries in order: US-07 FR-03 titles and
/// research N.4 urls.
const softwareTechSources = <String, List<({String title, String url})>>{
  'tech_stack': [
    (
      title: 'arc42 section 2, Architecture Constraints',
      url: 'https://docs.arc42.org/section-2/',
    ),
    (
      title: 'arc42 section 4, Solution Strategy',
      url: 'https://docs.arc42.org/section-4/',
    ),
    (
      title: 'GitHub Spec Kit, plan-template.md',
      url:
          'https://github.com/github/spec-kit/blob/main/templates/'
          'plan-template.md',
    ),
    (title: 'Google AIP-140, Field names', url: 'https://google.aip.dev/140'),
  ],
  'architecture': [
    (
      title: 'The C4 model, Notation',
      url: 'https://c4model.com/diagrams/notation',
    ),
    (
      title: 'arc42 section 5, Building Block View',
      url: 'https://docs.arc42.org/section-5/',
    ),
    (
      title: 'Google SRE Book, ch. 27 Reliable Product Launches at Scale',
      url: 'https://sre.google/sre-book/reliable-product-launches/',
    ),
    (
      title: 'Google SRE Book, ch. 6 Monitoring Distributed Systems',
      url: 'https://sre.google/sre-book/monitoring-distributed-systems/',
    ),
  ],
  'domain': [
    (
      title: 'Eric Evans, Domain-Driven Design Reference (2015)',
      url:
          'https://www.domainlanguage.com/wp-content/uploads/2016/05/'
          'DDD_Reference_2015-03.pdf',
    ),
    (
      title: 'Vaughn Vernon, Effective Aggregate Design, Part I',
      url:
          'https://www.dddcommunity.org/wp-content/uploads/files/'
          'pdf_articles/Vernon_2011_1.pdf',
    ),
    (
      title: 'Vaughn Vernon, Effective Aggregate Design, Part II',
      url:
          'https://www.dddcommunity.org/wp-content/uploads/files/'
          'pdf_articles/Vernon_2011_2.pdf',
    ),
    (
      title: 'DDD Crew, Aggregate Design Canvas',
      url: 'https://github.com/ddd-crew/aggregate-design-canvas',
    ),
  ],
  'api': [
    (
      title: 'OpenAPI Specification 3.2.1',
      url: 'https://spec.openapis.org/oas/v3.2.1.html',
    ),
    (
      title: 'Google AIP-121, Resource-oriented design',
      url: 'https://google.aip.dev/121',
    ),
    (
      title: 'Google AIP-180, Backwards compatibility',
      url: 'https://google.aip.dev/180',
    ),
    (
      title: 'Microsoft Azure REST API Guidelines',
      url:
          'https://github.com/microsoft/api-guidelines/blob/vNext/azure/'
          'Guidelines.md',
    ),
  ],
  'integration': [
    (
      title:
          'Marc Brooker, Timeouts, retries, and backoff with jitter '
          "(Amazon Builders' Library)",
      url:
          'https://aws.amazon.com/builders-library/'
          'timeouts-retries-and-backoff-with-jitter/',
    ),
    (
      title: 'IETF draft-ietf-httpapi-idempotency-key-header-08',
      url:
          'https://datatracker.ietf.org/doc/'
          'draft-ietf-httpapi-idempotency-key-header/',
    ),
    (
      title: 'AsyncAPI Specification 3.1.0',
      url: 'https://www.asyncapi.com/docs/reference/specification/v3.1.0',
    ),
    (
      title: 'CloudEvents 1.0.2',
      url:
          'https://github.com/cloudevents/spec/blob/ce@v1.0.2/cloudevents/'
          'spec.md',
    ),
  ],
  'error': [
    (
      title: 'RFC 9457, Problem Details for HTTP APIs',
      url: 'https://www.rfc-editor.org/rfc/rfc9457',
    ),
    (title: 'Google AIP-193, Errors', url: 'https://google.aip.dev/193'),
    (
      title: 'Google AIP-194, Automatic retry configuration',
      url: 'https://google.aip.dev/194',
    ),
    (
      title: 'Microsoft Azure REST API Guidelines',
      url:
          'https://github.com/microsoft/api-guidelines/blob/vNext/azure/'
          'Guidelines.md',
    ),
  ],
  'auth': [
    (
      title: 'OWASP ASVS 5.0',
      url: 'https://github.com/OWASP/ASVS/tree/master/5.0/en',
    ),
    (
      title: 'OWASP Authorization Cheat Sheet',
      url:
          'https://cheatsheetseries.owasp.org/cheatsheets/'
          'Authorization_Cheat_Sheet.html',
    ),
    (
      title: 'RFC 6749, The OAuth 2.0 Authorization Framework',
      url: 'https://www.rfc-editor.org/rfc/rfc6749#section-3.3',
    ),
    (
      title: 'OWASP Logging Vocabulary Cheat Sheet',
      url:
          'https://cheatsheetseries.owasp.org/cheatsheets/'
          'Logging_Vocabulary_Cheat_Sheet.html',
    ),
  ],
  'topic': [
    (
      title: 'arc42 section 8, Crosscutting Concepts',
      url: 'https://docs.arc42.org/section-8/',
    ),
    (
      title: 'arc42 tips 8-4 and 8-8, explain concepts with how and with code',
      url: 'https://docs.arc42.org/tips/8-4/',
    ),
    (
      title: 'arc42 section 5, Building Block View',
      url: 'https://docs.arc42.org/section-5/',
    ),
    (title: 'Diátaxis, Reference', url: 'https://diataxis.fr/reference/'),
  ],
};

/// The line target each doc type's description states (US-07 FR-02 E04).
String lineTargetOf(String id) => switch (id) {
  'tech_stack' => 'about 80 lines',
  'architecture' => 'under 150 lines',
  _ => 'about 150 to 200 lines',
};

/// The section id a header gives: lower case, each run of other characters
/// one underscore (US-07 FR-02 Output, "section header").
String snakeCaseOf(String header) =>
    header.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');

/// Resolves a temp project that pins the shipped `prd-core` and
/// `software-tech`.
///
/// Calls `writeTree`, so call it from a test or `setUpAll`.
Future<MergedSet> resolveSoftwareTech() async {
  final project = await writeTree({
    '.specstone/config.yaml': shippedPinsConfig(),
  });
  final home = await writeTree({});
  return TemplateResolver().resolve(
    workingDirectory: project,
    homeDirectory: home,
  );
}

String _squash(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Expects the guide shape every `software-tech` doc type shares.
///
/// Phrases compare lower-cased with each whitespace run as one space, except
/// the exact `Never write `status:`` sentence.
void expectSpecGuide(
  MergedDocType docType, {
  required String title,
  List<String> says = const [],
}) {
  final id = docType.id;
  expectGuideShape(docType, title: title, pack: 'software-tech');
  final description = docType.description!;
  expect(description, contains('Never write `status:`'), reason: id);
  final text = _squash(description);
  for (final phrase in ['no number', lineTargetOf(id), ...says]) {
    expect(text, contains(_squash(phrase)), reason: '$id: $phrase');
  }
  for (final section in docType.sections) {
    final where = '$id.${section.id}';
    expect(section.id, snakeCaseOf(section.header), reason: where);
    expect(section.template, isNull, reason: where);
  }
}

/// Expects each named section of [docType] to say each listed phrase.
///
/// Both sides compare lower-cased with each whitespace run as one space.
void expectSectionsSay(MergedDocType docType, Map<String, List<String>> says) {
  for (final MapEntry(key: sectionId, value: phrases) in says.entries) {
    final text = _squash(sectionOf(docType, sectionId).description ?? '');
    for (final phrase in phrases) {
      expect(
        text,
        contains(_squash(phrase)),
        reason: '${docType.id}.$sectionId: $phrase',
      );
    }
  }
}

/// Expects the 400-line cap and the four research sources on [docType].
void expectSpecLint(MergedDocType docType) {
  final id = docType.id;
  expect(docType.lint.maxLines, 400, reason: id);
  expect(docType.lint.maxChars, isNull, reason: id);
  expect(docType.lint.bannedWords, isNull, reason: id);
  expect(docType.lint.allowedWords, isNull, reason: id);
  for (final section in docType.sections) {
    expect(section.bannedWords, isNull, reason: '$id.${section.id}');
  }
  final reference = docType.reference;
  expect(reference, isNotNull, reason: id);
  final expected = softwareTechSources[id]!;
  expect(
    [for (final r in reference!) r.title],
    [for (final r in expected) r.title],
    reason: id,
  );
  expect(
    [for (final r in reference) r.url],
    [for (final r in expected) r.url],
    reason: id,
  );
  for (final entry in reference) {
    expect(entry.locator, isNotEmpty, reason: '$id: ${entry.title}');
    expect(entry.file, isNull, reason: id);
    expect(entry.doc, isNull, reason: id);
  }
}
