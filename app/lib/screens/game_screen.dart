import 'dart:async';

import 'package:echo_core/echo_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_services.dart';
import '../art/pip.dart';
import '../audio/game_sounds.dart';
import '../game/battery_bar.dart';
import '../game/echo_board.dart';
import '../game/floating_joystick.dart';
import '../game/flow_controller.dart';
import '../game/flow_keys.dart';
import '../game/game_clock.dart';
import '../game/game_controller.dart';
import '../game/hold_button.dart';
import '../game/palette.dart' as palette;
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

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _winDelay = Duration(milliseconds: 400);

  GameController? _controller;
  FlowController? _flow;
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  GameState? _lastState;
  EchoBoard? _board;
  bool _failed = false;
  Timer? _winTimer;
  bool _hintUnlocked = false;
  bool _adBusy = false;
  bool _rewound = false;
  bool _tipShown = false;
  bool _tipVisible = false;
  Timer? _tipTimer;

  @visibleForTesting
  GameController? get controllerForTesting => _controller;

  @visibleForTesting
  FlowController? get flowForTesting => _flow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        _flow = FlowController(
          game: controller,
          speed: () => widget.services.progress.moveSpeed,
        );
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
    if (c.lastEvent == GameEvent.runEnded) _onRewound();
    _syncHint();
    setState(() {});
  }

  // Drives the flow clock. Runs only while the clock runs, so a frozen game
  // forces no frames. Task 4 may move this into the board's update(dt).
  void _syncTicker() {
    final running = _flow?.clock.running ?? false;
    if (running && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!running && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    _flow?.advance(dt.inMicroseconds / Duration.microsecondsPerSecond);
    _syncTicker();
  }

  void _press(IntentKind kind, [Move? dir]) {
    _flow?.press(kind, dir);
    _syncTicker();
  }

  void _release(IntentKind kind) {
    _flow?.release(kind);
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        _flow
          ?..clock.stop()
          ..releaseAll();
        _syncTicker();
      case AppLifecycleState.resumed || AppLifecycleState.detached:
        break;
    }
  }

  void _newEcho() {
    final c = _controller;
    if (c != null && c.canEndRun) c.endRun();
  }

  void _restart() => _controller?.restart();

  static const _rewindTipsMax = 2;
  static const _rewindTip =
      'Echo created. It will repeat every move you just made.';
  static const _tipDuration = Duration(milliseconds: 3500);

  /// A run ended and play goes on: explain the echo, for the first rewinds.
  void _onRewound() {
    _rewound = true;
    final progress = widget.services.progress;
    if (progress.rewindTipsShown >= _rewindTipsMax) return;
    unawaited(progress.markRewindTipShown().catchError((_) {}));
    _tipTimer?.cancel();
    _tipTimer = Timer(_tipDuration, () {
      if (mounted) setState(() => _tipVisible = false);
    });
    _tipShown = true;
    _tipVisible = true;
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
    _tipTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _flow?.dispose();
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
    return Focus(
      autofocus: true,
      // Keys only: a semantics node here would merge the HUD labels.
      includeSemantics: false,
      // A KeyUp missed while focus was elsewhere must not leave Pip walking.
      onFocusChange: (focused) {
        if (focused) return;
        _flow?.releaseSource(InputSource.keys);
        _syncTicker();
      },
      onKeyEvent: (_, e) {
        final result = flowKeyHandler(
          e,
          _flow!,
          onNewEcho: _newEcho,
          onRestart: _restart,
        );
        _syncTicker();
        return result;
      },
      child: _buildColumn(context, c),
    );
  }

  Widget _buildColumn(BuildContext context, GameController c) {
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
              _RunDots(runIndex: state.runIndex, runLimit: c.level.runLimit),
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
                child: _BoardInput(
                  key: const Key('board'),
                  flow: _flow!,
                  onChanged: _syncTicker,
                  // The screen's Focus takes the keys; Flame would eat them.
                  child: GameWidget(game: _board!, autofocus: false),
                ),
              ),
              if (_tipShown)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _tipVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: _TipBanner(text: _rewindTip),
                    ),
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
              _holdButton(Icons.history, 'Rewind time', IntentKind.rewind),
              _holdButton(Icons.hourglass_bottom, 'Wait', IntentKind.wait),
              _newEchoButton(c),
              _button(Icons.replay, 'Restart', _restart),
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

  Widget _holdButton(IconData icon, String label, IntentKind kind) => SizedBox(
    width: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: HoldButton(
        icon: icon,
        label: label,
        onStart: () => _press(kind),
        onEnd: () => _release(kind),
      ),
    ),
  );

  /// A new echo while runs remain; on the last run the same action gives up.
  Widget _newEchoButton(GameController c) {
    final left = c.level.runLimit - c.state.runIndex - 1;
    final enabled = c.canEndRun;
    // Level 1-03 teaches echoes: nudge the button until it has been used.
    final nudge =
        c.level.id == '1-03' &&
        !MediaQuery.disableAnimationsOf(context) &&
        !_rewound &&
        widget.services.progress.rewindTipsShown == 0;
    return _button(
      left > 0 ? Icons.people_alt_outlined : Icons.flag,
      left > 0 ? 'New echo · $left left' : 'Give up',
      enabled ? _newEcho : null,
      pulse: nudge,
    );
  }

  Widget _button(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool pulse = false,
  }) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: pulse
            ? RepaintBoundary(
                child: _Pulse(
                  key: const Key('new-echo-pulse'),
                  active: onPressed != null,
                  child: button,
                ),
              )
            : button,
      ),
    );
  }
}

/// The board's input layer: the floating joystick over the Flame board.
class _BoardInput extends StatelessWidget {
  const _BoardInput({
    required this.flow,
    required this.onChanged,
    required this.child,
    super.key,
  });

  final FlowController flow;
  final VoidCallback onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    // Runs after the joystick's own handlers: wake the ticker if needed.
    onPointerDown: (_) => onChanged(),
    onPointerMove: (_) => onChanged(),
    onPointerUp: (_) => onChanged(),
    onPointerCancel: (_) => onChanged(),
    child: FloatingJoystick(flow: flow, child: child),
  );
}

class _TipBanner extends StatelessWidget {
  const _TipBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onInverseSurface),
        ),
      ),
    );
  }
}

/// Gently grows and shrinks its child while [active]: one cheap transform.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.child, super.key});

  final bool active;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: 1.08,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

/// One Pip per run: spent runs as faint echoes, the current run bright,
/// later runs dim. Repaints only when the run changes.
class _RunDots extends StatelessWidget {
  const _RunDots({required this.runIndex, required this.runLimit});

  final int runIndex;
  final int runLimit;

  static const _radius = 7.0;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    const slot = _radius * 2 + _gap;
    return Semantics(
      label: 'Run ${runIndex + 1} of $runLimit',
      excludeSemantics: true,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(slot * runLimit - _gap, _radius * 2),
          painter: _RunDotsPainter(runIndex, runLimit),
        ),
      ),
    );
  }
}

class _RunDotsPainter extends CustomPainter {
  _RunDotsPainter(this.runIndex, this.runLimit);

  final int runIndex;
  final int runLimit;

  @override
  void paint(Canvas canvas, Size size) {
    const r = _RunDots._radius;
    for (var i = 0; i < runLimit; i++) {
      final center = Offset(r + i * (r * 2 + _RunDots._gap), r);
      if (i < runIndex) {
        final ghosts = palette.ghostColors;
        paintPip(canvas, center, r, ghosts[i % ghosts.length], opacity: 0.55);
      } else if (i == runIndex) {
        paintPip(canvas, center, r, palette.player);
      } else {
        paintPip(canvas, center, r, palette.player, eyeOpen: 0, opacity: 0.18);
      }
    }
  }

  @override
  bool shouldRepaint(_RunDotsPainter old) =>
      old.runIndex != runIndex || old.runLimit != runLimit;
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
