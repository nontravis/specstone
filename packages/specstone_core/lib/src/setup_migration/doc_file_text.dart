import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart'
    show textHashOf;
import 'package:specstone_core/src/document_writing/write_session.dart'
    show cannotRead;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/models/doc_text.dart';

/// Reads a doc's bytes into [DocText] and writes text back in the doc's own
/// line style.
abstract final class DocFileText {
  /// Reads UTF-8 [bytes] into LF text, the byte order mark dropped from it.
  static DocText read(List<int> bytes) {
    final text = utf8.decode(bytes);
    return DocText(
      lf: toLf(text),
      ending: LineEnding.of(text),
      bom: startsWithUtf8Bom(bytes),
      hash: textHashOf(text),
    );
  }

  /// Reads the doc [file] at [docPath] into LF text, or returns null when its
  /// bytes are not UTF-8 text.
  ///
  /// A run moves a doc it gets null for untouched and rewrites none of it, as
  /// it does a file that is not `.md`.
  ///
  /// Throws [RenderFault] `output_not_writable` naming [docPath] when the file
  /// cannot be read.
  static DocText? readFile(File file, {required String docPath}) {
    final List<int> bytes;
    try {
      bytes = readPlanInput(file);
    } on FileSystemException catch (error) {
      throw cannotRead(docPath, error);
    }
    try {
      return read(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Returns [lf] in the line style of [original], the byte order mark first
  /// when [original] had one.
  static String written(DocText original, String lf) =>
      '${original.bom ? '﻿' : ''}${original.ending.apply(lf)}';
}
