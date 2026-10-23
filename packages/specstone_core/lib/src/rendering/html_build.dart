import 'package:specstone_core/src/rendering/doc_html.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/html_page.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// The html copy of a target and the warnings raised while building it.
final class HtmlBuild {
  const new({required this.html, required this.warnings});

  /// The self-contained page.
  final String html;

  /// One message per doc skipped or rendered off its template, in tree order.
  final List<String> warnings;
}

/// Builds the html copy of the docs under [target].
///
/// Docs render as on disk, never reordered. A doc that cannot be read is
/// skipped with a warning; one that does not match its template renders and
/// warns.
HtmlBuild buildHtml(DocsProject project, Target target) {
  final readable = <(String, ReadableDoc)>[];
  final warnings = <String>[];
  for (final entry in collectDocEntries(target, project.matcher)) {
    switch (readDoc(project, entry)) {
      case UnmatchedDoc(:final warning):
        warnings.add(warning);
      case AmbiguousDoc(:final warning):
        warnings.add(warning);
      case NotUtf8Doc(:final warning):
        warnings.add(warning);
      case UnreadableDoc(:final warning):
        warnings.add(warning);
      case final ReadableDoc read:
        if (!_matchesTemplate(read)) {
          warnings.add(
            '${read.path} does not match its template; run specstone format',
          );
        }
        readable.add((entry.docPath, read));
    }
  }
  final anchors = {
    for (final (index, (docPath, _)) in readable.indexed)
      docPath: _anchorOf(index),
  };
  final rendered = [
    for (final (index, (docPath, read)) in readable.indexed)
      RenderedDoc(
        anchor: _anchorOf(index),
        tocEntry: shownTitle(read.doc) ?? docPath,
        bodyHtml: renderDocBody(read.doc, docPath: docPath, anchors: anchors),
      ),
  ];
  return HtmlBuild(
    html: renderPage(
      title: target.isDocsRoot ? 'docs' : target.docPath,
      docs: rendered,
    ),
    warnings: warnings,
  );
}

String _anchorOf(int index) => 'doc-${index + 1}';

bool _matchesTemplate(ReadableDoc read) =>
    switch (formatDoc(read.doc, read.docType)) {
      Formatted(:final text) => text == toLf(read.text),
      Refused() => false,
    };
