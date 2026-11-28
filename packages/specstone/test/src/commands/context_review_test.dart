// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/relative_link.dart';
import '../../../../specstone_core/test/helpers/target_fixture.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

const _featurePath = 'prds/features/f02_signup/FEATURE.md';
const _story = 'prds/features/f02_signup/us01_register/USER_STORY.md';
const _checkEmail =
    'prds/features/f02_signup/us01_register/fr01_check_email.md';
const _sendCode = 'prds/features/f02_signup/us01_register/fr02_send_code.md';
const _checkAddress = 'fr:signup/register/check_email';
const _checkName = 'signup/register/check_email';
const _sendName = 'signup/register/send_code';
const _readFirstName = 'fr-signup-register-check_email.review.txt';
const _refsName = 'fr-signup-register-check_email.review.refs.txt';

/// The printed end of a bundle path, which uses the native separator.
String _bundleEnd(String name) =>
    ['', '.specstone', 'bundles', name].join(Platform.pathSeparator);

const _storyText =
    '---\ndraft: true\n---\n\n# Register\n\n## Use Case\n\nRegister with an email.\n';

const _feature =
    '---\napproved: true\npatterns:\n  - crud\n---\n\n# Signup\n\n'
    '## Problem\n\nUsers create an account.\n\n'
    '## Benefit hypothesis\n\nUsers finish signup faster.\n\n'
    '## Feature flow\n\nThe user types an email.\n\n'
    '## Out-of-scope\n\n- Social login.\n';

String _fr({
  String mark = 'approved: true',
  String edgeCases =
      '1. E01 — A blank email is refused. It names the field.\n'
      '2. E02 — A long email is cut.',
  String extraSections = '',
}) =>
    '---\n$mark\ntraced_from: US-01\nverify_method: test\n---\n\n'
    '# Check email\n\n## Statement\n\nThe system shall check the email.\n\n'
    '## Edge cases\n\n$edgeCases\n$extraSections';

const _sendFr =
    '---\napproved: true\ntraced_from: US-01\nverify_method: test\n---\n\n'
    '# Send code\n\n## Statement\n\n'
    'The system shall send a code after [E01](fr01_check_email.md#edge-cases).\n\n'
    '## Edge cases\n\n1. E01 — A code is sent once.\n';

/// A repository whose first commit holds the approved docs and whose second
/// holds the check-email draft over them, as the approve dry run reads two
/// commits.
Future<Directory> _repo({
  String? draftEdgeCases,
  String draftExtraSections = '',
  Map<String, String> extraFiles = const {},
  Map<String, String> draftFiles = const {},
}) async {
  final root = await writeWriteProject(
    extra: {
      'docs/$_featurePath': _feature,
      'docs/$_story': _storyText,
      'docs/$_checkEmail': _fr(),
      'docs/$_sendCode': _sendFr,
      ...extraFiles,
    },
  );
  expect(git(root, ['init', '-q']).exitCode, 0);
  expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
  commitAll(root, 'approved');
  docFile(root, _checkEmail).writeAsStringSync(
    _fr(
      mark: 'draft: true',
      edgeCases:
          draftEdgeCases ??
          '1. E01 — A blank email is refused with a message.\n'
              '2. E02 — A long email is cut.',
      extraSections: draftExtraSections,
    ),
  );
  for (final MapEntry(:key, :value) in draftFiles.entries) {
    File('${root.path}/$key').writeAsStringSync(value);
  }
  commitAll(root, 'edited as a draft');
  return root;
}

File _bundleFile(Directory root, String name) =>
    File('${root.path}/.specstone/bundles/$name');

bool _hasBundlesFolder(Directory root) =>
    Directory('${root.path}/.specstone/bundles').existsSync();

/// Returns [out]'s stdout lines.
List<String> _linesOf(StringBuffer out) =>
    const LineSplitter().convert(out.toString());

/// Returns [line] with its `<first>-<last>` range written `N-M`.
String _unranged(String line) =>
    line.replaceFirst(RegExp(r' · \d+-\d+'), ' · N-M');

Map<String, Object?> _errorOf(StringBuffer err) =>
    (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
        as Map<String, Object?>;

void main() {
  final skipGit = hasGit ? null : 'git is not available';

  test('context --for review --out writes a read-first and a refs file and prints the read plan with each part kind', () async {
    final root = await _repo();
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['context', _checkAddress, '--for', 'review', '--out']),
      0,
    );

    final lines = _linesOf(out);
    final headerPattern = RegExp(
      r'^==> bundle: (\d+) docs, (\d+) tokens, (\d+) lines · (.+) <==$',
    );
    final header = headerPattern.firstMatch(lines.first)!;
    expect(header.group(4), endsWith(_bundleEnd(_readFirstName)));
    expect(lines[1], 'read whole, in 1 read: lines 1-${header.group(3)}');
    expect(
      [for (final line in lines.skip(2).take(7)) _unranged(line)],
      [
        '- $_checkName (fr) · N-M · changed edge_cases [E01]',
        '- $_sendName (fr) · N-M · citer statement of $_checkName (fr) E01',
        '- signup (feature) · N-M · summary benefit_hypothesis',
        '- signup (feature) · N-M · summary flow',
        '- signup (feature) · N-M · summary out_of_scope',
        '- signup (architecture) · N-M · summary components',
        '- crud (feature pattern) · N-M',
      ],
    );
    final refsHeader = headerPattern.firstMatch(lines[9])!;
    expect(lines, hasLength(12));
    expect(lines[10], lines.first);
    expect(lines.last, lines[1]);
    expect(refsHeader.group(4), endsWith(_bundleEnd(_refsName)));
    expect(_bundleFile(root, _readFirstName).existsSync(), isTrue);
    expect(_bundleFile(root, _refsName).existsSync(), isTrue);
    expect(err.toString(), isEmpty);
  }, skip: skipGit);

  test('the read-first file keeps every part past one read and warns with a plan of two or more ranges', () async {
    final notes = [
      for (var i = 0; i < 3000; i++) 'Line number $i of the notes.',
    ].join('\n');
    final root = await _repo(draftExtraSections: '\n## Behavior\n\n$notes\n');
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['context', _checkAddress, '--for', 'review', '--out']),
      0,
    );

    final lines = _linesOf(out);
    final total = RegExp(r' (\d+) lines ·').firstMatch(lines.first)!.group(1);
    final plan = RegExp(
      r'^read whole, in (\d+) reads: lines 1-\d+(?:, lines \d+-\d+)*, lines \d+-(\d+)$',
    ).firstMatch(lines[1])!;
    final reads = int.parse(plan.group(1)!);
    expect(reads, 3);
    expect(plan.group(2), total);
    expect(
      err.toString(),
      matches(
        RegExp(
          '^⚠️ WARNING: the read-first file holds \\d+ est\\. tokens, more than one read of 20000; the read plan reads it in $reads ranges\\n\$',
        ),
      ),
    );
    final text = _bundleFile(root, _readFirstName).readAsStringSync();
    expect(
      text,
      contains('==> $_checkName (fr) · $_checkEmail#behavior · changed <==\n'),
    );
    expect(
      text,
      contains(
        '==> signup (feature) · $_featurePath#benefit_hypothesis · summary <==\n',
      ),
    );
    expect(
      text,
      contains(
        '==> signup (feature) · $_featurePath#out_of_scope · summary <==\n',
      ),
    );
  }, skip: skipGit);

  test("the refs file holds the refs docs' design bundle with its pattern checklists", () async {
    final root = await _repo();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['context', _checkAddress, '--for', 'review', '--out']),
      0,
    );
    final (runner: designRunner, out: designOut, err: _) = writeRunner(root);
    expect(
      await designRunner.run(['context', _checkAddress, '--for', 'design']),
      0,
    );

    final refs = _bundleFile(root, _refsName).readAsStringSync();

    expect(refs, designOut.toString());
    expect(refs, contains('==> crud (feature pattern) · signup <==\n'));
  }, skip: skipGit);

  test("the read-first file prints the target feature's pattern part after the summary sections, naming its listing doc by typed address", () async {
    final root = await _repo();
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['context', _checkAddress, '--for', 'review', '--out']),
      0,
    );

    final text = _bundleFile(root, _readFirstName).readAsStringSync();
    const naming = '==> crud (feature pattern) · feature:signup <==\n';
    expect(
      text,
      contains(
        '${naming}Create, read, list, update, and delete of one resource.\n',
      ),
    );
    expect(
      text.indexOf(naming),
      greaterThan(
        text.indexOf(
          '==> signup (feature) · $_featurePath#out_of_scope · summary <==\n',
        ),
      ),
    );
  }, skip: skipGit);

  test(
    '--target keeps the review of a name two code targets share to that target',
    () async {
      final root = await writeTwinProject();
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved');
      final jaspr = docFile(root, jasprArchitecture);
      jaspr.writeAsStringSync(
        jaspr
            .readAsStringSync()
            .replaceFirst(RegExp('approved: .*'), 'draft: true')
            .replaceFirst('One box.', 'Two boxes.'),
      );
      commitAll(root, 'edited as a draft');
      final (:runner, :out, :err) = writeRunner(root);

      expect(
        await runner.run([
          'context',
          'architecture:login',
          '--for',
          'review',
          '--out',
          '--target',
          'jaspr',
        ]),
        0,
        reason: err.toString(),
      );

      final header = RegExp(r'^==> bundle: .* · (.+) <==$').firstMatch(
        _linesOf(out).firstWhere((line) => line.startsWith('==> ')),
      )!;
      final text = File(header.group(1)!).readAsStringSync();
      expect(
        text,
        contains('$jasprArchitecture#technical_diagram · changed <==\n'),
      );
      expect(text, isNot(contains('specs/flutter/')));
    },
    skip: skipGit,
  );

  test('--for review --out --json marks each part kind and gives refs out, tokens, and lines alone', () async {
    final root = await _repo();
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run([
        'context',
        _checkAddress,
        '--for',
        'review',
        '--out',
        '--json',
      ]),
      0,
    );

    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    final docs = (json['docs']! as List).cast<Map<String, Object?>>();
    expect(
      [for (final doc in docs) '${doc['name']} ${doc['kind']}'],
      [
        '$_checkName changed',
        '$_sendName citer',
        'signup summary',
        'signup summary',
        'signup summary',
        'signup summary',
        'signup pattern',
      ],
    );
    expect(docs[1]['citesUnits'], ['$_checkName (fr) E01']);
    expect(docs[0].containsKey('citesUnits'), isFalse);
    expect(docs[1].containsKey('cites'), isFalse);
    expect(docs.last['docType'], 'feature');
    expect(json.containsKey('featurePatterns'), isFalse);
    expect(json['reads'], [
      [1, json['lines']],
    ]);
    final refs = json['refs']! as Map<String, Object?>;
    expect(refs.keys.toList(), ['out', 'tokens', 'lines']);
    expect(refs['out'], endsWith(_bundleEnd(_refsName)));
  }, skip: skipGit);

  test(
    '--for review with no target or no --out is argument_missing naming --out',
    () async {
      final root = await writeWriteProject();
      for (final (args, mentions) in [
        (<String>['context', '--for', 'review'], '--out'),
        (<String>['context', _checkAddress, '--for', 'review'], '--out'),
        (<String>['context', '--for', 'review', '--out'], 'a target'),
      ]) {
        final (:runner, :out, :err) = writeRunner(root);
        expect(await runner.run([...args, '--json']), 64, reason: '$args');
        final error = _errorOf(err);
        expect(error['code'], 'argument_missing', reason: '$args');
        expect(error['message'], contains(mentions), reason: '$args');
        expect(_hasBundlesFolder(root), isFalse, reason: '$args');
      }
    },
  );

  test('--for review with --code, --summary, or --budget is argument_conflict and writes nothing', () async {
    final root = await writeWriteProject();
    for (final (extra, flag) in [
      (<String>['--code', 'app/lib/main.dart'], '--code'),
      (<String>['--summary'], '--summary'),
      (<String>['--budget', '100'], '--budget'),
    ]) {
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'context',
          _checkAddress,
          '--for',
          'review',
          '--out',
          ...extra,
          '--json',
        ]),
        64,
        reason: flag,
      );
      final error = _errorOf(err);
      expect(error['code'], 'argument_conflict', reason: flag);
      expect(error['message'], '--for review takes no $flag', reason: flag);
      expect(_hasBundlesFolder(root), isFalse, reason: flag);
    }
  });

  test('--no-project with --for review reaches only the refs file', () async {
    final root = await _repo(
      extraFiles: {
        'docs/prds/GLOSSARY.md': '# Domain glossary\n\n## Terms\n\n- **Account** — a signup record.\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['context', _checkAddress, '--for', 'review', '--out']),
      0,
    );
    final withProject = _bundleFile(root, _readFirstName).readAsStringSync();
    final refsWithProject = _bundleFile(root, _refsName).readAsStringSync();
    final (runner: bareRunner, out: _, err: _) = writeRunner(root);

    expect(
      await bareRunner.run([
        'context',
        _checkAddress,
        '--for',
        'review',
        '--out',
        '--no-project',
      ]),
      0,
    );

    final without = _bundleFile(
      root,
      'fr-signup-register-check_email.review-no-project.txt',
    ).readAsStringSync();
    final refsWithout = _bundleFile(
      root,
      'fr-signup-register-check_email.review-no-project.refs.txt',
    ).readAsStringSync();
    expect(without, withProject);
    const joined = '==> glossary (glossary) · prds/GLOSSARY.md <==\n';
    expect(refsWithProject, contains(joined));
    expect(refsWithout, isNot(contains(joined)));
  }, skip: skipGit);

  test('a review refs file under Claude Code prints each imported doc as a stub', () async {
    const domainText = 'The words every signup doc uses.';
    const domainStub =
        '==> project_rulebook (project_rulebook) · specs/DOMAIN.md · loaded by CLAUDE.md <==\n';
    final root = await _repo(
      extraFiles: {
        'docs/specs/DOMAIN.md': '# Project domain\n\n$domainText\n',
        'CLAUDE.md':
            'Owner text\n\n<!-- BEGIN specstone v1.0.0 -->\n'
            '@docs/specs/DOMAIN.md\n<!-- END specstone -->\n',
      },
    );
    final claude = writeRunner(root, environment: const {'CLAUDECODE': '1'});
    expect(
      await claude.runner.run([
        'context',
        _checkAddress,
        '--for',
        'review',
        '--out',
      ]),
      0,
    );
    final stubbed = _bundleFile(root, _refsName).readAsStringSync();
    expect(stubbed, contains(domainStub));
    expect(stubbed, isNot(contains(domainText)));

    final outside = writeRunner(root, environment: const {});
    expect(
      await outside.runner.run([
        'context',
        _checkAddress,
        '--for',
        'review',
        '--out',
      ]),
      0,
    );
    final whole = _bundleFile(root, _refsName).readAsStringSync();
    expect(whole, contains(domainText));
    expect(whole, isNot(contains('loaded by CLAUDE.md')));
  }, skip: skipGit);

  test(
    'an unresolved target among several review targets writes no file',
    () async {
      final root = await _repo();
      final (:runner, :out, :err) = writeRunner(root);

      expect(
        await runner.run([
          'context',
          _checkAddress,
          'fr:nosuch',
          '--for',
          'review',
          '--out',
        ]),
        64,
      );

      expect(err.toString(), contains('nosuch'));
      expect(out.toString(), isEmpty);
      expect(_hasBundlesFolder(root), isFalse);
    },
    skip: skipGit,
  );

  test('a target that is no draft prints whole with each section heading keyed and its sections listed', () async {
    final root = await _repo();
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run([
        'context',
        'feature:login',
        '--for',
        'review',
        '--out',
      ]),
      0,
    );

    final text = File(
      '${root.path}/.specstone/bundles/feature-login.review.txt',
    ).readAsStringSync();
    expect(
      text,
      startsWith(
        '==> login (feature) · prds/features/f01_login/FEATURE.md <==\n',
      ),
    );
    expect(text, contains('\n## Problem {#problem}\n'));
    final headingLine =
        text.split('\n').indexWhere((line) => line.startsWith('## Problem')) +
        1;
    expect(
      _unranged(_linesOf(out)[2]),
      '- login (feature) · N-M · problem $headingLine',
    );
    // The target prints whole; only its spec docs print summary parts.
    expect(text, isNot(matches(RegExp(r'FEATURE\.md#\w+ · summary <=='))));
  }, skip: skipGit);

  test('a removed item prints under its section by its ID with its dropped sentences', () async {
    final root = await _repo(
      draftEdgeCases: '1. E01 — A blank email is refused. It names the field.',
    );
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['context', _checkAddress, '--for', 'review', '--out']),
      0,
    );

    final text = _bundleFile(root, _readFirstName).readAsStringSync();
    expect(
      text,
      contains(
        '==> $_checkName (fr) · $_checkEmail#edge_cases · item E02 · removed <==\n'
        'Dropped sentences:\n'
        '- E02 — A long email is cut.\n',
      ),
    );
    expect(
      _linesOf(out),
      contains(
        matches(
          RegExp(
            r'^- signup/register/check_email \(fr\) · \d+-\d+ · removed edge_cases \[E02\]$',
          ),
        ),
      ),
    );
  }, skip: skipGit);

  test('a removed block prints under its section by its anchor with its dropped sentences', () async {
    const arch = 'docs/specs/f02_signup/ARCHITECTURE.md';
    const head = '# Signup architecture\n\n## Data\n\n';
    final root = await _repo(
      extraFiles: {
        arch:
            '---\napproved: true\n---\n\n$head### Signup form\n\nCollects the email.\n',
      },
      draftFiles: {arch: '---\ndraft: true\n---\n\n${head}Nothing yet.\n'},
    );
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run([
        'context',
        'architecture:signup',
        '--for',
        'review',
        '--out',
      ]),
      0,
    );

    final text = File(
      '${root.path}/.specstone/bundles/architecture-signup.review.txt',
    ).readAsStringSync();
    expect(
      text,
      contains(
        '==> signup (architecture) · specs/f02_signup/ARCHITECTURE.md#data · block signup-form · removed <==\n',
      ),
    );
  }, skip: skipGit);

  test(
    'a bare --out review from a subfolder writes under the project root',
    () async {
      final root = await _repo();
      final (:runner, :out, :err) = writeRunner(Directory('${root.path}/docs'));

      expect(
        await runner.run([
          'context',
          _checkAddress,
          '--for',
          'review',
          '--out',
        ]),
        0,
      );

      expect(_bundleFile(root, _readFirstName).existsSync(), isTrue);
      expect(_bundleFile(root, _refsName).existsSync(), isTrue);
      expect(Directory('${root.path}/docs/.specstone').existsSync(), isFalse);
    },
    skip: skipGit,
  );

  test(
    'a review target in an untrusted root refuses before any file is written',
    () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/'))
            'ext/${key.substring(5)}': value
          else
            'src/clone/$key': value,
      });
      createRelativeLink('${base.path}/src/clone/docs', '../../ext');
      final clone = Directory('${base.path}/src/clone');
      final docs = Directory('${base.path}/ext');
      final before = treeBytes(docs);
      final (:runner, :out, :err) = writeRunner(clone);

      expect(
        await runner.run([
          'context',
          'user_story:login/email_login',
          '--for',
          'review',
          '--out',
        ]),
        73,
      );

      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        endsWith(
          'lies outside the project; run specstone trust at a terminal to allow it\n',
        ),
      );
      expect(_hasBundlesFolder(clone), isFalse);
      expect(treeBytes(docs), before);
    },
    skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null,
  );
}
