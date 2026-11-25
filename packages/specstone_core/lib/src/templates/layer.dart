/// The layer a doc-type file sits in: shipped, personal, or project.
enum LayerKind { shipped, personal, project }

/// Whether a layer holds a file at a layer-relative path.
///
/// Implemented by the disk and the shipped sources at load time.
abstract interface class LayerFiles {
  /// Whether the layer holds a file at [layerRelativePath].
  bool exists(String layerRelativePath);
}
