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
  test('context on a story lists the root spec doc in its index', () async {
    final (:runner, :out, :err) = readRunner(
      await writeReadProject(
        extra: {'docs/specs/DOMAIN.md': '# Project domain\n'},
      ),
    );
    expect(
      await runner.run(['context', 'login/email_login', '--for', 'implement']),
      0,
    );
    final lines = out.toString().split('\n');
    expect(lines, contains(startsWith('- project_domain (project_domain)')));
    expect(
      lines.where(
        (l) => l == '==> project_domain (project_domain) · specs/DOMAIN.md <==',
      ),
      hasLength(1),
    );
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
  test(
    'over budget with --json exits 1 with stdout one object and stderr empty',
    () async {
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
    },
  );
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
  test("under --json the object's first key is code", () async {
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

  test(
    'a design bundle keeps a line whose code span holds an HTML comment',
    () async {
      const line =
          'A block opens with `<!-- BEGIN specstone v1 -->` and closes '
          'with `<!-- END specstone -->`.';
      final project = await writeReadProject(
        extra: {
          'docs/prds/features/f01_login/FEATURE.md':
              '---\nvision:\n  - PV-01\nslug:\n  - sign-in\n---\n\n# Login\n\n'
              '## Problem\n$line\n',
        },
      );
      final (:runner, :out, :err) = readRunner(project);
      expect(
        await runner.run(['context', 'login/email_login', '--for', 'design']),
        0,
      );
      expect(out.toString(), contains('## Problem\n$line'));
      expect(err.toString(), isEmpty);
    },
  );

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

    test('--code under one root takes that target alone', () async {
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
    });

    test('f01/us05/fr04, domain:agent_plugin INV-25: --code names its code '
        'target on the first text line, covered or not', () async {
      final project = await writeToastProject(
        extra: {'jaspr_lib/lib/toast.dart': '', 'jaspr_lib/other/x.dart': ''},
      );
      final covered = readRunner(project);
      expect(
        await covered.runner.run([
          'context',
          '--code',
          'jaspr_lib/lib/toast.dart',
          '--for',
          'implement',
        ]),
        0,
      );
      expect(
        covered.out.toString(),
        startsWith('==> code target: jaspr <==\n'),
      );
      final bare = readRunner(project);
      expect(
        await bare.runner.run([
          'context',
          '--code',
          'jaspr_lib/other/x.dart',
          '--for',
          'implement',
        ]),
        0,
      );
      expect(bare.out.toString(), startsWith('==> code target: jaspr <==\n'));
      expect(
        bare.err.toString(),
        '⚠️ WARNING: no doc covers or implements other/x.dart\n',
      );
    });

    test('f01/us05/fr04, domain:agent_plugin INV-25: --json carries codeTarget '
        'for a covered and an uncovered path', () async {
      final project = await writeToastProject(
        extra: {'jaspr_lib/lib/toast.dart': '', 'jaspr_lib/other/x.dart': ''},
      );
      for (final path in ['lib/toast.dart', 'other/x.dart']) {
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            '--code',
            'jaspr_lib/$path',
            '--for',
            'implement',
            '--json',
          ]),
          0,
        );
        final json = jsonDecode(run.out.toString()) as Map<String, Object?>;
        expect(json.keys.first, 'code', reason: path);
        expect(json['codeTarget'], 'jaspr', reason: path);
      }
    });

    test('f01/us05/fr03, domain:agent_plugin INV-25: the over-budget --code '
        'reply names its code target in text and JSON', () async {
      final project = await writeToastProject(
        extra: {'jaspr_lib/lib/toast.dart': ''},
      );
      final args = [
        'context',
        '--code',
        'jaspr_lib/lib/toast.dart',
        '--for',
        'implement',
        '--budget',
        '1',
      ];
      final text = readRunner(project);
      expect(await text.runner.run(args), 1);
      expect(
        text.out.toString(),
        startsWith('==> code target: jaspr <==\nThe bundle holds'),
      );
      final json = readRunner(project);
      expect(await json.runner.run([...args, '--json']), 1);
      final answer = jsonDecode(json.out.toString()) as Map<String, Object?>;
      expect(answer['overBudget'], isTrue);
      expect(answer['codeTarget'], 'jaspr');
    });

    test('--code --out with two targets prints the code '
        'target line first on stdout, and the file keeps it first', () async {
      final project = await writeToastProject(
        extra: {'jaspr_lib/lib/toast.dart': ''},
      );
      final args = [
        'context',
        '--code',
        'jaspr_lib/lib/toast.dart',
        '--for',
        'implement',
        '--out',
      ];
      final text = readRunner(project);
      expect(await text.runner.run(args), 0, reason: text.err.toString());
      final lines = text.out.toString().split('\n');
      expect(lines[0], '==> code target: jaspr <==');
      expect(lines[1], startsWith('==> bundle: '));
      expect(lines[2], startsWith('- '));
      final file = File(
        '${project.path}/.specstone/bundles/'
        'code-jaspr_lib-lib-toast.dart.implement.txt',
      );
      expect(
        file.readAsStringSync(),
        startsWith('==> code target: jaspr <==\n'),
      );
      final json = readRunner(project);
      expect(await json.runner.run([...args, '--json']), 0);
      final answer = jsonDecode(json.out.toString()) as Map<String, Object?>;
      expect(answer['codeTarget'], 'jaspr');
      expect(answer['out'], isA<String>());
    });

    test('--code --out with one target prints no code '
        'target', () async {
      final project = await writeReadProject(extra: {'app/lib/main.dart': ''});
      final args = [
        'context',
        '--code',
        'app/lib/main.dart',
        '--for',
        'implement',
        '--out',
      ];
      final text = readRunner(project);
      expect(await text.runner.run(args), 0);
      expect(text.out.toString(), startsWith('==> bundle: '));
      expect(text.out.toString(), isNot(contains('code target')));
      final json = readRunner(project);
      expect(await json.runner.run([...args, '--json']), 0);
      final answer = jsonDecode(json.out.toString()) as Map<String, Object?>;
      expect(answer.containsKey('codeTarget'), isFalse);
    });

    test('--code with one target prints no code target', () async {
      final project = await writeReadProject(extra: {'app/lib/main.dart': ''});
      final text = readRunner(project);
      await text.runner.run([
        'context',
        '--code',
        'app/lib/main.dart',
        '--for',
        'implement',
      ]);
      expect(text.out.toString(), isNot(contains('code target')));
      final json = readRunner(project);
      await json.runner.run([
        'context',
        '--code',
        'app/lib/main.dart',
        '--for',
        'implement',
        '--json',
      ]);
      expect(
        (jsonDecode(json.out.toString()) as Map).containsKey('codeTarget'),
        isFalse,
      );
    });

    test(
      '--code on a test file bundles the story and FR its tests line names',
      () async {
        final project = await writeToastProject(
          extra: {
            'jaspr_lib/test/toast_test.dart': '',
            'docs/specs/jaspr/f02_feedback/f03_toast/IMPLEMENTATION.md':
                '---\nstatuses:\n'
                '  - show:implemented\n'
                'implements:\n'
                '  - show:lib/toast.dart:showToast\n'
                'tests:\n'
                '  - "show:test/toast_test.dart:queue: a toast #1"\n'
                '---\n\n# Record\n',
          },
        );
        final (:runner, :out, :err) = readRunner(project);
        expect(
          await runner.run([
            'context',
            '--code',
            'jaspr_lib/test/toast_test.dart',
            '--for',
            'implement',
          ]),
          0,
        );
        expect(
          out.toString(),
          contains(
            '==> feedback/toast/show (user_story) · prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md <==\n',
          ),
        );
        expect(
          out.toString(),
          contains(
            '==> feedback/toast (implementation) · specs/jaspr/f02_feedback/f03_toast/IMPLEMENTATION.md <==\n',
          ),
        );
        expect(err.toString(), isEmpty);
      },
    );

    test('--code with --target naming another target is argument_conflict, exit 64', () async {
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

    test('s04/inv26: --code naming a missing path with an unheld --target is argument_invalid first, as every other command checks the target first', () async {
      final (:runner, :out, :err) = readRunner(await writeToastProject());
      expect(
        await runner.run([
          'context',
          '--code',
          'jaspr_lib/lib/gone.dart',
          '--for',
          'implement',
          '--target',
          'ci',
        ]),
        64,
      );
      expect(
        err.toString(),
        '--target ci: the code targets are flutter, jaspr\n',
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

    test('--out with --target ends the name with .<target>.txt', () async {
      final project = await writeToastProject();
      final (:runner, :out, :err) = readRunner(project);
      expect(
        await runner.run([
          'context',
          'feedback/toast/show',
          '--for',
          'implement',
          '--target',
          'jaspr',
          '--out',
        ]),
        0,
        reason: '$err',
      );
      expect(
        File(
          '${project.path}/.specstone/bundles/feedback-toast-show.implement.jaspr.txt',
        ).existsSync(),
        isTrue,
      );
    });
  });

  group('context --out', () {
    const story = 'login/email_login';
    const storyFile = 'login-email_login.implement.txt';
    final header = RegExp(
      r'^==> bundle: (\d+) docs, (\d+) tokens, (\d+) lines · (.+) <==$',
    );
    final linksUnavailable = Platform.isWindows
        ? 'a link needs a privilege on Windows'
        : null;

    File bundleFile(Directory project, String name) =>
        File('${project.path}/.specstone/bundles/$name');

    /// Returns the bundle text `context` prints for [args] with no `--out`.
    Future<String> printed(Directory project, List<String> args) async {
      final run = readRunner(project);
      expect(await run.runner.run(['context', ...args]), 0);
      return run.out.toString();
    }

    /// Runs `context` with [args] in [folder] and returns its stdout, after
    /// checking it exits 0 with stderr empty.
    Future<String> saved(Directory folder, List<String> args) async {
      final run = readRunner(folder);
      expect(
        await run.runner.run(['context', ...args]),
        0,
        reason: run.err.toString(),
      );
      expect(run.err.toString(), isEmpty);
      return run.out.toString();
    }

    test('a bare --out at the root makes .specstone/bundles/, writes the whole bundle, and prints its header and index', () async {
      final project = await writeReadProject();
      expect(
        Directory('${project.path}/.specstone/bundles').existsSync(),
        isFalse,
      );
      final stdout = await saved(project, [
        story,
        '--for',
        'implement',
        '--out',
      ]);
      final file = bundleFile(project, storyFile);
      final bundle = await printed(project, [story, '--for', 'implement']);
      expect(file.readAsStringSync(), bundle);
      final lines = const LineSplitter().convert(stdout);
      final head = header.firstMatch(lines.first)!;
      final closing = RegExp(
        r'^==> bundle: (\d+) docs, (\d+) tokens <==$',
        multiLine: true,
      ).firstMatch(bundle)!;
      expect(head.group(1), closing.group(1));
      expect(head.group(2), closing.group(2));
      final fileLines = file.readAsLinesSync();
      expect(head.group(3), '${fileLines.length}');
      expect(head.group(4), file.resolveSymbolicLinksSync());
      expect(lines.skip(1), everyElement(startsWith('- ')));
      final storyLine = lines.singleWhere(
        (line) => line.startsWith('- $story (user_story) · '),
      );
      final range = RegExp(
        r'· (\d+)-(\d+) · use_case (\d+), acceptance_criteria (\d+)$',
      ).firstMatch(storyLine)!;
      expect(
        fileLines[int.parse(range.group(1)!) - 1],
        startsWith('==> $story (user_story) · '),
      );
      expect(fileLines[int.parse(range.group(3)!) - 1], '## Use Case');
      expect(
        fileLines[int.parse(range.group(4)!) - 1],
        '## Acceptance Criteria',
      );
    });

    test('a bare --out from a subfolder writes under the root and prints the same absolute path, text and --json', () async {
      final project = await writeReadProject(extra: {'app/lib/.keep': ''});
      final nested = Directory('${project.path}/app/lib');
      final args = [story, '--for', 'implement', '--out'];
      final paths = <String>[];
      for (final folder in [project, nested]) {
        final text = await saved(folder, args);
        paths.add(header.firstMatch(text.split('\n').first)!.group(4)!);
        final json =
            jsonDecode(await saved(folder, [...args, '--json'])) as Map;
        expect(json.keys.toList(), [
          'out',
          'tokens',
          'lines',
          'docs',
          'warnings',
        ]);
        paths.add(json['out']! as String);
        final docs = (json['docs']! as List).cast<Map<String, Object?>>();
        expect(docs.first.keys.toList(), [
          'name',
          'docType',
          'docPath',
          'lines',
          'summary',
          'cited',
          'sections',
        ]);
      }
      final file = bundleFile(project, storyFile);
      expect(paths.toSet(), {file.resolveSymbolicLinksSync()});
      expect(File(paths.first).isAbsolute, isTrue);
      expect(Directory('${nested.path}/.specstone').existsSync(), isFalse);
      expect(
        file.readAsStringSync(),
        await printed(project, [story, '--for', 'implement']),
        reason: 'under --json the file still holds the text bundle',
      );
    });

    test('a bare --out before --for, or before --json, stays bare', () async {
      final project = await writeReadProject();
      final before = await saved(project, [
        story,
        '--out',
        '--for',
        'implement',
      ]);
      expect(before, startsWith('==> bundle: '));
      expect(bundleFile(project, storyFile).existsSync(), isTrue);
      final json = await saved(project, [
        story,
        '--for',
        'design',
        '--out',
        '--json',
      ]);
      expect(
        (jsonDecode(json) as Map)['out'],
        bundleFile(
          project,
          'login-email_login.design.txt',
        ).resolveSymbolicLinksSync(),
      );
    });

    test('--out= and --out "" are argument_invalid, exit 64, before anything is written', () async {
      for (final args in [
        ['--out='],
        ['--out', ''],
      ]) {
        final project = await writeReadProject();
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            story,
            '--for',
            'implement',
            ...args,
          ]),
          64,
          reason: '$args',
        );
        expect(run.err.toString(), '--out takes a file path, not ""\n');
        expect(run.out.toString(), isEmpty);
        expect(
          Directory('${project.path}/.specstone/bundles').existsSync(),
          isFalse,
        );
        expect(
          File('${project.path}/.specstone/index.sqlite').existsSync(),
          isFalse,
        );
      }
    });

    test(
      '--out with --budget is argument_conflict, exit 64, and writes no file',
      () async {
        final project = await writeReadProject();
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            story,
            '--for',
            'implement',
            '--budget',
            '10',
            '--out',
          ]),
          64,
        );
        expect(run.err.toString(), 'give --out or --budget, not both\n');
        expect(
          Directory('${project.path}/.specstone/bundles').existsSync(),
          isFalse,
        );
      },
    );

    test(
      'a file of the same name is replaced whole; another name stays',
      () async {
        final project = await writeReadProject();
        final file = bundleFile(project, storyFile)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('old bundle\n');
        final other = bundleFile(project, 'login.query.txt')
          ..writeAsStringSync('kept\n');
        await saved(project, [story, '--for', 'implement', '--out']);
        expect(
          file.readAsStringSync(),
          await printed(project, [story, '--for', 'implement']),
        );
        expect(other.readAsStringSync(), 'kept\n');
      },
    );

    test('an --out path inside the docs root is output_not_writable, exit 73, before anything is written', () async {
      final project = await writeReadProject();
      final run = readRunner(project);
      expect(
        await run.runner.run([
          'context',
          story,
          '--for',
          'implement',
          '--out',
          'docs/prds/bundle.txt',
        ]),
        73,
      );
      expect(
        run.err.toString(),
        endsWith('the output path is inside the docs root\n'),
      );
      expect(run.out.toString(), isEmpty);
      expect(
        File('${project.path}/docs/prds/bundle.txt').existsSync(),
        isFalse,
      );
    });

    test(
      'an --out path through a link into the docs root is refused too',
      () async {
        final project = await writeReadProject();
        Link('${project.path}/notes').createSync('${project.path}/docs/prds');
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            story,
            '--for',
            'implement',
            '--out',
            'notes/bundle.txt',
          ]),
          73,
        );
        expect(
          run.err.toString(),
          endsWith('the output path is inside the docs root\n'),
        );
        expect(
          File('${project.path}/docs/prds/bundle.txt').existsSync(),
          isFalse,
        );
      },
      skip: linksUnavailable,
    );

    test(
      'an --out folder that cannot be made is output_not_writable, exit 73',
      () async {
        final project = await writeReadProject(extra: {'blocker': 'a file\n'});
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            story,
            '--for',
            'implement',
            '--out',
            'blocker/bundle.txt',
          ]),
          73,
        );
        expect(
          run.err.toString(),
          endsWith('the output path is not writable\n'),
        );
        expect(File('${project.path}/blocker').readAsStringSync(), 'a file\n');
      },
    );

    test(
      'an --out folder that refuses the write keeps the file there whole',
      () async {
        final project = await writeReadProject(
          extra: {'locked/bundle.txt': 'old\n'},
        );
        final locked = Directory('${project.path}/locked');
        await Process.run('chmod', ['555', locked.path]);
        addTearDown(() => Process.run('chmod', ['755', locked.path]));
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            story,
            '--for',
            'implement',
            '--out',
            'locked/bundle.txt',
          ]),
          73,
        );
        expect(File('${locked.path}/bundle.txt').readAsStringSync(), 'old\n');
      },
      skip: readOnlySkipReason(),
    );

    test('--out with --code names the file code-<path>; --for query writes the query bundle', () async {
      final project = await writeReadProject(extra: {'app/lib/main.dart': ''});
      for (final mode in ['implement', 'query']) {
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            '--code',
            'app/lib/main.dart',
            '--for',
            mode,
            '--out',
          ]),
          0,
        );
        final plain = readRunner(project);
        await plain.runner.run([
          'context',
          '--code',
          'app/lib/main.dart',
          '--for',
          mode,
        ]);
        expect(
          bundleFile(
            project,
            'code-app-lib-main.dart.$mode.txt',
          ).readAsStringSync(),
          plain.out.toString(),
        );
      }
    });

    test(
      'a --code path names one file from the root and from a subfolder',
      () async {
        final project = await writeReadProject(
          extra: {'app/lib/src/login/form.dart': ''},
        );
        final bundles = Directory('${project.path}/.specstone/bundles');
        for (final (folder, code) in [
          ('', 'app/lib/src/login/form.dart'),
          ('/app', 'lib/src/login/form.dart'),
          ('/app/lib/src/login', './form.dart'),
        ]) {
          await saved(Directory('${project.path}$folder'), [
            '--code',
            code,
            '--for',
            'implement',
            '--out',
          ]);
        }
        expect(
          [for (final file in bundles.listSync()) file.uri.pathSegments.last],
          ['code-app-lib-src-login-form.dart.implement.txt'],
        );
      },
    );

    test('a named --out path under the project .git is output_not_writable, exit 73', () async {
      final project = await writeReadProject(
        extra: {'.git/config': '[core]\n'},
      );
      final run = readRunner(project);
      expect(
        await run.runner.run([
          'context',
          story,
          '--for',
          'implement',
          '--out',
          '.git/bundle.txt',
        ]),
        73,
      );
      expect(run.err.toString(), contains('it lies under .git'));
      expect(File('${project.path}/.git/bundle.txt').existsSync(), isFalse);
    });

    test('--for design --summary --no-project names <target>.design-summary-no-project.txt', () async {
      final project = await writeReadProject();
      await saved(project, [
        'login',
        '--for',
        'design',
        '--summary',
        '--no-project',
        '--out',
      ]);
      expect(
        bundleFile(project, 'login.design-summary-no-project.txt').existsSync(),
        isTrue,
      );
    });

    test('a relative --out from a subfolder is read from it and printed canonical and absolute', () async {
      final project = await writeReadProject(extra: {'app/.keep': ''});
      final nested = Directory('${project.path}/app');
      final text = await saved(nested, [
        story,
        '--for',
        'implement',
        '--out',
        '../out/b.txt',
      ]);
      final file = File('${project.path}/out/b.txt');
      expect(file.existsSync(), isTrue);
      expect(
        header.firstMatch(text.split('\n').first)!.group(4),
        file.resolveSymbolicLinksSync(),
      );
      final json = jsonDecode(
        await saved(nested, [
          story,
          '--for',
          'implement',
          '--out=../out/b.txt',
          '--json',
        ]),
      ) as Map;
      expect(json['out'], file.resolveSymbolicLinksSync());
    });

    test('an --out path through a linked folder prints the canonical path of the written file', () async {
      final project = await writeReadProject();
      final outside = await writeTree({'.keep': ''});
      Link('${project.path}/linked').createSync(outside.path);
      final text = await saved(project, [
        story,
        '--for',
        'implement',
        '--out',
        'linked/b.txt',
      ]);
      final file = File('${outside.path}/b.txt');
      expect(file.existsSync(), isTrue);
      final shown = header.firstMatch(text.split('\n').first)!.group(4)!;
      expect(shown, file.resolveSymbolicLinksSync());
      expect(shown, isNot(contains('linked')));
    }, skip: linksUnavailable);
  });

  group('the over-budget next step names --out', () {
    test('without --summary', () async {
      final project = await writeReadProject();
      final text = readRunner(project);
      final args = [
        'context',
        'login/email_login',
        '--for',
        'implement',
        '--budget',
        '1',
      ];
      expect(await text.runner.run(args), 1);
      expect(
        text.out.toString(),
        endsWith(
          'Next step: narrow the target, or run it again with --out and no --budget.\n',
        ),
      );
      final json = readRunner(project);
      expect(await json.runner.run([...args, '--json']), 1);
      expect(
        (jsonDecode(json.out.toString()) as Map)['next'],
        'narrow the target, or run it again with --out and no --budget',
      );
    });
    test('e09: with --summary the next step keeps --summary', () async {
      final project = await writeReadProject();
      final text = readRunner(project);
      final args = [
        'context',
        'login',
        '--for',
        'design',
        '--summary',
        '--budget',
        '1',
      ];
      expect(await text.runner.run(args), 1);
      expect(
        text.out.toString(),
        endsWith(
          'Next step: narrow the target, or run it again with --summary --out and no --budget.\n',
        ),
      );
      final json = readRunner(project);
      expect(await json.runner.run([...args, '--json']), 1);
      expect(
        (jsonDecode(json.out.toString()) as Map)['next'],
        'narrow the target, or run it again with --summary --out and no --budget',
      );
    });
  });

  group('feature pattern parts', () {
    const featurePath = 'docs/prds/features/f01_login/FEATURE.md';
    Map<String, String> patterned(String patterns) => {
      '.specstone/templates/feature.yaml':
          'fields:\n  - id: patterns\n    type: string\n    list: true\n',
      featurePath:
          '---\nvision:\n  - PV-01\npatterns: $patterns\n---\n\n# Login\n\n## Problem\nUsers sign in.\n',
      '.specstone/templates/patterns/sign_in_checks.yaml':
          'id: sign_in_checks\ndescription: Sign-in checklist.\nitems:\n'
          '  - id: lockout\n    text: Name the lockout rule.\n'
          'reference:\n  - title: Handbook\n    url: https://example.com/handbook\n',
      '.specstone/templates/patterns/record_checks.yaml':
          'id: record_checks\ndescription: Record checklist.\nitems:\n'
          '  - id: create\n    text: Name the create path.\n',
    };
    Future<({int code, String out})> run(
      Map<String, String> extra,
      List<String> args,
    ) async {
      final (:runner, :out, :err) = readRunner(
        await writeReadProject(extra: extra),
      );
      final code = await runner.run(['context', ...args]);
      return (code: code, out: out.toString());
    }

    test('a design bundle holds each checklist the feature names right after it, in the order it names them', () async {
      final r = await run(patterned('[sign_in_checks, record_checks]'), [
        'login/email_login',
        '--for',
        'design',
      ]);

      expect(r.code, 0);
      final text = r.out;
      final feature = text.indexOf('==> login (feature) · ');
      final first = text.indexOf(
        '==> sign_in_checks (feature pattern) · login <==\nSign-in checklist.\n'
        '- **lockout** Name the lockout rule.\nPattern sources:\n- Handbook: https://example.com/handbook\n',
      );
      final second = text.indexOf(
        '==> record_checks (feature pattern) · login <==\nRecord checklist.\n- **create** Name the create path.\n',
      );
      final story = text.indexOf('==> login/email_login (user_story) · ');
      expect([feature, first, second, story], everyElement(isNonNegative));
      expect(feature, lessThan(first));
      expect(first, lessThan(second));
      expect(second, lessThan(story));
    });
    test('a bundle for implementing holds no checklist', () async {
      final r = await run(patterned('[sign_in_checks]'), [
        'login/email_login',
        '--for',
        'implement',
      ]);

      expect(r.code, 0);
      expect(r.out, isNot(contains('(feature pattern)')));
    });
    test('--json carries featurePatterns in each design reply and in no other mode', () async {
      final extra = patterned('[sign_in_checks]');
      final design = await run(extra, [
        'login/email_login',
        '--for',
        'design',
        '--json',
      ]);
      final implement = await run(extra, [
        'login/email_login',
        '--for',
        'implement',
        '--json',
      ]);
      final query = await run(extra, [
        'login/email_login',
        '--for',
        'query',
        '--json',
      ]);

      expect((jsonDecode(design.out) as Map)['featurePatterns'], [
        {
          'id': 'sign_in_checks',
          'doc': 'feature:login',
          'description': 'Sign-in checklist.',
          'items': [
            {'id': 'lockout', 'text': 'Name the lockout rule.'},
          ],
          'reference': [
            {'title': 'Handbook', 'url': 'https://example.com/handbook'},
          ],
        },
      ]);
      expect(
        jsonDecode(implement.out) as Map,
        isNot(contains('featurePatterns')),
      );
      expect(jsonDecode(query.out) as Map, isNot(contains('featurePatterns')));
    });
    test(
      'a design bundle where no part joins gives featurePatterns: []',
      () async {
        final none = await run(const {}, [
          'login/email_login',
          '--for',
          'design',
          '--json',
        ]);
        final unknown = await run(patterned('[nothing]'), [
          'login/email_login',
          '--for',
          'design',
          '--json',
        ]);

        expect((jsonDecode(none.out) as Map)['featurePatterns'], isEmpty);
        expect((jsonDecode(unknown.out) as Map)['featurePatterns'], isEmpty);
        expect(none.out, contains('"featurePatterns":'));
      },
    );
    test('--out --json indexes each part as {id, doc, lines} beside docs, whose lines point at the part in the file', () async {
      final project = await writeReadProject(
        extra: patterned('[sign_in_checks, record_checks]'),
      );
      final (:runner, :out, :err) = readRunner(project);

      final code = await runner.run([
        'context',
        'login/email_login',
        '--for',
        'design',
        '--out',
        '--json',
      ]);

      expect(code, 0, reason: err.toString());
      final index = jsonDecode(out.toString()) as Map;
      final fileLines = File(index['out'] as String).readAsLinesSync();
      final parts = (index['featurePatterns'] as List)
          .cast<Map<String, Object?>>();
      expect(
        [for (final part in parts) part['id']],
        ['sign_in_checks', 'record_checks'],
      );
      expect(parts.map((part) => part['doc']), everyElement('feature:login'));
      for (final part in parts) {
        final [first, last] = (part['lines']! as List).cast<int>();
        expect(
          fileLines[first - 1],
          '==> ${part['id']} (feature pattern) · login <==',
        );
        expect(last, greaterThan(first));
      }
      final docNames = [
        for (final doc in index['docs'] as List) (doc as Map)['name'],
      ];
      expect(docNames, contains('login'));
      expect(docNames, isNot(contains('sign_in_checks')));
    });
  });
}
