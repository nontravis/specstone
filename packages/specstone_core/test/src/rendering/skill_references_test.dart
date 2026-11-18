import 'dart:io';

import 'package:specstone_core/src/document_writing/reference_links.dart';
import 'package:specstone_core/src/rendering/skill_references.dart';
import 'package:test/test.dart';

import '../../helpers/agent_skills.dart';

const _skill = 'docs/specs/skills/review.md';
const _otherSkill = 'docs/specs/skills/other.md';
const _button = 'docs/specs/design_system/components/buttons/primary_button.md';
const _tokens = 'docs/specs/design_system/foundations/TOKENS.md';
const _contributing = 'docs/specs/design_system/CONTRIBUTING.md';
const _record = '.specstone/records/f05_rendering/IMPLEMENTATION.md';
const _output = '.claude/skills/review';
const _references = '$_output/references';
const _buttonReference =
    '$_references/specs/design_system/components/buttons/primary_button.md';
const _tokensReference =
    '$_references/specs/design_system/foundations/TOKENS.md';

const _buttonLink =
    '[Primary button](../design_system/components/buttons/primary_button.md)';
const _tokensLink = '[Tokens](../design_system/foundations/TOKENS.md)';

const _tokensDoc = '# Tokens\n\n## Token list\n\n- color.primary\n';
const _buttonBody = '# Primary button\n\n## Purpose\n\nStarts an action.\n';
const _buttonDoc =
    '---\nlifecycle: stable\nfeature: login\ndesign_source: design/kit.fig\n'
    '---\n\n$_buttonBody';

const _linksSkip = 'links need privileges on Windows';

SkillReferences _plan(SkillProject project, [String? target]) =>
    SkillReferences.plan(
      project.project,
      project.target(target),
      rewriteLinks: rewriteReferenceLinks,
    );

ExportedSkill _exported(SkillReferences plan, String path) {
  final skill = plan.of(path);
  expect(skill, isA<ExportedSkill>(), reason: path);
  return skill! as ExportedSkill;
}

Map<String, String> _texts(SkillReferences plan, String path) => {
  for (final file in _exported(plan, path).files) file.path: file.text,
};

void _expectRefused(
  SkillReferences plan,
  String path,
  SkillRefusalCode code,
  String message,
) {
  expect(
    plan.of(path),
    isA<RefusedSkill>()
        .having((skill) => skill.code, 'code', code)
        .having((skill) => skill.message, 'message', message),
  );
}

void main() {
  group('a skill doc whose sources name docs', () {
    test('plans one reference file per Sources doc at its path under '
        'references, each as the doc reads on disk, sources outside the '
        'target included', () async {
      final project = await openSkillProject({
        _skill: skillDocText(sources: [_buttonLink, _tokensLink]),
        _button: '---\nlifecycle: stable\n---\n\n$_buttonBody',
        _tokens: _tokensDoc,
      });

      final plan = _plan(project, _skill);

      expect(_texts(plan, _skill), {
        _buttonReference: '---\nlifecycle: stable\n---\n\n$_buttonBody',
        _tokensReference: _tokensDoc,
      });
    });

    test('plans one file for a doc two Sources links name', () async {
      final project = await openSkillProject({
        _skill: skillDocText(
          sources: [
            _tokensLink,
            '[List](../design_system/foundations/TOKENS.md#token-list)',
          ],
        ),
        _tokens: _tokensDoc,
      });

      expect(_texts(_plan(project), _skill).keys, [_tokensReference]);
    });

    test('plans nothing for a skill doc outside the target, though a '
        'source lies under it', () async {
      final project = await openSkillProject({
        _skill: skillDocText(sources: [_tokensLink]),
        _tokens: _tokensDoc,
      });

      final plan = _plan(project, 'docs/specs/design_system');

      expect(plan.skills, isEmpty);
    });

    test('leaves out each frontmatter field whose export is false and keeps '
        'the rest of the doc', () async {
      final project = await openSkillProject({
        _skill: skillDocText(sources: [_buttonLink]),
        _button: _buttonDoc,
      });

      expect(_texts(_plan(project), _skill), {
        _buttonReference: '---\nlifecycle: stable\n---\n\n$_buttonBody',
      });
    });

    test('leaves out every line of an unexported field written as a block '
        'scalar and keeps the next key whole', () async {
      final project = await openSkillProject({
        _skill: skillDocText(sources: [_buttonLink]),
        _button:
            '---\ndesign_source: |-\n  design/kit.fig\n  feature: not a key\n'
            '\n  page two\nlifecycle: >-\n  stable\n  still\n'
            'feature: >-\n  login\n  page\n---\n\n$_buttonBody',
      });

      expect(_texts(_plan(project), _skill), {
        _buttonReference:
            '---\nlifecycle: >-\n  stable\n  still\n---\n\n$_buttonBody',
      });
    });
  });

  group('the doc links of a reference file', () {
    // Each link is written in the button doc, whose folder is
    // specs/design_system/components/buttons.
    const rows = [
      (
        'a link to another Sources doc points at its reference file, its '
            'anchor kept',
        '[props](../../../design_system/foundations/TOKENS.md#props)',
        '[props](../../foundations/TOKENS.md#props)',
      ),
      (
        'a bare anchor link stays as written',
        '[E10](#edge-cases)',
        '[E10](#edge-cases)',
      ),
      (
        'a link to a doc outside the skill shows as text with its path',
        '[guide](../../GUIDELINES.md)',
        'guide (`specs/design_system/GUIDELINES.md`)',
      ),
      (
        'a link to a file such as an image shows as text with its path',
        '[badge](../../img/button.png)',
        'badge (`specs/design_system/img/button.png`)',
      ),
      (
        'a relative link that leaves the docs root shows as text with the '
            'path as written',
        '[readme](../../../../../README.md)',
        'readme (`../../../../../README.md`)',
      ),
      (
        'a web link stays as written',
        '[site](https://example.com/a.md)',
        '[site](https://example.com/a.md)',
      ),
    ];
    for (final (name, written, rewritten) in rows) {
      test(name, () async {
        final project = await openSkillProject({
          _skill: skillDocText(sources: [_buttonLink, _tokensLink]),
          _button:
              '---\nlifecycle: stable\n---\n\n$_buttonBody\nSee $written.\n',
          _tokens: _tokensDoc,
        });

        expect(
          _texts(_plan(project), _skill)[_buttonReference],
          '---\nlifecycle: stable\n---\n\n$_buttonBody\nSee $rewritten.\n',
        );
      });
    }
  });

  group('a skill doc whose sources it cannot take is refused', () {
    const missingRows = [
      ('a link to no file', '[Old](../design_system/OLD.md)'),
      ('a web link', '[Site](https://example.com/x.md)'),
      ('a link that leaves the docs root', '[Readme](../../../README.md)'),
      ('a file no doc type matches', '[Image](../design_system/img/b.png)'),
    ];
    for (final (name, link) in missingRows) {
      test('as missing a source for $name', () async {
        final href = link.substring(link.indexOf('(') + 1, link.length - 1);
        final project = await openSkillProject({
          _skill: skillDocText(sources: [_tokensLink, link]),
          _tokens: _tokensDoc,
          'README.md': '# Readme\n',
          'docs/specs/design_system/img/b.png': 'png',
        });

        _expectRefused(
          _plan(project),
          _skill,
          SkillRefusalCode.skillSourceMissing,
          'the source names no doc: $href',
        );
      });
    }

    test('as not exported for a source whose doc type sets export '
        'false', () async {
      final project = await openSkillProject({
        _skill: skillDocText(
          sources: [
            _tokensLink,
            '[Contributing](../design_system/CONTRIBUTING.md)',
          ],
        ),
        _tokens: _tokensDoc,
        _contributing: '# Contributing\n\n## Definition of done\n\n- x\n',
      });

      _expectRefused(
        _plan(project),
        _skill,
        SkillRefusalCode.skillSourceNotExported,
        "the source's doc type is not exported: $_contributing",
      );
    });

    test('as not exported for a record doc, which sits outside the docs '
        'root', () async {
      final project = await openSkillProject({
        _skill: skillDocText(sources: ['[Record](../../../$_record)']),
        _record: '# rendering\n',
      });

      _expectRefused(
        _plan(project),
        _skill,
        SkillRefusalCode.skillSourceNotExported,
        'the source sits outside the docs root: $_record',
      );
    });

    test('as missing before not exported when the sources hold '
        'both', () async {
      final project = await openSkillProject({
        _skill: skillDocText(
          sources: [
            '[Contributing](../design_system/CONTRIBUTING.md)',
            '[Old](../design_system/OLD.md)',
          ],
        ),
        _contributing: '# Contributing\n\n## Definition of done\n\n- x\n',
      });

      _expectRefused(
        _plan(project),
        _skill,
        SkillRefusalCode.skillSourceMissing,
        'the source names no doc: ../design_system/OLD.md',
      );
    });
  });

  group('a skill doc whose output folder is not allowed is refused', () {
    const rows = [
      (
        'outside the project root',
        '../shared/skills/review/',
        'the output folder is outside the project root',
      ),
      (
        'inside the docs root',
        'docs/skills/review/',
        'the output folder is inside the docs root',
      ),
      (
        'inside the records root',
        '.specstone/records/review/',
        'the output folder is inside the records root',
      ),
    ];
    for (final (name, output, message) in rows) {
      test(name, () async {
        final project = await openSkillProject({
          _skill: skillDocText(output: output, sources: [_tokensLink]),
          _tokens: _tokensDoc,
        });

        _expectRefused(
          _plan(project),
          _skill,
          SkillRefusalCode.skillOutputNotAllowed,
          message,
        );
      });
    }

    const linkRows = [
      ('the output folder', _output),
      ('a folder above the output folder', '.claude'),
      ('the references folder', _references),
      ('a file to write', _tokensReference),
    ];
    for (final (name, linked) in linkRows) {
      test('when $name is a symbolic link', () async {
        final elsewhere = await Directory.systemTemp.createTemp('elsewhere_');
        addTearDown(() => elsewhere.delete(recursive: true));
        final project = await openSkillProject({
          _skill: skillDocText(sources: [_tokensLink]),
          _tokens: _tokensDoc,
        });
        final link = Link('${project.root.path}/$linked');
        link.parent.createSync(recursive: true);
        link.createSync(elsewhere.path);

        _expectRefused(
          _plan(project),
          _skill,
          SkillRefusalCode.skillOutputNotAllowed,
          'the output path crosses a symbolic link: $linked',
        );
      }, skip: Platform.isWindows ? _linksSkip : false);
    }

    test('for both skill docs under the target whose output folders nest, '
        'each naming the other', () async {
      final project = await openSkillProject({
        _skill: skillDocText(sources: [_tokensLink]),
        _otherSkill: skillDocText(
          output: '.claude/skills/review/extra/',
          sources: [_tokensLink],
        ),
        _tokens: _tokensDoc,
      });

      final plan = _plan(project);

      _expectRefused(
        plan,
        _skill,
        SkillRefusalCode.skillOutputNotAllowed,
        'the output folder overlaps $_otherSkill',
      );
      _expectRefused(
        plan,
        _otherSkill,
        SkillRefusalCode.skillOutputNotAllowed,
        'the output folder overlaps $_skill',
      );
    });

    test('for the skill doc under the target whose output folder another '
        'skill doc outside the target shares; that one is not in the '
        'plan', () async {
      final project = await openSkillProject({
        _skill: skillDocText(sources: [_tokensLink]),
        _otherSkill: skillDocText(output: './.claude//skills/review'),
        _tokens: _tokensDoc,
      });

      final plan = _plan(project, _skill);

      _expectRefused(
        plan,
        _skill,
        SkillRefusalCode.skillOutputNotAllowed,
        'the output folder overlaps $_otherSkill',
      );
      expect(plan.of(_otherSkill), isNull);
      expect([for (final skill in plan.skills) skill.path], [_skill]);
    });
  });
}
