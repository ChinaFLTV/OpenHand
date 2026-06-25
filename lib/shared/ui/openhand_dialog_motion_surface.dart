import 'package:flutter/material.dart';

import 'animated_dialog.dart';

/// Content-level motion layer for large dialog surfaces.
///
/// `showAnimatedDialog` already animates the route. Full dashboard-sized
/// dialogs can still feel abrupt because the content spans most of the
/// viewport; this wrapper reuses the same dialog animation settings on the
/// content surface so entrance and exit remain visibly springy while still
/// honoring global motion settings and reduce-motion.
class OpenHandDialogMotionSurface extends StatelessWidget {
  const OpenHandDialogMotionSurface({
    super.key,
    required this.child,
    this.transitionProfile = const OpenHandAnimationTransitionProfile(
      fadeScaleBegin: 0.965,
      springScaleBegin: 0.955,
      elasticScaleBegin: 0.95,
      expandScaleBegin: 0.955,
    ),
  });

  final Widget child;
  final OpenHandAnimationTransitionProfile transitionProfile;

  @override
  Widget build(BuildContext context) {
    return buildOpenHandDialogMotionSurface(
      context: context,
      child: child,
      transitionProfile: transitionProfile,
    );
  }
}
