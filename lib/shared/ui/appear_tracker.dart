/// Tracks list item identities so only entries added after the first build
/// play their entrance animation.
class AppearTracker {
  final Set<String> _seen = <String>{};
  bool _initialBuildDone = false;

  /// Mark the initial population as done. Calls to [shouldAnimate] only
  /// return `true` once the initial build has completed — so the very
  /// first frame of an app launch never animates an existing list.
  void markInitialBuildDone() {
    _initialBuildDone = true;
  }

  /// Returns `true` iff this id should run its entrance animation.
  ///
  /// Specifically: the initial build must have completed AND this id
  /// must not have been seen yet.
  bool shouldAnimate(String id) {
    return _initialBuildDone && !_seen.contains(id);
  }

  /// Record that we have rendered [id]. Idempotent.
  void markSeen(String id) {
    _seen.add(id);
  }

  /// Drop bookkeeping for ids that are no longer present so a future
  /// re-appearance counts as new (e.g. user deletes a thread, then a
  /// snapshot restore brings it back).
  void retainOnly(Iterable<String> ids) {
    final keep = ids.toSet();
    _seen.removeWhere((id) => !keep.contains(id));
  }
}
