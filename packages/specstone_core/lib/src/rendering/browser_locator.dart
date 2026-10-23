import 'package:specstone_core/src/rendering/browser_host.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

const _browserVariable = 'SPECSTONE_BROWSER';

const _linuxNames = [
  'google-chrome',
  'google-chrome-stable',
  'microsoft-edge',
  'microsoft-edge-stable',
  'chromium',
  'chromium-browser',
];

const _macPaths = [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
];

const _windowsBaseVariables = [
  'ProgramFiles',
  'ProgramFiles(x86)',
  'LocalAppData',
];
const _windowsChrome = r'Google\Chrome\Application\chrome.exe';
const _windowsEdge = r'Microsoft\Edge\Application\msedge.exe';
const _windowsChromium = r'Chromium\Application\chrome.exe';

/// Returns the browser program that prints the pdf.
///
/// A non-empty `SPECSTONE_BROWSER` is the only candidate; otherwise the first
/// runnable of Chrome, Edge, Chromium at their standard install paths.
///
/// Throws a `browserNotFound` [RenderFault] when no candidate is runnable.
String locateBrowser(BrowserHost host) {
  final named = host.environment[_browserVariable];
  if (named != null && named.isNotEmpty) {
    return _locateNamed(host, named);
  }
  for (final path in _standardPaths(host)) {
    if (host.isRunnable(path)) return path;
  }
  throw RenderFault(
    RenderFaultCode.browserNotFound,
    'no Chrome, Edge, or Chromium found: install one, name a browser in '
    '$_browserVariable, or build html with --format html',
  );
}

String _locateNamed(BrowserHost host, String named) {
  final isBareName = !named.contains('/') && !named.contains(r'\');
  final candidates = isBareName ? _onPath(host, named) : [named];
  for (final path in candidates) {
    if (host.isRunnable(path)) return path;
  }
  throw RenderFault(
    RenderFaultCode.browserNotFound,
    '$_browserVariable names $named, which is not a runnable program: '
    'fix the variable or unset it',
  );
}

Iterable<String> _standardPaths(BrowserHost host) => switch (host.os) {
  HostOs.macos => _macPaths,
  HostOs.linux => _linuxNames.expand((name) => _onPath(host, name)),
  HostOs.windows => _windowsPaths(host.environment),
};

Iterable<String> _windowsPaths(Map<String, String> environment) sync* {
  final bases = [
    for (final variable in _windowsBaseVariables)
      if (environment[variable] case final base? when base.isNotEmpty) base,
  ];
  for (final base in bases) {
    yield '$base\\$_windowsChrome';
  }
  for (final base in bases) {
    yield '$base\\$_windowsEdge';
  }
  final localAppData = environment['LocalAppData'];
  if (localAppData != null && localAppData.isNotEmpty) {
    yield '$localAppData\\$_windowsChromium';
  }
}

Iterable<String> _onPath(BrowserHost host, String name) {
  final isWindows = host.os == HostOs.windows;
  final separator = isWindows ? r'\' : '/';
  final directories = (host.environment['PATH'] ?? '')
      .split(isWindows ? ';' : ':')
      .where((directory) => directory.isNotEmpty);
  return [
    for (final directory in directories)
      '$directory${directory.endsWith(separator) ? '' : separator}$name',
  ];
}
