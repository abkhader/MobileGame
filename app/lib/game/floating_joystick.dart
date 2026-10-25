import 'package:echo_core/echo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'flow_controller.dart';
import 'game_clock.dart';

/// Maps a thumb offset from the joystick's centre (logical px, screen y grows
/// downward) to a move. The dominant axis wins; ties go horizontal. Null
/// inside the [deadZone].
Move? joystickDirection(Offset delta, {double deadZone = 12}) {
  if (delta.distance < deadZone) return null;
  if (delta.dx.abs() >= delta.dy.abs()) {
    return delta.dx > 0 ? Move.right : Move.left;
  }
  return delta.dy > 0 ? Move.down : Move.up;
}

/// How far the steering centre trails the thumb, in logical px. Shorter than
/// the drawn ring, so corners turn after a short move.
const double _leash = 20;

/// A joystick that appears wherever a thumb lands on [child] and holds a
/// move while the thumb is pushed off-centre. The steering centre trails the
/// thumb on a short leash (20 px), so a turn needs only a short move; the
/// drawn ring follows separately at its own radius.
///
/// Pointer moves never rebuild: the ring and knob repaint alone, inside their
/// own [RepaintBoundary].
class FloatingJoystick extends StatefulWidget {
  const FloatingJoystick({required this.flow, required this.child, super.key});

  final FlowController flow;
  final Widget child;

  static const ringRadius = 44.0;
  static const knobRadius = 20.0;

  @override
  State<FloatingJoystick> createState() => _FloatingJoystickState();
}

/// Where the ring sits and the knob's offset from its centre.
typedef _Stick = ({Offset origin, Offset knob});

class _FloatingJoystickState extends State<FloatingJoystick> {
  int? _pointer;

  /// Steering centre: direction is measured from here.
  Offset _origin = Offset.zero;

  /// Where the ring is drawn; follows the thumb at the ring's radius.
  Offset _ring = Offset.zero;
  Move? _dir;
  final _stick = ValueNotifier<_Stick?>(null);

  @override
  void initState() {
    super.initState();
    widget.flow.releaseEpoch.addListener(_forget);
  }

  @override
  void didUpdateWidget(FloatingJoystick old) {
    super.didUpdateWidget(old);
    if (old.flow != widget.flow) {
      old.flow.releaseEpoch.removeListener(_forget);
      widget.flow.releaseEpoch.addListener(_forget);
    }
  }

  @override
  void dispose() {
    widget.flow.releaseEpoch.removeListener(_forget);
    _stick.dispose();
    super.dispose();
  }

  /// Every input was released elsewhere: drop the tracked thumb.
  void _forget() {
    _pointer = null;
    _dir = null;
    _stick.value = null;
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    // Mouse: only the primary button drives Pip.
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) {
      return;
    }
    _pointer = e.pointer;
    _origin = e.localPosition;
    _ring = e.localPosition;
    _stick.value = (origin: _ring, knob: Offset.zero);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final pos = e.localPosition;
    var delta = pos - _origin;
    if (delta.distance > _leash) {
      // Pull the steering centre along behind the thumb.
      delta = delta / delta.distance * _leash;
      _origin = pos - delta;
    }
    const max = FloatingJoystick.ringRadius;
    var knob = pos - _ring;
    if (knob.distance > max) {
      knob = knob / knob.distance * max;
      _ring = pos - knob;
    }
    final dir = joystickDirection(delta);
    if (dir != _dir) {
      _dir = dir;
      if (dir == null) {
        widget.flow.release(IntentKind.move, InputSource.joystick);
      } else {
        widget.flow.press(IntentKind.move, dir, InputSource.joystick);
      }
    }
    _stick.value = (origin: _ring, knob: knob);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    if (_dir != null) {
      widget.flow.release(IntentKind.move, InputSource.joystick);
    }
    _pointer = null;
    _dir = null;
    _stick.value = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _StickPainter(_stick)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter(this.stick) : super(repaint: stick);

  final ValueListenable<_Stick?> stick;

  static final _ring = Paint()
    ..color = const Color(0x55FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final _fill = Paint()..color = const Color(0x18FFFFFF);
  static final _knobPaint = Paint()..color = const Color(0x99FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final s = stick.value;
    if (s == null) return;
    const r = FloatingJoystick.ringRadius - 1;
    canvas
      ..drawCircle(s.origin, r, _fill)
      ..drawCircle(s.origin, r, _ring)
      ..drawCircle(s.origin + s.knob, FloatingJoystick.knobRadius, _knobPaint);
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.stick != stick;
}
