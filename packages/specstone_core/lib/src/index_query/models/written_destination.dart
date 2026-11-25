/// A link destination as written, angle brackets dropped, and whether angle
/// brackets enclose it.
final class WrittenDestination {
  const new({required this.shown, required this.angle});

  final String shown;
  final bool angle;
}
