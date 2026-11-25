/// One task ref entry: an item of the same doc and a task id, or a task id
/// alone for the whole doc.
final class TaskRef {
  const new _({required this.item, required this.task});

  /// The item the ref names, or null for a whole-doc ref.
  final String? item;

  /// The task id, non-empty and free of `:`.
  final String task;

  bool get isWholeDoc => item == null;

  /// Whether [task] can be a task id: not empty and free of `:`.
  static bool isTaskId(String task) => task.isNotEmpty && !task.contains(':');

  /// Returns the ref of [entry], split at its last `:`, or null when the entry
  /// has an empty task or, with a `:`, an empty item.
  static TaskRef? parse(String entry) {
    final colon = entry.lastIndexOf(':');
    final item = colon < 0 ? null : entry.substring(0, colon);
    final task = entry.substring(colon + 1);
    if (task.isEmpty || (item != null && item.isEmpty)) return null;
    return TaskRef._(item: item, task: task);
  }
}
