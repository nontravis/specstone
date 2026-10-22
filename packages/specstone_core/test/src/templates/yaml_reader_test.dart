import 'package:specstone_core/specstone_core.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _file = '.specstone/templates/a.yaml';

TypeMatcher<TemplateFault> _fault(FaultCode code, {String? key, int? line}) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _file)
        .having((f) => f.key, 'key', key)
        .having((f) => f.line, 'line', line);

void main() {
  group('readYamlMap', () {
    test(
      'f03/us03/fr01/e01, s03/inv10: invalid YAML is yaml_syntax with the line',
      () {
        expect(
          () => readYamlMap('id: a\nsections: [\n', file: _file),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.yamlSyntax)
                .having((f) => f.file, 'file', _file)
                .having((f) => f.line, 'line', isA<int>())
                .having((f) => f.exitStatus, 'exit', 78),
          ),
        );
      },
    );

    test('f03/us03/fr01/e01: fault message carries no location prefix', () {
      TemplateFault? caught;
      try {
        readYamlMap('id: a\nsections: [\n', file: _file);
      } on TemplateFault catch (fault) {
        caught = fault;
      }

      expect(caught, isNotNull);
      expect(caught!.message, isNot(contains('.specstone/')));
      expect(caught.message, isNot(matches(r':\d')));
    });

    test('f03/us03/fr01/e01: a duplicate key is yaml_syntax on line 2', () {
      expect(
        () => readYamlMap('a: 1\na: 2\n', file: _file),
        throwsA(_fault(FaultCode.yamlSyntax, line: 2)),
      );
    });

    test('f03/us03/fr01/e01: a non-map root is yaml_syntax on line 1', () {
      expect(
        () => readYamlMap('- a\n- b\n', file: _file),
        throwsA(_fault(FaultCode.yamlSyntax, line: 1)),
      );
    });

    test('f03/us03/fr01/e01: a scalar root is yaml_syntax on line 1', () {
      expect(
        () => readYamlMap('just text', file: _file),
        throwsA(_fault(FaultCode.yamlSyntax, line: 1)),
      );
    });

    test('f03/us03/fr01: empty text gives an empty map', () {
      expect(readYamlMap('', file: _file), isEmpty);
    });

    test('f03/us03/fr01: comment-only text gives an empty map', () {
      expect(readYamlMap('# nothing here\n', file: _file), isEmpty);
    });

    test('f03/us03/fr01: a mapping reads into a YamlMap', () {
      final map = readYamlMap('id: a\nn: 2\n', file: _file);

      expect(map['id'], 'a');
      expect(map['n'], 2);
    });
  });

  group('checkKeys', () {
    test('f03/us03/fr01/e02, s03/inv10: an unknown key under a prefix is unknown_key', () {
      final map = readYamlMap('bogus: 1\n', file: _file);

      expect(
        () => checkKeys(
          map,
          {'title'},
          file: _file,
          format: 'doc-type',
          prefix: 'sections.goal.',
        ),
        throwsA(_fault(FaultCode.unknownKey, key: 'sections.goal.bogus')),
      );
    });

    test('f03/us03/fr01/e04: a camelCase key is unknown_key by its name', () {
      final map = readYamlMap('prefixId: x\n', file: _file);

      expect(
        () => checkKeys(map, {'prefix_id'}, file: _file, format: 'doc-type'),
        throwsA(
          _fault(FaultCode.unknownKey, key: 'prefixId').having(
            (f) => f.message,
            'message',
            'the doc-type format defines no key prefixId',
          ),
        ),
      );
    });

    test('f03/us03/fr01/e02: the message names the given format', () {
      final map = readYamlMap('pakcs: 1\n', file: _file);

      expect(
        () => checkKeys(map, {'packs'}, file: _file, format: 'config'),
        throwsA(
          _fault(FaultCode.unknownKey, key: 'pakcs').having(
            (f) => f.message,
            'message',
            'the config format defines no key pakcs',
          ),
        ),
      );
    });

    test('f03/us03/fr01/e02: the first unknown key in file order wins', () {
      final map = readYamlMap('id: a\nzzz: 1\naaa: 2\n', file: _file);

      expect(
        () => checkKeys(map, {'id'}, file: _file, format: 'doc-type'),
        throwsA(_fault(FaultCode.unknownKey, key: 'zzz')),
      );
    });

    test('f03/us03/fr01: keys all in the allowed set pass', () {
      final map = readYamlMap('id: a\npath: p\n', file: _file);

      expect(
        () => checkKeys(
          map,
          {'id', 'path', 'extra'},
          file: _file,
          format: 'doc-type',
        ),
        returnsNormally,
      );
    });

    test('f03/us03/fr01/e02: a non-string key is unknown_key by its text', () {
      final map = readYamlMap('1: a\n', file: _file);

      expect(
        () => checkKeys(map, {'id'}, file: _file, format: 'doc-type'),
        throwsA(_fault(FaultCode.unknownKey, key: '1')),
      );
    });
  });

  group('requireValue', () {
    test('f03/us03/fr01: returns the value of the right type', () {
      final map = readYamlMap('id: a\n', file: _file);

      expect(requireValue<String>(map, 'id', file: _file), 'a');
    });

    test('f03/us03/fr01, s03/inv10: a missing key is missing_key', () {
      final map = readYamlMap('id: a\n', file: _file);

      expect(
        () => requireValue<String>(map, 'path', file: _file, prefix: 'x.'),
        throwsA(_fault(FaultCode.missingKey, key: 'x.path')),
      );
    });

    test('f03/us03/fr01: a null value is missing_key', () {
      final map = readYamlMap('path:\n', file: _file);

      expect(
        () => requireValue<String>(map, 'path', file: _file),
        throwsA(_fault(FaultCode.missingKey, key: 'path')),
      );
    });

    test('f03/us03/fr01: a value of another type is unknown_value', () {
      final map = readYamlMap('id: 3\n', file: _file);

      expect(
        () => requireValue<String>(map, 'id', file: _file, prefix: 'x.'),
        throwsA(_fault(FaultCode.unknownValue, key: 'x.id')),
      );
    });
  });

  group('optionalValue', () {
    test('f03/us03/fr01: an absent key gives null', () {
      final map = readYamlMap('id: a\n', file: _file);

      expect(optionalValue<bool>(map, 'locked', file: _file), isNull);
    });

    test('f03/us03/fr01: a null value gives null', () {
      final map = readYamlMap('locked:\n', file: _file);

      expect(optionalValue<bool>(map, 'locked', file: _file), isNull);
    });

    test('f03/us03/fr01: a value of the right type is returned', () {
      final map = readYamlMap('locked: true\n', file: _file);

      expect(optionalValue<bool>(map, 'locked', file: _file), isTrue);
    });

    test('f03/us03/fr01: a nested map is returned as YamlMap', () {
      final map = readYamlMap('goal:\n  title: t\n', file: _file);

      expect(optionalValue<YamlMap>(map, 'goal', file: _file), isA<YamlMap>());
    });

    test('f03/us03/fr01/e05: a value of another type is unknown_value', () {
      final map = readYamlMap('locked: yes-please\n', file: _file);

      expect(
        () => optionalValue<bool>(map, 'locked', file: _file),
        throwsA(_fault(FaultCode.unknownValue, key: 'locked')),
      );
    });

    test('f03/us03/fr01/e05: a bool mismatch says true or false', () {
      final map = readYamlMap('locked: yes-please\n', file: _file);

      expect(
        () => optionalValue<bool>(map, 'locked', file: _file),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'locked').having(
            (f) => f.message,
            'message',
            'the key locked must be true or false',
          ),
        ),
      );
    });

    test('f03/us03/fr01/e05: a map mismatch says a mapping', () {
      final map = readYamlMap('goal: t\n', file: _file);

      expect(
        () => optionalValue<YamlMap>(map, 'goal', file: _file),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'goal').having(
            (f) => f.message,
            'message',
            'the key goal must be a mapping',
          ),
        ),
      );
    });
  });

  group('stringList', () {
    test('f03/us03/fr01: reads a list of strings', () {
      final map = readYamlMap('words: [a, b]\n', file: _file);

      expect(stringList(map, 'words', file: _file), ['a', 'b']);
    });

    test('f03/us03/fr01: an absent key gives a growable empty list', () {
      final map = readYamlMap('id: a\n', file: _file);

      final words = stringList(map, 'words', file: _file)..add('later');

      expect(words, ['later']);
    });

    test('f03/us03/fr01: a null value gives a growable empty list', () {
      final map = readYamlMap('words:\n', file: _file);

      final words = stringList(map, 'words', file: _file)..add('later');

      expect(words, ['later']);
    });

    test('f03/us03/fr01: a non-list value is unknown_value', () {
      final map = readYamlMap('words: a\n', file: _file);

      expect(
        () => stringList(map, 'words', file: _file, prefix: 'x.'),
        throwsA(
          _fault(
            FaultCode.unknownValue,
            key: 'x.words',
          ).having((f) => f.message, 'message', 'the key words must be a list'),
        ),
      );
    });

    test('f03/us03/fr01: a non-string element is unknown_value', () {
      final map = readYamlMap('words: [a, 2]\n', file: _file);

      expect(
        () => stringList(map, 'words', file: _file),
        throwsA(
          _fault(FaultCode.unknownValue, key: 'words').having(
            (f) => f.message,
            'message',
            'the key words must hold only strings',
          ),
        ),
      );
    });
  });
}
