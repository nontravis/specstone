import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/rendering/doc_html.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/html_page.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/page_setup.dart';

/// The html copy of a target and the warnings raised while building it.
final class HtmlBuild {
  const new({required this.html, required this.warnings});

  /// The self-contained page.
  final String html;

  /// One message per doc skipped or rendered off its template, in tree order,
  /// then one per doc whose body the markdown parser failed on and that shows
  /// as plain text, in tree order.
  final List<String> warnings;
}

/// Builds the html copy of the docs under [target].
///
/// Docs render as on disk, never reordered. A doc that cannot be read is
/// skipped with a warning; one that does not match its template renders and
/// warns. The page prints as [page] sets.
HtmlBuild buildHtml(
  DocsProject project,
  Target target, {
  PageSetup page = PageSetup.defaults,
}) {
  final readable = <(String, ReadableDoc)>[];
  final warnings = <String>[];
  final parseWarnings = <String>[];
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
  final docAnchors = _DocAnchorSets({
    for (final (docPath, read) in readable) docPath: read,
  });
  final rendered = <RenderedDoc>[];
  for (final (index, (docPath, read)) in readable.indexed) {
    final body = renderDocBody(
      read.doc,
      docPath: docPath,
      anchors: anchors,
      anchorsAt: docAnchors.of,
    );
    docAnchors.rendered(docPath, body.anchors);
    if (!body.bodyParsed) {
      parseWarnings.add(
        '${read.path}: the markdown parser failed; its body is shown as plain '
        'text',
      );
    }
    rendered.add(
      RenderedDoc(
        anchor: _anchorOf(index),
        tocEntry: shownTitle(read.doc) ?? docPath,
        bodyHtml: body.html,
      ),
    );
  }
  return HtmlBuild(
    html: renderPage(
      title: target.isDocsRoot ? 'docs' : target.docPath,
      docs: rendered,
      page: page,
    ),
    warnings: [...warnings, ...parseWarnings],
  );
}

String _anchorOf(int index) => 'doc-${index + 1}';

/// The anchor set of each doc of a build: a rendered doc's from its own
/// parse, and a doc a link reaches before it renders read on demand, once,
/// by the function `check` reads (R60).
final class _DocAnchorSets {
  new(this._docs);

  final Map<String, ReadableDoc> _docs;
  final _sets = <String, DocAnchors>{};

  /// The anchor set of the doc at [docPath]; null for a doc not in the build.
  DocAnchors? of(String docPath) {
    if (_sets[docPath] case final known?) return known;
    final read = _docs[docPath];
    if (read == null) return null;
    return _sets[docPath] =
        anchorsOfBody(read.doc.afterFrontmatter) ??
        const DocAnchors(headingSlugs: [], htmlIds: {});
  }

  /// Keeps [anchors], read by the render of the doc at [docPath].
  void rendered(String docPath, DocAnchors anchors) =>
      _sets.putIfAbsent(docPath, () => anchors);
}

bool _matchesTemplate(ReadableDoc read) =>
    isLaidOut(read.doc, toLf(read.text), read.docType);
