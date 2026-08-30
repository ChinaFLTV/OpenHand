import 'package:flutter/material.dart';

import '../model/workflow_definition.dart';

const double kWorkflowAnnotationBackgroundAlpha = 0.13;

Color workflowAnnotationAccentColor(
  WorkflowAnnotationTheme theme,
  ColorScheme colors,
) => theme == WorkflowAnnotationTheme.blue
    ? colors.primary
    : Color(theme.accentColorValue);

Color workflowAnnotationBackgroundColor(
  WorkflowAnnotationTheme theme,
  ColorScheme colors,
) => Color.alphaBlend(
  workflowAnnotationAccentColor(
    theme,
    colors,
  ).withValues(alpha: kWorkflowAnnotationBackgroundAlpha),
  colors.surfaceContainerLow,
);
