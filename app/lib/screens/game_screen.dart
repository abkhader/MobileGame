import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Picture, PictureRecorder, PointMode;

import 'package:echo_core/echo_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../app_services.dart';
import '../art/pip.dart';
import '../art/spark_icon.dart';
import '../art/spark_star.dart';
import '../audio/audio_service.dart';
import '../audio/game_sounds.dart';
import '../game/board_effects.dart' show AlphaRamp;
import '../game/echo_board.dart';
import '../game/floating_joystick.dart';
import '../game/flow_controller.dart';
import '../game/flow_keys.dart';
import '../game/game_clock.dart';
import '../game/game_controller.dart';
import '../game/haptics.dart';
import '../game/hits.dart';
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

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const _winDelay = Duration(milliseconds: 400);

  GameController? _controller;
  FlowController? _flow;
  GameState? _lastState;
  EchoBoard? _board;
  bool _failed = false;
  Timer? _winTimer;
  bool _hintUnlocked = false;
  bool _adBusy = false;
  bool _rewound = false;
  bool _pushed = false;
  bool _tipShown = false;
  bool _tipVisible = false;
  String _tipText = _rewindTip;
  Timer? _tipTimer;
  // Latched by the first beat: the 1-01 thumb hint never comes back.
  bool _moved = false;
  // The spark fly: from a tile to the HUD counter and back, drawn over the
  // whole column.
  final _flyLayerKey = GlobalKey();
  final _flyKey = GlobalKey<_SparkFlyState>();
  final _gameKey = GlobalKey();
  final _counterKey = GlobalKey();
  // Grabbed sparks still flying to the counter; its number waits for them.
  final _sparksInbound = ValueNotifier<int>(0);

  @visibleForTesting
  GameController? get controllerForTesting => _controller;

  @visibleForTesting
  FlowController? get flowForTesting => _flow;

  @visibleForTesting
  EchoBoard? get boardForTesting => _board;

  /// Stars in the air between the board and the counter.
  @visibleForTesting
  int get sparkFlightsForTesting => _flyKey.currentState?.activeCount ?? 0;

  /// The end radius of spark [i]'s flight, or null when it is not flying.
  @visibleForTesting
  double? sparkFlightRadiusForTesting(int i) =>
      _flyKey.currentState?.radiusOf(i);

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
      final flow = FlowController(
        game: controller,
        speed: () => widget.services.progress.moveSpeed,
      );
      flow.bumps.addListener(_onBump);
      flow.frozenListenable.addListener(_onFrozen);
      flow.rewinding.addListener(_onRewinding);
      // Time starts frozen: the music ducks until the first input.
      _onFrozen();
      setState(() {
        _controller = controller;
        _flow = flow;
        _board = EchoBoard(
          flow,
          beatLength: () => widget.services.progress.moveSpeed.beat,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onChanged() {
    final c = _controller!;
    final before = _lastState!;
    _playSounds(c);
    _flySparks(c, before);
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
    if (c.state.tick > 0 || c.state.runIndex > 0) _moved = true;
    if (c.lastEvent == GameEvent.runEnded) _onRewound();
    if (c.lastEvent == GameEvent.hit) _onZapped(c);
    _syncHint();
    setState(() {});
  }

  // The board's game loop drives the flow clock and pauses itself once time
  // is frozen and its effects have settled. Any input wakes it.
  void _wake() => _board?.wake();

  void _press(IntentKind kind, [Move? dir]) {
    _flow?.press(kind, dir);
    _wake();
  }

  void _release(IntentKind kind) {
    _flow?.release(kind);
    _wake();
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
        _wake();
      case AppLifecycleState.resumed || AppLifecycleState.detached:
        break;
    }
  }

  void _newEcho() {
    final c = _controller;
    if (c != null && _canNewEcho(c)) c.endRun();
  }

  /// Level 1-03 teaches echoes until the first rewind: its tip says "Tap New
  /// echo", the button pulses, and the first-rewind tip has never shown.
  bool _echoLesson(GameController c) =>
      c.level.id == '1-03' &&
      !_rewound &&
      widget.services.progress.rewindTipsShown == 0;

  /// [GameController.canEndRun], except during the 1-03 lesson at tick 0: a
  /// player obeying the tip at once would make a 0-move echo and waste the
  /// level's only spare run. Everywhere else New echo works at tick 0.
  bool _canNewEcho(GameController c) =>
      c.canEndRun && !(_echoLesson(c) && c.state.tick == 0);

  void _restart() => _controller?.restart();

  static const _rewindTipsMax = 2;
  static const _rewindTip =
      'Echo created. It will repeat every move you just made.';
  static const _tipDuration = Duration(milliseconds: 3500);
  static const _zappedDuration = Duration(seconds: 2);

  /// The forced-rewind banner, by what hit Pip.
  static String hitBanner(HitCause cause) => switch (cause) {
    HitCause.laser => 'Zapped! Pip rewinds.',
    HitCause.hole => 'Pip fell! Pip rewinds.',
    HitCause.shade => 'Caught! Pip rewinds.',
  };

  /// A run ended and play goes on: explain the echo, for the first rewinds.
  void _onRewound() {
    _rewound = true;
    final progress = widget.services.progress;
    if (progress.rewindTipsShown >= _rewindTipsMax) return;
    unawaited(progress.markRewindTipShown().catchError((_) {}));
    _showBanner(_rewindTip, _tipDuration);
  }

  /// Pip was hit and play goes on in the next run: say so every time, by
  /// cause. It takes the rewind tip's place; a hit on the last run shows the
  /// lost card instead. A forced rewind is still a rewind: it counts for the
  /// 1-03 nudge (`_rewound`) but not toward the echo tip's two showings.
  void _onZapped(GameController c) {
    _rewound = true;
    final cause = c.lastPipHit?.cause ?? HitCause.laser;
    _showBanner(hitBanner(cause), _zappedDuration);
  }

  void _showBanner(String text, Duration duration) {
    _tipTimer?.cancel();
    _tipTimer = Timer(duration, () {
      if (mounted) setState(() => _tipVisible = false);
    });
    _tipText = text;
    _tipShown = true;
    _tipVisible = true;
  }

  void _playSounds(GameController c) {
    final before = _lastState!;
    _lastState = c.state;
    final services = widget.services;
    // A push plays only the push sound: the bump fired before this step.
    final pushed = _pushed;
    _pushed = false;
    final sounds = [
      for (final sfx in soundsFor(before, c.state, c.lastEvent))
        if (!(pushed && sfx == Sfx.move)) sfx,
    ];
    if (services.progress.vibration) {
      if (c.lastEvent == GameEvent.won || c.lastPipHit != null) {
        Haptics.play(HapticKind.heavy);
      } else if (sounds.contains(Sfx.plate) || sounds.contains(Sfx.spark)) {
        Haptics.play(HapticKind.medium);
      }
    }
    if (!services.progress.sfxOn) return;
    for (final sfx in sounds) {
      unawaited(services.audio.playSfx(sfx).catchError((_) {}));
    }
  }

  static const _flyIn = Duration(milliseconds: 400);
  static const _flyBack = Duration(milliseconds: 300);
  static const _flyFade = Duration(milliseconds: 150);

  /// A grabbed spark flies to the counter; one a rewind drops flies back to
  /// its tile. A restart puts every spark back without a flight.
  void _flySparks(GameController c, GameState before) {
    final fly = _flyKey.currentState;
    if (fly == null) return;
    if (c.lastEvent == GameEvent.restarted) {
      fly.cancel();
      return;
    }
    final was = c.sparkMaskOf(before);
    final now = c.sparkMask;
    if (was == now) return;
    final reduce = _reduce;
    for (var i = 0; i < c.level.sparks.length; i++) {
      final bit = 1 << i;
      if (was & bit == now & bit) continue;
      final ends = _flyEnds(i);
      if (ends == null) continue;
      final (tile, hud, radius) = ends;
      final collect = now & bit != 0;
      final from = collect ? tile : hud;
      final to = collect ? hud : tile;
      if (reduce) {
        // A short fade where the star ends: at the counter's size there, at
        // the board's size on a tile. It never holds the counter back.
        final r = collect ? _SparkFlyState.hudRadius : radius;
        fly.fly(i, to, to, r, r, _flyFade, fade: true);
      } else {
        fly.fly(
          i,
          from,
          to,
          collect ? radius : _SparkFlyState.hudRadius,
          collect ? _SparkFlyState.hudRadius : radius,
          collect ? _flyIn : _flyBack,
          inbound: collect,
        );
      }
    }
  }

  /// Spark [i]'s tile centre, the counter's star and the board's spark
  /// radius, in the fly layer's coordinates; null before layout.
  (Offset, Offset, double)? _flyEnds(int i) {
    final board = _board;
    final layer = _flyLayerKey.currentContext?.findRenderObject();
    final game = _gameKey.currentContext?.findRenderObject();
    final counter = _counterKey.currentContext?.findRenderObject();
    if (board == null ||
        layer is! RenderBox ||
        game is! RenderBox ||
        counter is! RenderBox ||
        !layer.hasSize ||
        !game.hasSize ||
        !counter.hasSize) {
      return null;
    }
    final center = board.sparkCenter(i);
    if (center == null) return null;
    final tile = layer.globalToLocal(game.localToGlobal(center));
    final hud = layer.globalToLocal(
      counter.localToGlobal(counter.size.center(Offset.zero)),
    );
    return (tile, hud, board.cellSize * 0.2);
  }

  bool get _reduce =>
      widget.services.progress.reduceEffects ||
      MediaQuery.disableAnimationsOf(context);

  /// A push: a soft tick and a light buzz.
  void _onBump() {
    _pushed = true;
    final services = widget.services;
    if (services.progress.vibration) Haptics.play(HapticKind.light);
    if (services.progress.sfxOn) {
      unawaited(services.audio.playSfx(Sfx.bump).catchError((_) {}));
    }
  }

  void _onFrozen() {
    final frozen = _flow?.frozen ?? true;
    unawaited(widget.services.audio.setFrozen(frozen).catchError((_) {}));
  }

  void _onRewinding() {
    final rewinding = _flow?.rewinding.value ?? false;
    if (rewinding && !widget.services.progress.sfxOn) return;
    unawaited(widget.services.audio.setRewinding(rewinding).catchError((_) {}));
  }

  /// Points the board's hint at the next four beats of the best solution.
  void _syncHint() {
    final c = _controller;
    final board = _board;
    if (c == null || board == null) return;
    final beats = _hintUnlocked
        ? HintService.nextBeats(c.level, c.state)
        : null;
    board.hintSteps = beats == null
        ? null
        : HintService.stepsFor(c.state, beats);
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
    final best = c.level.bestScore ?? score;
    final sparkMask = c.sparkMask;
    // What this win adds is the difference from what was saved before.
    final before = services.progress.progressOf(levelId);
    // Replace this route explicitly: a menu may sit above it.
    final route = ModalRoute.of(context)!;
    final navigator = Navigator.of(context);
    await services.progress.recordWin(
      levelId,
      score: score,
      best: best,
      sparkMask: sparkMask,
    );
    // The level's kept goals, earned in this play or before.
    final after = services.progress.progressOf(levelId);
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
          before: before,
          after: after,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sparksInbound.dispose();
    _winTimer?.cancel();
    _tipTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final flow = _flow;
    if (flow != null) {
      flow.bumps.removeListener(_onBump);
      flow.frozenListenable.removeListener(_onFrozen);
      flow.rewinding.removeListener(_onRewinding);
      // Leaving the screen restores the music and ends a held rewind sound.
      final audio = widget.services.audio;
      unawaited(audio.setFrozen(false).catchError((_) {}));
      unawaited(audio.setRewinding(false).catchError((_) {}));
    }
    flow?.dispose();
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
        _wake();
      },
      onKeyEvent: (_, e) {
        final result = flowKeyHandler(
          e,
          _flow!,
          onNewEcho: _newEcho,
          onRestart: _restart,
        );
        _wake();
        return result;
      },
      child: Stack(
        key: _flyLayerKey,
        children: [
          _buildColumn(context, c),
          Positioned.fill(
            child: IgnorePointer(
              child: _SparkFly(key: _flyKey, inbound: _sparksInbound),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(BuildContext context, GameController c) {
    final state = c.state;
    final reduce = _reduce;
    _board!.reduceEffects = reduce;
    final tip = c.level.tip;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RunDots(
                    runIndex: state.runIndex,
                    runLimit: c.level.runLimit,
                  ),
                  const SizedBox(width: 16),
                  ValueListenableBuilder<int>(
                    valueListenable: _sparksInbound,
                    builder: (_, inbound, _) => _SparkCounter(
                      iconKey: _counterKey,
                      count: state.collected.length,
                      // The number rises as each flying star lands.
                      shown: math.max(0, state.collected.length - inbound),
                      total: c.level.sparks.length,
                    ),
                  ),
                ],
              ),
              // The battery is drawn as a ring above Pip; screen readers
              // still get the exact count here.
              Semantics(
                label:
                    'Battery, ${Rules.maxTicksPerRun - state.tick} moves left',
                child: const SizedBox(width: 1, height: 1),
              ),
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
                  onChanged: _wake,
                  // The screen's Focus takes the keys; Flame would eat them.
                  child: KeyedSubtree(
                    key: _gameKey,
                    child: GameWidget(game: _board!, autofocus: false),
                  ),
                ),
              ),
              if (!reduce) ...[
                // One fade, no animation of its own: free while static.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _flow!.frozenListenable,
                      builder: (_, frozen, _) => AnimatedOpacity(
                        opacity: frozen ? 1 : 0,
                        duration: Duration(milliseconds: frozen ? 250 : 150),
                        child: const ColoredBox(
                          key: Key('frozen-tint'),
                          color: _frozenTint,
                        ),
                      ),
                    ),
                  ),
                ),
                // Only built (and only painting) while rewinding.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _flow!.rewinding,
                      builder: (_, rewinding, _) => rewinding
                          ? const RepaintBoundary(
                              child: _RewindShimmer(key: Key('rewind-shimmer')),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
              if (!reduce && c.level.id == '1-01' && !_moved)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: _ThumbHint(key: Key('thumb-hint')),
                    ),
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
                      child: _TipBanner(text: _tipText),
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
        releaseEpoch: _flow!.releaseEpoch,
      ),
    ),
  );

  /// A new echo while runs remain; on the last run the same action gives up.
  Widget _newEchoButton(GameController c) {
    final left = c.level.runLimit - c.state.runIndex - 1;
    final enabled = _canNewEcho(c);
    // Level 1-03 teaches echoes: nudge the button until it has been used.
    // The button is off at tick 0 during the lesson, so the pulse waits for
    // a first move too.
    final nudge = _echoLesson(c) && !MediaQuery.disableAnimationsOf(context);
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

/// About 8 % soft blue.
const _frozenTint = Color(0x143A6BFF);

/// Scanlines with a slow band sweeping down; exists only while rewinding.
class _RewindShimmer extends StatefulWidget {
  const _RewindShimmer({super.key});

  @override
  State<_RewindShimmer> createState() => _RewindShimmerState();
}

class _RewindShimmerState extends State<_RewindShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // The scanlines never repaint; only the thin band layer does.
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: CustomPaint(size: Size.infinite, painter: _ScanlinePainter()),
      ),
      RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _BandPainter(_controller),
        ),
      ),
    ],
  );
}

/// Records the scanlines once per size and replays the picture.
class _ScanlinePainter extends CustomPainter {
  static final _line = Paint()
    ..color = const Color(0x1A9FC4FF)
    ..strokeWidth = 1;

  Size? _size;
  Picture? _picture;

  @override
  void paint(Canvas canvas, Size size) {
    if (_size != size) {
      _picture?.dispose();
      final recorder = PictureRecorder();
      final c = Canvas(recorder);
      final lines = Float32List(((size.height / 4).ceil()) * 4);
      var i = 0;
      for (var y = 0.0; y < size.height; y += 4) {
        lines[i++] = 0;
        lines[i++] = y;
        lines[i++] = size.width;
        lines[i++] = y;
      }
      c.drawRawPoints(PointMode.lines, lines, _line);
      _picture = recorder.endRecording();
      _size = size;
    }
    canvas.drawPicture(_picture!);
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static final _band = Paint()..color = const Color(0x1F9FC4FF);

  @override
  void paint(Canvas canvas, Size size) {
    final bandY = size.height * progress.value;
    canvas.drawRect(Rect.fromLTWH(0, bandY - 24, size.width, 48), _band);
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.progress != progress;
}

/// A translucent thumb dragging right over the lower half, looping. It runs
/// while time is frozen, so it is one controller and one small painter; it
/// is removed (and disposed) at the first beat.
class _ThumbHint extends StatefulWidget {
  const _ThumbHint({super.key});

  @override
  State<_ThumbHint> createState() => _ThumbHintState();
}

class _ThumbHintState extends State<_ThumbHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _ThumbPainter(_controller));
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static final _fill = Paint();
  static final _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    // Press, drag right, lift: fade in over the first fifth, out over the last.
    final drag = Curves.easeInOut.transform((t / 0.8).clamp(0.0, 1.0));
    final fade = t < 0.2 ? t / 0.2 : (t > 0.8 ? (1 - t) / 0.2 : 1.0);
    final y = size.height * 0.75;
    final x0 = size.width * 0.3;
    final x = x0 + size.width * 0.4 * drag;
    _line.color = Color.fromRGBO(255, 255, 255, 0.25 * fade);
    canvas.drawLine(Offset(x0, y), Offset(x, y), _line);
    _fill.color = Color.fromRGBO(255, 255, 255, 0.4 * fade);
    canvas.drawCircle(Offset(x, y), 26, _fill);
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.progress != progress;
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
    // Runs after the joystick's own handlers: wake the board if needed.
    // Moves do not wake it: a direction change fires a beat, and beats wake
    // the board, so a thumb resting in the dead zone costs no frames.
    onPointerDown: (_) => onChanged(),
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

/// A drawn star and "n / 3": the sparks grabbed in this play.
class _SparkCounter extends StatelessWidget {
  const _SparkCounter({
    required this.iconKey,
    required this.count,
    required this.shown,
    required this.total,
  });

  /// On the star, so a flight lands on its centre.
  final Key iconKey;

  /// Sparks grabbed: screen readers hear it at once.
  final int count;

  /// The drawn number: [count] minus the stars still flying in.
  final int shown;
  final int total;

  static const _icon = _SparkFlyState.hudRadius * 2;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sparks, $count of $total',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          key: iconKey,
          child: const CustomPaint(
            key: Key('spark-icon'),
            size: Size.square(_icon),
            painter: SparkIconPainter(),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$shown / $total',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: palette.spark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Golden stars flying between tiles and the counter, one slot per spark so
/// quick grabs (or rewinds) all animate. One ticker drives every slot and
/// one painter draws them; the layer exists only while a star is in the air.
class _SparkFly extends StatefulWidget {
  const _SparkFly({super.key, required this.inbound});

  /// Set to the number of collect flights still in the air.
  final ValueNotifier<int> inbound;

  @override
  State<_SparkFly> createState() => _SparkFlyState();
}

/// One flight, reused: its fields are rewritten, never reallocated.
class _FlightSlot {
  bool active = false;
  double fromX = 0;
  double fromY = 0;
  double toX = 0;
  double toY = 0;
  double r0 = 0;
  double r1 = 0;
  bool fade = false;

  /// Flying in to the counter: it holds the counter's number back.
  bool inbound = false;

  /// Seconds on the ticker when it started, and how long it lasts.
  double start = 0;
  double duration = 1;
}

class _SparkFlyState extends State<_SparkFly>
    with SingleTickerProviderStateMixin {
  static const hudRadius = 7.0;
  static const slots = 3;

  late final Ticker _ticker = createTicker(_onTick);
  final List<_FlightSlot> _slots = List.generate(
    slots,
    (_) => _FlightSlot(),
    growable: false,
  );

  /// Seconds since the ticker started; repaints the painter.
  final ValueNotifier<double> _now = ValueNotifier(0);
  bool _shown = false;

  int get activeCount => _slots.where((s) => s.active).length;

  /// The end radius of slot [index]'s flight, or null when it is idle.
  double? radiusOf(int index) =>
      index >= 0 && index < slots && _slots[index].active
      ? _slots[index].r1
      : null;

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    var any = false;
    for (final s in _slots) {
      if (s.active && now - s.start >= s.duration) s.active = false;
      any |= s.active;
    }
    _syncInbound();
    _now.value = now;
    if (!any) _stop();
  }

  /// Publishes how many collect flights are in the air (only on change).
  void _syncInbound() {
    var n = 0;
    for (final s in _slots) {
      if (s.active && s.inbound) n++;
    }
    widget.inbound.value = n;
  }

  void _stop() {
    _ticker.stop();
    _now.value = 0;
    if (_shown && mounted) setState(() => _shown = false);
  }

  /// Starts (or restarts) the flight of spark [index]; the others keep
  /// flying. With [fade] the star stays at [to] and fades out.
  void fly(
    int index,
    Offset from,
    Offset to,
    double r0,
    double r1,
    Duration duration, {
    bool fade = false,
    bool inbound = false,
  }) {
    if (index < 0 || index >= slots) return;
    _slots[index]
      ..active = true
      ..fromX = from.dx
      ..fromY = from.dy
      ..toX = to.dx
      ..toY = to.dy
      ..r0 = r0
      ..r1 = r1
      ..fade = fade
      ..inbound = inbound
      ..start = _ticker.isActive ? _now.value : 0
      ..duration = duration.inMicroseconds / Duration.microsecondsPerSecond;
    _syncInbound();
    if (!_ticker.isActive) unawaited(_ticker.start());
    if (!_shown) setState(() => _shown = true);
  }

  /// Drops every flight at once, e.g. on a restart.
  void cancel() {
    for (final s in _slots) {
      s.active = false;
    }
    _syncInbound();
    if (_ticker.isActive) _stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        key: const Key('spark-fly'),
        size: Size.infinite,
        painter: _SparkFlyPainter(_now, _slots),
      ),
    );
  }
}

class _SparkFlyPainter extends CustomPainter {
  _SparkFlyPainter(this.now, this.slots) : super(repaint: now);

  final ValueNotifier<double> now;
  final List<_FlightSlot> slots;

  static final _paint = Paint();
  static final _ramp = AlphaRamp(palette.spark);

  @override
  void paint(Canvas canvas, Size size) {
    final time = now.value;
    for (final s in slots) {
      if (!s.active) continue;
      final t = ((time - s.start) / s.duration).clamp(0.0, 1.0);
      final double alpha;
      final double x;
      final double y;
      if (s.fade) {
        alpha = 1 - t;
        x = s.toX;
        y = s.toY;
      } else {
        final k = Curves.easeInOutCubic.transform(t);
        // A gentle arc upward on the way.
        x = s.fromX + (s.toX - s.fromX) * k;
        y = s.fromY + (s.toY - s.fromY) * k - math.sin(math.pi * k) * 24;
        alpha = t < 0.85 ? 1 : (1 - t) / 0.15 * 0.5 + 0.5;
      }
      final r = s.r0 + (s.r1 - s.r0) * t;
      _paint.color = _ramp.at(alpha);
      canvas
        ..save()
        ..translate(x, y)
        ..scale(r)
        ..drawPath(unitSparkStar, _paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_SparkFlyPainter old) =>
      old.now != now || old.slots != slots;
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
