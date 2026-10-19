import 'dart:async';

import 'package:echo_core/echo_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../game/echo_board.dart';
import '../game/game_controller.dart';
import '../game/input.dart';
import 'level_complete_screen.dart';

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
  EchoBoard? _board;
  bool _failed = false;
  Timer? _winTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final level = await widget.services.levels.load(widget.levelId);
      if (!mounted) return;
      final controller = GameController(level)..addListener(_onChanged);
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
    setState(() {});
  }

  Future<void> _defaultOnWon(GameController c) async {
    // The controller is disposed once this route is replaced: copy first.
    final services = widget.services;
    final levelId = widget.levelId;
    final score = c.state.score;
    final stars = c.stars!;
    final best = c.level.bestScore ?? score;
    await services.progress.recordCompletion(levelId, stars);
    services.completedThisSession++;
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
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
      appBar: AppBar(title: Text(controller?.level.name ?? '')),
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
              Text('Moves ${state.tick}', style: textTheme.titleMedium),
            ],
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
              _button(Icons.lightbulb_outline, 'Hint', null),
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
