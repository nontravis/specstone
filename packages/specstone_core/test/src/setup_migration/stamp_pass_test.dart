// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/setup_migration/models/stamp_doc.dart';
import 'package:specstone_core/src/setup_migration/stamp_pass.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

const _storyPath = 'prds/features/f01_a/us01_b/USER_STORY.md';
const _frPath = 'prds/features/f01_a/us01_b/fr01_c.md';
const _draftFrPath = 'prds/features/f01_a/us01_b/fr02_d.md';
const _notesPath = 'notes/free.md';
const _recordPath = '.specstone/records/f01_a/IMPLEMENTATION.md';
const _gnfrPath = 'prds/GNFR.md';
const _nfPath = 'prds/features/f01_a/us01_b/nf01_d.md';

const _one = '### Scenario 1 — [happy] one\n\n- **Given** g';

final _approvedHash = RegExp(r'^approved: "[0-9a-f]{12}"$', multiLine: true);

String _hashOf(String lf, MergedDocType? type) => approvalHashOf(lf, type);

/// [lf] stamped with [_hashOf].
String _stamped(String lf, MergedDocType? type) => withApprovalHash(lf, type);

/// [docs], each approved by the hash of its content.
Map<String, String> _approved(Map<String, String> docs) => {
  for (final MapEntry(key: docPath, value: lf) in docs.entries)
    docPath: _stamped(lf, _typeAt(docPath)),
};

/// [lf] with its heading changed, so its approval hash is stale.
String _edited(String lf) =>
    lf.replaceFirst(RegExp('^# ', multiLine: true), '# Edited ');

String _story(String scenarios) =>
    '# B\n\n## Acceptance Criteria\n\n$scenarios\n';

String _tracing(String entries) =>
    '---\ntraced_from: [S1]\nconfirmed:\n$entries---\n# C\n';

late MergedSet _set;

MergedDocType? _typeAt(String docPath) =>
    switch (DocTypeMatcher(_set, targetNames: const []).match(docPath)) {
      MatchedDocType(:final docType) => docType,
      _ => null,
    };

List<StampDoc> _docs(Map<String, String> texts) => [
  for (final MapEntry(key: docPath, value: lf) in texts.entries)
    StampDoc(docPath: docPath, lf: lf, type: _typeAt(docPath)),
];

/// The pass over [before] and [after], applied to each doc of [after].
({StampPass pass, Map<String, String> applied}) _run(
  Map<String, String> before,
  Map<String, String> after, {
  Set<String> typedByAdd = const {},
  Map<String, String> linkedFrom = const {},
}) {
  final pass = StampPass.plan(
    _docs(before),
    _docs(after),
    typedByAdd: typedByAdd,
    linkedFrom: linkedFrom,
  );
  return (
    pass: pass,
    applied: {
      for (final MapEntry(key: docPath, value: lf) in after.entries)
        docPath: pass.apply(docPath, lf),
    },
  );
}

/// The pass over a run that changes nothing but the stamps.
({StampPass pass, Map<String, String> applied}) _runUnchanged(
  Map<String, String> docs,
) => _run(docs, docs);

void main() {
  setUpAll(() {
    _set = TemplateResolver().resolveCarried(
      packNames: const ['prd-core', 'software-tech'],
      homeDirectory: null,
    );
  });

  group('the approval hash stamp', () {
    test('a doc approved by its hash takes the approval hash of its content '
        'after the run; a draft keeps its frontmatter', () {
      final approved = _approved({
        _storyPath: _story(_one),
        _frPath: _tracing('  - S1 ${fingerprintOf(_one)}\n'),
      });
      final before = {
        ...approved,
        _draftFrPath: '---\ndraft: true\n---\n# D\n',
      };
      final after = {
        _storyPath: _edited(approved[_storyPath]!),
        _frPath: _edited(approved[_frPath]!),
        _draftFrPath: _edited(before[_draftFrPath]!),
      };

      final run = _run(before, after);

      for (final docPath in [_storyPath, _frPath]) {
        final stamped = run.applied[docPath]!;
        expect(stamped, matches(_approvedHash));
        expect(stamped, _stamped(after[docPath]!, _typeAt(docPath)));
      }
      expect(run.applied[_draftFrPath], after[_draftFrPath]);
      expect(run.pass.planLine, 'stamps: 2 approval hashes, 0 fingerprints');
    });

    test('a doc the pass leaves as written is not counted', () {
      final settled = _approved({_storyPath: _story(_one)});

      final run = _runUnchanged(settled);

      expect(run.applied, settled);
      expect(run.pass.planLine, isNull);
    });

    test('an untyped doc is left as written', () {
      final run = _runUnchanged({_notesPath: '# Notes\n'});

      expect(run.applied[_notesPath], '# Notes\n');
      expect(run.pass.planLine, isNull);
    });

    test('a doc counts as approved by its text before the run: a draft the '
        'run left no longer a draft is still not stamped', () {
      final before = {_storyPath: '---\ndraft: true\n---\n${_story(_one)}'};
      final after = {_storyPath: _story(_one)};

      final run = _run(before, after);

      expect(run.applied, after);
    });

    test('a doc with approved: true, a doc with neither key, and a doc whose '
        'hash matches take no stamp', () {
      final docs = {
        _storyPath: '---\napproved: true\n---\n${_story(_one)}',
        _frPath: _tracing('  - S1 ${fingerprintOf(_one)}\n'),
        ..._approved({_draftFrPath: '# D\n'}),
      };

      final run = _runUnchanged(docs);

      expect(run.applied, docs);
      expect(run.pass.planLine, isNull);
    });

    test('a stale string hash and a digits-only value stay as written', () {
      final docs = {
        _storyPath: '---\napproved: "000000000000"\n---\n${_story(_one)}',
        _frPath: '---\napproved: 123456789012\n---\n# C\n',
      };

      final run = _runUnchanged(docs);

      expect(run.applied, docs);
      expect(run.pass.planLine, isNull);
    });

    test('a doc whose frontmatter is not valid YAML keeps its bytes, its '
        'entries included', () {
      final docs = {
        _storyPath: '---\ndraft: true\n: bad: [\n---\n${_story(_one)}',
        _frPath:
            '---\nconfirmed:\n  - S1 ${fingerprintOf(_one)}\nkey: [\n---\n'
            '# C\n',
      };

      final run = _runUnchanged(docs);

      expect(run.applied, docs);
      expect(
        run.pass.planLine,
        'stamps: 0 approval hashes, 0 fingerprints; skipped: 2',
      );
      expect(run.pass.paths, [_storyPath, _frPath]);
    });

    test('the skipped paths of a plan with none are empty, and the line '
        'ends after the two counts', () {
      final before = _approved({_storyPath: _story(_one)});

      final run = _run(before, {_storyPath: _edited(before[_storyPath]!)});

      expect(run.pass.paths, isEmpty);
      expect(run.pass.planLine, 'stamps: 1 approval hashes, 0 fingerprints');
    });

    test('no line prints when both counts are zero and no doc was skipped', () {
      expect(stampsPlanLine(0, 0), isNull);
      expect(
        stampsPlanLine(0, 0, skipped: const ['a.md']),
        'stamps: 0 approval hashes, 0 fingerprints; skipped: 1',
      );
    });

    test('a doc the add newly types gets no approval hash', () {
      final before = _approved({
        _storyPath: _story(_one),
        _frPath: _story(_one),
      });
      final after = {
        for (final MapEntry(:key, :value) in before.entries)
          key: _edited(value),
      };

      final run = _run(before, after, typedByAdd: {_storyPath});

      expect(run.applied[_storyPath], after[_storyPath]);
      expect(run.applied[_frPath], isNot(after[_frPath]));
      expect(run.pass.planLine, 'stamps: 1 approval hashes, 0 fingerprints');
    });

    test('a doc whose text is not the planned one is refused', () {
      final run = _runUnchanged({_storyPath: _story(_one)});

      expect(
        () => run.pass.apply(_storyPath, '# Other\n'),
        throwsArgumentError,
      );
      expect(run.pass.apply('docs/unplanned.md', '# X\n'), '# X\n');
    });
    group('a mark step wrote the doc', () {
      const marked =
          '---\ntraced_from: [S1]\nretrim:\n  - edge_cases\n---\n'
          '# C\n\n## Edge cases\n\n1. E01 — Empty → refused.\n';

      test('an approved doc a mark step wrote is stamped with the hash approve '
          'gives', () {
        final before = _approved({_frPath: _tracing('  - S1 000000000000\n')});
        final after = {_frPath: marked};

        final run = _run(before, after);

        final stamped = run.applied[_frPath]!;
        expect(stamped, withApprovalHash(marked, _typeAt(_frPath)));
        expect(run.pass.planLine, 'stamps: 1 approval hashes, 0 fingerprints');
      });

      test('a draft a mark step wrote stays a draft', () {
        const draft =
            '---\ndraft: true\ntraced_from: [S1]\nretrim:\n'
            '  - edge_cases\n---\n# C\n\n## Edge cases\n\n'
            '1. E01 — Empty → refused.\n';
        final before = {
          _frPath: '---\ndraft: true\ntraced_from: [S1]\n---\n# C\n',
        };
        final after = {_frPath: draft};

        final run = _run(before, after);

        expect(run.applied[_frPath], draft);
      });
    });
  });

  group('the entry fingerprint stamp', () {
    test('a matched entry with a link-only upstream change takes the new fingerprint', () {
      const folded =
          '### Scenario 1 — [happy] one\n\n- **Given** [domain:login](../x.md)';
      const relinked =
          '### Scenario 1 — [happy] one\n\n- **Given** [architecture:login](../x.md)';
      final before = _approved({
        _storyPath: _story(folded),
        _frPath: _tracing('  - S1 ${fingerprintOf(folded)}\n'),
      });
      final after = {_storyPath: _story(relinked), _frPath: before[_frPath]!};

      final run = _run(
        before,
        after,
        linkedFrom: {_storyPath: before[_storyPath]!},
      );

      expect(
        run.applied[_frPath],
        contains('  - S1 ${fingerprintOf(relinked)}\n'),
      );
      expect(run.pass.planLine, 'stamps: 2 approval hashes, 1 fingerprints');
    });

    test('a matched entry whose upstream a step changed beyond links stays', () {
      const folded =
          '### Scenario 1 — [happy] one\n\n- **Given** [domain:login](../x.md)';
      const stepped =
          '### Scenario 1 — [happy] one\n\n- **Given** a [domain:login](../x.md)';
      const relinked =
          '### Scenario 1 — [happy] one\n\n- **Given** a [architecture:login](../x.md)';
      final before = {
        _storyPath: _story(folded),
        _frPath: _tracing('  - S1 ${fingerprintOf(folded)}\n'),
      };
      final after = {_storyPath: _story(relinked), _frPath: before[_frPath]!};

      final run = _run(
        before,
        after,
        linkedFrom: {_storyPath: _story(stepped)},
      );

      expect(
        run.applied[_frPath],
        contains('  - S1 ${fingerprintOf(folded)}\n'),
      );
    });

    test('an entry already suspect keeps its fingerprint', () {
      const folded =
          '### Scenario 1 — [happy] one\n\n- **Given** [domain:login](../x.md)';
      const relinked =
          '### Scenario 1 — [happy] one\n\n- **Given** [architecture:login](../x.md)';
      final before = _approved({
        _storyPath: _story(folded),
        _frPath: _tracing('  - S1 000000000000\n'),
      });
      final after = {
        _storyPath: _story(relinked),
        _frPath: _edited(before[_frPath]!),
      };

      final run = _run(
        before,
        after,
        linkedFrom: {_storyPath: before[_storyPath]!},
      );

      expect(run.applied[_frPath], contains('  - S1 000000000000\n'));
      expect(run.pass.planLine, 'stamps: 2 approval hashes, 0 fingerprints');
    });

    test('a quoted entry keeps its quotes', () {
      const folded =
          '### Scenario 1 — [happy] one\n\n- **Given** [domain:login](../x.md)';
      const relinked =
          '### Scenario 1 — [happy] one\n\n- **Given** [architecture:login](../x.md)';
      final before = _approved({
        _storyPath: _story(folded),
        _frPath:
            '---\nconfirmed:\n  - "S1 ${fingerprintOf(folded)}"\n---\n# C\n',
      });
      final after = {...before, _storyPath: _story(relinked)};

      final run = _run(
        before,
        after,
        linkedFrom: {_storyPath: before[_storyPath]!},
      );

      expect(
        run.applied[_frPath],
        contains('  - "S1 ${fingerprintOf(relinked)}"\n'),
      );
    });

    test('the approval hash covers the stamped entries', () {
      const folded =
          '### Scenario 1 — [happy] one\n\n- **Given** [domain:login](../x.md)';
      const relinked =
          '### Scenario 1 — [happy] one\n\n- **Given** [architecture:login](../x.md)';
      final before = _approved({
        _storyPath: _story(folded),
        _frPath: _tracing('  - S1 ${fingerprintOf(folded)}\n'),
      });
      final after = {_storyPath: _story(relinked), _frPath: before[_frPath]!};

      final stamped = _run(
        before,
        after,
        linkedFrom: {_storyPath: before[_storyPath]!},
      ).applied[_frPath]!;

      final type = _typeAt(_frPath);
      expect(stamped, contains('approved: "${_hashOf(stamped, type)}"'));
      expect(_hashOf(stamped, type), isNot(_hashOf(after[_frPath]!, type)));
    });

    test('an entry naming an NFR of a gnfr section with no prefix_id takes the '
        'fingerprint of its Statement', () {
      const statement =
          '- **Statement:** The tool shall pass [domain:wcag](../x.md).';
      const reworded =
          '- **Statement:** The tool shall pass [architecture:wcag](../x.md).';
      String gnfr(String text) =>
          '# GNFR\n\n## Usability\n\n### NFR-U01 — WCAG\n$text\n';
      final shipped = _typeAt(_gnfrPath)!;
      final type = shipped.copyWith(
        sections: [
          ...shipped.sections,
          const MergedSection(id: 'usability', header: 'Usability'),
        ],
      );
      final nf =
          '---\nkind: tighten\noverrides: NFR-U01\nconfirmed:\n'
          '  - NFR-U01 ${fingerprintOf(statement)}\n---\n# D\n';
      StampDoc doc(String path, String lf) => StampDoc(
        docPath: path,
        lf: lf,
        type: path == _gnfrPath ? type : _typeAt(path),
      );

      final pass = StampPass.plan(
        [doc(_gnfrPath, gnfr(statement)), doc(_nfPath, nf)],
        [doc(_gnfrPath, gnfr(reworded)), doc(_nfPath, nf)],
        linkedFrom: {_gnfrPath: gnfr(statement)},
      );

      expect(
        pass.apply(_nfPath, nf),
        contains('  - NFR-U01 ${fingerprintOf(reworded)}\n'),
      );
    });

    test('an entry naming a block the run lacks is left as written', () {
      final docs = {
        _storyPath: _story(_one),
        _frPath: _tracing('  - S4 ${fingerprintOf(_one)}\n'),
      };

      final run = _runUnchanged(docs);

      expect(run.applied[_frPath], contains('  - S4 ${fingerprintOf(_one)}\n'));
    });
  });

  group('the type a doc had before the run', () {
    test('a doc is judged by the type it had before the run: a field the '
        'final type dropped still stays out of its hash', () {
      final dropped = _typeAt(_storyPath)!;
      expect(dropped.fields.map((f) => f.id), isNot(contains('implements')));
      final held = dropped.copyWith(
        fields: [
          ...dropped.fields,
          const MergedField(
            id: 'implements',
            type: FieldType.outputRef,
            list: true,
            pointer: PointerKind.exact,
          ),
        ],
      );
      const written = '---\nimplements:\n  - app/a.dart\n---\n# B\n';
      const moved = '---\n---\n# B\n';
      final approved = _stamped(written, held);

      final pass = StampPass.plan(
        [StampDoc(docPath: _storyPath, lf: approved, type: held)],
        [StampDoc(docPath: _storyPath, lf: moved, type: dropped)],
      );

      final stamped = pass.apply(_storyPath, moved);
      expect(stamped, matches(_approvedHash));
      expect(stamped, contains('approved: "${_hashOf(stamped, dropped)}"'));
      expect(pass.planLine, 'stamps: 1 approval hashes, 0 fingerprints');
    });
  });

  group('records across the statuses rule', () {
    const record =
        "---\nstatuses:\n  - 'b:implemented'\nimplements:\n"
        "  - 'b:app/a.dart'\n---\n\n# Record\n";

    test('a record approved by its hash takes the hash that leaves its '
        'statuses out', () {
      final type = _typeAt(_recordPath);
      final approved = _approved({_recordPath: record});
      final changed = _edited(approved[_recordPath]!);

      final run = _run(approved, {_recordPath: changed});

      final stamped = run.applied[_recordPath]!;
      expect(stamped, withApprovalHash(changed, type));
      final changedStatus = stamped.replaceFirst(
        "'b:implemented'",
        "'b:planned'",
      );
      expect(changedStatus, isNot(stamped));
      expect(
        approvalHashOf(stamped, type),
        approvalHashOf(changedStatus, type),
      );
      expect(run.pass.planLine, 'stamps: 1 approval hashes, 0 fingerprints');
    });

    test('a record whose hash went stale before the run keeps it, and a '
        'draft record keeps its draft line', () {
      final docs = {
        _recordPath: record.replaceFirst(
          '---\n',
          '---\napproved: "000000000000"\n',
        ),
        '.specstone/records/f02_c/IMPLEMENTATION.md': record.replaceFirst(
          '---\n',
          '---\ndraft: true\n',
        ),
      };

      final run = _runUnchanged(docs);

      expect(run.applied, docs);
      expect(run.pass.planLine, isNull);
    });
  });
}
