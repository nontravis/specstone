/// A resolver a format run opened, and the call that closes it after the last
/// write.
final class OpenedResolver<R> {
  const new({
    required this.resolver,
    required this.close,
    this.lockWrites = _runUnlocked,
  });

  final R resolver;
  final void Function() close;

  /// Runs a group's journaled write while the opener holds the write lock of
  /// what [resolver] reads from; runs it as it is when the opener holds none.
  final void Function(void Function() write) lockWrites;
}

void _runUnlocked(void Function() write) => write();
