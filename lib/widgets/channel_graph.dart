import 'dart:collection';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../models/wifi.dart';
import '../services/wifi_analysis.dart';
import '../theme.dart';

const _floorDbm = -100.0;
const _ceilingDbm = -30.0;

/// A stable colour per network, so a curve keeps its colour across scans.
Color networkColor(String bssid) => HSVColor.fromAHSV(
  1,
  (bssid.hashCode % 360).abs().toDouble(),
  0.65,
  0.95,
).toColor();

/// Every channel of one band on the x-axis, each network drawn as a curve
/// across its channel width with its peak at its signal. Curves animate
/// between scans instead of jumping.
class ChannelGraph extends StatefulWidget {
  const ChannelGraph({super.key, required this.analysis, this.height = 220});

  final BandAnalysis analysis;
  final double height;

  @override
  State<ChannelGraph> createState() => _ChannelGraphState();
}

class _ChannelGraphState extends State<ChannelGraph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  Map<String, double> _from = const {};
  Map<String, double> _to = const {};

  @override
  void initState() {
    super.initState();
    _to = _levels(widget.analysis);
    _from = _to;
  }

  @override
  void didUpdateWidget(ChannelGraph old) {
    super.didUpdateWidget(old);
    final next = _levels(widget.analysis);
    if (!_sameLevels(next, _to)) {
      _from = _current();
      _to = next;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static Map<String, double> _levels(BandAnalysis a) => {
    for (final n in a.networks) n.bssid: n.rssi.toDouble(),
  };

  static bool _sameLevels(Map<String, double> a, Map<String, double> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  Map<String, double> _current() {
    final t = Curves.easeOut.transform(_controller.value);
    return {
      for (final key in {..._from.keys, ..._to.keys})
        key: lerpDouble(_from[key] ?? _floorDbm, _to[key] ?? _floorDbm, t)!,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _ChannelPainter(
            analysis: widget.analysis,
            levels: _current(),
            axisColor: theme.colorScheme.onSurfaceVariant,
            gridColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            labelStyle: theme.textTheme.labelSmall!,
          ),
        ),
      ),
    );
  }
}

class _ChannelPainter extends CustomPainter {
  _ChannelPainter({
    required this.analysis,
    required this.levels,
    required this.axisColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final BandAnalysis analysis;
  final Map<String, double> levels;
  final Color axisColor;
  final Color gridColor;
  final TextStyle labelStyle;

  static const _left = 30.0;
  static const _bottom = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final band = analysis.band;
    final channels = band.channels;
    final minF = band.frequencyOf(channels.first) - 15.0;
    final maxF = band.frequencyOf(channels.last) + 15.0;
    final plot = Rect.fromLTRB(_left, 4, size.width - 4, size.height - _bottom);
    double x(double mhz) =>
        plot.left + (mhz - minF) / (maxF - minF) * plot.width;
    double y(double dbm) =>
        plot.bottom -
        ((dbm - _floorDbm) / (_ceilingDbm - _floorDbm)).clamp(0, 1) *
            plot.height;

    final grid = Paint()..color = gridColor;
    for (var dbm = -90; dbm <= -40; dbm += 10) {
      canvas.drawLine(
        Offset(plot.left, y(dbm.toDouble())),
        Offset(plot.right, y(dbm.toDouble())),
        grid,
      );
      _text(canvas, '$dbm', Offset(0, y(dbm.toDouble()) - 6));
    }

    // Channel ticks; DFS channels dimmed, the suggested channel highlighted.
    final labelEvery = channels.length > 30
        ? 4
        : (channels.length > 14 ? 2 : 1);
    for (var i = 0; i < channels.length; i++) {
      final ch = channels[i];
      final cx = x(band.frequencyOf(ch).toDouble());
      if (band.isDfs(ch)) {
        canvas.drawRect(
          Rect.fromLTRB(cx - 2, plot.top, cx + 2, plot.bottom),
          Paint()..color = gridColor.withValues(alpha: 0.15),
        );
      }
      if (ch == analysis.recommended) {
        canvas.drawRect(
          Rect.fromLTRB(cx - 3, plot.top, cx + 3, plot.bottom),
          Paint()..color = const Color(0xFF43A047).withValues(alpha: 0.25),
        );
      }
      if (i % labelEvery == 0) {
        _text(canvas, '$ch', Offset(cx - 6, plot.bottom + 3));
      }
    }

    final sorted = [...analysis.networks]
      ..sort((a, b) => a.rssi.compareTo(b.rssi));
    for (final n in sorted) {
      final level = levels[n.bssid] ?? n.rssi.toDouble();
      final s = n.span;
      final color = networkColor(n.bssid);
      final left = x(s.low), right = x(s.high), mid = (left + right) / 2;
      final peak = y(level);
      final shoulder = (right - left) * 0.18;
      final path = Path()
        ..moveTo(left, plot.bottom)
        ..cubicTo(left + shoulder, peak, left + shoulder, peak, mid, peak)
        ..cubicTo(
          right - shoulder,
          peak,
          right - shoulder,
          peak,
          right,
          plot.bottom,
        );
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      _text(
        canvas,
        n.displayName,
        Offset(mid - 20, peak - 13),
        color: color,
        max: 90,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    Color? color,
    double max = 40,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(color: color ?? axisColor, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: max);
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ChannelPainter old) =>
      old.analysis != analysis ||
      old.levels != levels ||
      old.axisColor != axisColor;
}

/// One bar per channel: height is the strongest signal on it, the label the
/// number of networks; the suggested channel is outlined.
class ChannelBars extends StatelessWidget {
  const ChannelBars({super.key, required this.analysis});

  final BandAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channels = analysis.channels;
    return SizedBox(
      height: 90,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = (box.maxWidth / channels.length).clamp(6.0, 40.0);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final c in channels)
                  Tooltip(
                    message:
                        'Channel ${c.channel}: ${c.count} networks'
                        '${c.strongest == null ? '' : ', strongest ${c.strongest} dBm'}',
                    child: SizedBox(
                      width: width,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (c.count > 0 && width >= 12)
                            Text(
                              '${c.count}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                              ),
                            ),
                          Container(
                            height: c.strongest == null
                                ? 2
                                : 60 *
                                      ((c.strongest! - _floorDbm) /
                                              (_ceilingDbm - _floorDbm))
                                          .clamp(0.03, 1),
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: c.strongest == null
                                  ? theme.colorScheme.surfaceContainerHighest
                                  : signalColor(c.strongest!),
                              border: c.channel == analysis.recommended
                                  ? Border.all(
                                      color: theme.colorScheme.onSurface,
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                          ),
                          if (width >= 16)
                            Text(
                              '${c.channel}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Per-channel waterfall: one row per scan, newest on top; each cell's
/// brightness is the strongest signal on that channel in that scan.
class ChannelWaterfall extends StatelessWidget {
  const ChannelWaterfall({
    super.key,
    required this.band,
    required this.history,
  });

  final WifiBand band;
  final ListQueue<Map<String, WifiNetwork>> history;

  @override
  Widget build(BuildContext context) {
    final channels = band.channels;
    final rows = history.toList().reversed.toList();
    return SizedBox(
      height: 8.0 * rows.length.clamp(1, 30),
      width: double.infinity,
      child: CustomPaint(
        painter: _WaterfallPainter(
          band: band,
          channels: channels,
          rows: rows,
          empty: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _WaterfallPainter extends CustomPainter {
  _WaterfallPainter({
    required this.band,
    required this.channels,
    required this.rows,
    required this.empty,
  });

  final WifiBand band;
  final List<int> channels;
  final List<Map<String, WifiNetwork>> rows;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;
    final cellW = size.width / channels.length;
    final cellH = size.height / rows.length;
    for (var r = 0; r < rows.length; r++) {
      final networks = rows[r].values.where((n) => n.band == band).toList();
      for (var c = 0; c < channels.length; c++) {
        int? strongest;
        for (final n in networks) {
          if (n.overlaps(band, channels[c]) &&
              (strongest == null || n.rssi > strongest)) {
            strongest = n.rssi;
          }
        }
        final color = strongest == null
            ? empty
            : Color.lerp(
                const Color(0xFF1A237E),
                const Color(0xFFFFEB3B),
                ((strongest - _floorDbm) / (_ceilingDbm - _floorDbm)).clamp(
                  0,
                  1,
                ),
              )!;
        canvas.drawRect(
          Rect.fromLTWH(c * cellW, r * cellH, cellW - 0.5, cellH - 0.5),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WaterfallPainter old) => true;
}
