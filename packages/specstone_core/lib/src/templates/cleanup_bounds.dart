import 'dart:math';

import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

const _cleanupKey = 'cleanup';
const _bundlesMaxAgeHoursKey = 'bundles_max_age_hours';
const _bundlesMaxMbKey = 'bundles_max_mb';
const _reportsMaxAgeDaysKey = 'reports_max_age_days';

const _defaultBundlesMaxAgeHours = 24;
const _defaultBundlesMaxMb = 256;
const _defaultReportsMaxAgeDays = 7;

/// One MB is 1,000,000 bytes.
const _bytesPerMb = 1000000;

/// The span of a `DateTime`, 8.64e15 ms either side of the epoch;
/// `now.subtract` throws past it.
const _maxAgeMicroseconds = 8640000000000000000;

/// The largest hour or day count whose age `DateTime.subtract` accepts.
const int _maxHours = _maxAgeMicroseconds ~/ Duration.microsecondsPerHour;
const int _maxDays = _maxAgeMicroseconds ~/ Duration.microsecondsPerDay;

const int _maxInt = 0x7fffffffffffffff;

/// The largest MB count whose bytes fit an `int`.
const int _maxMb = _maxInt ~/ _bytesPerMb;

final _digitsOnly = RegExp(r'^[0-9]+$');

/// Whether [node] is an integer literal past `int` range, which the yaml
/// package reads as a double.
bool _isOverflowedInteger(YamlNode? node) =>
    node is YamlScalar &&
    node.value is double &&
    _digitsOnly.hasMatch(node.span.text);

/// The three bounds that keep `.specstone/bundles/` and `reports/` small.
final class CleanupBounds {
  const new({
    required this.bundlesMaxAge,
    required this.bundlesMaxBytes,
    required this.reportsMaxAge,
  });

  /// The bounds of a config with no `cleanup:` key.
  static const CleanupBounds defaults = CleanupBounds(
    bundlesMaxAge: Duration(hours: _defaultBundlesMaxAgeHours),
    bundlesMaxBytes: _defaultBundlesMaxMb * _bytesPerMb,
    reportsMaxAge: Duration(days: _defaultReportsMaxAgeDays),
  );

  /// Reads the `cleanup:` key of the config [map], a default for each absent
  /// bound.
  ///
  /// Throws `unknown_value` for a `cleanup` that is not a map and for a bound
  /// that is not a positive integer, and `unknown_key` for a key other than the
  /// three bounds. An age too long for `DateTime.subtract`, and a size too
  /// large for an `int`, clamp to the largest that fits.
  static CleanupBounds fromConfig(YamlMap map, {required String file}) {
    final bounds = optionalValue<YamlMap>(map, _cleanupKey, file: file);
    if (bounds == null) return defaults;
    checkKeys(
      bounds,
      {_bundlesMaxAgeHoursKey, _bundlesMaxMbKey, _reportsMaxAgeDaysKey},
      file: file,
      format: 'config',
      prefix: '$_cleanupKey.',
    );
    return _build((key) => _readBound(bounds, key, file: file));
  }

  /// Reads the `cleanup:` key of the config [map] as [fromConfig] does, except
  /// that each bound that does not read takes its default.
  ///
  /// Never throws; a `cleanup` that is not a map, and every key beside the
  /// three bounds, change nothing.
  static CleanupBounds fromConfigLeniently(YamlMap map) {
    final bounds = map[_cleanupKey];
    if (bounds is! YamlMap) return defaults;
    return _build((key) {
      try {
        return _readBound(bounds, key, file: '');
      } on TemplateFault {
        return null;
      }
    });
  }

  /// The age past which a saved bundle is deleted.
  final Duration bundlesMaxAge;

  /// The total size, in bytes, the saved bundles are trimmed to.
  final int bundlesMaxBytes;

  /// The age past which a saved agent report is deleted.
  final Duration reportsMaxAge;
}

CleanupBounds _build(int? Function(String key) read) {
  final hours = read(_bundlesMaxAgeHoursKey);
  final mb = read(_bundlesMaxMbKey);
  final days = read(_reportsMaxAgeDaysKey);
  const defaults = CleanupBounds.defaults;
  return CleanupBounds(
    bundlesMaxAge: hours == null
        ? defaults.bundlesMaxAge
        : Duration(hours: min(hours, _maxHours)),
    bundlesMaxBytes: mb == null
        ? defaults.bundlesMaxBytes
        : min(mb, _maxMb) * _bytesPerMb,
    reportsMaxAge: days == null
        ? defaults.reportsMaxAge
        : Duration(days: min(days, _maxDays)),
  );
}

int? _readBound(YamlMap bounds, String key, {required String file}) {
  if (_isOverflowedInteger(bounds.nodes[key])) return _maxInt;
  final value = optionalValue<int>(
    bounds,
    key,
    file: file,
    prefix: '$_cleanupKey.',
  );
  if (value == null) return null;
  if (value > 0) return value;
  throw TemplateFault(
    FaultCode.unknownValue,
    'the key $key must be a positive whole number',
    file: file,
    key: '$_cleanupKey.$key',
  );
}
