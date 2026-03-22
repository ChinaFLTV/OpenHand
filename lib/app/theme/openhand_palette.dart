import 'package:flutter/material.dart';

@immutable
class OpenHandPalette extends ThemeExtension<OpenHandPalette> {
  const OpenHandPalette({
    required this.canvasStart,
    required this.canvasEnd,
    required this.sidebarBackground,
    required this.contentBackground,
    required this.composerBackground,
    required this.highlight,
    required this.outlineSoft,
  });

  final Color canvasStart;
  final Color canvasEnd;
  final Color sidebarBackground;
  final Color contentBackground;
  final Color composerBackground;
  final Color highlight;
  final Color outlineSoft;

  @override
  OpenHandPalette copyWith({
    Color? canvasStart,
    Color? canvasEnd,
    Color? sidebarBackground,
    Color? contentBackground,
    Color? composerBackground,
    Color? highlight,
    Color? outlineSoft,
  }) {
    return OpenHandPalette(
      canvasStart: canvasStart ?? this.canvasStart,
      canvasEnd: canvasEnd ?? this.canvasEnd,
      sidebarBackground: sidebarBackground ?? this.sidebarBackground,
      contentBackground: contentBackground ?? this.contentBackground,
      composerBackground: composerBackground ?? this.composerBackground,
      highlight: highlight ?? this.highlight,
      outlineSoft: outlineSoft ?? this.outlineSoft,
    );
  }

  @override
  OpenHandPalette lerp(
    covariant ThemeExtension<OpenHandPalette>? other,
    double t,
  ) {
    if (other is! OpenHandPalette) {
      return this;
    }

    return OpenHandPalette(
      canvasStart: Color.lerp(canvasStart, other.canvasStart, t) ?? canvasStart,
      canvasEnd: Color.lerp(canvasEnd, other.canvasEnd, t) ?? canvasEnd,
      sidebarBackground:
          Color.lerp(sidebarBackground, other.sidebarBackground, t) ??
          sidebarBackground,
      contentBackground:
          Color.lerp(contentBackground, other.contentBackground, t) ??
          contentBackground,
      composerBackground:
          Color.lerp(composerBackground, other.composerBackground, t) ??
          composerBackground,
      highlight: Color.lerp(highlight, other.highlight, t) ?? highlight,
      outlineSoft: Color.lerp(outlineSoft, other.outlineSoft, t) ?? outlineSoft,
    );
  }
}
