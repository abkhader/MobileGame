import 'package:flutter/material.dart';

/// A press-and-hold button: [onStart] when a finger lands, [onEnd] when it
/// lifts. A screen-reader tap counts as a short hold.
class HoldButton extends StatefulWidget {
  const HoldButton({
    required this.icon,
    required this.label,
    required this.onStart,
    required this.onEnd,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  int? _pointer;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    setState(() => _pointer = e.pointer);
    widget.onStart();
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    setState(() => _pointer = null);
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pressed = _pointer != null;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: () {
        widget.onStart();
        widget.onEnd();
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 40,
          decoration: BoxDecoration(
            color: pressed ? scheme.primary.withValues(alpha: 0.2) : null,
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(widget.icon, size: 20, color: scheme.primary),
        ),
      ),
    );
  }
}
