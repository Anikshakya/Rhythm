import 'dart:async';
import 'dart:math';
import 'package:rxdart/rxdart.dart' as rx;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(
    children: [],
  );
  final List<MediaItem> _queue = [];
  int? _currentIndex;
  bool _shuffleModeEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  List<int> _originalIndices = [];

  // Stream controllers for position data
  final StreamController<Duration> _positionController =
      StreamController<Duration>();
  final StreamController<Duration> _bufferedPositionController =
      StreamController<Duration>();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>();

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;

  AudioPlayerHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Forward streams
    _player.positionStream.listen(_positionController.add);
    _player.bufferedPositionStream.listen(_bufferedPositionController.add);
    _player.durationStream.listen(_durationController.add);

    // Auto-next when song completes
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_loopMode == LoopMode.one) {
          _player.seek(Duration.zero);
          _player.play();
        } else {
          skipToNext();
        }
      }
    });
  }

  Stream<PositionData> get positionDataStream =>
      rx.Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        positionStream,
        bufferedPositionStream,
        durationStream,
        (position, bufferedPosition, duration) =>
            PositionData(position, bufferedPosition, duration ?? Duration.zero),
      );

  /// Update queue with MediaItems (can be local file, http url, or YouTube videoId)
  Future<void> updateQueue(List<MediaItem> items, {int? initialIndex}) async {
    _queue.clear();
    _queue.addAll(items);
    _originalIndices = List.generate(items.length, (index) => index);

    if (_shuffleModeEnabled) {
      _shuffleQueue();
    }

    final audioSources = <AudioSource>[];
    for (final item in _queue) {
      final uri = item.extras?['uri'] as String?;
      final videoId = item.extras?['videoId'] as String?;

      if (videoId != null) {
        // Placeholder for YouTube (resolved dynamically in skipToQueueItem)
        audioSources.add(
          AudioSource.uri(Uri.parse("yt://$videoId"), tag: item),
        );
      } else if (uri != null && uri.startsWith('http')) {
        audioSources.add(AudioSource.uri(Uri.parse(uri), tag: item));
      } else if (uri != null) {
        audioSources.add(AudioSource.uri(Uri.file(uri), tag: item));
      }
    }

    await _playlist.clear();
    await _playlist.addAll(audioSources);

    final effectiveInitialIndex =
        _shuffleModeEnabled
            ? _originalIndices.indexOf(initialIndex ?? 0)
            : initialIndex;

    if (effectiveInitialIndex != null &&
        effectiveInitialIndex >= 0 &&
        effectiveInitialIndex < _queue.length) {
      await skipToQueueItem(effectiveInitialIndex);
    }

    queue.add(_queue);
  }

  void _shuffleQueue() {
    final random = Random();
    for (var i = _queue.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final tempItem = _queue[i];
      final tempIndex = _originalIndices[i];

      _queue[i] = _queue[j];
      _originalIndices[i] = _originalIndices[j];

      _queue[j] = tempItem;
      _originalIndices[j] = tempIndex;
    }
  }

  void toggleShuffle() {
    _shuffleModeEnabled = !_shuffleModeEnabled;
    if (_shuffleModeEnabled) {
      _shuffleQueue();
    } else {
      // Restore original order
      final tempQueue = List<MediaItem>.from(_queue);
      final tempIndices = List<int>.from(_originalIndices);

      for (var i = 0; i < _queue.length; i++) {
        final originalIndex = tempIndices[i];
        _queue[originalIndex] = tempQueue[i];
        _originalIndices[originalIndex] = tempIndices[i];
      }
    }

    if (_currentIndex != null) {
      _currentIndex = _queue.indexWhere(
        (item) => item.id == mediaItem.value?.id,
      );
    }

    queue.add(_queue);
  }

  LoopMode toggleRepeat() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.one;
        _player.setLoopMode(LoopMode.one);
        break;
      case LoopMode.one:
        _loopMode = LoopMode.all;
        _player.setLoopMode(LoopMode.all);
        break;
      case LoopMode.all:
        _loopMode = LoopMode.off;
        _player.setLoopMode(LoopMode.off);
        break;
    }

    // ❌ REMOVE playbackState.add(...)
    // AudioService manages playbackState automatically when you call setLoopMode

    return _loopMode; // return updated mode
  }


  bool get isShuffleEnabled => _shuffleModeEnabled;
  LoopMode get loopMode => _loopMode;

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;

    var item = _queue[index];
    mediaItem.add(item);

    final uri = item.extras?['uri'] as String?;
    final videoId = item.extras?['videoId'] as String?;

    if (videoId != null) {
      final yt = YoutubeExplode();
      try {
        final manifest = await yt.videos.streamsClient.getManifest(videoId);
        final streamInfo = manifest.audioOnly.withHighestBitrate();
        await _player.setAudioSource(
          AudioSource.uri(Uri.parse(streamInfo.url.toString()), tag: item),
        );
      } finally {
        yt.close();
      }
    } else if (uri != null && uri.startsWith('http')) {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(uri), tag: item));
    } else if (uri != null) {
      await _player.setAudioSource(AudioSource.uri(Uri.file(uri), tag: item));
    }

    // ✅ Update MediaItem with duration for notification slider
    final duration = await _player.load();
    if (duration != null) {
      item = item.copyWith(duration: duration);
      mediaItem.add(item);
    }

    await play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() {
    _currentIndex = null;
    return _player.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_currentIndex == null || _queue.isEmpty) return;

    if (_loopMode == LoopMode.one) {
      await _player.seek(Duration.zero);
      await play();
      return;
    }

    final nextIndex = (_currentIndex! + 1) % _queue.length;
    await skipToQueueItem(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentIndex == null || _queue.isEmpty) return;

    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    final prevIndex = (_currentIndex! - 1) % _queue.length;
    await skipToQueueItem(prevIndex);
  }

  Future<void> dispose() async {
    await _positionController.close();
    await _bufferedPositionController.close();
    await _durationController.close();
    await _player.dispose();
    await super.stop();
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState:
          const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
      repeatMode:
          _loopMode == LoopMode.off
              ? AudioServiceRepeatMode.none
              : _loopMode == LoopMode.one
              ? AudioServiceRepeatMode.one
              : AudioServiceRepeatMode.all,
      shuffleMode:
          _shuffleModeEnabled
              ? AudioServiceShuffleMode.all
              : AudioServiceShuffleMode.none,
    );
  }
}
