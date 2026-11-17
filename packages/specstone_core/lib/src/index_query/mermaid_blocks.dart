import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart'
    show lfLinesOf, linesBeforeBodyOf;

/// A `mermaid` block as the line facts keep it: its opening fence's 1-based
/// file line and the [hash] of its text.
final class MermaidBlock {
  const new({required this.fenceLine, required this.hash});

  /// The 1-based file line of the opening fence.
  final int fenceLine;

  /// The full `sha256` hex of the block's text.
  final String hash;
}

/// A `mermaid` block with its text, as a doc holds it.
final class MermaidSource {
  const new({required this.fenceLine, required this.text});

  /// The 1-based file line of the opening fence.
  final int fenceLine;

  /// The block's lines past their containers' marks, joined with `\n`.
  final String text;

  /// The full `sha256` hex of [text], the key a stored parse result uses.
  ///
  /// A hash collision would hide a broken diagram, so it is not shortened.
  String get hash => sha256.convert(utf8.encode(text)).toString();

  /// The block the line facts store for this source.
  MermaidBlock get block => MermaidBlock(fenceLine: fenceLine, hash: hash);
}

/// Returns the `mermaid` blocks of [doc], whose LF text is [lfText], in file
/// order.
///
/// A block is a fence, backtick or tilde, whose info string starts with the
/// word `mermaid`. An unclosed fence runs to the end of the doc.
List<MermaidSource> mermaidSourcesOf(Doc doc, String lfText) {
  final body = doc.afterFrontmatter;
  if (!body.contains(mermaidInfoWord)) return const [];
  final scan = fenceScan(lfLinesOf(body));
  final bodyStart = linesBeforeBodyOf(doc, lfText);
  final sources = <MermaidSource>[];
  int? fenceLine;
  final lines = <String>[];
  void finish() {
    if (fenceLine == null) return;
    sources.add(MermaidSource(fenceLine: fenceLine!, text: lines.join('\n')));
    fenceLine = null;
    lines.clear();
  }

  for (var i = 0; i < scan.fenced.length; i++) {
    final info = scan.opens[i];
    if (info != null) {
      finish();
      if (info == mermaidInfoWord) fenceLine = bodyStart + i + 1;
    } else if (!scan.fenced[i] || scan.closes[i]) {
      finish();
    } else if (fenceLine != null) {
      lines.add(scan.contents[i]);
    }
  }
  finish();
  return sources;
}
