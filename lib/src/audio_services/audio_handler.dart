import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';



// Settings controller for configurable playback options
class SettingsController {
  final RxDouble volume = 0.75.obs;
  final RxBool skipSilenceEnabled = false.obs;
  final RxBool enableVolumeFadeOnPlayPause = true.obs;
  final RxInt pauseFadeDurInMilli = 200.obs;
  final RxInt playFadeDurInMilli = 200.obs;
  final RxInt seekDurationInSeconds = 10.obs;
  final RxBool previousButtonReplays = true.obs;
  LoopMode loopMode = LoopMode.off;
  final RxBool shuffleModeEnabled = false.obs;

  void save({
    double? volume,
    bool? skipSilenceEnabled,
    bool? enableVolumeFadeOnPlayPause,
    int? pauseFadeDurInMilli,
    int? playFadeDurInMilli,
    int? seekDurationInSeconds,
    bool? previousButtonReplays,
    LoopMode? loopMode,
    bool? shuffleModeEnabled,
  }) {
    if (volume != null) this.volume.value = volume;
    if (skipSilenceEnabled != null) this.skipSilenceEnabled.value = skipSilenceEnabled;
    if (enableVolumeFadeOnPlayPause != null) this.enableVolumeFadeOnPlayPause.value = enableVolumeFadeOnPlayPause;
    if (pauseFadeDurInMilli != null) this.pauseFadeDurInMilli.value = pauseFadeDurInMilli;
    if (playFadeDurInMilli != null) this.playFadeDurInMilli.value = playFadeDurInMilli;
    if (seekDurationInSeconds != null) this.seekDurationInSeconds.value = seekDurationInSeconds;
    if (previousButtonReplays != null) this.previousButtonReplays.value = previousButtonReplays;
    if (loopMode != null) this.loopMode = loopMode;
    if (shuffleModeEnabled != null) this.shuffleModeEnabled.value = shuffleModeEnabled;
  }
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final OnAudioQuery audioQuery = OnAudioQuery();
  final SettingsController settings = SettingsController();

  // Internal queue and state
  final RxList<SongModel> _queue = <SongModel>[].obs;
  final RxList<SongModel> _originalQueue = <SongModel>[].obs;
  final RxInt _currentIndex = 0.obs;
  final RxBool isPlaying = false.obs;
  final RxBool _isShuffled = false.obs;
  final BehaviorSubject<List<MediaItem>> _mediaItemQueueSubject = BehaviorSubject.seeded([]);
  final RxMap<String, File> _audioCacheMap = <String, File>{}.obs;

  // For last position restoration
  final RxMap<String, int> _trackLastPosition = <String, int>{}.obs;

  @override
  BehaviorSubject<List<MediaItem>> get queue => _mediaItemQueueSubject;

  MyAudioHandler() {
    _initPlayer();
  }

  void _initPlayer() {
    // Initialize notification configuration
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
      },
      androidCompactActionIndices: const [0, 1, 2],
    ));

    _player.playbackEventStream.listen((event) {
      _notifyPlaybackState();
    });

    _player.playingStream.listen((playing) {
      isPlaying.value = playing;
      _updateNotification();
    });

    _player.durationStream.listen((duration) {
      final currentMedia = mediaItem.value;
      if (currentMedia != null && duration != null) {
        mediaItem.add(currentMedia.copyWith(duration: duration));
        _updateNotification();
      }
    });

    _player.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
      ));
      // Save last position
      final currentSong = _queue.isNotEmpty ? _queue[_currentIndex.value] : null;
      if (currentSong != null) {
        _trackLastPosition[currentSong.id.toString()] = position.inMilliseconds;
      }
      _updateNotification();
    });

    _player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        await skipToNext();
      }
    });

    // Set initial loop and shuffle modes
    _player.setLoopMode(settings.loopMode);
    if (settings.shuffleModeEnabled.value) {
      _enableShuffle();
    }

    // Apply initial player configuration
    _player.setVolume(settings.volume.value);
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
        MediaControl.stop,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _getProcessingState(_player.processingState),
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      queueIndex: _currentIndex.value,
      shuffleMode: _isShuffled.value 
          ? AudioServiceShuffleMode.all 
          : AudioServiceShuffleMode.none,
      repeatMode: switch(_player.loopMode) {
        LoopMode.off => AudioServiceRepeatMode.none,
        LoopMode.one => AudioServiceRepeatMode.one,
        LoopMode.all => AudioServiceRepeatMode.all,
      },
    ));
  }

  void _updateNotification() {
    final currentMedia = mediaItem.value;
    if (currentMedia != null) {
      mediaItem.add(currentMedia); // Ensure media item is updated for notification
      _notifyPlaybackState();
    }
  }

  Future<MediaItem> _songToMediaItem(SongModel song, int index, int queueLength) async {
    String? artPath;
    Uri? artUri;
    try {
      final artworkBytes = await audioQuery.queryArtwork(
        song.albumId ?? song.id,
        ArtworkType.ALBUM,
        format: ArtworkFormat.JPEG,
        size: 200,
        quality: 100,
      );
      if (artworkBytes != null) {
        artPath = await queryNSave(
          id: song.albumId ?? song.id,
          type: ArtworkType.ALBUM,
          fileName: '${song.id}_art',
        );
        artUri = Uri.file(artPath);
      }
    } catch (e) {
      print('Error getting artwork: $e');
    }

    return MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist ?? 'Unknown Artist',
      album: song.album ?? 'Unknown Album',
      duration: Duration(milliseconds: song.duration ?? 0),
      artUri: artUri,
      extras: {
        'index': index,
        'queueLength': queueLength,
        'song_data': song.data,
        'art_path': artPath,
      },
    );
  }

  Future<String> queryNSave({
    required int id,
    required ArtworkType type,
    required String fileName,
    int size = 200,
    int quality = 100,
    ArtworkFormat format = ArtworkFormat.JPEG,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName.jpg');
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    if (!await file.exists()) {
      final image = await audioQuery.queryArtwork(id, type, format: format, size: size, quality: quality);
      if (image != null) {
        await file.writeAsBytes(image);
      }
    }
    return file.path;
  }

  Future<void> _updateQueue() async {
    try {
      final mediaItems = await Future.wait(
        _queue.asMap().entries.map((entry) => _songToMediaItem(entry.value, entry.key, _queue.length)),
      );
      _mediaItemQueueSubject.add(mediaItems);
      _updateNotification();
    } catch (e) {
      print('Error updating queue: $e');
      _mediaItemQueueSubject.addError(e);
    }
  }

  Future<void> setQueue(List<SongModel> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) {
      await stop();
      return;
    }

    // Save original order
    _originalQueue.assignAll(songs);
    
    // Apply shuffle if enabled
    if (settings.shuffleModeEnabled.value) {
      songs = List.from(songs); // Create a copy
      songs.shuffle();
      // Find the new position of the startIndex song
      startIndex = songs.indexWhere((song) => song.id == _originalQueue[startIndex].id);
    }

    _queue.assignAll(songs);
    _currentIndex.value = startIndex.clamp(0, songs.length - 1);
    _isShuffled.value = settings.shuffleModeEnabled.value;

    await _updateQueue();

    final currentSong = _queue[_currentIndex.value];
    final cachedFile = _audioCacheMap[currentSong.id.toString()];
    final source = cachedFile != null && await cachedFile.exists()
        ? AudioSource.uri(Uri.file(cachedFile.path))
        : AudioSource.uri(Uri.parse(currentSong.data));

    final currentMediaItem = await _songToMediaItem(currentSong, _currentIndex.value, _queue.length);
    mediaItem.add(currentMediaItem);

    try {
      await _player.setAudioSource(
        source,
        initialPosition: _trackLastPosition[currentSong.id.toString()]?.milliseconds,
      );
      if (isPlaying.value) await play();
      _updateNotification();
    } catch (e) {
      print('Error setting audio source: $e');
      if (cachedFile != null && await cachedFile.exists()) {
        try {
          await _player.setAudioSource(
            AudioSource.uri(Uri.file(cachedFile.path)),
            initialPosition: _trackLastPosition[currentSong.id.toString()]?.milliseconds,
          );
          _updateNotification();
          if (isPlaying.value) await play();
        } catch (e) {
          print('Error playing cached file: $e');
          if (_queue.length > 1) await skipToNext();
        }
      } else {
        if (_queue.length > 1) await skipToNext();
      }
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    isPlaying.value = false;
    _updateNotification();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;

    if (_currentIndex.value < _queue.length - 1) {
      _currentIndex.value++;
      await _playCurrentTrack();
    } else {
      // Handle end of queue based on loop mode
      switch (_player.loopMode) {
        case LoopMode.one:
          await seek(Duration.zero);
          await play();
        case LoopMode.all:
          _currentIndex.value = 0;
          await _playCurrentTrack();
        case LoopMode.off:
          await stop();
      }
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;

    if (settings.previousButtonReplays.value && 
        _player.position.inSeconds > settings.seekDurationInSeconds.value) {
      await seek(Duration.zero);
    } else if (_currentIndex.value > 0) {
      _currentIndex.value--;
      await _playCurrentTrack();
    } else {
      // Handle start of queue based on loop mode
      switch (_player.loopMode) {
        case LoopMode.one:
          await seek(Duration.zero);
          await play();
        case LoopMode.all:
          _currentIndex.value = _queue.length - 1;
          await _playCurrentTrack();
        case LoopMode.off:
          await seek(Duration.zero);
      }
    }
  }

  Future<void> _playCurrentTrack() async {
    final song = _queue[_currentIndex.value];
    final cachedFile = _audioCacheMap[song.id.toString()];
    final source = cachedFile != null && await cachedFile.exists()
        ? AudioSource.uri(Uri.file(cachedFile.path))
        : AudioSource.uri(Uri.parse(song.data));

    final media = await _songToMediaItem(song, _currentIndex.value, _queue.length);
    mediaItem.add(media);

    try {
      await _player.setAudioSource(
        source,
        initialPosition: _trackLastPosition[song.id.toString()]?.milliseconds,
      );
      _updateNotification();
      if (isPlaying.value) await play();
    } catch (e) {
      print('Error playing track: $e');
      if (cachedFile != null && await cachedFile.exists()) {
        try {
          await _player.setAudioSource(
            AudioSource.uri(Uri.file(cachedFile.path)),
            initialPosition: _trackLastPosition[song.id.toString()]?.milliseconds,
          );
          _updateNotification();
          if (isPlaying.value) await play();
        } catch (e) {
          print('Error playing cached file: $e');
          if (_queue.length > 1) await skipToNext();
        }
      } else {
        if (_queue.length > 1) await skipToNext();
      }
    }
  }

  @override
  Future<void> play() async {
    if (settings.enableVolumeFadeOnPlayPause.value) {
      await _player.play();
      isPlaying.value = true;
      for (var i = 0; i <= 100; i += 10) {
        await Future.delayed(Duration(milliseconds: settings.playFadeDurInMilli.value ~/ 10));
        await _player.setVolume((settings.volume.value * i / 100).clamp(0.0, 1.0));
      }
    } else {
      await _player.play();
      isPlaying.value = true;
    }
    _updateNotification();
  }

  @override
  Future<void> pause() async {
    if (settings.enableVolumeFadeOnPlayPause.value) {
      for (var i = 100; i >= 0; i -= 10) {
        await Future.delayed(Duration(milliseconds: settings.pauseFadeDurInMilli.value ~/ 10));
        await _player.setVolume((settings.volume.value * i / 100).clamp(0.0, 1.0));
      }
      await _player.pause();
      isPlaying.value = false;
    } else {
      await _player.pause();
      isPlaying.value = false;
    }
    _updateNotification();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _updateNotification();
  }

  // Loop mode control
  Future<void> setLoopMode(LoopMode mode) async {
    settings.loopMode = mode;
    await _player.setLoopMode(mode);
    _updateNotification();
  }

  // Shuffle mode control
  Future<void> toggleShuffle() async {
    if (_isShuffled.value) {
      await _disableShuffle();
    } else {
      await _enableShuffle();
    }
    settings.shuffleModeEnabled.value = _isShuffled.value;
    _updateNotification();
  }

  Future<void> _enableShuffle() async {
    if (_queue.isEmpty || _isShuffled.value) return;
    
    // Save original order
    _originalQueue.assignAll(_queue);
    
    // Shuffle the queue but keep current song at the same position
    final currentSong = _queue[_currentIndex.value];
    _queue.removeAt(_currentIndex.value);
    _queue.shuffle();
    _queue.insert(_currentIndex.value, currentSong);
    
    _isShuffled.value = true;
    await _updateQueue();
  }

  Future<void> _disableShuffle() async {
    if (!_isShuffled.value) return;
    
    // Restore original order
    final currentSong = _queue[_currentIndex.value];
    _queue.assignAll(_originalQueue);
    _currentIndex.value = _queue.indexWhere((song) => song.id == currentSong.id);
    
    _isShuffled.value = false;
    await _updateQueue();
  }

  Future<void> playSongAtIndex(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex.value = index;
      await _playCurrentTrack();
      await play();
    }
  }

  Future<void> cacheTrack(SongModel song) async {
    final dir = await getTemporaryDirectory();
    final cacheDir = Directory('${dir.path}/audio_cache');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    final cacheFile = File('${cacheDir.path}/${song.id}.mp3');
    if (!await cacheFile.exists()) {
      final sourceFile = File(song.data);
      if (await sourceFile.exists()) {
        await sourceFile.copy(cacheFile.path);
        _audioCacheMap[song.id.toString()] = cacheFile;
      }
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await _player.dispose();
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _mediaItemQueueSubject.close();
    await super.stop();
  }

  // Getters
  RxList<SongModel> get internalQueue => _queue;
  RxInt get currentIndex => _currentIndex;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  LoopMode get currentLoopMode => _player.loopMode;
  bool get isShuffleEnabled => _isShuffled.value;
}