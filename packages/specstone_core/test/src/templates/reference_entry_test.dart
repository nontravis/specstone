import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/reference_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:test/test.dart';

const _file = '.specstone/templates/feature.yaml';
const _exists = {'refs/handbook.md'};

final class _FakeFiles implements LayerFiles {
  const new(this.paths);

  final Set<String> paths;

  @override
  bool exists(String layerRelativePath) => paths.contains(layerRelativePath);
}

ReferenceEntry parseRef(
  String entry, {
  LayerKind kind = LayerKind.project,
  String templateFolder = '',
  Set<String> files = _exists,
  String key = 'reference[0]',
}) {
  final map = readYamlMap(entry, file: _file);
  return ReferenceEntry.parse(
    map,
    file: _file,
    key: key,
    kind: kind,
    templateFolder: templateFolder,
    files: _FakeFiles(files),
  );
}

TypeMatcher<TemplateFault> _fault(FaultCode code, {String? key}) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _file)
        .having((f) => f.key, 'key', key);

void main() {
  group('ReferenceEntry.parse', () {
    test('an entry with no title is missing_key', () {
      expect(
        () => parseRef('{url: https://x}'),
        throwsA(_fault(FaultCode.missingKey, key: 'reference[0].title')),
      );
    });

    test('two links in one entry is reference_link_conflict', () {
      expect(
        () => parseRef('{title: T, url: https://x, doc: prd/feature}'),
        throwsA(_fault(FaultCode.referenceLinkConflict, key: 'reference[0]')),
      );
    });

    test('a missing file is reference_file_missing', () {
      expect(
        () => parseRef('{title: T, file: refs/none.md}'),
        throwsA(_fault(FaultCode.referenceFileMissing, key: 'reference[0]')),
      );
    });

    test('an absolute file is reference_file_outside', () {
      expect(
        () => parseRef('{title: T, file: /etc/hosts}'),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });

    test('an escaping segment is reference_file_outside', () {
      expect(
        () => parseRef('{title: T, file: refs/../../x.md}'),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });

    test('a doc in a personal layer '
        'is reference_doc_outside_project', () {
      expect(
        () =>
            parseRef('{title: T, doc: prd/feature}', kind: LayerKind.personal),
        throwsA(
          _fault(FaultCode.referenceDocOutsideProject, key: 'reference[0]'),
        ),
      );
    });

    test('a doc in a shipped layer '
        'is reference_doc_outside_project', () {
      expect(
        () => parseRef('{title: T, doc: prd/feature}', kind: LayerKind.shipped),
        throwsA(
          _fault(FaultCode.referenceDocOutsideProject, key: 'reference[0]'),
        ),
      );
    });

    test('a url entry is accepted unchanged', () {
      final entry = parseRef('{title: T, url: https://example.com/a}');
      expect(entry.url, 'https://example.com/a');
      expect(entry.file, isNull);
      expect(entry.doc, isNull);
    });

    test('a doc entry in the project layer is accepted', () {
      final entry = parseRef('{title: T, doc: prd/feature}');
      expect(entry.doc, 'prd/feature');
    });

    test('a file of a shipped layer is accepted when present', () {
      final entry = parseRef(
        '{title: T, file: refs/handbook.md}',
        kind: LayerKind.shipped,
      );
      expect(entry.file, 'refs/handbook.md');
    });

    test('an unknown entry key is unknown_key', () {
      expect(
        () => parseRef('{title: T, href: https://x}'),
        throwsA(_fault(FaultCode.unknownKey, key: 'reference[0].href')),
      );
    });

    test('a title-only entry carries only the title', () {
      final entry = parseRef('{title: Clean Architecture}');
      expect(entry.toJson(), {'title': 'Clean Architecture'});
    });

    test('a locator rides along in toJson', () {
      final entry = parseRef(
        '{title: NASA Systems Engineering Handbook, locator: Appendix C}',
      );
      expect(entry.toJson(), {
        'title': 'NASA Systems Engineering Handbook',
        'locator': 'Appendix C',
      });
    });

    test('an add entry is checked by its own '
        'key', () {
      expect(
        () => parseRef(
          '{title: T, doc: x}',
          kind: LayerKind.personal,
          key: 'reference.add[0]',
        ),
        throwsA(
          _fault(FaultCode.referenceDocOutsideProject, key: 'reference.add[0]'),
        ),
      );
    });
  });

  group('ReferenceEntry file normalization', () {
    test('a file URL is reference_file_outside', () {
      expect(
        () => parseRef('{title: T, file: "file:///etc/hosts"}'),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });

    test('an http URL is reference_file_outside', () {
      expect(
        () => parseRef('{title: T, file: "https://h/handbook.md"}'),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });

    test('a drive letter is reference_file_outside', () {
      expect(
        () => parseRef('{title: T, file: "C:/x.md"}'),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });

    test('a leading backslash is reference_file_outside', () {
      expect(
        () => parseRef(r"{title: T, file: '\x.md'}"),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });

    test('a backslash escape is reference_file_outside', () {
      expect(
        () => parseRef(r"{title: T, file: 'refs\..\..\x.md'}"),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });

    test('a backslash separator is reference_file_outside', () {
      expect(
        () => parseRef(r"{title: T, file: 'refs\x.md'}"),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });

    test('a file name with a space keeps its characters', () {
      final entry = parseRef(
        '{title: T, file: my notes.md}',
        files: {'my notes.md'},
      );
      expect(entry.file, 'my notes.md');
    });

    test('a file name with a hash keeps its characters', () {
      final entry = parseRef(
        '{title: T, file: refs/a#b.md}',
        files: {'refs/a#b.md'},
      );
      expect(entry.file, 'refs/a#b.md');
    });

    test('a file inside a nested template folder is accepted', () {
      final entry = parseRef(
        '{title: T, file: handbook.md}',
        templateFolder: 'refs',
      );
      expect(entry.file, 'refs/handbook.md');
    });

    test('a file escaping a nested template folder is '
        'reference_file_outside', () {
      expect(
        () =>
            parseRef('{title: T, file: ../secrets.md}', templateFolder: 'refs'),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });
  });
}
