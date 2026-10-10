import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/model/ring_buffer.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 10, 12);
  DateTime at(int s) => t0.add(Duration(seconds: s));

  test('starts empty', () {
    final r = RingBuffer(3);
    expect(r.isEmpty, isTrue);
    expect(r.length, 0);
    expect(r.last, isNull);
    expect(r.average, isNull);
    expect(r.max, isNull);
    expect(r.shareAtOrAbove(10), 0);
  });

  test('drops the oldest value when full', () {
    final r = RingBuffer(3);
    for (var i = 1; i <= 5; i++) {
      r.add(i.toDouble(), at(i));
    }
    expect(r.length, 3);
    expect(r.values, [3, 4, 5]);
    expect(r.times, [at(3), at(4), at(5)]);
    expect(r.last, 5);
  });

  test('null samples are gaps, ignored by the statistics', () {
    final r = RingBuffer(5)
      ..add(10, at(0))
      ..add(null, at(1))
      ..add(30, at(2))
      ..add(90, at(3));
    expect(r.values, [10, null, 30, 90]);
    expect(r.known, [10, 30, 90]);
    expect(r.average, closeTo(43.33, 0.01));
    expect(r.max, 90);
    expect(r.shareAtOrAbove(30), closeTo(2 / 3, 1e-9));
    r.add(null, at(4));
    expect(r.last, isNull);
  });

  test('values and times are read-only views', () {
    final r = RingBuffer(2)..add(1, at(0));
    expect(() => r.values.add(2), throwsUnsupportedError);
    expect(() => r.times.clear(), throwsUnsupportedError);
  });

  test('clear', () {
    final r = RingBuffer(2)..add(1, at(0));
    r.clear();
    expect(r.isEmpty, isTrue);
    expect(r.times, isEmpty);
  });

  test('resized keeps the newest values in either direction', () {
    final r = RingBuffer(5);
    for (var i = 0; i < 5; i++) {
      r.add(i.toDouble(), at(i));
    }
    final small = r.resized(2);
    expect(small.capacity, 2);
    expect(small.values, [3, 4]);
    expect(small.times, [at(3), at(4)]);
    final big = r.resized(10);
    expect(big.values, [0, 1, 2, 3, 4]);
    big.add(5, at(5));
    expect(big.length, 6);
    expect(r.length, 5, reason: 'the original is untouched');
  });

  test('toJson rounds to 2 decimals and uses epoch seconds', () {
    final r = RingBuffer(3)
      ..add(1.23456, at(0))
      ..add(null, at(2));
    final j = r.toJson();
    expect(j['start'], '2026-10-10T12:00:00.000Z');
    expect(j['times'], [t0.millisecondsSinceEpoch ~/ 1000, t0.millisecondsSinceEpoch ~/ 1000 + 2]);
    expect(j['values'], [1.23, null]);
    expect(RingBuffer(1).toJson(), {'start': null, 'times': [], 'values': []});
  });
}
