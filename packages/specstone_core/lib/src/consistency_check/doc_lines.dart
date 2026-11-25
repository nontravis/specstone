import 'dart:convert';

import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// Reads [text], a file's decoded text with any line ends, the way a refresh
/// stores it.
///
/// The empty docPath resolves no link relative to a folder, so `links` are
/// those of a doc at the docs root.
DocLines docLinesOf(String text) => DocLines.from(
  parseIndexedDoc(
    docPath: '',
    bytes: utf8.encode(text),
    match: const NoDocType(),
    // An untyped doc has no approval hash, so neither rule applies.
    statusesOutside: false,
  ).content,
);
