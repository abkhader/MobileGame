import 'dart:math' as math;
import 'dart:ui';

import 'package:echo_app/game/board_effects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrailBuffer', () {
    test('keeps only the last 0.4 tile of samples', () {
      final trail = TrailBuffer();
      for (var i = 0; i <= 20; i++) {
        trail.add(Offset(i * 0.1, 0));
      }
      expect(trail.length, closeTo(0.4, 1e-9));
      expect(trail.points.last, const Offset(2, 0));
      expect(trail.points.first.dx, closeTo(1.6, 1e-9));
    });

    test('a jump of more than a tile starts a fresh trail', () {
      final trail = TrailBuffer()
        ..add(Offset.zero)
        ..add(const Offset(0.2, 0))
        ..add(const Offset(3, 0));
      expect(trail.points, [const Offset(3, 0)]);
      expect(trail.length, 0);
    });

    test('shrink fades the tail until it is gone', () {
      final trail = TrailBuffer()
        ..add(Offset.zero)
        ..add(const Offset(0.3, 0));
      trail.shrink(0.1);
      expect(trail.length, closeTo(0.2, 1e-9));
      trail.shrink(1);
      expect(trail.isEmpty, isTrue);
    });
  });

  group('BumpNudge', () {
    test('is 0 at 0 ms, 4 px at 60 ms and 0 at 120 ms', () {
      final nudge = BumpNudge()..start(const Offset(1, 0));
      expect(nudge.distance, 0);
      nudge.update(0.06);
      expect(nudge.distance, closeTo(4, 1e-9));
      expect(nudge.offset.dx, closeTo(4, 1e-9));
      nudge.update(0.06);
      expect(nudge.distance, 0);
      expect(nudge.active, isFalse);
    });
  });

  group('DoorSlide', () {
    test('goes 0 to 1 over 150 ms', () {
      final door = DoorSlide(open: false);
      expect(door.value, 0);
      door.target = true;
      door.update(0.075);
      expect(door.value, closeTo(0.5, 1e-9));
      expect(door.active, isTrue);
      door.update(0.075);
      expect(door.value, closeTo(1, 1e-9));
      expect(door.active, isFalse);
    });
  });

  group('one-shot effects', () {
    test('plate ripple runs 300 ms, shimmer 300 ms', () {
      final ripple = PlateRipple()..start();
      ripple.update(0.15);
      expect(ripple.progress, closeTo(0.5, 1e-9));
      ripple.update(0.15);
      expect(ripple.active, isFalse);

      final shimmer = Shimmer()..start();
      shimmer.update(0.299);
      expect(shimmer.active, isTrue);
      shimmer.update(0.001);
      expect(shimmer.active, isFalse);
    });

    test('exit pulse loops every 1.2 s', () {
      final pulse = ExitPulse();
      expect(pulse.value, closeTo(0, 1e-9));
      pulse.update(0.6);
      expect(pulse.value, closeTo(1, 1e-9));
      pulse.update(0.6);
      expect(pulse.value, closeTo(0, 1e-9));
    });

    test('idle bob moves 2 px over 1.6 s', () {
      final bob = IdleBob();
      var lo = double.infinity;
      var hi = -double.infinity;
      for (var i = 0; i < 160; i++) {
        bob.update(0.01);
        lo = math.min(lo, bob.offset);
        hi = math.max(hi, bob.offset);
      }
      expect(hi - lo, closeTo(2, 0.01));
      expect(bob.offset, closeTo(0, 1e-6));
    });
  });

  group('PipMotion', () {
    void glideRight(PipMotion m) {
      m.onBeat(const Offset(1, 0));
      for (var i = 1; i <= 10; i++) {
        m.update(0.02, Offset(i * 0.1, 0));
      }
    }

    test('leans up to 8 degrees toward travel and stretches on start', () {
      final m = PipMotion();
      m.onBeat(const Offset(1, 0));
      expect(m.stretch, closeTo(0.08, 1e-9));
      glideRight(m);
      expect(m.lean, greaterThan(0));
      expect(m.lean, lessThanOrEqualTo(8 * math.pi / 180 + 1e-9));
      expect(m.trail.isEmpty, isFalse);
      expect(m.lookDir, const Offset(1, 0));
    });

    test('squashes 10% on stop and on a turn', () {
      final m = PipMotion();
      glideRight(m);
      m.onBeat(const Offset(0, 1));
      expect(m.stretch, closeTo(-0.10, 1e-9));
      m.update(1, const Offset(1, 1));
      expect(m.stretch, 0);
      m.onStop();
      expect(m.stretch, closeTo(-0.10, 1e-9));
    });

    test('with reduceEffects the trail is empty and lean is 0', () {
      final m = PipMotion(reduceEffects: true);
      glideRight(m);
      expect(m.trail.isEmpty, isTrue);
      expect(m.lean, 0);
      expect(m.stretch, 0);
      // Motion itself stays: the eye still looks toward travel.
      expect(m.lookDir, const Offset(1, 0));
    });

    test('settles: not busy once stopped and faded', () {
      final m = PipMotion();
      glideRight(m);
      m.onStop();
      expect(m.busy, isTrue);
      for (var i = 0; i < 50; i++) {
        m.update(0.02, const Offset(1, 0));
      }
      expect(m.busy, isFalse);
      expect(m.trail.isEmpty, isTrue);
    });
  });

  group('fix round 1', () {
    test('rewind beats keep Pip facing forward with no lean or kick', () {
      final m = PipMotion();
      m.onBeat(const Offset(1, 0));
      for (var i = 0; i < 20; i++) {
        m.update(0.02, Offset(i * 0.05, 0));
      }
      m.onStop();
      m.update(1, const Offset(1, 0));
      expect(m.stretch, 0);
      m.onRewindBeat();
      expect(m.stretch, 0);
      expect(m.moving, isTrue);
      for (var i = 1; i <= 10; i++) {
        m.update(0.01, Offset(1 - i * 0.1, 0));
        expect(m.lean, lessThanOrEqualTo(1e-9));
        expect(m.stretch, 0);
      }
      expect(m.lookDir, const Offset(1, 0));
      m.onStop();
      expect(m.stretch, 0);
    });

    test('FinishGlide lasts the beat it is given', () {
      final g = FinishGlide()..startFor(0.3);
      g.update(0.15);
      expect(g.progress, closeTo(0.5, 1e-9));
      g.update(0.15);
      expect(g.active, isFalse);
      expect(g.progress, 1);
    });

    test('AlphaRamp reuses the same colour objects', () {
      final ramp = AlphaRamp(const Color(0xFF00E5FF));
      expect(identical(ramp.at(0.5), ramp.at(0.5)), isTrue);
      expect(ramp.at(1).a, closeTo(1, 1e-9));
      expect(ramp.at(0).a, 0);
      expect(ramp.at(0.5).a, closeTo(0.5, 1 / 64));
    });

    test('reduced effects: battery warning steady red, win light steady', () {
      final fx = BoardEffects();
      var lit = 0;
      var dark = 0;
      for (var i = 0; i < 20; i++) {
        fx.update(
          0.05,
          flowing: true,
          ghostTiles: const [],
          reduceEffects: false,
        );
        fx.batteryRedLit(reduceEffects: false) ? lit++ : dark++;
        expect(fx.batteryRedLit(reduceEffects: true), isTrue);
      }
      expect(lit, greaterThan(0));
      expect(dark, greaterThan(0));

      fx.winFlash.start();
      final full = fx.winLight(reduceEffects: false);
      final steady = fx.winLight(reduceEffects: true);
      fx.update(0.2, flowing: false, ghostTiles: const [], reduceEffects: true);
      expect(fx.winLight(reduceEffects: false), lessThan(full));
      expect(fx.winLight(reduceEffects: true), steady);
    });
  });
}
