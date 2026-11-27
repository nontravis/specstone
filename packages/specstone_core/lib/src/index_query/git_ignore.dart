// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved.
//
// The pattern parser and the rule match are adapted from pub's
// lib/src/ignore.dart (https://github.com/dart-lang/pub). That adapted part
// is governed by pub's BSD-style license, in git_ignore.LICENSE beside this
// file.

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart'
    show absoluteFrom, canonicalPath, isVolumeRoot, parentOf, pathInside;

const _separator = '/';
const _gitEntry = '.git';
const _ignoreFileName = '.gitignore';
const _projectConfig = '.specstone/config.yaml';
const _gitDirKey = 'gitdir:';
const _commonDirFile = 'commondir';
const _infoFolder = 'info';
const _excludeFile = 'exclude';
final String _native = Platform.pathSeparator;

/// The `.gitignore` rules that apply in one folder, matched as git matches
/// them: `info/exclude`, then each `.gitignore` from the work tree's top down
/// to the folder, a lower file's rules winning over a higher one's.
///
/// - No global excludes file is read, and git's index is not: a tracked file
///   the rules ignore is ignored.
/// - Matching is in exact case on every OS, as every Specstone path match is,
///   never by git's `core.ignoreCase`.
final class GitIgnoreRules {
  new _(this._folder, this._fromTop, this._files);

  /// Returns the rules that apply in [codeRoot].
  ///
  /// The work tree top is the nearest folder, [codeRoot] or above, holding a
  /// `.git` entry; outside git it is the nearest one holding
  /// `.specstone/config.yaml`, else [codeRoot]. Only inside git is
  /// `info/exclude` read, from the common git folder.
  static GitIgnoreRules above(Directory codeRoot) {
    final root = canonicalPath(codeRoot.path);
    final gitTop = _nearestHolding(root, _gitEntry);
    final top =
        gitTop ??
        _nearestHolding(root, _projectConfig.replaceAll(_separator, _native)) ??
        root;
    final fromTop = pathInside(top, root) ?? '';
    final excludeFile = gitTop == null ? null : _excludeFileOf(gitTop);
    final files = [
      if (excludeFile != null) _IgnoreFile.read(excludeFile, ''),
      _IgnoreFile.read(_join(top, _ignoreFileName), ''),
    ];
    var folder = top;
    var prefix = '';
    for (final name in fromTop.split(_separator)) {
      if (name.isEmpty) continue;
      folder = _join(folder, name);
      prefix = prefix.isEmpty ? name : '$prefix$_separator$name';
      files.add(_IgnoreFile.read(_join(folder, _ignoreFileName), prefix));
    }
    return GitIgnoreRules._(codeRoot.path, fromTop, files.nonNulls.toList());
  }

  /// The folder these rules apply in, as the caller wrote its path.
  final String _folder;

  /// [_folder]'s `/`-separated path from the work tree top, `''` at the top.
  final String _fromTop;

  /// The ignore files read, lowest precedence first.
  final List<_IgnoreFile> _files;

  /// Returns the rules that apply in [folder], a child of this folder written
  /// from this folder's path, adding its own `.gitignore`.
  GitIgnoreRules within(Directory folder) {
    if (!folder.path.startsWith(_folder)) {
      throw ArgumentError.value(folder.path, 'folder', 'lies outside $_folder');
    }
    final name = folder.path
        .substring(_folder.length)
        .replaceAll(_native, _separator)
        .split(_separator)
        .where((segment) => segment.isNotEmpty && segment != '.')
        .join(_separator);
    final fromTop = _fromTop.isEmpty ? name : '$_fromTop$_separator$name';
    final file = _IgnoreFile.read(_join(folder.path, _ignoreFileName), fromTop);
    return GitIgnoreRules._(
      folder.path,
      fromTop,
      file == null ? _files : [..._files, file],
    );
  }

  /// Whether the rules ignore [pathFromRule], or a folder on its way.
  ///
  /// - [pathFromRule]: `/`-separated, from the folder these rules apply in.
  bool ignores(String pathFromRule, {required bool isFolder}) {
    final path = _fromTop.isEmpty
        ? pathFromRule
        : '$_fromTop$_separator$pathFromRule';
    var slash = path.indexOf(
      _separator,
      _fromTop.isEmpty ? 0 : _fromTop.length + 1,
    );
    while (slash != -1) {
      if (_matches(path.substring(0, slash + 1))) return true;
      slash = path.indexOf(_separator, slash + 1);
    }
    return _matches(isFolder ? '$path$_separator' : path);
  }

  /// Whether the last rule matching [path], a path from the top ending in `/`
  /// for a folder, ignores it rather than re-including it.
  bool _matches(String path) {
    for (final file in _files.reversed) {
      final local = _Subject(
        file.prefix.isEmpty ? path : path.substring(file.prefix.length + 1),
      );
      for (final rule in file.rules.reversed) {
        if (rule.matches(local)) return !rule.negative;
      }
    }
    return false;
  }
}

/// The rules of one ignore file and the folder they are read from.
final class _IgnoreFile {
  new(this.prefix, this.rules);

  /// Returns the rules of the file at [path], null when it cannot be read or
  /// holds none.
  static _IgnoreFile? read(String path, String prefix) {
    final List<int> bytes;
    try {
      bytes = File(path).readAsBytesSync();
    } on FileSystemException {
      return null;
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    final rules = [
      for (final line in text.split(_lineBreak)) ?_parseIgnorePattern(line),
    ];
    return rules.isEmpty ? null : _IgnoreFile(prefix, rules);
  }

  /// The `/`-separated path from the work tree top of the folder the rules
  /// are read from, `''` at the top.
  final String prefix;

  final List<_IgnoreRule> rules;
}

/// One `.gitignore` line parsed as [GitIgnoreRules] parses it, for tests.
final class IgnorePatternProbe {
  new _(this._rule);

  /// Parses [line]; null for a blank line, a comment, or a broken pattern.
  static IgnorePatternProbe? parse(String line) {
    final rule = _parseIgnorePattern(line);
    return rule == null ? null : IgnorePatternProbe._(rule);
  }

  final _IgnoreRule _rule;

  /// Whether the rule matches through a RegExp rather than by its text.
  bool get holdsRegExp => _rule is _RegExpRule;

  /// Whether the rule matches [path], `/`-separated and ending in `/` for a
  /// folder, ignoring its `!`.
  bool matches(String path) => _rule.matches(_Subject(path));

  /// Whether the RegExp the pattern parses to matches [path].
  bool matchesByRegExp(String path) => RegExp(_rule.source).hasMatch(path);
}

/// A path a rule is matched against, from the rule's folder, ending in `/`
/// for a folder.
final class _Subject {
  new(this.path);

  final String path;

  // Lazy: a rule's kind reads only the forms it compares.
  late final bool isFolder = path.endsWith(_separator);

  /// [path] without its folder `/`.
  late final String bare = isFolder ? path.substring(0, path.length - 1) : path;

  /// The last segment of [bare].
  late final String base = bare.substring(bare.lastIndexOf(_separator) + 1);
}

sealed class _IgnoreRule {
  new(this.source, {required this.negative, required this.matchesFoldersOnly});

  /// The RegExp source the pattern parses to.
  final String source;

  /// Whether the rule re-includes what it matches (`!`).
  final bool negative;

  /// Whether the pattern ends in `/`.
  final bool matchesFoldersOnly;

  bool matches(_Subject subject) =>
      (!matchesFoldersOnly || subject.isFolder) && _matchesShape(subject);

  bool _matchesShape(_Subject subject);
}

/// How a pattern with no wildcard beyond a leading or trailing `*` or a
/// leading `**/` compares its text, as git's `match_basename` does.
enum _TextMatch {
  /// `name`: the last segment is the text.
  baseLiteral,

  /// `*name`: the last segment ends with the text.
  baseSuffix,

  /// `name*`: the last segment starts with the text.
  basePrefix,

  /// `/a/name` or `a/name`: the path is the text.
  pathLiteral,

  /// `**/a/name`: the path is the text or ends with `/` and the text.
  pathSuffix,
}

final class _TextRule extends _IgnoreRule {
  new(
    super.source,
    this.kind,
    this.text, {
    required super.negative,
    required super.matchesFoldersOnly,
  });

  final _TextMatch kind;

  /// The pattern's literal text, escapes resolved.
  final String text;

  @override
  bool _matchesShape(_Subject subject) => switch (kind) {
    _TextMatch.baseLiteral => subject.base == text,
    _TextMatch.baseSuffix => subject.base.endsWith(text),
    _TextMatch.basePrefix => subject.base.startsWith(text),
    _TextMatch.pathLiteral => subject.bare == text,
    _TextMatch.pathSuffix => _endsWithSegments(subject.bare),
  };

  bool _endsWithSegments(String path) {
    if (!path.endsWith(text)) return false;
    final before = path.length - text.length;
    return before == 0 || path[before - 1] == _separator;
  }
}

final class _RegExpRule extends _IgnoreRule {
  new(
    super.source, {
    required super.negative,
    required super.matchesFoldersOnly,
  }) : _pattern = RegExp(source);

  final RegExp _pattern;

  @override
  bool _matchesShape(_Subject subject) => _pattern.hasMatch(subject.path);
}

// MARK: - Work tree

/// A line break, LF or CR LF.
final _lineBreak = RegExp('\r?\n');

/// Returns the nearest folder, [folder] or above, that holds [name].
String? _nearestHolding(String folder, String name) {
  for (var current = folder; ; current = parentOf(current)) {
    if (FileSystemEntity.typeSync(_join(current, name), followLinks: false) !=
        FileSystemEntityType.notFound) {
      return current;
    }
    if (isVolumeRoot(current)) return null;
  }
}

/// Returns the `info/exclude` path of the work tree at [top]: under its `.git`
/// folder, or for a `.git` file under its `gitdir:` folder's `commondir`.
String? _excludeFileOf(String top) {
  final dotGit = _join(top, _gitEntry);
  final gitDir = FileSystemEntity.isDirectorySync(dotGit)
      ? dotGit
      : _linkedGitDir(top, dotGit);
  if (gitDir == null) return null;
  final commonDir = _firstLineOf(_join(gitDir, _commonDirFile));
  final infoDir = _join(
    commonDir == null ? gitDir : absoluteFrom(Directory(gitDir), commonDir),
    _infoFolder,
  );
  return _join(infoDir, _excludeFile);
}

/// Returns the folder a `.git` file at [dotGit] names, from [top] when
/// relative; null when it names none.
String? _linkedGitDir(String top, String dotGit) {
  final line = _firstLineOf(dotGit);
  if (line == null || !line.startsWith(_gitDirKey)) return null;
  return absoluteFrom(Directory(top), line.substring(_gitDirKey.length).trim());
}

/// Returns the first line of the file at [path], trimmed; null when it cannot
/// be read.
String? _firstLineOf(String path) {
  try {
    return File(path).readAsStringSync().split(_lineBreak).first.trim();
  } on FileSystemException {
    return null;
  }
}

String _join(String folder, String name) =>
    folder.endsWith(_native) ? '$folder$name' : '$folder$_native$name';

// MARK: - Pattern

/// Parses [pattern], one `.gitignore` line; null for a blank line, a comment,
/// or a broken pattern.
///
/// A trailing `/**` matches only inside its folder, as git's does, so a later
/// `!` line can re-include a file there.
_IgnoreRule? _parseIgnorePattern(String pattern) {
  if (pattern.startsWith('#')) return null;
  var first = 0;
  var end = pattern.length;

  final negative = pattern.startsWith('!');
  if (negative) first++;

  // Remove trailing whitespace unless escaped.
  while (end != 0 &&
      pattern[end - 1] == ' ' &&
      (end == 1 || pattern[end - 2] != r'\')) {
    end--;
  }
  if (first == end) return null;

  var current = first;
  String? peekChar() => current >= end ? null : pattern[current];
  String? previous() => current < 2 ? null : pattern[current - 2];

  final expr = StringBuffer();

  // The pattern's text and wildcards, to match it without a RegExp when only
  // a leading or trailing `*` or a leading `**/` is a wildcard.
  final literal = StringBuffer();
  final starPositions = <int>[];
  var leadsWithAnyFolders = false;
  var hasOtherWildcard = false;

  // Parses the inside of a [] range. Returns the value as a RegExp character
  // range, or null if the pattern was broken.
  String? parseCharacterRange() {
    final characterRange = StringBuffer();
    var isFirst = true;
    for (;;) {
      final nextChar = peekChar();
      if (nextChar == null) return null;
      current++;
      if (nextChar == r'\') {
        final escaped = peekChar();
        if (escaped == null) return null;
        current++;
        characterRange.write(escaped == '-' ? r'\-' : RegExp.escape(escaped));
      } else if (nextChar == '!' && isFirst) {
        characterRange.write('^');
      } else if (nextChar == ']' && isFirst) {
        characterRange.write(RegExp.escape(nextChar));
      } else if (nextChar == ']') {
        return characterRange.toString();
      } else {
        characterRange.write(nextChar);
      }
      isFirst = false;
    }
  }

  var relativeToPath = false;
  var matchesDirectoriesOnly = false;

  // A slash at the end matches folders only; anywhere else it anchors the
  // pattern at the ignore file's folder.
  void handleSlash() {
    if (current == end) {
      matchesDirectoriesOnly = true;
    } else {
      relativeToPath = true;
    }
  }

  for (;;) {
    final nextChar = peekChar();
    if (nextChar == null) break;
    current++;
    if (nextChar == '*') {
      if (peekChar() == '*') {
        current++;
        if (peekChar() == '/') {
          current++;
          final isLeading =
              current != end &&
              literal.isEmpty &&
              starPositions.isEmpty &&
              !leadsWithAnyFolders &&
              !hasOtherWildcard;
          leadsWithAnyFolders = leadsWithAnyFolders || isLeading;
          hasOtherWildcard = hasOtherWildcard || !isLeading;
          // Match nothing or a path followed by '/'.
          expr.write(current == end ? '.*' : '(?:(?:)|(?:.*/))');
          handleSlash();
        } else if (peekChar() == null &&
            current - 3 >= first &&
            pattern[current - 3] == '/') {
          hasOtherWildcard = true;
          expr.write('.+');
        } else {
          hasOtherWildcard = true;
          expr.write('.*');
        }
      } else if (previous() == '/' && peekChar() == null) {
        // /a/* should not match '/a/', so we require at least one character.
        hasOtherWildcard = true;
        expr.write('[^/]+');
      } else {
        starPositions.add(literal.length);
        expr.write('[^/]*');
      }
    } else if (nextChar == '?') {
      hasOtherWildcard = true;
      expr.write('[^/]');
    } else if (nextChar == '[') {
      final characterRange = parseCharacterRange();
      if (characterRange == null) return null;
      hasOtherWildcard = true;
      expr.write('[$characterRange]');
    } else if (nextChar == r'\') {
      final escaped = peekChar();
      if (escaped == null) return null;
      // An escaped `/` is a separator that anchors nothing.
      hasOtherWildcard = hasOtherWildcard || escaped == _separator;
      literal.write(escaped);
      expr.write(RegExp.escape(escaped));
      current++;
    } else if (nextChar == '/') {
      // A leading or trailing slash does not appear in the expression.
      if (current - 1 != first && current != end) {
        literal.write('/');
        expr.write('/');
      }
      handleSlash();
    } else {
      literal.write(nextChar);
      expr.write(RegExp.escape(nextChar));
    }
  }
  final anchored = relativeToPath ? '^$expr' : '(?:^|/)$expr';
  final source = matchesDirectoriesOnly ? '$anchored/\$' : '$anchored/?\$';
  final text = literal.toString();
  final textMatch = hasOtherWildcard
      ? null
      : _textMatchOf(
          text,
          isAnchored: relativeToPath,
          starPositions: starPositions,
          leadsWithAnyFolders: leadsWithAnyFolders,
        );
  return textMatch == null
      ? _RegExpRule(
          source,
          negative: negative,
          matchesFoldersOnly: matchesDirectoriesOnly,
        )
      : _TextRule(
          source,
          textMatch,
          text,
          negative: negative,
          matchesFoldersOnly: matchesDirectoriesOnly,
        );
}

/// Returns how a pattern with [text] and single `*`s at [starPositions] in it
/// matches without a RegExp; null when only a RegExp can.
///
/// - [isAnchored]: a `/` other than a trailing one anchors the pattern.
/// - [leadsWithAnyFolders]: the pattern starts with `**/`.
_TextMatch? _textMatchOf(
  String text, {
  required bool isAnchored,
  required List<int> starPositions,
  required bool leadsWithAnyFolders,
}) {
  if (leadsWithAnyFolders) {
    return starPositions.isEmpty && text.isNotEmpty
        ? _TextMatch.pathSuffix
        : null;
  }
  if (starPositions.isEmpty) {
    if (text.isEmpty) return null;
    return isAnchored ? _TextMatch.pathLiteral : _TextMatch.baseLiteral;
  }
  if (isAnchored || starPositions.length > 1) return null;
  if (starPositions.single == 0) return _TextMatch.baseSuffix;
  return starPositions.single == text.length ? _TextMatch.basePrefix : null;
}
