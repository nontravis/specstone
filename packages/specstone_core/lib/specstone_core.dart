/// Core library of Specstone, shared by the `specstone` CLI and MCP server.
library;

export 'src/consistency_check/check_report.dart' show CheckReport;
export 'src/consistency_check/check_run.dart' show runCheck;
export 'src/consistency_check/finding.dart' show Finding, FindingKind;
export 'src/consistency_check/suspect_list.dart' show answerListSuspect;
export 'src/document_writing/approval.dart' show ApprovalHistory;
export 'src/document_writing/approve_drafts.dart'
    show approveDrafts, requireOwnerTerminal;
export 'src/document_writing/delete_doc.dart' show answerDelete;
export 'src/document_writing/move_doc.dart' show answerRename, answerReorder;
export 'src/document_writing/new_doc.dart' show answerNew;
export 'src/document_writing/set_doc.dart' show SetRequest, answerSet;
export 'src/document_writing/write_fault.dart'
    show CurrentTarget, WriteFault, WriteFaultCode;
export 'src/document_writing/write_session.dart' show WriteSession;
export 'src/fault.dart';
export 'src/index_query/bundle.dart' show Bundle, BundleMode, pickBundle;
export 'src/index_query/bundle_render.dart' show answerContext;
export 'src/index_query/code_bundle.dart'
    show CodePath, pickCodeBundle, resolveCodePath;
export 'src/index_query/doc_index.dart' show DocIndex;
export 'src/index_query/get_docs.dart' show answerGet;
export 'src/index_query/index_fault.dart' show IndexFault, IndexFaultCode;
export 'src/index_query/index_store.dart' show indexBusyTimeout;
export 'src/index_query/indexed_doc.dart' show IndexedDoc;
export 'src/index_query/list_docs.dart' show ListFilters, answerList;
export 'src/index_query/read_answer.dart'
    show
        ReadAnswer,
        docJson,
        docLine,
        missingArgument,
        nameWithType,
        namingLine,
        parsePositiveOption;
export 'src/index_query/read_session.dart' show ReadSession;
export 'src/index_query/refs.dart' show answerRefs;
export 'src/index_query/search_docs.dart'
    show SearchOptions, answerSearch, checkQuery, defaultSearchLimit;
export 'src/index_query/structure.dart' show answerStructure;
export 'src/rendering/build_output.dart'
    show
        BuildResult,
        OutputFormat,
        defaultOutputFile,
        outputName,
        writeBuildOutput;
export 'src/rendering/docs_project.dart' show DocsProject, Target;
export 'src/rendering/format_run.dart' show FormatReport, runFormat;
export 'src/rendering/html_build.dart' show HtmlBuild, buildHtml;
export 'src/rendering/page_setup.dart' show PageSetup, Paper;
export 'src/rendering/render_fault.dart';
export 'src/templates/merged_doc_type.dart';
export 'src/templates/merged_set.dart';
export 'src/templates/template_fault.dart';
export 'src/templates/template_resolver.dart';
export 'src/version.dart';
