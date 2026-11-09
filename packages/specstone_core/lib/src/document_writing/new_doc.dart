import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// Refuses [lfText] whose frontmatter holds an `approved` key of any value.
///
/// Only `specstone approve` and the hash stamps write the mark, so `new`
/// never takes it from stdin.
void _refuseApprovedMark(String lfText) {
  final marked =
      Doc.parse(lfText).frontmatter?.any((b) => b.name == 'approved') ?? false;
  if (!marked) return;
  throw WriteFault(
    WriteFaultCode.fieldNotWritable,
    approvedNotWritableMessage,
    key: 'approved',
  );
}

/// Adds what a new doc's type derives from the project, such as first
/// `confirmed` entries, to [lfText] and returns the result.
typedef NewDocFill = String Function(
  String lfText,
  MergedDocType docType,
  DocIndex index,
);

/// Creates a doc of [docTypeId] from its template at its next sibling number.
///
/// [parent] names a doc of the doc type's `parent:`, or of the nesting type
/// below `max_depth`; [slug] fills `{slug}`; a non-empty [text] is the doc,
/// forced to `draft: true`. Under the session lock, [generators] and
/// [firstConfirmations] fill it, then an exclusive create writes it.
/// Throws [TemplateFault] `doc_type_unknown` for [docTypeId] or a [parent]
/// that names another doc type id, [IndexFault] `argument_missing`
/// or `argument_invalid` for a [parent] or [slug] the doc type needs or does
/// not take, or a [parent] already at `max_depth`, [WriteFault] `doc_exists`
/// when the doc is there and `field_not_writable` when [text] holds an
/// `approved` key, and [RenderFault] `output_not_writable` when the disk
/// refuses, after removing what this call created.
ReadAnswer answerNew(
  WriteSession session, {
  required String docTypeId,
  String? parent,
  String? slug,
  String text = '',
  GeneratorRegistry<DocIndex>? generators,
  NewDocFill? firstConfirmations,
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
  final parentTypeId = _parentTypeIdOf(docType, set);
  _checkArguments(docType, shape, parentTypeId, parent: parent, slug: slug);

  final parentDoc = parent == null
      ? null
      : session.parentTarget(parent, parentTypeId!);
  final (parentShape, parentValues) = parentDoc == null
      ? (null, const <String>[])
      : _shapeOfParent(set, parentTypeId!, parentDoc);
  final depth = _depthOf(docType, set, parentDoc, parentShape);
  final placed =
      DocPathShape.of(docType, set, depth: depth) ??
      (throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '$docTypeId has no path to create a doc at depth $depth',
      ));
  final title = slug ?? parentDoc?.name.split('/').last ?? docType.id;
  if (text.isNotEmpty) _refuseApprovedMark(toLf(text));
  final given = text.isEmpty
      ? skeletonOf(docType, title)
      : markDraft(toLf(text), docType);
  final lineEnding = LineEnding.of(text);

  return session.locked(() {
    final docsRoot = session.project.docsRoot;
    final siblings = siblingsOnDisk(docsRoot, placed, parentValues);
    _checkNoClash(session, docType, placed, parentValues, siblings, slug);
    final highest = siblings.fold(0, (top, s) => max(top, s.number ?? 0));
    final created = <Directory>[];
    File? claimed;
    final String docPath;
    var lfText = given;
    try {
      (docPath, claimed) = _claim(
        session,
        placed,
        docType,
        parentValues,
        slug,
        highest + 1,
        created,
      );
      if (generators != null) {
        lfText = fillGeneratedBlocks(
          lfText,
          docType,
          generators,
          session.index,
        );
      }
      if (firstConfirmations != null) {
        lfText = firstConfirmations(lfText, docType, session.index);
      }
      lfText = session.writeDoc(docPath, lfText, lineEnding);
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

/// Returns the id of the doc type [docType]'s `--parent` names: its declared
/// `parent:`, or itself when it is the nesting type and nests; else null.
String? _parentTypeIdOf(MergedDocType docType, MergedSet set) {
  if (docType.parent case final declared?) return declared;
  final nesting = set.nestingType;
  return nesting != null && nesting.id == docType.id && nesting.nests
      ? docType.id
      : null;
}

/// Throws the fault for a [parent] or [slug] that [docType] needs and lacks,
/// or takes no value for, or a [slug] that is no slug.
void _checkArguments(
  MergedDocType docType,
  DocPathShape shape,
  String? parentTypeId, {
  required String? parent,
  required String? slug,
}) {
  final declaredParent = docType.parent;
  if (declaredParent != null && parent == null) {
    throw IndexFault(
      IndexFaultCode.argumentMissing,
      '${docType.id} needs --parent: a $declaredParent named by '
      '<doc type>:<name>, a bare name, or a path',
    );
  }
  if (shape.slugged && slug == null) {
    throw IndexFault(
      IndexFaultCode.argumentMissing,
      '${docType.id} needs --slug, lowercase letters, digits, and _',
    );
  }
  if (parentTypeId == null && parent != null) {
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

/// Returns the shape of [parentDoc], the doc of type [parentTypeId] that the
/// new doc hangs under, with the placeholder values its path holds.
(DocPathShape, List<String>) _shapeOfParent(
  MergedSet set,
  String parentTypeId,
  IndexedDoc parentDoc,
) {
  final parentType = set.lookup(parentTypeId);
  final shape = parentType == null
      ? null
      : DocPathShape.ofDoc(parentType, set, parentDoc.docPath);
  final values = shape?.valuesOf(parentDoc.docPath);
  if (shape == null || values == null) {
    throw StateError('${parentDoc.docPath} does not match its doc type');
  }
  return (shape, values);
}

/// Returns the nesting depth the new doc takes: its parent's, or one deeper
/// for a doc of the nesting type under another.
///
/// Throws [IndexFault] `argument_invalid` when that parent already sits at
/// the limit.
int _depthOf(
  MergedDocType docType,
  MergedSet set,
  IndexedDoc? parentDoc,
  DocPathShape? parentShape,
) {
  if (parentDoc == null || parentShape == null) return 0;
  if (docType.parent != null) return parentShape.depth;
  final limit = set.nestingType!.maxDepth!;
  if (parentShape.depth >= limit) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '${nameWithType(parentDoc)} sits ${parentShape.depth} levels deep, '
      'the limit, so it takes no sub-${docType.id}',
    );
  }
  return parentShape.depth + 1;
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
    session.project.requireWritablePath(file.path);
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

/// Returns the laid-out template skeleton of [docType]: a draft frontmatter
/// with each required field empty, the [title], and each required section.
String skeletonOf(MergedDocType docType, String title) =>
    layOutDoc(_rawSkeletonOf(docType, title), docType);

String _rawSkeletonOf(MergedDocType docType, String title) {
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
