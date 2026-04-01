import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An elegant, Material You inspired animated loading logo for OpenHand.
/// Features a beautifully proportioned squircle background with pulsing,
/// intersecting orbital rings and a color-shifting AI spark at its core.
class OpenHandLoadingLogo extends StatefulWidget {
  const OpenHandLoadingLogo({super.key});

  @override
  State<OpenHandLoadingLogo> createState() => _OpenHandLoadingLogoState();
}

class _OpenHandLoadingLogoState extends State<OpenHandLoadingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Elegant Material You theming
    final containerColor = colorScheme.surfaceContainerHigh;
    final primaryColor = colorScheme.primary;
    final tertiaryColor = colorScheme.tertiary;

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.85, end: 1.0),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.elasticOut,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: SizedBox(
          width: 140,
          height: 140,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer orbiting, breathing rings
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) {
                    final t = _animController.value;
                    return CustomPaint(
                      size: const Size(100, 100),
                      painter: _AiRingsPainter(
                        progress: t,
                        color1: primaryColor.withValues(alpha: 0.6),
                        color2: tertiaryColor.withValues(alpha: 0.6),
                      ),
                    );
                  },
                ),
                // Center AI Spark
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) {
                    // Smooth rocking rotation
                    final rotation = math.sin(_animController.value * math.pi * 2) * 0.2;
                    return Transform.rotate(
                      angle: rotation,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 42,
                        color: Color.lerp(
                          primaryColor,
                          tertiaryColor,
                          (math.sin(_animController.value * math.pi * 1) + 1) / 2,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiRingsPainter extends CustomPainter {
  _AiRingsPainter({
    required this.progress,
    required this.color1,
    required this.color2,
  });

  final double progress;
  final Color color1;
  final Color color2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Smooth breathing sine wave based on progress
    final breath = (math.sin(progress * math.pi * 2) + 1) / 2;

    final paint1 = Paint()
      ..color = color1
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final paint2 = Paint()
      ..color = color2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Inner orbiting arc
    final innerR = size.width * 0.28 + (breath * 6);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerR),
      progress * 2 * math.pi, // Rotates clockwise
      math.pi * 1.2,
      false,
      paint1,
    );

    // Outer orbiting arc
    final outerR = size.width * 0.42 - (breath * 6);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerR),
      -progress * 2 * math.pi, // Rotates counter-clockwise
      math.pi * 0.9,
      false,
      paint2,
    );
  }

  @override
  bool shouldRepaint(covariant _AiRingsPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color1 != color1 ||
      oldDelegate.color2 != color2;
}
