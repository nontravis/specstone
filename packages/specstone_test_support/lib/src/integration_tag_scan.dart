import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

/// The test tag that marks a file whose tests spawn processes.
const integrationTag = 'integration';

/// The guard test file, which the scan skips.
const integrationGuardFileName = 'integration_tag_guard_test.dart';

const _spawnMembers = {'run', 'runSync', 'start'};

/// Returns the 1-based line of the first process spawn call, else null.
int? spawnLineOf(String source) => _factsOf(source).spawnLine;

/// Returns the names in the first directive's `@Tags` list, else empty.
List<String> tagsOf(String source) => _factsOf(source).tags;

/// Returns every import, export, conditional, and part URI, never part-of.
List<String> directivesOf(String source) => _factsOf(source).directives;

/// What one parse of a Dart source yields for the scan.
final class _Facts {
  const new(this.spawnLine, this.tags, this.directives);

  final int? spawnLine;
  final List<String> tags;
  final List<String> directives;
}

_Facts _factsOf(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final directives = result.unit.directives;
  return _Facts(
    _spawnLineIn(result.unit.beginToken, result.lineInfo),
    _tagsIn(directives),
    [for (final directive in directives) ..._urisOf(directive)],
  );
}

int? _spawnLineIn(Token first, LineInfo lineInfo) {
  for (
    Token? token = first;
    token != null && !token.isEof;
    token = token.next
  ) {
    if (token.lexeme != 'Process') continue;
    final dot = token.next;
    final member = dot?.next;
    if (dot?.lexeme == '.' && _spawnMembers.contains(member?.lexeme)) {
      return lineInfo.getLocation(token.offset).lineNumber;
    }
  }
  return null;
}

List<String> _tagsIn(List<Directive> directives) {
  if (directives.isEmpty) return const [];
  final prefixes = {
    for (final directive in directives)
      if (directive is ImportDirective && directive.prefix != null)
        directive.prefix!.name,
  };
  return [
    for (final annotation in directives.first.metadata)
      if (_isTags(annotation, prefixes))
        ..._stringsOf(annotation.arguments?.arguments.firstOrNull),
  ];
}

bool _isTags(Annotation annotation, Set<String> prefixes) =>
    switch (annotation.name) {
      SimpleIdentifier(:final name) => name == 'Tags',
      PrefixedIdentifier(:final prefix, :final identifier) =>
        identifier.name == 'Tags' && prefixes.contains(prefix.name),
    } &&
    annotation.constructorName == null;

List<String> _stringsOf(Argument? list) => [
  if (list is ListLiteral)
    for (final element in list.elements)
      if (element is StringLiteral && element.stringValue != null)
        element.stringValue!,
];

List<String> _urisOf(Directive directive) => [
  for (final literal in switch (directive) {
    NamespaceDirective(:final uri, :final configurations) => [
      uri,
      for (final configuration in configurations) configuration.uri,
    ],
    PartDirective(:final uri) => [uri],
    _ => const <StringLiteral?>[],
  })
    if (literal?.stringValue != null) literal!.stringValue!,
];

/// The test files of one package that break the integration tag rule.
final class IntegrationTagReport {
  /// Creates a report.
  const new({
    required this.untaggedSpawning,
    required this.taggedPure,
    required this.staleAllowlist,
  });

  /// Files that spawn, in their source or a followed import, with no tag.
  final List<String> untaggedSpawning;

  /// Files tagged integration that spawn nowhere and are not allowlisted.
  final List<String> taggedPure;

  /// Allowlist entries whose file is missing or untagged.
  final List<String> staleAllowlist;
}

/// Scans `<packagesRoot>/<package>/test/` for tag and spawn mismatches.
///
/// `package:<name>/` imports of a [libraryPackages] name resolve to its `lib/`.
IntegrationTagReport scanIntegrationTags({
  required Directory packagesRoot,
  required String package,
  required List<String> followedPackages,
  required List<String> libraryPackages,
  required Map<String, String> allowlist,
}) {
  final scan = _Scan(
    packagesRoot.absolute.uri,
    followedPackages,
    libraryPackages,
  );
  final packageUri = scan.root.resolve('$package/');
  final tests = scan.testFilesOf(packageUri);

  final untaggedSpawning = <String>[];
  final taggedPure = <String>[];
  for (final MapEntry(:key, :value) in tests.entries) {
    final tagged = scan.facts(value).tags.contains(integrationTag);
    final chain = scan.spawnChain(value, {value.path});
    if (chain != null && !tagged) {
      untaggedSpawning.add('$key: ${chain.join(' -> ')}');
    } else if (chain == null && tagged && !allowlist.containsKey(key)) {
      taggedPure.add(
        '$key: tagged $integrationTag, no spawn in its source or test/ imports',
      );
    }
  }

  final staleAllowlist = <String>[];
  for (final key in allowlist.keys) {
    final file = tests[key];
    if (file == null) {
      staleAllowlist.add('$key: listed but missing');
    } else if (!scan.facts(file).tags.contains(integrationTag)) {
      staleAllowlist.add('$key: listed but untagged');
    }
  }

  return IntegrationTagReport(
    untaggedSpawning: untaggedSpawning..sort(),
    taggedPure: taggedPure..sort(),
    staleAllowlist: staleAllowlist..sort(),
  );
}

final class _Scan {
  new(this.root, List<String> followedPackages, this._libraryPackages)
    : _followedPrefixes = [
        for (final name in followedPackages) root.resolve('$name/test/').path,
        for (final name in _libraryPackages) root.resolve('$name/lib/').path,
      ];

  final Uri root;
  final List<String> _libraryPackages;
  final List<String> _followedPrefixes;
  final _facts = <String, _Facts>{};

  _Facts facts(Uri file) =>
      _facts[file.path] ??= _factsOf(File.fromUri(file).readAsStringSync());

  /// Resolves [directive] against [file]; a `package:` URI maps to its `lib/`.
  Uri? _resolve(Uri file, String directive) {
    final uri = Uri.parse(directive);
    if (uri.scheme.isEmpty) return file.resolve(directive);
    if (uri.scheme != 'package' || uri.pathSegments.isEmpty) return null;
    final name = uri.pathSegments.first;
    if (!_libraryPackages.contains(name)) return null;
    return root.resolve(
      '$name/lib/${uri.pathSegments.skip(1).map(Uri.encodeComponent).join('/')}',
    );
  }

  String _relative(Uri file) =>
      Uri.decodeFull(file.path.substring(root.path.length));

  /// Maps each package-relative test path to its file, guard file excluded.
  Map<String, Uri> testFilesOf(Uri packageUri) {
    final testDir = Directory.fromUri(packageUri.resolve('test/'));
    if (!testDir.existsSync()) return {};
    final files = [
      for (final entity in testDir.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('_test.dart')) entity.uri,
    ]..sort((a, b) => a.path.compareTo(b.path));
    return {
      for (final file in files)
        Uri.decodeFull(file.path.substring(packageUri.path.length)): file,
    }..remove('test/$integrationGuardFileName');
  }

  /// Returns the chain from [file] to the first spawning file, else null.
  List<String>? spawnChain(Uri file, Set<String> visited) {
    final facts = this.facts(file);
    final line = facts.spawnLine;
    if (line != null) return ['${_relative(file)}:$line'];
    for (final directive in facts.directives) {
      final target = _resolve(file, directive);
      if (target == null || !_isFollowed(target)) continue;
      if (!visited.add(target.path)) continue;
      final rest = spawnChain(target, visited);
      if (rest != null) return [_relative(file), ...rest];
    }
    return null;
  }

  bool _isFollowed(Uri target) =>
      _followedPrefixes.any(target.path.startsWith) &&
      File.fromUri(target).existsSync();
}
