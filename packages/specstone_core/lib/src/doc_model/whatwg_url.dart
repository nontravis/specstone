import 'dart:convert';

// MARK: - Public

/// Whether the WHATWG URL Standard's basic URL parser returns failure on
/// [input] with a `file:` URL as its base.
///
/// UTS46 domain-to-ASCII does not run, since no IDNA mapping table ships
/// (doc_model RULE-11): a domain holding a non-ASCII code point or an
/// `xn--` label once percent-decoded reads, and only steps outside its host
/// can fail it.
bool whatwgParseFails(String input) {
  final url = _withoutStrayUnits(input);
  final scheme = _schemePattern.matchAsPrefix(url);
  if (scheme == null) return _fileFails(url, 0);
  final name = url.substring(0, scheme.end - 1).toLowerCase();
  if (name == 'file') return _fileFails(url, scheme.end);
  if (_specialNonFileSchemes.contains(name)) {
    return _authorityFails(
      url,
      _afterSlashes(url, scheme.end),
      isSpecial: true,
    );
  }
  if (url.startsWith('//', scheme.end)) {
    return _authorityFails(url, scheme.end + 2, isSpecial: false);
  }
  return false;
}

// MARK: - Constants

/// The special schemes but `file`, which has states of its own.
const _specialNonFileSchemes = {'ftp', 'http', 'https', 'ws', 'wss'};
const _maxPort = 65535;
const _maxIpv4Part = 255;
const _ipv6Pieces = 8;
const _maxIpv4TailStart = 6;
const _ipv4TailNumbers = 4;
const _maxIpv4Parts = 4;
const _maxPieceHexDigits = 4;
const _escapeLength = 3;
const _space = 0x20;
const _percentSign = 0x25;
const _delete = 0x7F;
const _maxAscii = 0x7F;

final _schemePattern = RegExp(r'[A-Za-z][A-Za-z0-9+.\-]*:');
final _tabOrNewline = RegExp('[\t\n\r]');
final _specialAuthorityEnd = RegExp(r'[/\\?#]');
final _authorityEnd = RegExp('[/?#]');
final _windowsDriveLetter = RegExp(r'^[A-Za-z][:|]$');
final _decimalDigits = RegExp(r'^[0-9]+$');
final _octalDigits = RegExp(r'^[0-7]+$');
final _hexDigits = RegExp(r'^[0-9A-Fa-f]+$');
final Set<int> _forbiddenHostUnits = '\u0000\t\n\r #/:<>?@[\\]^|'.codeUnits
    .toSet();

// MARK: - URL states

/// Trims leading and trailing C0 controls and spaces, then drops every tab
/// and newline, as the parser does before its first state.
String _withoutStrayUnits(String input) {
  var start = 0;
  var end = input.length;
  while (start < end && _isC0ControlOrSpace(input.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isC0ControlOrSpace(input.codeUnitAt(end - 1))) {
    end--;
  }
  return input.substring(start, end).replaceAll(_tabOrNewline, '');
}

/// Runs the file state from [start]; with a `file:` base it fails only in
/// the file host state, which two slashes (either one a `\`) open.
bool _fileFails(String url, int start) {
  if (!_isSlashAt(url, start) || !_isSlashAt(url, start + 1)) return false;
  final hostStart = start + 2;
  final host = url.substring(
    hostStart,
    _authorityEndFrom(url, hostStart, isSpecial: true),
  );
  if (host.isEmpty || _windowsDriveLetter.hasMatch(host)) return false;
  return _hostFails(host, isOpaque: false);
}

/// Runs the authority, host, and port states from [start].
bool _authorityFails(String url, int start, {required bool isSpecial}) {
  final authority = url.substring(
    start,
    _authorityEndFrom(url, start, isSpecial: isSpecial),
  );
  final atSign = authority.lastIndexOf('@');
  final hostAndPort = authority.substring(atSign + 1);
  if (atSign >= 0 && hostAndPort.isEmpty) return true;
  return _hostAndPortFails(hostAndPort, isSpecial: isSpecial);
}

bool _hostAndPortFails(String hostAndPort, {required bool isSpecial}) {
  final colon = _portColon(hostAndPort);
  final host = colon == null ? hostAndPort : hostAndPort.substring(0, colon);
  if (host.isEmpty && (colon != null || isSpecial)) return true;
  if (_hostFails(host, isOpaque: !isSpecial)) return true;
  return colon != null && _portFails(hostAndPort.substring(colon + 1));
}

/// Returns the index of the first `:` outside `[` and `]`, or null.
int? _portColon(String hostAndPort) {
  var isInsideBrackets = false;
  for (var index = 0; index < hostAndPort.length; index++) {
    switch (hostAndPort[index]) {
      case '[':
        isInsideBrackets = true;
      case ']':
        isInsideBrackets = false;
      case ':' when !isInsideBrackets:
        return index;
    }
  }
  return null;
}

bool _portFails(String port) {
  if (port.isEmpty) return false;
  if (!_decimalDigits.hasMatch(port)) return true;
  return BigInt.parse(port) > BigInt.from(_maxPort);
}

int _authorityEndFrom(String url, int start, {required bool isSpecial}) {
  final end = url.indexOf(
    isSpecial ? _specialAuthorityEnd : _authorityEnd,
    start,
  );
  return end < 0 ? url.length : end;
}

int _afterSlashes(String url, int start) {
  var index = start;
  while (_isSlashAt(url, index)) {
    index++;
  }
  return index;
}

bool _isSlashAt(String url, int index) =>
    index < url.length && (url[index] == '/' || url[index] == r'\');

bool _isC0ControlOrSpace(int unit) => unit <= _space;

// MARK: - Host parser

bool _hostFails(String input, {required bool isOpaque}) {
  if (input.startsWith('[')) {
    return !input.endsWith(']') ||
        _Ipv6Parser(input.substring(1, input.length - 1)).fails();
  }
  if (isOpaque) return input.codeUnits.any(_forbiddenHostUnits.contains);
  return _domainFails(_utf8Decoded(_percentDecoded(input)));
}

/// Runs the domain parser's checks after ToASCII, then the IPv4 parser.
bool _domainFails(String domain) {
  // ToASCII only lowercases an ASCII domain. Any other needs UTS46, whose
  // table does not ship, so its content reads (doc_model RULE-11).
  if (_needsUts46(domain)) return false;
  if (domain.codeUnits.any(_isForbiddenDomainUnit)) return true;
  return _endsInANumber(domain) && _ipv4Fails(domain);
}

/// Whether [domain] holds a code point above U+007F or a label opening
/// with `xn--`, ASCII case-insensitive.
bool _needsUts46(String domain) =>
    domain.codeUnits.any((unit) => unit > _maxAscii) ||
    domain.split('.').any((label) => label.toLowerCase().startsWith('xn--'));

bool _isForbiddenDomainUnit(int unit) =>
    _forbiddenHostUnits.contains(unit) ||
    _isC0Control(unit) ||
    unit == _percentSign ||
    unit == _delete;

bool _isC0Control(int unit) => unit < _space;

/// Returns the bytes of [text] in UTF-8, each `%` and two hex digits one
/// byte; a `%` without two hex digits stays as written.
List<int> _percentDecoded(String text) {
  final bytes = utf8.encode(text);
  final decoded = <int>[];
  var index = 0;
  while (index < bytes.length) {
    final escaped = bytes[index] == _percentSign
        ? _hexByte(bytes, index + 1)
        : null;
    decoded.add(escaped ?? bytes[index]);
    index += escaped == null ? 1 : _escapeLength;
  }
  return decoded;
}

int? _hexByte(List<int> bytes, int start) {
  if (start + 1 >= bytes.length) return null;
  final pair = String.fromCharCodes(bytes, start, start + 2);
  return _hexDigits.hasMatch(pair) ? int.parse(pair, radix: 16) : null;
}

String _utf8Decoded(List<int> bytes) =>
    // Dart drops a leading BOM, which the standard keeps; UTS46 ignores
    // U+FEFF, so the parser's result is the same.
    utf8.decode(bytes, allowMalformed: true);

// MARK: - IPv4 parser

bool _endsInANumber(String domain) {
  final last = _ipv4Parts(domain).last;
  return _decimalDigits.hasMatch(last) || _ipv4Number(last) != null;
}

bool _ipv4Fails(String domain) {
  final parts = _ipv4Parts(domain);
  if (parts.length > _maxIpv4Parts) return true;
  final numbers = <BigInt>[];
  for (final part in parts) {
    final number = _ipv4Number(part);
    if (number == null) return true;
    numbers.add(number);
  }
  final last = numbers.removeLast();
  // The last part fills every byte the parts before it leave.
  final lastBytes = _maxIpv4Parts - numbers.length;
  final lastLimit = BigInt.from(_maxIpv4Part + 1).pow(lastBytes);
  return numbers.any((n) => n > BigInt.from(_maxIpv4Part)) || last >= lastLimit;
}

/// Splits [domain] on `.`, without a trailing empty part.
List<String> _ipv4Parts(String domain) {
  final parts = domain.split('.');
  if (parts.length > 1 && parts.last.isEmpty) parts.removeLast();
  return parts;
}

/// Parses [part] as decimal, octal after a `0`, or hex after `0x`; null
/// when it is not a number.
BigInt? _ipv4Number(String part) {
  if (part.isEmpty) return null;
  final (digits, radix, pattern) = switch (part) {
    _ when part.startsWith('0x') || part.startsWith('0X') => (
      part.substring(2),
      16,
      _hexDigits,
    ),
    _ when part.length > 1 && part.startsWith('0') => (
      part.substring(1),
      8,
      _octalDigits,
    ),
    _ => (part, 10, _decimalDigits),
  };
  if (digits.isEmpty) return BigInt.zero;
  return pattern.hasMatch(digits) ? BigInt.parse(digits, radix: radix) : null;
}

// MARK: - IPv6 parser

/// Runs the IPv6 parser's failure steps over the text inside `[` and `]`.
final class _Ipv6Parser {
  new(this._text);

  final String _text;
  var _pointer = 0;
  var _pieceIndex = 0;
  var _hasCompress = false;

  /// The code unit at the pointer as a string; null at the end.
  String? get _c => _pointer < _text.length ? _text[_pointer] : null;

  bool fails() {
    if (_c == ':') {
      if (!_text.startsWith(':', _pointer + 1)) return true;
      _pointer += 2;
      _compress();
    }
    while (_c != null) {
      if (_pieceIndex == _ipv6Pieces) return true;
      if (_c == ':') {
        if (_hasCompress) return true;
        _pointer++;
        _compress();
      } else if (_pieceFails()) {
        return true;
      }
    }
    return !_hasCompress && _pieceIndex != _ipv6Pieces;
  }

  void _compress() {
    _pieceIndex++;
    _hasCompress = true;
  }

  /// Reads up to four hex digits, or hands a dotted tail to the IPv4 steps.
  bool _pieceFails() {
    final start = _pointer;
    while (_pointer - start < _maxPieceHexDigits && _isHexDigit(_c)) {
      _pointer++;
    }
    if (_c == '.') {
      if (_pointer == start) return true;
      _pointer = start;
      return _pieceIndex > _maxIpv4TailStart || _ipv4TailFails();
    }
    if (_c == ':') {
      _pointer++;
      if (_c == null) return true;
    } else if (_c != null) {
      return true;
    }
    _pieceIndex++;
    return false;
  }

  /// Reads the dotted IPv4 tail to the end of the text.
  bool _ipv4TailFails() {
    var numbersSeen = 0;
    while (_c != null) {
      if (numbersSeen > 0) {
        if (_c != '.' || numbersSeen >= _ipv4TailNumbers) return true;
        _pointer++;
      }
      if (_ipv4PieceFails()) return true;
      numbersSeen++;
      if (numbersSeen.isEven) _pieceIndex++;
    }
    return numbersSeen != _ipv4TailNumbers;
  }

  bool _ipv4PieceFails() {
    if (!_isDigit(_c)) return true;
    int? piece;
    while (_isDigit(_c)) {
      if (piece == 0) return true;
      piece = (piece ?? 0) * 10 + _text.codeUnitAt(_pointer) - 0x30;
      if (piece > _maxIpv4Part) return true;
      _pointer++;
    }
    return false;
  }

  bool _isDigit(String? c) => c != null && _decimalDigits.hasMatch(c);

  bool _isHexDigit(String? c) => c != null && _hexDigits.hasMatch(c);
}
