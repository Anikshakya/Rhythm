import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rhythm/app_config/app_theme.dart';
import 'package:rhythm/custom_audio_handler/audio_scanner_utils.dart';
import 'package:rhythm/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Global audio handler for managing playback
late AudioHandler _audioHandler;

// ValueNotifier for managing app theme dynamically
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

// Entry point of the application
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved theme preference
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('app_theme');
  themeNotifier.value =
      savedTheme == 'dark'
          ? ThemeMode.dark
          : savedTheme == 'light'
          ? ThemeMode.light
          : ThemeMode.system;

  // Initialize audio handler with configuration
  _audioHandler = await AudioService.init(
    builder: () => CustomAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.myaudio.channel',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(const MyApp());
}

/// Root widget of the application
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Rhythm Player',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const MainScreen(),
        );
      },
    );
  }
}

/// Main screen of the app handling music library and player UI
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  // Scanner for local music files
  final LocalMusicScanner _scanner = LocalMusicScanner();

  // List of discovered local songs
  List<SongInfo> _musicFiles = [];

  // Flag for ongoing scanning operation
  bool _isScanning = false;

  // Message for scanning status or errors
  String? _message;

  // ID of the currently playing song
  String? _currentId;

  // Subscription to media item changes
  StreamSubscription<MediaItem?>? _mediaItemSubscription;

  // Notifiers for repeat and shuffle modes for optimistic UI updates
  late ValueNotifier<AudioServiceRepeatMode> _repeatModeNotifier;
  late ValueNotifier<bool> _shuffleNotifier;

  // Static list of online demo songs
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
    // Add more online items as needed
  ];

  // Combined stream for media item and position
  Stream<MediaState> get _mediaStateStream =>
      Rx.combineLatest2<MediaItem?, Duration, MediaState>(
        _audioHandler.mediaItem.stream,
        AudioService.position,
        (mediaItem, position) => MediaState(mediaItem, position),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize notifiers for repeat and shuffle
    _repeatModeNotifier = ValueNotifier(AudioServiceRepeatMode.none);
    _shuffleNotifier = ValueNotifier(false);

    // Update notifiers on playback state changes
    _audioHandler.playbackState.stream.listen((state) {
      _repeatModeNotifier.value = state.repeatMode;
      _shuffleNotifier.value = state.shuffleMode == AudioServiceShuffleMode.all;
    });

    // Subscribe to media item updates
    _mediaItemSubscription = _audioHandler.mediaItem.stream.listen((item) {
      _saveCurrentState();
      setState(() => _currentId = item?.id);
    });

    // Subscribe to queue changes
    _audioHandler.queue.stream.listen((_) => _saveCurrentState());

    // Load saved data asynchronously
    _loadSavedSongs();
    _loadLastState();
  }

  @override
  void dispose() {
    _mediaItemSubscription?.cancel();
    _repeatModeNotifier.dispose();
    _shuffleNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveCurrentState();
    }
  }

  // Format duration as mm:ss or h:mm:ss
  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '--:--';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  // Check if a song is currently playing
  bool _isCurrent(String id) => id == _currentId;

  // Toggle between light and dark theme
  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTheme = themeNotifier.value;
    final newTheme =
        currentTheme == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    themeNotifier.value = newTheme;
    await prefs.setString(
      'app_theme',
      newTheme == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  // Load saved local songs from preferences
  Future<void> _loadSavedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSongsJson = prefs.getString('saved_songs');
    if (savedSongsJson == null) {
      setState(() => _message = 'No saved songs found. Scan to find songs.');
      return;
    }

    try {
      final savedList = json.decode(savedSongsJson) as List<dynamic>;
      final loadedSongs = <SongInfo>[];
      for (final map in savedList) {
        final song = await SongInfo.fromJson(
          Map<String, dynamic>.from(map as Map),
        );
        if (song != null) loadedSongs.add(song);
      }
      setState(() {
        _musicFiles = loadedSongs;
        _message = 'Loaded ${loadedSongs.length} saved songs.';
      });
    } catch (e) {
      debugPrint('Error loading saved songs: $e');
      setState(() => _message = 'Failed to load saved songs.');
    }
  }

  // Save current list of songs to preferences
  Future<void> _saveSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final musicLists = _musicFiles.map((item) => item.toJson()).toList();
    await prefs.setString('saved_songs', json.encode(musicLists));
    debugPrint('Saved ${_musicFiles.length} songs.');
  }

  // Load last playback state
  Future<void> _loadLastState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastQueueJson = prefs.getString('last_queue');
    if (lastQueueJson == null) return;

    final lastQueueList = json.decode(lastQueueJson) as List<dynamic>;
    final items = <MediaItem>[];
    final sources = <AudioSource>[];
    for (final map in lastQueueList) {
      final id = map['id'] as String;
      final item = MediaItem(
        id: id,
        title: map['title'] as String? ?? 'Unknown Title',
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        duration: Duration(milliseconds: map['duration'] as int? ?? 0),
        artUri:
            map['artUri'] != null ? Uri.parse(map['artUri'] as String) : null,
      );
      items.add(item);
      sources.add(AudioSource.uri(Uri.parse(id), tag: item));
    }

    if (items.isNotEmpty) {
      final lastIndex = prefs.getInt('last_index') ?? 0;
      final lastPosition = Duration(
        milliseconds: prefs.getInt('last_position') ?? 0,
      );
      await (_audioHandler as CustomAudioHandler).loadPlaylist(
        items,
        sources,
        initialIndex: lastIndex,
      );
      await _audioHandler.pause();
      await _audioHandler.seek(lastPosition);
    }
  }

  // Save current playback state
  Future<void> _saveCurrentState() async {
    final prefs = await SharedPreferences.getInstance();
    final currentQueue = _audioHandler.queue.value;
    if (currentQueue.isEmpty) return;

    final queueList =
        currentQueue
            .map(
              (item) => {
                'id': item.id,
                'title': item.title,
                'artist': item.artist,
                'album': item.album,
                'duration': item.duration?.inMilliseconds,
                'artUri': item.artUri?.toString(),
              },
            )
            .toList();
    await prefs.setString('last_queue', json.encode(queueList));
    await prefs.setInt(
      'last_index',
      _audioHandler.playbackState.value.queueIndex ?? 0,
    );
    await prefs.setInt('last_position', 0); // Reset position for next launch
  }

  // Start automatic scan for local music
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
        _message = 'Found ${foundSongs.length} songs.';
      });
      await _saveSongs();
    } catch (e) {
      setState(() => _message = 'Scan failed: $e');
    } finally {
      setState(() => _isScanning = false);
    }
  }

  // Scan selected folder for local music
  Future<void> _selectAndScanFolder() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null) return;

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
        _message = 'Found ${foundSongs.length} songs in selected folder.';
      });
      await _saveSongs();
    } catch (e) {
      setState(() => _message = 'Scan failed: $e');
    } finally {
      setState(() => _isScanning = false);
    }
  }

  // Play local playlist starting from index
  void _playLocalSongs(List<SongInfo> playlist, int index) {
    (_audioHandler as CustomAudioHandler).playLocalPlaylist(playlist, index);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing: ${playlist[index].meta.title}')),
    );
  }

  // Play online playlist starting from index
  void _playOnlineSongs(List<MediaItem> items, int index) {
    (_audioHandler as CustomAudioHandler).playOnlinePlaylist(items, index);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Playing: ${items[index].title}')));
  }

  // Get album art URI from the first song in the list
  Uri? _getAlbumArt(List<SongInfo> songs) {
    if (songs.isEmpty) return null;
    final song = songs.first;
    return song.meta.artUri ??
        (song.meta.albumArt != null
            ? Uri.file(
              '${(getTemporaryDirectory())}/art_${song.file.path.hashCode}.jpg',
            )
            : null);
  }

  // Get artist art (using first song's art as proxy)
  Uri? _getArtistArt(List<SongInfo> songs) {
    return _getAlbumArt(songs);
  }

  // Build tab for all songs
  Widget _buildSongsTab() {
    if (_musicFiles.isEmpty) {
      return const Center(child: Text('No local songs found.'));
    }
    return ListView.builder(
      itemCount: _musicFiles.length,
      itemBuilder: (context, index) {
        final song = _musicFiles[index];
        final songId = Uri.file(song.file.path).toString();
        Widget leading = const Icon(Icons.music_note);
        if (song.meta.artUri != null) {
          leading = CircleAvatar(
            backgroundImage: FileImage(File(song.meta.artUri!.path)),
          );
        } else if (song.meta.albumArt != null) {
          leading = CircleAvatar(
            backgroundImage: MemoryImage(song.meta.albumArt!),
          );
        }
        return ListTile(
          leading: leading,
          title: Text(song.meta.title),
          subtitle: Text('${song.meta.artist} - ${song.meta.album}'),
          trailing:
              _isCurrent(songId)
                  ? const Icon(Icons.volume_up, color: Colors.blue)
                  : null,
          onTap: () => _playLocalSongs(_musicFiles, index),
        );
      },
    );
  }

  // Build tab for artists
  Widget _buildArtistsTab() {
    if (_musicFiles.isEmpty) {
      return const Center(child: Text('No local artists found.'));
    }
    final artists = <String, List<SongInfo>>{};
    for (final song in _musicFiles) {
      artists.putIfAbsent(song.meta.artist, () => []).add(song);
    }
    final artistList = artists.keys.toList()..sort();
    return ListView.builder(
      itemCount: artistList.length,
      itemBuilder: (context, index) {
        final artist = artistList[index];
        final songs = artists[artist]!;
        return ListTile(
          title: Text(artist),
          subtitle: Text('${songs.length} songs'),
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          ArtistDetailScreen(artist: artist, songs: songs),
                ),
              ),
        );
      },
    );
  }

  // Build tab for albums with grid view
  Widget _buildAlbumsTab() {
    if (_musicFiles.isEmpty) {
      return const Center(child: Text('No local albums found.'));
    }
    final albums = <String, List<SongInfo>>{};
    for (final song in _musicFiles) {
      albums.putIfAbsent(song.meta.album, () => []).add(song);
    }
    final albumList = albums.keys.toList()..sort();
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: albumList.length,
      itemBuilder: (context, index) {
        final album = albumList[index];
        final songs = albums[album]!;
        final artUri = _getAlbumArt(songs);
        final artist = songs.first.meta.artist;
        return GestureDetector(
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => AlbumDetailScreen(
                        album: album,
                        artist: artist,
                        songs: songs,
                        artUri: artUri,
                      ),
                ),
              ),
          child: Column(
            children: [
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image:
                      artUri != null
                          ? DecorationImage(
                            image: FileImage(File(artUri.path)),
                            fit: BoxFit.cover,
                          )
                          : null,
                  color: Colors.grey[300],
                ),
                child:
                    artUri == null ? const Icon(Icons.album, size: 60) : null,
              ),
              const SizedBox(height: 8),
              Text(
                album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  // Build tab for online songs (always available)
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
          leading: const Icon(Icons.public),
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
      appBar: AppBar(
        title: const Text('Rhythm Audio Player'),
        actions: [
          IconButton(
            icon: Icon(
              themeNotifier.value == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: _toggleTheme,
            tooltip: 'Toggle Theme',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _selectAndScanFolder,
        child: const Icon(Icons.folder_special),
        tooltip: 'Select Folder to Scan',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Compact player UI
            _buildCompactPlayer(),

            const Divider(height: 40),

            // Scan control buttons (only auto scan)
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Scan Local Files (Automatic)'),
              onPressed: _startScan,
            ),

            const SizedBox(height: 20),

            // Music library section with status and tabs
            _buildMusicListSection(),
          ],
        ),
      ),
    );
  }

  // Build compact player controls
  Widget _buildCompactPlayer() {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurface.withOpacity(0.4);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem.stream,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        if (mediaItem == null) {
          return Center(
            child: Text(
              'Select a track to play.',
              style: TextStyle(color: inactiveColor),
            ),
          );
        }

        Widget artWidget = Icon(Icons.album, size: 50, color: inactiveColor);
        if (mediaItem.artUri != null) {
          final uri = mediaItem.artUri!;
          artWidget =
              uri.scheme == 'file'
                  ? Image.file(
                    File(uri.path),
                    height: 50,
                    width: 50,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) =>
                            Icon(Icons.album, size: 50, color: inactiveColor),
                  )
                  : Image.network(
                    uri.toString(),
                    height: 50,
                    width: 50,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) =>
                            Icon(Icons.album, size: 50, color: inactiveColor),
                  );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                isDark
                    ? Colors.black.withOpacity(0.8)
                    : AppTheme.lightTheme.cardColor.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: inactiveColor.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 50,
                      width: 50,
                      color: inactiveColor.withOpacity(0.1),
                      child: artWidget,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mediaItem.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          mediaItem.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  StreamBuilder<AudioProcessingState>(
                    stream:
                        _audioHandler.playbackState.stream
                            .map((state) => state.processingState)
                            .distinct(),
                    builder: (context, snapshot) {
                      final state = snapshot.data ?? AudioProcessingState.idle;
                      return Icon(
                        _getProcessingIcon(state),
                        size: 20,
                        color: inactiveColor,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              StreamBuilder<MediaState>(
                stream: _mediaStateStream,
                builder: (context, snapshot) {
                  final position = snapshot.data?.position ?? Duration.zero;
                  final duration =
                      snapshot.data?.mediaItem?.duration ?? Duration.zero;
                  return Row(
                    children: [
                      Text(
                        _formatDuration(position),
                        style: TextStyle(color: inactiveColor, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SeekBar(
                          duration: duration,
                          position: position,
                          activeColor: primaryColor,
                          inactiveColor: inactiveColor.withOpacity(0.3),
                          onChangeEnd: (newPos) => _audioHandler.seek(newPos),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(duration),
                        style: TextStyle(color: inactiveColor, fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              StreamBuilder<PlaybackState>(
                stream: _audioHandler.playbackState.stream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  final queueIndex = snapshot.data?.queueIndex ?? 0;
                  final queueLength = _audioHandler.queue.value.length;
                  final repeatMode = _repeatModeNotifier.value;
                  final shuffleEnabled = _shuffleNotifier.value;

                  final hasPrev =
                      (repeatMode != AudioServiceRepeatMode.one) &&
                      queueIndex > 0;
                  final hasNext =
                      (repeatMode != AudioServiceRepeatMode.one) &&
                      queueIndex < queueLength - 1;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: Icon(
                          shuffleEnabled ? Icons.shuffle_on : Icons.shuffle,
                          color: shuffleEnabled ? primaryColor : inactiveColor,
                          size: 24,
                        ),
                        onPressed: () {
                          final current = shuffleEnabled;
                          _shuffleNotifier.value = !current;
                          (_audioHandler as CustomAudioHandler)
                              .toggleShuffle()
                              .catchError((_) {
                                _shuffleNotifier.value = current;
                              });
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.skip_previous,
                          color: hasPrev ? primaryColor : inactiveColor,
                          size: 36,
                        ),
                        onPressed:
                            hasPrev ? _audioHandler.skipToPrevious : null,
                      ),
                      IconButton(
                        icon: Icon(
                          playing
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                          color: primaryColor,
                          size: 48,
                        ),
                        onPressed:
                            playing ? _audioHandler.pause : _audioHandler.play,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.skip_next,
                          color: hasNext ? primaryColor : inactiveColor,
                          size: 36,
                        ),
                        onPressed: hasNext ? _audioHandler.skipToNext : null,
                      ),
                      IconButton(
                        icon: Icon(
                          repeatMode == AudioServiceRepeatMode.one
                              ? Icons.repeat_one
                              : Icons.repeat,
                          color:
                              repeatMode != AudioServiceRepeatMode.none
                                  ? primaryColor
                                  : inactiveColor,
                          size: 24,
                        ),
                        onPressed: () {
                          final current = repeatMode;
                          final next = switch (current) {
                            AudioServiceRepeatMode.none =>
                              AudioServiceRepeatMode.all,
                            AudioServiceRepeatMode.all =>
                              AudioServiceRepeatMode.one,
                            _ => AudioServiceRepeatMode.none,
                          };
                          _repeatModeNotifier.value = next;
                          (_audioHandler as CustomAudioHandler)
                              .setRepeatMode(next)
                              .catchError((_) {
                                _repeatModeNotifier.value = current;
                              });
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
    );
  }

  // Build music library section with status and tabs
  Widget _buildMusicListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _message ?? 'Local Music Library',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (_isScanning) const CircularProgressIndicator(),
            ],
          ),
        ),
        const Divider(),
        SizedBox(
          height: 350,
          child:
              _isScanning
                  ? const Center(child: CircularProgressIndicator())
                  : DefaultTabController(
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
    );
  }

  // Get icon for processing state
  IconData _getProcessingIcon(AudioProcessingState state) {
    return switch (state) {
      AudioProcessingState.loading ||
      AudioProcessingState.buffering => Icons.cached,
      AudioProcessingState.ready => Icons.done,
      AudioProcessingState.completed => Icons.repeat,
      _ => Icons.error,
    };
  }
}

/// Screen for artist details
class ArtistDetailScreen extends StatelessWidget {
  final String artist;
  final List<SongInfo> songs;

  const ArtistDetailScreen({
    super.key,
    required this.artist,
    required this.songs,
  });

  Uri? _getArtistArt() {
    if (songs.isEmpty) return null;
    final song = songs.first;
    return song.meta.artUri ??
        (song.meta.albumArt != null
            ? Uri.file(
              '${(getTemporaryDirectory())}/art_${song.file.path.hashCode}.jpg',
            )
            : null);
  }

  void _playSongs(int index, {bool shuffle = false}) {
    final handler = _audioHandler as CustomAudioHandler;
    if (shuffle) {
      handler.toggleShuffle();
    }
    handler.playLocalPlaylist(songs, index);
  }

  @override
  Widget build(BuildContext context) {
    final artUri = _getArtistArt();
    return Scaffold(
      appBar: AppBar(title: Text(artist)),
      body: Column(
        children: [
          if (artUri != null)
            Image.file(
              File(artUri.path),
              height: 200,
              width: 200,
              fit: BoxFit.cover,
            ),
          Text(artist, style: Theme.of(context).textTheme.headlineMedium),
          Text(
            '${songs.length} songs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => _playSongs(0),
                child: const Text('Play'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () => _playSongs(0, shuffle: true),
                child: const Text('Shuffle'),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return ListTile(
                  title: Text(song.meta.title),
                  subtitle: Text(song.meta.album),
                  onTap: () => _playSongs(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen for album details
class AlbumDetailScreen extends StatelessWidget {
  final String album;
  final String artist;
  final List<SongInfo> songs;
  final Uri? artUri;

  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.artist,
    required this.songs,
    this.artUri,
  });

  void _playSongs(int index, {bool shuffle = false}) {
    final handler = _audioHandler as CustomAudioHandler;
    if (shuffle) {
      handler.toggleShuffle();
    }
    handler.playLocalPlaylist(songs, index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(album),
              background:
                  artUri != null
                      ? Image.file(File(artUri!.path), fit: BoxFit.cover)
                      : const Center(child: Icon(Icons.album, size: 100)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(artist, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FilledButton(
                        onPressed: () => _playSongs(0),
                        child: const Text('Play'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _playSongs(0, shuffle: true),
                        child: const Text('Shuffle'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final song = songs[index];
              return ListTile(
                leading: Text('${index + 1}'),
                title: Text(song.meta.title),
                onTap: () => _playSongs(index),
              );
            }, childCount: songs.length),
          ),
        ],
      ),
    );
  }
}

/// Combined media state for stream builder
class MediaState {
  final MediaItem? mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

/// Custom seek bar widget
class SeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final ValueChanged<Duration>? onChangeEnd;
  final Color activeColor;
  final Color inactiveColor;

  const SeekBar({
    super.key,
    required this.duration,
    required this.position,
    this.onChangeEnd,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  _SeekBarState createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    double value = _dragValue ?? widget.position.inMilliseconds.toDouble();
    value = value.clamp(0.0, widget.duration.inMilliseconds.toDouble());
    final max = widget.duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );

    return Slider(
      min: 0.0,
      max: max,
      value: value,
      activeColor: widget.activeColor,
      inactiveColor: widget.inactiveColor,
      onChanged: (newValue) => setState(() => _dragValue = newValue),
      onChangeEnd: (newValue) {
        widget.onChangeEnd?.call(Duration(milliseconds: newValue.round()));
        setState(() => _dragValue = null);
      },
    );
  }
}
