import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:rhythm/src/components/miniplayer/mini_player.dart';
import 'package:rhythm/src/widgets/custom_blurry_container.dart';
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
      androidStopForegroundOnPause: true,
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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: AudioPlayerPage(),
      builder: (context, child) {
        return FullScreenBuilder(child: child!);
      },
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
  bool _shuffleModeEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  List<int> _originalIndices = [];

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
        if (_loopMode == LoopMode.one) {
          _player.seek(Duration.zero);
          _player.play();
        } else {
          skipToNext();
        }
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
    _originalIndices = List.generate(items.length, (index) => index);
    
    if (_shuffleModeEnabled) {
      _shuffleQueue();
    }
    
    final audioSources = _queue.map((item) => AudioSource.uri(
      Uri.parse(item.extras!['uri'] as String),
      tag: item,
    )).toList();
    
    await _playlist.clear();
    await _playlist.addAll(audioSources);
    
    final effectiveInitialIndex = _shuffleModeEnabled 
      ? _originalIndices.indexOf(initialIndex ?? 0)
      : initialIndex;
    
    if (effectiveInitialIndex != null && effectiveInitialIndex >= 0 && effectiveInitialIndex < _queue.length) {
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
    
    // Update the current index after shuffle
    if (_currentIndex != null) {
      _currentIndex = _queue.indexWhere((item) => item.id == mediaItem.value?.id);
    }
    
    queue.add(_queue);
  }

  void toggleRepeat() {
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
    playbackState.add(playbackState.value.copyWith(
      repeatMode: _loopMode == LoopMode.off 
        ? AudioServiceRepeatMode.none 
        : _loopMode == LoopMode.one 
          ? AudioServiceRepeatMode.one 
          : AudioServiceRepeatMode.all,
    ));
  }

  bool get isShuffleEnabled => _shuffleModeEnabled;
  LoopMode get loopMode => _loopMode;

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
      repeatMode: _loopMode == LoopMode.off 
      ? AudioServiceRepeatMode.none 
      : _loopMode == LoopMode.one 
        ? AudioServiceRepeatMode.one 
        : AudioServiceRepeatMode.all,
      shuffleMode: _shuffleModeEnabled 
        ? AudioServiceShuffleMode.all 
        : AudioServiceShuffleMode.none,
    );
  }
}

class AudioPlayerController extends GetxController {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final RxList<SongModel> songs = <SongModel>[].obs;
  final RxList<AlbumModel> albums = <AlbumModel>[].obs;
  final RxList<ArtistModel> artists = <ArtistModel>[].obs;
  final RxList<MediaItem> mediaItems = <MediaItem>[].obs;
  final Rxn<MediaItem> currentMediaItem = Rxn<MediaItem>();
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final RxBool isPlaying = false.obs;
  final RxBool isLoading = true.obs;
  final RxBool isShuffleEnabled = false.obs;
  final Rx<LoopMode> loopMode = LoopMode.off.obs;
  final RxInt currentTabIndex = 0.obs; // 0: Songs, 1: Albums, 2: Artists
  final RxBool showAlbumSongs = false.obs;
  final RxBool showArtistSongs = false.obs;
  final RxList<MediaItem> currentAlbumSongs = <MediaItem>[].obs;
  final RxList<MediaItem> currentArtistSongs = <MediaItem>[].obs;
  final Rxn<AlbumModel> currentAlbum = Rxn<AlbumModel>();
  final Rxn<ArtistModel> currentArtist = Rxn<ArtistModel>();

  AudioHandler get audioHandler => Get.find<AudioHandler>();

  @override
  void onInit() {
    super.onInit();
    fetchMedia();
    _setupAudioHandlerListeners();
  }

  Future<void> fetchMedia() async {
    try {
      isLoading.value = true;
      
      // Fetch all data in parallel
      final results = await Future.wait([
        _audioQuery.querySongs(
          sortType: SongSortType.DISPLAY_NAME,
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        ),
        _audioQuery.queryAlbums(),
        _audioQuery.queryArtists(),
      ]);
      
      // Process results
      final fetchedSongs = results[0] as List<SongModel>;
      songs.assignAll(fetchedSongs.where((song) => song.duration != null && song.duration! > 0));
      
      albums.assignAll(results[1] as List<AlbumModel>);
      artists.assignAll(results[2] as List<ArtistModel>);
      
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

  Future<void> loadAlbumSongs(AlbumModel album) async {
    isLoading.value = true;
    try {
      currentAlbum.value = album;
      final albumSongs = await _audioQuery.queryAudiosFrom(
        AudiosFromType.ALBUM_ID,
        album.id,
      );
      currentAlbumSongs.assignAll(
        await Future.wait(
          albumSongs.where((song) => song.duration != null && song.duration! > 0)
            .map((song) => _songToMediaItem(song))
        )
      );
      showAlbumSongs.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadArtistSongs(ArtistModel artist) async {
    isLoading.value = true;
    try {
      currentArtist.value = artist;
      final artistSongs = await _audioQuery.queryAudiosFrom(
        AudiosFromType.ARTIST_ID,
        artist.id,
      );
      currentArtistSongs.assignAll(
        await Future.wait(
          artistSongs.where((song) => song.duration != null && song.duration! > 0)
            .map((song) => _songToMediaItem(song))
        )
      );
      showArtistSongs.value = true;
    } finally {
      isLoading.value = false;
    }
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

    isShuffleEnabled.listen((enabled) {
      if (enabled != handler.isShuffleEnabled) {
        handler.toggleShuffle();
      }
    });

    loopMode.listen((mode) {
      if (mode != handler.loopMode) {
        handler.toggleRepeat();
      }
    });
  }

  void playSong(int index) {
    final handler = audioHandler as AudioPlayerHandler;
    handler.updateQueue(mediaItems, initialIndex: index);
  }

  void playAlbum(int index) {
    final handler = audioHandler as AudioPlayerHandler;
    handler.updateQueue(currentAlbumSongs, initialIndex: index);
  }

  void playArtist(int index) {
    final handler = audioHandler as AudioPlayerHandler;
    handler.updateQueue(currentArtistSongs, initialIndex: index);
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

  void toggleShuffle() {
    isShuffleEnabled.toggle();
  }

  void toggleRepeat() {
    loopMode.value = loopMode.value.next;
  }

  void backToAlbums() {
    showAlbumSongs.value = false;
    currentAlbum.value = null;
  }

  void backToArtists() {
    showArtistSongs.value = false;
    currentArtist.value = null;
  }
}

class AudioPlayerPage extends StatelessWidget {
  final AudioPlayerController controller = Get.put(AudioPlayerController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.timer),
            onPressed: () {
              // Open the sleep timer dialog
              SleepTimerManager.openSleepTimerDialog(context);
            },
          ),
        ],
        title: Obx(() {
          if (controller.showAlbumSongs.value && controller.currentAlbum.value != null) {
            return Text(controller.currentAlbum.value!.album);
          } else if (controller.showArtistSongs.value && controller.currentArtist.value != null) {
            return Text(controller.currentArtist.value!.artist ?? 'Unknown Artist');
          }
          return Text('Audio Player');
        }),
        leading: Obx(() {
          if (controller.showAlbumSongs.value || controller.showArtistSongs.value) {
            return IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () {
                if (controller.showAlbumSongs.value) {
                  controller.backToAlbums();
                } else {
                  controller.backToArtists();
                }
              },
            );
          }
          return SizedBox.shrink();
        }),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return Center(child: CircularProgressIndicator());
        }
        
        if (controller.showAlbumSongs.value) {
          return _buildAlbumSongsList();
        } else if (controller.showArtistSongs.value) {
          return _buildArtistSongsList();
        }
        
        return DefaultTabController(
          length: 3,
          child: Expanded(
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.music_note),),
                    Tab(icon: Icon(Icons.album)), 
                    Tab(icon: Icon(Icons.people)),
                  ],
                ),
                
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildSongsTab(),
                      _buildAlbumsTab(),
                      _buildArtistsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSongsTab() {
    return ListView.builder(
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
    );
  }

  Widget _buildAlbumsTab() {
    return ListView.builder(
      itemCount: controller.albums.length,
      itemBuilder: (context, index) {
        final album = controller.albums[index];
        return ListTile(
          leading: FutureBuilder<Uint8List?>(
            future: controller._audioQuery.queryArtwork(album.id, ArtworkType.ALBUM),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.memory(snapshot.data!, width: 50, height: 50);
              }
              return Icon(Icons.album, size: 50);
            },
          ),
          title: Text(album.album),
          subtitle: Text('${album.numOfSongs} songs • ${album.artist ?? 'Unknown Artist'}'),
          onTap: () => controller.loadAlbumSongs(album),
        );
      },
    );
  }

  Widget _buildArtistsTab() {
    return ListView.builder(
      itemCount: controller.artists.length,
      itemBuilder: (context, index) {
        final artist = controller.artists[index];
        return ListTile(
          leading: FutureBuilder<Uint8List?>(
            future: controller._audioQuery.queryArtwork(artist.id, ArtworkType.ARTIST),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.memory(snapshot.data!, width: 50, height: 50);
              }
              return Icon(Icons.person, size: 50);
            },
          ),
          title: Text(artist.artist ?? 'Unknown Artist'),
          subtitle: Text('${artist.numberOfAlbums} albums • ${artist.numberOfTracks} songs'),
          onTap: () => controller.loadArtistSongs(artist),
        );
      },
    );
  }

  Widget _buildAlbumSongsList() {
    return Column(
      children: [
        if (controller.currentAlbum.value != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                FutureBuilder<Uint8List?>(
                  future: controller._audioQuery.queryArtwork(
                    controller.currentAlbum.value!.id, 
                    ArtworkType.ALBUM
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return Image.memory(
                        snapshot.data!, 
                        width: 200, 
                        height: 200,
                        fit: BoxFit.cover,
                      );
                    }
                    return Icon(Icons.album, size: 200);
                  },
                ),
                SizedBox(height: 16),
                Text(
                  controller.currentAlbum.value!.album,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  controller.currentAlbum.value!.artist ?? 'Unknown Artist',
                  style: TextStyle(fontSize: 18),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      icon: Icon(Icons.shuffle),
                      label: Text('Shuffle'),
                      onPressed: () {
                        controller.isShuffleEnabled.value = true;
                        controller.playAlbum(0);
                      },
                    ),
                    SizedBox(width: 16),
                    ElevatedButton.icon(
                      icon: Icon(Icons.play_arrow),
                      label: Text('Play'),
                      onPressed: () {
                        controller.isShuffleEnabled.value = false;
                        controller.playAlbum(0);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: controller.currentAlbumSongs.length,
            itemBuilder: (context, index) {
              final mediaItem = controller.currentAlbumSongs[index];
              return ListTile(
                leading: FutureBuilder<Uint8List?>(
                  future: controller._audioQuery.queryArtwork(
                    int.parse(mediaItem.id), 
                    ArtworkType.AUDIO
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return Image.memory(snapshot.data!, width: 50, height: 50);
                    }
                    return Icon(Icons.music_note, size: 50);
                  },
                ),
                title: Text(mediaItem.title),
                subtitle: Text(mediaItem.artist ?? 'Unknown Artist'),
                trailing: Text(_formatDuration(mediaItem.duration ?? Duration.zero)),
                onTap: () => controller.playAlbum(index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildArtistSongsList() {
    return Column(
      children: [
        if (controller.currentArtist.value != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                FutureBuilder<Uint8List?>(
                  future: controller._audioQuery.queryArtwork(
                    controller.currentArtist.value!.id, 
                    ArtworkType.ARTIST
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return CircleAvatar(
                        radius: 60,
                        backgroundImage: MemoryImage(snapshot.data!),
                      );
                    }
                    return CircleAvatar(
                      radius: 60,
                      child: Icon(Icons.person, size: 60),
                    );
                  },
                ),
                SizedBox(height: 16),
                Text(
                  controller.currentArtist.value!.artist ?? 'Unknown Artist',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${controller.currentArtist.value!.numberOfTracks} songs',
                  style: TextStyle(fontSize: 18),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      icon: Icon(Icons.shuffle),
                      label: Text('Shuffle'),
                      onPressed: () {
                        controller.isShuffleEnabled.value = true;
                        controller.playArtist(0);
                      },
                    ),
                    SizedBox(width: 16),
                    ElevatedButton.icon(
                      icon: Icon(Icons.play_arrow),
                      label: Text('Play'),
                      onPressed: () {
                        controller.isShuffleEnabled.value = false;
                        controller.playArtist(0);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: controller.currentArtistSongs.length,
            itemBuilder: (context, index) {
              final mediaItem = controller.currentArtistSongs[index];
              return ListTile(
                leading: FutureBuilder<Uint8List?>(
                  future: controller._audioQuery.queryArtwork(
                    int.parse(mediaItem.id), 
                    ArtworkType.AUDIO
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return Image.memory(snapshot.data!, width: 50, height: 50);
                    }
                    return Icon(Icons.music_note, size: 50);
                  },
                ),
                title: Text(mediaItem.title),
                subtitle: Text(mediaItem.album ?? 'Unknown Album'),
                trailing: Text(_formatDuration(mediaItem.duration ?? Duration.zero)),
                onTap: () => controller.playArtist(index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNowPlaying(MediaItem mediaItem) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (mediaItem.artUri != null)
            Image.network(
              mediaItem.artUri.toString(), 
              width: 200, 
              height: 200,
              fit: BoxFit.cover,
            )
          else
            Icon(Icons.music_note, size: 200),
          SizedBox(height: 16),
          Text(
            mediaItem.title, 
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            mediaItem.artist ?? 'Unknown Artist',
            style: TextStyle(fontSize: 18),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            mediaItem.album ?? 'Unknown Album',
            style: TextStyle(fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.skip_previous, size: 40),
                onPressed: controller.skipToPrevious,
              ),
              Obx(() => IconButton(
                icon: Icon(
                  controller.isPlaying.value ? Icons.pause : Icons.play_arrow, 
                  size: 50
                ),
                onPressed: controller.playPause,
              )),
              IconButton(
                icon: Icon(Icons.skip_next, size: 40),
                onPressed: controller.skipToNext,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Obx(() => IconButton(
                icon: Icon(
                  controller.loopMode.value == LoopMode.one 
                    ? Icons.repeat_one 
                    : Icons.repeat,
                  color: controller.loopMode.value != LoopMode.off 
                    ? Colors.blue 
                    : Colors.grey,
                ),
                onPressed: controller.toggleRepeat,
              )),
              Obx(() => IconButton(
                icon: Icon(Icons.shuffle),
                color: controller.isShuffleEnabled.value 
                  ? Colors.blue 
                  : Colors.grey,
                onPressed: controller.toggleShuffle,
              )),
            ],
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

extension on LoopMode {
  LoopMode get next {
    switch (this) {
      case LoopMode.off:
        return LoopMode.one;
      case LoopMode.one:
        return LoopMode.all;
      case LoopMode.all:
        return LoopMode.off;
    }
  }
}

class FullScreenBuilder extends StatefulWidget {
  final Widget child;
  const FullScreenBuilder({super.key, required this.child});
 
  @override
  State<FullScreenBuilder> createState() =>
      _FullScreenBuilderState();
}
 
class _FullScreenBuilderState extends State<FullScreenBuilder> {
  final AudioPlayerController controller = Get.put(AudioPlayerController());
  @override
  void initState() {
    super.initState();
  }
 
  @override
  Widget build(BuildContext context) {
    return Material(
      child: Obx(()=>
        Stack(
          children: [
            widget.child,
            if(controller.currentMediaItem.value != null)
            Positioned.fill(
              child: DraggableMiniPlayer()
            ),
          ],
        ),
      ),
    );
  }
}



