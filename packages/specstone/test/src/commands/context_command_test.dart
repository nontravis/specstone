// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  test('f01/us05/s1: context for a story prints the bundle and its doc list, exit 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['context', 'login/email_login', '--for', 'implement']),
      0,
    );
    expect(out.toString(), contains('==> bundle: '));
    expect(out.toString(), endsWith('- login (architecture)\n'));
  });
  test('f01/us05/fr01/e10: no target, no --for, or another --for value refuses with exit 64', () async {
    final project = await writeReadProject();
    final noTarget = readRunner(project);
    expect(await noTarget.runner.run(['context', '--for', 'implement']), 64);
    expect(
      noTarget.err.toString(),
      'context needs a target or --code, such as specstone context login --for implement\n',
    );
    final noMode = readRunner(project);
    expect(await noMode.runner.run(['context', 'login']), 64);
    expect(
      noMode.err.toString(),
      'context needs --for, such as specstone context login --for implement\n',
    );
    final badMode = readRunner(project);
    expect(
      await badMode.runner.run(['context', 'login', '--for', 'deploy']),
      64,
    );
    expect(
      badMode.err.toString(),
      '--for takes query, implement, or design, not deploy\n',
    );
  });
  test('f01/us05/s15, db-r6: context --summary on a feature prints its stories in summary, exit 0', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['context', 'login', '--for', 'design', '--summary']),
      0,
    );
    expect(
      out.toString(),
      contains('- login/email_login (user_story) · summary\n'),
    );
  });
  test('f01/us05/fr01/e18, db-c2: --summary with another mode or --code refuses with exit 64', () async {
    final project = await writeReadProject();
    final mode = readRunner(project);
    expect(
      await mode.runner.run([
        'context',
        'login',
        '--for',
        'implement',
        '--summary',
      ]),
      64,
    );
    expect(mode.err.toString(), '--summary works only with --for design\n');
    final code = readRunner(project);
    expect(
      await code.runner.run([
        'context',
        '--code',
        'app/lib/src/login/',
        '--for',
        'design',
        '--summary',
      ]),
      64,
    );
    expect(code.err.toString(), 'give --summary with a target, not --code\n');
  });
  test(
    'f01/us05/fr01/e17, db-c2: --summary on a story refuses with exit 64',
    () async {
      final r = readRunner(await writeReadProject());
      expect(
        await r.runner.run([
          'context',
          'login/email_login',
          '--for',
          'design',
          '--summary',
        ]),
        64,
      );
      expect(
        r.err.toString(),
        '--summary takes a doc with children and no parent, such as a feature; login/email_login (user_story) is not one\n',
      );
    },
  );
  test('f01/us05/fr03/e06: over budget with --json exits 1 with stdout one object and stderr empty', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run([
        'context',
        'login/email_login',
        '--for',
        'implement',
        '--budget',
        '1',
        '--json',
      ]),
      1,
    );
    expect((jsonDecode(out.toString()) as Map)['overBudget'], isTrue);
    expect(err.toString(), isEmpty);
  });
  test('f01/us01/s7, f01/us05/s10: an untyped target exits 64 with the untyped_target message', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run([
        'context',
        'prds/d01_context.md',
        '--for',
        'implement',
      ]),
      64,
    );
    expect(
      err.toString(),
      'prds/d01_context.md has no doc type, so it never joins a bundle; read it with specstone get\n',
    );
  });
  test('f01/us05/s13, f01/us05/fr01/e12: outside a project, or under a 9.9.9 pin, exits 78', () async {
    expect(
      await readRunner(await writeTree({})).runner
          .run(['context', 'login', '--for', 'query']),
      78,
    );
    final pinned = await writeReadProject(
      extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
    );
    expect(
      await readRunner(pinned).runner
          .run(['context', 'login', '--for', 'query']),
      78,
    );
  });
  test('f01/us05/s11, f01/us05/fr04/e07: a target and --code together are argument_conflict, exit 64', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: {'app/lib/main.dart': ''}),
    );
    expect(
      await runner.run([
        'context',
        'login',
        '--code',
        'app/lib/main.dart',
        '--for',
        'query',
      ]),
      64,
    );
    expect(err.toString(), 'give a target or --code, not both\n');
  });
  test('f01/us05/s7, f01/us05/fr04/e06: an unmatched code path exits 0 with the warning on stderr', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: {'app/lib/main.dart': ''}),
    );
    expect(
      await runner.run([
        'context',
        '--code',
        'app/lib/main.dart',
        '--for',
        'implement',
      ]),
      0,
    );
    expect(
      err.toString(),
      '⚠️ WARNING: no doc covers or implements app/lib/main.dart\n',
    );
  });
  test("f01/us05/fr04: under --json the object's first key is code", () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(extra: {'app/lib/main.dart': ''}),
    );
    expect(
      await runner.run([
        'context',
        '--code',
        'app/lib/main.dart',
        '--for',
        'implement',
        '--json',
      ]),
      0,
    );
    expect((jsonDecode(out.toString()) as Map).keys.first, 'code');
  });
  test('f01/us05/s12, f01/us05/fr04/e09: a code path outside the project exits 64 and names it', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['context', '--code', '../', '--for', 'implement']),
      64,
    );
    expect(err.toString(), 'the code path ../ lies outside the code root\n');
  });
  test('f01/us05/fr04/e12, s05: --code "" is argument_invalid, exit 64, and opens no index', () async {
    final project = await writeReadProject();
    final (:runner, :out, :err) = readRunner(project);
    expect(
      await runner.run(['context', '--code', '', '--for', 'implement']),
      64,
    );
    expect(err.toString(), '--code takes a file or folder, not ""\n');
    expect(out.toString(), isEmpty);
    expect(
      File('${project.path}/.specstone/index.sqlite').existsSync(),
      isFalse,
    );
  });
  test("sf-c7: context shop/cart/add_item --for design prints shop's names list with shop/pay", () async {
    final (:runner, :out, :err) = readRunner(await writeNestedProject());
    expect(
      await runner.run(['context', 'shop/cart/add_item', '--for', 'design']),
      0,
    );
    expect(out.toString(), contains('==> names: shop (feature) <==\n'));
    expect(
      out.toString(),
      matches(
        RegExp(r'^- shop/pay \(feature\) · \d+ tokens$', multiLine: true),
      ),
    );
  });

  group('f01/us05/fr01, per code target', () {
    /// Writes the two-target fixture of pick_bundle_docs E23: the feature
    /// `feedback/toast`, its story `show`, and its architecture doc in both
    /// targets.
    Future<Directory> writeToastProject({
      Map<String, String> extra = const {},
    }) => writeReadProject(
      extra: {
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
            '    list: true\n'
            '  - id: implements\n'
            '    type: output_ref\n'
            '    list: true\n'
            '    pointer: item_exact\n',
        '.specstone/templates/tech_stack.yaml':
            'id: tech_stack\nper_target: true\n',
        '.specstone/config.yaml':
            'packs:\n'
            '  prd-core: ${shippedPackVersions()['prd-core']}\n'
            '  software-tech: ${shippedPackVersions()['software-tech']}\n'
            'targets:\n'
            '  flutter:\n    code_root: flutter_lib\n'
            '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/prds/features/f02_feedback/FEATURE.md': '# Feedback\n',
        'docs/prds/features/f02_feedback/f03_toast/FEATURE.md': '# Toast\n',
        'docs/prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md':
            '# Agent sees a toast\n',
        'docs/specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md':
            '---\ncovers:\n  - lib/\n---\n\n# Toast architecture\n',
        'docs/specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md':
            '---\ncovers:\n  - lib/\n---\n\n# Toast architecture\n',
        'docs/specs/flutter/TECH_STACK.md': '# Toast stack\n',
        'docs/specs/jaspr/TECH_STACK.md': '# Toast stack\n',
        'docs/specs/flutter/f02_feedback/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            '  - toast/show:implemented\n'
            'implements:\n'
            '  - toast/show:lib/toast.dart:showToast\n'
            '---\n\n# Record\n',
        'docs/specs/jaspr/f02_feedback/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            '  - toast/show:implemented\n'
            'implements:\n'
            '  - toast/show:lib/toast.dart:showToast\n'
            '---\n\n# Record\n',
        ...extra,
      },
    );

    test('f01/us05/fr01/e23: implement with two targets and no --target exits 64 naming them', () async {
      final (:runner, :out, :err) = readRunner(await writeToastProject());
      expect(
        await runner.run([
          'context',
          'feedback/toast/show',
          '--for',
          'implement',
        ]),
        64,
      );
      expect(
        err.toString(),
        '--for implement needs --target with two or more code targets; '
        'the targets are flutter, jaspr\n',
      );
      expect(out.toString(), isEmpty);
    });

    test('f01/us05/fr01/e24: --target jaspr prints jaspr spec docs and no flutter doc', () async {
      final (:runner, :out, :err) = readRunner(await writeToastProject());
      expect(
        await runner.run([
          'context',
          'feedback/toast/show',
          '--for',
          'implement',
          '--target',
          'jaspr',
        ]),
        0,
      );
      expect(
        out.toString(),
        contains(
          '==> feedback/toast (architecture) · specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md <==\n',
        ),
      );
      expect(
        out.toString(),
        contains(
          '==> feedback (implementation) · specs/jaspr/f02_feedback/IMPLEMENTATION.md <==\n',
        ),
      );
      expect(
        out.toString(),
        contains(
          '==> tech_stack (tech_stack) · specs/jaspr/TECH_STACK.md <==\n',
        ),
      );
      expect(out.toString(), isNot(contains('flutter')));
      expect(err.toString(), isEmpty);
    });

    test(
      'f01/us05/fr04/e13: --code under one root takes that target alone',
      () async {
        final project = await writeToastProject(
          extra: {'jaspr_lib/lib/toast.dart': ''},
        );
        final (:runner, :out, :err) = readRunner(project);
        expect(
          await runner.run([
            'context',
            '--code',
            'jaspr_lib/lib/toast.dart',
            '--for',
            'implement',
          ]),
          0,
        );
        expect(
          out.toString(),
          contains(
            '==> feedback/toast (architecture) · specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md <==\n',
          ),
        );
        expect(
          out.toString(),
          contains(
            '==> feedback (implementation) · specs/jaspr/f02_feedback/IMPLEMENTATION.md <==\n',
          ),
        );
        expect(
          out.toString(),
          contains(
            '==> tech_stack (tech_stack) · specs/jaspr/TECH_STACK.md <==\n',
          ),
        );
        expect(out.toString(), isNot(contains('flutter')));
        expect(err.toString(), isEmpty);
      },
    );

    test('f01/us05/fr04/e15: --code with --target naming another target is argument_conflict, exit 64', () async {
      final project = await writeToastProject(
        extra: {'jaspr_lib/lib/toast.dart': ''},
      );
      final (:runner, :out, :err) = readRunner(project);
      expect(
        await runner.run([
          'context',
          '--code',
          'jaspr_lib/lib/toast.dart',
          '--for',
          'implement',
          '--target',
          'flutter',
        ]),
        64,
      );
      expect(
        err.toString(),
        'the code path jaspr_lib/lib/toast.dart lies in the code target '
        'jaspr, not flutter\n',
      );
      final same = readRunner(project);
      expect(
        await same.runner.run([
          'context',
          '--code',
          'jaspr_lib/lib/toast.dart',
          '--for',
          'implement',
          '--target',
          'jaspr',
        ]),
        0,
      );
      expect(same.err.toString(), isEmpty);
    });

    test('s04/inv26: --code with an unheld or premature --target is argument_invalid, exit 64', () async {
      final project = await writeToastProject(
        extra: {'jaspr_lib/lib/toast.dart': ''},
      );
      final unheld = readRunner(project);
      expect(
        await unheld.runner.run([
          'context',
          '--code',
          'jaspr_lib/lib/toast.dart',
          '--for',
          'implement',
          '--target',
          'ci',
        ]),
        64,
      );
      expect(
        unheld.err.toString(),
        '--target ci: the code targets are flutter, jaspr\n',
      );

      final unnamed = readRunner(
        await writeReadProject(extra: {'app/lib/main.dart': ''}),
      );
      expect(
        await unnamed.runner.run([
          'context',
          '--code',
          'app/lib/main.dart',
          '--for',
          'implement',
          '--target',
          'ci',
        ]),
        64,
      );
      expect(
        unnamed.err.toString(),
        '--target ci: this project names no code target\n',
      );
    });

    test('f01/us05/fr04/e14, review focus 2: nested code roots pick the longest that holds the path', () async {
      final project = await writeReadProject(
        extra: {
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
          '.specstone/templates/tech_stack.yaml':
              'id: tech_stack\nper_target: true\n',
          '.specstone/config.yaml':
              'packs:\n'
              '  prd-core: ${shippedPackVersions()['prd-core']}\n'
              '  software-tech: ${shippedPackVersions()['software-tech']}\n'
              'targets:\n'
              '  app:\n    code_root: .\n'
              '  web:\n    code_root: packages/web\n',
          'docs/prds/features/f02_feedback/FEATURE.md': '# Feedback\n',
          'docs/specs/app/TECH_STACK.md': '# Stack\n',
          'docs/specs/web/TECH_STACK.md': '# Stack\n',
          'docs/specs/app/f02_feedback/IMPLEMENTATION.md': '# Record\n',
          'docs/specs/web/f02_feedback/IMPLEMENTATION.md': '# Record\n',
          'lib/main.dart': '',
          'packages/web/lib/main.dart': '',
        },
      );
      final nested = readRunner(project);
      expect(
        await nested.runner.run([
          'context',
          '--code',
          'packages/web/lib/main.dart',
          '--for',
          'implement',
          '--target',
          'app',
        ]),
        64,
      );
      expect(
        nested.err.toString(),
        'the code path packages/web/lib/main.dart lies in the code target '
        'web, not app\n',
      );
      final top = readRunner(project);
      expect(
        await top.runner.run([
          'context',
          '--code',
          'lib/main.dart',
          '--for',
          'implement',
          '--target',
          'web',
        ]),
        64,
      );
      expect(
        top.err.toString(),
        'the code path lib/main.dart lies in the code target app, not web\n',
      );
    });
  });
}
