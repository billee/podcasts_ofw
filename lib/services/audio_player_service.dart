import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class AudioPlayerService {
  AudioPlayer _audioPlayer = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isSeeking = false;

  // Stream controllers for state changes
  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  // Track if disposed
  bool _isDisposed = false;

  AudioPlayerService() {
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (_isDisposed) return;
      _playerState = state;
      _safeAddToStream(_playerStateController, state);
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (_isDisposed) return;
      _duration = duration;
      _safeAddToStream(_durationController, duration);
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (_isDisposed) return;
      if (!_isSeeking) {
        _position = position;
        _safeAddToStream(_positionController, position);
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (_isDisposed) return;
      _playerState = PlayerState.stopped;
      _position = Duration.zero;
      _safeAddToStream(_playerStateController, _playerState);
      _safeAddToStream(_positionController, _position);
    });
  }

  // Safe method to add to streams
  void _safeAddToStream<T>(StreamController<T> controller, T value) {
    if (!_isDisposed && !controller.isClosed) {
      controller.add(value);
    }
  }

  // Getters
  PlayerState get playerState => _playerState;
  Duration get duration => _duration;
  Duration get position => _position;
  bool get isSeeking => _isSeeking;

  // Stream getters
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<Duration> get positionStream => _positionController.stream;

  Future<void> play(String url) async {
    if (_isDisposed) return;
    await _audioPlayer.play(UrlSource(url));
  }

  Future<void> pause() async {
    if (_isDisposed) return;
    await _audioPlayer.pause();
  }

  Future<void> resume() async {
    if (_isDisposed) return;
    await _audioPlayer.resume();
  }

  Future<void> stop() async {
    if (_isDisposed) return;
    await _audioPlayer.stop();
    _position = Duration.zero;
    _safeAddToStream(_positionController, _position);
  }

  Future<void> seek(Duration position) async {
    if (_isDisposed) return;

    _isSeeking = true;
    _position = position;
    _safeAddToStream(_positionController, _position);

    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      print('Error seeking: $e');
    }

    _isSeeking = false;
  }

  void dispose() {
    _isDisposed = true;

    // Stop audio first
    _audioPlayer.stop();

    // Then close streams
    if (!_playerStateController.isClosed) {
      _playerStateController.close();
    }
    if (!_durationController.isClosed) {
      _durationController.close();
    }
    if (!_positionController.isClosed) {
      _positionController.close();
    }

    // Finally dispose audio player
    _audioPlayer.dispose();
  }
}
