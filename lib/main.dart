import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:rhythm/app_config/app_theme.dart'; // Assuming this is your theme file
import 'package:rhythm/custom_audio_handler/audio_scanner_utils.dart'; // Assuming this exists
import 'package:rhythm/custom_audio_handler/custom_audio_handler_with_metadata.dart'; // Assuming this exists
import 'package:rxdart/rxdart.dart' as rx;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Global audio handler for managing playback
late AudioHandler _audioHandler;

// ValueNotifier for managing app theme dynamically
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

// Notifiers for repeat and shuffle modes for optimistic UI updates
ValueNotifier<AudioServiceRepeatMode> repeatModeNotifier = ValueNotifier(
  AudioServiceRepeatMode.none,
);
ValueNotifier<bool> shuffleNotifier = ValueNotifier(false);
ValueNotifier<bool> _showBlurImagePlayerBg = ValueNotifier(false);
ValueNotifier<bool> _showFullPlayer = ValueNotifier(false);

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
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Rhythm Player',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const MainScreen(),
          builder: (context, child) {
            return GlobalWrapper(child: child!);
          },
        );
      },
    );
  }
}

/// Utility class for common functions
class AppUtils {
  static String formatDuration(Duration duration) {
    if (duration == Duration.zero) return '--:--';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  static Uri? getAlbumArt(List<SongInfo> songs) {
    if (songs.isEmpty) return null;
    final song = songs.first;
    return song.meta.artUri ??
        (song.meta.albumArt != null
            ? Uri.file(
              '${(getTemporaryDirectory())}/art_${song.file.path.hashCode}.jpg',
            )
            : null);
  }

  static Uri? getArtistArt(List<SongInfo> songs) {
    return getAlbumArt(songs); // Reuse the same logic for artist art
  }

  static IconData getProcessingIcon(AudioProcessingState state) {
    return switch (state) {
      AudioProcessingState.loading ||
      AudioProcessingState.buffering => Icons.cached,
      AudioProcessingState.ready => Icons.done,
      AudioProcessingState.completed => Icons.repeat,
      _ => Icons.error,
    };
  }
}

 /// Reusable widget for song tile
class SongTile extends StatelessWidget {
  final SongInfo song;
  final bool isCurrent;
  final VoidCallback onTap;
  final int? trackNumber;
  final bool showDuration;

  const SongTile({
    super.key,
    required this.song,
    required this.isCurrent,
    required this.onTap,
    this.trackNumber,
    this.showDuration = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w500,
      color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
    );
    final subtitleStyle = TextStyle(color: Colors.grey[600]);
    final duration = Duration(milliseconds: song.meta.durationMs ?? 0);
    final formattedDuration = AppUtils.formatDuration(duration);

    Widget leading;
    Widget? subtitleWidget;
    Widget? trailing;

    if (trackNumber != null) {
      // Album mode: number or eq left, duration right, no subtitle
      leading = isCurrent 
          ? Icon(Icons.bar_chart_rounded)
          : Text('$trackNumber', style: subtitleStyle);
      subtitleWidget = null;
      trailing = Text(formattedDuration, style: subtitleStyle);
    } else {
      // General mode: art left, artist subtitle, eq right if current
      leading = SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: _buildArt(),
        ),
      );
      subtitleWidget = Text(song.meta.artist, style: subtitleStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
      trailing = isCurrent ? Icon(Icons.bar_chart_rounded, color: theme.colorScheme.primary) : null;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 0,
      leading: leading,
      title: Text(song.meta.title, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitleWidget,
      trailing: trailing,
      onTap: onTap,
      shape: const Border(bottom: BorderSide(color: Colors.grey, width: 0.1)),
    );
  }

  Widget _buildArt() {
    if (song.meta.artUri != null) {
      return Image.file(
        File(song.meta.artUri!.path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note_outlined),
      );
    } else if (song.meta.albumArt != null) {
      return Image.memory(
        song.meta.albumArt!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note_outlined),
      );
    } else {
      return const Icon(Icons.music_note_outlined);
    }
  }
}

/// Reusable widget for online item tile
class OnlineTile extends StatelessWidget {
  final MediaItem item;
  final bool isCurrent;
  final VoidCallback onTap;

  const OnlineTile({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w500,
      color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
    );
    final subtitleStyle = TextStyle(color: Colors.grey[600]);
    // final formattedDuration = AppUtils.formatDuration(item.duration ?? Duration.zero);

    Widget leading = SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: _buildArt(),
      ),
    );
    Widget? trailing = isCurrent ? Icon(Icons.bar_chart_rounded, color: theme.colorScheme.primary): null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 0,
      leading: leading,
      title: Text(item.title, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.artist ?? 'Unknown', style: subtitleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: onTap,
      shape: const Border(bottom: BorderSide(color: Colors.grey, width: 0.1)),
    );
  }

  Widget _buildArt() {
    if (item.artUri != null) {
      final uri = item.artUri!;
      if (uri.scheme == 'file') {
        return Image.file(
          File(uri.path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.cloud_queue_outlined),
        );
      } else {
        return Image.network(
          uri.toString(),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.cloud_queue_outlined),
        );
      }
    } else {
      return const Icon(Icons.cloud_queue_outlined);
    }
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
  // Static list of online demo songs
  static final List<MediaItem> _onlineItems = [
    MediaItem(
      id: 'https://freepd.com/music/A%20Good%20Bass%20for%20Gambling.mp3 ',
      title: 'A Good Bass for Gambling',
      artist: 'Kevin MacLeod',
      album: 'FreePD',
      duration: Duration.zero,
    ),
    MediaItem(
      id: 'https://freepd.com/music/A%20Surprising%20Encounter.mp3 ',
      title: 'A Surprising Encounter',
      artist: 'Kevin MacLeod',
      album: 'FreePD',
      duration: Duration.zero,
    ),
  ];
  // Global key for Scaffold to open endDrawer
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Update notifiers on playback state changes
    _audioHandler.playbackState.stream.listen((state) {
      repeatModeNotifier.value = state.repeatMode;
      shuffleNotifier.value = state.shuffleMode == AudioServiceShuffleMode.all;
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
    repeatModeNotifier.dispose();
    shuffleNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveCurrentState();
    }
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
      setState(() => _message = 'Failed to load saved songs.');
    }
  }

  // Save current list of songs to preferences
  Future<void> _saveSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final musicLists = _musicFiles.map((item) => item.toJson()).toList();
    await prefs.setString('saved_songs', json.encode(musicLists));
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

  // Build tab content based on index
  Widget _buildTabContent(int index) {
    switch (index) {
      case 0:
        return _buildSongsTab();
      case 1:
        return _buildOnlineTab();
      case 2:
        return _buildArtistsTab();
      case 3:
        return _buildAlbumsTab();
      case 4:
        return _buildFoldersTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // Build tab for all songs
  Widget _buildSongsTab() {
    if (_musicFiles.isEmpty) {
      return const Center(child: Text('No local songs found.'));
    }
    return ListView.builder(
      itemCount: _musicFiles.length,
      padding: const EdgeInsets.only(
        bottom: 210,
      ), // To Avoid Miniplayer Overlap
      itemBuilder: (context, index) {
        final song = _musicFiles[index];
        final songId = Uri.file(song.file.path).toString();
        return SongTile(
          song: song,
          isCurrent: _isCurrent(songId),
          onTap: () => _playLocalSongs(_musicFiles, index),
        );
      },
    );
  }

  // Build tab for online (using online items as placeholder)
  Widget _buildOnlineTab() {
    if (_onlineItems.isEmpty) {
      return const Center(child: Text('No online found.'));
    }
    return ListView.builder(
      itemCount: _onlineItems.length,
      padding: const EdgeInsets.only(
        bottom: 210,
      ), // To Avoid Miniplayer Overlap
      itemBuilder: (context, index) {
        final item = _onlineItems[index];
        return OnlineTile(
          item: item,
          isCurrent: _isCurrent(item.id),
          onTap: () => _playOnlineSongs(_onlineItems, index),
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
    if (artistList.isEmpty) {
      return const Center(child: Text('No matching artists found.'));
    }
    return ListView.builder(
      itemCount: artistList.length,
      padding: const EdgeInsets.only(
        bottom: 210,
      ), // To Avoid Miniplayer Overlap
      itemBuilder: (context, index) {
        final artist = artistList[index];
        final songs = artists[artist]!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
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
    if (albumList.isEmpty) {
      return const Center(child: Text('No matching albums found.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 210, top: 20), 
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
        final artUri = AppUtils.getAlbumArt(songs);
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

  // Build tab for folders
  Widget _buildFoldersTab() {
    if (_musicFiles.isEmpty) {
      return const Center(child: Text('No folders found.'));
    }
    final folders = <String, List<SongInfo>>{};
    for (final song in _musicFiles) {
      final dir = path.dirname(song.file.path);
      folders.putIfAbsent(dir, () => []).add(song);
    }
    final folderList = folders.keys.toList()..sort();
    if (folderList.isEmpty) {
      return const Center(child: Text('No matching folders found.'));
    }
    return ListView.builder(
      itemCount: folderList.length,
      padding: const EdgeInsets.only(
        bottom: 210,
      ), // To Avoid Miniplayer Overlap
      itemBuilder: (context, index) {
        final folder = folderList[index];
        final songs = folders[folder]!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            title: Text(path.basename(folder)),
            subtitle: Text('${songs.length} songs'),
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            FolderDetailScreen(folder: folder, songs: songs),
                  ),
                ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: AppDrawer(
          themeNotifier: themeNotifier,
          showBlurImagePlayerBg: _showBlurImagePlayerBg,
          startScan: _startScan,
          selectAndScanFolder: _selectAndScanFolder,
          toggleTheme: _toggleTheme,
        ),
        body: Stack(
          children: [
            NestedScrollView(
              headerSliverBuilder: (
                BuildContext context,
                bool innerBoxIsScrolled,
              ) {
                return <Widget>[
                  SliverAppBar(
                    floating: true,
                    pinned: true,
                    title: GestureDetector(
                      onTap: () {
                        Get.to(
                          () => SearchScreen(
                            musicFiles: _musicFiles,
                            onlineItems: _onlineItems,
                          ),
                        );
                      },
                      child: AbsorbPointer(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search songs, playlists, and artists',
                              suffixIcon: const Icon(Icons.search_rounded),
                              contentPadding: const EdgeInsets.only(
                                top: 5,
                                left: 15,
                                right: 5,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30.0),
                              ),
                              filled: true,
                              fillColor:
                                  Theme.of(context).colorScheme.surfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottom: const TabBar(
                      unselectedLabelColor: Colors.grey,
                      tabs: [
                        Tab(text: 'Songs'),
                        Tab(text: 'Online'),
                        Tab(text: 'Artists'),
                        Tab(text: 'Albums'),
                        Tab(text: 'Folders'),
                      ],
                    ),
                  ),
                ];
              },
              body: Column(
                children: [
                  if (_message != null)
                    Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _message ?? '${_musicFiles.length} songs',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: List.generate(
                        5,
                        (index) => _buildTabContent(index),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isScanning) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

// App Drawer

class AppDrawer extends StatelessWidget {
  final ValueNotifier<ThemeMode> themeNotifier;
  final ValueNotifier<bool> showBlurImagePlayerBg;
  final VoidCallback _startScan;
  final VoidCallback _selectAndScanFolder;
  final VoidCallback _toggleTheme;

  const AppDrawer({
    super.key,
    required this.themeNotifier,
    required this.showBlurImagePlayerBg,
    required VoidCallback startScan,
    required VoidCallback selectAndScanFolder,
    required VoidCallback toggleTheme,
  })  : _startScan = startScan,
        _selectAndScanFolder = selectAndScanFolder,
        _toggleTheme = toggleTheme;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 210),
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Scan Local Files (Automatic)'),
              onTap: () {
                Navigator.pop(context);
                _startScan();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Select Folder to Scan'),
              onTap: () {
                Navigator.pop(context);
                _selectAndScanFolder();
              },
            ),
            const Divider(),
            // 🌙 Toggle Theme
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, mode, _) {
                return ListTile(
                  leading: Icon(
                    mode == ThemeMode.dark
                        ? Icons.light_mode
                        : Icons.dark_mode,
                  ),
                  title: const Text('Dark Mode'),
                  trailing: CupertinoSwitch(
                    value: mode == ThemeMode.dark,
                    onChanged: (value) {
                      _toggleTheme();
                    },
                  ),
                );
              },
            ),
            // 🖼️ Toggle Blur Image Player Background
            ValueListenableBuilder<bool>(
              valueListenable: showBlurImagePlayerBg,
              builder: (context, value, _) {
                return ListTile(
                  leading: Icon(
                    value
                        ? Icons.image_not_supported_outlined
                        : Icons.image_rounded,
                  ),
                  title: const Text('Show Image On Bg of Player'),
                  trailing: CupertinoSwitch(
                    value: value,
                    onChanged: (newValue) {
                      showBlurImagePlayerBg.value = newValue;
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}


/// Search screen for handling search functionality
class SearchScreen extends StatefulWidget {
  final List<SongInfo> musicFiles;
  final List<MediaItem> onlineItems;
  const SearchScreen({
    super.key,
    required this.musicFiles,
    required this.onlineItems,
  });
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // Search query for filtering
  String _searchQuery = '';
  // Text controller for search bar
  final TextEditingController _searchController = TextEditingController();
  // ID of the currently playing song
  String? _currentId;
  // Subscription to media item changes
  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  @override
  void initState() {
    super.initState();
    // Subscribe to media item updates
    _mediaItemSubscription = _audioHandler.mediaItem.stream.listen((item) {
      setState(() => _currentId = item?.id);
    });
    // Listen to search changes
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _mediaItemSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Check if a song is currently playing
  bool _isCurrent(String id) => id == _currentId;
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

  // Build tab for all songs
  Widget _buildSongsTab() {
    final filteredSongs =
        widget.musicFiles.where((song) {
          final lowerTitle = song.meta.title.toLowerCase();
          final lowerArtist = song.meta.artist.toLowerCase();
          final lowerAlbum = song.meta.album.toLowerCase();
          return lowerTitle.contains(_searchQuery) ||
              lowerArtist.contains(_searchQuery) ||
              lowerAlbum.contains(_searchQuery);
        }).toList();
    if (filteredSongs.isEmpty) {
      return const Center(child: Text('No matching songs found.'));
    }
    return ListView.builder(
      itemCount: filteredSongs.length,
      padding: const EdgeInsets.only(
        bottom: 210,
      ), // To Avoid Miniplayer Overlap
      itemBuilder: (context, index) {
        final song = filteredSongs[index];
        final songId = Uri.file(song.file.path).toString();
        return SongTile(
          song: song,
          isCurrent: _isCurrent(songId),
          onTap: () => _playLocalSongs(filteredSongs, index),
        );
      },
    );
  }

  // Build tab for online (using online items)
  Widget _buildOnlineTab() {
    final filteredItems =
        widget.onlineItems.where((item) {
          final lowerTitle = item.title.toLowerCase();
          final lowerArtist = (item.artist ?? '').toLowerCase();
          final lowerAlbum = (item.album ?? '').toLowerCase();
          return lowerTitle.contains(_searchQuery) ||
              lowerArtist.contains(_searchQuery) ||
              lowerAlbum.contains(_searchQuery);
        }).toList();
    if (filteredItems.isEmpty) {
      return const Center(child: Text('No matching online found.'));
    }
    return ListView.builder(
      itemCount: filteredItems.length,
      padding: const EdgeInsets.only(
        bottom: 210,
      ), // To Avoid Miniplayer Overlap
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        return OnlineTile(
          item: item,
          isCurrent: _isCurrent(item.id),
          onTap: () => _playOnlineSongs(filteredItems, index),
        );
      },
    );
  }

  // Build tab for artists
  Widget _buildArtistsTab() {
    final artists = <String, List<SongInfo>>{};
    for (final song in widget.musicFiles) {
      final lowerArtist = song.meta.artist.toLowerCase();
      if (lowerArtist.contains(_searchQuery) ||
          song.meta.title.toLowerCase().contains(_searchQuery) ||
          song.meta.album.toLowerCase().contains(_searchQuery)) {
        artists.putIfAbsent(song.meta.artist, () => []).add(song);
      }
    }
    final artistList = artists.keys.toList()..sort();
    if (artistList.isEmpty) {
      return const Center(child: Text('No matching artists found.'));
    }
    return ListView.builder(
      itemCount: artistList.length,
      padding: const EdgeInsets.only(
        bottom: 210,
      ), // To Avoid Miniplayer Overlap
      itemBuilder: (context, index) {
        final artist = artistList[index];
        final songs = artists[artist]!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
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
          ),
        );
      },
    );
  }

  // Build tab for albums with grid view
  Widget _buildAlbumsTab() {
    final albums = <String, List<SongInfo>>{};
    for (final song in widget.musicFiles) {
      final lowerAlbum = song.meta.album.toLowerCase();
      if (lowerAlbum.contains(_searchQuery) ||
          song.meta.title.toLowerCase().contains(_searchQuery) ||
          song.meta.artist.toLowerCase().contains(_searchQuery)) {
        albums.putIfAbsent(song.meta.album, () => []).add(song);
      }
    }
    final albumList = albums.keys.toList()..sort();
    if (albumList.isEmpty) {
      return const Center(child: Text('No matching albums found.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.only(
        bottom: 210,
        top: 20
      ), // To Avoid Miniplayer Overlap
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
        final artUri = AppUtils.getAlbumArt(songs);
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

  // Build tab for folders
  Widget _buildFoldersTab() {
    final folders = <String, List<SongInfo>>{};
    for (final song in widget.musicFiles) {
      final dir = path.dirname(song.file.path);
      final lowerDir = dir.toLowerCase();
      if (lowerDir.contains(_searchQuery) ||
          song.meta.title.toLowerCase().contains(_searchQuery) ||
          song.meta.artist.toLowerCase().contains(_searchQuery) ||
          song.meta.album.toLowerCase().contains(_searchQuery)) {
        folders.putIfAbsent(dir, () => []).add(song);
      }
    }
    final folderList = folders.keys.toList()..sort();
    if (folderList.isEmpty) {
      return const Center(child: Text('No matching folders found.'));
    }
    return ListView.builder(
      itemCount: folderList.length,
      padding: const EdgeInsets.only(
        bottom: 210,
      ), // To Avoid Miniplayer Overlap
      itemBuilder: (context, index) {
        final folder = folderList[index];
        final songs = folders[folder]!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            title: Text(path.basename(folder)),
            subtitle: Text('${songs.length} songs'),
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            FolderDetailScreen(folder: folder, songs: songs),
                  ),
                ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return <Widget>[
              SliverAppBar(
                floating: true,
                pinned: true,
                title: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.only(
                        top: 5,
                        left: 15,
                        right: 5,
                      ),
                      hintText: 'Search songs, playlists, and artists',
                      suffixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceVariant,
                    ),
                  ),
                ),
                bottom: const TabBar(
                  unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(text: 'Songs'),
                    Tab(text: 'Online'),
                    Tab(text: 'Artists'),
                    Tab(text: 'Albums'),
                    Tab(text: 'Folders'),
                  ],
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              _buildSongsTab(),
              _buildOnlineTab(),
              _buildArtistsTab(),
              _buildAlbumsTab(),
              _buildFoldersTab(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen for folder details
class FolderDetailScreen extends StatefulWidget {
  final String folder;
  final List<SongInfo> songs;

  const FolderDetailScreen({
    super.key,
    required this.folder,
    required this.songs,
  });

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  String? _currentId;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;

  @override
  void initState() {
    super.initState();
    _mediaItemSubscription = _audioHandler.mediaItem.stream.listen((item) {
      setState(() => _currentId = item?.id);
    });
  }

  @override
  void dispose() {
    _mediaItemSubscription?.cancel();
    super.dispose();
  }

  bool _isCurrent(String id) => id == _currentId;

  void _playSongs(int index, {bool shuffle = false}) {
    final handler = _audioHandler as CustomAudioHandler;
    if (shuffle) {
      handler.toggleShuffle();
    }
    handler.playLocalPlaylist(widget.songs, index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(path.basename(widget.folder))),
      body: Column(
        children: [
          Text(
            '${widget.songs.length} songs',
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
              itemCount: widget.songs.length,
              itemBuilder: (context, index) {
                final song = widget.songs[index];
                final songId = Uri.file(song.file.path).toString();
                return SongTile(
                  song: song,
                  isCurrent: _isCurrent(songId),
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

/// Mini player widget that can be used across screens
class MiniPlayer extends StatelessWidget {
  MiniPlayer({super.key});
  Stream<MediaState> get _mediaStateStream =>
      rx.Rx.combineLatest2<MediaItem?, Duration, MediaState>(
        _audioHandler.mediaItem.stream,
        AudioService.position,
        (item, pos) => MediaState(item, pos),
      );

  Widget _art(MediaItem item, double size) {
    final uri = item.artUri;
    Widget image = Icon(Icons.album, size: size, color: Colors.grey);
    if (uri != null) {
      image =
          uri.scheme == 'file'
              ? Image.file(
                File(uri.path),
                height: size,
                width: size,
                fit: BoxFit.cover,
              )
              : CachedNetworkImage(
                imageUrl: uri.toString(),
                height: size,
                width: size,
                fit: BoxFit.cover,
              );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.colorScheme.onSurface.withOpacity(.4);
    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem.stream,
      builder: (_, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () {
            _showFullPlayer.value = true;
            Get.to(() => FullScreenPlayer());
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: theme.brightness ==
                  Brightness.dark ? const Color.fromARGB(255, 18, 18, 18).withValues(alpha: 0.92) : theme.cardColor.withOpacity(.9),
              boxShadow: [
                BoxShadow(
                  color: inactive.withOpacity(.2),
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
                    _art(item, 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            item.artist ?? 'Unknown',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: inactive, fontSize: 12),
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
                        final state =
                            snapshot.data ?? AudioProcessingState.idle;
                        return Icon(
                          AppUtils.getProcessingIcon(state),
                          size: 20,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                StreamBuilder<MediaState>(
                  stream: _mediaStateStream,
                  builder: (_, ss) {
                    final pos = ss.data?.position ?? Duration.zero;
                    final dur = ss.data?.mediaItem?.duration ?? Duration.zero;
                    return Row(
                      children: [
                        Text(
                          AppUtils.formatDuration(pos),
                          style: TextStyle(color: inactive, fontSize: 10),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SeekBar(
                            duration: dur,
                            position: pos,
                            activeColor: theme.colorScheme.primary,
                            inactiveColor: inactive.withOpacity(.3),
                            onChangeEnd: _audioHandler.seek,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppUtils.formatDuration(dur),
                          style: TextStyle(color: inactive, fontSize: 10),
                        ),
                      ],
                    );
                  },
                ),
                _Controls(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Screen for artist details
class ArtistDetailScreen extends StatefulWidget {
  final String artist;
  final List<SongInfo> songs;

  const ArtistDetailScreen({
    super.key,
    required this.artist,
    required this.songs,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  String? _currentId;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;

  @override
  void initState() {
    super.initState();
    _mediaItemSubscription = _audioHandler.mediaItem.stream.listen((item) {
      setState(() => _currentId = item?.id);
    });
  }

  @override
  void dispose() {
    _mediaItemSubscription?.cancel();
    super.dispose();
  }

  bool _isCurrent(String id) => id == _currentId;

  void _playSongs(int index, {bool shuffle = false}) {
    final handler = _audioHandler as CustomAudioHandler;
    if (shuffle) {
      handler.toggleShuffle();
    }
    handler.playLocalPlaylist(widget.songs, index);
  }

  @override
  Widget build(BuildContext context) {
    final artUri = AppUtils.getArtistArt(widget.songs);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.artist),
              background:
                  artUri != null
                      ? Image.file(File(artUri.path), fit: BoxFit.cover)
                      : const Center(child: Icon(Icons.person, size: 100)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.songs.length} songs',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
              final song = widget.songs[index];
              final songId = Uri.file(song.file.path).toString();
              return SongTile(
                song: song,
                isCurrent: _isCurrent(songId),
                onTap: () => _playSongs(index),
              );
            }, childCount: widget.songs.length),
          ),
        ],
      ),
    );
  }
}

/// Screen for album details
class AlbumDetailScreen extends StatefulWidget {
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

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  String? _currentId;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;

  @override
  void initState() {
    super.initState();
    _mediaItemSubscription = _audioHandler.mediaItem.stream.listen((item) {
      setState(() => _currentId = item?.id);
    });
  }

  @override
  void dispose() {
    _mediaItemSubscription?.cancel();
    super.dispose();
  }

  bool _isCurrent(String id) => id == _currentId;

  void _playSongs(int index, {bool shuffle = false}) {
    final handler = _audioHandler as CustomAudioHandler;
    if (shuffle) {
      handler.toggleShuffle();
    }
    handler.playLocalPlaylist(widget.songs, index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.album),
              background:
                  widget.artUri != null
                      ? Image.file(File(widget.artUri!.path), fit: BoxFit.cover)
                      : const Center(child: Icon(Icons.album, size: 100)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.artist,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.songs.length} songs',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
              final song = widget.songs[index];
              final songId = Uri.file(song.file.path).toString();
              return SongTile(
                song: song,
                isCurrent: _isCurrent(songId),
                onTap: () => _playSongs(index),
                trackNumber: index + 1,
                showDuration: true,
              );
            }, childCount: widget.songs.length),
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
  State<SeekBar>  createState() => _SeekBarState();
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
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4.0, // 🔹 Increase slider height
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 6, // 🔹 Reduce thumb size
        ),
        overlayShape: const RoundSliderOverlayShape(
          overlayRadius: 14.0, // 🔹 Reduce the ripple when dragging
        ),
      ),
      child: Slider(
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
      ),
    );
  }
}

class GlobalWrapper extends StatefulWidget {
  final Widget child;
  const GlobalWrapper({super.key, required this.child});
  @override
  State<GlobalWrapper> createState() => _GlobalWrapperState();
}

class _GlobalWrapperState extends State<GlobalWrapper> {
  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          widget.child,
          ValueListenableBuilder<bool>(
            valueListenable: _showFullPlayer,
            builder:
                (_, open, __) => AnimatedSwitcher(
                  duration: 300.milliseconds,
                  child:
                      !open
                          ? SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: MiniPlayer(),
                            ),
                          )
                          : const SizedBox.shrink(),
                ),
          ),
        ],
      ),
    );
  }
}


class FullScreenPlayer extends StatelessWidget {
  const FullScreenPlayer({super.key});

  void _onBack() {
    Get.back();
    _showFullPlayer.value = false; // reactive close flag
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _onBack(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder<MediaItem?>(
          stream: _audioHandler.mediaItem.stream,
          builder: (_, snap) {
            final item = snap.data;
            if (item == null) return const SizedBox.shrink();

            return Stack(
              fit: StackFit.expand,
              children: [
                
                /// 🪞 BLURRED BACKGROUND IMAGE
                if (item.artUri != null)
                ValueListenableBuilder<bool>(
                    valueListenable: _showBlurImagePlayerBg,
                    builder:
                        (_, value, __) => AnimatedSwitcher(
                          duration: 300.milliseconds,
                          child:
                              value
                                  ? ImageFiltered(
                                    imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                                    child: Image.file(
                                      height: double.infinity,
                                      width: double.infinity,
                                      File(item.artUri!.toFilePath()),
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                  : const SizedBox.shrink(),
                        ),
                  ),
                Container(
                  color: Theme.of(context)
                      .scaffoldBackgroundColor
                      .withOpacity(0.4), // subtle overlay
                ),

                /// 🎧 PLAYER BODY
                SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// Top Controls
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 35,
                              ),
                              onPressed: _onBack,
                            ),
                            IconButton(
                              icon: const Icon(Icons.timer_outlined, size: 28),
                              onPressed: () {
                                // TODO: open your sleep timer dialog
                                Get.snackbar(
                                  'Sleep Timer',
                                  'Open sleep timer settings here.',
                                  snackPosition: SnackPosition.BOTTOM,
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      /// Player content
                      const Expanded(child: _PlayerBody()),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerBody extends StatelessWidget {
  const _PlayerBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.colorScheme.onSurface.withOpacity(.4);

    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem.stream,
      builder: (_, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              /// 🎶 ALBUM ART WITH SHRINK ANIMATION
              StreamBuilder<PlaybackState>(
                stream: _audioHandler.playbackState,
                builder: (_, stateSnap) {
                  final playing = stateSnap.data?.playing ?? false;

                  return AnimatedScale(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    scale: playing ? 1.0 : 0.7, // shrink slightly when paused
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 400),
                      opacity: playing ? 1 : 0.9,
                      child: Container(
                        width: MediaQuery.sizeOf(context).width * .75,
                        height: MediaQuery.sizeOf(context).width * .75,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 30,
                              spreadRadius: 4,
                              color:
                                  Theme.of(context).shadowColor.withOpacity(.3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: MiniPlayer()._art(item, double.infinity),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const Spacer(),

              /// Title & Artist
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.artist ?? 'Unknown',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: inactive),
              ),

              const Spacer(),

              /// Seekbar
              StreamBuilder<MediaState>(
                stream: rx.Rx.combineLatest2<MediaItem?, Duration, MediaState>(
                  _audioHandler.mediaItem.stream,
                  AudioService.position,
                  (a, b) => MediaState(a, b),
                ),
                builder: (_, ss) {
                  final pos = ss.data?.position ?? Duration.zero;
                  final dur = ss.data?.mediaItem?.duration ?? Duration.zero;
                  return Column(
                    children: [
                      SeekBar(
                        duration: dur,
                        position: pos,
                        activeColor: theme.colorScheme.primary,
                        inactiveColor: inactive.withOpacity(.3),
                        onChangeEnd: _audioHandler.seek,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppUtils.formatDuration(pos),
                              style: TextStyle(color: inactive, fontSize: 12),
                            ),
                            Text(
                              AppUtils.formatDuration(dur),
                              style: TextStyle(color: inactive, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              const Spacer(),

              /// Controls
              _Controls(),

              const Spacer(flex: 2),
            ],
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.colorScheme.onSurface.withOpacity(.4);
    final primary = theme.colorScheme.primary;
    return StreamBuilder<PlaybackState>(
      stream: _audioHandler.playbackState,
      builder: (_, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final queueIndex = state?.queueIndex ?? 0;
        final queueLen = _audioHandler.queue.value.length;
        final repeat = repeatModeNotifier.value;
        final shuffle = shuffleNotifier.value;
        final hasPrev = repeat != AudioServiceRepeatMode.one && queueIndex > 0;
        final hasNext =
            repeat != AudioServiceRepeatMode.one && queueIndex < queueLen - 1;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          // mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.shuffle,
                color: shuffle ? primary : inactive,
              ),
              onPressed: () => _toggleShuffle(),
            ),
            IconButton(
              icon: Icon(
                Icons.skip_previous,
                color: hasPrev ? primary : inactive,
              ),
              onPressed: hasPrev ? _audioHandler.skipToPrevious : null,
            ),
            IconButton(
              icon: Icon(
                playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: primary,
              ),
              onPressed: playing ? _audioHandler.pause : _audioHandler.play,
            ),
            IconButton(
              icon: Icon(Icons.skip_next, color: hasNext ? primary : inactive),
              onPressed: hasNext ? _audioHandler.skipToNext : null,
            ),
            IconButton(
              icon: Icon(
                repeat == AudioServiceRepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
                color:
                    repeat != AudioServiceRepeatMode.none ? primary : inactive,
              ),
              onPressed: () => _cycleRepeat(),
            ),
          ],
        );
      },
    );
  }

  void _toggleShuffle() {
    final old = shuffleNotifier.value;
    shuffleNotifier.value = !old;
    (_audioHandler as CustomAudioHandler).toggleShuffle().catchError(
      (_) => shuffleNotifier.value = old,
    );
  }

  void _cycleRepeat() {
    final old = repeatModeNotifier.value;
    final next = switch (old) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    };
    repeatModeNotifier.value = next;
    (_audioHandler as CustomAudioHandler)
        .setRepeatMode(next)
        .catchError((_) => repeatModeNotifier.value = old);
  }
}

