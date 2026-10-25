import 'package:echo_app/audio/volume_ramp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ramps in small steps over the duration', (t) async {
    final set = <double>[];
    final ramp = VolumeRamp((v) async => set.add(v), initial: 0.5);
    ramp.to(0.2, const Duration(milliseconds: 250));
    expect(set, isEmpty);
    await t.pump(const Duration(milliseconds: 125));
    expect(set, isNotEmpty);
    expect(set.last, inExclusiveRange(0.2, 0.5));
    await t.pump(const Duration(milliseconds: 125));
    expect(set.last, closeTo(0.2, 1e-9));
    expect(set.length, greaterThanOrEqualTo(5));
    for (var i = 1; i < set.length; i++) {
      expect(set[i], lessThan(set[i - 1]));
    }
    final n = set.length;
    await t.pump(const Duration(milliseconds: 500));
    expect(set.length, n, reason: 'the timer stops at the target');
    expect(ramp.volume, closeTo(0.2, 1e-9));
  });

  testWidgets('a new target cancels the running ramp', (t) async {
    final set = <double>[];
    final ramp = VolumeRamp((v) async => set.add(v), initial: 0.5);
    ramp.to(0.2, const Duration(milliseconds: 250));
    await t.pump(const Duration(milliseconds: 100));
    final mid = ramp.volume;
    expect(mid, inExclusiveRange(0.2, 0.5));
    ramp.to(0.5, const Duration(milliseconds: 150));
    await t.pump(const Duration(milliseconds: 150));
    expect(set.last, closeTo(0.5, 1e-9));
    await t.pump(const Duration(milliseconds: 300));
    expect(set.last, closeTo(0.5, 1e-9), reason: 'the old ramp is gone');
    for (final v in set.skipWhile((v) => v != mid).skip(1)) {
      expect(v, greaterThan(mid));
    }
  });

  testWidgets('errors from the player are swallowed', (t) async {
    var calls = 0;
    final ramp = VolumeRamp((v) async {
      calls++;
      throw StateError('no player');
    }, initial: 0.5);
    ramp.to(0.2, const Duration(milliseconds: 250));
    await t.pump(const Duration(milliseconds: 300));
    expect(calls, greaterThan(0));
    expect(ramp.volume, closeTo(0.2, 1e-9));

    final sync = VolumeRamp((v) => throw StateError('sync'), initial: 0.5);
    sync.to(0.2, const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 150));
    expect(sync.volume, closeTo(0.2, 1e-9));
  });

  testWidgets('jump sets the level without a ramp; dispose stops it', (
    t,
  ) async {
    final set = <double>[];
    final ramp = VolumeRamp((v) async => set.add(v), initial: 0.5);
    ramp.to(0.2, const Duration(milliseconds: 250));
    ramp.jump(0.4);
    expect(ramp.volume, 0.4);
    await t.pump(const Duration(milliseconds: 300));
    expect(set, isEmpty);
    ramp.to(0.1, const Duration(milliseconds: 250));
    ramp.dispose();
    await t.pump(const Duration(milliseconds: 300));
    expect(set, isEmpty);
  });
}
