import 'dart:convert';

import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import 'shipped_pins.dart';
import 'temp_tree.dart';

/// The words and phrases the NASA lint bans (US-06 FR-03), in list order.
const nasaBannedWords = <String>[
  'flexible',
  'easy',
  'sufficient',
  'safe',
  'ad hoc',
  'adequate',
  'accommodate',
  'user-friendly',
  'usable',
  'when required',
  'if required',
  'appropriate',
  'fast',
  'portable',
  'light-weight',
  'small',
  'large',
  'maximize',
  'minimize',
  'robust',
  'quickly',
  'easily',
  'clearly',
  'this',
  'these',
  'as appropriate',
  'etc.',
  'and/or',
  'but not limited to',
];

/// The title of the NASA handbook reference entry.
const nasaHandbookTitle =
    'NASA Systems Engineering Handbook, NASA SP-2016-6105 Rev2';

/// The URL of the NASA handbook reference entry.
const nasaHandbookUrl =
    'https://www.nasa.gov/wp-content/uploads/2018/09/'
    'nasa_systems_engineering_handbook_0.pdf';

/// The Statement template `fr` and `nf` share (F3P-D37, F3P-D39).
const requirementStatementTemplate =
    'The <product> shall <verb> <object> <value ± tolerance> <condition>.';

/// The Verification template `fr` and `nf` share.
const verificationTemplate =
    '- **Pass criteria:** <what shows the requirement holds>\n'
    '- **Level:** <level>';

/// The TBR template `fr` and `nf` share.
const tbrTemplate =
    '- **Value:** <best estimate>\n'
    '- **Why:** <reason>\n'
    '- **Close action:** <what resolves it>\n'
    '- **Who:** <name>\n'
    '- **By when:** <date or milestone>';

/// The `prd-core` doc type ids, in code point order.
const prdCoreIds = <String>[
  'anti_persona',
  'feature',
  'features',
  'fr',
  'gnfr',
  'journey',
  'nf',
  'persona',
  'project',
  'reference',
  'user_story',
];

/// One expected section: id, header, prefix id, and required flag.
final class SectionSpec {
  const new(this.id, this.header, {this.prefixId, this.required = false});

  final String id;
  final String header;
  final String? prefixId;
  final bool required;
}

/// One expected own field: id, type, list flag, required flag, and links.
final class FieldSpec {
  const new(
    this.id,
    this.type, {
    this.list = false,
    this.required = false,
    this.enumValues,
    this.docTypes,
    this.pointer,
  });

  final String id;
  final FieldType type;
  final bool list;
  final bool required;
  final List<String>? enumValues;
  final List<String>? docTypes;
  final PointerKind? pointer;
}

/// Resolves a temp project that pins the shipped `prd-core`.
///
/// Each [templates] entry lands at `.specstone/templates/<key>`. Calls
/// `writeTree`, so call it from a test or `setUpAll`.
Future<MergedSet> resolvePrdCore({
  Map<String, String> templates = const {},
}) async {
  final project = await writeTree({
    '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
    for (final MapEntry(:key, :value) in templates.entries)
      '.specstone/templates/$key': value,
  });
  final home = await writeTree({});
  return TemplateResolver().resolve(
    workingDirectory: project,
    homeDirectory: home,
  );
}

/// Returns the doc type [id] of [set], failing the test when it is absent.
MergedDocType prdCoreDocType(MergedSet set, String id) {
  final docType = set.lookup(id);
  expect(docType, isNotNull, reason: id);
  return docType!;
}

/// Returns the section [id] of [docType].
MergedSection sectionOf(MergedDocType docType, String id) =>
    docType.sections.singleWhere((s) => s.id == id);

/// Returns the field [id] of [docType].
MergedField fieldOf(MergedDocType docType, String id) =>
    docType.fields.singleWhere((f) => f.id == id);

/// Parses the shipped `<pack>/<id>.yaml` as a shipped layer.
DocTypeLayer shippedLayer(String id, {String pack = 'prd-core'}) =>
    DocTypeLayer.parse(
      utf8.decode(shippedPackFiles['$pack/$id.yaml']!),
      file: 'packs/$pack/$id.yaml',
      docTypeId: id,
      kind: LayerKind.shipped,
      files: const _NoFiles(),
    );

/// Expects the section ids, headers, prefix ids, and required flags.
void expectSections(MergedDocType docType, List<SectionSpec> expected) {
  expect(
    [
      for (final s in docType.sections)
        (s.id, s.header, s.prefixId, s.required),
    ],
    [for (final s in expected) (s.id, s.header, s.prefixId, s.required)],
    reason: docType.id,
  );
}

const _builtInFieldIds = {'slug', 'status', 'draft', 'approved', 'reference'};

/// Expects the fields other than the built-in five, each with a description.
void expectOwnFields(MergedDocType docType, List<FieldSpec> expected) {
  final own = [
    for (final f in docType.fields)
      if (!_builtInFieldIds.contains(f.id)) f,
  ];
  // Lists, not records: a record compares its parts with `==`, and a `List`
  // compares by identity, so only a list is matched element by element.
  expect(
    [
      for (final f in own)
        [f.id, f.type, f.list, f.required, f.enumValues, f.docTypes, f.pointer],
    ],
    [
      for (final f in expected)
        [f.id, f.type, f.list, f.required, f.enumValues, f.docTypes, f.pointer],
    ],
    reason: docType.id,
  );
  for (final f in own) {
    expect(f.description, isNotEmpty, reason: '${docType.id}.${f.id}');
  }
}

/// Expects the `status` enum values of [docType].
void expectStatusValues(MergedDocType docType, List<String> values) {
  expect(fieldOf(docType, 'status').enumValues, values, reason: docType.id);
}

/// Expects the guide shape every `prd-core` doc type shares.
void expectGuideShape(
  MergedDocType docType, {
  required String title,
  String pack = 'prd-core',
}) {
  final id = docType.id;
  expect(docType.pack, pack, reason: id);
  final description = docType.description;
  expect(description, isNotNull, reason: id);
  final firstLine = const LineSplitter().convert(description!).first;
  expect(firstLine, isNotEmpty, reason: id);
  expect(firstLine, endsWith('.'), reason: id);
  expect(firstLine, isNot(startsWith('#')), reason: id);
  expect(description, contains(title), reason: id);
  for (final section in docType.sections) {
    final lines = const LineSplitter().convert(section.description ?? '');
    final where = '$id.${section.id}';
    expect(section.description, isNotEmpty, reason: where);
    expect(lines.length, lessThanOrEqualTo(5), reason: where);
    for (final line in lines) {
      expect(line.length, lessThanOrEqualTo(120), reason: '$where: $line');
    }
  }
  expect(_guideTexts(docType).where(_thai.hasMatch), isEmpty, reason: id);
  expect(docType.fields.any((f) => f.id == 'name'), isFalse, reason: id);
  expect(docType.lint.maxLines, 400, reason: id);
  expect(docType.lint.maxChars, isNull, reason: id);
  expect(fieldOf(docType, 'reference').docTypes, isNull, reason: id);
}

/// Expects the NASA words on [sections] only, with [linePrefix], and the
/// handbook reference on [docType].
void expectNasaLint(
  MergedDocType docType, {
  required List<String> sections,
  String? linePrefix,
}) {
  expect(docType.lint.bannedWords, isNull, reason: docType.id);
  expect(docType.lint.allowedWords, isNull, reason: docType.id);
  for (final section in docType.sections) {
    final where = '${docType.id}.${section.id}';
    final listed = sections.contains(section.id);
    expect(
      section.bannedWords,
      listed ? nasaBannedWords : isNull,
      reason: where,
    );
    expect(section.allowedWords, isNull, reason: where);
    expect(section.linePrefix, listed ? linePrefix : isNull, reason: where);
  }
  final reference = docType.reference;
  expect(reference, isNotNull, reason: docType.id);
  expect(reference, hasLength(1), reason: docType.id);
  final entry = reference!.single;
  expect(entry.title, nasaHandbookTitle, reason: docType.id);
  expect(entry.url, nasaHandbookUrl, reason: docType.id);
  expect(entry.file, isNull, reason: docType.id);
  expect(entry.doc, isNull, reason: docType.id);
  expect(entry.locator, isNull, reason: docType.id);
}

/// Expects [docType] to carry no banned words and no reference list.
void expectNoNasaLint(MergedDocType docType) {
  expect(docType.lint.bannedWords, isNull, reason: docType.id);
  for (final section in docType.sections) {
    expect(section.bannedWords, isNull, reason: '${docType.id}.${section.id}');
  }
  expect(docType.reference, isNull, reason: docType.id);
}

/// Returns the [nasaBannedWords] entries [text] holds, in list order.
List<String> listedWordsIn(String text) => [
  for (final word in nasaBannedWords)
    if (_wholeWord(word).hasMatch(text)) word,
];

/// Expects no section header or template of [docType] to hold a listed word.
void expectTemplatesFreeOfListedWords(MergedDocType docType) {
  for (final section in docType.sections) {
    final reason = '${docType.id}.${section.id}';
    expect(listedWordsIn(section.header), isEmpty, reason: '$reason header');
    expect(
      listedWordsIn(section.template ?? ''),
      isEmpty,
      reason: '$reason template',
    );
  }
}

RegExp _wholeWord(String word) => RegExp(
  '(?<![A-Za-z0-9])${RegExp.escape(word)}(?![A-Za-z0-9])',
  caseSensitive: false,
);

final _thai = RegExp(r'[\u0E00-\u0E7F]');

Iterable<String> _guideTexts(MergedDocType docType) sync* {
  yield docType.description ?? '';
  for (final field in docType.fields) {
    yield field.description ?? '';
  }
  for (final section in docType.sections) {
    yield section.header;
    yield section.description ?? '';
    yield section.template ?? '';
  }
}

final class _NoFiles implements LayerFiles {
  const new();

  @override
  bool exists(String layerRelativePath) => false;
}
