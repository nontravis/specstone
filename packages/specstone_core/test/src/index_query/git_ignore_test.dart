import 'dart:io';

import 'package:specstone_core/src/index_query/git_ignore.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('specstone_git_ignore_');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  void write(String path, String text) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  Directory folder(String path) =>
      Directory('${root.path}/$path')..createSync(recursive: true);

  // D14
  test('matches git pattern forms: a negation, a folder-only pattern, an '
      'anchored pattern, and a double star', () {
    write(
      '.gitignore',
      [
        '# a comment',
        '*.log',
        '!keep.log',
        'build/',
        '!build/kept.txt',
        '/top.txt',
        'docs/*.tmp',
        '**/cache',
        'a/**/z',
        'out/**',
        '!out/kept.txt',
        r'\#hash',
        'spaced   ',
      ].join('\n'),
    );
    final rules = GitIgnoreRules.above(root);
    bool ignoredFile(String path) => rules.ignores(path, isFolder: false);
    bool ignoredFolder(String path) => rules.ignores(path, isFolder: true);

    expect(ignoredFile('a.log'), isTrue);
    expect(ignoredFile('sub/b.log'), isTrue);
    expect(ignoredFile('keep.log'), isFalse);
    expect(ignoredFolder('build'), isTrue);
    expect(ignoredFolder('src/build'), isTrue);
    expect(ignoredFile('build'), isFalse);
    expect(
      ignoredFile('build/kept.txt'),
      isTrue,
      reason: 'its folder is ignored',
    );
    expect(ignoredFile('top.txt'), isTrue);
    expect(ignoredFile('sub/top.txt'), isFalse);
    expect(ignoredFile('docs/a.tmp'), isTrue);
    expect(ignoredFile('sub/docs/a.tmp'), isFalse);
    expect(ignoredFile('docs/sub/a.tmp'), isFalse);
    expect(ignoredFolder('cache'), isTrue);
    expect(ignoredFolder('x/y/cache'), isTrue);
    expect(ignoredFile('a/z'), isTrue);
    expect(ignoredFile('a/b/c/z'), isTrue);
    expect(
      ignoredFolder('out'),
      isFalse,
      reason: 'out/** matches only inside out/',
    );
    expect(ignoredFile('out/x.txt'), isTrue);
    expect(ignoredFile('out/kept.txt'), isFalse);
    expect(ignoredFile('#hash'), isTrue);
    expect(ignoredFile('# a comment'), isFalse);
    expect(ignoredFile('spaced'), isTrue);
  });

  // D14
  test('an ignore file starting with a byte order mark matches its first '
      'pattern', () {
    write('.gitignore', '${String.fromCharCode(0xFEFF)}*.log\n');

    expect(
      GitIgnoreRules.above(root).ignores('a.log', isFolder: false),
      isTrue,
    );
  });

  // D14
  test('a nested .gitignore overrides its parent, and info/exclude applies '
      'under the work tree top', () {
    write('.gitignore', '*.outside\n');
    write('repo/.git/info/exclude', '*.secret\n');
    write('repo/.gitignore', '*.gen\n!shown.secret\n');
    write('repo/app/.gitignore', '!keep.gen\n');
    write('repo/app/lib/.gitignore', '*.dart\n');
    final rules = GitIgnoreRules.above(folder('repo/app'));

    expect(rules.ignores('a.secret', isFolder: false), isTrue);
    expect(rules.ignores('shown.secret', isFolder: false), isFalse);
    expect(rules.ignores('a.gen', isFolder: false), isTrue);
    expect(rules.ignores('keep.gen', isFolder: false), isFalse);
    expect(rules.ignores('a.outside', isFolder: false), isFalse);
    expect(rules.ignores('lib/a.dart', isFolder: false), isFalse);
    expect(
      rules.within(folder('repo/app/lib')).ignores('a.dart', isFolder: false),
      isTrue,
    );

    write('main/.git/info/exclude', '*.secret\n');
    write('main/.git/worktrees/wt/commondir', '../..\n');
    write('wt/.git', 'gitdir: ${root.path}/main/.git/worktrees/wt\n');
    final linked = GitIgnoreRules.above(folder('wt/lib'));

    expect(linked.ignores('a.secret', isFolder: false), isTrue);
  });

  group('a pattern matched without a RegExp decides as its RegExp does', () {
    const patterns = [
      'build',
      'build/',
      '!keep.log',
      '*.log',
      '*',
      '*.log/',
      'lib*',
      'lib*/',
      '/top.txt',
      'a/b',
      '/a/b/',
      '**/cache',
      '**/a/b',
      '**/cache/',
      '/**/cache',
      'a/**/z',
      'out/**',
      '**',
      '**/',
      '**.log',
      'docs/*.tmp',
      '/*',
      '*a*',
      'a?',
      '[ab]',
      '[!a]*',
      r'\#hash',
      r'\!bang',
      r'li\*',
      r'a\/b',
      'spaced   ',
      r'spaced\ ',
      'a//b',
    ];
    const names = [
      'build',
      'src/build',
      'build/x',
      'keep.log',
      'a.log',
      'log',
      'x.logx',
      'sub/a.log',
      'lib',
      'libfoo',
      'foo.lib',
      'li*',
      'top.txt',
      'sub/top.txt',
      'a',
      'b',
      'ab',
      'a/b',
      'x/a/b',
      'xa/b',
      'a/b/c',
      'cache',
      'x/y/cache',
      'xcache',
      'a/z',
      'a/b/c/z',
      'out',
      'out/x.txt',
      'docs/a.tmp',
      'docs/sub/a.tmp',
      '#hash',
      '!bang',
      'spaced',
      'spaced ',
      '.gitignore',
    ];
    final paths = [
      for (final name in names) ...[name, '$name/'],
    ];

    for (final pattern in patterns) {
      test(pattern, () {
        final probe = IgnorePatternProbe.parse(pattern)!;
        for (final path in paths) {
          expect(
            probe.matches(path),
            probe.matchesByRegExp(path),
            reason: '$pattern on $path',
          );
        }
      });
    }
  });

  test('a pattern with no wildcard beyond a leading or trailing star or a '
      'leading **/ holds no RegExp', () {
    const holdsRegExp = {
      'build': false,
      'build/': false,
      '!keep.log': false,
      '*.log': false,
      'lib*': false,
      '/top.txt': false,
      'a/b': false,
      '**/cache': false,
      r'\#hash': false,
      'spaced   ': false,
      'a/**/z': true,
      'docs/*.tmp': true,
      '*a*': true,
      'a?': true,
      '[ab]': true,
    };

    for (final MapEntry(key: pattern, value: expected) in holdsRegExp.entries) {
      expect(
        IgnorePatternProbe.parse(pattern)!.holdsRegExp,
        expected,
        reason: pattern,
      );
    }
  });

  // D14
  test('outside a git work tree the rules start at the project root', () {
    write('.gitignore', '*.outer\n');
    write('project/.specstone/config.yaml', 'packs: []\n');
    write('project/.gitignore', '*.tmp\n');
    write('project/app/.gitignore', '*.app\n');
    write('bare/.gitignore', '*.tmp\n');
    final rules = GitIgnoreRules.above(folder('project/app'));

    expect(rules.ignores('a.tmp', isFolder: false), isTrue);
    expect(rules.ignores('a.app', isFolder: false), isTrue);
    expect(rules.ignores('a.outer', isFolder: false), isFalse);
    expect(
      GitIgnoreRules.above(folder('bare/app'))
          .ignores('a.tmp', isFolder: false),
      isFalse,
      reason: 'with no project root the code root is the top',
    );
  });
}
