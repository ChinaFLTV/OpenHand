import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';
import 'animated_dialog.dart';
import 'motion_preference.dart';

/// 浮层进出场的起始缩放：略小于 1，避免弹出时的生硬跳变。
const double _kOverlayScaleBegin = 0.95;

/// 构建由 [AnimatedOverlayEntryController] 持有的动画浮层条目。
///
/// 调用方应把可见性信号和退场回调传给 [AnimatedOverlayContent]。
typedef AnimatedOverlayEntryBuilder =
    Widget Function(
      BuildContext context,
      ValueListenable<bool> visibility,
      VoidCallback onExitCompleted,
    );

/// 锚定到输入框等目标组件的动画浮层。
///
/// 统一处理点击外部关闭、ESC 关闭、跟随定位和全局菜单进退场动画，避免各功能
/// 重复拼装浮层骨架后出现行为偏差。
class OpenHandAnchoredAnimatedOverlay extends StatelessWidget {
  const OpenHandAnchoredAnimatedOverlay({
    super.key,
    required this.link,
    required this.targetAnchor,
    required this.followerAnchor,
    required this.offset,
    required this.constraints,
    required this.onDismiss,
    required this.visibility,
    required this.onExitCompleted,
    required this.child,
    this.customSettings,
  });

  final LayerLink link;
  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;
  final BoxConstraints constraints;
  final VoidCallback onDismiss;
  final ValueListenable<bool> visibility;
  final VoidCallback onExitCompleted;
  final Widget child;
  final DialogAnimationSettings? customSettings;

  @override
  Widget build(BuildContext context) {
    return OpenHandEscapeDismissScope(
      onDismiss: onDismiss,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onDismiss,
            ),
          ),
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: offset,
            child: TextFieldTapRegion(
              child: ConstrainedBox(
                constraints: constraints,
                child: AnimatedOverlayContent(
                  customSettings: customSettings,
                  visibility: visibility,
                  onExitCompleted: onExitCompleted,
                  alignment: followerAnchor,
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一管理 [OverlayEntry] 及其动画可见性信号。
///
/// 退场期间调用 [show] 会复用并重新打开原条目；[close] 播放退场动画，
/// [dispose] 同步释放。会话标识与代次可防止迟到回调误删替换后的条目。
class AnimatedOverlayEntryController {
  _AnimatedOverlayEntrySession? _session;
  int _generation = 0;
  bool _disposed = false;

  bool get hasEntry => _session != null;

  /// 重新打开当前条目，不创建替代条目。
  bool reopen({bool rebuild = false}) {
    if (_disposed) return false;
    final session = _session;
    if (session == null) return false;
    if (!session.visibility.value) {
      session.visibility.value = true;
    }
    if (rebuild) {
      _markSessionNeedsBuild(session);
    }
    return true;
  }

  /// 插入新条目，或重新打开并重建当前条目。
  ///
  /// 控制器释放后返回 false；插入失败时先释放未插入会话，再继续抛出异常。
  bool show({
    required OverlayState overlay,
    required AnimatedOverlayEntryBuilder builder,
    VoidCallback? onRemoved,
    bool rebuildIfPresent = true,
  }) {
    if (_disposed) return false;
    final current = _session;
    if (current != null) {
      current.builder = builder;
      current.onRemoved = onRemoved;
      reopen();
      if (rebuildIfPresent) {
        _markSessionNeedsBuild(current);
      }
      return true;
    }

    final session = _AnimatedOverlayEntrySession(
      generation: ++_generation,
      builder: builder,
      onRemoved: onRemoved,
    );
    session.onExitCompleted = () => _completeExit(session);
    session.entry = OverlayEntry(
      builder: (context) =>
          session.builder(context, session.visibility, session.onExitCompleted),
    );
    _session = session;
    try {
      overlay.insert(session.entry);
    } catch (_) {
      if (identical(_session, session)) {
        _session = null;
        _generation += 1;
      }
      session.entry.dispose();
      session.visibility.dispose();
      rethrow;
    }
    return true;
  }

  /// 重建当前条目，不改变可见性。
  ///
  /// 构建阶段的请求会合并到帧尾，避免跨树同步标脏；迟到回调只作用于
  /// 发起请求时仍然有效的会话。
  void markNeedsBuild() {
    final session = _session;
    if (session != null) _markSessionNeedsBuild(session);
  }

  void _markSessionNeedsBuild(_AnimatedOverlayEntrySession session) {
    if (_disposed ||
        !identical(_session, session) ||
        session.generation != _generation) {
      return;
    }
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      session.entry.markNeedsBuild();
      return;
    }
    if (session.rebuildScheduled) return;
    session.rebuildScheduled = true;
    scheduler.addPostFrameCallback((_) {
      session.rebuildScheduled = false;
      if (_disposed ||
          !identical(_session, session) ||
          session.generation != _generation) {
        return;
      }
      session.entry.markNeedsBuild();
    }, debugLabel: '动画浮层重建');
    scheduler.ensureVisualUpdate();
  }

  /// 启动退场动画；[immediately] 为 true 时同步移除。可安全重复调用。
  void close({bool immediately = false}) {
    final session = _session;
    if (session == null) return;
    if (immediately || _disposed) {
      _removeSession(session);
      return;
    }
    if (session.visibility.value) {
      session.visibility.value = false;
    }
  }

  void _completeExit(_AnimatedOverlayEntrySession session) {
    if (_disposed ||
        !identical(_session, session) ||
        session.generation != _generation ||
        session.visibility.value) {
      return;
    }
    _removeSession(session);
  }

  void _removeSession(_AnimatedOverlayEntrySession session) {
    if (!identical(_session, session) || session.generation != _generation) {
      return;
    }
    _session = null;
    _generation += 1;
    session.entry.remove();
    session.entry.dispose();
    session.visibility.dispose();
    session.onRemoved?.call();
  }

  /// 永久释放持有的条目。可安全重复调用。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final session = _session;
    if (session != null) {
      _removeSession(session);
    } else {
      _generation += 1;
    }
  }
}

class _AnimatedOverlayEntrySession {
  _AnimatedOverlayEntrySession({
    required this.generation,
    required this.builder,
    required this.onRemoved,
  });

  final int generation;
  final ValueNotifier<bool> visibility = ValueNotifier<bool>(true);
  AnimatedOverlayEntryBuilder builder;
  VoidCallback? onRemoved;
  late final OverlayEntry entry;
  late final VoidCallback onExitCompleted;
  bool rebuildScheduled = false;
}

/// 为悬停浮窗、工具提示和自动补全面板等浮层提供进退场动画。
///
/// 动效一律取自全局菜单动画设置；[customSettings] 供已自行解析过设置的宿主
/// 透传，不提供绕过全局设置的固定时长通道。
///
/// 所有者移除 [OverlayEntry] 时应传入 [visibility] 和 [onExitCompleted]；
/// 可见性变为 false 后先播放退场动画，完成后才通知所有者移除条目。
class AnimatedOverlayContent extends StatefulWidget {
  const AnimatedOverlayContent({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.customSettings,
    this.visibility,
    this.onExitCompleted,
  });

  final Widget child;

  /// 已由宿主解析好的动画设置；为空时读取全局菜单动画设置。
  final DialogAnimationSettings? customSettings;

  final Alignment alignment;

  /// 协调 [OverlayEntry] 退场的可选可见性信号。
  ///
  /// 省略时浮层在生命周期内始终可见，仅播放进场动画。
  final ValueListenable<bool>? visibility;

  /// [visibility] 变为 false 且退场完成后调用一次，所有者应在此移除条目。
  final VoidCallback? onExitCompleted;

  @override
  State<AnimatedOverlayContent> createState() => _AnimatedOverlayContentState();
}

class _AnimatedOverlayContentState extends State<AnimatedOverlayContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  // 首帧尚未拿到 SettingsController 时的占位值，didChangeDependencies 会立刻
  // 用全局菜单设置覆盖它。
  DialogAnimationSettings _settings = OpenHandMotionDefaults.menu;
  bool _animationsDisabled = false;
  SettingsController? _settingsController;
  bool _exitCompletionScheduled = false;
  bool _exitCompletionDelivered = false;
  int _exitCompletionGeneration = 0;

  bool get _isVisible => widget.visibility?.value ?? true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_handleAnimationStatus);
    widget.visibility?.addListener(_handleVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindSettingsController();
    _syncAnimationPreference();
  }

  @override
  void didUpdateWidget(covariant AnimatedOverlayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindSettingsController();
    if (oldWidget.visibility != widget.visibility) {
      oldWidget.visibility?.removeListener(_handleVisibilityChanged);
      widget.visibility?.addListener(_handleVisibilityChanged);
      _cancelExitCompletion();
      _exitCompletionDelivered = false;
    }
    if (oldWidget.onExitCompleted != widget.onExitCompleted &&
        !_exitCompletionDelivered) {
      // 取消持有旧所有者的帧后回调，随后用最新回调重新安排退场完成通知。
      _cancelExitCompletion();
    }
    if (oldWidget.customSettings != widget.customSettings ||
        oldWidget.alignment != widget.alignment ||
        oldWidget.visibility != widget.visibility ||
        oldWidget.onExitCompleted != widget.onExitCompleted) {
      _syncAnimationPreference();
    }
  }

  DialogAnimationSettings _resolveSettings() {
    return widget.customSettings ??
        openHandMotionSettingsFallbackOf(
          context,
          OpenHandMotionSettingsScope.menu,
        );
  }

  void _bindSettingsController() {
    SettingsController? nextController;
    if (widget.customSettings == null) {
      try {
        nextController = context.read<SettingsController>();
      } on ProviderNotFoundException {
        nextController = null;
      }
    }
    if (identical(_settingsController, nextController)) return;
    _settingsController?.removeListener(_handleSettingsChanged);
    _settingsController = nextController;
    _settingsController?.addListener(_handleSettingsChanged);
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    final resolved = _resolveSettings();
    final disabled =
        !openHandTickerMotionEnabled(context) ||
        openHandMotionDisabled(resolved);
    if (resolved == _settings && disabled == _animationsDisabled) return;
    setState(_syncAnimationPreference);
  }

  void _syncAnimationPreference() {
    final resolved = _resolveSettings();
    final disabled =
        !openHandTickerMotionEnabled(context) ||
        openHandMotionDisabled(resolved);
    _settings = resolved;
    _animationsDisabled = disabled;
    _controller
      ..duration = resolved.entranceDuration
      ..reverseDuration = resolved.exitDuration;
    if (disabled) {
      _controller.stop();
      _controller.value = _isVisible ? 1.0 : 0.0;
      if (!_isVisible) {
        _scheduleExitCompletion();
      }
      return;
    }
    _driveVisibility();
  }

  void _handleVisibilityChanged() {
    if (!mounted) return;
    if (_isVisible) {
      _cancelExitCompletion();
      _exitCompletionDelivered = false;
    }
    if (_animationsDisabled) {
      _controller.value = _isVisible ? 1.0 : 0.0;
      if (!_isVisible) {
        _scheduleExitCompletion();
      }
      return;
    }
    _driveVisibility();
  }

  void _driveVisibility() {
    if (_isVisible) {
      if (_controller.status != AnimationStatus.completed) {
        _controller.forward();
      }
      return;
    }
    if (_controller.status == AnimationStatus.dismissed) {
      _scheduleExitCompletion();
    } else {
      _controller.reverse();
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_isVisible) {
      _scheduleExitCompletion();
    }
  }

  void _scheduleExitCompletion() {
    if (_exitCompletionScheduled || _exitCompletionDelivered || _isVisible) {
      return;
    }
    final callback = widget.onExitCompleted;
    if (callback == null) return;
    _exitCompletionScheduled = true;
    final generation = ++_exitCompletionGeneration;
    final visibility = widget.visibility;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_exitCompletionScheduled ||
          generation != _exitCompletionGeneration ||
          widget.visibility != visibility) {
        return;
      }
      if (!_isVisible) {
        _exitCompletionScheduled = false;
        _exitCompletionDelivered = true;
        callback();
      } else {
        _cancelExitCompletion();
      }
    });
    // 禁用动画时没有 Ticker 主动请求下一帧，需确保退场回调仍能执行。
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _cancelExitCompletion() {
    _exitCompletionScheduled = false;
    _exitCompletionGeneration += 1;
  }

  @override
  void dispose() {
    widget.visibility?.removeListener(_handleVisibilityChanged);
    _settingsController?.removeListener(_handleSettingsChanged);
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  OpenHandAnimationTransitionProfile _transitionProfile() {
    return OpenHandAnimationTransitionProfile(
      alignment: widget.alignment,
      fadeScaleBegin: _kOverlayScaleBegin,
      expandScaleBegin: _kOverlayScaleBegin,
      rotateScaleBegin: _kOverlayScaleBegin,
      elasticScaleBegin: _kOverlayScaleBegin,
      springScaleBegin: _kOverlayScaleBegin,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_animationsDisabled) {
      return _isVisible ? widget.child : const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => buildAnimationStyleTransition(
        animation: _controller,
        settings: _settings,
        profile: _transitionProfile(),
        child: child!,
      ),
    );
  }
}
