/// A fixed-capacity series of timestamped values, oldest first.
///
/// Every graph in TurboMon reads one of these. When full, adding a value drops
/// the oldest one, so memory stays bounded however long the app runs.
class RingBuffer {
  RingBuffer(this.capacity) : assert(capacity > 0);

  final int capacity;
  final List<double?> _values = [];
  final List<DateTime> _times = [];

  int get length => _values.length;
  bool get isEmpty => _values.isEmpty;

  /// Values oldest first; `null` marks a sample where the metric was unknown,
  /// which the graph draws as a gap rather than a zero.
  List<double?> get values => List.unmodifiable(_values);
  List<DateTime> get times => List.unmodifiable(_times);

  double? get last => _values.isEmpty ? null : _values.last;

  void add(double? value, DateTime at) {
    if (_values.length == capacity) {
      _values.removeAt(0);
      _times.removeAt(0);
    }
    _values.add(value);
    _times.add(at);
  }

  void clear() {
    _values.clear();
    _times.clear();
  }

  Iterable<double> get known => _values.whereType<double>();

  double? get average {
    final k = known.toList();
    if (k.isEmpty) return null;
    return k.reduce((a, b) => a + b) / k.length;
  }

  double? get max {
    final k = known;
    if (k.isEmpty) return null;
    return k.reduce((a, b) => a > b ? a : b);
  }

  /// Share of known samples at or above [threshold], 0..1.
  double shareAtOrAbove(double threshold) {
    final k = known.toList();
    if (k.isEmpty) return 0;
    return k.where((v) => v >= threshold).length / k.length;
  }

  /// Rebuilds the buffer with a new capacity, keeping the newest values.
  RingBuffer resized(int newCapacity) {
    final out = RingBuffer(newCapacity);
    final start = _values.length > newCapacity ? _values.length - newCapacity : 0;
    for (var i = start; i < _values.length; i++) {
      out.add(_values[i], _times[i]);
    }
    return out;
  }

  Map<String, Object?> toJson() => {
        'start': _times.isEmpty ? null : _times.first.toUtc().toIso8601String(),
        'times': _times
            .map((t) => t.millisecondsSinceEpoch ~/ 1000)
            .toList(growable: false),
        'values': _values
            .map((v) => v == null ? null : double.parse(v.toStringAsFixed(2)))
            .toList(growable: false),
      };
}
