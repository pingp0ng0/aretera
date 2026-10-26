import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 절차적으로 생성하는 등고선(Topographic contour) 패턴.
/// 로고 · 카드 배경 · 빈 화면에 공통으로 사용한다.
class TopoPainter extends CustomPainter {
  const TopoPainter({
    required this.color,
    this.seed = 1,
    this.spacing = 14,
    this.strokeWidth = 1,
    this.peaks = 2,
  });

  final Color color;
  final int seed;
  final double spacing;
  final double strokeWidth;
  final int peaks;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rnd = Random(seed);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    final maxR = size.longestSide * 1.1;
    const steps = 96;

    for (var p = 0; p < peaks; p++) {
      final center = Offset(
        size.width * (0.15 + rnd.nextDouble() * 0.7),
        size.height * (0.15 + rnd.nextDouble() * 0.7),
      );
      final a1 = rnd.nextDouble() * 2 * pi;
      final a2 = rnd.nextDouble() * 2 * pi;
      final a3 = rnd.nextDouble() * 2 * pi;
      final stretch = 0.75 + rnd.nextDouble() * 0.5;

      for (var r = spacing; r < maxR; r += spacing) {
        final path = Path();
        for (var i = 0; i <= steps; i++) {
          final t = i / steps * 2 * pi;
          final wobble = 1 +
              0.14 * sin(3 * t + a1 + r * 0.004) +
              0.08 * sin(5 * t + a2) +
              0.05 * sin(2 * t + a3 + r * 0.01);
          final x = center.dx + cos(t) * r * wobble * stretch;
          final y = center.dy + sin(t) * r * wobble;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(TopoPainter old) =>
      old.color != color || old.seed != seed || old.spacing != spacing || old.peaks != peaks;
}

/// 등고선 배경 카드
class TopoCard extends StatelessWidget {
  const TopoCard({
    super.key,
    required this.child,
    this.seed = 3,
    this.color = BiviColors.surface,
    this.lineColor,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final int seed;
  final Color color;
  final Color? lineColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: TopoPainter(
              color: lineColor ?? BiviColors.contour.withValues(alpha: 0.55),
              seed: seed,
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Bivi badge logo (option 2, lavender — PRD_step4), rendered from design/bivi_badge_dawn.svg.
/// [size] is the badge height; the artwork is 600×640, so the width is slightly smaller.
class BiviLogo extends StatelessWidget {
  const BiviLogo({super.key, this.size = 36});

  static const asset = 'assets/images/bivi_badge.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      height: size,
      width: size * 600 / 640,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Bivi 로고',
    );
  }
}

/// 데이터가 없는 화면용 등고선 Empty State
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.illustration,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// Shown instead of the round [icon] badge, e.g. a mascot image.
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: TopoPainter(
              color: BiviColors.contour.withValues(alpha: 0.45),
              seed: 11,
              spacing: 18,
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                illustration ??
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        color: BiviColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 40, color: BiviColors.forestLight),
                    ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: BiviColors.textSecondary, height: 1.5),
                ),
                if (action != null) ...[const SizedBox(height: 20), action!],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
