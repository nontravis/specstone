import 'package:specstone_core/src/doc_model/records_root.dart';

/// The most UTF-16 code units a doc's path from the project root may hold.
const pathLengthLimit = 200;

/// Returns the code units in the path from the project root of the doc at
/// [docPath].
///
/// `check` and the writers count with this one function, so no path passes
/// one and fails the other.
int projectPathLength(String docPath) => projectPathOfDocPath(docPath).length;
