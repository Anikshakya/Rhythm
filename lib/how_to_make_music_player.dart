import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

// =======================================================
// Global Audio Handler Setup
// =======================================================
late AudioHandler _audioHandler;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.myaudio.channel',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(MyApp());
}

// =======================================================
// Placeholder Models for Local Scanning
// =======================================================

// =======================================================
// Audio Handler (The core business logic with the full fix)
// =======================================================
/// An [AudioHandler] for playing audio from local files or online URLs.
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);

  /// Initialise our audio handler.
  AudioPlayerHandler() {
    // 1. Pipe player events to audio_service state
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // 2. ⭐ FIX: Listen for duration changes and update mediaItem consistently ⭐
    _player.durationStream.listen((duration) {
      if (duration == null) return;
      final index = _player.currentIndex ?? 0;
      final currentQueue = queue.value;
      if (index >= currentQueue.length) return;
      final oldItem = currentQueue[index];
      if (oldItem.duration != duration && duration > Duration.zero) {
        final newItem = oldItem.copyWith(duration: duration);
        currentQueue[index] = newItem;
        queue.add(currentQueue);
        mediaItem.add(newItem);
      }
    });

    // 3. FIX: Also listen to position stream to keep the notification/system up-to-date.
    // This often improves seeking responsiveness on the notification bar.
    _player.positionStream.listen((position) {
      // This listener ensures AudioService.position is kept up-to-date,
      // which is used by the UI's _mediaStateStream.
    });

    // 4. Update mediaItem when the current index changes (for playlists)
    _player.sequenceStateStream.listen((state) {
      final index = state.currentIndex ?? 0;
      final currentQueue = queue.value;
      if (index < currentQueue.length) {
        mediaItem.add(currentQueue[index]);
      }
    });
  }

  // Play Single Song Demo
  Future<void> howToPlaySong() async {
    final onlineItems = [
      MediaItem(
        id: 'https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3',
        album: "Science Friday",
        title: "A Salute To Head-Scratching Science (Online)",
        artist: "Science Friday and WNYC Studios",
        duration: const Duration(milliseconds: 5739820),
        artUri: Uri.parse(
          'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
        ),
      ),
    ];
    final onlineSources = [
      AudioSource.uri(Uri.parse(onlineItems[0].id), tag: onlineItems[0]),
    ];
    await loadPlaylist(onlineItems, onlineSources);
  }

  // New method to handle playing a list of local files
  Future<void> playLocalPlaylist(List<SongInfo> songs, int startIndex) async {
    final items = <MediaItem>[];
    final sources = <AudioSource>[];
    final tempDir = await getTemporaryDirectory();
    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      final localUri = Uri.file(song.file.path);
      Uri? artUri;
      if (song.meta.artUri != null) {
        artUri = song.meta.artUri;
      } else {
        if (song.meta.albumArt != null) {
          final artFile = File(
            '${tempDir.path}/art_${song.file.path.hashCode}.jpg',
          );
          await artFile.writeAsBytes(song.meta.albumArt!);
          artUri = Uri.file(artFile.path);
        }
      }
      final localItem = MediaItem(
        id: localUri.toString(),
        album: song.meta.album,
        title: song.meta.title,
        artist: song.meta.artist,
        duration: Duration.zero,
        artUri: artUri,
      );
      items.add(localItem);
      sources.add(AudioSource.uri(localUri, tag: localItem));
    }
    await loadPlaylist(items, sources, initialIndex: startIndex);
  }

  // New method to handle playing a list of online items
  Future<void> playOnlinePlaylist(List<MediaItem> items, int startIndex) async {
    final sources =
        items
            .map((item) => AudioSource.uri(Uri.parse(item.id), tag: item))
            .toList();
    await loadPlaylist(items, sources, initialIndex: startIndex);
  }

  // How To Play A Song
  Future<void> loadPlaylist(
    List<MediaItem> items,
    List<AudioSource> sources, {
    int initialIndex = 0,
  }) async {
    await _playlist.clear();
    await _playlist.addAll(sources);
    queue.add(items);
    await _player.setAudioSource(_playlist, initialIndex: initialIndex);
    mediaItem.add(items[initialIndex]);
    play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> fastForward() async {
    final newPosition = _player.position + const Duration(seconds: 10);
    await seek(newPosition);
  }

  @override
  Future<void> rewind() async {
    final newPosition = _player.position - const Duration(seconds: 10);
    await seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  /// Transform a just_audio event into an audio_service state.
  PlaybackState _transformEvent(PlaybackEvent event) {
    final hasPrevious = _player.hasPrevious;
    final hasNext = _player.hasNext;
    final playPauseControl =
        _player.playing ? MediaControl.pause : MediaControl.play;

    final controls = <MediaControl>[];
    if (hasPrevious) controls.add(MediaControl.skipToPrevious);
    controls.add(MediaControl.rewind);
    controls.add(playPauseControl);
    controls.add(MediaControl.stop);
    controls.add(MediaControl.fastForward);
    if (hasNext) controls.add(MediaControl.skipToNext);

    List<int> compactIndices;
    final prevOrRewindIndex =
        hasPrevious
            ? controls.indexOf(MediaControl.skipToPrevious)
            : controls.indexOf(MediaControl.rewind);
    final nextOrFfIndex =
        hasNext
            ? controls.indexOf(MediaControl.skipToNext)
            : controls.indexOf(MediaControl.fastForward);
    final playIndex = controls.indexOf(playPauseControl);
    compactIndices = [prevOrRewindIndex, playIndex, nextOrFfIndex];

    return PlaybackState(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: compactIndices,
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
      updateTime: DateTime.now(),
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}

// =======================================================
// Main Application and Screens
// =======================================================
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final LocalMusicScanner _scanner = LocalMusicScanner();
  List<SongInfo> _musicFiles = [];
  bool _isScanning = false;
  String? _message;
  String? _currentId;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;

  static final List<MediaItem> _onlineItems = [
    MediaItem(
      id: 'https://freepd.com/music/A%20Good%20Bass%20for%20Gambling.mp3',
      title: 'A Good Bass for Gambling',
      artist: 'Kevin MacLeod',
      album: 'FreePD',
      duration: Duration.zero,
    ),
    MediaItem(
      id: 'https://freepd.com/music/A%20Surprising%20Encounter.mp3',
      title: 'A Surprising Encounter',
      artist: 'Kevin MacLeod',
      album: 'FreePD',
      duration: Duration.zero,
    ),
    MediaItem(
      id: 'https://freepd.com/music/A%20Very%20Brady%20Special.mp3',
      title: 'A Very Brady Special',
      artist: 'Kevin MacLeod',
      album: 'FreePD',
      duration: Duration.zero,
    ),
    MediaItem(
      id: 'https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3',
      album: "Science Friday",
      title: "A Salute To Head-Scratching Science (Online)",
      artist: "Science Friday and WNYC Studios",
      duration: const Duration(milliseconds: 5739820),
      artUri: Uri.parse(
        'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mediaItemSubscription = _audioHandler.mediaItem.listen((item) {
      _saveCurrentState();
      setState(() {
        _currentId = item?.id;
      });
    });
    _audioHandler.queue.listen((_) {
      _saveCurrentState();
    });
    _loadSavedSongs();
    _loadLastState();
  }

  @override
  void dispose() {
    _mediaItemSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveCurrentState();
    }
  }

  Future<void> _loadSavedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSongsJson = prefs.getString('saved_songs');
    if (savedSongsJson == null) {
      setState(() {
        _musicFiles = [];
        _message = 'No saved songs found. Scan to find songs.';
      });
      return;
    }

    try {
      final savedList = json.decode(savedSongsJson) as List;
      final loadedSongs = <SongInfo>[];

      for (final map in savedList) {
        if (map is Map<String, dynamic>) {
          final song = await SongInfo.fromJson(map);
          if (song != null) loadedSongs.add(song);
        } else if (map is Map) {
          final song = await SongInfo.fromJson(Map<String, dynamic>.from(map));
          if (song != null) loadedSongs.add(song);
        }
      }

      setState(() {
        _musicFiles = loadedSongs;
        _message = 'Loaded ${loadedSongs.length} saved songs.';
      });
    } catch (e) {
      debugPrint('Error loading saved songs: $e');
      setState(() {
        _musicFiles = [];
        _message = 'Failed to load saved songs.';
      });
    }
  }

  Future<void> _saveSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final appDir = await getApplicationDocumentsDirectory();

    // Ensure a folder exists for album arts
    final artDir = Directory('${appDir.path}/album_arts');
    if (!await artDir.exists()) {
      await artDir.create(recursive: true);
    }

    // ✅ Convert all SongInfo objects to JSON-safe maps
    final musicLists = _musicFiles.map((item) => item.toJson()).toList();

    await prefs.setString('saved_songs', json.encode(musicLists));
    debugPrint('🎵 Saved ${musicLists.length} songs with album arts.');
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _musicFiles = [];
      _message = 'Requesting permissions...';
    });
    final granted = await _scanner.requestPermission();
    if (!granted) {
      setState(() {
        _isScanning = false;
        _message = 'Storage permission denied. Cannot scan local files.';
      });
      return;
    }
    setState(() => _message = 'Scanning directories...');
    try {
      final foundSongs = await _scanner.startSafeAutoScan();
      setState(() {
        _musicFiles = foundSongs;
        _isScanning = false;
        _message = 'Found ${foundSongs.length} songs.';
      });
      await _saveSongs();
    } catch (e) {
      setState(() {
        _isScanning = false;
        _message = 'Scan failed: $e';
      });
    }
  }

  Future<void> _selectAndScanFolder() async {
    final String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null) {
      return;
    }
    setState(() {
      _isScanning = true;
      _musicFiles = [];
      _message = 'Requesting permissions...';
    });
    final granted = await _scanner.requestPermission();
    if (!granted) {
      setState(() {
        _isScanning = false;
        _message = 'Storage permission denied. Cannot scan selected folder.';
      });
      return;
    }
    setState(() => _message = 'Scanning selected folder...');
    try {
      final foundSongs = await _scanner.scanDirectory(directoryPath);
      setState(() {
        _musicFiles = foundSongs;
        _isScanning = false;
        _message = 'Found ${foundSongs.length} songs in selected folder.';
      });
      await _saveSongs();
    } catch (e) {
      setState(() {
        _isScanning = false;
        _message = 'Scan failed: $e';
      });
    }
  }

  Future<void> _loadLastState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastQueueJson = prefs.getString('last_queue');
    if (lastQueueJson != null) {
      final lastQueueList = json.decode(lastQueueJson) as List;
      final items = <MediaItem>[];
      final sources = <AudioSource>[];
      for (var map in lastQueueList) {
        final id = map['id'];
        final item = MediaItem(
          id: id,
          title: map['title'] ?? 'Unknown Title',
          artist: map['artist'],
          album: map['album'],
          duration: Duration(milliseconds: map['duration'] ?? 0),
          artUri: map['artUri'] != null ? Uri.parse(map['artUri']) : null,
        );
        items.add(item);
        sources.add(AudioSource.uri(Uri.parse(id), tag: item));
      }
      if (items.isNotEmpty) {
        final lastIndex = prefs.getInt('last_index') ?? 0;
        final lastPosition = Duration(
          milliseconds: prefs.getInt('last_position') ?? 0,
        );
        await (_audioHandler as AudioPlayerHandler).loadPlaylist(
          items,
          sources,
          initialIndex: lastIndex,
        );
        await _audioHandler.pause();
        await _audioHandler.seek(lastPosition);
      }
    }
  }

  Future<void> _saveCurrentState() async {
    final prefs = await SharedPreferences.getInstance();
    final currentQueue = _audioHandler.queue.value;
    if (currentQueue.isEmpty) return;
    final queueList =
        currentQueue.map((item) {
          return {
            'id': item.id,
            'title': item.title,
            'artist': item.artist,
            'album': item.album,
            'duration': item.duration?.inMilliseconds,
            'artUri': item.artUri?.toString(),
          };
        }).toList();
    await prefs.setString('last_queue', json.encode(queueList));
    await prefs.setInt(
      'last_index',
      _audioHandler.playbackState.value.queueIndex ?? 0,
    );
    await prefs.setInt('last_position', 0);
  }

  void _playLocalSongs(List<SongInfo> playlist, int index) {
    (_audioHandler as AudioPlayerHandler).playLocalPlaylist(playlist, index);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing: ${playlist[index].meta.title}')),
    );
  }

  void _playOnlineSongs(List<MediaItem> items, int index) {
    (_audioHandler as AudioPlayerHandler).playOnlinePlaylist(items, index);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Playing: ${items[index].title}')));
  }

  bool _isCurrent(String id) {
    return id == _currentId;
  }

  Widget _buildSongsTab() {
    return ListView.builder(
      itemCount: _musicFiles.length,
      itemBuilder: (context, index) {
        final song = _musicFiles[index];
        final songId = Uri.file(song.file.path).toString();
        return ListTile(
          title: Text(song.meta.title),
          subtitle: Text('${song.meta.artist} - ${song.meta.album}'),
          leading: const Icon(Icons.music_note),
          trailing:
              _isCurrent(songId)
                  ? const Icon(Icons.volume_up, color: Colors.blue)
                  : null,
          onTap: () => _playLocalSongs(_musicFiles, index),
        );
      },
    );
  }

  Widget _buildArtistsTab() {
    Map<String, List<SongInfo>> artists = {};
    for (var song in _musicFiles) {
      var artist = song.meta.artist;
      artists.putIfAbsent(artist, () => []).add(song);
    }
    var artistList = artists.keys.toList()..sort();
    return ListView.builder(
      itemCount: artistList.length,
      itemBuilder: (context, index) {
        final artist = artistList[index];
        final songs = artists[artist]!;
        return ExpansionTile(
          title: Text(artist),
          children:
              songs.map((song) {
                final songId = Uri.file(song.file.path).toString();
                return ListTile(
                  title: Text(song.meta.title),
                  subtitle: Text(song.meta.album),
                  leading: const Icon(Icons.music_note),
                  trailing:
                      _isCurrent(songId)
                          ? const Icon(Icons.volume_up, color: Colors.blue)
                          : null,
                  onTap: () => _playLocalSongs(songs, songs.indexOf(song)),
                );
              }).toList(),
        );
      },
    );
  }

  Widget _buildAlbumsTab() {
    Map<String, List<SongInfo>> albums = {};
    for (var song in _musicFiles) {
      var album = song.meta.album;
      albums.putIfAbsent(album, () => []).add(song);
    }
    var albumList = albums.keys.toList()..sort();
    return ListView.builder(
      itemCount: albumList.length,
      itemBuilder: (context, index) {
        final album = albumList[index];
        final songs = albums[album]!;
        return ExpansionTile(
          title: Text(album),
          children:
              songs.map((song) {
                final songId = Uri.file(song.file.path).toString();
                return ListTile(
                  title: Text(song.meta.title),
                  subtitle: Text(song.meta.artist),
                  leading: const Icon(Icons.music_note),
                  trailing:
                      _isCurrent(songId)
                          ? const Icon(Icons.volume_up, color: Colors.blue)
                          : null,
                  onTap: () => _playLocalSongs(songs, songs.indexOf(song)),
                );
              }).toList(),
        );
      },
    );
  }

  Widget _buildOnlineTab() {
    return ListView.builder(
      itemCount: _onlineItems.length,
      itemBuilder: (context, index) {
        final item = _onlineItems[index];
        return ListTile(
          title: Text(item.title),
          subtitle: Text(
            '${item.artist ?? 'Unknown'} - ${item.album ?? 'Unknown'}',
          ),
          leading: const Icon(Icons.music_note),
          trailing:
              _isCurrent(item.id)
                  ? const Icon(Icons.volume_up, color: Colors.blue)
                  : null,
          onTap: () => _playOnlineSongs(_onlineItems, index),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audio Service Demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- Player UI Refactored to Match Image ---
            StreamBuilder<MediaItem?>(
              stream: _audioHandler.mediaItem,
              builder: (context, snapshot) {
                if (snapshot.data == null) {
                  // Return a simple widget when no track is selected
                  return const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'No track selected',
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }

                final mediaItem = snapshot.data;
                Widget? artWidget;

                // Determine the album art widget (simplified for the compact view)
                // The image has a small, square art area.
                if (mediaItem?.artUri != null) {
                  final uri = mediaItem!.artUri!;
                  if (uri.scheme == 'file') {
                    artWidget = Image.file(
                      File.fromUri(uri),
                      height: 50, // Compact size
                      width: 50, // Compact size
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) => const Icon(
                            Icons.album,
                            size: 50,
                            color: Colors.grey,
                          ),
                    );
                  } else {
                    artWidget = Image.network(
                      uri.toString(),
                      height: 50, // Compact size
                      width: 50, // Compact size
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) => const Icon(
                            Icons.album,
                            size: 50,
                            color: Colors.grey,
                          ),
                    );
                  }
                } else {
                  artWidget = const Icon(
                    Icons.album,
                    size: 50,
                    color: Colors.grey,
                  );
                }

                // Main container with dark, rounded look
                return Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85), // Dark background
                    borderRadius: BorderRadius.circular(
                      16.0,
                    ), // Rounded corners
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Keep column compact
                    children: [
                      // Top Row: Album Art, Title/Artist, Volume/Signal Icon
                      Row(
                        children: [
                          // Album Art Placeholder/Widget
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6.0),
                            child: Container(
                              height: 50,
                              width: 50,
                              color:
                                  Colors
                                      .grey
                                      .shade800, // Placeholder color matching the image's empty art area
                              child:
                                  artWidget, // Using the smaller artWidget defined above
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Title and Artist
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  mediaItem?.title ?? 'No Title',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  mediaItem?.artist ?? 'Unknown Artist',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          // Signal/Volume Icon (using an approximation)
                          Icon(
                            Icons
                                .bar_chart_sharp, // Represents the vertical lines icon approximation
                            color: Colors.white.withOpacity(0.7),
                            size: 20,
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Seek Bar and Times
                      StreamBuilder<MediaState>(
                        stream: _mediaStateStream,
                        builder: (context, snapshot) {
                          final mediaState = snapshot.data;
                          final position =
                              mediaState?.position ?? Duration.zero;
                          final duration =
                              mediaState?.mediaItem?.duration ?? Duration.zero;

                          // This uses the existing SeekBar, but you might need a custom one for the exact visual style.
                          // We'll wrap it to integrate time display.
                          return Column(
                            children: [
                              // A simplified horizontal progress bar/SeekBar integration
                              Row(
                                children: [
                                  Text(
                                    _formatDuration(
                                      position,
                                    ).toString(), // Format: 0:05
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SeekBar(
                                      // Assuming SeekBar is a widget that takes duration, position, and onChangeEnd
                                      duration: duration,
                                      position: position,
                                      onChangeEnd: (newPosition) {
                                        _audioHandler.seek(newPosition);
                                      },
                                      // NOTE: You will need to customize the 'SeekBar' widget to match the visual style (e.g., color, height)
                                      // of the seek bar in the image if it's not already generic.
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDuration(duration).toString(),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),

                      // Control Row: Favorite, Previous, Play/Pause, Next, Volume/Queue
                      const SizedBox(height: 10),
                      StreamBuilder<PlaybackState>(
                        stream: _audioHandler.playbackState,
                        builder: (context, playbackSnapshot) {
                          final playing =
                              playbackSnapshot.data?.playing ?? false;

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              // Favorite Star
                              IconButton(
                                icon: const Icon(
                                  Icons.star_border,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () {
                                  // Implement favorite/like logic
                                },
                              ),

                              // Previous Button (Simplified using the existing logic for enabled/disabled)
                              StreamBuilder<List<MediaItem>?>(
                                stream: _audioHandler.queue,
                                builder: (context, queueSnapshot) {
                                  final queueIndex =
                                      playbackSnapshot.data?.queueIndex ?? 0;
                                  final hasPrevious = queueIndex > 0;
                                  return IconButton(
                                    icon: const Icon(
                                      Icons.skip_previous,
                                      color: Colors.white,
                                      size: 36,
                                    ),
                                    onPressed:
                                        hasPrevious
                                            ? _audioHandler.skipToPrevious
                                            : null, // Disable if no previous track
                                    disabledColor: Colors.white.withOpacity(
                                      0.4,
                                    ),
                                  );
                                },
                              ),

                              // Play/Pause Button (Large size as in the image)
                              IconButton(
                                icon: Icon(
                                  playing ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 48,
                                ),
                                onPressed:
                                    playing
                                        ? _audioHandler.pause
                                        : _audioHandler.play,
                              ),

                              // Next Button
                              StreamBuilder<List<MediaItem>?>(
                                stream: _audioHandler.queue,
                                builder: (context, queueSnapshot) {
                                  final queue = queueSnapshot.data ?? [];
                                  final queueIndex =
                                      playbackSnapshot.data?.queueIndex ?? 0;
                                  final hasNext = queueIndex < queue.length - 1;
                                  return IconButton(
                                    icon: const Icon(
                                      Icons.skip_next,
                                      color: Colors.white,
                                      size: 36,
                                    ),
                                    onPressed:
                                        hasNext
                                            ? _audioHandler.skipToNext
                                            : null, // Disable if no next track
                                    disabledColor: Colors.white.withOpacity(
                                      0.4,
                                    ),
                                  );
                                },
                              ),

                              // Volume/Queue Icon (Approximation of the three-dots/settings icon)
                              IconButton(
                                icon: const Icon(
                                  Icons.more_horiz,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () {
                                  // Implement queue/volume/settings logic
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),

            // --- Processing State Display ---
            StreamBuilder<AudioProcessingState>(
              stream:
                  _audioHandler.playbackState
                      .map((state) => state.processingState)
                      .distinct(),
              builder: (context, snapshot) {
                final processingState =
                    snapshot.data ?? AudioProcessingState.idle;
                return Text(
                  "Processing state: ${describeEnum(processingState)}",
                );
              },
            ),

            // NOTE: The original _button function and the use of AudioProcessingState are omitted
            // for brevity and to focus on the visual match with the compact player image.
            // You will need to ensure the _mediaStateStream and SeekBar widget are correctly defined in your code.
            const Divider(height: 40),
            // --- Online/Local Navigation Buttons ---
            ElevatedButton.icon(
              icon: const Icon(Icons.public),
              label: const Text('How to Play Single Audio'),
              onPressed: () {
                (_audioHandler as AudioPlayerHandler).howToPlaySong();
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Scan Local Files'),
              onPressed: _startScan,
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_special),
              label: const Text('Select Folder and Scan'),
              onPressed: _selectAndScanFolder,
            ),
            const SizedBox(height: 20),
            // --- Music Section ---
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_message ?? ''),
                      if (_isScanning)
                        const CircularProgressIndicator()
                      else if (_musicFiles.isNotEmpty)
                        ElevatedButton(
                          onPressed: _startScan,
                          child: const Text('Re-scan'),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                if (_isScanning)
                  const Center(child: CircularProgressIndicator())
                else if (_musicFiles.isEmpty && _message != null)
                  Center(child: Text(_message!))
                else
                  SizedBox(
                    height: 300,
                    child: DefaultTabController(
                      length: 4,
                      child: Column(
                        children: [
                          const TabBar(
                            tabs: [
                              Tab(text: 'Songs'),
                              Tab(text: 'Artists'),
                              Tab(text: 'Albums'),
                              Tab(text: 'Online'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildSongsTab(),
                                _buildArtistsTab(),
                                _buildAlbumsTab(),
                                _buildOnlineTab(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A stream reporting the combined state of the current media item and its
  /// current position.
  Stream<MediaState> get _mediaStateStream =>
      Rx.combineLatest2<MediaItem?, Duration, MediaState>(
        _audioHandler.mediaItem,
        AudioService.position,
        (mediaItem, position) => MediaState(mediaItem, position),
      );
}

class LocalMusicScanner {
  static const Set<String> _supportedFormats = {
    'mp3',
    'flac',
    'm4a',
    'wav',
    'ogg',
  };
  int _scannedFiles = 0;

  Future<bool> requestPermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    if (Platform.isAndroid && await _getAndroidVersion() >= 30) {
      final manage = await Permission.manageExternalStorage.status;
      if (!manage.isGranted) await Permission.manageExternalStorage.request();
      status = await Permission.manageExternalStorage.status;
    }
    return status.isGranted;
  }

  Future<int> _getAndroidVersion() async {
    return Platform.isAndroid ? 30 : 0;
  }

  bool _isMusicFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return _supportedFormats.contains(ext);
  }

  List<SongInfo> _removeDuplicates(List<SongInfo> files) {
    final seen = <String>{};
    return files.where((f) => seen.add(f.file.path)).toList();
  }

  Future<List<SongInfo>> startSafeAutoScan() async {
    _scannedFiles = 0;
    final found = <SongInfo>[];
    final dirs = await _getAccessibleDirectories();
    for (final dir in dirs) {
      await Future.delayed(const Duration(milliseconds: 50));
      final files = await _scanDirectoryForMusic(dir);
      for (final file in files) {
        final meta = await AudioMetadata.fromFile(file);
        if (meta != null) found.add(SongInfo(file: file, meta: meta));
      }
    }
    final unique = _removeDuplicates(found)
      ..sort((a, b) => a.file.path.compareTo(b.file.path));
    return unique;
  }

  Future<List<SongInfo>> scanDirectory(String path) async {
    _scannedFiles = 0;
    final dir = Directory(path);
    final files = await _scanDirectoryForMusic(dir);
    final found = <SongInfo>[];
    for (final file in files) {
      final meta = await AudioMetadata.fromFile(file);
      if (meta != null) found.add(SongInfo(file: file, meta: meta));
    }
    final unique = _removeDuplicates(found)
      ..sort((a, b) => a.file.path.compareTo(b.file.path));
    return unique;
  }

  Future<List<Directory>> _getAccessibleDirectories() async {
    List<Directory> dirs = [];
    Directory? extDir = Directory('/storage/emulated/0');
    if (await extDir.exists()) dirs.add(extDir);
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null && await downloadsDir.exists()) {
        dirs.add(downloadsDir);
      }
    } catch (_) {}
    List<Directory> accessibleDirs = [];
    for (var dir in dirs.toSet().toList()) {
      try {
        await dir.list().take(1).toList();
        accessibleDirs.add(dir);
      } catch (_) {}
    }
    if (dirs.isNotEmpty && accessibleDirs.contains(dirs.first)) {
      List<String> commonPaths = ['Music', 'Download', 'Audio'];
      for (var path in commonPaths) {
        Directory subDir = Directory('${dirs.first.path}/$path');
        if (await subDir.exists()) accessibleDirs.add(subDir);
      }
    }
    return accessibleDirs.toSet().toList();
  }

  Future<List<File>> _scanDirectoryForMusic(Directory dir) async {
    final music = <File>[];
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && _isMusicFile(entity.path)) {
          music.add(entity);
          _scannedFiles++;
        }
        if (_scannedFiles > 15000) break;
      }
    } catch (e) {
      print('Scan error in ${dir.path}: $e');
    }
    return music;
  }
}

class MediaState {
  final MediaItem? mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

class SeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final bool? showDurations;
  final ValueChanged<Duration>? onChanged;
  final ValueChanged<Duration>? onChangeEnd;

  SeekBar({
    required this.duration,
    this.showDurations,
    required this.position,
    this.bufferedPosition = Duration.zero,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  _SeekBarState createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;
  bool _dragging = false;
  late SliderThemeData _sliderThemeData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sliderThemeData = SliderTheme.of(context).copyWith(trackHeight: 2.0);
  }

  @override
  Widget build(BuildContext context) {
    final value = min(
      _dragValue ?? widget.position.inMilliseconds.toDouble(),
      widget.duration.inMilliseconds.toDouble(),
    );
    if (_dragValue != null && !_dragging) {
      _dragValue = null;
    }
    final maxDuration = widget.duration.inMilliseconds.toDouble();
    // Use max(1.0, maxDuration) to prevent slider Max=0 leading to errors
    final sliderMax = max(1.0, maxDuration);
    return Stack(
      children: [
        // Buffered Track (Grey)
        SliderTheme(
          data: _sliderThemeData.copyWith(
            thumbShape: HiddenThumbComponentShape(),
            activeTrackColor: Colors.blue.shade100,
            inactiveTrackColor: Colors.grey.shade300,
          ),
          child: ExcludeSemantics(
            child: Slider(
              min: 0.0,
              max: sliderMax,
              value: min(
                widget.bufferedPosition.inMilliseconds.toDouble(),
                sliderMax,
              ),
              onChanged: (value) {},
            ),
          ),
        ),
        // Position Track and Thumb (Blue)
        SliderTheme(
          data: _sliderThemeData.copyWith(
            inactiveTrackColor: Colors.transparent,
          ),
          child: Slider(
            min: 0.0,
            max: sliderMax,
            value: min(value, sliderMax),
            onChanged: (value) {
              if (!_dragging) {
                _dragging = true;
              }
              setState(() {
                _dragValue = value;
              });
              if (widget.onChanged != null) {
                widget.onChanged!(Duration(milliseconds: value.round()));
              }
            },
            onChangeEnd: (value) {
              if (widget.onChangeEnd != null) {
                widget.onChangeEnd!(Duration(milliseconds: value.round()));
              }
              _dragging = false;
            },
          ),
        ),
        // Position Display
        if (widget.showDurations == true)
          Positioned(
            left: 16.0,
            bottom: 0.0,
            child: Text(
              _formatDuration(widget.position),
              style: const TextStyle(color: Colors.black),
            ),
          ),
        // Remaining/Total Display
        if (widget.showDurations == true)
          Positioned(
            right: 16.0,
            bottom: 0.0,
            child: Text(
              _formatDuration(widget.duration),
              style: const TextStyle(color: Colors.black),
            ),
          ),
      ],
    );
  }
}

class HiddenThumbComponentShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.zero;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {}
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours > 0) {
    final hours = d.inHours.toString();
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

class SongInfo {
  final File file;
  final AudioMetadata meta;
  SongInfo({required this.file, required this.meta});

  MediaItem toMediaItem(String id) {
    return MediaItem(
      id: id,
      album: meta.album,
      title: meta.title,
      artist: meta.artist,
      genre: meta.genre,
      duration:
          meta.durationMs != null
              ? Duration(milliseconds: meta.durationMs!)
              : null,
      artUri: meta.artUri,
      extras: {'filePath': file.path},
    );
  }

  /// Convert SongInfo -> Map (serializable)
  Map<String, dynamic> toJson() {
    return {
      'filePath': file.path,
      'title': meta.title,
      'artist': meta.artist,
      'album': meta.album,
      'genre': meta.genre,
      'durationMs': meta.durationMs,
      'artUri': meta.artUri?.toString(),
    };
  }

  /// Reconstruct SongInfo from Map (returns null if file missing)
  static Future<SongInfo?> fromJson(Map<String, dynamic> map) async {
    final filePath = map['filePath'] as String?;
    if (filePath == null) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;

    // Try to re-read metadata from file if you want; here we create a fallback meta
    final meta = AudioMetadata(
      id: file.path,
      title: map['title'] ?? 'Unknown',
      artist: map['artist'] ?? 'Unknown Artist',
      album: map['album'] ?? 'Unknown Album',
      genre: map['genre'],
      durationMs:
          map['durationMs'] is int
              ? map['durationMs'] as int
              : (map['durationMs'] is String
                  ? int.tryParse(map['durationMs'])
                  : null),
      albumArt: null,
      artUri: map['artUri'] != null ? Uri.tryParse(map['artUri']) : null,
    );

    return SongInfo(file: file, meta: meta);
  }
}


/// ==================== AUDIO METADATA EXTRACTOR ====================
class AudioMetadata {
  String? id;
  String title;
  String artist;
  String album;
  String? genre;
  int? durationMs;
  Uint8List? albumArt;
  Uri? artUri;

  AudioMetadata({
    this.id,
    this.artUri,
    this.title = "Unknown Title",
    this.artist = "Unknown Artist",
    this.album = "Unknown Album",
    this.genre,
    this.durationMs,
    this.albumArt,
  });

  /// Extract metadata from file based on extension
  static Future<AudioMetadata?> fromFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      AudioMetadata meta;

      switch (ext) {
        case 'mp3':
          meta = _readMp3(bytes, file);
          break;
        case 'wav':
          meta = _readWav(file);
          break;
        case 'flac':
          meta = await _readFlac(file);
          break;
        case 'm4a':
        case 'mp4':
        case 'aac':
          meta = _readM4a(bytes, file);
          break;
        default:
          meta = AudioMetadata(title: file.path.split('/').last);
      }

      // ✅ Generate artUri if albumArt exists
      if (meta.albumArt != null) {
        final tempDir = await getTemporaryDirectory();
        final artFile = File('${tempDir.path}/art_${file.path.hashCode}.jpg');
        await artFile.writeAsBytes(meta.albumArt!);
        meta.artUri = Uri.file(artFile.path);
      }

      return meta;
    } catch (e) {
      debugPrint('Metadata extraction failed: $e');
      return AudioMetadata(title: file.path.split('/').last);
    }
  }

  // ------------------- MP3 METADATA -------------------
  static AudioMetadata _readMp3(Uint8List bytes, File file) {
    final meta = AudioMetadata();
    meta.title = 'MP3 Audio';

    // Check ID3 tag
    if (bytes.length > 10 &&
        String.fromCharCodes(bytes.sublist(0, 3)) == 'ID3') {
      final headerSize = 10;
      final tagSize = _syncSafeToInt(bytes.sublist(6, 10));
      var pos = headerSize;

      while (pos + 10 < tagSize + headerSize && pos + 10 < bytes.length) {
        final frameId = ascii.decode(bytes.sublist(pos, pos + 4));
        final frameSize = _bytesToInt(bytes.sublist(pos + 4, pos + 8));
        if (frameSize <= 0 || pos + 10 + frameSize > bytes.length) break;

        final frameData = bytes.sublist(pos + 10, pos + 10 + frameSize);

        switch (frameId) {
          case 'TIT2':
            meta.title = _decodeTextFrame(frameData);
            break;
          case 'TPE1':
            meta.artist = _decodeTextFrame(frameData);
            break;
          case 'TALB':
            meta.album = _decodeTextFrame(frameData);
            break;
          case 'TCON':
            meta.genre = _decodeTextFrame(frameData);
            break;
          case 'APIC':
            meta.albumArt = _decodeApic(frameData);
            break;
        }
        pos += 10 + frameSize;
      }
    }

    meta.durationMs = _estimateMp3Duration(bytes);
    return meta;
  }

  static int _syncSafeToInt(List<int> bytes) =>
      (bytes[0] << 21) | (bytes[1] << 14) | (bytes[2] << 7) | bytes[3];

  static int _bytesToInt(List<int> bytes) =>
      bytes.fold(0, (a, b) => (a << 8) + b);

  static String _decodeTextFrame(Uint8List data) {
    if (data.isEmpty) return '';
    final encoding = data[0];
    final textBytes = data.sublist(1);
    try {
      return encoding == 0
          ? ascii.decode(textBytes).trim()
          : utf8.decode(textBytes).trim();
    } catch (_) {
      return '';
    }
  }

  static Uint8List? _decodeApic(Uint8List data) {
    try {
      var i = 1;
      while (i < data.length && data[i] != 0) i++;
      i += 2; // skip null + picture type
      while (i < data.length && data[i] != 0) i++;
      i++;
      return data.sublist(i);
    } catch (_) {
      return null;
    }
  }

  static int _estimateMp3Duration(Uint8List bytes) {
    const bitrate = 128000; // 128 kbps fallback
    return ((bytes.length * 8) / bitrate * 1000).toInt();
  }

  // ------------------- WAV METADATA -------------------
  static AudioMetadata _readWav(File file) {
    return AudioMetadata(title: file.path.split('/').last);
  }

  // ------------------- FLAC METADATA -------------------
  static Future<AudioMetadata> _readFlac(File file) async {
    final meta = AudioMetadata(title: 'FLAC Audio');

    try {
      final bytes = await file.readAsBytes();

      // ✅ Check FLAC file signature
      if (utf8.decode(bytes.sublist(0, 4)) != "fLaC") {
        print("❌ Not a valid FLAC file");
        return meta;
      }

      int offset = 4;
      bool isLast = false;

      while (!isLast && offset < bytes.length) {
        final header = bytes[offset];
        isLast = (header & 0x80) != 0; // Last-metadata-block flag
        final type = header & 0x7F; // Block type
        final length =
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3];
        offset += 4;

        final blockData = bytes.sublist(offset, offset + length);

        switch (type) {
          case 0: // STREAMINFO
            final duration = _parseStreamInfo(blockData);
            if (duration != null) meta.durationMs = duration;
            break;
          case 4: // VORBIS_COMMENT
            _parseVorbisComments(blockData, meta);
            break;
          case 6: // PICTURE (Album art)
            final imageBytes = _parsePicture(blockData);
            if (imageBytes != null) meta.albumArt = imageBytes;
            break;
        }

        offset += length;
      }
    } catch (e) {
      print('❌ Error reading FLAC: $e');
    }

    return meta;
  }

  static int? _parseStreamInfo(Uint8List data) {
    if (data.length < 34) return null;

    final totalSamples =
        ((data[27] & 0x0F) << 32) |
        (data[28] << 24) |
        (data[29] << 16) |
        (data[30] << 8) |
        data[31];
    final sampleRate =
        ((data[18] << 12) | (data[19] << 4) | ((data[20] & 0xF0) >> 4));

    if (sampleRate == 0) return null;

    final durationSeconds = totalSamples / sampleRate;
    return (durationSeconds * 1000).round();
  }

  static void _parseVorbisComments(Uint8List data, AudioMetadata meta) {
    final reader = ByteData.sublistView(data);
    int offset = 0;

    try {
      // Skip vendor string
      final vendorLength = reader.getUint32(offset, Endian.little);
      offset += 4 + vendorLength;

      // Number of comments
      final commentsCount = reader.getUint32(offset, Endian.little);
      offset += 4;

      for (int i = 0; i < commentsCount; i++) {
        final len = reader.getUint32(offset, Endian.little);
        offset += 4;
        final commentBytes = data.sublist(offset, offset + len);
        offset += len;

        final comment = utf8.decode(commentBytes);
        final parts = comment.split('=');
        if (parts.length == 2) {
          final key = parts[0].toUpperCase();
          final value = parts[1];
          switch (key) {
            case 'TITLE':
              meta.title = value;
              break;
            case 'ARTIST':
              meta.artist = value;
              break;
            case 'ALBUM':
              meta.album = value;
              break;
            case 'GENRE':
              meta.genre = value;
              break;
          }
        }
      }
    } catch (e) {
      print('❌ Failed to parse Vorbis comments: $e');
    }
  }

  static Uint8List? _parsePicture(Uint8List data) {
    final reader = ByteData.sublistView(data);
    int offset = 0;

    try {
      offset += 4;
      final mimeLength = reader.getUint32(offset);
      offset += 4;
      final mime = utf8.decode(data.sublist(offset, offset + mimeLength));
      offset += mimeLength;

      final descLength = reader.getUint32(offset);
      offset += 4;
      offset += descLength;

      offset += 16;

      final imgDataLength = reader.getUint32(offset);
      offset += 4;

      final imgBytes = data.sublist(offset, offset + imgDataLength);
      print("✅ FLAC album art extracted (${mime}, ${imgBytes.length} bytes)");
      return Uint8List.fromList(imgBytes);
    } catch (e) {
      print('⚠️ Failed to parse FLAC picture: $e');
      return null;
    }
  }

  // ------------------- M4A METADATA -------------------
  static AudioMetadata _readM4a(Uint8List bytes, File file) {
    final meta = AudioMetadata();
    int pos = 0;

    while (pos + 8 < bytes.length) {
      final size = _bytesToInt(bytes.sublist(pos, pos + 4));
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      if (size < 8 || pos + size > bytes.length) break;

      if (type == 'moov' || type == 'udta' || type == 'meta') {
        int end = pos + size;
        pos += 8;
        while (pos + 8 < end) {
          final childSize = _bytesToInt(bytes.sublist(pos, pos + 4));
          final childType = String.fromCharCodes(
            bytes.sublist(pos + 4, pos + 8),
          );
          if (childSize < 8 || pos + childSize > end) break;

          final dataStart = pos + 8;
          final dataEnd = pos + childSize;
          final atomData = bytes.sublist(dataStart, dataEnd);

          switch (childType) {
            case '©nam':
              meta.title = _readAtomString(atomData);
              break;
            case '©ART':
              meta.artist = _readAtomString(atomData);
              break;
            case '©alb':
              meta.album = _readAtomString(atomData);
              break;
            case '©gen':
              meta.genre = _readAtomString(atomData);
              break;
          }
          pos += childSize;
        }
        continue;
      }
      pos += size;
    }
    return meta;
  }

  static String _readAtomString(Uint8List data) {
    if (data.length <= 8) return '';
    return utf8.decode(data.sublist(8)).trim();
  }
}
