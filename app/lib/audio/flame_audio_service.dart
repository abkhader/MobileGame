import 'package:flame_audio/flame_audio.dart';

import 'audio_service.dart';

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
  Future<AudioPool>? _movePool;
  bool _bgmInitialized = false;
  bool _wanted = false;
  bool _frozen = false;
  bool _rewindWanted = false;
  int _rewindGen = 0;
  Future<void> Function()? _stopRewind;

  static const _musicVolume = 0.5;

  /// Music plays at 40 % of its volume while time is frozen.
  static const _duck = 0.4;

  double get _targetVolume => _frozen ? _musicVolume * _duck : _musicVolume;

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

  /// One lazily created pool for the move sound; a failure clears it so the
  /// next call retries.
  Future<AudioPool> _ensureMovePool() {
    return _movePool ??= FlameAudio.createPool(_files[Sfx.move]!, maxPlayers: 4)
        .catchError((Object e) {
          _movePool = null;
          throw e;
        });
  }

  @override
  Future<void> playSfx(Sfx s) async {
    try {
      if (!_loaded) await _ensureLoaded();
      if (s == Sfx.move) {
        try {
          await (await _ensureMovePool()).start();
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
    _frozen = frozen;
    try {
      if (_bgmInitialized) {
        await FlameAudio.bgm.audioPlayer.setVolume(_targetVolume);
      }
    } catch (_) {}
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
