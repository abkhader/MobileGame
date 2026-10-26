import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/level_repository.dart';
import '../data/progress_repository.dart';
import '../game/palette.dart' as palette;
import 'open_level.dart';

class LevelCompleteScreen extends StatefulWidget {
  const LevelCompleteScreen({
    required this.services,
    required this.levelId,
    required this.score,
    required this.best,
    required this.after,
    this.before = const LevelProgress(),
    super.key,
  });

  final AppServices services;
  final String levelId;
  final int score;
  final int best;

  /// The level's saved goals before this win and after it. The goals that
  /// differ are the stars this win earned, and only those animate.
  final LevelProgress before;
  final LevelProgress after;

  @override
  State<LevelCompleteScreen> createState() => _LevelCompleteScreenState();
}

/// Which of the three goals (finished, all sparks, moves) [after] holds and
/// [before] did not.
List<bool> newlyEarnedGoals(LevelProgress before, LevelProgress after) {
  final b = before.goals;
  final a = after.goals;
  return [
    a.finished && !b.finished,
    a.allSparks && !b.allSparks,
    a.moves && !b.moves,
  ];
}

class _LevelCompleteScreenState extends State<LevelCompleteScreen>
    with SingleTickerProviderStateMixin {
  static const _flyTime = Duration(milliseconds: 300);
  static const _stagger = Duration(milliseconds: 150);

  late final List<bool> _new = newlyEarnedGoals(widget.before, widget.after);
  late final int _newCount = _new.where((e) => e).length;
  AnimationController? _fly;

  String? _nextId;
  int _levelNumber = 0;
  bool _loaded = false;
  bool _isLast = false;

  @override
  void initState() {
    super.initState();
    _loadNext();
    if (_newCount > 0) {
      // One controller for all newly earned stars; it stops when done, so
      // nothing ticks afterwards.
      _fly = AnimationController(
        vsync: this,
        duration: _flyTime + _stagger * (_newCount - 1),
      )..forward();
    }
  }

  @override
  void dispose() {
    _fly?.dispose();
    super.dispose();
  }

  List<({bool earned, String text, String label})> _goals() {
    final g = widget.after.goals;
    final n = widget.after.sparkCount;
    final sparks = g.allSparks ? 'All 3 sparks' : 'All 3 sparks ($n/3)';
    final moves = 'In ${widget.best} moves or fewer';
    String say(String what, bool earned) =>
        '$what, ${earned ? 'earned' : 'not yet'}';
    return [
      (
        earned: g.finished,
        text: 'Finished',
        label: say('Finished', g.finished),
      ),
      (
        earned: g.allSparks,
        text: sparks,
        label: g.allSparks
            ? say('All 3 sparks', true)
            : 'All 3 sparks, $n of 3',
      ),
      (earned: g.moves, text: moves, label: say(moves, g.moves)),
    ];
  }

  Widget _goalRow(int i, ({bool earned, String text, String label}) goal) {
    final textTheme = Theme.of(context).textTheme;
    Widget star = Icon(
      goal.earned ? Icons.star : Icons.star_border,
      size: 32,
      color: goal.earned ? palette.spark : Colors.white38,
    );
    final controller = _fly;
    if (_new[i] && controller != null) {
      // The nth new star starts n staggers in.
      final order = _new.take(i).where((e) => e).length;
      final total = controller.duration!.inMilliseconds;
      final start = _stagger.inMilliseconds * order / total;
      final end =
          (_stagger.inMilliseconds * order + _flyTime.inMilliseconds) / total;
      final t = controller.drive(
        CurveTween(curve: Interval(start, end, curve: Curves.easeOutBack)),
      );
      final fade = controller.drive(CurveTween(curve: Interval(start, end)));
      final reduce = widget.services.progress.reduceEffects;
      star = KeyedSubtree(
        key: ValueKey('goal-fly-$i'),
        child: FadeTransition(
          opacity: fade,
          child: reduce
              ? star
              : ScaleTransition(
                  scale: Tween<double>(begin: 0.4, end: 1).animate(t),
                  child: star,
                ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: goal.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            star,
            const SizedBox(width: 12),
            Text(
              goal.text,
              style: textTheme.titleMedium?.copyWith(
                color: goal.earned ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadNext() async {
    final ids = await widget.services.levels.levelIds();
    final i = ids.indexOf(widget.levelId);
    if (!mounted) return;
    setState(() {
      _levelNumber = levelNumber(ids, widget.levelId);
      _nextId = i >= 0 && i + 1 < ids.length ? ids[i + 1] : null;
      _isLast = ids.isNotEmpty && ids.last == widget.levelId;
      _loaded = true;
    });
  }

  void _openGame(String id) =>
      openLevel(context, widget.services, id, replace: true);

  /// Shows the between-levels interstitial when the policy asks for one.
  Future<void> _maybeInterstitial() async {
    final services = widget.services;
    final show = services.adPolicy.shouldShowInterstitial(
      completedThisSession: services.completedThisSession,
      levelNumber: _levelNumber,
    );
    if (show) await services.ads.showInterstitialIfLoaded();
  }

  Future<void> _next(String id) async {
    await _maybeInterstitial();
    if (mounted) _openGame(id);
  }

  Future<void> _levels() async {
    await _maybeInterstitial();
    if (!mounted) return;
    // The first win on the last level ends the story before the map.
    if (_isLast && !widget.services.progress.endingSeen) {
      await showEnding(context, widget.services);
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Level complete', style: textTheme.headlineMedium),
              const SizedBox(height: 16),
              for (final (i, goal) in _goals().indexed) _goalRow(i, goal),
              const SizedBox(height: 16),
              Text(
                'Score ${widget.score} · Best ${widget.best}',
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              if (_loaded && _nextId != null) ...[
                FilledButton(
                  onPressed: () => _next(_nextId!),
                  child: const Text('Next'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: () => _openGame(widget.levelId),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _levels, child: const Text('Levels')),
            ],
          ),
        ),
      ),
    );
  }
}
