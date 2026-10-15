import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/time_series.dart';
import '../theme.dart';
import 'expandable_chart.dart';

/// One line on a [UsageGraph].
class GraphLine {
  const GraphLine(this.series, {this.color, this.fill = true, this.label});

  final TimeSeries series;

  /// Fixed colour; when null the line is coloured by its current load.
  final Color? color;
  final bool fill;
  final String? label;
}

/// A live usage graph that can also be explored in a full-screen viewer.
/// Resolve lines on each notification, including when buffers are replaced.
class LiveUsageGraph extends StatelessWidget {
  const LiveUsageGraph({
    super.key,
    required this.listenable,
    required this.linesBuilder,
    required this.semanticLabel,
    this.maxValue,
    this.minValue = 0,
    this.height = 72,
  });

  final Listenable listenable;
  final List<GraphLine> Function() linesBuilder;
  final String semanticLabel;
  final double? maxValue;
  final double minValue;
  final double height;

  @override
  Widget build(BuildContext context) => ExpandableChart(
    title: semanticLabel,
    listenable: listenable,
    height: height,
    builder: (context, size, expanded) => UsageGraph(
      lines: linesBuilder(),
      maxValue: maxValue,
      minValue: minValue,
      height: size.height,
      semanticLabel: semanticLabel,
    ),
    detailsBuilder: (context) => Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final line in linesBuilder())
          if (line.label != null)
            Text(
              line.label!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: line.color ?? loadColor(line.series.latest?.value),
              ),
            ),
      ],
    ),
  );
}

/// A scrolling line graph drawn with a plain CustomPainter. The newest point
/// sits at the right edge and older ones scroll left as samples arrive.
class UsageGraph extends StatelessWidget {
  const UsageGraph({
    super.key,
    required this.lines,
    this.maxValue,
    this.minValue = 0,
    this.height = 72,
    this.semanticLabel,
  });

  final List<GraphLine> lines;

  /// Fixed top of the y-axis (100 for percentages); null scales to the data.
  final double? maxValue;

  /// Bottom of the y-axis; -100 for signal graphs in dBm.
  final double minValue;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final grid = Theme.of(
      context,
    ).colorScheme.outlineVariant.withValues(alpha: 0.4);
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _GraphPainter(
            lines: lines,
            maxValue: maxValue,
            minValue: minValue,
            gridColor: grid,
          ),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.lines,
    required this.maxValue,
    required this.minValue,
    required this.gridColor,
  })
    // Repaint whenever any series gains a point.
    : _signature = [
         for (final l in lines)
           (
             l.series,
             l.series.length,
             l.series.latest?.time,
             l.series.latest?.value,
             l.color,
             l.fill,
           ),
       ];

  final List<GraphLine> lines;
  final double? maxValue;
  final double minValue;
  final Color gridColor;
  final List<Object?> _signature;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    var top = maxValue ?? 0;
    if (maxValue == null) {
      for (final l in lines) {
        top = math.max(top, l.series.max ?? 0);
      }
      top = top <= minValue ? minValue + 1 : top * 1.15;
    }
    for (final line in lines) {
      _drawLine(canvas, size, line, top);
    }
  }

  void _drawLine(Canvas canvas, Size size, GraphLine line, double top) {
    final values = line.series.values.toList();
    if (values.isEmpty) return;
    final capacity = math.max(line.series.capacity, 2);
    final color = line.color ?? loadColor(values.last);
    final step = size.width / (capacity - 1);
    final offset = capacity - values.length;
    Offset point(int i) => Offset(
      (i + offset) * step,
      size.height -
          ((values[i] - minValue) / (top - minValue)).clamp(0, 1) * size.height,
    );

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    if (line.fill) {
      final fill = Path.from(path)
        ..lineTo(point(values.length - 1).dx, size.height)
        ..lineTo(point(0).dx, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.35),
              color.withValues(alpha: 0.02),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    if (values.length == 1) {
      canvas.drawCircle(point(0), 2.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.maxValue != maxValue ||
      old.minValue != minValue ||
      old.gridColor != gridColor ||
      old.lines.length != lines.length ||
      !_sameSignature(old._signature);

  bool _sameSignature(List<Object?> other) {
    if (other.length != _signature.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i] != _signature[i]) return false;
    }
    return true;
  }
}
