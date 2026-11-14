import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/setup_migration/stamp_pass.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType, PointerKind;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

const _fr = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';

const _storyPath = 'prds/features/f01_a/us01_b/USER_STORY.md';
const _frPath = 'prds/features/f01_a/us01_b/fr01_c.md';
const _draftFrPath = 'prds/features/f01_a/us01_b/fr02_d.md';
const _notesPath = 'notes/free.md';
const _recordPath = 'specs/f01_a/IMPLEMENTATION.md';

const _one = '### Scenario 1 — [happy] one\n\n- **Given** g';
const _lettered = '### Scenario 6a — [edge] lettered\n- **Given** g\n';
const _renumbered = '### Scenario 9 — [edge] lettered\n\n- **Given** g';

PackVersion _version(String text) =>
    PackVersion.parse(text, file: 'config.yaml', key: 'packs');

Map<String, PackVersion> get _belowBoth => {
  'prd-core': _version('1.0.0'),
  'software-tech': _version('1.0.0'),
};

final _approvedHash = RegExp(r'^approved: "[0-9a-f]{12}"$', multiLine: true);

/// The approval hash by the rule of the pins every run here starts from, all
/// below the statuses pin.
String _hashOf(String lf, MergedDocType? type) =>
    approvalHashOf(lf, type, statusesOutside: false);

/// [lf] stamped with [_hashOf].
String _stamped(String lf, MergedDocType? type) =>
    withApprovalHash(lf, type, statusesOutside: false);

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
    (docPath: docPath, lf: lf, type: _typeAt(docPath)),
];

/// The pass over [before] and [after], applied to each doc of [after].
({StampPass pass, Map<String, String> applied}) _run(
  Map<String, String> before,
  Map<String, String> after, {
  Map<String, PackVersion>? pins,
  Map<String, PackVersion>? pinsAfter,
  bool restampsFingerprints = true,
}) {
  final pass = StampPass.plan(
    _docs(before),
    _docs(after),
    pins: pins ?? _belowBoth,
    pinsAfter: pinsAfter ?? pins ?? _belowBoth,
    restampsFingerprints: restampsFingerprints,
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

  group('$_fr E30', () {
    test('a doc with approved: true and a doc with neither key take the '
        'approval hash of their content; a draft keeps its frontmatter', () {
      final docs = {
        _storyPath: '---\napproved: true\n---\n${_story(_one)}',
        _frPath: _tracing('  - S1 ${fingerprintOf(_one)}\n'),
        _draftFrPath: '---\ndraft: true\n---\n# D\n',
      };

      final run = _runUnchanged(docs);

      final story = run.applied[_storyPath]!;
      expect(story, matches(_approvedHash));
      expect(
        story,
        '---\napproved: "${_hashOf(story, _typeAt(_storyPath))}"\n---\n'
        '${_story(_one)}',
      );
      expect(run.applied[_frPath], matches(_approvedHash));
      expect(run.applied[_draftFrPath], docs[_draftFrPath]);
      expect(run.pass.planLine, 'stamps: 2 approval hashes, 0 fingerprints');
    });

    test('a doc with no frontmatter gains one holding only the hash', () {
      final run = _runUnchanged({_storyPath: _story(_one)});

      final stamped = run.applied[_storyPath]!;
      expect(stamped, startsWith('---\napproved: "'));
      expect(
        stamped,
        contains('"\n---\n\n# B\n'),
        reason: 'the fence is closed and a blank line follows it',
      );
    });

    test('a doc the pass leaves as written is not counted', () {
      final first = _runUnchanged({_storyPath: _story(_one)});
      final settled = {_storyPath: first.applied[_storyPath]!};

      final second = _runUnchanged(settled);

      expect(second.applied, settled);
      expect(second.pass.planLine, isNull);
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

    test('a stale string hash and a digits-only value stay as written', () {
      final docs = {
        _storyPath: '---\napproved: "000000000000"\n---\n${_story(_one)}',
        _frPath: '---\napproved: 123456789012\n---\n# C\n',
      };

      final run = _runUnchanged(docs);

      expect(run.applied, docs);
      expect(run.pass.planLine, isNull);
    });

    test('approved: true is stamped while the pins before the run are below '
        'both, and left once one of them has the stamps', () {
      final docs = {_storyPath: '---\napproved: true\n---\n${_story(_one)}'};
      final mixed = {
        'prd-core': _version('1.7.0'),
        'software-tech': _version('1.3.0'),
      };

      expect(_run(docs, docs).applied[_storyPath], matches(_approvedHash));
      expect(_run(docs, docs, pins: mixed).applied, docs);
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
      final run = _runUnchanged({_storyPath: _story(_one)});

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

    test('an upgrade past the one-time run stamps a doc that was approved '
        'before it, and keeps confirmed entries as written', () {
      final before = {
        _storyPath: _story(_one),
        _frPath: _tracing('  - S1 000000000000\n'),
      };
      final approvedBefore = {
        _storyPath: _stamped(before[_storyPath]!, _typeAt(_storyPath)),
        _frPath: before[_frPath]!,
      };
      final after = {
        _storyPath: approvedBefore[_storyPath]!.replaceFirst('# B', '# B2'),
        _frPath: approvedBefore[_frPath]!,
      };

      final run = _run(
        approvedBefore,
        after,
        pins: {
          'prd-core': _version('1.7.0'),
          'software-tech': _version('1.4.0'),
        },
        restampsFingerprints: false,
      );

      expect(
        run.applied[_storyPath],
        _stamped(after[_storyPath]!, _typeAt(_storyPath)),
      );
      expect(run.applied[_frPath], after[_frPath]);
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
  });

  group('$_fr E31', () {
    test('a matched entry takes the fingerprint of its upstream block after '
        'the run, whether the run rewrote the block or not', () {
      const reworded = '### Scenario 1 — [happy] one\n\n- **Given** a g';
      const untouched = '### Scenario 2 — [edge] two\n\n- **Given** h';
      final before = {
        _storyPath: _story('$_one\n\n$untouched'),
        _frPath: _tracing(
          '  - S1 ${fingerprintOf(_one)}\n  - S2 ${fingerprintOf(untouched)}\n',
        ),
      };
      final after = {
        _storyPath: _story('$reworded\n\n$untouched'),
        _frPath: before[_frPath]!,
      };

      final run = _run(before, after);

      expect(
        run.applied[_frPath],
        contains(
          '  - S1 ${fingerprintOf(reworded)}\n'
          '  - S2 ${fingerprintOf(untouched)}\n',
        ),
      );
      expect(run.pass.planLine, 'stamps: 2 approval hashes, 1 fingerprints');
    });

    test('an entry stamped by the 1.1.0 recipe matches, and takes the '
        'layout-blind fingerprint of its block laid out', () {
      const unpadded =
          '### Scenario 1 — [happy] Table\n| Item | Count |\n| --- | --- |\n'
          '| apple | 2 |';
      const laidOut =
          '### Scenario 1 — [happy] Table\n\n| Item  | Count |\n'
          '| ----- | ----- |\n| apple | 2     |';
      expect(legacyFingerprintOf(unpadded), isNot(fingerprintOf(unpadded)));
      final before = {
        _storyPath: _story(unpadded),
        _frPath: _tracing('  - S1 ${legacyFingerprintOf(unpadded)}\n'),
      };
      final after = {_storyPath: _story(laidOut), _frPath: before[_frPath]!};

      final run = _run(before, after);

      expect(fingerprintOf(laidOut), fingerprintOf(unpadded));
      expect(
        run.applied[_frPath],
        contains('  - S1 ${fingerprintOf(unpadded)}\n'),
      );
    });

    test('an entry already suspect keeps its fingerprint', () {
      final docs = {
        _storyPath: _story(_one),
        _frPath: _tracing('  - S1 000000000000\n'),
      };

      final run = _runUnchanged(docs);

      expect(run.applied[_frPath], contains('  - S1 000000000000\n'));
      expect(run.pass.planLine, 'stamps: 2 approval hashes, 0 fingerprints');
    });

    test('a renumbered block: the entry the renumber pass renamed takes the '
        'fingerprint of the block at its new number', () {
      final before = {
        _storyPath: _story('$_one\n\n$_lettered'),
        _frPath: _tracing('  - S6a ${fingerprintOf(_lettered)}\n'),
      };
      final after = {
        _storyPath: _story('$_one\n\n$_renumbered'),
        _frPath: _tracing('  - S9 ${fingerprintOf(_lettered)}\n'),
      };

      final run = _run(before, after);

      expect(
        run.applied[_frPath],
        contains('  - S9 ${fingerprintOf(_renumbered)}\n'),
      );
    });

    test('a quoted entry keeps its quotes', () {
      const reworded = '### Scenario 1 — [happy] one\n\n- **Given** a g';
      final old = fingerprintOf(_one);
      final before = {
        _storyPath: _story(_one),
        _frPath: '---\nconfirmed:\n  - "S1 $old"\n---\n# C\n',
      };
      final after = {...before, _storyPath: _story(reworded)};

      final run = _run(before, after);

      expect(
        run.applied[_frPath],
        contains('  - "S1 ${fingerprintOf(reworded)}"\n'),
      );
    });

    test('the approval hash covers the stamped entries', () {
      const reworded = '### Scenario 1 — [happy] one\n\n- **Given** a g';
      final before = {
        _storyPath: _story(_one),
        _frPath: _tracing('  - S1 ${fingerprintOf(_one)}\n'),
      };
      final after = {_storyPath: _story(reworded), _frPath: before[_frPath]!};

      final stamped = _run(before, after).applied[_frPath]!;

      final type = _typeAt(_frPath);
      expect(stamped, contains('approved: "${_hashOf(stamped, type)}"'));
      expect(_hashOf(stamped, type), isNot(_hashOf(after[_frPath]!, type)));
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

  group('$_fr E38', () {
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
        [(docPath: _storyPath, lf: approved, type: held)],
        [(docPath: _storyPath, lf: moved, type: dropped)],
        pins: _belowBoth,
        pinsAfter: _belowBoth,
        restampsFingerprints: false,
      );

      final stamped = pass.apply(_storyPath, moved);
      expect(stamped, matches(_approvedHash));
      expect(stamped, contains('approved: "${_hashOf(stamped, dropped)}"'));
      expect(pass.planLine, 'stamps: 1 approval hashes, 0 fingerprints');
    });
  });

  group('records across the statuses rule', () {
    final below = {
      'prd-core': _version('1.7.0'),
      'software-tech': _version('1.6.0'),
    };
    final at = {
      'prd-core': _version('1.7.0'),
      'software-tech': _version('1.7.0'),
    };
    const record =
        "---\nstatuses:\n  - 'b:implemented'\nimplements:\n"
        "  - 'b:app/a.dart'\n---\n\n# Record\n";

    test('a record approved by the hash that counted its statuses takes the '
        'hash that leaves them out', () {
      final type = _typeAt(_recordPath);
      final approved = withApprovalHash(record, type, statusesOutside: false);
      final docs = {_recordPath: approved};

      final run = _run(docs, docs, pins: below, pinsAfter: at);

      final stamped = run.applied[_recordPath]!;
      expect(stamped, withApprovalHash(approved, type, statusesOutside: true));
      expect(
        approvalHashOf(stamped, type, statusesOutside: true),
        isNot(approvalHashOf(stamped, type, statusesOutside: false)),
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
        'specs/f02_c/IMPLEMENTATION.md': record.replaceFirst(
          '---\n',
          '---\ndraft: true\n',
        ),
      };

      final run = _run(docs, docs, pins: below, pinsAfter: at);

      expect(run.applied, docs);
      expect(run.pass.planLine, isNull);
    });

    test('an upgrade that keeps the pins below the rule re-stamps a changed '
        'record by the rule that counts the statuses', () {
      final type = _typeAt(_recordPath);
      final approved = withApprovalHash(record, type, statusesOutside: false);
      final changed = approved.replaceFirst('# Record', '# Login record');

      final run = _run(
        {_recordPath: approved},
        {_recordPath: changed},
        pins: below,
        pinsAfter: below,
      );

      expect(
        run.applied[_recordPath],
        withApprovalHash(changed, type, statusesOutside: false),
      );
    });
  });
}
