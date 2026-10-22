import 'dart:async';

import 'package:echo_core/echo_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../audio/game_sounds.dart';
import '../game/battery_bar.dart';
import '../game/echo_board.dart';
import '../game/game_controller.dart';
import '../game/input.dart';
import '../hints/hint_service.dart';
import 'level_complete_screen.dart';
import 'open_level.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    required this.services,
    required this.levelId,
    this.onWon,
    super.key,
  });

  final AppServices services;
  final String levelId;
  final void Function(GameController c)? onWon;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const _winDelay = Duration(milliseconds: 400);

  GameController? _controller;
  GameState? _lastState;
  EchoBoard? _board;
  bool _failed = false;
  Timer? _winTimer;
  bool _hintUnlocked = false;
  bool _adBusy = false;

  @visibleForTesting
  GameController? get controllerForTesting => _controller;

  @override
  void initState() {
    super.initState();
    // Retry music here: a browser may have blocked the earlier autoplay.
    if (widget.services.progress.musicOn) {
      unawaited(widget.services.audio.startMusic().catchError((_) {}));
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final level = await widget.services.levels.load(widget.levelId);
      if (!mounted) return;
      final controller = GameController(level)..addListener(_onChanged);
      _lastState = controller.state;
      setState(() {
        _controller = controller;
        _board = EchoBoard(controller);
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onChanged() {
    final c = _controller!;
    _playSounds(c);
    if (c.lastEvent == GameEvent.won && _winTimer == null) {
      _winTimer = Timer(_winDelay, () {
        if (!mounted) return;
        final onWon = widget.onWon;
        if (onWon != null) {
          onWon(c);
        } else {
          _defaultOnWon(c);
        }
      });
    } else if (c.state.status != GameStatus.won) {
      _winTimer?.cancel();
      _winTimer = null;
    }
    _syncHint();
    setState(() {});
  }

  void _playSounds(GameController c) {
    final before = _lastState!;
    _lastState = c.state;
    final services = widget.services;
    if (!services.progress.sfxOn) return;
    for (final sfx in soundsFor(before, c.state, c.lastEvent)) {
      unawaited(services.audio.playSfx(sfx).catchError((_) {}));
    }
  }

  /// Points the board's hint dots at the current run of the best solution.
  void _syncHint() {
    final c = _controller;
    final board = _board;
    if (c == null || board == null) return;
    board.hintPath = _hintUnlocked
        ? HintService.pathFor(c.level, c.state.runIndex)
        : null;
  }

  void _showNoAd() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('No ad available right now, try again later.'),
        ),
      );
  }

  Future<void> _onHint() async {
    if (_adBusy) return;
    _adBusy = true;
    try {
      final rewarded = await widget.services.ads.showRewarded();
      if (!mounted) return;
      if (!rewarded) return _showNoAd();
      _hintUnlocked = true;
      _syncHint();
      setState(() {});
    } finally {
      _adBusy = false;
    }
  }

  Future<void> _onSkip() async {
    if (!mounted) return;
    if (_adBusy) return;
    _adBusy = true;
    try {
      final services = widget.services;
      final rewarded = await services.ads.showRewarded();
      if (!mounted) return;
      if (!rewarded) return _showNoAd();
      await services.progress.recordSkip(widget.levelId);
      final ids = await services.levels.levelIds();
      if (!mounted) return;
      final i = ids.indexOf(widget.levelId);
      final nextId = i >= 0 && i + 1 < ids.length ? ids[i + 1] : null;
      if (nextId == null) {
        // Back to the city map underneath.
        Navigator.of(context).pop();
      } else {
        // Replaces this game route, even with a menu above it.
        await openLevel(context, services, nextId, replace: true);
      }
    } finally {
      _adBusy = false;
    }
  }

  Future<void> _defaultOnWon(GameController c) async {
    // The controller is disposed once this route is replaced: copy first.
    final services = widget.services;
    final levelId = widget.levelId;
    final score = c.state.score;
    final stars = c.stars!;
    final best = c.level.bestScore ?? score;
    // Replace this route explicitly: a menu may sit above it.
    final route = ModalRoute.of(context)!;
    final navigator = Navigator.of(context);
    await services.progress.recordCompletion(levelId, stars);
    services.completedThisSession++;
    if (!mounted) return;
    // Close any open menu or dialog above this route first.
    navigator.popUntil((r) => r == route);
    navigator.replace(
      oldRoute: route,
      newRoute: MaterialPageRoute<void>(
        builder: (_) => LevelCompleteScreen(
          services: services,
          levelId: levelId,
          score: score,
          best: best,
          stars: stars,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _winTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(controller?.level.name ?? ''),
        actions: [
          PopupMenuButton<void>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            enabled: controller != null,
            itemBuilder: (_) => [
              PopupMenuItem<void>(
                enabled: controller?.state.status == GameStatus.playing,
                onTap: _onSkip,
                child: const Text('Skip level'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _failed
            ? const _LoadErrorCard()
            : controller == null
            ? const Center(child: CircularProgressIndicator())
            : _buildGame(context, controller),
      ),
    );
  }

  Widget _buildGame(BuildContext context, GameController c) {
    final state = c.state;
    final tip = c.level.tip;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Run ${state.runIndex + 1} / ${c.level.runLimit}',
                style: textTheme.titleMedium,
              ),
              BatteryBar(tick: state.tick),
            ],
          ),
        ),
        if (_hintUnlocked && !HintService.matchesSolution(c.level, state))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Hints follow the best solution. Restart the level to match them.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall,
            ),
          ),
        if (tip != null && tip.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              tip,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('board'),
                  behavior: HitTestBehavior.opaque,
                  onPanEnd: (details) {
                    final move = swipeToMove(details.velocity.pixelsPerSecond);
                    if (move != null) c.move(move);
                  },
                  onTap: () => c.move(Move.wait),
                  child: GameWidget(game: _board!),
                ),
              ),
              if (state.status == GameStatus.lost)
                Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Out of runs', style: textTheme.titleLarge),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: c.restart,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _button(Icons.undo, 'Undo', c.canUndo ? c.undo : null),
              _button(Icons.flag, 'End run', c.canEndRun ? c.endRun : null),
              _button(Icons.replay, 'Restart', c.restart),
              _button(
                Icons.lightbulb_outline,
                'Hint',
                state.status == GameStatus.playing ? _onHint : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _button(IconData icon, String label, VoidCallback? onPressed) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        ),
      ),
    );
  }
}

class _LoadErrorCard extends StatelessWidget {
  const _LoadErrorCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("This level couldn't be loaded."),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to levels'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
