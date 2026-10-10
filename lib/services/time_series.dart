import 'dart:collection';
import 'dart:math' as math;

class SeriesPoint {
  const SeriesPoint(this.time, this.value);

  final DateTime time;
  final double value;
}

/// A fixed-size ring buffer of timestamped values: the data behind each
/// scrolling graph. The oldest point drops out once [capacity] is reached.
class TimeSeries {
  TimeSeries(this.capacity) : assert(capacity > 0);

  final int capacity;
  final _points = ListQueue<SeriesPoint>();

  int get length => _points.length;
  bool get isEmpty => _points.isEmpty;
  Iterable<SeriesPoint> get points => _points;
  Iterable<double> get values => _points.map((p) => p.value);
  SeriesPoint? get latest => _points.isEmpty ? null : _points.last;

  void add(DateTime time, double value) {
    if (!value.isFinite) return;
    _points.addLast(SeriesPoint(time, value));
    while (_points.length > capacity) {
      _points.removeFirst();
    }
  }

  void clear() => _points.clear();

  /// Keeps the newest points when the graph window changes size.
  TimeSeries resized(int newCapacity) {
    final copy = TimeSeries(newCapacity);
    for (final p in _points.skip(math.max(0, _points.length - newCapacity))) {
      copy.add(p.time, p.value);
    }
    return copy;
  }

  double? get average =>
      _points.isEmpty ? null : values.reduce((a, b) => a + b) / _points.length;

  double? get max => _points.isEmpty ? null : values.reduce(math.max);

  double? get min => _points.isEmpty ? null : values.reduce(math.min);

  /// Share of points at or above [threshold], 0–1.
  double fractionAtLeast(double threshold) => _points.isEmpty
      ? 0
      : values.where((v) => v >= threshold).length / _points.length;

  Duration get span => _points.length < 2
      ? Duration.zero
      : _points.last.time.difference(_points.first.time);

  /// `[[epochMs, value], ...]`, the compact form used in snapshots.
  List<List<num>> toJson({int decimals = 2}) => [
    for (final p in _points)
      [p.time.millisecondsSinceEpoch, _round(p.value, decimals)],
  ];

  static num _round(double v, int decimals) {
    final f = math.pow(10, decimals);
    return (v * f).round() / f;
  }
}
