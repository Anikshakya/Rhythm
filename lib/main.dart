import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:rxdart/rxdart.dart' as rx;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize AudioHandler first
  final audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.audio',
      androidNotificationChannelName: 'Audio Player',
      androidNotificationOngoing: true,
    ),
  );
  
  // Register with GetX
  Get.put<AudioHandler>(audioHandler);
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Audio Player',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AudioPlayerPage(),
    );
  }
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  final List<MediaItem> _queue = [];
  int? _currentIndex;

  // Stream controllers for position data
  final StreamController<Duration> _positionController = StreamController<Duration>();
  final StreamController<Duration> _bufferedPositionController = StreamController<Duration>();
  final StreamController<Duration?> _durationController = StreamController<Duration?>();

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get bufferedPositionStream => _bufferedPositionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;

  AudioPlayerHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    
    // Listen to player streams and forward them
    _player.positionStream.listen(_positionController.add);
    _player.bufferedPositionStream.listen(_bufferedPositionController.add);
    _player.durationStream.listen(_durationController.add);

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  Stream<PositionData> get positionDataStream => rx.Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
    positionStream,
    bufferedPositionStream,
    durationStream,
    (position, bufferedPosition, duration) => PositionData(
      position,
      bufferedPosition,
      duration ?? Duration.zero,
    ),
  );

  Future<void> updateQueue(List<MediaItem> items, {int? initialIndex}) async {
    _queue.clear();
    _queue.addAll(items);
    
    final audioSources = items.map((item) => AudioSource.uri(
      Uri.parse(item.extras!['uri'] as String),
      tag: item,
    )).toList();
    
    await _playlist.clear();
    await _playlist.addAll(audioSources);
    
    if (initialIndex != null) {
      await skipToQueueItem(initialIndex);
    }
    
    queue.add(_queue);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    mediaItem.add(_queue[index]);
    await _player.seek(Duration.zero);
    await _player.setAudioSource(_playlist, initialIndex: index);
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
    final nextIndex = (_currentIndex! + 1) % _queue.length;
    await skipToQueueItem(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentIndex == null || _queue.isEmpty) return;
    final prevIndex = (_currentIndex! - 1) % _queue.length;
    await skipToQueueItem(prevIndex);
  }

  @override
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
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
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
    );
  }
}

class AudioPlayerController extends GetxController {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final RxList<SongModel> songs = <SongModel>[].obs;
  final RxList<MediaItem> mediaItems = <MediaItem>[].obs;
  final Rxn<MediaItem> currentMediaItem = Rxn<MediaItem>();
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final RxBool isPlaying = false.obs;
  final RxBool isLoading = true.obs;

  AudioHandler get audioHandler => Get.find<AudioHandler>();

  @override
  void onInit() {
    super.onInit();
    fetchSongs();
    _setupAudioHandlerListeners();
  }

  Future<void> fetchSongs() async {
    try {
      isLoading.value = true;
      final fetchedSongs = await _audioQuery.querySongs(
        sortType: SongSortType.DISPLAY_NAME,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      songs.assignAll(fetchedSongs.where((song) => song.duration != null && song.duration! > 0));
      await _convertSongsToMediaItems();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _convertSongsToMediaItems() async {
    mediaItems.assignAll(await Future.wait(songs.map((song) => _songToMediaItem(song))));
  }

  Future<MediaItem> _songToMediaItem(SongModel song) async {
    Uri? artUri;
    try {
      final artBytes = await _audioQuery.queryArtwork(song.id, ArtworkType.AUDIO);
      if (artBytes != null) {
        final tempDir = await getTemporaryDirectory();
        final artPath = '${tempDir.path}/${song.id}_art.jpg';
        final file = File(artPath);
        await file.writeAsBytes(artBytes);
        artUri = Uri.file(artPath);
      }
    } catch (_) {}

    return MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist ?? 'Unknown Artist',
      album: song.album ?? 'Unknown Album',
      duration: Duration(milliseconds: song.duration ?? 0),
      artUri: artUri,
      extras: {'uri': song.uri ?? song.data},
    );
  }

  void _setupAudioHandlerListeners() {
    final handler = audioHandler as AudioPlayerHandler;
    
    handler.mediaItem.listen((mediaItem) {
      currentMediaItem.value = mediaItem;
    });

    handler.playbackState.listen((state) {
      isPlaying.value = state.playing;
    });

    handler.positionDataStream.listen((positionData) {
      position.value = positionData.position;
      duration.value = positionData.duration;
    });
  }

  void playSong(int index) {
    final handler = audioHandler as AudioPlayerHandler;
    handler.updateQueue(mediaItems, initialIndex: index);
  }

  void playPause() {
    if (isPlaying.value) {
      audioHandler.pause();
    } else {
      audioHandler.play();
    }
  }

  void seek(Duration position) {
    audioHandler.seek(position);
  }

  void skipToNext() {
    audioHandler.skipToNext();
  }

  void skipToPrevious() {
    audioHandler.skipToPrevious();
  }
}

class AudioPlayerPage extends StatelessWidget {
  final AudioPlayerController controller = Get.put(AudioPlayerController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Audio Player')),
      body: Obx(() {
        if (controller.isLoading.value) {
          return Center(child: CircularProgressIndicator());
        }
        
        return Column(
          children: [
            if (controller.currentMediaItem.value != null)
              _buildNowPlaying(controller.currentMediaItem.value!),
            
            _buildProgressBar(),
            
            _buildControls(),
            
            Expanded(
              child: ListView.builder(
                itemCount: controller.songs.length,
                itemBuilder: (context, index) {
                  final song = controller.songs[index];
                  return ListTile(
                    leading: FutureBuilder<Uint8List?>(
                      future: controller._audioQuery.queryArtwork(song.id, ArtworkType.AUDIO),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.memory(snapshot.data!, width: 50, height: 50);
                        }
                        return Icon(Icons.music_note, size: 50);
                      },
                    ),
                    title: Text(song.title),
                    subtitle: Text(song.artist ?? 'Unknown Artist'),
                    onTap: () => controller.playSong(index),
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildNowPlaying(MediaItem mediaItem) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (mediaItem.artUri != null)
            Image.network(mediaItem.artUri.toString(), width: 200, height: 200)
          else
            Icon(Icons.music_note, size: 200),
          SizedBox(height: 16),
          Text(mediaItem.title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(mediaItem.artist ?? 'Unknown Artist', style: TextStyle(fontSize: 18)),
          Text(mediaItem.album ?? 'Unknown Album', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Obx(() {
            final position = controller.position.value;
            final duration = controller.duration.value;
            return Slider(
              min: 0,
              max: duration.inMilliseconds.toDouble(),
              value: min(position.inMilliseconds.toDouble(), duration.inMilliseconds.toDouble()),
              onChanged: (value) {
                controller.position.value = Duration(milliseconds: value.toInt());
              },
              onChangeEnd: (value) {
                controller.seek(Duration(milliseconds: value.toInt()));
              },
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Obx(() {
              final position = controller.position.value;
              final duration = controller.duration.value;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position)),
                  Text(_formatDuration(duration)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.skip_previous, size: 40),
            onPressed: controller.skipToPrevious,
          ),
          Obx(() => IconButton(
            icon: Icon(controller.isPlaying.value ? Icons.pause : Icons.play_arrow, size: 50),
            onPressed: controller.playPause,
          )),
          IconButton(
            icon: Icon(Icons.skip_next, size: 40),
            onPressed: controller.skipToNext,
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}