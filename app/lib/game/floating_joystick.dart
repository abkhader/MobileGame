import 'package:echo_core/echo_core.dart';
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

/// A joystick that appears wherever a thumb lands in the lower 60 % of
/// [child] and holds a move while the thumb is pushed off-centre.
class FloatingJoystick extends StatefulWidget {
  const FloatingJoystick({required this.flow, required this.child, super.key});

  final FlowController flow;
  final Widget child;

  /// Top share of the box where a touch does not spawn the joystick.
  static const topShare = 0.4;
  static const ringRadius = 44.0;
  static const knobRadius = 20.0;

  @override
  State<FloatingJoystick> createState() => _FloatingJoystickState();
}

class _FloatingJoystickState extends State<FloatingJoystick> {
  int? _pointer;
  Offset _origin = Offset.zero;
  Offset _knob = Offset.zero;
  Move? _dir;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    // Mouse: only the primary button drives Pip.
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) {
      return;
    }
    final height = context.size?.height ?? 0;
    if (e.localPosition.dy < height * FloatingJoystick.topShare) return;
    setState(() {
      _pointer = e.pointer;
      _origin = e.localPosition;
      _knob = Offset.zero;
    });
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final delta = e.localPosition - _origin;
    final dir = joystickDirection(delta);
    if (dir != _dir) {
      _dir = dir;
      if (dir == null) {
        widget.flow.release(IntentKind.move, InputSource.joystick);
      } else {
        widget.flow.press(IntentKind.move, dir, InputSource.joystick);
      }
    }
    const max = FloatingJoystick.ringRadius;
    setState(() {
      _knob = delta.distance > max ? delta / delta.distance * max : delta;
    });
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    if (_dir != null) {
      widget.flow.release(IntentKind.move, InputSource.joystick);
    }
    setState(() {
      _pointer = null;
      _dir = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const r = FloatingJoystick.ringRadius;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_pointer != null)
            Positioned(
              left: _origin.dx - r,
              top: _origin.dy - r,
              width: r * 2,
              height: r * 2,
              child: IgnorePointer(
                child: CustomPaint(painter: _StickPainter(_knob)),
              ),
            ),
        ],
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter(this.knob);

  final Offset knob;

  static final _ring = Paint()
    ..color = const Color(0x55FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final _fill = Paint()..color = const Color(0x18FFFFFF);
  static final _knobPaint = Paint()..color = const Color(0x99FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas
      ..drawCircle(c, FloatingJoystick.ringRadius - 1, _fill)
      ..drawCircle(c, FloatingJoystick.ringRadius - 1, _ring)
      ..drawCircle(c + knob, FloatingJoystick.knobRadius, _knobPaint);
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.knob != knob;
}
