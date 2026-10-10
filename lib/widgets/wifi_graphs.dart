import 'package:flutter/material.dart';

import '../parsers/wifi_channels.dart';
import 'graphs.dart';

const _minDbm = -100.0;
const _maxDbm = -30.0;

double _dbmToUnit(num dbm) => ((dbm - _minDbm) / (_maxDbm - _minDbm)).clamp(0, 1).toDouble();

/// Colour for a signal strength: red weak, amber fair, green strong.
Color signalColor(num dbm) {
  if (dbm >= -60) return const Color(0xFF2E9D57);
  if (dbm >= -75) return const Color(0xFFE0A100);
  return const Color(0xFFD64545);
}

/// Every channel of a band on the x-axis, each network drawn as a curve over
/// the channels it spans, signal in dBm on the y-axis.
class ChannelGraph extends StatelessWidget {
  const ChannelGraph({
    super.key,
    required this.band,
    required this.networks,
    this.highlight,
    this.height = 190,
  });

  final WifiBand band;
  final List<WifiNetwork> networks;
  final String? highlight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channels = channelsOf(band);
    // 6 GHz has 59 channels: give it room to scroll sideways.
    final minWidth = channels.length * (band == WifiBand.ghz24 ? 24.0 : 22.0) + 40;
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth > minWidth ? c.maxWidth : minWidth;
      final graph = SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _ChannelPainter(
            band: band,
            channels: channels,
            networks: networks.where((n) => n.band == band).toList(),
            highlight: highlight,
            grid: theme.colorScheme.outlineVariant,
            text: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
      return width > c.maxWidth
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: graph)
          : graph;
    });
  }
}

class _ChannelPainter extends CustomPainter {
  _ChannelPainter({
    required this.band,
    required this.channels,
    required this.networks,
    required this.highlight,
    required this.grid,
    required this.text,
  });

  final WifiBand band;
  final List<int> channels;
  final List<WifiNetwork> networks;
  final String? highlight;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const bottom = 18.0;
    final plot = Rect.fromLTWH(left, 6, size.width - left - 6, size.height - bottom - 6);
    final lo = frequencyOf(band, channels.first) - 20;
    final hi = frequencyOf(band, channels.last) + 20;
    double xOf(num f) => plot.left + (f - lo) / (hi - lo) * plot.width;
    double yOf(num dbm) => plot.bottom - _dbmToUnit(dbm) * plot.height;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (final dbm in const [-90, -70, -50, -30]) {
      final y = yOf(dbm);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _label(canvas, '$dbm', Offset(left - 3, y), alignRight: true);
    }
    final every = channels.length > 30 ? 4 : (channels.length > 14 ? 2 : 1);
    for (var i = 0; i < channels.length; i++) {
      final ch = channels[i];
      final x = xOf(frequencyOf(band, ch));
      if (band == WifiBand.ghz5 && isDfs(ch)) {
        canvas.drawRect(
          Rect.fromLTRB(x - 8, plot.top, x + 8, plot.bottom),
          Paint()..color = grid.withValues(alpha: 0.18),
        );
      }
      if (i % every == 0) _label(canvas, '$ch', Offset(x, plot.bottom + 9), center: true);
    }

    final sorted = [...networks]..sort((a, b) => a.rssi.compareTo(b.rssi));
    for (var i = 0; i < sorted.length; i++) {
      final n = sorted[i];
      final color = seriesPalette[n.bssid.hashCode.abs() % seriesPalette.length];
      final (f0, f1) = n.span;
      final x0 = xOf(f0);
      final x1 = xOf(f1);
      final peak = yOf(n.rssi);
      final base = plot.bottom;
      final rise = (x1 - x0) * 0.18;
      final path = Path()
        ..moveTo(x0, base)
        ..cubicTo(x0 + rise * 0.3, peak, x0 + rise, peak, x0 + rise * 1.4, peak)
        ..lineTo(x1 - rise * 1.4, peak)
        ..cubicTo(x1 - rise, peak, x1 - rise * 0.3, peak, x1, base);
      final emphasised = highlight == null || highlight == n.bssid;
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: emphasised ? 0.16 : 0.04));
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: emphasised ? 1 : 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = highlight == n.bssid ? 2.6 : 1.4,
      );
      if (emphasised) {
        _label(canvas, n.displayName, Offset((x0 + x1) / 2, peak - 7), center: true, color: color, bold: true);
      }
    }
  }

  void _label(Canvas canvas, String s, Offset at,
      {bool alignRight = false, bool center = false, Color? color, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
            color: color ?? text, fontSize: 9, fontWeight: bold ? FontWeight.w600 : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110);
    final dx = alignRight ? at.dx - tp.width : (center ? at.dx - tp.width / 2 : at.dx);
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ChannelPainter old) => true;
}

/// One bar per channel: height is the strongest signal on it, the number on
/// top is how many networks use it, the suggested channel is outlined.
class ChannelBars extends StatelessWidget {
  const ChannelBars({super.key, required this.band, required this.networks, this.height = 110});

  final WifiBand band;
  final List<WifiNetwork> networks;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loads = channelLoads(band, networks);
    final suggested = suggestedChannel(band, networks);
    final minWidth = loads.length * 22.0 + 10;
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth > minWidth ? c.maxWidth : minWidth;
      final bars = SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _BarsPainter(loads, suggested, theme.colorScheme.onSurfaceVariant,
              theme.colorScheme.primary, theme.colorScheme.surfaceContainerHighest),
        ),
      );
      return width > c.maxWidth
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: bars)
          : bars;
    });
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.loads, this.suggested, this.text, this.accent, this.empty);
  final List<ChannelLoad> loads;
  final int suggested;
  final Color text;
  final Color accent;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 16.0;
    const top = 14.0;
    final slot = size.width / loads.length;
    final h = size.height - bottom - top;
    final every = loads.length > 30 ? 4 : (loads.length > 14 ? 2 : 1);
    for (var i = 0; i < loads.length; i++) {
      final l = loads[i];
      final x = i * slot + slot * 0.15;
      final w = slot * 0.7;
      final unit = l.strongest == null ? 0.0 : _dbmToUnit(l.strongest!);
      final barTop = top + h * (1 - unit);
      canvas.drawRect(Rect.fromLTWH(x, top, w, h), Paint()..color = empty);
      if (l.strongest != null) {
        canvas.drawRect(Rect.fromLTRB(x, barTop, x + w, top + h), Paint()..color = signalColor(l.strongest!));
      }
      if (l.channel == suggested) {
        canvas.drawRect(
          Rect.fromLTWH(x - 1.5, top - 1.5, w + 3, h + 3),
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if (l.networks > 0) _text(canvas, '${l.networks}', Offset(x + w / 2, barTop - 7));
      if (i % every == 0 || l.channel == suggested) {
        _text(canvas, '${l.channel}', Offset(x + w / 2, size.height - bottom / 2),
            bold: l.channel == suggested);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset c, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: bold ? accent : text, fontSize: 9, fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

/// Each row is one scan result set (newest at the bottom), each column a
/// channel, coloured by the strongest signal seen on it.
class ChannelWaterfall extends StatelessWidget {
  const ChannelWaterfall({super.key, required this.band, required this.rows, this.rowHeight = 6});

  final WifiBand band;
  final List<Map<int, int>> rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channels = channelsOf(band);
    final minWidth = channels.length * 14.0;
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth > minWidth ? c.maxWidth : minWidth;
      final w = SizedBox(
        width: width,
        height: rows.length * rowHeight + 2,
        child: CustomPaint(
          painter: _WaterfallPainter(channels, rows, rowHeight, theme.colorScheme.surfaceContainerHighest),
        ),
      );
      return width > c.maxWidth ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: w) : w;
    });
  }
}

class _WaterfallPainter extends CustomPainter {
  _WaterfallPainter(this.channels, this.rows, this.rowHeight, this.empty);
  final List<int> channels;
  final List<Map<int, int>> rows;
  final double rowHeight;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / channels.length;
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < channels.length; c++) {
        final dbm = rows[r][channels[c]];
        final color = dbm == null ? empty : signalColor(dbm).withValues(alpha: 0.25 + 0.75 * _dbmToUnit(dbm));
        canvas.drawRect(Rect.fromLTWH(c * cw, r * rowHeight, cw - 1, rowHeight - 1), Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_WaterfallPainter old) => true;
}
