import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rhythm/app_config/app_theme.dart';
// Assuming these imports point to your custom files, keeping them as placeholders
import 'package:rhythm/custom_audio_handler/audio_scanner_utils.dart'; // Placeholder
import 'package:rhythm/custom_audio_handler/custom_audio_handler_with_metadata.dart'; // Placeholder
import 'package:rxdart/rxdart.dart';
import 'package:just_audio/just_audio.dart'; // Just Audio is used internally by Audio Service/just_audio
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

// --- Global State and Theme Management ---
late AudioHandler _audioHandler;
// ValueNotifier for theme state, making it accessible application-wide
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize SharedPreferences and load saved theme
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('app_theme');
  if (savedTheme == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else if (savedTheme == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else {
    // Default to system if no preference or 'system' is saved
    themeNotifier.value = ThemeMode.system;
  }

  // 2. Initialize Audio Handler
  _audioHandler = await AudioService.init(
    builder: () => CustomAudioHandler(), // CustomAudioHandler must be defined
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.myaudio.channel',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(const MyApp());
}

// --- App Root Widget ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use ValueListenableBuilder to rebuild the MaterialApp when the theme changes
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Rhythm Player',
          // Define Light Theme
          theme: AppTheme.lightTheme,

          // Define Dark Theme
          darkTheme: AppTheme.darkTheme,
          themeMode: mode, // Use the dynamically managed theme mode
          home: const MainScreen(),
        );
      },
    );
  }
}

// --- Main Screen Widget ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

// --- Main Screen State ---
class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  // Utility for scanning local music files
  final LocalMusicScanner _scanner = LocalMusicScanner();

  // State variables for local music management
  List<SongInfo> _musicFiles = [];
  bool _isScanning = false;
  String? _message;
  String? _currentId;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;

  // Notifiers for optimistic UI updates
  late ValueNotifier<AudioServiceRepeatMode> _repeatModeNotifier;
  late ValueNotifier<bool> _shuffleNotifier;

  // Static list of online songs (used for demo/testing)
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
    // ... other online items
  ];

  // Stream that combines the current media item and playback position
  Stream<MediaState> get _mediaStateStream =>
      Rx.combineLatest2<MediaItem?, Duration, MediaState>(
        _audioHandler.mediaItem,
        AudioService.position,
        (mediaItem, position) => MediaState(mediaItem, position),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _repeatModeNotifier = ValueNotifier(AudioServiceRepeatMode.none);
    _shuffleNotifier = ValueNotifier(false);

    // Listen to playback state to update notifiers
    _audioHandler.playbackState.listen((state) {
      _repeatModeNotifier.value = state.repeatMode;
      _shuffleNotifier.value = state.shuffleMode == AudioServiceShuffleMode.all;
    });

    // Subscribe to media item changes to update the current ID and save state
    _mediaItemSubscription = _audioHandler.mediaItem.listen((item) {
      _saveCurrentState();
      setState(() {
        _currentId = item?.id;
      });
    });

    // Listen to queue changes to save state
    _audioHandler.queue.listen((_) {
      _saveCurrentState();
    });

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
    // Save state when the app is paused (e.g., sent to background)
    if (state == AppLifecycleState.paused) {
      _saveCurrentState();
    }
  }

  // --- Utility Methods ---

  // Formats a Duration object into a 'mm:ss' or 'h:mm:ss' string.
  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '--:--';
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  // Checks if a given song ID is the one currently playing
  bool _isCurrent(String id) {
    return id == _currentId;
  }

  // Toggles between light and dark theme
  void _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTheme = themeNotifier.value;
    ThemeMode newTheme;

    if (currentTheme == ThemeMode.dark) {
      newTheme = ThemeMode.light;
      await prefs.setString('app_theme', 'light');
    } else {
      newTheme = ThemeMode.dark;
      await prefs.setString('app_theme', 'dark');
    }
    themeNotifier.value = newTheme;
  }

  // --- Data Persistence and Loading ---

  // Loads previously saved local songs from SharedPreferences
  Future<void> _loadSavedSongs() async {
    // ... (Your existing _loadSavedSongs logic) ...
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
          // Assuming SongInfo.fromJson is an async method
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

  // Saves the current list of found songs to SharedPreferences
  Future<void> _saveSongs() async {
    // ... (Your existing _saveSongs logic) ...
    final prefs = await SharedPreferences.getInstance();
    final appDir = await getApplicationDocumentsDirectory();

    // Ensure a folder exists for album arts
    final artDir = Directory('${appDir.path}/album_arts');
    if (!await artDir.exists()) {
      await artDir.create(recursive: true);
    }

    // Convert all SongInfo objects to JSON-safe maps
    final musicLists = _musicFiles.map((item) => item.toJson()).toList();

    await prefs.setString('saved_songs', json.encode(musicLists));
    debugPrint('🎵 Saved ${musicLists.length} songs with album arts.');
  }

  // Loads the playback state (queue, index, position) from the last session
  Future<void> _loadLastState() async {
    // ... (Your existing _loadLastState logic) ...
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
        // Assuming Local/Online songs can both be played via URI in CustomAudioHandler
        sources.add(AudioSource.uri(Uri.parse(id), tag: item));
      }
      if (items.isNotEmpty) {
        final lastIndex = prefs.getInt('last_index') ?? 0;
        final lastPosition = Duration(
          milliseconds: prefs.getInt('last_position') ?? 0,
        );
        // Load the saved playlist into the CustomAudioHandler
        await (_audioHandler as CustomAudioHandler).loadPlaylist(
          items,
          sources,
          initialIndex: lastIndex,
        );
        await _audioHandler.pause();
        await _audioHandler.seek(lastPosition);
      }
    }
  }

  // Saves the current playback state (queue, index) to SharedPreferences
  Future<void> _saveCurrentState() async {
    // ... (Your existing _saveCurrentState logic) ...
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
    // Setting position to 0 to resume from start of the track on reload
    await prefs.setInt(
      'last_position',
      0, // Consider saving the actual position here if you want resume playback
    );
  }

  // --- Scanning Logic ---

  // Starts a general automatic scan for music files
  Future<void> _startScan() async {
    // ... (Your existing _startScan logic) ...
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

  // Allows the user to select a folder and scans it
  Future<void> _selectAndScanFolder() async {
    // ... (Your existing _selectAndScanFolder logic) ...
    final String? directoryPath = await FilePicker.platform.getDirectoryPath();
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

  // --- Playback Controls ---

  // Starts playback for a list of local songs
  void _playLocalSongs(List<SongInfo> playlist, int index) {
    // Ensure CustomAudioHandler has playLocalPlaylist method
    (_audioHandler as CustomAudioHandler).playLocalPlaylist(playlist, index);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing local: ${playlist[index].meta.title}')),
    );
  }

  // Starts playback for a list of online songs
  void _playOnlineSongs(List<MediaItem> items, int index) {
    // Ensure CustomAudioHandler has playOnlinePlaylist method
    (_audioHandler as CustomAudioHandler).playOnlinePlaylist(items, index);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing online: ${items[index].title}')),
    );
  }

  // --- UI Builder Methods for Tabs ---

  Widget _buildSongsTab() {
    // ... (Your existing _buildSongsTab logic) ...
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
    // ... (Your existing _buildArtistsTab logic) ...
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
    // ... (Your existing _buildAlbumsTab logic) ...
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
    // ... (Your existing _buildOnlineTab logic) ...
    return ListView.builder(
      itemCount: _onlineItems.length,
      itemBuilder: (context, index) {
        final item = _onlineItems[index];
        return ListTile(
          title: Text(item.title),
          subtitle: Text(
            '${item.artist ?? 'Unknown'} - ${item.album ?? 'Unknown'}',
          ),
          leading: const Icon(Icons.public), // Differentiate online
          trailing:
              _isCurrent(item.id)
                  ? const Icon(Icons.volume_up, color: Colors.blue)
                  : null,
          onTap: () => _playOnlineSongs(_onlineItems, index),
        );
      },
    );
  }

  // --- Main Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rhythm Audio Player'),
        actions: [
          // Theme Switch Button
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Compact Player UI ---
            _buildCompactPlayer(),

            const Divider(height: 40),

            // --- Control and Scan Buttons ---
            _buildControlButtons(),

            const SizedBox(height: 20),

            // --- Scanning Status and Song List ---
            _buildMusicListSection(),
          ],
        ),
      ),
    );
  }

  // Refactored method to build the compact player widget
  Widget _buildCompactPlayer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurface.withOpacity(0.4);

    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem,
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

        Widget artWidget;
        if (mediaItem.artUri != null) {
          final uri = mediaItem.artUri!;
          if (uri.scheme == 'file') {
            artWidget = Image.file(
              File.fromUri(uri),
              height: 50,
              width: 50,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) =>
                      Icon(Icons.album, size: 50, color: inactiveColor),
            );
          } else {
            artWidget = Image.network(
              uri.toString(),
              height: 50,
              width: 50,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) =>
                      Icon(Icons.album, size: 50, color: inactiveColor),
            );
          }
        } else {
          artWidget = Icon(Icons.album, size: 50, color: inactiveColor);
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                isDark
                    ? Colors.black.withValues(alpha: 0.8)
                    : AppTheme.lightTheme.cardColor.withValues(alpha: 0.9),
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
              // Top Row: Art + Title/Artist + Status Icon
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
                        _audioHandler.playbackState
                            .map((state) => state.processingState)
                            .distinct(),
                    builder: (context, snapshot) {
                      final processingState =
                          snapshot.data ?? AudioProcessingState.idle;
                      return Icon(
                        _getProcessingIcon(processingState),
                        size: 20,
                        color: inactiveColor,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // SeekBar
              StreamBuilder<MediaState>(
                stream: _mediaStateStream,
                builder: (context, snapshot) {
                  final mediaState = snapshot.data;
                  final position = mediaState?.position ?? Duration.zero;
                  final duration =
                      mediaState?.mediaItem?.duration ?? Duration.zero;

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

              // Control Row
              StreamBuilder<PlaybackState>(
                stream: _audioHandler.playbackState,
                builder: (context, snapshot) {
                  final playback = snapshot.data;
                  final playing = playback?.playing ?? false;
                  final queueIndex = playback?.queueIndex ?? 0;
                  final queueLength = _audioHandler.queue.value.length;
                  final repeatMode = _repeatModeNotifier.value;
                  final shuffleEnabled = _shuffleNotifier.value;

                  final hasPrev =
                      (repeatMode != AudioServiceRepeatMode.one) && queueIndex > 0;
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
                              .catchError((e) {
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
                            AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                            AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                            _ => AudioServiceRepeatMode.none,
                          };
                          _repeatModeNotifier.value = next;
                          (_audioHandler as CustomAudioHandler)
                              .setRepeatMode(next)
                              .catchError((e) {
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

  // Refactored method to build the control and scan buttons
  Widget _buildControlButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.folder_open),
          label: const Text('Scan Local Files (Automatic Search)'),
          onPressed: _startScan,
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.folder_special),
          label: const Text('Select Specific Folder and Scan'),
          onPressed: _selectAndScanFolder,
        ),
      ],
    );
  }

  // Refactored method to build the music list section with tabs
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
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
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
        SizedBox(
          // Fixed height is necessary for nested ListView/TabBarView
          height: 350,
          child:
              _isScanning
                  ? const Center(child: CircularProgressIndicator())
                  : _musicFiles.isEmpty &&
                      _message != null &&
                      !_message!.contains('Found')
                  ? Center(child: Text(_message!))
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

  // Helper to get an icon based on audio processing state
  IconData _getProcessingIcon(AudioProcessingState state) {
    switch (state) {
      case AudioProcessingState.loading:
      case AudioProcessingState.buffering:
        return Icons.cached;
      case AudioProcessingState.ready:
        return Icons.done;
      case AudioProcessingState.completed:
        return Icons.repeat;
      case AudioProcessingState.idle:
      case AudioProcessingState.error:
        return Icons.bar_chart_sharp; // As in original code approximation
    }
  }
}

// --- Data Classes and Utility Widgets ---

// Class to hold both MediaItem and Position for the StreamBuilder
class MediaState {
  final MediaItem? mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

// Custom SeekBar Widget (Simplified and theme-aware)
class SeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final ValueChanged<Duration>? onChangeEnd;
  final Color activeColor;
  final Color inactiveColor;

  const SeekBar({
    super.key,
    required this.duration,
    required this.position,
    this.bufferedPosition = Duration.zero,
    this.onChangeEnd,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  _SeekBarState createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;
  bool _dragging = false;

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
    final sliderMax = max(1.0, maxDuration);

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3.0, // Thicker track
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        overlayColor: widget.activeColor.withOpacity(0.2),
      ),
      child: Slider(
        min: 0.0,
        max: sliderMax,
        value: min(value, sliderMax),
        activeColor: widget.activeColor,
        inactiveColor: widget.inactiveColor,
        onChanged: (newValue) {
          setState(() {
            _dragging = true;
            _dragValue = newValue;
          });
        },
        onChangeEnd: (newValue) {
          _dragging = false;
          widget.onChangeEnd?.call(Duration(milliseconds: newValue.round()));
          _dragValue = null; // Reset drag value after seeking
        },
      ),
    );
  }
}
