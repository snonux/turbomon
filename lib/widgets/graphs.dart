import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/ring_buffer.dart';

/// Load colours: green under 50 %, amber to 80 %, red above.
Color loadColor(double? percent) {
  if (percent == null) return Colors.grey;
  if (percent < 50) return const Color(0xFF2E9D57);
  if (percent < 80) return const Color(0xFFE0A100);
  return const Color(0xFFD64545);
}

/// Distinct colours for multi-line graphs (cores, networks, devices).
const seriesPalette = [
  Color(0xFF3B82F6),
  Color(0xFFF97316),
  Color(0xFF10B981),
  Color(0xFFE11D48),
  Color(0xFF8B5CF6),
  Color(0xFF0EA5E9),
  Color(0xFFEAB308),
  Color(0xFF14B8A6),
  Color(0xFFEC4899),
  Color(0xFF64748B),
];

/// A horizontal bar for one utilisation value, coloured by load.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.label, required this.percent, this.detail, this.height = 14});

  final String label;
  final double? percent;
  final String? detail;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = percent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: theme.textTheme.labelMedium)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                    if (v != null)
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (v / 100).clamp(0, 1),
                        child: ColoredBox(color: loadColor(v)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              v == null ? 'n/a' : (detail ?? '${v.toStringAsFixed(0)} %'),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line in a [LineGraph].
class GraphSeries {
  const GraphSeries(this.buffer, {this.color, this.label, this.colorByLoad = false});
  final RingBuffer buffer;
  final Color? color;
  final String? label;

  /// Colour the line and fill by the latest value as a percentage.
  final bool colorByLoad;
}

/// A scrolling line graph drawn with a [CustomPainter]. The newest sample is
/// at the right edge; gaps (null samples) break the line.
class LineGraph extends StatelessWidget {
  const LineGraph({
    super.key,
    required this.series,
    required this.capacity,
    this.minY = 0,
    this.maxY,
    this.height = 110,
    this.formatY,
    this.fill = true,
    this.percentScale = false,
  });

  final List<GraphSeries> series;
  final int capacity;
  final double minY;

  /// Fixed top of the y-axis; when null it follows the data.
  final double? maxY;
  final double height;
  final String Function(double)? formatY;
  final bool fill;

  /// Load colours are computed from the value relative to [maxY] (or 100).
  final bool percentScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var top = maxY;
    if (top == null) {
      top = minY;
      for (final s in series) {
        final m = s.buffer.max;
        if (m != null && m > top!) top = m;
      }
      top = top! <= minY ? minY + 1 : top * 1.15;
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _LinePainter(
          series: series,
          capacity: capacity,
          minY: minY,
          maxY: top,
          grid: theme.colorScheme.outlineVariant,
          text: theme.colorScheme.onSurfaceVariant,
          formatY: formatY ?? (v) => v.toStringAsFixed(0),
          fill: fill,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.series,
    required this.capacity,
    required this.minY,
    required this.maxY,
    required this.grid,
    required this.text,
    required this.formatY,
    required this.fill,
  });

  final List<GraphSeries> series;
  final int capacity;
  final double minY;
  final double maxY;
  final Color grid;
  final Color text;
  final String Function(double) formatY;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 34.0;
    final plot = Rect.fromLTWH(leftPad, 4, size.width - leftPad - 2, size.height - 8);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 2; i++) {
      final y = plot.top + plot.height * i / 2;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final v = maxY - (maxY - minY) * i / 2;
      final tp = TextPainter(
        text: TextSpan(text: formatY(v), style: TextStyle(color: text, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: leftPad - 2);
      tp.paint(canvas, Offset(leftPad - tp.width - 3, y - tp.height / 2));
    }
    final range = (maxY - minY) == 0 ? 1 : maxY - minY;
    final step = plot.width / math.max(1, capacity - 1);
    for (final s in series) {
      final values = s.buffer.values;
      if (values.isEmpty) continue;
      final offset = capacity - values.length;
      final color = s.colorByLoad
          ? _loadFor(s.buffer.last, range)
          : (s.color ?? seriesPalette.first);
      final line = Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      Path? path;
      Path? area;
      double? lastX;
      void close() {
        if (path != null) {
          canvas.drawPath(path!, line);
          if (fill && area != null && lastX != null) {
            area!
              ..lineTo(lastX, plot.bottom)
              ..close();
            canvas.drawPath(area!, Paint()..color = color.withValues(alpha: 0.15));
          }
        }
        path = null;
        area = null;
      }

      for (var i = 0; i < values.length; i++) {
        final v = values[i];
        final x = plot.left + (offset + i) * step;
        if (v == null) {
          close();
          continue;
        }
        final y = plot.bottom - ((v - minY) / range).clamp(0, 1) * plot.height;
        if (path == null) {
          path = Path()..moveTo(x, y);
          area = Path()
            ..moveTo(x, plot.bottom)
            ..lineTo(x, y);
        } else {
          path!.lineTo(x, y);
          area!.lineTo(x, y);
        }
        lastX = x;
      }
      close();
    }
  }

  Color _loadFor(double? v, num range) {
    if (v == null) return Colors.grey;
    return loadColor((v - minY) * 100 / range);
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}

/// A titled card holding a graph, its current value and a legend.
class GraphCard extends StatelessWidget {
  const GraphCard({
    super.key,
    required this.title,
    required this.value,
    required this.graph,
    this.legend = const [],
    this.note,
    this.onTap,
  });

  final String title;
  final String value;
  final Widget graph;
  final List<(String, Color)> legend;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                  Text(value, style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 6),
              graph,
              if (legend.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      for (final (label, color) in legend)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 10, height: 3, color: color),
                          const SizedBox(width: 4),
                          Text(label, style: theme.textTheme.labelSmall),
                        ]),
                    ],
                  ),
                ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(note!, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
