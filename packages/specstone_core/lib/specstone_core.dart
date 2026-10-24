/// Core library of Specstone, shared by the `specstone` CLI and MCP server.
library;

export 'src/fault.dart';
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
export 'src/rendering/browser_host.dart' show BrowserHost, HostOs, RunProcess;
export 'src/rendering/browser_locator.dart' show locateBrowser;
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
export 'src/rendering/pdf_printer.dart' show printPdf;
export 'src/rendering/render_fault.dart';
export 'src/templates/merged_doc_type.dart';
export 'src/templates/merged_set.dart';
export 'src/templates/template_fault.dart';
export 'src/templates/template_resolver.dart';
export 'src/version.dart';
