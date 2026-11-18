import 'dart:io';

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/search_docs.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

/// Returns the path of [segments] under [project], with native separators.
String _underProject(Directory project, List<String> segments) =>
    [project.path, ...segments].join(Platform.pathSeparator);

void main() {
  late DocIndex index;
  setUpAll(() async => index = await searchIndexWith());
  List<String> heads(ReadAnswer a) => [
    for (final l in a.text.split('\n'))
      if (l.isNotEmpty && !l.startsWith('  ')) l,
  ];

  test(
    'hits name doc and section, with type, title, and an indented snippet',
    () async {
      final answer = answerSearch(
        index,
        'lock the account',
        const SearchOptions(),
      );
      expect(
        heads(answer),
        containsAll([
          'login/email_login/lock_after_failures#statement (fr) — Lock after failures',
          'login/email_login#acceptance_criteria (user_story) — Agent signs in with email',
        ]),
      );
      expect(answer.text, contains('\n  '));
      expect(answer.text, contains('lock the account'));
    },
  );
  test(
    'a Thai phrase hits the untyped doc by DocPath and snake_case key',
    () async {
      expect(heads(answerSearch(index, 'ค้นหา', const SearchOptions())), [
        'prds/d01_context.md#project_vision — D-01 — Project context',
      ]);
    },
  );
  test('a word part matches the longer word', () async {
    expect(
      heads(answerSearch(index, 'ount', const SearchOptions())),
      contains(
        'login/email_login/lock_after_failures#statement (fr) — Lock after failures',
      ),
    );
  });
  test('an alias hit points at the first section', () async {
    expect(
      heads(answerSearch(index, 'sign-in', const SearchOptions())),
      contains('login#problem (feature) — Login'),
    );
  });
  test('quotes, asterisks, AND, and NEAR( are plain text', () async {
    for (final query in ['"lock', 'account*', 'the AND account', 'NEAR(lock']) {
      expect(answerSearch(index, query, const SearchOptions()).exitStatus, 0);
    }
  });
  test('a query inside two words hits the doc of each', () async {
    final both = await searchIndexWith({
      'docs/m/login_note.md': '# Entry\n\n## Body\nlogin here\n',
      'docs/m/catalog_note.md': '# Shelf\n\n## Body\ncatalog here\n',
    });
    expect(
      heads(answerSearch(both, 'log', const SearchOptions())),
      containsAll([
        'm/login_note.md#body — Entry',
        'm/catalog_note.md#body — Shelf',
      ]),
    );
  });
  test('operator characters and words match the literal text only', () async {
    final literal = await searchIndexWith({
      'docs/m/quote_yes.md': '# QY\n\n## Body\nsay "ember" twice\n',
      'docs/m/quote_no.md': '# QN\n\n## Body\nsay ember twice\n',
      'docs/m/star_yes.md': '# SY\n\n## Body\ncat*dog\n',
      'docs/m/star_no.md': '# SN\n\n## Body\ncatdog and cats\n',
      'docs/m/and_yes.md': '# AY\n\n## Body\nrock AND roll\n',
      'docs/m/and_no.md': '# AN\n\n## Body\nrock roll\n',
      'docs/m/near_yes.md': '# NY\n\n## Body\nNEAR(fox\n',
      'docs/m/near_no.md': '# NN\n\n## Body\nNEAR fox\n',
    });
    for (final (query, hit) in [
      ('"ember"', 'm/quote_yes.md#body — QY'),
      ('cat*', 'm/star_yes.md#body — SY'),
      ('rock AND roll', 'm/and_yes.md#body — AY'),
      ('NEAR(fox', 'm/near_yes.md#body — NY'),
    ]) {
      expect(heads(answerSearch(literal, query, const SearchOptions())), [
        hit,
      ], reason: query);
    }
  });
  test('a title hit on a doc with sections names its first section', () async {
    final titled = await searchIndexWith({
      'docs/m/titled.md': '# Quokkas\n\n## First\nxx\n\n## Second\nyy\n',
    });
    final answer = answerSearch(titled, 'Quokkas', const SearchOptions());
    expect(heads(answer), ['m/titled.md#first — Quokkas']);
    final hit = (answer.json['hits']! as List).single as Map;
    expect(hit['section'], 'first');
  });
  test('no hit is an empty answer and success', () async {
    final answer = answerSearch(index, 'zzqqxx', const SearchOptions());
    expect(answer.text, isEmpty);
    expect(answer.json['hits'], isEmpty);
    expect(answer.exitStatus, 0);
  });
  test('fewer than 3 characters is query_too_short', () {
    expect(
      () => checkQuery('ui'),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.message,
          'message',
          'a search needs at least 3 characters: ui',
        ),
      ),
    );
    expect(() => checkQuery('ค้น'), returnsNormally);
  });
  test('--type and --under narrow, --limit caps', () async {
    final answer = answerSearch(
      index,
      'system shall',
      const SearchOptions(docTypeId: 'fr', under: 'login', limit: 2),
    );
    expect(heads(answer), hasLength(2));
    expect(
      heads(answer)
          .every((h) => h.startsWith('login/') && h.contains(' (fr) ')),
      isTrue,
    );
  });
  test('the first search after a doc changed finds the new text and none of '
      'the old', () async {
    final project = await writeLoginProject(
      extra: {'docs/m/note.md': '# Note\n\n## Body\nalpha beta\n'},
    );
    final first = openSession(project, fillSearchRows: true);
    expect(heads(answerSearch(first.index, 'alpha', const SearchOptions())), [
      'm/note.md#body — Note',
    ]);
    first.close();
    File(_underProject(project, ['docs', 'm', 'note.md']))
        .writeAsStringSync('# Note\n\n## Body\ngamma delta epsilon\n');
    final second = openSession(project, fillSearchRows: true);
    addTearDown(second.close);
    expect(heads(answerSearch(second.index, 'delta', const SearchOptions())), [
      'm/note.md#body — Note',
    ]);
    expect(
      heads(answerSearch(second.index, 'alpha', const SearchOptions())),
      isEmpty,
    );
  });
  test('a read that does not search leaves the search rows unwritten, and the '
      'first search after it still finds every doc', () async {
    final project = await writeLoginProject();
    openSession(project).close();
    final raw = sqlite3.open(_underProject(project, [indexFilePath]));
    addTearDown(raw.close);
    expect(raw.select('SELECT count(*) FROM doc_search').single.columnAt(0), 0);
    final searcher = openSession(project, fillSearchRows: true);
    addTearDown(searcher.close);
    expect(
      heads(answerSearch(searcher.index, 'ค้นหา', const SearchOptions())),
      ['prds/d01_context.md#project_vision — D-01 — Project context'],
    );
  });
  test('a session opened without its search rows refuses to search, never '
      'answering from missing rows', () async {
    final session = openSession(await writeLoginProject());
    addTearDown(session.close);
    expect(
      () => answerSearch(session.index, 'login', const SearchOptions()),
      throwsStateError,
    );
  });
  test('20 hits at most by default, untyped docs included', () async {
    final zebras = await searchIndexWith({
      for (var i = 1; i <= 25; i++)
        'docs/z/zebra_$i.md': '# Z\n\n## Body\nzebra\n',
    });
    final hits = heads(answerSearch(zebras, 'zebra', const SearchOptions()));
    expect(hits, hasLength(20));
    expect(hits.every((h) => h.startsWith('z/zebra_')), isTrue);
  });
  test('an unknown --type is doc_type_unknown', () async {
    expect(
      () => answerSearch(index, 'login', const SearchOptions(docTypeId: 'frr')),
      throwsA(isA<TemplateFault>()),
    );
  });
  test('an --under no doc carries is doc_not_found', () async {
    expect(
      () => answerSearch(index, 'login', const SearchOptions(under: 'logn')),
      throwsA(isA<IndexFault>()),
    );
  });
  test('--type drops untyped docs', () async {
    expect(
      heads(
        answerSearch(index, 'ค้นหา', const SearchOptions(docTypeId: 'feature')),
      ),
      isEmpty,
    );
  });
  test('a --limit that is not a positive integer is argument_invalid', () {
    for (final v in ['0', '-5', 'ten']) {
      expect(
        () => parsePositiveOption('--limit', v),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.message,
            'message',
            '--limit takes a positive integer, not $v',
          ),
        ),
      );
    }
  });
  test('a title hit on a doc with no section prints no key', () async {
    final answer = answerSearch(index, 'Readme', const SearchOptions());
    expect(heads(answer), contains('README.md — Readme'));
    expect(
      (answer.json['hits']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((h) => h['name'] == 'README.md')
          .containsKey('section'),
      isFalse,
    );
  });
  test('a snippet over several lines prints as one indented line, JSON keeps '
      'it as indexed', () async {
    final multi = await searchIndexWith({
      'docs/m/multi.md': '# M\n\n## Body\nalpha beta\ngamma delta\n',
    });
    final answer = answerSearch(multi, 'alpha', const SearchOptions());
    expect(answer.text, 'm/multi.md#body — M\n  alpha beta gamma delta\n');
    expect(
      ((answer.json['hits']! as List).single as Map)['snippet'],
      'alpha beta\ngamma delta\n',
    );
  });

  test('--under with --target stays in that '
      'target, an unknown name is argument_invalid', () async {
    const feature = 'prds/features/f01_toast/FEATURE.md';
    const flutterArch = 'specs/flutter/f01_toast/ARCHITECTURE.md';
    const jasprArch = 'specs/jaspr/f01_toast/ARCHITECTURE.md';
    final session = openSession(
      await writeTree({
        '.specstone/templates/architecture.yaml':
            'id: architecture\nper_target: true\n',
        '.specstone/templates/implementation.yaml':
            'id: implementation\n'
            'description: One feature record per target.\n'
            'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
            'parent: feature\n'
            'per_target: true\n'
            'fields:\n'
            '  - id: statuses\n'
            '    type: record_status\n'
            '    list: true\n',
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  flutter:\n    code_root: flutter_lib\n'
            '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/$feature': '# Toast\n\n## Problem\nWarm toast.\n',
        'docs/$flutterArch':
            '# Toast architecture\n\n## Purpose\nWarm toast on flutter.\n',
        'docs/$jasprArch':
            '# Toast architecture\n\n## Purpose\nWarm toast on jaspr.\n',
      }),
      fillSearchRows: true,
    );
    addTearDown(session.close);
    final scoped = answerSearch(
      session.index,
      'Warm toast',
      const SearchOptions(under: 'toast', codeTarget: 'jaspr'),
    );
    expect(scoped.text, contains('Warm toast on jaspr.'));
    expect(
      scoped.text,
      isNot(contains('on flutter')),
      reason:
          "jaspr's name keeps only its own architecture doc; the flutter "
          'twin would print its own marker text',
    );
    expect(
      () => answerSearch(
        session.index,
        'Toast',
        const SearchOptions(codeTarget: 'web'),
      ),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having(
              (f) => f.message,
              'message',
              '--target web: the code targets are flutter, jaspr',
            ),
      ),
    );
  });
}
