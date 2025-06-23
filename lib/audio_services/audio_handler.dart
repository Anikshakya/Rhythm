import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final RxList<SongModel> _queue = <SongModel>[].obs; // Internal queue for SongModel
  final RxInt _currentIndex = 0.obs;
  final RxBool isPlaying = false.obs;

  MyAudioHandler() {
    _initPlayer();
  }

  void _initPlayer() {
    _player.playbackEventStream.listen((event) {
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          isPlaying.value ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: _getProcessingState(event.processingState),
        playing: isPlaying.value,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex.value,
      ));
    });

    _player.playingStream.listen((playing) {
      isPlaying.value = playing;
      _notifyPlaybackState();
    });

    _player.durationStream.listen((duration) {
      final mediaItem = this.mediaItem.value;
      if (mediaItem != null && duration != null) {
        this.mediaItem.add(mediaItem.copyWith(duration: duration));
      }
    });

    _player.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
      ));
    });

    _player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        await skipToNext();
      }
    });
  }

  AudioProcessingState _getProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  void _notifyPlaybackState() {
    playbackState.add(playbackState.value.copyWith(
      playing: isPlaying.value,
      controls: [
        MediaControl.skipToPrevious,
        isPlaying.value ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
    ));
  }

  MediaItem _songToMediaItem(SongModel song, int index, int queueLength) {
    return MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist ?? 'Unknown Artist',
      album: song.album ?? 'Unknown Album',
      duration: Duration(milliseconds: song.duration ?? 0),
      artUri: song.uri != null ? Uri.parse(song.uri!) : null,
      extras: {
        'index': index,
        'queueLength': queueLength,
      },
    );
  }

  Future<void> setQueue(List<SongModel> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

    _queue.assignAll(songs);
    _currentIndex.value = startIndex.clamp(0, songs.length - 1);

    final mediaItems = songs.asMap().entries.map((entry) {
      return _songToMediaItem(entry.value, entry.key, songs.length);
    }).toList();

    queue.add(mediaItems); // Corrected: Assign List<MediaItem> to queue
    mediaItem.add(mediaItems[_currentIndex.value]);

    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(songs[_currentIndex.value].data),
          tag: mediaItems[_currentIndex.value],
        ),
      );
      if (isPlaying.value) {
        await play();
      }
    } catch (e) {
      print('Error setting audio source: $e');
    }
  }

  @override
  Future<void> play() async {
    await _player.play();
    isPlaying.value = true;
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    isPlaying.value = false;
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    isPlaying.value = false;
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_currentIndex.value < _queue.length - 1) {
      _currentIndex.value++;
      await _playCurrentTrack();
    } else {
      await stop();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentIndex.value > 0) {
      _currentIndex.value--;
      await _playCurrentTrack();
    } else if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
    } else {
      await _playCurrentTrack();
    }
  }

  Future<void> _playCurrentTrack() async {
    final song = _queue[_currentIndex.value];
    final mediaItem = _songToMediaItem(song, _currentIndex.value, _queue.length);
    this.mediaItem.add(mediaItem);

    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(song.data),
          tag: mediaItem,
        ),
      );
      if (isPlaying.value) {
        await play();
      }
    } catch (e) {
      print('Error playing track: $e');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> playSongAtIndex(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex.value = index;
      await _playCurrentTrack();
      await play();
    }
  }

  // Expose internal queue and index for UI
  RxList<SongModel> get songQueue => _queue;
  RxInt get currentIndex => _currentIndex;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await _player.dispose();
  }

  Future<void> dispose() async {
    // No @override since BaseAudioHandler doesn't define dispose
    await _player.dispose();
    await super.stop();
  }
}