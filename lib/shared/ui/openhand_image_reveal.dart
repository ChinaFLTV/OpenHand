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
    // 封面卡片父级是紧约束：expand 才能让 BoxFit.cover 铺满。内联图只有
    // max 约束，继续 loose，避免被撑到占位上限。
    return LayoutBuilder(
      builder: (context, constraints) {
        final fillParent = constraints.isTight;
        return AnimatedSwitcher(
          duration: inDuration,
          reverseDuration: outDuration,
          layoutBuilder: (currentChild, previousChildren) =>
              buildCollisionSafeAnimatedSwitcherLayout(
                currentChild,
                previousChildren,
                fit: fillParent ? StackFit.expand : StackFit.loose,
                clipBehavior: Clip.none,
              ),
          transitionBuilder: (transitionChild, animation) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: kOpenHandSwitchInCurve,
              reverseCurve: kOpenHandSwitchOutCurve,
            );
            final spring = CurvedAnimation(
              parent: animation,
              curve: kOpenHandEntranceCurve,
              reverseCurve: kOpenHandSpringExitCurve,
            );
            return FadeTransition(
              opacity: fade,
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[fade, spring]),
                builder: (context, child) {
                  final fadeT = fade.value.clamp(0.0, 1.0);
                  final springT = spring.value.clamp(0.0, 1.25);
                  return Transform.translate(
                    offset: Offset(0, (1 - fadeT) * slide),
                    child: Transform.scale(
                      scale: scaleFrom + (1 - scaleFrom) * springT,
                      child: child,
                    ),
                  );
                },
                child: transitionChild,
              ),
            );
          },
          child: KeyedSubtree(key: ValueKey<String>(stateKey), child: child),
        );
      },
    );
  }
}
