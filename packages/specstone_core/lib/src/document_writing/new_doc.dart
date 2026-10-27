import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// Creates a doc of [docTypeId] from its template at its next sibling number.
///
/// [parent] names a doc of the doc type's `parent:`, [slug] fills `{slug}`, and
/// a non-empty [text] is the doc's text, forced to `draft: true`; otherwise the
/// doc is the template's skeleton. The number is the highest sibling number on
/// disk plus one, read under the session lock; the path is claimed with an
/// exclusive create, so a doc that appears meanwhile is never overwritten. A
/// failed write removes the file and the folders this call created.
/// Throws [TemplateFault] `doc_type_unknown`, [IndexFault] `argument_missing`
/// or `argument_invalid` for a [parent] or [slug] the doc type needs or does
/// not take, [WriteFault] `doc_exists` when the doc is there, and [RenderFault]
/// `output_not_writable` when the disk refuses.
ReadAnswer answerNew(
  WriteSession session, {
  required String docTypeId,
  String? parent,
  String? slug,
  String text = '',
}) {
  final set = session.index.set;
  final docType =
      set.lookup(docTypeId) ??
      (throw TemplateFault(
        FaultCode.docTypeUnknown,
        'Could not find a doc type named "$docTypeId".',
      ));
  final shape =
      DocPathShape.of(docType, set) ??
      (throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '$docTypeId has no path to create a doc at',
      ));
  _checkArguments(docType, shape, parent: parent, slug: slug);

  final parentDoc = parent == null
      ? null
      : session.target('${docType.parent}:$parent');
  final parentValues = parentDoc == null
      ? const <String>[]
      : _valuesOfParent(session, docType, parentDoc);
  final title = slug ?? parentDoc?.name.split('/').last ?? docType.id;
  final lfText = text.isEmpty
      ? _skeleton(docType, title)
      : markDraft(toLf(text));
  final lineEnding = LineEnding.of(text);

  return session.locked(() {
    final docsRoot = session.project.docsRoot;
    final siblings = siblingsOnDisk(docsRoot, shape, parentValues);
    _checkNoClash(session, docType, shape, parentValues, siblings, slug);
    final highest = siblings.fold(0, (top, s) => max(top, s.number ?? 0));
    final created = <Directory>[];
    File? claimed;
    final String docPath;
    try {
      (docPath, claimed) = _claim(
        session,
        shape,
        docType,
        parentValues,
        slug,
        highest + 1,
        created,
      );
      session.writeDoc(docPath, lfText, lineEnding);
    } on Object {
      _remove(claimed, created);
      rethrow;
    }

    final written = parseIndexedDoc(
      docPath: docPath,
      bytes: utf8.encode(lineEnding.apply(lfText)),
      match: MatchedDocType(docType),
    );
    return ReadAnswer(
      text: '${namingLine(written.doc)}\n',
      json: {
        'name': written.doc.name,
        'docType': docType.id,
        'path': docPath,
        'bases': basesOf(written.content, docType),
      },
    );
  });
}

/// Throws the fault for a [parent] or [slug] that [docType] needs and lacks,
/// or takes no value for, or a [slug] that is no slug.
void _checkArguments(
  MergedDocType docType,
  DocPathShape shape, {
  required String? parent,
  required String? slug,
}) {
  final parentType = docType.parent;
  if (parentType != null && parent == null) {
    throw IndexFault(
      IndexFaultCode.argumentMissing,
      '${docType.id} needs --parent, the name of a $parentType',
    );
  }
  if (shape.slugged && slug == null) {
    throw IndexFault(
      IndexFaultCode.argumentMissing,
      '${docType.id} needs --slug, lowercase letters, digits, and _',
    );
  }
  if (parentType == null && parent != null) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '${docType.id} takes no --parent',
    );
  }
  if (!shape.slugged && slug != null) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '${docType.id} takes no --slug',
    );
  }
  if (slug != null) checkSlug(slug);
}

/// Returns the placeholder values of [parentDoc], the doc [docType] hangs
/// under.
List<String> _valuesOfParent(
  WriteSession session,
  MergedDocType docType,
  IndexedDoc parentDoc,
) {
  final set = session.index.set;
  final parentType = set.lookup(docType.parent ?? '');
  final parentShape = parentType == null
      ? null
      : DocPathShape.of(parentType, set);
  return parentShape?.valuesOf(parentDoc.docPath) ??
      (throw StateError('${parentDoc.docPath} does not match its doc type'));
}

/// Throws [WriteFault] `doc_exists` when a doc of [docType] already holds the
/// place the new doc would take.
///
/// A numbered doc clashes with a sibling that carries [slug]; any other
/// doc type clashes with the file at its one path. A folder with no doc of
/// [docType] in it is no clash.
void _checkNoClash(
  WriteSession session,
  MergedDocType docType,
  DocPathShape shape,
  List<String> parentValues,
  List<SiblingEntry> siblings,
  String? slug,
) {
  final candidates = shape.numbered
      ? [
          for (final sibling in siblings)
            if (sibling.slug != null && sibling.slug == slug)
              _docPathOfSibling(shape, parentValues, sibling),
        ]
      : [
          shape.build([...parentValues, ...shape.ownValues(slug: slug)]),
        ];
  for (final docPath in candidates) {
    if (!session.fileOf(docPath).existsSync()) continue;
    throw WriteFault(
      WriteFaultCode.docExists,
      'a ${docType.id} named ${docNameOf(docPath, docType)} exists',
      file: docPath,
    );
  }
}

String _docPathOfSibling(
  DocPathShape shape,
  List<String> parentValues,
  SiblingEntry sibling,
) => [
  '${shape.containerOf(parentValues)}${sibling.name}',
  ...shape.segments.skip(shape.ownIndex + 1),
].join('/');

/// Creates the folders and the empty file of the new doc, trying the next
/// number each time the file turns out to be there.
///
/// Returns the DocPath and the file; every folder made joins [created].
/// Throws [RenderFault] `output_not_writable` when the disk refuses, and
/// [WriteFault] `doc_exists` when a doc with no number to bump is there.
(String, File) _claim(
  WriteSession session,
  DocPathShape shape,
  MergedDocType docType,
  List<String> parentValues,
  String? slug,
  int firstNumber,
  List<Directory> created,
) {
  for (var number = firstNumber; ; number++) {
    final own = shape.ownValues(
      number: shape.numbered ? padNumber(number) : null,
      slug: slug,
    );
    final docPath = shape.build([...parentValues, ...own]);
    final file = session.fileOf(docPath);
    try {
      _createFolders(file.parent, created);
      file.createSync(exclusive: true);
      return (docPath, file);
    } on PathExistsException {
      if (!shape.numbered) {
        throw WriteFault(
          WriteFaultCode.docExists,
          'a ${docType.id} named ${docNameOf(docPath, docType)} exists',
          file: docPath,
        );
      }
    } on FileSystemException catch (error) {
      throw RenderFault(
        RenderFaultCode.outputNotWritable,
        'cannot write $docPath: ${error.osError?.message ?? error.message}',
      );
    }
  }
}

/// Creates [folder] and each missing folder above it, recording each in
/// [created].
void _createFolders(Directory folder, List<Directory> created) {
  final missing = <Directory>[];
  for (var dir = folder; !dir.existsSync(); dir = dir.parent) {
    missing.add(dir);
  }
  for (final dir in missing.reversed) {
    dir.createSync();
    created.add(dir);
  }
}

/// Deletes [file] and then each of [created], innermost first.
///
/// A folder that is not empty or already gone stays: the fault that brought
/// the cleanup is the one to report.
void _remove(File? file, List<Directory> created) {
  for (final entity in <FileSystemEntity?>[file, ...created.reversed]) {
    try {
      entity?.deleteSync();
    } on FileSystemException {
      continue;
    }
  }
}

/// Returns the template skeleton of [docType]: a draft frontmatter with each
/// required field empty, the [title], and each required section.
String _skeleton(MergedDocType docType, String title) {
  final buffer = StringBuffer('---\ndraft: true\n');
  for (final field in docType.fields) {
    if (field.required) buffer.write('${field.id}:\n');
  }
  buffer.write('---\n\n# $title\n');
  for (final section in docType.sections) {
    if (!section.required) continue;
    buffer.write('\n## ${section.header}\n');
    final template = section.template;
    if (template != null && template.isNotEmpty) buffer.write('$template\n');
  }
  return buffer.toString();
}
