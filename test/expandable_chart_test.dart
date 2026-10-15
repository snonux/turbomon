import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/models/wifi.dart';
import 'package:turbomon/services/time_series.dart';
import 'package:turbomon/services/wifi_analysis.dart';
import 'package:turbomon/widgets/channel_graph.dart';
import 'package:turbomon/widgets/expandable_chart.dart';
import 'package:turbomon/widgets/usage_graph.dart';

class _SeriesNotifier extends ValueNotifier<TimeSeries> {
  _SeriesNotifier(super.value);

  bool get observed => hasListeners;
}

void main() {
  Future<void> pinch(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.startGesture(
      center - const Offset(20, 0),
      pointer: 100,
    );
    final second = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 101,
    );
    await first.moveTo(center - const Offset(45, 0));
    await second.moveTo(center + const Offset(45, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(130, 0));
    await second.moveTo(center + const Offset(130, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  }

  testWidgets('live viewer zooms, pans, resets and releases its listeners', (
    tester,
  ) async {
    final series = _SeriesNotifier(TimeSeries(5));
    addTearDown(series.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveUsageGraph(
            listenable: series,
            linesBuilder: () => [
              GraphLine(series.value, color: Colors.blue, label: 'Download'),
            ],
            semanticLabel: 'Network speed graph',
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Expand Network speed graph'));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsOneWidget);
    expect(series.observed, isTrue);
    final initialSize = tester.getSize(find.byType(UsageGraph));
    expect(initialSize.height, greaterThan(72));
    expect(initialSize.isFinite, isTrue);

    // Replacing a buffer while the source route is covered must also work.
    final replacement = TimeSeries(10)..add(DateTime.utc(2026), 42);
    series.value = replacement;
    await tester.pump();
    expect(
      tester.widget<UsageGraph>(find.byType(UsageGraph)).lines.single.series,
      same(replacement),
    );
    await pinch(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final transform = viewer.transformationController!;
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(transform.value.getMaxScaleOnAxis(), lessThanOrEqualTo(8));
    final beforePan = transform.value.clone();
    await tester.drag(find.byType(InteractiveViewer), const Offset(30, 20));
    await tester.pumpAndSettle();
    expect(transform.value, isNot(beforePan));

    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pump();
    expect(transform.value, Matrix4.identity());
    await tester.tap(find.byTooltip('Close chart'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(series.observed, isFalse);
    await tester.tap(find.byTooltip('Expand Network speed graph'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value,
      Matrix4.identity(),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(series.observed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and disappearing lines remain safe in a small viewer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lines = ValueNotifier(<GraphLine>[GraphLine(TimeSeries(1))]);
    addTearDown(lines.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveUsageGraph(
            listenable: lines,
            linesBuilder: () => lines.value,
            semanticLabel: 'Signal (dBm)',
            minValue: -100,
            maxValue: -30,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Expand Signal (dBm)'));
    await tester.pumpAndSettle();
    lines.value = [];
    await tester.pump();
    expect(tester.widget<UsageGraph>(find.byType(UsageGraph)).lines, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  for (final kind in ['curves', 'bars', 'waterfall']) {
    testWidgets('$kind uses bounded live data in full screen on every band', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final updates = ValueNotifier(0);
      addTearDown(updates.dispose);
      final history = ListQueue<Map<String, WifiNetwork>>();
      for (final band in WifiBand.values) {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ExpandableChart(
                title: kind,
                listenable: updates,
                height: 90,
                builder: (context, size, expanded) {
                  final analysis = analyseBand(
                    band,
                    history.isEmpty ? [] : history.last.values.toList(),
                  );
                  return switch (kind) {
                    'curves' => ChannelGraph(
                      analysis: analysis,
                      height: size.height,
                    ),
                    'bars' => ChannelBars(
                      analysis: analysis,
                      height: size.height,
                      scrollable: !expanded,
                    ),
                    _ => ChannelWaterfall(
                      band: band,
                      history: history,
                      height: size.height,
                    ),
                  };
                },
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Expand $kind'));
        await tester.pumpAndSettle();
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.byType(InteractiveViewer)),
          ).scale(10),
          20,
        );
        final network = WifiNetwork.fromJson({
          'ssid': 'Live network',
          'bssid': '00:11:22:33:44:55',
          'frequency': band.frequencyOf(band.channels.first),
          'rssi': -45,
        });
        history.add({'network': network});
        updates.value++;
        await tester.pumpAndSettle();
        final chart = switch (kind) {
          'curves' => find.byType(ChannelGraph),
          'bars' => find.byType(ChannelBars),
          _ => find.byType(ChannelWaterfall),
        };
        expect(tester.getSize(chart).isFinite, isTrue);
        if (kind == 'curves') {
          expect(
            tester.widget<ChannelGraph>(chart).analysis.networks.single.ssid,
            'Live network',
          );
        } else if (kind == 'bars') {
          expect(tester.widget<ChannelBars>(chart).scrollable, isFalse);
          expect(
            tester.widget<ChannelBars>(chart).analysis.networks.single.rssi,
            -45,
          );
        } else {
          expect(tester.widget<ChannelWaterfall>(chart).history, isNotEmpty);
        }
        expect(tester.takeException(), isNull, reason: band.label);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        history.clear();
      }
    });
  }
}
