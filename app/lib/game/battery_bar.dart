import 'package:echo_core/echo_core.dart';
import 'package:flutter/material.dart';

import 'palette.dart' as palette;

/// Moves left in the run, drawn as a battery that drains from full (tick 0)
/// to empty ([max]). Screen readers get the exact count.
class BatteryBar extends StatelessWidget {
  const BatteryBar({
    required this.tick,
    this.max = Rules.maxTicksPerRun,
    super.key,
  });

  static const fillKey = Key('battery-fill');

  /// At or below this fraction left, the fill turns to the warning colour.
  static const _lowFraction = 0.3;

  final int tick;
  final int max;

  @override
  Widget build(BuildContext context) {
    final fraction = ((max - tick) / max).clamp(0.0, 1.0);
    final color = fraction <= _lowFraction
        ? palette.doorClosed
        : palette.platePressed;
    return Semantics(
      label: 'Battery, ${max - tick} moves left',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 14,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(color: palette.gridLine, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  key: fillKey,
                  widthFactor: fraction,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            // The battery's terminal nub.
            Container(
              width: 3,
              height: 6,
              decoration: BoxDecoration(
                color: palette.gridLine,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
