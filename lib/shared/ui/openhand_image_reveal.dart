import 'package:flutter/material.dart';

import 'collision_safe_animated_switcher.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_spacing.dart';
import 'openhand_sweep_shimmer.dart';

/// 大图（会话正文、预览弹窗、媒体卡片）首帧显现时长。
const Duration kOpenHandImageRevealDuration = kOpenHandMotion400;

/// 图片切换或卸载时的收起时长，略短于进场，收得干脆。
const Duration kOpenHandImageRevealHideDuration = kOpenHandMotion280;

const double kOpenHandImageRevealSlide = 8;
const double kOpenHandImageRevealScaleFrom = 0.97;
const double kOpenHandImageRevealCompactSlide = 4;
const double kOpenHandImageRevealCompactScaleFrom = 0.92;
const double _kImageShimmerIconSize = 48;
const double _kImageShimmerCompactIconSize = 18;
const double _kImageShimmerFallbackExtent = 48;
const double _kImageShimmerCompactFallbackExtent = 24;

/// 解码完成前的骨架占位，避免空白闪一下。
class OpenHandImageShimmerPlaceholder extends StatelessWidget {
  const OpenHandImageShimmerPlaceholder({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = Center(
      child: Icon(
        Icons.image_outlined,
        size: compact ? _kImageShimmerCompactIconSize : _kImageShimmerIconSize,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final expand =
            constraints.hasBoundedWidth &&
            constraints.hasBoundedHeight &&
            constraints.maxWidth < double.infinity &&
            constraints.maxHeight < double.infinity;
        return OpenHandSkeletonShimmer(
          expand: expand,
          width: expand
              ? null
              : (compact
                    ? _kImageShimmerCompactFallbackExtent
                    : _kImageShimmerFallbackExtent),
          height: expand
              ? null
              : (compact
                    ? _kImageShimmerCompactFallbackExtent
                    : _kImageShimmerFallbackExtent),
          borderRadius: compact
              ? kOpenHandBorderRadius10
              : kOpenHandBorderRadius12,
          period: kOpenHandMotion1200,
          child: icon,
        );
      },
    );
  }
}

/// 标准尺寸图片的 [Image.frameBuilder]：加载骨架 → Q 弹淡入。
Widget openHandImageRevealFrameBuilder(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  return _openHandImageRevealFrame(
    context,
    child,
    frame,
    wasSynchronouslyLoaded,
    compact: false,
  );
}

/// 头像 / 缩略图的 [Image.frameBuilder]，位移与缩放更克制。
Widget openHandCompactImageRevealFrameBuilder(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  return _openHandImageRevealFrame(
    context,
    child,
    frame,
    wasSynchronouslyLoaded,
    compact: true,
  );
}

Widget _openHandImageRevealFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded, {
  required bool compact,
}) {
  if (wasSynchronouslyLoaded) return child;
  final ready = frame != null;
  return OpenHandImageRevealSwitcher(
    stateKey: ready ? 'ready' : 'loading',
    compact: compact,
    child: ready
        ? child
        : Stack(
            alignment: Alignment.center,
            children: [
              Opacity(opacity: 0, child: child),
              Positioned.fill(
                child: OpenHandImageShimmerPlaceholder(compact: compact),
              ),
            ],
          ),
  );
}

/// 同一槽位里图片的加载完成、替换、失败回退都走淡入缩放，而不是生硬切页。
class OpenHandImageRevealSwitcher extends StatelessWidget {
  const OpenHandImageRevealSwitcher({
    super.key,
    required this.stateKey,
    required this.child,
    this.compact = false,
    this.duration = kOpenHandImageRevealDuration,
    this.hideDuration = kOpenHandImageRevealHideDuration,
  });

  final String stateKey;
  final Widget child;
  final bool compact;
  final Duration duration;
  final Duration hideDuration;

  @override
  Widget build(BuildContext context) {
    final inDuration = openHandMotionDuration(context, duration);
    if (inDuration == Duration.zero) return child;
    final outDuration = openHandMotionDuration(context, hideDuration);
    final slide = compact
        ? kOpenHandImageRevealCompactSlide
        : kOpenHandImageRevealSlide;
    final scaleFrom = compact
        ? kOpenHandImageRevealCompactScaleFrom
        : kOpenHandImageRevealScaleFrom;
    // 直接传递约束：封面保持铺满，内联图按内容收缩，并兼容消息气泡预布局。
    return AnimatedSwitcher(
      duration: inDuration,
      reverseDuration: outDuration,
      layoutBuilder: (currentChild, previousChildren) =>
          buildCollisionSafeAnimatedSwitcherLayout(
            currentChild,
            previousChildren,
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
          ),
      transitionBuilder: (transitionChild, animation) => _ImageRevealTransition(
        animation: animation,
        slide: slide,
        scaleFrom: scaleFrom,
        child: transitionChild,
      ),
      child: KeyedSubtree(key: ValueKey<String>(stateKey), child: child),
    );
  }
}

/// 曲线随过渡节点存活，重建不重复注册监听，中途反向保留当前曲线进度。
class _ImageRevealTransition extends StatefulWidget {
  const _ImageRevealTransition({
    required this.animation,
    required this.slide,
    required this.scaleFrom,
    required this.child,
  });

  final Animation<double> animation;
  final double slide;
  final double scaleFrom;
  final Widget child;

  @override
  State<_ImageRevealTransition> createState() => _ImageRevealTransitionState();
}

class _ImageRevealTransitionState extends State<_ImageRevealTransition> {
  late CurvedAnimation _fade;
  late CurvedAnimation _spring;

  @override
  void initState() {
    super.initState();
    _configureCurves();
  }

  @override
  void didUpdateWidget(covariant _ImageRevealTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    _fade.dispose();
    _spring.dispose();
    _configureCurves();
  }

  void _configureCurves() {
    _fade = CurvedAnimation(
      parent: widget.animation,
      curve: kOpenHandSwitchInCurve,
      reverseCurve: kOpenHandSwitchOutCurve,
    );
    _spring = CurvedAnimation(
      parent: widget.animation,
      curve: kOpenHandEntranceCurve,
      reverseCurve: kOpenHandSpringExitCurve,
    );
  }

  @override
  void dispose() {
    _fade.dispose();
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: AnimatedBuilder(
        animation: widget.animation,
        builder: (context, child) {
          final fadeT = _fade.value.clamp(0.0, 1.0);
          final springT = _spring.value.clamp(0.0, 1.25);
          return Transform.translate(
            offset: Offset(0, (1 - fadeT) * widget.slide),
            child: Transform.scale(
              scale: widget.scaleFrom + (1 - widget.scaleFrom) * springT,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
