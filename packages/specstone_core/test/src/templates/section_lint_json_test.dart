import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

void main() {
  test('a section prints each guide-rule lint key its layers set, in '
      'camelCase', () {
    const section = MergedSection(
      id: 'errors',
      header: 'Errors',
      minLines: 2,
      catalog: CatalogLint(column: 'Code'),
      namesCodes: true,
      itemFields: [
        ItemFieldLint(field: 'Kind', values: ['a', 'b']),
        ItemFieldLint(field: 'Why'),
      ],
      requiredWhen: RequiredWhenLint(
        section: 'flow',
        field: 'Kind',
        value: 'a',
      ),
      diagram: DiagramLint(title: true, edgeLabels: true, bannedLabels: ['x']),
      maxSentences: [
        SentenceLimit(count: 2),
        SentenceLimit(count: 1, linePrefix: '- ', column: 'Why'),
      ],
      itemCount: ItemCountLint(
        min: 1,
        max: 5,
        perSubsection: true,
        prefixes: [(linePrefix: 'E', count: 2)],
      ),
    );

    expect(section.toJson()['lint'], {
      'minLines': 2,
      'catalog': {'column': 'Code'},
      'namesCodes': true,
      'itemFields': [
        {
          'field': 'Kind',
          'values': ['a', 'b'],
        },
        {'field': 'Why'},
      ],
      'requiredWhen': {'section': 'flow', 'field': 'Kind', 'value': 'a'},
      'diagram': {
        'title': true,
        'edgeLabels': true,
        'bannedLabels': ['x'],
      },
      'maxSentences': [
        {'count': 2},
        {'count': 1, 'linePrefix': '- ', 'column': 'Why'},
      ],
      'itemCount': {
        'min': 1,
        'max': 5,
        'perSubsection': true,
        'prefixes': [
          {'linePrefix': 'E', 'count': 2},
        ],
      },
    });
  });

  test('a section that sets no guide-rule key prints none', () {
    const section = MergedSection(id: 'plain', header: 'Plain', maxChars: 9);

    expect(section.toJson()['lint'], {'maxChars': 9});
  });
}
