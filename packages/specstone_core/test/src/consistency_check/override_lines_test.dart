// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/override_lines.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/project_domain_fixture.dart';
import '../../helpers/shipped_pins.dart';

const _overridesField =
    'fields:\n  - id: overrides\n    type: string\n    list: true\n';

const Map<String, String> _templates = {
  '.specstone/templates/domain.yaml': _overridesField,
  '.specstone/templates/topic.yaml': _overridesField,
  ...projectDomainTemplate,
};

const _loginDomain = 'specs/f01_login/DOMAIN.md';
const _rootDomain = 'specs/DOMAIN.md';
const _payDomain = 'specs/f02_pay/DOMAIN.md';
const _topic = 'specs/topics/rules.md';

/// The file line of the first item a [_domain] body holds.
const _firstItemLine = 5;

/// The address of the rule a root doc holds: its doc type, its name, its ID.
const _rootAddress = 'project_domain:project_domain#INV-3';

const _rootRule = '- **INV-3** A cart expires after 7 days.';
const _because = 'carts expire after 7 days, because a cart holds stock';
const _toRoot = '../DOMAIN.md#invariants';

String _domain(List<String> items) =>
    '# Domain\n\n## Invariants\n\n${items.join('\n')}\n';

String _topicDoc(List<String> items) =>
    '---\ncovers:\n  - app/lib/\n---\n\n# Rules\n\n## Rules\n\n${items.join('\n')}\n';

/// The file line of the first item a [_topicDoc] body holds.
const _firstTopicItemLine = 10;

final _base = <String, String>{
  ..._templates,
  'docs/$_rootDomain': _domain([_rootRule]),
};

Map<String, String> _withLoginDomain(List<String> items) => {
  ..._base,
  'docs/$_loginDomain': _domain(items),
};

// The docs stay as written, so the file lines the tests name hold.
Future<Directory> _write(Map<String, String> files) => writeCheckProject(
  extra: files,
  unstamped: {for (final path in files.keys) path},
);

typedef _Read = ({List<OverrideLine> lines, List<Finding> findings});

Future<_Read> _read(Map<String, String> files, String docPath) async {
  final session = openSession(await _write(files));
  try {
    final context = CheckContext(session);
    final doc = context.index.at(docPath)!;
    return (
      lines: overrideLinesOf(context, doc),
      findings: checkOverrideLines(context, doc).toList(),
    );
  } finally {
    session.close();
  }
}

Future<List<Finding>> _runFindings(Map<String, String> files) async {
  final report = checkOf(await _write(files));
  return [
    for (final finding in report.findings)
      if (finding.kind == FindingKind.overrideLineMalformed ||
          finding.kind == FindingKind.overrideNotInChain)
        finding,
  ];
}

void main() {
  test('a line linking a root rule is one tracked override', () async {
    final read = await _read(
      _withLoginDomain([
        '- **INV-1** An account holds one email.',
        '- Overrides: [INV-3]($_toRoot) — $_because',
      ]),
      _loginDomain,
    );
    expect(read.findings, isEmpty);
    expect(read.lines, hasLength(1));
    final line = read.lines.single;
    expect(line.line, _firstItemLine + 1);
    expect(line.address, _rootAddress);
    expect(line.upstream, _rootDomain);
    expect(line.itemId, 'INV-3');
    expect(line.itemText, contains('A cart expires after 7 days.'));
  });

  test('a section link is malformed', () async {
    final read = await _read(
      _withLoginDomain(['- Overrides: [invariants]($_toRoot) — $_because']),
      _loginDomain,
    );
    expect(read.findings, hasLength(1));
    final finding = read.findings.single;
    expect(finding.kind, FindingKind.overrideLineMalformed);
    expect(finding.line, _firstItemLine);
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys, {'target': _toRoot});
    expect(read.lines.single.address, isNull);
  });

  test('a line with no link is malformed with its text as target', () async {
    final read = await _read(
      _withLoginDomain(['- Overrides: INV-3 — $_because']),
      _loginDomain,
    );
    final finding = read.findings.single;
    expect(finding.kind, FindingKind.overrideLineMalformed);
    expect(finding.line, _firstItemLine);
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys, {'target': 'INV-3'});
  });

  test('an empty marker is malformed with an empty target', () async {
    final read = await _read(_withLoginDomain(['- Overrides:']), _loginDomain);
    final finding = read.findings.single;
    expect(finding.kind, FindingKind.overrideLineMalformed);
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys, {'target': ''});
  });

  test('a sibling feature doc is out of chain', () async {
    final files = {
      ..._withLoginDomain([
        '- Overrides: [INV-1](../f02_pay/DOMAIN.md#invariants) — $_because',
      ]),
      'docs/prds/features/f02_pay/FEATURE.md': '# Pay\n',
      'docs/$_payDomain': _domain(['- **INV-1** A payment settles once.']),
    };
    final read = await _read(files, _loginDomain);
    final finding = read.findings.single;
    expect(finding.kind, FindingKind.overrideNotInChain);
    expect(finding.line, _firstItemLine);
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys, {
      'target': '../f02_pay/DOMAIN.md#invariants',
      'doc': _payDomain,
    });
    expect(read.lines.single.address, isNull);
  });

  test("another target's doc is out of chain", () async {
    const flutterDomain = 'specs/flutter/f01_login/DOMAIN.md';
    const jasprRoot = 'specs/jaspr/DOMAIN.md';
    final files = {
      ..._templates,
      '.specstone/config.yaml':
          '${shippedPinsConfig()}targets:\n'
          '  flutter:\n    code_root: flutter_lib\n'
          '  jaspr:\n    code_root: jaspr_lib\n',
      'flutter_lib/.keep': '',
      'jaspr_lib/.keep': '',
      'docs/specs/flutter/DOMAIN.md': _domain([_rootRule]),
      'docs/$jasprRoot': _domain(['- **INV-3** A cart never expires.']),
      'docs/$flutterDomain': _domain([
        '- Overrides: [INV-3](../../jaspr/DOMAIN.md#invariants) — $_because',
        '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because',
      ]),
    };
    final read = await _read(files, flutterDomain);
    expect(read.findings, hasLength(1));
    final finding = read.findings.single;
    expect(finding.kind, FindingKind.overrideNotInChain);
    expect(finding.line, _firstItemLine);
    expect(finding.keys, {
      'target': '../../jaspr/DOMAIN.md#invariants',
      'doc': jasprRoot,
    });
    expect(read.lines.last.address, _rootAddress);
  });

  test('a topic, a PRD doc, or the doc itself is out of chain', () async {
    final files = {
      ..._withLoginDomain([
        '- **INV-1** An account holds one email.',
        '- Overrides: [RULE-1](../topics/rules.md#rules) — $_because',
        '- Overrides: [INV-1](../../prds/features/f01_login/FEATURE.md#problem) — $_because',
        '- Overrides: [INV-1](DOMAIN.md#invariants) — $_because',
      ]),
      'docs/$_topic': _topicDoc(['- **RULE-1** A rule holds.']),
    };
    final read = await _read(files, _loginDomain);
    expect(
      [for (final f in read.findings) f.kind],
      [
        FindingKind.overrideNotInChain,
        FindingKind.overrideNotInChain,
        FindingKind.overrideNotInChain,
      ],
    );
    expect(
      [for (final f in read.findings) f.keys['doc']],
      [_topic, loginFeature, _loginDomain],
    );
    expect(
      [for (final f in read.findings) f.line],
      [_firstItemLine + 1, _firstItemLine + 2, _firstItemLine + 3],
    );
    expect(read.lines.map((l) => l.address), everyElement(isNull));
  });

  test('a missing item gives only link_item_missing', () async {
    final files = _withLoginDomain([
      '- Overrides: [INV-99]($_toRoot) — $_because',
    ]);
    expect(await _runFindings(files), isEmpty);
    final report = checkOf(await _write(files));
    expect(
      report.findings.map((f) => f.kind),
      contains(FindingKind.linkItemMissing),
    );
    final read = await _read(files, _loginDomain);
    expect(read.findings, isEmpty);
    expect(read.lines.single.itemText, isNull);
  });

  test('a topic line linking a root rule is read', () async {
    final files = {
      ..._base,
      'docs/$_topic': _topicDoc([
        '- **RULE-1** A rule holds.',
        '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because',
        '- Overrides: [INV-1](../f01_login/DOMAIN.md#invariants) — $_because',
      ]),
      'docs/$_loginDomain': _domain([
        '- **INV-1** An account holds one email.',
      ]),
    };
    final findings = await _runFindings(files);
    expect(findings, hasLength(1));
    expect(findings.single.kind, FindingKind.overrideNotInChain);
    expect(findings.single.path, _topic);
    expect(findings.single.line, _firstTopicItemLine + 2);
    expect(findings.single.keys['doc'], _loginDomain);
    final read = await _read(files, _topic);
    expect(read.lines.first.address, _rootAddress);
  });

  test(
    "a nested feature line linking its parent feature's rule is in chain",
    () async {
      const shopDomain = 'specs/f02_shop/DOMAIN.md';
      const cartDomain = 'specs/f02_shop/f01_cart/DOMAIN.md';
      final files = {
        ..._base,
        'docs/prds/features/f02_shop/FEATURE.md': '# Shop\n',
        'docs/prds/features/f02_shop/f01_cart/FEATURE.md': '# Cart\n',
        'docs/$shopDomain': _domain(['- **INV-3** A cart holds stock.']),
        'docs/$cartDomain': _domain([
          '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because',
        ]),
      };
      final read = await _read(files, cartDomain);
      expect(read.findings, isEmpty);
      expect(read.lines.single.address, 'domain:shop#INV-3');
      expect(read.lines.single.upstream, shopDomain);
    },
  );

  test('lines in tech stack, root, and record docs are not read', () async {
    const record = 'specs/f01_login/IMPLEMENTATION.md';
    final files = {
      ..._base,
      'docs/$_rootDomain': _domain([
        _rootRule,
        '- Overrides: INV-3 — $_because',
      ]),
      'docs/$techStack':
          '---\ncode:\n  - app/lib/\n---\n\n# Tech stack\n\n## Stack\n\n- Overrides: INV-3 — $_because\n',
      'docs/$record':
          "---\nstatuses:\n  - 'email_login:implemented'\n---\n\n# Record\n\n- Overrides: INV-3 — $_because\n",
    };
    for (final path in [_rootDomain, techStack, record]) {
      final read = await _read(files, path);
      expect(read.findings, isEmpty, reason: path);
      expect(read.lines, isEmpty, reason: path);
    }
    expect(await _runFindings(files), isEmpty);
  });

  test('two lines linking one item share one address', () async {
    final read = await _read(
      _withLoginDomain([
        '- Overrides: [INV-3]($_toRoot) — $_because',
        '- Overrides: [INV-3]($_toRoot) — a second reason, because stock',
      ]),
      _loginDomain,
    );
    expect(read.findings, isEmpty);
    expect(read.lines.map((l) => l.address), [_rootAddress, _rootAddress]);
  });

  test('two spellings of one linked path share one tracked link', () async {
    final read = await _read(
      _withLoginDomain([
        '- Overrides: [INV-3]($_toRoot) — $_because',
        '- Overrides: [INV-3](../f01_login/../DOMAIN.md#invariants) — $_because',
      ]),
      _loginDomain,
    );
    expect(read.findings, isEmpty);
    expect({for (final l in read.lines) l.address}, {_rootAddress});
    expect({for (final l in read.lines) l.upstream}, {_rootDomain});
  });

  test('a plain item link is no override', () async {
    final read = await _read(
      _withLoginDomain(['- Follows [INV-3]($_toRoot) without exception.']),
      _loginDomain,
    );
    expect(read.lines, isEmpty);
    expect(read.findings, isEmpty);
  });

  test('an nf keeps its own overrides field out of override checks', () async {
    final files = {
      ..._base,
      ...doc(
        loginNf,
        'Users wait.\n\n## Verification',
        'Users wait.\n\n- Overrides: NFR-P01 — x\n\n## Verification',
      ),
    };
    final read = await _read(files, loginNf);
    expect(read.lines, isEmpty);
    expect(read.findings, isEmpty);
    final session = openSession(await _write(files));
    addTearDown(session.close);
    final context = CheckContext(session);
    expect(
      carriesOverrides(context.typeOf(context.index.at(loginNf)!)),
      isFalse,
    );
    expect(
      carriesOverrides(context.typeOf(context.index.at(_rootDomain)!)),
      isTrue,
    );
    expect(carriesOverrides(null), isFalse);
  });

  test(
    'only a list item that opens with the marker is an override line',
    () async {
      final read = await _read(
        _withLoginDomain([
          '- A rule that says Overrides: [INV-3]($_toRoot) — $_because',
          'Overrides: [INV-3]($_toRoot) — $_because',
        ]),
        _loginDomain,
      );
      expect(read.lines, isEmpty);
      expect(read.findings, isEmpty);
    },
  );

  test('an override line inside fenced code is not read', () async {
    final read = await _read(
      _withLoginDomain(['```text', '- Overrides: INV-3 — $_because', '```']),
      _loginDomain,
    );
    expect(read.lines, isEmpty);
    expect(read.findings, isEmpty);
  });

  test('a doc type without the overrides field is not read', () async {
    final files = {
      ..._base,
      '.specstone/templates/domain.yaml': 'id: domain\n',
      'docs/$_loginDomain': _domain(['- Overrides: INV-3 — $_because']),
    };
    final read = await _read(files, _loginDomain);
    expect(read.lines, isEmpty);
    expect(read.findings, isEmpty);
  });

  test(
    'a line whose link names no indexed doc gives no override finding',
    () async {
      final read = await _read(
        _withLoginDomain([
          '- Overrides: [INV-3](../NOWHERE.md#invariants) — $_because',
        ]),
        _loginDomain,
      );
      expect(read.findings, isEmpty);
      expect(read.lines.single.address, isNull);
    },
  );
}
