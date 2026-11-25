// Test names stay one literal so `specstone check` finds them by exact text.

import 'package:specstone_core/src/setup_migration/merge_doc_step.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:test/test.dart';

const _step = MergeDoc(
  fromId: 'playbook',
  fromPath: 'prds/runbooks/{slug}/PLAYBOOK.md',
  toId: 'runbook',
  sections: [
    MergeSection(fromId: 'moves', fromHeader: 'Moves', toId: 'procedure'),
    MergeSection(fromId: 'checks', fromHeader: 'Checks', toId: 'procedure'),
  ],
);

const _toHeaders = {'procedure': 'Procedure'};

const _toDoc = '''
---
owner: sre
---
# Deploy

## Goals

Ship it.
''';

const _fromDoc = '''
---
tasks:
  - Review
  - Ship
---
# Deploy playbook

## Moves

Run it.

## Notes

Keep calm.
''';

MergedDoc _merge({
  String toLf = _toDoc,
  String fromLf = _fromDoc,
  MergeDoc step = _step,
}) =>
    mergeDocInto(toLf: toLf, fromLf: fromLf, step: step, toHeaders: _toHeaders);

void main() {
  group('merge', () {
    test('each section of the from doc lands at the end of the to doc in '
        'order, the mapped one under the to header and the rest under their '
        'own', () {
      expect(_merge().text, '''
---
owner: sre
tasks:
  - Review
  - Ship
---
# Deploy

## Goals

Ship it.

## Procedure

Run it.

## Notes

Keep calm.
''');
    });

    test('a header matches a mapped one as the drop_section header match '
        'reads it, case and spacing aside', () {
      final merged = _merge(fromLf: '# Deploy\n\n##   MOVES\n\nRun it.\n');

      expect(merged.text, '''
---
owner: sre
---
# Deploy

## Goals

Ship it.

## Procedure

Run it.
''');
    });

    test('two sections mapped to one id join under one header in source '
        'order', () {
      final merged = _merge(
        fromLf:
            '# Deploy\n\n## Moves\n\nRun it.\n\n## Notes\n\nKeep calm.\n\n'
            '## Checks\n\nCheck it.\n',
      );

      expect(merged.text, '''
---
owner: sre
---
# Deploy

## Goals

Ship it.

## Procedure

Run it.

Check it.

## Notes

Keep calm.
''');
      expect(merged.movedHeaders, ['Procedure', 'Notes']);
    });

    test('movedHeaders lists each header the merge adds, in order', () {
      expect(_merge().movedHeaders, ['Procedure', 'Notes']);
    });

    test('an empty to doc gives the new draft: a draft flag, the from '
        'title, the sections, and the list fields', () {
      expect(_merge(toLf: '').text, '''
---
draft: true
tasks:
  - Review
  - Ship
---

# Deploy playbook

## Procedure

Run it.

## Notes

Keep calm.
''');
    });
  });

  group('fields', () {
    test('an entry of a list field the to doc holds goes after its entries, '
        'indented as they are', () {
      final merged = _merge(
        toLf: '---\ntasks:\n- Plan\n---\n# Deploy\n',
        fromLf: '---\ntasks:\n  - Review\n  - Ship\n---\n# Deploy\n',
      );

      expect(
        merged.text,
        '---\ntasks:\n- Plan\n- Review\n- Ship\n---\n# Deploy\n',
      );
    });

    test('a list field the to doc lacks is added after its last key', () {
      final merged = _merge(
        fromLf: '---\noverrides:\n  - a: 1\n    b: two\n---\n# Deploy\n',
      );

      expect(
        merged.text,
        '---\nowner: sre\noverrides:\n  - a: 1\n    b: two\n---\n'
        '# Deploy\n\n## Goals\n\nShip it.\n',
      );
    });

    test('a tasks entry the to doc already holds is not appended again, so a '
        'rerun adds nothing', () {
      const entriesOnly = '---\ntasks:\n  - Review\n  - Ship\n---\n# Deploy\n';
      final once = _merge(fromLf: entriesOnly);
      final again = _merge(toLf: once.text, fromLf: entriesOnly);

      expect(again.text, once.text);
      expect(
        again.text.split('\n').where((line) => line == '  - Review'),
        hasLength(1),
      );
    });

    test('an entry the to doc lacks is appended after the ones it holds', () {
      final merged = _merge(
        toLf: '---\ntasks:\n  - Review\n---\n# Deploy\n',
        fromLf: '---\ntasks:\n  - Review\n  - Ship\n---\n# Deploy\n',
      );

      expect(merged.text, '---\ntasks:\n  - Review\n  - Ship\n---\n# Deploy\n');
    });

    test('a to list written in flow style, or empty, is rewritten in block '
        'style with its entries kept', () {
      final merged = _merge(
        toLf: '---\ntasks: [Plan]\n---\n# Deploy\n',
        fromLf: '---\ntasks:\n  - Review\n---\n# Deploy\n',
      );

      expect(
        merged.text,
        '---\ntasks:\n  - "Plan"\n  - Review\n---\n# Deploy\n',
      );
    });

    test('a scalar field of the from doc is left behind', () {
      final merged = _merge(fromLf: '---\nowner: ops\n---\n# Deploy\n');

      expect(merged.text, _toDoc);
    });

    test('the lead of the from doc lands first in the first section the merge '
        "moves, before that section's text", () {
      final merged = _merge(
        fromLf:
            '# Deploy\n\nAbout deploys.\n\n## Notes\n\nKeep calm.\n\n'
            '## Moves\n\nRun it.\n',
      );

      expect(merged.text, '''
---
owner: sre
---
# Deploy

## Goals

Ship it.

## Notes

About deploys.

Keep calm.

## Procedure

Run it.
''');
      expect(merged.isLeadUnplaced, isFalse);
    });

    test('a from doc with a lead and no section reports the lead unplaced and '
        'leaves the to doc as it is', () {
      final merged = _merge(fromLf: '# Deploy\n\nAbout deploys.\n');

      expect(merged.isLeadUnplaced, isTrue);
      expect(merged.text, _toDoc);
    });

    test('a from doc with no lead and no section places nothing and reports '
        'nothing unplaced', () {
      final merged = _merge(fromLf: '# Deploy\n');

      expect(merged.isLeadUnplaced, isFalse);
    });

    for (final held in ['tasks: oops', 'tasks: [oops']) {
      test('a to field that is no list ($held) is reported unmerged and left '
          'as it is', () {
        final to = '---\n$held\n---\n# Deploy\n';
        final merged = _merge(toLf: to, fromLf: _fromDoc);

        expect(merged.unmergedFields, ['tasks']);
        expect(merged.text, startsWith(to.substring(0, to.length - 1)));
      });
    }
  });
}
