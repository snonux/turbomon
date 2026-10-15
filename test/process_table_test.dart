import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/models/readings.dart';
import 'package:turbomon/widgets/process_table.dart';

List<ProcessInfo> sample(int count) => [
  for (var i = 0; i < count; i++)
    ProcessInfo(
      pid: 1000 + i,
      user: 'u0_a$i',
      name: 'process.$i',
      cpuPercent: (count - i).toDouble(),
      rssBytes: (i + 1) << 20,
      state: i.isEven ? 'R' : 'S',
      batteryMah: i.isEven ? i.toDouble() : null,
    ),
];

void main() {
  late ValueNotifier<List<ProcessInfo>> live;

  setUp(() => live = ValueNotifier(sample(75)));
  tearDown(() => live.dispose());

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1200, 1100),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder(
              valueListenable: live,
              builder: (context, rows, _) => ProcessTable(processes: rows),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> enter(WidgetTester tester, String label, String value) async {
    await tester.ensureVisible(field(label));
    await tester.enterText(field(label), value);
    await tester.pump();
  }

  testWidgets('search reaches all sampled rows and live updates preserve it', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('75 of 75 processes'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('process.74'),
      ),
      findsNothing,
    );
    await enter(tester, 'Search processes', 'process.74');
    expect(find.text('1 of 75 processes'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('process.74'),
      ),
      findsOneWidget,
    );
    live.value = sample(80);
    await tester.pumpAndSettle();
    expect(find.text('1 of 80 processes'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('process.74'),
      ),
      findsOneWidget,
    );
    live.value = sample(20);
    await tester.pumpAndSettle();
    expect(find.text('No processes match these filters.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('20 of 20 processes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sort headers change real row order and paginate all rows', (
    tester,
  ) async {
    await pump(tester);
    PaginatedDataTable table() =>
        tester.widget(find.byType(PaginatedDataTable));
    String firstPid() =>
        ((table().source.getRow(0)!.cells.first.child) as Text).data!;
    expect(firstPid(), '1000');
    await tester.tap(find.text('RSS'));
    await tester.pumpAndSettle();
    expect(table().sortAscending, isTrue);
    expect(firstPid(), '1000');
    await tester.tap(find.text('RSS'));
    await tester.pumpAndSettle();
    expect(firstPid(), '1074');
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('process.74'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byType(DropdownButton<int>));
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25').last);
    await tester.pumpAndSettle();
    expect(table().rowsPerPage, 25);
    await tester.ensureVisible(find.byTooltip('Last page'));
    await tester.tap(find.byTooltip('Last page'));
    await tester.pumpAndSettle();
    expect(find.text('process.0'), findsOneWidget);
    // Shrinking the live sample on the final page must recover to page one.
    live.value = sample(3);
    await tester.pumpAndSettle();
    expect(find.text('process.2'), findsOneWidget);
    expect(find.text('3 of 3 processes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('numeric filters validate, apply, survive samples and reset', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await enter(tester, 'Min PID', '1020');
    await enter(tester, 'Max PID', '1010');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum must be at least minimum'), findsOneWidget);
    await enter(tester, 'Min PID', 'nope');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a non-negative whole number'), findsOneWidget);
    await enter(tester, 'Min PID', '1010');
    await enter(tester, 'Max PID', '1010');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 75 processes'), findsOneWidget);
    expect(find.text('process.10'), findsOneWidget);
    live.value = sample(80);
    await tester.pumpAndSettle();
    expect(find.text('1 of 80 processes'), findsOneWidget);
    await tester.tap(find.text('Filters applied'));
    await tester.pumpAndSettle();
    await enter(tester, 'Name contains', 'absent');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 80 processes'), findsOneWidget);
    await tester.tap(find.text('Filters applied'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(
      tester.widget<TextField>(field('Min PID')).controller!.text,
      isEmpty,
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('80 of 80 processes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel preserves filters and small large-font layouts work', (
    tester,
  ) async {
    await pump(tester, size: const Size(360, 720), scale: 1.6);
    await tester.ensureVisible(find.text('Filters'));
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await enter(tester, 'Name contains', 'absent');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('75 of 75 processes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
