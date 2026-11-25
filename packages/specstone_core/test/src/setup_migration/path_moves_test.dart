import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/setup_migration/path_moves.dart';
import 'package:test/test.dart';

void main() {
  group('PathMoves', () {
    test('caseBlindPath folds a path to lowercase, non-ASCII letters too', () {
      expect(PathMoves.caseBlindPath('Specs/ÄB.md'), 'specs/äb.md');
    });

    test('prunesOf lists each emptied folder once, a deeper one first', () {
      final prunes = PathMoves.prunesOf([
        const PathMove(from: 'prds/a/x.md', to: 'prds/f01/x.md'),
        const PathMove(from: 'prds/a/b/y.md', to: 'prds/f01/y.md'),
        const PathMove(from: 'prds/a/z.md', to: 'prds/f01/z.md'),
        const PathMove(from: 'specs/c/w.md', to: 'specs/w.md'),
      ]);

      expect(prunes, ['docs/specs/c', 'docs/prds/a/b', 'docs/prds/a']);
    });
  });
}
