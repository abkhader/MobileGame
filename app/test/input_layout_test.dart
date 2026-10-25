import 'package:echo_app/game/board_layout.dart';
import 'package:echo_app/game/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_core/echo_core.dart';

void main() {
  test('the largest grid fits a small phone board area', () {
    final l = BoardLayout(canvas: const Size(360, 480), columns: 8, rows: 10);
    expect(l.cellSize, 41);
    expect(l.origin, const Offset(16, 35));
    expect(l.centerOf(const Position(0, 0)), const Offset(36.5, 55.5));
    expect(l.rectOf(const Position(7, 9)).bottomRight, const Offset(344, 445));
  });
  test('palette matches the spec', () {
    expect(ghostColors, const [
      Color(0xFF00E5FF),
      Color(0xFFFF2BD6),
      Color(0xFFFFB300),
    ]);
    expect(tickDuration, const Duration(milliseconds: 150));
  });
}
