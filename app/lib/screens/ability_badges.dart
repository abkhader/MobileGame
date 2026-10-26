import 'package:flutter/material.dart';

import '../art/spark_icon.dart';
import '../game/palette.dart' as palette;

/// One ability Pip will learn in a later round, and the sparks it needs.
class AbilityBadge {
  const AbilityBadge(this.name, this.threshold);

  final String name;
  final int threshold;
}

const abilityBadges = [
  AbilityBadge('Dash', 15),
  AbilityBadge('Light burst', 35),
  AbilityBadge('Swap', 60),
  AbilityBadge('Freeze', 90),
];

/// The map header's total: a drawn spark and "n / of".
class SparkTotal extends StatelessWidget {
  const SparkTotal({required this.count, required this.of, super.key});

  final int count;
  final int of;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sparks collected, $count of $of',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SparkIcon(size: 16),
        const SizedBox(width: 6),
        Text(
          '$count / $of',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: palette.spark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// The four locked abilities: dim below their threshold, glowing at or
/// above it. They do nothing yet, so each says "Coming soon".
class AbilityBadges extends StatelessWidget {
  const AbilityBadges({required this.total, super.key});

  final int total;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final b in abilityBadges)
        Expanded(
          child: _Badge(badge: b, reached: total >= b.threshold),
        ),
    ],
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.badge, required this.reached});

  final AbilityBadge badge;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final ink = reached ? palette.spark : Colors.white38;
    final small = Theme.of(context).textTheme.labelSmall;
    return Semantics(
      container: true,
      button: true,
      label:
          '${badge.name}, ${badge.threshold} sparks, '
          '${reached ? 'reached' : 'locked'}, coming soon',
      onTap: () => _explain(context),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('badge-${badge.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _explain(context),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: reached ? palette.spark : palette.gridLine,
            ),
            boxShadow: reached
                ? [
                    BoxShadow(
                      color: palette.spark.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  badge.name,
                  style: small?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SparkIcon(size: 10, color: ink),
                  const SizedBox(width: 3),
                  Text(
                    '${badge.threshold}',
                    style: small?.copyWith(color: ink),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Coming soon',
                  style: small?.copyWith(color: Colors.white54, fontSize: 9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _explain(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            container: true,
            label:
                '${badge.name} unlocks at ${badge.threshold} sparks. '
                'Collect sparks to power Pip.',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${badge.name} unlocks at '),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: SparkIcon(size: 14),
                  ),
                  TextSpan(
                    text: ' ${badge.threshold}. Collect sparks to power Pip.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
