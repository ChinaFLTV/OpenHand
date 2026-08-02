/// 跟踪列表项，使首帧后的新增项才播放进场动画。
class AppearTracker {
  final Set<String> _seen = <String>{};
  bool _initialBuildDone = false;

  /// 标记首批内容已完成构建。
  void markInitialBuildDone() {
    _initialBuildDone = true;
  }

  /// 首批构建完成且标识从未出现时返回 `true`。
  bool shouldAnimate(String id) {
    return _initialBuildDone && !_seen.contains(id);
  }

  /// 记录已渲染的 [id]，可重复调用。
  void markSeen(String id) {
    _seen.add(id);
  }

  /// 移除已不存在的标识，使后续重新出现时视为新增项。
  void retainOnly(Iterable<String> ids) {
    final keep = ids.toSet();
    _seen.removeWhere((id) => !keep.contains(id));
  }
}
