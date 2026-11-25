import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/feature_pattern_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/models/reference_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

const _file = '.specstone/templates/patterns/auth.yaml';

final class _FakeFiles implements LayerFiles {
  const new(this.paths);

  final Set<String> paths;

  @override
  bool exists(String layerRelativePath) => paths.contains(layerRelativePath);
}

FeaturePatternLayer parsePattern(
  String yaml, {
  String patternId = 'auth',
  LayerKind kind = LayerKind.project,
  Set<String> files = const {'patterns/notes.md'},
}) => FeaturePatternLayer.parse(
  yaml,
  file: _file,
  patternId: patternId,
  kind: kind,
  files: _FakeFiles(files),
);

TypeMatcher<TemplateFault> _fault(FaultCode code, {String? key, int? line}) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _file)
        .having((f) => f.key, 'key', key)
        .having((f) => f.line, 'line', line)
        .having((f) => f.exitStatus, 'exit status', 78);

void main() {
  group('FeaturePatternLayer.parse', () {
    test('reads every key of a full defining file', () {
      final layer = parsePattern('''
id: auth
description: |
  Sign-in checklist.
  Second line.
extends: base
items:
  - id: lockout
    text: Name the lockout rule.
  - id: reset
    text: Name the reset path.
reference:
  - title: Handbook
    url: https://example.com/handbook
''');

      expect(layer.id, 'auth');
      expect(layer.file, _file);
      expect(layer.kind, LayerKind.project);
      expect(layer.description, 'Sign-in checklist.\nSecond line.\n');
      expect(layer.extendsId, 'base');
      expect(layer.items.map((i) => i.id), ['lockout', 'reset']);
      expect(layer.items.first.text, 'Name the lockout rule.');
      expect(layer.items.first.disabled, isFalse);
      expect(layer.reference, isA<PlainList<ReferenceEntry>>());
      expect(
        (layer.reference! as PlainList<ReferenceEntry>).items.single.title,
        'Handbook',
      );
    });

    test('reads an override file that writes one item entry', () {
      final layer = parsePattern('''
id: auth
items:
  - id: lockout
    text: Own text.
''');

      expect(layer.description, isNull);
      expect(layer.extendsId, isNull);
      expect(layer.reference, isNull);
      expect(layer.items.single.text, 'Own text.');
    });

    test('reads an item that disables another', () {
      final layer = parsePattern('''
id: auth
items:
  - id: lockout
    disabled: true
''');

      expect(layer.items.single.disabled, isTrue);
      expect(layer.items.single.text, isNull);
    });

    test('refuses invalid YAML with the file and the line', () {
      expect(
        () => parsePattern('id: auth\nitems: [unclosed\n'),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.yamlSyntax)
              .having((f) => f.file, 'file', _file)
              .having((f) => f.line, 'line', isNotNull)
              .having((f) => f.exitStatus, 'exit status', 78),
        ),
      );
    });

    test('refuses a key the format does not define', () {
      expect(
        () => parsePattern('id: auth\ntitle: Sign in\n'),
        throwsA(_fault(FaultCode.unknownKey, key: 'title')),
      );
    });

    test('refuses a key an item does not define', () {
      expect(
        () => parsePattern('id: auth\nitems:\n  - {id: a, text: t, why: w}\n'),
        throwsA(_fault(FaultCode.unknownKey, key: 'items[0].why')),
      );
    });

    test('refuses an id that is no slug', () {
      expect(
        () => parsePattern('id: Auth\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'id')),
      );
    });

    test('refuses an item id that is no slug', () {
      expect(
        () => parsePattern('id: auth\nitems:\n  - {id: Lock-out, text: t}\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'items[0].id')),
      );
    });

    test('refuses an extends that holds a list', () {
      expect(
        () => parsePattern('id: auth\nextends: [a, b]\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'extends')),
      );
    });

    test('refuses items that is no list', () {
      expect(
        () => parsePattern('id: auth\nitems: lockout\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'items')),
      );
    });

    test('refuses an item that is no mapping', () {
      expect(
        () => parsePattern('id: auth\nitems:\n  - lockout\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'items[0]')),
      );
    });

    test('refuses an item text that is no string', () {
      expect(
        () => parsePattern('id: auth\nitems:\n  - {id: a, text: [x]}\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'items[0].text')),
      );
    });

    test('refuses a file with no id', () {
      expect(
        () => parsePattern('description: d\n'),
        throwsA(_fault(FaultCode.missingKey, key: 'id')),
      );
    });

    test('refuses an item with no id', () {
      expect(
        () => parsePattern('id: auth\nitems:\n  - {text: t}\n'),
        throwsA(_fault(FaultCode.missingKey, key: 'items[0].id')),
      );
    });

    test('refuses an item with neither text nor disabled', () {
      expect(
        () => parsePattern('id: auth\nitems:\n  - {id: a}\n'),
        throwsA(_fault(FaultCode.missingKey, key: 'items[0].text')),
      );
    });

    test('refuses an item that writes disabled false and no text', () {
      expect(
        () => parsePattern('id: auth\nitems:\n  - {id: a, disabled: false}\n'),
        throwsA(_fault(FaultCode.missingKey, key: 'items[0].text')),
      );
    });

    test('refuses an id that differs from the file name', () {
      expect(
        () => parsePattern('id: crud\n'),
        throwsA(_fault(FaultCode.featurePatternIdMismatch, key: 'id')),
      );
    });

    test('refuses an item id the file repeats, naming the id', () {
      expect(
        () => parsePattern('''
id: auth
items:
  - {id: lockout, text: one}
  - {id: reset, text: two}
  - {id: lockout, text: three}
'''),
        throwsA(
          _fault(
            FaultCode.checklistItemDuplicate,
            key: 'items',
          ).having((f) => f.message, 'message', contains('lockout')),
        ),
      );
    });

    test('refuses a source holding both a url and a file', () {
      expect(
        () => parsePattern('''
id: auth
reference:
  - {title: T, url: 'https://example.com', file: notes.md}
'''),
        throwsA(_fault(FaultCode.referenceLinkConflict, key: 'reference[0]')),
      );
    });

    test('resolves a file source against the patterns folder', () {
      final layer = parsePattern('''
id: auth
reference:
  - {title: T, file: notes.md}
''');

      final reference = layer.reference! as PlainList<ReferenceEntry>;
      expect(reference.items.single.file, 'patterns/notes.md');
    });

    test('refuses a file source that leaves the patterns folder', () {
      expect(
        () => parsePattern(
          '''
id: auth
reference:
  - {title: T, file: ../x.md}
''',
          files: {'x.md'},
        ),
        throwsA(_fault(FaultCode.referenceFileOutside, key: 'reference[0]')),
      );
    });

    test('refuses a file source the layer does not hold', () {
      expect(
        () => parsePattern('''
id: auth
reference:
  - {title: T, file: absent.md}
'''),
        throwsA(_fault(FaultCode.referenceFileMissing, key: 'reference[0]')),
      );
    });

    test('reads a reference written as add and remove', () {
      final layer = parsePattern('''
id: auth
reference:
  add:
    - {title: New, url: 'https://example.com'}
  remove: [Old]
''');

      final change = layer.reference! as ListChange<ReferenceEntry>;
      expect(change.add.single.title, 'New');
      expect(change.remove, ['Old']);
    });
  });

  group('isFeaturePatternFileName', () {
    test('accepts one slug under patterns', () {
      expect(isFeaturePatternFileName('patterns/auth.yaml'), isTrue);
      expect(isFeaturePatternFileName('patterns/sign_in2.yaml'), isTrue);
    });

    test('rejects a name that is no pattern file', () {
      expect(isFeaturePatternFileName('auth.yaml'), isFalse);
      expect(isFeaturePatternFileName('patterns/Auth.yaml'), isFalse);
      expect(isFeaturePatternFileName('patterns/auth.yml'), isFalse);
      expect(isFeaturePatternFileName('patterns/a/b.yaml'), isFalse);
      expect(isFeaturePatternFileName('patterns/.yaml'), isFalse);
      expect(isFeaturePatternFileName('other/auth.yaml'), isFalse);
    });
  });

  group('FaultCode', () {
    test('pattern faults exit 78 with their catalog wires', () {
      expect(
        FaultCode.featurePatternIdMismatch.wire,
        'feature_pattern_id_mismatch',
      );
      expect(FaultCode.featurePatternIdMismatch.exitStatus, 78);
      expect(FaultCode.checklistItemDuplicate.wire, 'checklist_item_duplicate');
      expect(FaultCode.checklistItemDuplicate.exitStatus, 78);
    });
  });
}
