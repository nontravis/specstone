import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/journal_bounds.dart';
import 'package:specstone_core/src/document_writing/models/new_item.dart';
import 'package:specstone_core/src/document_writing/models/record_edit.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/document_writing/record_edit.dart';
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
import 'package:specstone_core/src/rendering/models/line_ending.dart';
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
/// forced to `draft: true`. [codeTarget] narrows [parent] to that target's
/// docs and the shared docs, and places a per-target doc type's doc in that
/// target's spec folder when the project names two or more targets. Under the
/// session lock, [generators] and [firstConfirmations] fill it, then an
/// exclusive create writes it. The json holds one `docs` element: name,
/// docType, path, base, and bases, as `get` gives them.
/// Throws [TemplateFault] `doc_type_unknown` for [docTypeId] or a [parent]
/// that names another doc type id, [IndexFault] `argument_missing`
/// or `argument_invalid` for a [parent] or [slug] the doc type needs or does
/// not take, a per-target doc type with no [codeTarget] among two or more
/// targets, a [codeTarget] the project does not name, a [parent] already at
/// `max_depth`, or a [text] that holds a naming line at column 0 outside
/// fenced code, [WriteFault] `doc_exists` when the doc is there and
/// `field_not_writable` when [text] holds an `approved` key, and
/// [RenderFault] `output_not_writable` when the disk refuses or the doc path
/// holds a `.` or `..` name, after removing what this call created.
ReadAnswer answerNew(
  WriteSession session, {
  required String docTypeId,
  String? parent,
  String? slug,
  String? codeTarget,
  String text = '',
  GeneratorRegistry<DocIndex>? generators,
  NewDocFill? firstConfirmations,
}) {
  final place = planNewDoc(
    session,
    docTypeId: docTypeId,
    parent: parent,
    slug: slug,
    codeTarget: codeTarget,
  );
  final NewDocPlace(:docType, shape: placed, :parentValues, :placedIn) = place;
  if (text.isNotEmpty) {
    refuseNamingLine(toLf(text), 'the text');
    _refuseApprovedMark(toLf(text));
  }
  final given = text.isEmpty
      ? skeletonOf(docType, place.title)
      : markDraft(toLf(text), docType);
  final lineEnding = LineEnding.of(text);

  return session.locked(() {
    final highest = place.highestOnDisk(session);
    final records = plannedLineEditsOf(session, [place.itemAt(highest + 1)]);
    final created = <Directory>[];
    File? claimed;
    var isJournalSaved = false;
    final String docPath;
    var lfText = given;
    try {
      final claim = _claim(
        session,
        placed,
        docType,
        parentValues,
        slug,
        highest + 1,
        created,
        placedIn,
      );
      docPath = claim.docPath;
      claimed = claim.file;
      if (generators != null) {
        lfText = fillGeneratedBlocks(
          lfText,
          docType,
          generators,
          session.index,
          docPath: docPath,
        );
      }
      if (firstConfirmations != null) {
        lfText = firstConfirmations(lfText, docType, session.index);
      }
      lfText = records.isEmpty
          ? session.writeDoc(docPath, lfText, lineEnding)
          : _writeWithRecords(
              session,
              docPath,
              lfText,
              lineEnding,
              records,
              onSaved: () => isJournalSaved = true,
            );
    } on Object {
      // A journal this run saved finishes the doc and its records on the next
      // write.
      if (!isJournalSaved) _remove(claimed, created);
      rethrow;
    }

    final written = parseIndexedDoc(
      docPath: docPath,
      bytes: utf8.encode(lineEnding.apply(lfText)),
      match: MatchedDocType(docType, target: placedIn),
      statusesOutside: session.project.statusesOutsideApproval,
    );
    return ReadAnswer(
      text: '${namingLine(written.doc)}\n',
      json: {
        'docs': [
          {
            'name': written.doc.name,
            'docType': docType.id,
            'path': docPath,
            'base': wholeDocBaseOf(written.content),
            'bases': basesOf(written.content, docType),
          },
        ],
      },
    );
  });
}

/// Where a new doc of one doc type goes, as `new` judges it.
final class NewDocPlace {
  const new({
    required this.docType,
    required this.shape,
    required this.parentDoc,
    required this.parentValues,
    required this.placedIn,
    required this.slug,
  });

  final MergedDocType docType;

  /// The path shape the new doc takes at its depth and code target.
  final DocPathShape shape;

  /// The doc the new doc nests under; null for a doc with no parent.
  final IndexedDoc? parentDoc;

  /// The placeholder values the parent's path holds.
  final List<String> parentValues;

  /// The code target whose spec folder holds the new doc; null for none.
  final String? placedIn;
  final String? slug;

  /// The `# ` title of the doc's skeleton when the doc type fixes none.
  String get title => slug ?? parentDoc?.name.split('/').last ?? docType.id;

  /// Returns the DocPath the doc takes at sibling [number]; an unnumbered doc
  /// type ignores it.
  String docPathAt(int number) => shape.build([
    ...parentValues,
    ...shape.ownValues(
      number: shape.numbered ? padNumber(number) : null,
      slug: slug,
    ),
  ]);

  /// Returns the doc at sibling [number] as its feature's records read it.
  NewItem itemAt(int number) {
    final docPath = docPathAt(number);
    return NewItem(
      docTypeId: docType.id,
      docPath: docPath,
      name: docNameOf(docPath, docType, target: placedIn),
      parent: parentDoc,
    );
  }

  /// Returns the highest sibling number on disk, 0 when there is none.
  ///
  /// Throws [WriteFault] `doc_exists` when a doc already holds the place.
  int highestOnDisk(WriteSession session) {
    final siblings = siblingsOnDisk(session.project, shape, parentValues);
    _checkNoClash(
      session,
      docType,
      shape,
      parentValues,
      siblings,
      slug,
      placedIn,
    );
    return siblings.fold(0, (top, s) => max(top, s.number ?? 0));
  }
}

/// Returns where a new doc of [docTypeId] under [parent] with [slug] goes,
/// writing nothing.
///
/// [parentNamed], when given, reads [parent] in place of
/// [WriteSession.parentTarget], as a plan reads it among the docs its `new`
/// lines create too.
/// Throws as [answerNew] does before its lock.
NewDocPlace planNewDoc(
  WriteSession session, {
  required String docTypeId,
  String? parent,
  String? slug,
  String? codeTarget,
  IndexedDoc Function(String parent, String parentTypeId)? parentNamed,
}) {
  session.index.checkCodeTarget(codeTarget);
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
  final placedIn = _placedInOf(docType, session.index, codeTarget);
  final parentDoc = parent == null
      ? null
      : parentNamed?.call(parent, parentTypeId!) ??
            session.parentTarget(parent, parentTypeId!, codeTarget: codeTarget);
  final parentLayout = parentDoc == null
      ? null
      : _shapeOfParent(set, parentTypeId!, parentDoc);
  final parentShape = parentLayout?.shape;
  final depth = _depthOf(docType, set, parentDoc, parentShape);
  final placed =
      DocPathShape.of(docType, set, depth: depth, target: placedIn) ??
      (throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '$docTypeId has no path to create a doc at depth $depth',
      ));
  return NewDocPlace(
    docType: docType,
    shape: placed,
    parentDoc: parentDoc,
    parentValues: parentLayout?.values ?? const <String>[],
    placedIn: placedIn,
    slug: slug,
  );
}

/// Writes the new doc at [docPath] and the planned line of each of [records]
/// in one journal, and returns the LF text of the doc as written.
///
/// A crash leaves the journal for the next write to finish, so no record names
/// an item whose doc is not there.
String _writeWithRecords(
  WriteSession session,
  String docPath,
  String lfText,
  LineEnding lineEnding,
  List<RecordEdit> records, {
  required void Function() onSaved,
}) {
  final laidOut = layOutDoc(lfText, session.docTypeAt(docPath));
  MoveJournal([
    WriteStep(
      session.projectPathOf(docPath),
      lineEnding.apply(laidOut),
      before: textHashOf(''),
    ),
    for (final record in records) plannedLineStepOf(session, record),
  ]).run(session.journalTarget, onSaved: onSaved);
  return laidOut;
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

/// Returns the code target whose spec folder holds the new doc of [docType],
/// or null when the plain `path:` places it.
///
/// A per-target doc type is placed in a target's folder only when the project
/// names two or more targets, as the doc type matcher reads it.
/// Throws [IndexFault] `argument_missing` when [codeTarget] is null then.
String? _placedInOf(MergedDocType docType, DocIndex index, String? codeTarget) {
  if (!docType.isPerTarget || !index.hasTwins) return null;
  if (codeTarget != null) return codeTarget;
  throw IndexFault(
    IndexFaultCode.argumentMissing,
    '${docType.id} needs --target: the code targets are '
    '${index.twinNames.join(', ')}',
  );
}

/// The path shape of a parent doc and the placeholder values its path holds.
final class _ParentShape {
  const new({required this.shape, required this.values});

  final DocPathShape shape;
  final List<String> values;
}

/// Returns the shape of [parentDoc], the doc of type [parentTypeId] that the
/// new doc hangs under, with the placeholder values its path holds.
_ParentShape _shapeOfParent(
  MergedSet set,
  String parentTypeId,
  IndexedDoc parentDoc,
) {
  final parentType = set.lookup(parentTypeId);
  final shape = parentType == null
      ? null
      : DocPathShape.ofDoc(
          parentType,
          set,
          parentDoc.docPath,
          target: parentDoc.target,
        );
  final values = shape?.valuesOf(parentDoc.docPath);
  if (shape == null || values == null) {
    throw StateError('${parentDoc.docPath} does not match its doc type');
  }
  return _ParentShape(shape: shape, values: values);
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
  String? placedIn,
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
      'a ${docType.id} named ${docNameOf(docPath, docType, target: placedIn)} '
      'exists',
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

/// The DocPath of a claimed doc and its newly made, empty file.
final class _Claimed {
  const new({required this.docPath, required this.file});

  final String docPath;
  final File file;
}

/// Creates the folders and the empty file of the new doc, trying the next
/// number each time the file turns out to be there.
///
/// Returns the DocPath and the file; every folder made joins [created].
/// Throws [RenderFault] `output_not_writable` when the disk refuses or the
/// DocPath holds a `.` or `..` name, and [WriteFault] `doc_exists` when a doc
/// with no number to bump is there.
_Claimed _claim(
  WriteSession session,
  DocPathShape shape,
  MergedDocType docType,
  List<String> parentValues,
  String? slug,
  int firstNumber,
  List<Directory> created,
  String? placedIn,
) {
  for (var number = firstNumber; ; number++) {
    final own = shape.ownValues(
      number: shape.numbered ? padNumber(number) : null,
      slug: slug,
    );
    final docPath = shape.build([...parentValues, ...own]);
    final file = session.fileOf(docPath);
    _refuseDotSegment(session, docPath, file);
    session.project.requireWritablePath(file.path);
    try {
      _createFolders(file.parent, created);
      file.createSync(exclusive: true);
      return _Claimed(docPath: docPath, file: file);
    } on PathExistsException {
      if (!shape.numbered) {
        throw WriteFault(
          WriteFaultCode.docExists,
          'a ${docType.id} named '
          '${docNameOf(docPath, docType, target: placedIn)} exists',
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

/// Throws [RenderFault] `output_not_writable` when [docPath], the DocPath of
/// [file], holds a `.` or `..` name.
///
/// The disk may resolve one (Windows always folds a `..` by name), yet a
/// DocPath names each folder down from the docs root.
void _refuseDotSegment(WriteSession session, String docPath, File file) {
  if (!holdsDotSegment(docPath.split('/'))) return;
  final shown = pathFromProjectRoot(
    file.path,
    session.project.projectRoot,
    session.project.docsRoot,
  );
  throw RenderFault(
    RenderFaultCode.outputNotWritable,
    'cannot write $shown: a doc path cannot hold a . or .. name',
    file: shown,
  );
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
/// with each required field empty, the title, each required section with its
/// template, and each optional section that sets `skeleton` as a bare header.
///
/// The title is the doc type's fixed `title` when it sets one, else [title].
String skeletonOf(MergedDocType docType, String title) =>
    layOutDoc(_rawSkeletonOf(docType, docType.title ?? title), docType);

String _rawSkeletonOf(MergedDocType docType, String title) {
  final buffer = StringBuffer('---\ndraft: true\n');
  for (final field in docType.fields) {
    if (field.required) buffer.write('${field.id}:\n');
  }
  buffer.write('---\n\n# $title\n');
  for (final section in docType.sections) {
    if (!section.required && section.skeleton != true) continue;
    buffer.write('\n## ${section.header}\n');
    if (!section.required) continue;
    final template = section.template;
    if (template != null && template.isNotEmpty) buffer.write('$template\n');
  }
  return buffer.toString();
}
