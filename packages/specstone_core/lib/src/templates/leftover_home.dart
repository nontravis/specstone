import 'package:specstone_core/src/templates/format_keys.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

/// One `leftover_homes:` entry of a `pack.yaml`: a leftover section or file
/// and the doc types its statements move to.
final class LeftoverHome {
  const new _({
    required this.docTypes,
    required this.sectionId,
    required this.header,
    required this.path,
    required this.to,
    required this.home,
  });

  /// Parses a `leftover_homes:` [node] of a `pack.yaml` read from [file].
  ///
  /// A null node gives no entries; entries keep file order. A missing key is
  /// `missing_key` and a key outside the entry's format is `unknown_key`,
  /// keyed `leftover_homes[<i>].<key>`. An entry holds `to` and `home`, then
  /// either `path`, or `doc_types` and `section: {id, header}`.
  static List<LeftoverHome> parseList(YamlNode? node, {required String file}) =>
      switch (node) {
        null => const <LeftoverHome>[],
        final YamlList list => [
          for (var i = 0; i < list.length; i++)
            _parse(list.nodes[i], i, file: file),
        ],
        _ => throw TemplateFault(
          FaultCode.unknownValue,
          'the key leftover_homes must be a list',
          file: file,
          key: 'leftover_homes',
        ),
      };

  static LeftoverHome _parse(YamlNode node, int i, {required String file}) {
    final prefix = 'leftover_homes[$i].';
    final map = switch (node) {
      final YamlMap map => map,
      _ => throw TemplateFault(
        FaultCode.unknownValue,
        'the leftover_homes entry must be a mapping',
        file: file,
        key: 'leftover_homes[$i]',
      ),
    };
    final isPath = map.containsKey('path');
    checkKeys(
      map,
      formatKeysAt(
        packFileFormat,
        'leftover_homes',
        variant: isPath ? 'path' : 'section',
      ),
      file: file,
      format: 'leftover_homes entry',
      prefix: prefix,
    );
    final to = _requireStrings(map, 'to', file: file, prefix: prefix);
    final home = requireValue<String>(map, 'home', file: file, prefix: prefix);
    if (isPath) {
      return LeftoverHome._(
        docTypes: const [],
        sectionId: null,
        header: null,
        path: requireValue<String>(map, 'path', file: file, prefix: prefix),
        to: to,
        home: home,
      );
    }
    final docTypes = _requireStrings(
      map,
      'doc_types',
      file: file,
      prefix: prefix,
    );
    final section = requireValue<YamlMap>(
      map,
      'section',
      file: file,
      prefix: prefix,
    );
    final sectionPrefix = '${prefix}section.';
    checkKeys(
      section,
      formatKeysAt(packFileFormat, 'leftover_homes.section'),
      file: file,
      format: 'leftover_homes section',
      prefix: sectionPrefix,
    );
    return LeftoverHome._(
      docTypes: docTypes,
      sectionId: requireValue<String>(
        section,
        'id',
        file: file,
        prefix: sectionPrefix,
      ),
      header: requireValue<String>(
        section,
        'header',
        file: file,
        prefix: sectionPrefix,
      ),
      path: null,
      to: to,
      home: home,
    );
  }

  static List<String> _requireStrings(
    YamlMap map,
    String key, {
    required String file,
    required String prefix,
  }) => stringsOf(
    requireValue<YamlList>(map, key, file: file, prefix: prefix),
    key,
    file: file,
    prefix: prefix,
  );

  /// The doc types whose leftover section this entry names; empty for a path
  /// entry.
  final List<String> docTypes;

  /// The id of the leftover section; null for a path entry.
  final String? sectionId;

  /// The header of the leftover section; null for a path entry.
  final String? header;

  /// The path pattern of the leftover file; null for a section entry.
  final String? path;

  /// The doc types [home] names.
  final List<String> to;

  /// One line saying where in the [to] types the leftover's statements go.
  final String home;
}
