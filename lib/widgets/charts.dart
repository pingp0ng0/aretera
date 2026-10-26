import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/hike_insights.dart';
import '../theme/app_theme.dart';

// Small hand-drawn charts for the records tab (no chart package; works offline).

const _axisText = TextStyle(color: BiviColors.textSecondary, fontSize: 10);
const _gridColor = Color(0x553A4A40);

/// "Nice" step (1, 2, 5 × 10ⁿ) so that [range] splits into about [ticks] parts.
double niceStep(double range, {int ticks = 4}) {
  if (range <= 0) return 1;
  final raw = range / ticks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / mag;
  final nice = f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10;
  return nice * mag;
}

void _text(Canvas c, String s, Offset at, {TextAlign align = TextAlign.left, TextStyle style = _axisText}) {
  final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
  final dx = switch (align) {
    TextAlign.right => at.dx - tp.width,
    TextAlign.center => at.dx - tp.width / 2,
    _ => at.dx,
  };
  tp.paint(c, Offset(dx, at.dy - tp.height / 2));
}

/// Altitude (m) over distance (m), with the high point marked.
class ElevationChart extends StatelessWidget {
  const ElevationChart({super.key, required this.profile, this.height = 170});

  final List<(double, double)> profile;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (profile.length < 2) {
      return SizedBox(
        height: 60,
        child: Center(child: Text('고도 데이터가 부족해요', style: _axisText.copyWith(fontSize: 13))),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _ElevationPainter(profile)),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter(this.profile);

  final List<(double, double)> profile;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, bottom = 18.0, top = 16.0, right = 8.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);

    final alts = [for (final p in profile) p.$2];
    final lo = alts.reduce(math.min), hi = alts.reduce(math.max);
    final step = niceStep(math.max(hi - lo, 20), ticks: 3);
    final yMin = (lo / step).floor() * step, yMax = (hi / step).ceil() * step;
    final xMax = math.max(profile.last.$1, 1.0);

    Offset at(double d, double alt) => Offset(
          plot.left + d / xMax * plot.width,
          plot.bottom - (alt - yMin) / (yMax - yMin) * plot.height,
        );

    final grid = Paint()..color = _gridColor;
    for (var y = yMin; y <= yMax + 1e-6; y += step) {
      final py = at(0, y).dy;
      canvas.drawLine(Offset(plot.left, py), Offset(plot.right, py), grid);
      _text(canvas, '${y.round()}', Offset(plot.left - 6, py), align: TextAlign.right);
    }
    String dist(double m) => xMax < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
    _text(canvas, '0', Offset(plot.left, size.height - 8));
    _text(canvas, dist(xMax / 2), Offset(plot.center.dx, size.height - 8), align: TextAlign.center);
    _text(canvas, dist(xMax), Offset(plot.right, size.height - 8), align: TextAlign.right);

    final start = at(profile.first.$1, profile.first.$2);
    final line = Path()..moveTo(start.dx, start.dy);
    for (final (d, a) in profile.skip(1)) {
      final o = at(d, a);
      line.lineTo(o.dx, o.dy);
    }
    final area = Path.from(line)
      ..lineTo(at(profile.last.$1, yMin).dx, plot.bottom)
      ..lineTo(at(profile.first.$1, yMin).dx, plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BiviColors.forestLight.withValues(alpha: 0.55), BiviColors.forestLight.withValues(alpha: 0.05)],
        ).createShader(plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = BiviColors.forestLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final top0 = profile.reduce((a, b) => b.$2 > a.$2 ? b : a);
    final peak = at(top0.$1, top0.$2);
    canvas.drawCircle(peak, 4, Paint()..color = BiviColors.amber);
    final labelRight = peak.dx > plot.center.dx;
    _text(
      canvas,
      '최고 ${top0.$2.round()} m',
      Offset(peak.dx + (labelRight ? -6 : 6), peak.dy - 9),
      align: labelRight ? TextAlign.right : TextAlign.left,
      style: _axisText.copyWith(color: BiviColors.amber, fontWeight: FontWeight.w700),
    );
  }

  @override
  bool shouldRepaint(_ElevationPainter old) => old.profile != profile;
}

/// Dots (x, y) with an optional trend line.
class ScatterChart extends StatelessWidget {
  const ScatterChart({
    super.key,
    required this.points,
    required this.xLabel,
    required this.yLabel,
    this.fit,
    this.yRange,
    this.yTicks,
    this.height = 180,
  });

  final List<(double, double)> points;
  final String xLabel;
  final String yLabel;
  final LinearFit? fit;

  /// Fixed y axis, e.g. (1, 5) for star ratings.
  final (double, double)? yRange;

  /// Fixed y tick step (e.g. 1 for stars).
  final double? yTicks;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _ScatterPainter(this)),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter(this.chart);

  final ScatterChart chart;

  static (double, double, double) _axis(Iterable<double> values, {(double, double)? fixed, double? step}) {
    if (fixed != null) return (fixed.$1, fixed.$2, step ?? niceStep(fixed.$2 - fixed.$1));
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final s = step ?? niceStep(hi - lo, ticks: 3);
    return ((lo / s).floor() * s, (hi / s).ceil() * s, s);
  }

  static String _fmt(double v, double step) => step >= 1 ? '${v.round()}' : v.toStringAsFixed(1);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, bottom = 30.0, top = 18.0, right = 10.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final pts = chart.points;
    if (pts.isEmpty) return;

    final (x0, x1, xs) = _axis(pts.map((p) => p.$1));
    final (y0, y1, ys) = _axis(pts.map((p) => p.$2), fixed: chart.yRange, step: chart.yTicks);
    Offset at(double x, double y) => Offset(
          plot.left + (x - x0) / (x1 - x0) * plot.width,
          plot.bottom - (y - y0) / (y1 - y0) * plot.height,
        );

    final grid = Paint()..color = _gridColor;
    for (var y = y0; y <= y1 + 1e-6; y += ys) {
      final py = at(x0, y).dy;
      canvas.drawLine(Offset(plot.left, py), Offset(plot.right, py), grid);
      _text(canvas, _fmt(y, ys), Offset(plot.left - 6, py), align: TextAlign.right);
    }
    for (var x = x0; x <= x1 + 1e-6; x += xs) {
      _text(canvas, _fmt(x, xs), Offset(at(x, y0).dx, plot.bottom + 9), align: TextAlign.center);
    }
    _text(canvas, chart.xLabel, Offset(plot.right, size.height - 6), align: TextAlign.right);
    _text(canvas, chart.yLabel, const Offset(0, 6));

    final fit = chart.fit;
    if (fit != null) {
      canvas.save();
      canvas.clipRect(plot);
      canvas.drawLine(
        at(x0, fit.at(x0)),
        at(x1, fit.at(x1)),
        Paint()
          ..color = BiviColors.amber
          ..strokeWidth = 2,
      );
      canvas.restore();
    }
    final dot = Paint()..color = BiviColors.forestLight;
    final ring = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final (x, y) in pts) {
      canvas.drawCircle(at(x, y), 5, dot);
      canvas.drawCircle(at(x, y), 5, ring);
    }
  }

  @override
  bool shouldRepaint(_ScatterPainter old) => old.chart != chart;
}

/// Vertical bars with a label under each and the value above the tallest ones.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.values, required this.labels, required this.format, this.height = 150});

  final List<double> values;
  final List<String> labels;
  final String Function(double) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold(0.0, math.max);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (values[i] > 0)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(format(values[i]), style: _axisText.copyWith(color: BiviColors.textPrimary)),
                    ),
                  const SizedBox(height: 2),
                  Container(
                    height: maxV == 0 ? 2 : math.max(2, values[i] / maxV * (height - 40)),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: values[i] > 0 ? BiviColors.forestLight : BiviColors.contour,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(labels[i], style: _axisText),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
