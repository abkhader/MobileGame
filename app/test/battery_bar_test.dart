import 'package:echo_app/game/battery_bar.dart';
import 'package:echo_app/game/palette.dart' as palette;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, int tick) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(child: BatteryBar(tick: tick)),
    ),
  ),
);

FractionallySizedBox _fill(WidgetTester t) =>
    t.widget<FractionallySizedBox>(find.byKey(BatteryBar.fillKey));

Color? _fillColor(WidgetTester t) {
  final box = t.widget<DecoratedBox>(
    find.descendant(
      of: find.byKey(BatteryBar.fillKey),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  testWidgets('tick 0 is full', (t) async {
    await _pump(t, 0);
    expect(find.bySemanticsLabel('Battery, 25 moves left'), findsOneWidget);
    expect(_fill(t).widthFactor, 1.0);
    expect(_fillColor(t), palette.platePressed);
  });

  testWidgets('tick 25 is empty', (t) async {
    await _pump(t, 25);
    expect(find.bySemanticsLabel('Battery, 0 moves left'), findsOneWidget);
    expect(_fill(t).widthFactor, 0.0);
  });

  testWidgets('tick 20 (20% left) uses the low colour', (t) async {
    await _pump(t, 20);
    expect(_fill(t).widthFactor, closeTo(0.2, 1e-9));
    expect(_fillColor(t), palette.doorClosed);
  });

  testWidgets('tick 17 (32% left) still uses the normal colour', (t) async {
    await _pump(t, 17);
    expect(_fillColor(t), palette.platePressed);
  });
}
