/// Returns [id] in sentence case, such as `content_pillars` to `Content
/// pillars`.
String sentenceCase(String id) {
  final words = id.replaceAll('_', ' ');
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
