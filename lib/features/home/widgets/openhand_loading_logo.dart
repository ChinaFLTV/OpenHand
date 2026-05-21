import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated loading badge built around the OpenHand bitmap LOGO.
///
/// The bitmap is the visual anchor; subtle motion is layered around it so
/// the brand mark stays recognisable while still signalling "loading":
///   * elastic entry scale
///   * gentle breathing pulse on the LOGO itself
///   * soft halo glow that breathes in sync with the pulse
///   * two thin counter-rotating arcs orbiting the LOGO
class OpenHandLoadingLogo extends StatefulWidget {
  const OpenHandLoadingLogo({super.key, this.size = 140});

  final double size;

  @override
  State<OpenHandLoadingLogo> createState() => _OpenHandLoadingLogoState();
}

class _OpenHandLoadingLogoState extends State<OpenHandLoadingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final size = widget.size;
    final logoSize = size * 0.66;
    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);

    Widget buildLogo(double t) {
      final breath = animationsEnabled
          ? (math.sin(t * math.pi * 2) + 1) / 2
          : 0.5;
      final pulseScale = animationsEnabled ? 0.96 + breath * 0.06 : 1.0;
      return Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _HaloPainter(
              breath: breath,
              color: colorScheme.primary.withValues(
                alpha: isDark ? 0.28 : 0.18,
              ),
            ),
          ),
          if (animationsEnabled)
            CustomPaint(
              size: Size(size * 0.92, size * 0.92),
              painter: _OrbitPainter(
                progress: t,
                color1: colorScheme.primary.withValues(alpha: 0.55),
                color2: colorScheme.tertiary.withValues(alpha: 0.55),
              ),
            ),
          Transform.scale(
            scale: pulseScale,
            child: SizedBox(
              width: logoSize,
              height: logoSize,
              child: Image.asset('assets/branding/openhand_logo.png'),
            ),
          ),
        ],
      );
    }

    if (!animationsEnabled) {
      _controller.stop();
      return Center(
        child: SizedBox(width: size, height: size, child: buildLogo(0)),
      );
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.85, end: 1.0),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.elasticOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: SizedBox(
          width: size,
          height: size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return buildLogo(_controller.value);
            },
          ),
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.breath, required this.color});

  final double breath;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * (0.72 + breath * 0.10);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _HaloPainter old) =>
      old.breath != breath || old.color != color;
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
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
    final breath = (math.sin(progress * math.pi * 2) + 1) / 2;

    final paint1 = Paint()
      ..color = color1
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    final paint2 = Paint()
      ..color = color2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final innerR = size.width * 0.46 + breath * 3;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerR),
      progress * 2 * math.pi,
      math.pi * 0.9,
      false,
      paint1,
    );

    final outerR = size.width * 0.50 - breath * 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerR),
      -progress * 2 * math.pi + math.pi / 3,
      math.pi * 0.7,
      false,
      paint2,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.progress != progress || old.color1 != color1 || old.color2 != color2;
}
