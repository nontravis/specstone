import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart'
    show
        BlockParser,
        Delimiter,
        Document,
        Element,
        ExtensionSet,
        InlineParser,
        Line,
        LinkSyntax,
        Node,
        SimpleDelimiter;
import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show RelativeLink, readLinkTarget;
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show relativeHref;
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show startsWithUtf8Bom, utf8Bom;
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show sectionIndexOf;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

/// The id of the doc type whose docs name a skill's reference files.
const skillDocTypeId = 'skill';

/// The id of the field that holds a skill doc's output folder.
const skillOutputFieldId = 'output';

const _sourcesSectionId = 'sources';
const _referencesFolder = 'references';
const _frontmatterOpenLine = '---\n';
final _rootedOutput = RegExp(r'^(?:[/\\]|[A-Za-z]:)');
final _angleInlineOpen = RegExp(r'\]\(\s*<');

// MARK: - Link actions

/// What a reference file makes of one doc link of its Sources doc.
sealed class LinkAction {
  const new();
}

/// Keeps the link as written.
final class KeepLink extends LinkAction {
  const new();
}

/// Sets the link's path, its `?` and `#` part kept as written.
final class RetargetLink extends LinkAction {
  const new(this.path);

  /// The new path, percent-encoded as an href writes it.
  final String path;
}

/// Writes the link as its text followed by [path] in a code span, the
/// markdown form of `build`'s outside-link span.
final class LinkAsText extends LinkAction {
  const new(this.path);

  /// The path shown, decoded.
  final String path;
}

/// Returns [lfText], a doc's LF text, with each link after its frontmatter
/// rewritten as [actionOf] gives for the link's href.
typedef LinkRewriter = String Function(
  String lfText,
  LinkAction Function(String href) actionOf,
);

// MARK: - Plan

/// Why `format` refuses a skill doc; the run goes on with the other docs.
enum SkillRefusalCode {
  skillSourceMissing('skill_source_missing'),
  skillSourceNotExported('skill_source_not_exported'),
  skillOutputNotAllowed('skill_output_not_allowed');

  new(this.wire);

  /// The snake_case code printed in the result line and in `--json`.
  final String wire;
}

/// One reference file a skill doc's plan writes.
final class ReferenceFile {
  const new({
    required this.path,
    required this.file,
    required this.text,
    required this.lineEnding,
    required this.hasBom,
  });

  /// The path from the project root, `/`-separated.
  final String path;

  /// The file to write.
  final File file;

  /// The file's text with LF line endings.
  final String text;

  /// The line-break style of the Sources doc, which the file takes.
  final LineEnding lineEnding;

  /// Whether the Sources doc starts with a UTF-8 byte order mark.
  final bool hasBom;

  /// Returns the bytes to write: [text] in [lineEnding], after the byte order
  /// mark when [hasBom].
  List<int> get bytes => [
    if (hasBom) ...utf8Bom,
    ...utf8.encode(lineEnding.apply(text)),
  ];
}

/// What one format run does for one skill doc under its Target.
sealed class SkillPlan {
  const new(this.path);

  /// The skill doc's path from the project root, as its result line prints it.
  final String path;
}

/// A skill doc whose reference files the run writes.
final class ExportedSkill extends SkillPlan {
  const new(super.path, this.files, this._referencesFolder, this._prefix);

  /// One file per Sources doc, in code point order of path.
  final List<ReferenceFile> files;

  final Directory _referencesFolder;

  /// The path of [_referencesFolder] from the project root, ending in `/`.
  final String _prefix;

  /// The references folder's path from the project root, ending in `/`.
  String get referencesPath => _prefix;

  /// Returns the path, from the project root, of each regular file under the
  /// references folder that no planned file names, in code point order.
  ///
  /// A symbolic link is not followed and not listed.
  ///
  /// Throws a [FileSystemException] when the folder or one under it cannot
  /// be listed; no partial list is returned.
  List<String> get leftoverPaths {
    if (!_referencesFolder.existsSync()) return const [];
    final planned = {for (final file in files) file.path};
    final found = <String>[];
    for (final entity in _referencesFolder.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relative = entity.path
          .substring(_referencesFolder.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      final path = '$_prefix$relative';
      if (!planned.contains(path)) found.add(path);
    }
    return found..sort(compareCodePoints);
  }
}

/// A skill doc the run refuses, writing none of its files.
final class RefusedSkill extends SkillPlan {
  const new(super.path, this.code, this.message);

  /// The cause's code.
  final SkillRefusalCode code;

  /// Plain text naming the case.
  final String message;
}

/// The reference files and refusals of the skill docs under one Target.
final class SkillReferences {
  new _(this.skills);

  /// Plans each `skill` doc under [target] with an `output:` string.
  ///
  /// Every refusal cause is judged before any file is planned. The overlap
  /// cause compares the output folders of every skill doc under the docs
  /// root, by canonical path. Each reference file holds its Sources doc as
  /// it reads on disk now, less each field whose `export` is false, its links
  /// rewritten by [rewriteLinks].
  factory plan(
    DocsProject project,
    Target target, {
    required LinkRewriter rewriteLinks,
  }) {
    final inTarget = _skillDocsUnder(project, target);
    if (inTarget.isEmpty) return SkillReferences._(const []);
    final everySkill = target.isDocsRoot
        ? inTarget
        : _skillDocsUnder(project, Target(project.docsRoot, ''));
    final planner = _Planner(project, everySkill, rewriteLinks);
    return SkillReferences._([
      for (final skill in inTarget) ?planner.planOf(skill),
    ]);
  }

  /// The plans in tree order.
  final List<SkillPlan> skills;

  /// Returns the plan of the skill doc at [path], or null when it has none.
  SkillPlan? of(String path) =>
      skills.where((skill) => skill.path == path).firstOrNull;
}

// MARK: - Planning

/// A `skill` doc read for its `output:` and its Sources links.
final class _SkillDoc {
  new({
    required this.path,
    required this.docPath,
    required this.docType,
    required this.doc,
  });

  final String path;
  final String docPath;
  final MergedDocType docType;
  final Doc doc;

  /// The `output:` value, or null when it is no string.
  late final String? output = _stringField(doc, skillOutputFieldId);
}

/// A doc a Sources link names, read as on disk.
final class _Source {
  new({required this.docPath, required this.docType, required this.text});

  final String docPath;
  final MergedDocType docType;
  final _DiskText text;

  /// The path from the project root that a refusal message names.
  String get path => projectPathOfDocPath(docPath);
}

/// A file's text with LF line endings, its line-break style, and its BOM.
final class _DiskText {
  new(this.lfText, this.lineEnding, {required this.hasBom});

  final String lfText;
  final LineEnding lineEnding;
  final bool hasBom;
}

/// Plans the skill docs of one run against every skill doc of the project.
final class _Planner {
  new(this.project, this.everySkill, this.rewriteLinks);

  final DocsProject project;
  final List<_SkillDoc> everySkill;
  final LinkRewriter rewriteLinks;

  late final Map<String, String?> _canonicalOutputs = {
    for (final skill in everySkill) skill.docPath: _canonicalOutputOf(skill),
  };

  SkillPlan? planOf(_SkillDoc skill) {
    final output = skill.output;
    if (output == null) return null;
    RefusedSkill refused(SkillRefusalCode code, String message) =>
        RefusedSkill(skill.path, code, message);
    final segments = _segmentsOf(output);
    if (segments == null) {
      return refused(
        SkillRefusalCode.skillOutputNotAllowed,
        'the output folder is outside the project root',
      );
    }
    final folderRefusal = _folderRefusal(skill, segments);
    if (folderRefusal != null) {
      return refused(SkillRefusalCode.skillOutputNotAllowed, folderRefusal);
    }
    final sources = <String, _Source>{};
    for (final link in _sourceLinksOf(skill)) {
      final source = _sourceOf(link.href, skill.docPath);
      if (source == null) {
        return refused(
          SkillRefusalCode.skillSourceMissing,
          'the source names no doc: ${link.written}',
        );
      }
      sources.putIfAbsent(source.docPath, () => source);
    }
    for (final source in sources.values) {
      if (_exportRefusal(source) case final message?) {
        return refused(SkillRefusalCode.skillSourceNotExported, message);
      }
    }
    final placed = {
      for (final docPath in sources.keys)
        docPath: [...segments, _referencesFolder, ...docPath.split('/')],
    };
    for (final relative in placed.values) {
      if (_firstLink(relative) case final link?) {
        return refused(
          SkillRefusalCode.skillOutputNotAllowed,
          _crossesLink(link),
        );
      }
    }
    final files = [
      for (final source in sources.values)
        _referenceFile(placed[source.docPath]!, source, sources.keys.toSet()),
    ]..sort((a, b) => compareCodePoints(a.path, b.path));
    return ExportedSkill(
      skill.path,
      files,
      Directory(_joined([...segments, _referencesFolder])),
      _referencesPrefixOf(segments),
    );
  }

  /// Returns the message of the folder cause [segments] meets, or null.
  String? _folderRefusal(_SkillDoc skill, List<String> segments) {
    if (_firstLink([...segments, _referencesFolder]) case final link?) {
      return _crossesLink(link);
    }
    final folder = canonicalPath(_joined(segments));
    final docsRoot = project.docsRoot.path;
    if (folder == docsRoot || pathInside(docsRoot, folder) != null) {
      return 'the output folder is inside the docs root';
    }
    if (isInsideRecordsRoot(folder, projectRoot: project.projectRoot)) {
      return 'the output folder is inside the records root';
    }
    for (final other in everySkill) {
      if (other.docPath == skill.docPath) continue;
      final otherFolder = _canonicalOutputs[other.docPath];
      if (otherFolder != null && _overlaps(folder, otherFolder)) {
        return 'the output folder overlaps ${other.path}';
      }
    }
    return null;
  }

  String? _canonicalOutputOf(_SkillDoc skill) {
    final output = skill.output;
    final segments = output == null ? null : _segmentsOf(output);
    return segments == null ? null : canonicalPath(_joined(segments));
  }

  /// Returns the first of the folders and file [relative] walks down to that
  /// is a symbolic link, `/`-separated from the project root, or null.
  String? _firstLink(List<String> relative) {
    for (var count = 1; count <= relative.length; count++) {
      final walked = relative.take(count).toList();
      if (FileSystemEntity.isLinkSync(_joined(walked))) return walked.join('/');
    }
    return null;
  }

  String _joined(List<String> relative) =>
      [project.projectRoot.path, ...relative].join(Platform.pathSeparator);

  /// Returns the doc [href], written in the doc at [skillDocPath], names, or
  /// null when it names no file one doc type matches and that reads as UTF-8.
  _Source? _sourceOf(String href, String skillDocPath) {
    if (resolveDocLink(href, skillDocPath) case DocTarget(:final docPath)) {
      if (project.matcher.match(docPath) case MatchedDocType(:final docType)) {
        final file = fileOfDocPath(
          docPath,
          docsRoot: project.docsRoot,
          projectRoot: project.projectRoot,
        );
        final text = _diskTextOf(file);
        if (text == null) return null;
        return _Source(docPath: docPath, docType: docType, text: text);
      }
    }
    return null;
  }

  ReferenceFile _referenceFile(
    List<String> relative,
    _Source source,
    Set<String> sourceDocPaths,
  ) {
    final exported = _withoutUnexportedFields(
      source.text.lfText,
      source.docType,
    );
    return ReferenceFile(
      path: relative.join('/'),
      file: File(_joined(relative)),
      text: rewriteLinks(
        exported,
        (href) => _actionOf(href, source.docPath, sourceDocPaths),
      ),
      lineEnding: source.text.lineEnding,
      hasBom: source.text.hasBom,
    );
  }
}

// MARK: - Reading

List<_SkillDoc> _skillDocsUnder(DocsProject project, Target target) => [
  for (final entry in collectDocEntries(target, project.matcher))
    if (entry case DocFile(:final file, :final docPath))
      if (project.matcher.match(docPath) case MatchedDocType(:final docType)
          when docType.id == skillDocTypeId)
        ?_skillDocOf(project, file, docPath, docType),
];

_SkillDoc? _skillDocOf(
  DocsProject project,
  File file,
  String docPath,
  MergedDocType docType,
) {
  final text = _diskTextOf(file);
  if (text == null) return null;
  return _SkillDoc(
    path: project.displayPath(file),
    docPath: docPath,
    docType: docType,
    doc: Doc.parse(text.lfText),
  );
}

_DiskText? _diskTextOf(File file) {
  try {
    final bytes = file.readAsBytesSync();
    final text = utf8.decode(bytes);
    return _DiskText(
      toLf(text),
      LineEnding.of(text),
      hasBom: startsWithUtf8Bom(bytes),
    );
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

String? _stringField(Doc doc, String fieldId) {
  final block = doc.frontmatter?.where((b) => b.name == fieldId).firstOrNull;
  if (block == null) return null;
  try {
    final value = loadYaml(block.valueText);
    return value is String ? value : null;
  } on YamlException {
    return null;
  }
}

/// Returns the folder segments [output] walks down from the project root,
/// `.` and `..` applied, or null when it is rooted or leaves the root.
///
/// A leading `/` or `\`, or a drive such as `C:`, counts as rooted on every
/// OS, so one config reads the same on each.
List<String>? _segmentsOf(String output) {
  if (_rootedOutput.hasMatch(output)) return null;
  final separators = Platform.isWindows ? RegExp(r'[/\\]') : RegExp('/');
  final segments = <String>[];
  for (final segment in output.split(separators)) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (segments.isEmpty) return null;
        segments.removeLast();
      default:
        segments.add(segment);
    }
  }
  return segments;
}

/// Returns the `<output>/references/` prefix of a skill doc's [output], from
/// the project root and ending in `/`, or null when the writer refuses the
/// path as outside the project root.
String? skillReferencesPrefixOf(String output) {
  final segments = _segmentsOf(output);
  if (segments == null) return null;
  return _referencesPrefixOf(segments);
}

String _referencesPrefixOf(List<String> segments) =>
    '${[...segments, _referencesFolder].join('/')}/';

bool _overlaps(String folder, String other) =>
    folder == other ||
    pathInside(folder, other) != null ||
    pathInside(other, folder) != null;

String _crossesLink(String path) =>
    'the output path crosses a symbolic link: $path';

/// Returns each link of the skill doc's Sources section, in order; a
/// footnote's own links are left out.
///
/// A reference link may use a definition written anywhere in the doc: the
/// block pass reads them all before the section is parsed. A doc `markdown`
/// fails on yields no link.
List<_SourceLink> _sourceLinksOf(_SkillDoc skill) {
  final index = sectionIndexOf(skill.doc, skill.docType, _sourcesSectionId);
  if (index == null) return const [];
  final syntax = _WrittenLinkSyntax();
  final List<Node> nodes;
  try {
    final document = Document(
      extensionSet: ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [syntax],
    );
    BlockParser(
      LineSplitter.split(skill.doc.afterFrontmatter).map(Line.new).toList(),
      document,
    ).parseLines();
    nodes = document.parse(skill.doc.sections[index].body);
  } on Object {
    // `markdown` has no failure contract, so every thrown object counts.
    return const [];
  }
  final links = <_SourceLink>[];
  void visit(List<Node> nodes) {
    for (final node in nodes) {
      if (node is! Element || _isFootnoteMade(node)) continue;
      final href = node.attributes['href'];
      final written = syntax.written[node];
      if (node.tag == 'a' && href != null && written != null) {
        links.add(_SourceLink(href: href, written: written));
      }
      if (node.children case final children?) visit(children);
    }
  }

  visit(nodes);
  return links;
}

/// One Sources link: the href `markdown` gives it, and its destination as
/// the Owner wrote it, angle brackets left out.
final class _SourceLink {
  new({required this.href, required this.written});

  final String href;
  final String written;
}

/// The link syntax `markdown` runs, keeping each link's destination as
/// written before `markdown` escapes and percent-encodes it into the href.
///
/// `markdown` writes each space of an inline `<...>` destination as `%20`
/// before the node is made, so such a destination turns it back.
final class _WrittenLinkSyntax extends LinkSyntax {
  final written = Map<Element, String>.identity();
  bool _isAngleInline = false;

  @override
  Iterable<Node>? close(
    InlineParser parser,
    covariant SimpleDelimiter opener,
    Delimiter? closer, {
    String? tag,
    required List<Node> Function() getChildren,
  }) {
    _isAngleInline =
        _angleInlineOpen.matchAsPrefix(parser.source, parser.pos) != null;
    return super.close(
      parser,
      opener,
      closer,
      tag: tag,
      getChildren: getChildren,
    );
  }

  @override
  Node createNode(
    String destination,
    String? title, {
    required List<Node> Function() getChildren,
  }) {
    final node = super.createNode(destination, title, getChildren: getChildren);
    if (node is Element) {
      written[node] = _isAngleInline
          ? destination.replaceAll('%20', ' ')
          : destination;
    }
    return node;
  }
}

bool _isFootnoteMade(Element element) => switch (element.attributes['class']) {
  'footnote-ref' || 'footnote-backref' => true,
  _ => false,
};

/// Returns the message of the export cause [source] meets, or null.
String? _exportRefusal(_Source source) {
  if (isRecordsDocPath(source.docPath)) {
    return 'the source sits outside the docs root: ${source.path}';
  }
  if (!source.docType.exported) {
    return "the source's doc type is not exported: ${source.path}";
  }
  return null;
}

/// Returns [lfText], a doc of [docType], less each frontmatter key block of
/// a field whose `export` is false.
String _withoutUnexportedFields(String lfText, MergedDocType docType) {
  final hidden = {
    for (final field in docType.fields)
      if (!field.exported) field.id,
  };
  if (hidden.isEmpty) return lfText;
  final doc = Doc.parse(lfText);
  final blocks = doc.frontmatter;
  if (blocks == null || !blocks.any((block) => hidden.contains(block.name))) {
    return lfText;
  }
  final blocksEnd = blocks.fold(
    _frontmatterOpenLine.length,
    (end, block) => end + block.text.length,
  );
  final frontmatterEnd = lfText.length - doc.afterFrontmatter.length;
  return [
    _frontmatterOpenLine,
    for (final block in blocks)
      if (!hidden.contains(block.name)) block.text,
    lfText.substring(blocksEnd, frontmatterEnd),
    doc.afterFrontmatter,
  ].join();
}

/// Returns what the reference file of the Sources doc at [docPath] makes of
/// a link to [href]; [sourceDocPaths] are the docs of the same skill.
LinkAction _actionOf(String href, String docPath, Set<String> sourceDocPaths) {
  final isPathLink = switch (readLinkTarget(href)) {
    RelativeLink(:final segments) => segments.isNotEmpty,
    _ => false,
  };
  if (!isPathLink) return const KeepLink();
  return switch (resolveDocLink(href, docPath)) {
    DocTarget(docPath: final target) when sourceDocPaths.contains(target) =>
      RetargetLink(_hrefOf(relativeHref(docPath, target))),
    DocTarget(docPath: final target) => LinkAsText(target),
    OutsideTarget(:final shown) => LinkAsText(shown),
    WebTarget() => const KeepLink(),
  };
}

String _hrefOf(String path) =>
    path.split('/').map(Uri.encodeComponent).join('/');
