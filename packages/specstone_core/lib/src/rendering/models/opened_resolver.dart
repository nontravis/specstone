/// A resolver a format run opened, and the call that closes it after the last
/// write.
final class OpenedResolver<R> {
  const new({required this.resolver, required this.close});

  final R resolver;
  final void Function() close;
}
