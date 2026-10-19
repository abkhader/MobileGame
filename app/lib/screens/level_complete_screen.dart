import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/level_repository.dart';
import 'game_screen.dart';

class LevelCompleteScreen extends StatefulWidget {
  const LevelCompleteScreen({
    required this.services,
    required this.levelId,
    required this.score,
    required this.best,
    required this.stars,
    super.key,
  });

  final AppServices services;
  final String levelId;
  final int score;
  final int best;
  final int stars;

  @override
  State<LevelCompleteScreen> createState() => _LevelCompleteScreenState();
}

class _LevelCompleteScreenState extends State<LevelCompleteScreen> {
  String? _nextId;
  int _levelNumber = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadNext();
  }

  Future<void> _loadNext() async {
    final ids = await widget.services.levels.levelIds();
    final i = ids.indexOf(widget.levelId);
    if (!mounted) return;
    setState(() {
      _levelNumber = levelNumber(ids, widget.levelId);
      _nextId = i >= 0 && i + 1 < ids.length ? ids[i + 1] : null;
      _loaded = true;
    });
  }

  void _openGame(String id) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(services: widget.services, levelId: id),
      ),
    );
  }

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
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Level complete', style: textTheme.headlineMedium),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Icon(
                    i < widget.stars ? Icons.star : Icons.star_border,
                    size: 40,
                  ),
              ],
            ),
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
    );
  }
}
