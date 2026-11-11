import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'alwaha_theme.dart';

/// خلفية متحركة: تدرّج بحري داكن وثلاث بقع ضوء (فيروزي وأخضر وذهبي) تتحرك ببطء.
class AnimatedGlowBackground extends StatefulWidget {
  const AnimatedGlowBackground({super.key});

  @override
  State<AnimatedGlowBackground> createState() => _AnimatedGlowBackgroundState();
}

class _AnimatedGlowBackgroundState extends State<AnimatedGlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _GlowPainter(_controller.value),
            size: Size.infinite,
          ),
        ),
      );
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff031017), Color(0xff06242e), Color(0xff031017)],
        ).createShader(rect),
    );
    void glow(Color color, double phase, double rx, double ry, double radius,
        int alpha) {
      final angle = (t + phase) * 2 * math.pi;
      final center = Offset(
        size.width * (0.5 + rx * math.cos(angle)),
        size.height * (0.5 + ry * math.sin(angle * 0.8)),
      );
      final r = radius * size.shortestSide;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withAlpha(alpha), color.withAlpha(0)],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    glow(AlwahaColors.teal, 0.0, 0.35, 0.30, 0.95, 70);
    glow(AlwahaColors.green, 0.33, 0.40, 0.25, 0.80, 48);
    glow(AlwahaColors.gold, 0.66, 0.30, 0.35, 0.60, 36);
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => oldDelegate.t != t;
}

/// بطاقة زجاجية بحافة متوهجة تنبض بهدوء.
class GlowCard extends StatefulWidget {
  const GlowCard({
    required this.child,
    this.accent = AlwahaColors.teal,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final Color accent;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  State<GlowCard> createState() => _GlowCardState();
}

class _GlowCardState extends State<GlowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.16 + 0.24 * Curves.easeInOut.transform(_pulse.value);
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [widget.accent.withAlpha(40), const Color(0x0dffffff)],
            ),
            border: Border.all(color: widget.accent.withAlpha(150), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withAlpha((glow * 255).round()),
                blurRadius: 20,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onTap,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
  }
}

/// شعار «الواحة» (assets/images/logo.png).
class LogoMark extends StatelessWidget {
  const LogoMark({this.size = 88, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.18),
          boxShadow: const [
            BoxShadow(color: Color(0x5522d3b6), blurRadius: 24),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.18),
          child: Image.asset(
            'assets/images/logo.png',
            width: size,
            height: size * 1.1,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => SizedBox(
              width: size,
              height: size,
              child: const Icon(Icons.spa_rounded,
                  size: 48, color: AlwahaColors.teal),
            ),
          ),
        ),
      );
}
