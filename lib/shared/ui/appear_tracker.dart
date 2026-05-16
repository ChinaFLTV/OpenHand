/// Tiny helper that decides whether an entry "is new" relative to its
/// surrounding list, enabling per-item entrance animations (e.g. wrapping
/// with `AppearOnce`) without re-animating the whole list on first build.
///
/// Usage pattern:
///
/// ```dart
/// final tracker = AppearTracker();
/// // First build: prime the tracker with the existing ids so they are
/// // treated as "already seen". Nothing animates.
/// for (final id in initialIds) {
///   tracker.markSeen(id);
/// }
/// tracker.markInitialBuildDone();
///
/// // Subsequent builds: ask before adding to the tree.
/// for (final id in currentIds) {
///   final isNew = tracker.shouldAnimate(id);
///   tracker.markSeen(id);
///   // ... wrap with AppearOnce iff isNew
/// }
///
/// // After computing the new list, evict ids that are no longer present so
/// // a future re-appearance counts as new again.
/// tracker.retainOnly(currentIds);
/// ```
///
/// The class is intentionally framework-agnostic — there are no Flutter
/// imports here so it can be unit-tested cheaply without spinning up a
/// `WidgetTester`.
class AppearTracker {
  AppearTracker();

  final Set<String> _seen = <String>{};
  bool _initialBuildDone = false;

  /// True iff [shouldAnimate] would return `true` for an id that has not
  /// been seen yet.
  bool get isInitialBuildDone => _initialBuildDone;

  /// Visible for testing.
  Set<String> get seenIdsForTest => Set<String>.unmodifiable(_seen);

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
