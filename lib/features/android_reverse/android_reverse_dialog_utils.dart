import 'package:flutter/material.dart';

import '../../shared/ui/animated_dialog.dart';

const OpenHandAnimationTransitionProfile kAndroidReverseDialogMotionProfile =
    OpenHandAnimationTransitionProfile(
      fadeScaleBegin: 0.88,
      expandScaleBegin: 0.80,
      rotateScaleBegin: 0.86,
      elasticScaleBegin: 0.86,
      springScaleBegin: 0.84,
      slideUpOffset: Offset(0, 0.20),
      slideDownOffset: Offset(0, -0.16),
      slideLeftOffset: Offset(-0.20, 0),
      slideRightOffset: Offset(0.20, 0),
    );

/// 使用 Android 逆向模块统一动效参数的工具弹窗入口。
const OpenHandProfiledDialogPresenter androidReverseToolDialogs =
    OpenHandProfiledDialogPresenter(kAndroidReverseDialogMotionProfile);
