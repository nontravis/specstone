import 'dart:io';

/// The error every connect fails with under [withRefusedConnect].
const refusedConnect = SocketException('connection refused by the test');

/// Runs [body] with every socket connect failing at once with
/// [refusedConnect], so no port is dialed and no listener can answer.
T withRefusedConnect<T>(T Function() body) => IOOverrides.runZoned(
  body,
  socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) =>
      Future.error(refusedConnect),
);
