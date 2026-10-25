import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A press-and-hold button: [onStart] when a finger lands, [onEnd] when it
/// lifts. A screen-reader tap counts as a short hold.
class HoldButton extends StatefulWidget {
  const HoldButton({
    required this.icon,
    required this.label,
    required this.onStart,
    required this.onEnd,
    this.releaseEpoch,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  /// When it changes, every input was released elsewhere (the app went to
  /// the background): forget the finger and the pressed look.
  final ValueListenable<int>? releaseEpoch;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  int? _pointer;

  @override
  void initState() {
    super.initState();
    widget.releaseEpoch?.addListener(_forget);
  }

  @override
  void didUpdateWidget(HoldButton old) {
    super.didUpdateWidget(old);
    if (old.releaseEpoch != widget.releaseEpoch) {
      old.releaseEpoch?.removeListener(_forget);
      widget.releaseEpoch?.addListener(_forget);
    }
  }

  @override
  void dispose() {
    widget.releaseEpoch?.removeListener(_forget);
    super.dispose();
  }

  void _forget() {
    if (_pointer != null) setState(() => _pointer = null);
  }

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
          // At least a 48 x 48 touch target.
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
