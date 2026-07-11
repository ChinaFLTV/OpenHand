import 'package:flutter/widgets.dart';

/// Builds an [AnimatedSwitcher] stack without mounting duplicate keyed
/// transitions. Rapid cyclic changes such as A → B → A can otherwise leave an
/// outgoing A alive when the new A enters, which violates Flutter's sibling-key
/// invariant and crashes in debug builds.
Widget buildCollisionSafeAnimatedSwitcherLayout(
  Widget? currentChild,
  List<Widget> previousChildren,
) {
  final usedKeys = <Key>{};
  final currentKey = currentChild?.key;
  if (currentKey != null) usedKeys.add(currentKey);

  final uniquePreviousReversed = <Widget>[];
  for (final child in previousChildren.reversed) {
    final key = child.key;
    if (key == null || usedKeys.add(key)) {
      uniquePreviousReversed.add(child);
    }
  }

  return Stack(
    alignment: Alignment.center,
    children: <Widget>[
      ...uniquePreviousReversed.reversed,
      if (currentChild != null) currentChild,
    ],
  );
}
