/// Core library of Specstone, shared by the `specstone` CLI and MCP server.
library;

export 'src/fault.dart';
export 'src/rendering/docs_project.dart' show DocsProject, Target;
export 'src/rendering/format_run.dart' show FormatReport, runFormat;
export 'src/rendering/render_fault.dart';
export 'src/templates/merged_doc_type.dart';
export 'src/templates/merged_set.dart';
export 'src/templates/template_fault.dart';
export 'src/templates/template_resolver.dart';
export 'src/version.dart';
