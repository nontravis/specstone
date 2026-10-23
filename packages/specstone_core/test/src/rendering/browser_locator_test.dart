import 'package:specstone_core/src/rendering/browser_host.dart';
import 'package:specstone_core/src/rendering/browser_locator.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

const _macChrome =
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const _macChromium = '/Applications/Chromium.app/Contents/MacOS/Chromium';

const _noBrowserMessage =
    'no Chrome, Edge, or Chromium found: install one, name a browser in '
    'SPECSTONE_BROWSER, or build html with --format html';

BrowserHost _host({
  required HostOs os,
  Set<String> runnable = const {},
  Map<String, String> environment = const {},
}) => BrowserHost(
  environment: environment,
  os: os,
  isRunnable: runnable.contains,
  runProcess: (executable, arguments, {required timeout}) =>
      fail('locateBrowser must not run a process: $executable'),
);

RenderFault _faultOf(BrowserHost host) {
  try {
    locateBrowser(host);
  } on RenderFault catch (fault) {
    return fault;
  }
  fail('locateBrowser returned instead of throwing');
}

void main() {
  group('locateBrowser standard paths', () {
    test('f05/us03/fr01: macOS prefers Chrome over Chromium', () {
      final host = _host(
        os: HostOs.macos,
        runnable: {_macChromium, _macChrome},
      );

      expect(locateBrowser(host), _macChrome);
    });

    test('f05/us03/fr01: macOS falls to Edge, then Chromium', () {
      const edge =
          '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge';

      expect(
        locateBrowser(_host(os: HostOs.macos, runnable: {_macChromium, edge})),
        edge,
      );
      expect(
        locateBrowser(_host(os: HostOs.macos, runnable: {_macChromium})),
        _macChromium,
      );
    });

    test('f05/us03/fr01/e04: Linux takes Edge before Chromium along PATH', () {
      final host = _host(
        os: HostOs.linux,
        environment: {'PATH': '/usr/local/bin:/usr/bin'},
        runnable: {'/usr/bin/microsoft-edge', '/usr/bin/chromium'},
      );

      expect(locateBrowser(host), '/usr/bin/microsoft-edge');
    });

    test('NFR-Po01: Linux finds each name on PATH', () {
      final environment = {'PATH': '/usr/local/bin:/usr/bin'};

      expect(
        locateBrowser(
          _host(
            os: HostOs.linux,
            environment: environment,
            runnable: {'/usr/bin/google-chrome-stable'},
          ),
        ),
        '/usr/bin/google-chrome-stable',
      );
      expect(
        locateBrowser(
          _host(
            os: HostOs.linux,
            environment: environment,
            runnable: {'/usr/local/bin/chromium-browser'},
          ),
        ),
        '/usr/local/bin/chromium-browser',
      );
    });

    test('NFR-Po01: Linux searches PATH in order and skips empty entries', () {
      final host = _host(
        os: HostOs.linux,
        environment: {'PATH': ':/opt/bin/:/usr/bin'},
        runnable: {'/opt/bin/chromium', '/usr/bin/chromium'},
      );

      expect(locateBrowser(host), '/opt/bin/chromium');
    });

    test('NFR-Po01: Windows tries ProgramFiles(x86) for Chrome', () {
      const chrome =
          r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe';
      final host = _host(
        os: HostOs.windows,
        environment: {'ProgramFiles(x86)': r'C:\Program Files (x86)'},
        runnable: {chrome},
      );

      expect(locateBrowser(host), chrome);
    });

    test('NFR-Po01: Windows finds Chromium under LocalAppData only', () {
      const chromium =
          r'C:\Users\o\AppData\Local\Chromium\Application\chrome.exe';
      final host = _host(
        os: HostOs.windows,
        environment: {'LocalAppData': r'C:\Users\o\AppData\Local'},
        runnable: {chromium},
      );

      expect(locateBrowser(host), chromium);
    });

    test('NFR-Po01: Windows orders bases and skips an unset one', () {
      const programFiles =
          r'C:\Program Files\Microsoft\Edge\Application\msedge.exe';
      const localAppData =
          r'C:\Users\o\AppData\Local\Microsoft\Edge\Application\msedge.exe';
      final host = _host(
        os: HostOs.windows,
        environment: {
          'ProgramFiles': r'C:\Program Files',
          'LocalAppData': r'C:\Users\o\AppData\Local',
        },
        runnable: {localAppData, programFiles},
      );

      expect(locateBrowser(host), programFiles);
    });

    for (final os in HostOs.values) {
      test(
        'f05/us03/fr01/e01: nothing runnable on $os is browser_not_found',
        () {
          final fault = _faultOf(
            _host(
              os: os,
              environment: {
                'PATH': '/usr/bin',
                'ProgramFiles': r'C:\Program Files',
                'ProgramFiles(x86)': r'C:\Program Files (x86)',
                'LocalAppData': r'C:\Users\o\AppData\Local',
              },
            ),
          );

          expect(fault.code, RenderFaultCode.browserNotFound);
          expect(fault.exitStatus, 69);
          expect(fault.message, _noBrowserMessage);
        },
      );
    }
  });

  group('locateBrowser SPECSTONE_BROWSER', () {
    test(
      'f05/us03/fr01/e03: a named program that is not runnable is a fault',
      () {
        final host = _host(
          os: HostOs.macos,
          environment: {'SPECSTONE_BROWSER': '/opt/none/chrome'},
          runnable: {_macChrome},
        );

        final fault = _faultOf(host);

        expect(fault.code, RenderFaultCode.browserNotFound);
        expect(
          fault.message,
          'SPECSTONE_BROWSER names /opt/none/chrome, which is not a runnable '
          'program: fix the variable or unset it',
        );
      },
    );

    test('f05/us03/fr01: a runnable named path wins', () {
      final host = _host(
        os: HostOs.macos,
        environment: {'SPECSTONE_BROWSER': '/opt/chrome'},
        runnable: {'/opt/chrome', _macChrome},
      );

      expect(locateBrowser(host), '/opt/chrome');
    });

    test('f05/us03/fr01: a bare name is looked up on PATH', () {
      final host = _host(
        os: HostOs.linux,
        environment: {'SPECSTONE_BROWSER': 'chromium', 'PATH': '/bin:/usr/bin'},
        runnable: {'/usr/bin/chromium'},
      );

      expect(locateBrowser(host), '/usr/bin/chromium');
    });

    test('f05/us03/fr01: on Windows a bare name with no extension is also '
        'tried as <name>.exe on PATH', () {
      final host = _host(
        os: HostOs.windows,
        environment: {
          'SPECSTONE_BROWSER': 'chrome',
          'PATH': r'C:\bin;C:\tools',
        },
        runnable: {r'C:\tools\chrome.exe'},
      );

      expect(locateBrowser(host), r'C:\tools\chrome.exe');
    });

    test('f05/us03/fr01: on Windows a bare name with an extension is not '
        'given .exe', () {
      final host = _host(
        os: HostOs.windows,
        environment: {'SPECSTONE_BROWSER': 'chrome.cmd', 'PATH': r'C:\bin'},
        runnable: {r'C:\bin\chrome.cmd.exe'},
      );

      expect(_faultOf(host).code, RenderFaultCode.browserNotFound);
    });

    test('f05/us03/fr01/e03: a bare name missing from PATH is a fault', () {
      final host = _host(
        os: HostOs.linux,
        environment: {'SPECSTONE_BROWSER': 'chromium', 'PATH': '/usr/bin'},
        runnable: {'/usr/bin/google-chrome'},
      );

      expect(
        _faultOf(host).message,
        'SPECSTONE_BROWSER names chromium, which is not a runnable program: '
        'fix the variable or unset it',
      );
    });

    test('f05/us03/fr01/e05: an empty value counts as unset', () {
      expect(
        locateBrowser(
          _host(
            os: HostOs.macos,
            environment: {'SPECSTONE_BROWSER': ''},
            runnable: {_macChrome},
          ),
        ),
        _macChrome,
      );

      final fault = _faultOf(
        _host(os: HostOs.macos, environment: {'SPECSTONE_BROWSER': ''}),
      );

      expect(fault.message, _noBrowserMessage);
    });
  });
}
