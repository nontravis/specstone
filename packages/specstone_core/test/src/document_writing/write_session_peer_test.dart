import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/write_fixture.dart';

/// Commits, from another connection, the drop of [doc]'s index row.
void _peerDrops(WriteSession session, IndexedDoc doc) {
  final peer = IndexStore.open(session.project.projectRoot);
  try {
    peer.write(() => peer.deleteDoc(doc.docPath));
  } finally {
    peer.close();
  }
}

/// Commits, from another connection, a stamp of the index's last check alone.
void _peerStamps(WriteSession session) {
  final peer = IndexStore.open(session.project.projectRoot);
  try {
    peer.write(() => peer.setCheckedAt(1));
  } finally {
    peer.close();
  }
}

void main() {
  group('a peer commit between the read snapshot and the write lock', () {
    test('that only stamps the last check still runs the body twice and its '
        'write once', () async {
      final root = await writeWriteProject();
      var runs = 0;
      var writes = 0;
      WriteSession.run(
        (session) {
          runs++;
          if (runs == 1) _peerStamps(session);
          session.locked(() => writes++);
        },
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: null,
      );
      expect(runs, 2);
      expect(writes, 1);
    });

    test('runs the command again on the fresh index', () async {
      final root = await writeWriteProject();
      var runs = 0;
      final text = WriteSession.run(
        (session) {
          runs++;
          final doc = session.index.docs.firstWhere((d) => d.isTyped);
          if (runs == 1) _peerDrops(session, doc);
          return session.locked(() => session.index.contentOf(doc).text);
        },
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: null,
      );
      expect(runs, 2);
      expect(text, isNotEmpty);
    });

    test('runs the body twice and its write once', () async {
      final root = await writeWriteProject();
      var runs = 0;
      var writes = 0;
      WriteSession.run(
        (session) {
          runs++;
          if (runs == 1) {
            _peerDrops(
              session,
              session.index.docs.firstWhere((d) => d.isTyped),
            );
          }
          session.locked(() => writes++);
        },
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: null,
      );
      expect(runs, 2);
      expect(writes, 1);
    });

    test('ends as index_busy after three stale runs, with nothing '
        'written', () async {
      final root = await writeWriteProject();
      var runs = 0;
      var writes = 0;
      expect(
        () => WriteSession.run(
          (session) {
            runs++;
            _peerDrops(
              session,
              session.index.docs.firstWhere((d) => d.isTyped),
            );
            session.locked(() => writes++);
          },
          templates: TemplateResolver(),
          workingDirectory: root,
          homeDirectory: null,
        ),
        throwsA(
          isA<IndexFault>().having(
            (fault) => fault.code,
            'code',
            IndexFaultCode.indexBusy,
          ),
        ),
      );
      expect(runs, 3);
      expect(writes, 0);
    });
  });
}
