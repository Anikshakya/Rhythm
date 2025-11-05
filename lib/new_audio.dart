import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rhythm/audio_meta_data/audio_meta_data.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
class SongInfo {
  final File file;
  final AudioMetadata meta;
  SongInfo({required this.file, required this.meta});
}

// =======================================================
// Audio Handler (The core business logic with the full fix)
// =======================================================
/// An [AudioHandler] for playing audio from local files or online URLs.
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);

  // Default Online Media Item
  static final _onlineItem = MediaItem(
    id: 'https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3',
    album: "Science Friday",
    title: "A Salute To Head-Scratching Science (Online)",
    artist: "Science Friday and WNYC Studios",
    duration: const Duration(milliseconds: 5739820),
    artUri: Uri.parse(
      'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
    ),
  );

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

    // Load the default online track initially
    playOnlineDefault();
  }

  // Expose a method to switch to the default online stream
  Future<void> playOnlineDefault() async {
    final onlineItems = [_onlineItem];
    final onlineSources = [
      AudioSource.uri(Uri.parse(_onlineItem.id), tag: _onlineItem),
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
      if (song.meta.albumArt != null) {
        final artFile = File(
          '${tempDir.path}/art_${song.file.path.hashCode}.jpg',
        );
        await artFile.writeAsBytes(song.meta.albumArt!);
        artUri = Uri.file(artFile.path);
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

  // General method to load a playlist
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

class _MainScreenState extends State<MainScreen> {
  final LocalMusicScanner _scanner = LocalMusicScanner();
  List<SongInfo> _musicFiles = [];
  bool _isScanning = false;
  String? _message;
  String? _currentId;
  StreamSubscription<MediaItem?>? mediaItemSubscription;

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
    AudioPlayerHandler._onlineItem,
  ];

  @override
  void initState() {
    super.initState();
    mediaItemSubscription = _audioHandler.mediaItem.listen((item) {
      setState(() {
        _currentId = item?.id;
      });
    });
    _loadSavedSongs();
  }

  Future<void> _loadSavedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSongsJson = prefs.getString('saved_songs');
    if (savedSongsJson != null) {
      final List<dynamic> savedSongsList = json.decode(savedSongsJson);
      final loadedSongs = <SongInfo>[];
      for (var songMap in savedSongsList) {
        final path = songMap['path'];
        final file = File(path);
        if (await file.exists()) {
          final meta = AudioMetadata(
            title: songMap['title'],
            artist: songMap['artist'],
            album: songMap['album'],
            // albumArt: songMap['albumArt'],
          );
          loadedSongs.add(SongInfo(file: file, meta: meta));
        }
      }
      if (loadedSongs.isNotEmpty) {
        setState(() {
          _musicFiles = loadedSongs;
          _message = 'Loaded ${loadedSongs.length} saved songs.';
        });
        return;
      }
    }
    // If no saved songs or failed to load, set empty
    setState(() {
      _musicFiles = [];
      _message = 'No saved songs found. Scan to find songs.';
    });
  }

  Future<void> _saveSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final songsList =
        _musicFiles.map((song) {
          return {
            'path': song.file.path,
            'title': song.meta.title,
            'artist': song.meta.artist,
            'album': song.meta.album,
            // 'albumArt': song.meta.albumArt,
          };
        }).toList();
    await prefs.setString('saved_songs', json.encode(songsList));
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
            // --- Current Media Item Display ---
            StreamBuilder<MediaItem?>(
              stream: _audioHandler.mediaItem,
              builder: (context, snapshot) {
                final mediaItem = snapshot.data;
                Widget? artWidget;
                if (mediaItem?.artUri != null) {
                  final uri = mediaItem!.artUri!;
                  if (uri.scheme == 'file') {
                    artWidget = Image.file(
                      File.fromUri(uri),
                      height: 200,
                      width: 200,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) =>
                              const Icon(Icons.album, size: 200),
                    );
                  } else {
                    artWidget = Image.network(
                      uri.toString(),
                      height: 200,
                      width: 200,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) =>
                              const Icon(Icons.album, size: 200),
                    );
                  }
                } else {
                  artWidget = const Icon(Icons.album, size: 200);
                }
                return Column(
                  children: [
                    artWidget,
                    const SizedBox(height: 10),
                    Text(
                      'Now Playing:',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      mediaItem?.title ?? 'No track loaded',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(mediaItem?.artist ?? ''),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            // --- Control Buttons ---
            StreamBuilder<List<MediaItem>?>(
              stream: _audioHandler.queue,
              builder: (context, queueSnapshot) {
                final queue = queueSnapshot.data ?? [];
                return StreamBuilder<PlaybackState>(
                  stream: _audioHandler.playbackState,
                  builder: (context, playbackSnapshot) {
                    final playing = playbackSnapshot.data?.playing ?? false;
                    final queueIndex = playbackSnapshot.data?.queueIndex ?? 0;
                    final hasPrevious = queueIndex > 0;
                    final hasNext = queueIndex < queue.length - 1;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _button(
                          Icons.skip_previous,
                          hasPrevious ? _audioHandler.skipToPrevious : null,
                        ),
                        _button(Icons.fast_rewind, _audioHandler.rewind),
                        if (playing)
                          _button(Icons.pause, _audioHandler.pause)
                        else
                          _button(Icons.play_arrow, _audioHandler.play),
                        _button(Icons.stop, _audioHandler.stop),
                        _button(Icons.fast_forward, _audioHandler.fastForward),
                        _button(
                          Icons.skip_next,
                          hasNext ? _audioHandler.skipToNext : null,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            // --- Seek Bar (Relies on MediaState) ---
            StreamBuilder<MediaState>(
              stream: _mediaStateStream,
              builder: (context, snapshot) {
                final mediaState = snapshot.data;
                return SeekBar(
                  duration: mediaState?.mediaItem?.duration ?? Duration.zero,
                  position: mediaState?.position ?? Duration.zero,
                  onChangeEnd: (newPosition) {
                    _audioHandler.seek(newPosition);
                  },
                );
              },
            ),
            const SizedBox(height: 20),
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
            const Divider(height: 40),
            // --- Online/Local Navigation Buttons ---
            ElevatedButton.icon(
              icon: const Icon(Icons.public),
              label: const Text('Play Default Online Stream'),
              onPressed: () {
                (_audioHandler as AudioPlayerHandler).playOnlineDefault();
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Scan Local Files'),
              onPressed: _startScan,
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

  IconButton _button(IconData iconData, VoidCallback? onPressed) => IconButton(
    icon: Icon(iconData),
    iconSize: 64.0,
    onPressed: onPressed,
    disabledColor: Colors.grey,
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
  final ValueChanged<Duration>? onChanged;
  final ValueChanged<Duration>? onChangeEnd;

  SeekBar({
    required this.duration,
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
        Positioned(
          left: 16.0,
          bottom: 0.0,
          child: Text(
            _formatDuration(widget.position),
            style: const TextStyle(color: Colors.black),
          ),
        ),
        // Remaining/Total Display
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString();
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
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
