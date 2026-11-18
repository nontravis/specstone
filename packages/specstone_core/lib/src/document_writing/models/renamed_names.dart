import 'package:specstone_core/src/doc_model/models/doc_address.dart';
import 'package:specstone_core/src/document_writing/models/typed_name.dart';

/// The new Name of each doc a change renames, by its doc type id and old Name.
final class RenamedNames {
  const new(this._newNames);

  final Map<TypedName, String> _newNames;

  bool get isEmpty => _newNames.isEmpty;

  bool get isNotEmpty => _newNames.isNotEmpty;

  /// Returns the new Name of the [typeId] doc called [name]; null when it is
  /// not renamed or [typeId] is null.
  String? newNameOf(String? typeId, String name) =>
      typeId == null ? null : _newNames[TypedName(typeId: typeId, name: name)];

  /// Returns the new Name every renamed doc called [name] takes; null when
  /// none is renamed or two disagree.
  String? agreedNewNameOf(String name) {
    final names = {
      for (final MapEntry(:key, :value) in _newNames.entries)
        if (key.name == name) value,
    };
    return names.length == 1 ? names.single : null;
  }

  /// Returns the new name of the doc [address] names, or null when it names no
  /// renamed doc or, bare, names renamed docs that disagree.
  String? newNameFor(DocAddress address) {
    final typeId = address.typeId;
    return typeId == null
        ? agreedNewNameOf(address.body)
        : newNameOf(typeId, address.body);
  }

  /// Whether [text] holds the old Name of a renamed doc.
  bool anyOldNameIn(String text) =>
      _newNames.keys.any((key) => text.contains(key.name));
}
