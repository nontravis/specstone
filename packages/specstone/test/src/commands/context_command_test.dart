// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/commands/context_command.dart' show withBareOut;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show tokenSizeOf;
import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart'
    show shippedPinsConfig;
import '../../../../specstone_core/test/helpers/skill_doc_fixture.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/read_fixture.dart';
import '../../helpers/temp_tree.dart';

/// Returns the `error` object `--json` writes to [err].
Map<String, Object?> _errorOf(StringBuffer err) =>
    (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
        as Map<String, Object?>;

void main() {
  test('a bare --out of context, check, guide, and get is read as a flag', () {
    for (final command in ['context', 'check', 'guide', 'get']) {
      expect(withBareOut([command, 'x', '--out']), [
        command,
        'x',
        '--bare-out',
      ]);
      expect(withBareOut([command, '--out', '--json']), [
        command,
        '--bare-out',
        '--json',
      ]);
      expect(withBareOut([command, '--out', 'a.txt']), [
        command,
        '--out',
        'a.txt',
      ]);
    }
    expect(withBareOut(['list', '--out']), ['list', '--out']);
  });

  test(
    'context for a story prints the bundle and its doc list, exit 0',
    () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(
        await runner.run([
          'context',
          'login/email_login',
          '--for',
          'implement',
        ]),
        0,
      );
      expect(out.toString(), contains('==> bundle: '));
      expect(out.toString(), endsWith('- login (architecture)\n'));
    },
  );
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
  test('no target, no --for, or another --for value refuses with exit 64', () async {
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
  test(
    'context --summary on a feature prints its stories in summary, exit 0',
    () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(
        await runner.run(['context', 'login', '--for', 'design', '--summary']),
        0,
      );
      expect(
        out.toString(),
        contains('- login/email_login (user_story) · summary\n'),
      );
    },
  );
  test('--summary with another mode or --code refuses with exit 64', () async {
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
  test('--summary on a story refuses with exit 64', () async {
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
      '--summary takes a doc with children, such as a feature; login/email_login (user_story) is not one\n',
    );
  });
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
  test(
    'a bundle whose heading keys take it over --budget is over budget',
    () async {
      const args = ['context', 'login/email_login', '--for', 'implement'];
      final project = await writeReadProject();
      final whole = readRunner(project);
      expect(await whole.runner.run([...args, '--budget', '100000']), 0);
      final text = whole.out.toString();
      final shown = text.substring(0, text.indexOf('\n==> bundle: '));
      final bare = shown.replaceAllMapped(
        RegExp(r'^(## .*) \{#[a-z0-9_]+\}$', multiLine: true),
        (match) => match[1]!,
      );
      final bareTokens = tokenSizeOf(bare);
      expect(tokenSizeOf(shown), greaterThan(bareTokens));

      final over = readRunner(project);

      expect(await over.runner.run([...args, '--budget', '$bareTokens']), 1);
      expect(over.out.toString(), contains('over the budget of $bareTokens'));
    },
  );
  test(
    'a --budget that is no positive integer is argument_invalid, exit 64',
    () async {
      final project = await writeReadProject();
      for (final value in ['0', '-5', '5k']) {
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            'login/email_login',
            '--for',
            'implement',
            '--budget=$value',
            '--json',
          ]),
          64,
          reason: value,
        );
        expect(_errorOf(run.err)['code'], 'argument_invalid', reason: value);
        expect(_errorOf(run.err)['message'], contains(value), reason: value);
        expect(run.out.toString(), isEmpty, reason: value);
      }
    },
  );
  test('an untyped target exits 64 with the untyped_target message', () async {
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
  test('outside a project, or under a 9.9.9 pin, exits 78', () async {
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
  test('a target and --code together are argument_conflict, exit 64', () async {
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
  test('an unmatched code path exits 0 with the warning on stderr', () async {
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
  test('a code path outside the project exits 64 and names it', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['context', '--code', '../', '--for', 'implement']),
      64,
    );
    expect(err.toString(), 'the code path ../ lies outside the code root\n');
  });
  test('--code "" is argument_invalid, exit 64, and opens no index', () async {
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
  test(
    'a target beside --code is argument_conflict in the --json envelope',
    () async {
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
          '--json',
        ]),
        64,
      );
      expect(_errorOf(err), {
        'code': 'argument_conflict',
        'message': 'give a target or --code, not both',
      });
    },
  );
  test('a --code path that does not exist exits 64 as code_path_not_found naming it', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run([
        'context',
        '--code',
        'app/lib/gone.dart',
        '--for',
        'implement',
        '--json',
      ]),
      64,
    );
    expect(_errorOf(err)['code'], 'code_path_not_found');
    expect(_errorOf(err)['message'], contains('app/lib/gone.dart'));
    expect(out.toString(), isEmpty);
  });
  test(
    '--code "" with no --for is argument_invalid, not argument_missing',
    () async {
      final (:runner, :out, :err) = readRunner(await writeReadProject());
      expect(await runner.run(['context', '--code', '', '--json']), 64);
      expect(_errorOf(err), {
        'code': 'argument_invalid',
        'message': '--code takes a file or folder, not ""',
      });
    },
  );
  test('an unknown target is doc_not_found, exit 64, naming it', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['context', 'no_such_doc', '--for', 'query', '--json']),
      64,
    );
    expect(_errorOf(err)['code'], 'doc_not_found');
    expect(_errorOf(err)['message'], contains('no_such_doc'));
  });
  test('no project is project_not_found and a broken template is its own fault, both exit 78', () async {
    final none = readRunner(await writeTree({}));
    expect(
      await none.runner.run(['context', 'login', '--for', 'query', '--json']),
      78,
    );
    expect(_errorOf(none.err), {
      'code': 'project_not_found',
      'message': 'no Specstone project: no folder from the working directory upward holds .specstone/config.yaml',
    });

    final broken = readRunner(
      await writeReadProject(
        extra: {'.specstone/templates/feature.yaml': 'id: [unclosed\n'},
      ),
    );
    expect(
      await broken.runner.run(['context', 'login', '--for', 'query', '--json']),
      78,
    );
    expect(_errorOf(broken.err)['code'], 'yaml_syntax');
    expect(_errorOf(broken.err)['file'], '.specstone/templates/feature.yaml');
    expect(_errorOf(broken.err)['message'], isNotEmpty);
  });
  test(
    '--code of a missing path under a missing code_root is code_path_not_found',
    () async {
      final project = await writeReadProject(
        extra: {
          '.specstone/config.yaml':
              'packs:\n'
              '  prd-core: ${shippedPackVersions()['prd-core']}\n'
              '  software-tech: ${shippedPackVersions()['software-tech']}\n'
              'targets:\n  app:\n    code_root: nowhere\n',
        },
      );
      final (:runner, :out, :err) = readRunner(project);
      expect(
        await runner.run([
          'context',
          '--code',
          'nowhere/lib/x.dart',
          '--for',
          'implement',
          '--json',
        ]),
        64,
      );
      expect(_errorOf(err)['code'], 'code_path_not_found');
      expect(_errorOf(err)['message'], contains('nowhere/lib/x.dart'));
    },
  );
  group('per code target', () {
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

    test(
      'implement with two targets and no --target exits 64 naming them',
      () async {
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
      },
    );

    test('--code names its code '
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

    test('--json carries codeTarget '
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

    test('the over-budget --code '
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
      expect(lines[2], startsWith('read whole, in '));
      expect(lines[3], startsWith('- '));
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

    test('--code with an unheld or premature --target is argument_invalid, exit 64', () async {
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

    test('--code naming a missing path with an unheld --target is argument_invalid first, as every other command checks the target first', () async {
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

    test('--code with --target naming its own target prints the bundle --code alone prints, and another target is argument_conflict in the --json envelope', () async {
      final project = await writeToastProject(
        extra: {'jaspr_lib/lib/toast.dart': ''},
      );
      const path = 'jaspr_lib/lib/toast.dart';
      final alone = readRunner(project);
      expect(
        await alone.runner.run([
          'context',
          '--code',
          path,
          '--for',
          'implement',
        ]),
        0,
      );
      final named = readRunner(project);
      expect(
        await named.runner.run([
          'context',
          '--code',
          path,
          '--for',
          'implement',
          '--target',
          'jaspr',
        ]),
        0,
      );
      expect(named.out.toString(), alone.out.toString());
      expect(named.out.toString(), startsWith('==> code target: jaspr <==\n'));
      expect(named.out.toString(), contains('specs/jaspr/f02_feedback/'));
      expect(named.out.toString(), isNot(contains('specs/flutter/')));

      final other = readRunner(project);
      expect(
        await other.runner.run([
          'context',
          '--code',
          path,
          '--for',
          'implement',
          '--target',
          'flutter',
          '--json',
        ]),
        64,
      );
      expect(_errorOf(other.err), {
        'code': 'argument_conflict',
        'message':
            'the code path jaspr_lib/lib/toast.dart lies in the code target '
            'jaspr, not flutter',
      });
    });

    test('--for design --out with two targets keeps the code target line first in the file, and one named target prints none', () async {
      final toast = await writeToastProject(
        extra: {'jaspr_lib/lib/toast.dart': ''},
      );
      final design = readRunner(toast);
      expect(
        await design.runner.run([
          'context',
          '--code',
          'jaspr_lib/lib/toast.dart',
          '--for',
          'design',
          '--out',
        ]),
        0,
        reason: design.err.toString(),
      );
      expect(
        design.out.toString(),
        startsWith('==> code target: jaspr <==\n==> bundle: '),
      );
      expect(
        File(
          '${toast.path}/.specstone/bundles/'
          'code-jaspr_lib-lib-toast.dart.design.txt',
        ).readAsStringSync(),
        startsWith('==> code target: jaspr <==\n'),
      );

      final one = await writeReadProject(
        extra: {
          '.specstone/config.yaml':
              'packs:\n'
              '  prd-core: ${shippedPackVersions()['prd-core']}\n'
              '  software-tech: ${shippedPackVersions()['software-tech']}\n'
              'targets:\n  app:\n    code_root: app\n',
          'app/lib/main.dart': '',
        },
      );
      for (final mode in ['implement', 'design']) {
        final text = readRunner(one);
        expect(
          await text.runner.run([
            'context',
            '--code',
            'app/lib/main.dart',
            '--for',
            mode,
            '--target',
            'app',
            '--out',
          ]),
          0,
          reason: text.err.toString(),
        );
        expect(text.out.toString(), startsWith('==> bundle: '), reason: mode);
        expect(text.out.toString(), isNot(contains('code target')));
        final saved = File(
          '${one.path}/.specstone/bundles/'
          'code-app-lib-main.dart.$mode.app.txt',
        ).readAsStringSync();
        expect(saved, isNot(contains('code target')), reason: mode);
        final json = readRunner(one);
        expect(
          await json.runner.run([
            'context',
            '--code',
            'app/lib/main.dart',
            '--for',
            mode,
            '--target',
            'app',
            '--out',
            '--json',
          ]),
          0,
        );
        expect(
          (jsonDecode(json.out.toString()) as Map).containsKey('codeTarget'),
          isFalse,
          reason: mode,
        );
      }
    });

    test('nested code roots pick the longest that holds the path', () async {
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

  group('context --out', () {
    const story = 'login/email_login';
    const storyFile = 'login-email_login.query.txt';
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

    test('a bare --out at the root makes .specstone/bundles/, writes the read-first file, and prints its header and index', () async {
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
      final file = bundleFile(project, 'login-email_login.implement.txt');
      final bundle = file.readAsStringSync();
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
      final refsHeader = lines.indexWhere((line) => line.contains('.refs.txt'));
      expect(lines[1], 'read whole, in 1 read: lines 1-${fileLines.length}');
      expect(lines.take(refsHeader).skip(2), everyElement(startsWith('- ')));
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
      expect(
        fileLines[int.parse(range.group(3)!) - 1],
        '## Use Case {#use_case}',
      );
      expect(
        fileLines[int.parse(range.group(4)!) - 1],
        '## Acceptance Criteria {#acceptance_criteria}',
      );
    });

    test('a bare --for query --out from a subfolder writes under the root and prints the same absolute path, text and --json', () async {
      final project = await writeReadProject(extra: {'app/lib/.keep': ''});
      final nested = Directory('${project.path}/app/lib');
      final args = [story, '--for', 'query', '--out'];
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
        await printed(project, [story, '--for', 'query']),
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
      expect(
        bundleFile(project, 'login-email_login.implement.txt').existsSync(),
        isTrue,
      );
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
        await saved(project, [story, '--for', 'query', '--out']);
        expect(
          file.readAsStringSync(),
          await printed(project, [story, '--for', 'query']),
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
            'code-app-lib-main.dart.$mode.refs.txt',
          ).existsSync(),
          mode == 'implement',
        );
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
      'a bare --out from a long code path writes a name of 250 bytes or fewer',
      () async {
        final segments = ['\u3042' * 45, '\u3044' * 45];
        final code = 'app/lib/${segments.join('/')}.dart';
        final project = await writeReadProject(extra: {code: ''});

        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            '--code',
            code,
            '--for',
            'implement',
            '--out',
          ]),
          0,
        );

        final paths = [
          for (final line in run.out.toString().split('\n'))
            ?header.firstMatch(line)?.group(4),
        ];
        expect(paths, hasLength(2));
        final names = [
          for (final path in paths) path.split(RegExp(r'[/\\]')).last,
        ];
        expect(utf8.encode(names.first).length, lessThanOrEqualTo(250));
        expect(utf8.encode(names.last).length, lessThanOrEqualTo(255));
        expect(names.last, endsWith('.implement.refs.txt'));
        expect(File(paths.first).existsSync(), isTrue);
        expect(File(paths.last).existsSync(), isTrue);
      },
    );

    test('a bare --out of a 250-byte ASCII name writes both files', () async {
      final code = 'app/lib/${'a' * 218}.dart';
      final project = await writeReadProject(extra: {code: ''});
      final run = readRunner(project);

      expect(
        await run.runner.run([
          'context',
          '--code',
          code,
          '--for',
          'implement',
          '--out',
        ]),
        0,
        reason: run.err.toString(),
      );

      final names = [
        for (final file in Directory(
          '${project.path}/.specstone/bundles',
        ).listSync())
          file.uri.pathSegments.last,
      ];
      expect(names, hasLength(2));
      expect(names.map((name) => utf8.encode(name).length).toList()..sort(), [
        250,
        255,
      ]);
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
          [for (final file in bundles.listSync()) file.uri.pathSegments.last]
            ..sort(),
          [
            'code-app-lib-src-login-form.dart.implement.refs.txt',
            'code-app-lib-src-login-form.dart.implement.txt',
          ],
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

    test('an --out path under .specstone/ outside bundles/ and reports/ is output_not_writable, exit 73, and the config stays whole', () async {
      final project = await writeReadProject();
      final config = File('${project.path}/.specstone/config.yaml');
      final before = config.readAsBytesSync();
      final run = readRunner(project);
      expect(
        await run.runner.run([
          'context',
          story,
          '--for',
          'implement',
          '--out',
          '.specstone/config.yaml',
        ]),
        73,
      );
      expect(
        run.err.toString(),
        endsWith(
          'the output path is inside .specstone/ but outside its bundles/ '
          'and reports/\n',
        ),
      );
      expect(run.out.toString(), isEmpty);
      expect(config.readAsBytesSync(), before);
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

    test(
      '--out= is argument_invalid in the --json envelope, with nothing written',
      () async {
        final project = await writeReadProject();
        for (final args in [
          ['--out='],
          ['--out', ''],
        ]) {
          final run = readRunner(project);
          expect(
            await run.runner.run([
              'context',
              story,
              '--for',
              'implement',
              ...args,
              '--json',
            ]),
            64,
            reason: '$args',
          );
          expect(_errorOf(run.err), {
            'code': 'argument_invalid',
            'message': '--out takes a file path, not ""',
          }, reason: '$args');
        }
        expect(
          Directory('${project.path}/.specstone/bundles').existsSync(),
          isFalse,
        );
      },
    );

    test('--budget beside --out is argument_conflict in the --json envelope, exit 64', () async {
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
          '--json',
        ]),
        64,
      );
      expect(_errorOf(run.err), {
        'code': 'argument_conflict',
        'message': 'give --out or --budget, not both',
      });
      expect(run.out.toString(), isEmpty);
    });

    test('an --out folder that cannot be made is output_not_writable in the --json envelope, exit 73', () async {
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
          '--json',
        ]),
        73,
      );
      expect(_errorOf(run.err)['code'], 'output_not_writable');
      expect(
        _errorOf(run.err)['message'],
        endsWith('the output path is not writable'),
      );
    });

    test('an --out folder that refuses the write is output_not_writable in the --json envelope, exit 73', () async {
      final project = await writeReadProject(extra: {'locked/keep.txt': 'x\n'});
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
          '--json',
        ]),
        73,
      );
      expect(_errorOf(run.err)['code'], 'output_not_writable');
    }, skip: readOnlySkipReason());

    test('a refused .git path names the file from the project root, also through a link', () async {
      final project = await writeReadProject(
        extra: {'.git/config': '[core]\n'},
      );
      final direct = readRunner(project);
      expect(
        await direct.runner.run([
          'context',
          story,
          '--for',
          'implement',
          '--out',
          '.git/b.txt',
        ]),
        73,
      );
      expect(
        direct.err.toString(),
        endsWith('cannot write .git/b.txt: it lies under .git\n'),
      );

      if (Platform.isWindows) return;
      Link('${project.path}/notes').createSync('${project.path}/.git');
      final linked = readRunner(project);
      expect(
        await linked.runner.run([
          'context',
          story,
          '--for',
          'implement',
          '--out',
          'notes/b.txt',
        ]),
        73,
      );
      expect(linked.err.toString(), contains('it lies under .git'));
      expect(File('${project.path}/.git/b.txt').existsSync(), isFalse);
    });

    test('--out .specstone/reports/b.txt is written', () async {
      final project = await writeReadProject();
      final text = await saved(project, [
        story,
        '--for',
        'implement',
        '--out',
        '.specstone/reports/b.txt',
      ]);
      final file = File('${project.path}/.specstone/reports/b.txt');
      expect(file.existsSync(), isTrue);
      expect(
        header.firstMatch(text.split('\n').first)!.group(4),
        file.resolveSymbolicLinksSync(),
      );
      expect(
        file.readAsStringSync(),
        await printed(project, [story, '--for', 'implement']),
      );
      expect(
        File('${project.path}/.specstone/reports/b.refs.txt').existsSync(),
        isTrue,
      );
    });

    test(
      'a --budget call within budget prints one bundle and writes no file',
      () async {
        final project = await writeReadProject();
        final text = await printed(project, [
          story,
          '--for',
          'implement',
          '--budget',
          '100000',
        ]);
        expect(text, startsWith('==> '));
        expect(
          text,
          isNot(
            matches(
              RegExp(
                r'^==> bundle: \d+ docs, \d+ tokens, \d+ lines',
                multiLine: true,
              ),
            ),
          ),
        );
        expect(text, isNot(contains('.refs.txt')));
        expect(
          Directory('${project.path}/.specstone/bundles').existsSync(),
          isFalse,
        );
      },
    );
  });

  group('context --out writes a read-first and a refs file', () {
    const story = 'login/email_login';
    final header = RegExp(
      r'^==> bundle: (\d+) docs, (\d+) tokens, (\d+) lines · (.+) <==$',
    );

    File bundleFile(Directory project, String name) =>
        File('${project.path}/.specstone/bundles/$name');

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

    /// Returns the header of each file [stdout] prints, in order.
    List<RegExpMatch> headersOf(String stdout) => [
      for (final line in stdout.split('\n')) ?header.firstMatch(line),
    ];

    /// Returns the `- ` lines of the closing list of the bundle text [text].
    List<String> closingListOf(String text) {
      final lines = const LineSplitter().convert(text);
      final closing = lines.lastIndexWhere(
        (line) =>
            line.startsWith('==> bundle: ') && line.endsWith(' tokens <=='),
      );
      return [
        for (final line in lines.skip(closing + 1))
          if (line.startsWith('- ')) line,
      ];
    }

    test('implement and design write both files from the root and from a subfolder, each header naming its own file', () async {
      final project = await writeReadProject(extra: {'app/lib/.keep': ''});
      final nested = Directory('${project.path}/app/lib');
      for (final mode in ['implement', 'design']) {
        for (final folder in [project, nested]) {
          final text = await saved(folder, [story, '--for', mode, '--out']);
          final first = bundleFile(project, 'login-email_login.$mode.txt');
          final refs = bundleFile(project, 'login-email_login.$mode.refs.txt');
          final headers = headersOf(text);
          expect(headers, hasLength(2));
          for (final (i, file) in [first, refs].indexed) {
            expect(headers[i].group(4), file.resolveSymbolicLinksSync());
            expect(headers[i].group(3), '${file.readAsLinesSync().length}');
          }
          expect(text.indexOf(headers[1].group(0)!), greaterThan(0));
        }
      }
      expect(Directory('${nested.path}/.specstone').existsSync(), isFalse);
    });

    test('context --out prints its plan as the second stdout line', () async {
      final project = await writeReadProject();
      final text = await saved(project, [story, '--for', 'design', '--out']);
      final headers = headersOf(text);
      final lines = text.split('\n');
      final fileLines = headers.first.group(3);
      expect(lines.first, headers.first.group(0));
      expect(lines[1], 'read whole, in 1 read: lines 1-$fileLines');
      expect('read whole'.allMatches(text), hasLength(1));
    });

    test(
      'the two files hold the docs of the one-file bundle between them',
      () async {
        final project = await writeReadProject();
        await saved(project, [story, '--for', 'implement', '--out']);
        final whole = readRunner(project);
        await whole.runner.run(['context', story, '--for', 'implement']);
        final both = [
          for (final name in ['', '.refs'])
            ...closingListOf(
              bundleFile(
                project,
                'login-email_login.implement$name.txt',
              ).readAsStringSync(),
            ),
        ];
        expect(both..sort(), closingListOf(whole.out.toString())..sort());
      },
    );

    test('--out <path> from a subfolder writes b.txt and b.refs.txt beside it, and --json describes both', () async {
      final project = await writeReadProject(extra: {'app/.keep': ''});
      final nested = Directory('${project.path}/app');
      final text = await saved(nested, [
        story,
        '--for',
        'implement',
        '--out',
        '../out/b.txt',
      ]);
      final first = File('${project.path}/out/b.txt');
      final refs = File('${project.path}/out/b.refs.txt');
      expect(first.existsSync(), isTrue);
      expect(refs.existsSync(), isTrue);
      final headers = headersOf(text);
      expect(headers[0].group(4), first.resolveSymbolicLinksSync());
      expect(headers[1].group(4), refs.resolveSymbolicLinksSync());
      final json = jsonDecode(
        await saved(nested, [
          story,
          '--for',
          'implement',
          '--out=../out/b.txt',
          '--json',
        ]),
      ) as Map<String, Object?>;
      expect(json['out'], first.resolveSymbolicLinksSync());
      final refsJson = json['refs']! as Map<String, Object?>;
      expect(refsJson.keys.toList(), ['out', 'tokens', 'lines', 'docs']);
      expect(refsJson['out'], refs.resolveSymbolicLinksSync());
    });

    test('a refs file with no part is still written and replaces an older refs file', () async {
      final project = await writeReadProject();
      const name = 'login-email_login.implement-no-project';
      final refs = bundleFile(project, '$name.refs.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('old refs of an earlier call\n');
      final text = await saved(project, [
        story,
        '--for',
        'implement',
        '--no-project',
        '--out',
      ]);
      expect(bundleFile(project, '$name.txt').existsSync(), isTrue);
      expect(refs.readAsStringSync(), startsWith('==> bundle: 0 docs, '));
      expect(refs.readAsLinesSync(), hasLength(1));
      expect(headersOf(text)[1].group(4), refs.resolveSymbolicLinksSync());
    });

    test(
      '--for query --out writes one file, and no --out prints one bundle',
      () async {
        final project = await writeReadProject();
        final text = await saved(project, [story, '--for', 'query', '--out']);
        expect(headersOf(text), hasLength(1));
        expect(
          bundleFile(project, 'login-email_login.query.txt').existsSync(),
          isTrue,
        );
        expect(
          bundleFile(project, 'login-email_login.query.refs.txt').existsSync(),
          isFalse,
        );
        final plain = readRunner(project);
        expect(
          await plain.runner.run(['context', story, '--for', 'implement']),
          0,
        );
        expect(headersOf(plain.out.toString()), isEmpty);
        expect(
          Directory('${project.path}/.specstone/bundles')
              .listSync()
              .map((file) => file.uri.pathSegments.last),
          ['login-email_login.query.txt'],
        );
      },
    );

    test('a refused path writes neither file', () async {
      for (final (out, refs) in [
        ('docs/prds/b.txt', 'docs/prds/b.refs.txt'),
        ('.git/b.txt', '.git/b.refs.txt'),
        ('.specstone/config.yaml', '.specstone/config.refs.yaml'),
      ]) {
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
            out,
          ]),
          73,
          reason: out,
        );
        expect(run.out.toString(), isEmpty);
        expect(File('${project.path}/$refs').existsSync(), isFalse);
        expect(
          Directory('${project.path}/.specstone/bundles').existsSync(),
          isFalse,
        );
      }
    });
  });

  group('context --out prunes old bundle files', () {
    const story = 'login/email_login';
    final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));

    /// Writes [path] under [project], last modified and read [age] ago (two
    /// days by default), and returns it.
    File aged(Directory project, String path, {Duration? age}) {
      final then = age == null ? twoDaysAgo : DateTime.now().subtract(age);
      return File('${project.path}/$path')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('old\n')
        ..setLastModifiedSync(then)
        ..setLastAccessedSync(then);
    }

    /// The `--out` commands that prune, each with the report file it writes.
    const writers = {
      'get': (['get', story, '--out'], 'get.login-email_login.txt'),
      'check': (['check', story, '--out'], 'check.login-email_login.txt'),
      'guide': (['guide', 'feature', '--out'], 'guide.feature.txt'),
    };

    /// Returns the config text of the fixture project with a `cleanup:` map.
    String cleanupConfig(String bounds) =>
        '${shippedPinsConfig()}cleanup:\n$bounds';

    Future<(int, String)> run(Directory project, List<String> args) async {
      final result = readRunner(project);
      final status = await result.runner.run(args);
      return (status, result.out.toString());
    }

    test('an aged file under bundles/, a subfolder included, is gone; reports/ and a fresh file stay; stdout is unchanged', () async {
      final project = await writeReadProject();
      final old = aged(project, '.specstone/bundles/old.txt');
      final nested = aged(project, '.specstone/bundles/sub/old.txt');
      final report = aged(project, '.specstone/reports/old.txt');
      final fresh = File('${project.path}/.specstone/bundles/fresh.txt')
        ..writeAsStringSync('fresh\n');
      final args = ['context', story, '--for', 'implement', '--out'];
      final (status, first) = await run(project, args);
      expect(status, 0);
      expect(old.existsSync(), isFalse);
      expect(nested.existsSync(), isFalse);
      expect(nested.parent.existsSync(), isTrue);
      expect(report.existsSync(), isTrue);
      expect(fresh.existsSync(), isTrue);
      expect(first, isNot(contains('old.txt')));
      expect((await run(project, args)).$2, first);
      for (final name in [
        'login-email_login.implement',
        'login-email_login.implement.refs',
      ]) {
        expect(
          File('${project.path}/.specstone/bundles/$name.txt').existsSync(),
          isTrue,
        );
      }
    });

    test('an --out <path> run prunes the bundles folder too', () async {
      final project = await writeReadProject();
      final old = aged(project, '.specstone/bundles/old.txt');
      final (status, _) = await run(project, [
        'context',
        story,
        '--for',
        'implement',
        '--out',
        'out/b.txt',
      ]);
      expect(status, 0);
      expect(old.existsSync(), isFalse);
    });

    test('a bundles folder that is a link prunes nothing in the folder it leads to', () async {
      final project = await writeReadProject();
      final outside = await writeTree({'.keep': ''});
      final old = File('${outside.path}/old.txt')
        ..writeAsStringSync('old\n')
        ..setLastModifiedSync(twoDaysAgo)
        ..setLastAccessedSync(twoDaysAgo);
      Link('${project.path}/.specstone/bundles').createSync(outside.path);
      final (status, _) = await run(project, [
        'context',
        story,
        '--for',
        'implement',
        '--out',
        'out/b.txt',
      ]);
      expect(status, 0);
      expect(File('${project.path}/out/b.txt').existsSync(), isTrue);
      expect(old.existsSync(), isTrue);
    }, skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null);

    test('a refused context --out prunes nothing', () async {
      final project = await writeReadProject();
      final old = aged(project, '.specstone/bundles/old.txt');
      for (final args in [
        ['--out', 'docs/prds/b.txt'],
        ['--out', ''],
        ['--out', '--budget', '10'],
      ]) {
        final (status, _) = await run(project, [
          'context',
          story,
          '--for',
          'implement',
          ...args,
        ]);
        expect(status, anyOf(64, 73), reason: '$args');
        expect(old.existsSync(), isTrue, reason: '$args');
      }
    });

    test('get --out, check --out, and guide --out each prune an aged bundle and report and keep their own file', () async {
      for (final MapEntry(key: name, value: (args, written))
          in writers.entries) {
        final project = await writeReadProject();
        final oldBundle = aged(project, '.specstone/bundles/old.txt');
        final oldReport = aged(
          project,
          '.specstone/reports/old.txt',
          age: const Duration(days: 8),
        );
        final result = readRunner(project);
        final status = await result.runner.run(args);
        expect(status, anyOf(0, 1), reason: '$name ${result.err}');
        expect(oldBundle.existsSync(), isFalse, reason: name);
        expect(oldReport.existsSync(), isFalse, reason: name);
        expect(
          File('${project.path}/.specstone/reports/$written').existsSync(),
          isTrue,
          reason: name,
        );
      }
    });

    test('check --out with a finding exits 1 and prunes', () async {
      final project = await writeReadProject();
      final old = aged(project, '.specstone/bundles/old.txt');
      final (status, _) = await run(project, ['check', story, '--out']);
      expect(status, 1);
      expect(old.existsSync(), isFalse);
    });

    test('get and context with no --out delete nothing', () async {
      final project = await writeReadProject();
      final old = aged(project, '.specstone/bundles/old.txt');
      final oldReport = aged(
        project,
        '.specstone/reports/old.txt',
        age: const Duration(days: 8),
      );
      for (final args in [
        ['get', story],
        ['context', story, '--for', 'implement'],
        ['check', story],
        ['guide', 'feature'],
      ]) {
        final (status, _) = await run(project, args);
        expect(status, anyOf(0, 1), reason: '$args');
        expect(old.existsSync(), isTrue, reason: '$args');
        expect(oldReport.existsSync(), isTrue, reason: '$args');
      }
    });

    test('a refused get --out and check --out keep every aged file', () async {
      final project = await writeReadProject();
      final files = [
        aged(project, '.specstone/bundles/old.txt'),
        aged(
          project,
          '.specstone/reports/old.txt',
          age: const Duration(days: 8),
        ),
      ];
      for (final command in ['get', 'check']) {
        for (final out in ['docs/prds/b.txt', '.specstone/config.yaml', '']) {
          final (status, _) = await run(project, [
            command,
            story,
            '--out',
            out,
          ]);
          expect(status, anyOf(64, 73), reason: '$command $out');
          for (final file in files) {
            expect(file.existsSync(), isTrue, reason: '$command $out');
          }
        }
      }
    });

    test(
      'a cleanup map in the config moves the bundle and the report bound',
      () async {
        final tighter = await writeReadProject(
          extra: {
            '.specstone/config.yaml': cleanupConfig(
              '  bundles_max_age_hours: 1\n  reports_max_age_days: 1\n',
            ),
          },
        );
        final tightBundle = aged(
          tighter,
          '.specstone/bundles/old.txt',
          age: const Duration(hours: 3),
        );
        final tightReport = aged(tighter, '.specstone/reports/old.txt');
        expect((await run(tighter, ['get', story, '--out'])).$1, 0);
        expect(tightBundle.existsSync(), isFalse);
        expect(tightReport.existsSync(), isFalse);

        final looser = await writeReadProject(
          extra: {
            '.specstone/config.yaml': cleanupConfig(
              '  bundles_max_age_hours: 72\n  reports_max_age_days: 30\n',
            ),
          },
        );
        final looseBundle = aged(looser, '.specstone/bundles/old.txt');
        final looseReport = aged(
          looser,
          '.specstone/reports/old.txt',
          age: const Duration(days: 8),
        );
        expect((await run(looser, ['get', story, '--out'])).$1, 0);
        expect(looseBundle.existsSync(), isTrue);
        expect(looseReport.existsSync(), isTrue);
      },
    );

    test(
      'a cleanup map in the config moves the report bound of guide --out',
      () async {
        final tighter = await writeReadProject(
          extra: {
            '.specstone/config.yaml': cleanupConfig(
              '  reports_max_age_days: 1\n',
            ),
          },
        );
        final tightReport = aged(tighter, '.specstone/reports/old.txt');
        expect((await run(tighter, ['guide', 'feature', '--out'])).$1, 0);
        expect(tightReport.existsSync(), isFalse);

        final looser = await writeReadProject(
          extra: {
            '.specstone/config.yaml': cleanupConfig(
              '  reports_max_age_days: 30\n',
            ),
          },
        );
        final looseReport = aged(
          looser,
          '.specstone/reports/old.txt',
          age: const Duration(days: 8),
        );
        expect((await run(looser, ['guide', 'feature', '--out'])).$1, 0);
        expect(looseReport.existsSync(), isTrue);
      },
    );

    test('a guide --out <path> with no project above it exits 0 and touches no folder', () async {
      final folder = await writeTree({'.keep': ''});
      final (status, out) = await run(folder, [
        'guide',
        'feature',
        '--out',
        'out/guide.txt',
      ]);
      expect(status, 0);
      expect(out, contains('guide.txt'));
      expect(File('${folder.path}/out/guide.txt').existsSync(), isTrue);
      expect(Directory('${folder.path}/.specstone').existsSync(), isFalse);
    });

    test('a path under .specstone/ outside bundles/ and reports/ is refused and prunes nothing', () async {
      final project = await writeReadProject();
      final old = aged(project, '.specstone/bundles/old.txt');
      for (final path in [
        '.specstone/config.yaml',
        '.specstone/records/b.txt',
      ]) {
        final (status, out) = await run(project, [
          'context',
          story,
          '--for',
          'implement',
          '--out',
          path,
        ]);
        expect(status, 73, reason: path);
        expect(out, isEmpty, reason: path);
        expect(old.existsSync(), isTrue, reason: path);
      }
    });

    test(
      'get, check, and guide print the same with a file to prune as without',
      () async {
        for (final MapEntry(key: name, value: (args, _)) in writers.entries) {
          for (final flag in ['', '--json']) {
            final withFlag = [...args, if (flag.isNotEmpty) flag];
            final project = await writeReadProject();
            final (cleanStatus, clean) = await run(project, withFlag);
            final old = aged(project, '.specstone/bundles/old.txt');
            final (status, pruned) = await run(project, withFlag);
            expect(old.existsSync(), isFalse, reason: '$name $flag');
            expect(status, cleanStatus, reason: '$name $flag');
            expect(pruned, clean, reason: '$name $flag');
            expect(pruned, isNot(contains('old.txt')), reason: '$name $flag');
          }
        }
      },
    );

    test('a pruning run deletes nothing under reports/, trash/, build/, or of the index', () async {
      final project = await writeReadProject();
      final old = aged(project, '.specstone/bundles/old.txt');
      final kept = [
        aged(project, '.specstone/reports/old.txt'),
        aged(project, '.specstone/trash/old.txt'),
        aged(project, '.specstone/build/old.txt'),
        aged(project, 'build/old.txt'),
      ];
      final (before, _) = await run(project, [
        'context',
        story,
        '--for',
        'query',
      ]);
      expect(before, 0);
      final index = File('${project.path}/.specstone/index.sqlite');
      expect(index.existsSync(), isTrue);
      final (status, _) = await run(project, [
        'context',
        story,
        '--for',
        'implement',
        '--out',
      ]);
      expect(status, 0);
      expect(old.existsSync(), isFalse);
      for (final file in kept) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }
      expect(index.existsSync(), isTrue);
    });

    test(
      'the pruning of an aged file leaves the --json index as it was',
      () async {
        final project = await writeReadProject();
        final args = [
          'context',
          story,
          '--for',
          'implement',
          '--out',
          '--json',
        ];
        final (_, clean) = await run(project, args);
        final old = aged(project, '.specstone/bundles/old.txt');
        final (status, pruned) = await run(project, args);
        expect(status, 0);
        expect(old.existsSync(), isFalse);
        expect(pruned, clean);
        expect(pruned, isNot(contains('old.txt')));
      },
    );
  });

  group('the verification matrix of a record', () {
    const recordFile = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const validateRow =
        '- email_login/validate_credentials E01: `a wrong password`';
    const resetRow = '- reset_password/send_reset_link E01: `a link is mailed`';
    const resetStory =
        'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md';
    const resetFr =
        'docs/prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md';

    Future<Directory> project() => writeReadProject(
      extra: {
        resetStory: '# Agent resets a password\n\n## Use Case\nReset it.\n',
        resetFr:
            '---\nverify_method: test\n---\n\n# Send a reset link\n\n'
            '## Statement\nThe system shall mail a link.\n',
        '.specstone/templates/implementation.yaml':
            'sections:\n  - id: notes\n    header: Notes\n',
        recordFile:
            "---\nstatuses:\n  - 'email_login:planned'\ntests:\n"
            "  - 'email_login/validate_credentials:test/login_test.dart'\n"
            "  - 'reset_password/send_reset_link:test/reset_test.dart'\n"
            '---\n\n# Login implementation\n\n## Verification matrix\n\n'
            '$validateRow\n$resetRow\n\n## Notes\n\nSee the rows.\n',
        'test/login_test.dart': '',
        'test/reset_test.dart': '',
      },
    );

    test('context --code on a test file prints the matrix rows of its bundled FRs alone', () async {
      final (:runner, :out, :err) = readRunner(await project());

      expect(
        await runner.run([
          'context',
          '--code',
          'test/login_test.dart',
          '--for',
          'implement',
        ]),
        0,
        reason: err.toString(),
      );
      expect(out.toString(), contains(validateRow));
      expect(out.toString(), isNot(contains('send_reset_link E01')));
    });

    test('the --out index lines match the trimmed record', () async {
      final folder = await project();
      final (:runner, :out, :err) = readRunner(folder);

      expect(
        await runner.run([
          'context',
          'login/email_login',
          '--for',
          'implement',
          '--out',
        ]),
        0,
        reason: err.toString(),
      );
      final fileLines = File(
        '${folder.path}/.specstone/bundles/login-email_login.implement.txt',
      ).readAsLinesSync();
      final index = RegExp(
        r'^- login \(implementation\) · (\d+)-(\d+) · '
        r'verification_matrix (\d+), notes (\d+)$',
        multiLine: true,
      ).firstMatch(out.toString())!;
      int at(int group) => int.parse(index.group(group)!) - 1;

      expect(fileLines.join('\n'), isNot(contains('send_reset_link E01')));
      expect(fileLines[at(1)], startsWith('==> login (implementation) · '));
      expect(fileLines[at(3)], '## Verification matrix {#verification_matrix}');
      expect(fileLines[at(4)], '## Notes {#notes}');
      expect(fileLines[at(2)], 'See the rows.');
    });
  });

  group('context design --out splits the ancestor spec docs and their pieces', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    test('context design out on a story writes ancestor spec docs to the refs file and their pieces to the read-first file', () async {
      final project = await writeReadProject(
        extra: {
          'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md': '# Validate credentials\n\n## Statement\nThe system shall check the email, by [INV-1](../../../../specs/f01_login/DOMAIN.md#invariants).\n',
          'docs/specs/f01_login/DOMAIN.md': '# Login domain\n\n## Invariants\n- **INV-1** An account has an email.\n- **INV-2** An account has a password.\n',
          'docs/specs/f01_login/API.md':
              '# Login API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
              '| [validate](../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md) | `signIn` |\n'
              '| other | `signOut` |\n',
        },
      );
      final run = await Process.run(binary, [
        'context',
        'login/email_login',
        '--for',
        'design',
        '--out',
      ], workingDirectory: project.path);
      expect(run.exitCode, 0, reason: '${run.stderr}');

      final folder = '${project.path}/.specstone/bundles';
      final readFirst = File('$folder/login-email_login.design.txt')
          .readAsStringSync();
      final refs = File('$folder/login-email_login.design.refs.txt')
          .readAsStringSync();
      const domain = '==> login (domain) · specs/f01_login/DOMAIN.md';
      const api = '==> login (api) · specs/f01_login/API.md';
      expect(refs, contains('$domain <==\n# Login domain'));
      expect(refs, contains('$api <==\n# Login API'));
      expect(readFirst, isNot(contains('$domain <==')));
      expect(
        readFirst,
        contains('$domain#invariants · item INV-1 · cited <=='),
      );
      expect(readFirst, contains('$api#fr_trace · cites <=='));
      expect(readFirst, isNot(contains('INV-2')));
      expect(readFirst, isNot(contains('signOut')));
      final stdout = run.stdout as String;
      expect(
        stdout,
        matches(
          RegExp(
            r'^- login \(domain\) · \d+-\d+ · cited invariants \[INV-1\]',
            multiLine: true,
          ),
        ),
      );
      expect(
        stdout,
        matches(
          RegExp(
            r'^- login \(api\) · \d+-\d+ · cites fr_trace',
            multiLine: true,
          ),
        ),
      );
    });
  });

  group('a path outside the code roots that a skill doc reaches', () {
    late String binary;

    setUpAll(() async => binary = await buildSpecstone());

    /// Writes a project whose skill doc covers the folder of [skillFile], with
    /// the code roots [targets], a `name: root` line each.
    Future<Directory> writeSkillProject(List<String> targets) {
      final lines = [for (final target in targets) '  $target\n'].join();
      return writeReadProject(
        extra: {
          '.specstone/config.yaml': '${skillPinsConfig()}targets:\n$lines',
          ...skillDocFile(['.claude/skills/review/']),
          skillFile: skillText,
          'flutter_lib/.keep': '',
          'jaspr_lib/.keep': '',
        },
      );
    }

    Future<ProcessResult> run(Directory project, List<String> args) =>
        Process.run(binary, [
          'context',
          '--code',
          skillFile,
          '--for',
          'implement',
          ...args,
        ], workingDirectory: project.path);

    const twoTargets = [
      'flutter:\n    code_root: flutter_lib',
      'jaspr:\n    code_root: jaspr_lib',
    ];

    test("a skill-covered path outside the code roots prints the first target's code target line with two targets", () async {
      final project = await writeSkillProject(twoTargets);

      final text = await run(project, []);
      final json = await run(project, ['--json']);

      expect(text.exitCode, 0, reason: '${text.stderr}');
      expect(
        text.stdout as String,
        startsWith('==> code target: flutter <==\n'),
      );
      expect(text.stdout as String, contains('(skill)'));
      expect(
        (jsonDecode(json.stdout as String)
            as Map<String, Object?>)['codeTarget'],
        'flutter',
      );
    });
    test('that path with another target is argument_conflict', () async {
      final project = await writeSkillProject(twoTargets);

      final other = await run(project, ['--target', 'jaspr']);
      final same = await run(project, ['--target', 'flutter']);

      expect(other.exitCode, 64);
      expect(
        other.stderr,
        'the code path $skillFile lies in the code target flutter, not jaspr\n',
      );
      expect(same.exitCode, 0, reason: '${same.stderr}');
    });
    test('that path with one target prints no code target line', () async {
      final project = await writeSkillProject([
        'app:\n    code_root: flutter_lib',
      ]);

      final text = await run(project, []);

      expect(text.exitCode, 0, reason: '${text.stderr}');
      expect(text.stdout as String, contains('(skill)'));
      expect(text.stdout as String, isNot(contains('code target')));
    });
  });

  group('context over several targets', () {
    const first = 'login/email_login';
    const second = 'login/reset_password';
    final stories = {
      'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md':
          '# Agent resets a password\n',
      'docs/prds/features/f01_login/us03_magic_link/USER_STORY.md':
          '# Agent signs in with a link\n',
      'app/lib/src/login/.keep': '',
    };

    test('--for query with two targets refuses argument_invalid, exit 64, and writes nothing', () async {
      final project = await writeReadProject(extra: stories);
      const query = '--for query takes one target; got 2';
      const summary = '--summary takes one target; got 2';
      for (final (args, message) in [
        (['--for', 'query'], query),
        (['--for', 'query', '--summary'], query),
        (['--for', 'query', '--code', 'app/lib/src/login/'], query),
        (['--for', 'query', '--budget', '0'], query),
        (['--for', 'query', '--out', ''], query),
        (['--for', 'query', '--out'], query),
        (['--summary'], summary),
        (['--for', 'design', '--summary'], summary),
        (['--for', 'design', '--summary', '--out', ''], summary),
      ]) {
        final run = readRunner(project);
        expect(
          await run.runner.run(['context', first, second, ...args]),
          64,
          reason: '$args',
        );
        expect(run.err.toString(), '$message\n', reason: '$args');
        expect(run.out.toString(), isEmpty, reason: '$args');
        expect(
          Directory('${project.path}/.specstone/bundles').existsSync(),
          isFalse,
          reason: '$args',
        );
      }
      final unresolved = readRunner(project);
      expect(
        await unresolved.runner.run([
          'context',
          first,
          'nobody',
          '--for',
          'query',
        ]),
        64,
      );
      expect(unresolved.err.toString(), '$query\n');
      final json = readRunner(project);
      expect(
        await json.runner.run([
          'context',
          first,
          second,
          '--for',
          'query',
          '--json',
        ]),
        64,
      );
      expect(_errorOf(json.err), {
        'code': 'argument_invalid',
        'message': query,
      });
    });

    test('--code with a target and an empty --out refuses argument_invalid before argument_conflict', () async {
      final project = await writeReadProject(extra: stories);
      final run = readRunner(project);
      expect(
        await run.runner.run([
          'context',
          first,
          '--code',
          'app/lib/src/login/',
          '--for',
          'implement',
          '--out',
          '',
        ]),
        64,
      );
      expect(run.err.toString(), '--out takes a file path, not ""\n');
      final conflict = readRunner(project);
      expect(
        await conflict.runner.run([
          'context',
          first,
          '--code',
          'app/lib/src/login/',
          '--for',
          'implement',
        ]),
        64,
      );
      expect(conflict.err.toString(), 'give a target or --code, not both\n');
    });

    test(
      'two design targets print one bundle, each sibling story in summary',
      () async {
        final project = await writeReadProject(extra: stories);
        final run = readRunner(project);
        expect(
          await run.runner.run(['context', first, second, '--for', 'design']),
          0,
          reason: run.err.toString(),
        );
        final lines = run.out.toString().split('\n');
        for (final story in [first, second]) {
          expect(
            lines.where((l) => l.startsWith('==> $story (user_story) · ')),
            hasLength(1),
            reason: story,
          );
          expect(
            lines.where((l) => l == '- $story (user_story)'),
            hasLength(1),
          );
        }
        expect(
          lines.where((l) => l == '- login/magic_link (user_story) · summary'),
          hasLength(1),
        );
      },
    );

    test('an unresolved target among several refuses before anything prints, one line per target', () async {
      final project = await writeReadProject(extra: stories);
      final run = readRunner(project);
      expect(
        await run.runner.run([
          'context',
          'nobody',
          first,
          'nope',
          '--for',
          'design',
          '--out',
        ]),
        64,
      );
      expect(run.out.toString(), isEmpty);
      final lines = run.err.toString().trimRight().split('\n');
      expect(lines, hasLength(2));
      expect(lines[0], contains('nobody'));
      expect(lines[1], contains('nope'));
      expect(
        Directory('${project.path}/.specstone/bundles').existsSync(),
        isFalse,
      );
    });

    test('--json lists the targets in the order given, and holds target for one alone', () async {
      final project = await writeReadProject(extra: stories);
      Future<Map<String, Object?>> jsonOf(List<String> targets) async {
        final run = readRunner(project);
        expect(
          await run.runner.run([
            'context',
            ...targets,
            '--for',
            'design',
            '--json',
          ]),
          0,
          reason: run.err.toString(),
        );
        return jsonDecode(run.out.toString()) as Map<String, Object?>;
      }

      final one = await jsonOf([first]);
      expect(one['target'], first);
      expect(one['targets'], [first]);
      final two = await jsonOf([second, first]);
      expect(two.containsKey('target'), isFalse);
      expect(two['targets'], [second, first]);
    });

    test('a bare --out with two targets writes the joined file name and its refs file', () async {
      final project = await writeReadProject(extra: stories);
      final run = readRunner(project);
      expect(
        await run.runner.run([
          'context',
          first,
          second,
          '--for',
          'design',
          '--out',
        ]),
        0,
        reason: run.err.toString(),
      );
      const name = 'login-email_login+login-reset_password.design.txt';
      final file = File('${project.path}/.specstone/bundles/$name');
      final refs = File(
        '${project.path}/.specstone/bundles/'
        'login-email_login+login-reset_password.design.refs.txt',
      );
      expect(file.existsSync(), isTrue);
      expect(refs.existsSync(), isTrue);
      final headers = run.out
          .toString()
          .split('\n')
          .where((l) => l.startsWith('==> bundle: '));
      expect(headers, hasLength(2));
      expect(headers.first, contains(name));
    });
  });
  test(
    'context of an agent doc for design prints its feature right after it',
    () async {
      final project = await writeReadProject(
        extra: {
          '.specstone/config.yaml': skillPinsConfig(),
          'docs/specs/agents/reviewer.md':
              '---\nfeature:\n  - login\n---\n\n'
              '# reviewer\n\n## Role\n\nReviews a diff.\n',
        },
      );
      final run = readRunner(project);
      expect(
        await run.runner.run(['context', 'agent:reviewer', '--for', 'design']),
        0,
        reason: run.err.toString(),
      );
      final naming = [
        for (final line in run.out.toString().split('\n'))
          if (line.startsWith('==> ') && !line.startsWith('==> bundle: ')) line,
      ];
      final at = naming.indexWhere((l) => l.startsWith('==> reviewer (agent)'));
      expect(at, isNonNegative);
      expect(naming[at + 1], startsWith('==> login (feature)'));
    },
  );
}
