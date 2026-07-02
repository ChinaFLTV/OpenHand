import 'package:flutter/material.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_motion_surface.dart';

const OpenHandAnimationTransitionProfile kWebReverseDialogMotionProfile =
    OpenHandAnimationTransitionProfile(
      fadeScaleBegin: 0.925,
      expandScaleBegin: 0.86,
      rotateScaleBegin: 0.88,
      elasticScaleBegin: 0.90,
      springScaleBegin: 0.90,
      slideUpOffset: Offset(0, 0.16),
      slideDownOffset: Offset(0, -0.14),
      slideLeftOffset: Offset(-0.18, 0),
      slideRightOffset: Offset(0.18, 0),
    );

/// Shows a Web Reverse tool dialog with one feature-level motion profile.
///
/// The route still reads the global dialog animation settings through
/// [showAnimatedDialog]; this helper only centralizes the Web Reverse
/// transition geometry so all tool dialogs can be tuned in one place.
Future<T?> showWebReverseToolDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  AlignmentGeometry alignment = Alignment.center,
  bool surfaceMotion = false,
}) {
  return showAnimatedDialog<T>(
    context: context,
    settings: settings,
    transitionProfile: kWebReverseDialogMotionProfile,
    barrierDismissible: barrierDismissible,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    alignment: alignment,
    builder: surfaceMotion
        ? (dialogContext) => OpenHandDialogMotionSurface(
            transitionProfile: kWebReverseDialogMotionProfile,
            child: builder(dialogContext),
          )
        : builder,
  );
}
