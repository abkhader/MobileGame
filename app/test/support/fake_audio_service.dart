import 'package:echo_app/audio/audio_service.dart';

/// Records every call; set [throws] to make each call fail.
class FakeAudioService implements AudioService {
  FakeAudioService({this.throws = false});

  final bool throws;
  final List<Sfx> played = [];
  final List<bool> frozenCalls = [];
  final List<bool> rewindingCalls = [];
  int startMusicCalls = 0;
  int stopMusicCalls = 0;

  @override
  Future<void> playSfx(Sfx s) async {
    if (throws) throw StateError('playSfx failed');
    played.add(s);
  }

  @override
  Future<void> startMusic() async {
    startMusicCalls++;
    if (throws) throw StateError('startMusic failed');
  }

  @override
  Future<void> stopMusic() async {
    stopMusicCalls++;
    if (throws) throw StateError('stopMusic failed');
  }

  @override
  Future<void> setFrozen(bool frozen) async {
    frozenCalls.add(frozen);
    if (throws) throw StateError('setFrozen failed');
  }

  @override
  Future<void> setRewinding(bool rewinding) async {
    rewindingCalls.add(rewinding);
    if (throws) throw StateError('setRewinding failed');
  }
}
