import 'dart:ui';

import 'package:echo_core/echo_core.dart';
import 'package:flame/game.dart';

import '../art/pip.dart';
import 'board_layout.dart';
import 'game_controller.dart';
import 'palette.dart' as palette;

/// Draws the level, ghosts and player in neon, tweening each tick.
class EchoBoard extends FlameGame {
  EchoBoard(this.controller);

  final GameController controller;

  /// Cells to mark as a suggested route; null hides it.
  List<Position>? hintPath;

  static const _trailLength = 4;
  // Reused every frame so drawing allocates as little as possible.
  static final _hintPaint = Paint()
    ..color = palette.player.withValues(alpha: 0.4);
  static final _trailPaint = Paint();
  static final _tickSeconds = palette.tickDuration.inMicroseconds / 1e6;

  // Positions being tweened from; null when snapped to the controller state.
  Position? _fromPlayer;
  List<Position>? _fromGhosts;
  double _elapsed = 0;

  int _trailRun = 0;
  final List<List<Position>> _trails = [];

  bool get _animating => _fromPlayer != null;

  @override
  void onMount() {
    super.onMount();
    _resetTrails();
    controller.addListener(_onControllerChanged);
  }

  @override
  void onRemove() {
    controller.removeListener(_onControllerChanged);
    super.onRemove();
  }

  void _onControllerChanged() {
    _snap();
    final state = controller.state;
    final previous = controller.previous;
    const animated = {GameEvent.moved, GameEvent.won, GameEvent.lost};
    if (previous != null &&
        animated.contains(controller.lastEvent) &&
        previous.ghostPositions.length == state.ghostPositions.length) {
      _fromPlayer = previous.player;
      _fromGhosts = previous.ghostPositions;
      _elapsed = 0;
    }
    _recordTrails();
  }

  void _snap() {
    _fromPlayer = null;
    _fromGhosts = null;
  }

  void _resetTrails() {
    final state = controller.state;
    _trailRun = state.runIndex;
    _trails
      ..clear()
      ..addAll([
        for (final p in state.ghostPositions) [p],
      ]);
  }

  void _recordTrails() {
    final state = controller.state;
    if (state.runIndex != _trailRun ||
        _trails.length != state.ghostPositions.length) {
      _resetTrails();
      return;
    }
    for (var i = 0; i < _trails.length; i++) {
      final trail = _trails[i];
      final p = state.ghostPositions[i];
      if (trail.last != p) trail.add(p);
      if (trail.length > _trailLength) trail.removeAt(0);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_animating) return;
    _elapsed += dt;
    if (_elapsed >= _tickSeconds) _snap();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final level = controller.level;
    final state = controller.state;
    final layout = BoardLayout(
      canvas: Size(size.x, size.y),
      columns: level.width,
      rows: level.height,
    );
    if (layout.cellSize <= 0) return;
    final cell = layout.cellSize;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = palette.background,
    );
    _drawGrid(canvas, layout, level);

    final occupied = {state.player, ...state.ghostPositions};
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        final p = Position(x, y);
        final rect = layout.rectOf(p);
        switch (level.tileAt(p).kind) {
          case TileKind.wall:
            canvas.drawRect(rect, Paint()..color = palette.wall);
          case TileKind.exit:
            canvas.drawRect(
              rect.deflate(cell * 0.15),
              Paint()
                ..color = palette.exit
                ..style = PaintingStyle.stroke
                ..strokeWidth = cell * 0.06,
            );
          case TileKind.plate:
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                rect.deflate(cell * 0.18),
                Radius.circular(cell * 0.12),
              ),
              Paint()
                ..color = occupied.contains(p)
                    ? palette.platePressed
                    : palette.plateIdle,
            );
          case TileKind.door:
            final open = state.openDoors.contains(p);
            canvas.drawRect(
              Rect.fromCenter(
                center: rect.center,
                width: cell * 0.3,
                height: cell,
              ),
              Paint()..color = open ? palette.doorOpen : palette.doorClosed,
            );
          case TileKind.floor:
          case TileKind.start:
            break;
        }
      }
    }

    final hint = hintPath;
    if (hint != null) {
      for (final p in hint) {
        canvas.drawCircle(layout.centerOf(p), cell * 0.08, _hintPaint);
      }
    }

    final t = _animating ? (_elapsed / _tickSeconds).clamp(0.0, 1.0) : 1.0;
    for (var i = 0; i < state.ghostPositions.length; i++) {
      final color = palette.ghostColors[i % palette.ghostColors.length];
      if (i < _trails.length) {
        final trail = _trails[i];
        // Skip the newest entry: it is the ghost's current cell.
        for (var j = 0; j < trail.length - 1; j++) {
          final alpha = 0.15 + 0.2 * (j + 1) / trail.length;
          canvas.drawCircle(
            layout.centerOf(trail[j]),
            cell * 0.18,
            _trailPaint..color = color.withValues(alpha: alpha),
          );
        }
      }
      final from = _fromGhosts?[i] ?? state.ghostPositions[i];
      paintPip(
        canvas,
        _lerp(layout, from, state.ghostPositions[i], t),
        cell * 0.3,
        color,
        opacity: 0.55,
      );
    }

    final center = _lerp(layout, _fromPlayer ?? state.player, state.player, t);
    paintPip(canvas, center, cell * 0.3, palette.player);
  }

  void _drawGrid(Canvas canvas, BoardLayout layout, Level level) {
    final paint = Paint()
      ..color = palette.gridLine
      ..strokeWidth = 1;
    final o = layout.origin;
    final cell = layout.cellSize;
    final right = o.dx + cell * level.width;
    final bottom = o.dy + cell * level.height;
    for (var x = 0; x <= level.width; x++) {
      final dx = o.dx + x * cell;
      canvas.drawLine(Offset(dx, o.dy), Offset(dx, bottom), paint);
    }
    for (var y = 0; y <= level.height; y++) {
      final dy = o.dy + y * cell;
      canvas.drawLine(Offset(o.dx, dy), Offset(right, dy), paint);
    }
  }

  Offset _lerp(BoardLayout layout, Position from, Position to, double t) =>
      Offset.lerp(layout.centerOf(from), layout.centerOf(to), t)!;
}
