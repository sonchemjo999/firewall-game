import 'package:flutter/material.dart';
import 'dart:math' as math;

class ShieldLogo extends StatelessWidget {
  final double size;
  final bool animated;
  const ShieldLogo({super.key, this.size = 80, this.animated = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShieldPainter(size)),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  final double size;
  _ShieldPainter(this.size);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final w = canvasSize.width;
    final h = canvasSize.height;
    final cx = w / 2;

    // Outer glow
    final glowPaint = Paint()
      ..color = const Color(0xFF6C63FF).withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(Offset(cx, h * 0.45), w * 0.38, glowPaint);

    // Shield body gradient
    final shieldPath = Path();
    shieldPath.moveTo(cx, h * 0.08);
    shieldPath.cubicTo(cx - w * 0.15, h * 0.08, cx - w * 0.42, h * 0.12, cx - w * 0.42, h * 0.18);
    shieldPath.lineTo(cx - w * 0.42, h * 0.48);
    shieldPath.cubicTo(cx - w * 0.42, h * 0.65, cx - w * 0.2, h * 0.82, cx, h * 0.94);
    shieldPath.cubicTo(cx + w * 0.2, h * 0.82, cx + w * 0.42, h * 0.65, cx + w * 0.42, h * 0.48);
    shieldPath.lineTo(cx + w * 0.42, h * 0.18);
    shieldPath.cubicTo(cx + w * 0.42, h * 0.12, cx + w * 0.15, h * 0.08, cx, h * 0.08);
    shieldPath.close();

    final shieldGradient = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF6C63FF), Color(0xFF4834DF), Color(0xFF6C63FF)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(shieldPath, shieldGradient);

    // Border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF00D9FF), Color(0xFF6C63FF)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(shieldPath, borderPaint);

    // Inner shield (smaller)
    final innerPath = Path();
    final s = 0.72;
    final ox = cx;
    final oy = h * 0.08 + (h * 0.86 * (1 - s) / 2);
    innerPath.moveTo(ox, oy);
    innerPath.cubicTo(
      ox - w * 0.15 * s, oy,
      ox - w * 0.42 * s, oy + h * 0.04 * s,
      ox - w * 0.42 * s, oy + h * 0.1 * s,
    );
    innerPath.lineTo(ox - w * 0.42 * s, oy + h * 0.4 * s);
    innerPath.cubicTo(
      ox - w * 0.42 * s, oy + h * 0.57 * s,
      ox - w * 0.2 * s, oy + h * 0.74 * s,
      ox, oy + h * 0.86 * s,
    );
    innerPath.cubicTo(
      ox + w * 0.2 * s, oy + h * 0.74 * s,
      ox + w * 0.42 * s, oy + h * 0.57 * s,
      ox + w * 0.42 * s, oy + h * 0.4 * s,
    );
    innerPath.lineTo(ox + w * 0.42 * s, oy + h * 0.1 * s);
    innerPath.cubicTo(
      ox + w * 0.42 * s, oy + h * 0.04 * s,
      ox + w * 0.15 * s, oy,
      ox, oy,
    );
    innerPath.close();

    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF00D9FF).withOpacity(0.3);
    canvas.drawPath(innerPath, innerPaint);

    // Checkmark / bolt icon
    final iconPaint = Paint()
      ..color = const Color(0xFF00F5A0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final boltPath = Path();
    boltPath.moveTo(cx - w * 0.1, h * 0.38);
    boltPath.lineTo(cx + w * 0.02, h * 0.46);
    boltPath.lineTo(cx - w * 0.04, h * 0.46);
    boltPath.lineTo(cx + w * 0.1, h * 0.62);
    canvas.drawPath(boltPath, iconPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AnimatedShieldLogo extends StatefulWidget {
  final double size;
  const AnimatedShieldLogo({super.key, this.size = 80});
  @override
  State<AnimatedShieldLogo> createState() => _AnimatedShieldLogoState();
}

class _AnimatedShieldLogoState extends State<AnimatedShieldLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF).withOpacity(0.15 + 0.1 * math.sin(_ctrl.value * math.pi * 2)),
                blurRadius: 20 + 8 * math.sin(_ctrl.value * math.pi * 2),
                spreadRadius: 2,
              ),
            ],
          ),
          child: ShieldLogo(size: widget.size),
        );
      },
    );
  }
}
