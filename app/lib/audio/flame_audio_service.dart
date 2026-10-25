import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

import 'audio_service.dart';
import 'volume_ramp.dart';

/// [AudioService] backed by flame_audio. Every error is swallowed: sound is
/// never allowed to break the game (for example when a browser blocks
/// autoplay).
class FlameAudioService implements AudioService {
  static const _files = {
    Sfx.move: 'move.wav',
    Sfx.plate: 'plate.wav',
    Sfx.door: 'door.wav',
    Sfx.runEnd: 'run_end.wav',
    Sfx.win: 'win.wav',
    Sfx.bump: 'bump.wav',
  };

  Future<void>? _preload;
  bool _loaded = false;
  final Map<Sfx, Future<AudioPool>> _pools = {};
  bool _bgmInitialized = false;
  bool _wanted = false;
  bool _frozen = false;
  bool _rewindWanted = false;
  int _rewindGen = 0;
  Future<void> Function()? _stopRewind;

  static const _musicVolume = 0.5;

  /// Music plays at 40 % of its volume while time is frozen.
  static const _duck = 0.4;

  /// Fades into the duck when time freezes, and back out when it flows.
  static const _duckIn = Duration(milliseconds: 250);
  static const _duckOut = Duration(milliseconds: 150);

  /// Sounds that fire every beat get a pool, not a new player each time.
  static const _pooled = {Sfx.move, Sfx.bump};

  double get _targetVolume => _frozen ? _musicVolume * _duck : _musicVolume;

  late final _ramp = VolumeRamp(
    (v) => FlameAudio.bgm.audioPlayer.setVolume(v),
    initial: _musicVolume * _duck,
  );

  /// One shared load; a failure clears it so the next call retries.
  Future<void> _ensureLoaded() {
    return _preload ??= FlameAudio.audioCache
        .loadAll([..._files.values, 'ambient.wav', 'rewind.wav'])
        .then<void>((_) {
          _loaded = true;
        })
        .catchError((Object e) {
          _preload = null;
          throw e;
        });
  }

  /// One lazily created pool per pooled sound; a failure clears it so the
  /// next call retries.
  Future<AudioPool> _ensurePool(Sfx s) {
    return _pools[s] ??= FlameAudio.createPool(_files[s]!, maxPlayers: 4)
        .catchError((Object e) {
          _pools.remove(s);
          throw e;
        });
  }

  @override
  Future<void> playSfx(Sfx s) async {
    try {
      if (!_loaded) await _ensureLoaded();
      if (_pooled.contains(s)) {
        try {
          await (await _ensurePool(s)).start();
          return;
        } catch (_) {
          // Fall back to a one-shot player below.
        }
      }
      await FlameAudio.play(_files[s]!);
    } catch (_) {}
  }

  @override
  Future<void> startMusic() async {
    _wanted = true;
    try {
      await _ensureLoaded();
      if (!_bgmInitialized) {
        await FlameAudio.bgm.initialize();
        _bgmInitialized = true;
      }
      if (!_wanted || FlameAudio.bgm.isPlaying) return;
      _ramp.jump(_targetVolume);
      await FlameAudio.bgm.play('ambient.wav', volume: _targetVolume);
      if (!_wanted) await FlameAudio.bgm.stop();
    } catch (_) {}
  }

  @override
  Future<void> stopMusic() async {
    _wanted = false;
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {}
  }

  @override
  Future<void> setFrozen(bool frozen) async {
    final changed = frozen != _frozen;
    _frozen = frozen;
    // Called when a level opens: warm the sounds so a rewind press never
    // waits for a load inside the browser's gesture window.
    unawaited(_ensureLoaded().catchError((_) {}));
    if (!_bgmInitialized) {
      // Nothing playing yet: the music starts at the right level.
      _ramp.jump(_targetVolume);
    } else if (changed) {
      _ramp.to(_targetVolume, frozen ? _duckIn : _duckOut);
    }
  }

  @override
  Future<void> setRewinding(bool rewinding) async {
    _rewindWanted = rewinding;
    final gen = ++_rewindGen;
    try {
      if (!rewinding) {
        final stop = _stopRewind;
        _stopRewind = null;
        await stop?.call();
        return;
      }
      if (_stopRewind != null) return;
      if (!_loaded) await _ensureLoaded();
      final player = await FlameAudio.loop('rewind.wav', volume: 0.6);
      Future<void> stop() async {
        await player.stop();
        await player.dispose();
      }

      // Released while the loop was starting, or started again meanwhile.
      if (!_rewindWanted || gen != _rewindGen) {
        await stop();
        return;
      }
      _stopRewind = stop;
    } catch (_) {}
  }
}
