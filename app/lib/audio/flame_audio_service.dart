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
  };

  Future<void>? _preload;
  bool _bgmInitialized = false;
  bool _wanted = false;

  /// One shared load; a failure clears it so the next call retries.
  Future<void> _ensureLoaded() {
    return _preload ??= FlameAudio.audioCache
        .loadAll([..._files.values, 'ambient.wav'])
        .then<void>((_) {})
        .catchError((Object e) {
          _preload = null;
          throw e;
        });
  }

  @override
  Future<void> playSfx(Sfx s) async {
    try {
      await _ensureLoaded();
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
      await FlameAudio.bgm.play('ambient.wav', volume: 0.5);
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
}
