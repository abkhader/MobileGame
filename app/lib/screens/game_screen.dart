import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Picture, PictureRecorder, PointMode;

import 'package:echo_core/echo_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../art/pip.dart';
import '../art/spark_star.dart';
import '../audio/audio_service.dart';
import '../audio/game_sounds.dart';
import '../game/echo_board.dart';
import '../game/floating_joystick.dart';
import '../game/flow_controller.dart';
import '../game/flow_keys.dart';
import '../game/game_clock.dart';
import '../game/game_controller.dart';
import '../game/haptics.dart';
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
  Timer? _tipTimer;
  // Latched by the first beat: the 1-01 thumb hint never comes back.
  bool _moved = false;
  // The spark fly: from a tile to the HUD counter and back, drawn over the
  // whole column.
  final _flyLayerKey = GlobalKey();
  final _flyKey = GlobalKey<_SparkFlyState>();
  final _gameKey = GlobalKey();
  final _counterKey = GlobalKey();

  @visibleForTesting
  GameController? get controllerForTesting => _controller;

  @visibleForTesting
  FlowController? get flowForTesting => _flow;

  @visibleForTesting
  EchoBoard? get boardForTesting => _board;

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
    // A push plays only the push sound: the bump fired before this step.
    final pushed = _pushed;
    _pushed = false;
    final sounds = [
      for (final sfx in soundsFor(before, c.state, c.lastEvent))
        if (!(pushed && sfx == Sfx.move)) sfx,
    ];
    if (services.progress.vibration) {
      if (c.lastEvent == GameEvent.won) {
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
        fly.fly(to, to, _hudStarRadius, _hudStarRadius, _flyFade, fade: true);
      } else {
        fly.fly(
          from,
          to,
          collect ? radius : _hudStarRadius,
          collect ? _hudStarRadius : radius,
          collect ? _flyIn : _flyBack,
        );
      }
    }
  }

  static const _hudStarRadius = 7.0;

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
    final h = counter.size.height / 2;
    final hud = layer.globalToLocal(counter.localToGlobal(Offset(h, h)));
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
    // Replace this route explicitly: a menu may sit above it.
    final route = ModalRoute.of(context)!;
    final navigator = Navigator.of(context);
    await services.progress.recordWin(
      levelId,
      score: score,
      best: best,
      sparkMask: sparkMask,
    );
    // The level's kept stars, earned in this play or before.
    final stars = services.progress.progressOf(levelId).stars;
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
            child: IgnorePointer(child: _SparkFly(key: _flyKey)),
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
                  _SparkCounter(
                    key: _counterKey,
                    count: state.collected.length,
                    total: c.level.sparks.length,
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
        releaseEpoch: _flow!.releaseEpoch,
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

/// "✦ n / 3": the sparks grabbed in this play.
class _SparkCounter extends StatelessWidget {
  const _SparkCounter({required this.count, required this.total, super.key});

  final int count;
  final int total;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sparks, $count of $total',
    excludeSemantics: true,
    child: Text(
      '✦ $count / $total',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: palette.spark,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// One golden star flying between a tile and the counter. Built only while
/// a flight runs: one controller, one small painter in its own layer.
class _SparkFly extends StatefulWidget {
  const _SparkFly({super.key});

  @override
  State<_SparkFly> createState() => _SparkFlyState();
}

typedef _Flight = ({Offset from, Offset to, double r0, double r1, bool fade});

class _SparkFlyState extends State<_SparkFly>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);

  _Flight? _flight;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _flight = null);
    }
  }

  /// Starts a flight, replacing any running one. With [fade] the star stays
  /// at [to] and fades out.
  void fly(
    Offset from,
    Offset to,
    double r0,
    double r1,
    Duration duration, {
    bool fade = false,
  }) {
    setState(() {
      _flight = (from: from, to: to, r0: r0, r1: r1, fade: fade);
    });
    _controller
      ..duration = duration
      ..forward(from: 0);
  }

  void cancel() {
    _controller.stop();
    if (_flight != null) setState(() => _flight = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flight = _flight;
    if (flight == null) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        key: const Key('spark-fly'),
        size: Size.infinite,
        painter: _SparkFlyPainter(_controller, flight),
      ),
    );
  }
}

class _SparkFlyPainter extends CustomPainter {
  _SparkFlyPainter(this.progress, this.flight) : super(repaint: progress);

  final Animation<double> progress;
  final _Flight flight;

  static final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final double alpha;
    final Offset at;
    if (flight.fade) {
      alpha = 1 - t;
      at = flight.to;
    } else {
      final k = Curves.easeInOutCubic.transform(t);
      // A gentle arc upward on the way.
      final lift = -math.sin(math.pi * k) * 24;
      at = Offset.lerp(flight.from, flight.to, k)! + Offset(0, lift);
      alpha = t < 0.85 ? 1 : (1 - t) / 0.15 * 0.5 + 0.5;
    }
    final r = flight.r0 + (flight.r1 - flight.r0) * t;
    _paint.color = palette.spark.withValues(alpha: alpha.clamp(0.0, 1.0));
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..scale(r)
      ..drawPath(unitSparkStar, _paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_SparkFlyPainter old) =>
      old.progress != progress || old.flight != flight;
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
