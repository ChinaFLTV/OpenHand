import 'package:flutter/material.dart';

import 'openhand_spacing.dart';

const double kOpenHandInputIconInset = 4;
const double kOpenHandInputIconExtent = 32;

/// 输入框内的图标操作保留四周间隙，紧凑输入框按可用空间收缩。
class OpenHandInputIconAction extends StatelessWidget {
  const OpenHandInputIconAction({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(kOpenHandInputIconInset),
    child: Center(
      widthFactor: 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: kOpenHandInputIconExtent,
          maxHeight: kOpenHandInputIconExtent,
        ),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: (IconButtonTheme.of(context).style ?? const ButtonStyle())
                .merge(
                  const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size.zero),
                    padding: WidgetStatePropertyAll(EdgeInsets.zero),
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: kOpenHandBorderRadius8,
                      ),
                    ),
                  ),
                ),
          ),
          child: child,
        ),
      ),
    ),
  );
}
