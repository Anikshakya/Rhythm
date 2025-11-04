import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/audio_meta_data/audio_meta_data.dart';

late AudioHandler audioHandler;

/// A simple data class for your songs
class SongInfo {
  final File file;
  final AudioMetadata meta;
  SongInfo({required this.file, required this.meta});
}

/// The AudioHandler handling background playback / notification controls
class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  List<MediaItem> _queue = [];
  int _currentIndex = 0;

  MyAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.durationStream.listen((duration) {
      if (duration != null &&
          _queue.isNotEmpty &&
          _currentIndex < _queue.length) {
        final item = _queue[_currentIndex];
        // Only update if duration is null or has changed
        if (item.duration == null || item.duration != duration) {
          final newItem = item.copyWith(duration: duration);
          _queue[_currentIndex] = newItem;
          mediaItem.add(newItem);
          // We don't need playMediaItem or updateQueue here,
          // as mediaItem.add handles broadcasting the updated item.
        }
      }
    });
  }

  Future<void> _loadQueue(List<SongInfo> songs, {int startIndex = 0}) async {
    _queue = await Future.wait(
      songs.map((song) async {
        // Await the file path URI for the album art
        final artUri = await _writeAlbumArtToFile(song.meta.albumArt);

        return MediaItem(
          id: song.file.path,
          album: song.meta.album ?? '',
          title: song.meta.title ?? song.file.path.split('/').last,
          artist: song.meta.artist ?? '',
          duration: null,
          artUri: artUri, // Use the file URI here
        );
      }),
    );

    audioHandler.updateQueue(_queue);
    _currentIndex = startIndex;

    await _player.setAudioSources(
      _queue
          .map((item) => AudioSource.uri(Uri.file(item.id), tag: item))
          .toList(),
      initialIndex: startIndex,
    );

    mediaItem.add(_queue[startIndex]);
  }

  // 1. Helper function to write bytes to a temp file
  Future<Uri?> _writeAlbumArtToFile(Uint8List? albumArtBytes) async {
    if (albumArtBytes == null) return null;

    try {
      // Get the directory where temporary files can be stored
      final tempDir = await getTemporaryDirectory();

      // Create a unique file name
      final fileName = 'album_art_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final file = File('${tempDir.path}/$fileName');

      // Write the bytes to the file
      await file.writeAsBytes(albumArtBytes);

      // Return the file URI (Uri.file) which the notification can handle
      return Uri.file(file.path);
    } catch (e) {
      print('Error writing album art to file: $e');
      return null;
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;

    // --- START: Seek Action Addition ---
    final controls = [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    final systemActions = const {
      MediaAction.seek, // <--- **ADDED SEEK ACTION HERE**
      MediaAction.seekForward,
      MediaAction.seekBackward,
    };
    // --- END: Seek Action Addition ---

    final mediaItem_ =
        (_queue.isNotEmpty && _currentIndex < _queue.length)
            ? _queue[_currentIndex]
            : null;

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: systemActions, // Use the systemActions set
        androidCompactActionIndices: const [0, 1, 2],
        processingState:
            {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
      ),
    );

    if (mediaItem_ != null) {
      mediaItem.add(mediaItem_);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  // The seek handler method is already implemented and correct!
  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      await _player.seek(Duration.zero, index: _currentIndex);
      mediaItem.add(_queue[_currentIndex]);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentIndex - 1 >= 0) {
      _currentIndex--;
      await _player.seek(Duration.zero, index: _currentIndex);
      mediaItem.add(_queue[_currentIndex]);
    }
  }

  /// A helper method your UI can call to load songs and start at index
  Future<void> loadSongs(List<SongInfo> songs, {int startIndex = 0}) =>
      _loadQueue(songs, startIndex: startIndex);
}

/// ==================== MAIN APP ====================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.musicplayer.channel.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: true,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = true;

  void toggleTheme() {
    setState(() => isDarkMode = !isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: MusicPlayerScreen(onToggleTheme: toggleTheme),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// ==================== MUSIC PLAYER SCREEN ====================
class MusicPlayerScreen extends StatefulWidget {
  final VoidCallback? onToggleTheme;
  const MusicPlayerScreen({super.key, this.onToggleTheme});

  @override
  State<MusicPlayerScreen> createState() => MusicPlayerScreenState();
}

class MusicPlayerScreenState extends State<MusicPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final AudioHandler _audioHandler;
  bool isDarkMode = true;

  List<SongInfo> _musicFiles = [];
  int? _currentPlayingIndex;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isScanning = false;
  int _scannedFiles = 0;
  bool _isLoading = false;
  late TabController _tabController;

  final List<String> _supportedFormats = [
    'mp3',
    'wav',
    'flac',
    'm4a',
    'mp4',
    'aac',
    'ogg',
    'wma',
    'amr',
    'aiff',
    'opus',
  ];

  @override
  void initState() {
    super.initState();
    _audioHandler = audioHandler;
    _tabController = TabController(length: 3, vsync: this);
    _initializeApp();
    _startSafeAutoScan();
    _listenToPlaybackState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Initialize permissions
  Future<void> _initializeApp() async {
    await _requestPermission();
  }

  /// Setup listener for background handler
  void _listenToPlaybackState() {
    _audioHandler.playbackState.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });
    _audioHandler.mediaItem.listen((item) {
      if (item != null) {
        setState(() {
          _duration = item.duration ?? Duration.zero;
          _currentPlayingIndex = _musicFiles.indexWhere(
            (song) => song.file.path == item.id,
          );
        });
      }
    });
    AudioService.position.listen((pos) {
      setState(() {
        _position = pos;
      });
    });
  }

  /// Request storage permissions
  Future<bool> _requestPermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) status = await Permission.storage.request();

    if (Platform.isAndroid) {
      final manage = await Permission.manageExternalStorage.status;
      if (!manage.isGranted) await Permission.manageExternalStorage.request();
    }

    return status.isGranted;
  }

  /// Check if file is supported music
  bool _isMusicFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return _supportedFormats.contains(ext);
  }

  /// Remove duplicate files by path
  List<SongInfo> _removeDuplicates(List<SongInfo> files) {
    final seen = <String>{};
    return files.where((f) => seen.add(f.file.path)).toList();
  }

  /// Extract filename
  String _getFileName(String path) => path.split('/').last;

  // ==================== SCAN MUSIC ====================
  Future<void> _startSafeAutoScan() async {
    setState(() {
      _isScanning = true;
      _scannedFiles = 0;
    });

    try {
      final found = <SongInfo>[];
      final dirs = await _getAccessibleDirectories();

      for (final dir in dirs) {
        final files = await _scanDirectoryForMusic(dir);
        for (final file in files) {
          final meta = await AudioMetadata.fromFile(file);
          if (meta != null) found.add(SongInfo(file: file, meta: meta));
        }
      }

      final unique = _removeDuplicates(found)
        ..sort((a, b) => a.file.path.compareTo(b.file.path));

      setState(() {
        _musicFiles = unique;
        _isScanning = false;
      });

      _showMessage('Found ${unique.length} songs');
    } catch (e) {
      setState(() => _isScanning = false);
      _showError('Scan failed: $e');
    }
  }

  Future<List<Directory>> _getAccessibleDirectories() async {
    List<Directory> dirs = [];

    Directory? extDir = Directory('/storage/emulated/0');
    if (await extDir.exists()) dirs.add(extDir);

    List<String> commonPaths = [
      'Music',
      'Download',
      'Downloads',
      'Audio',
      'Media',
    ];
    for (var path in commonPaths) {
      Directory subDir = Directory('${extDir.path}/$path');
      if (await subDir.exists()) dirs.add(subDir);
    }

    List<Directory> accessibleDirs = [];
    for (var dir in dirs) {
      try {
        await dir.list().take(1).toList();
        accessibleDirs.add(dir);
      } catch (_) {}
    }

    return accessibleDirs;
  }

  Future<List<File>> _scanDirectoryForMusic(Directory dir) async {
    final music = <File>[];
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && _isMusicFile(entity.path)) {
          music.add(entity);
          setState(() => _scannedFiles++);
        }
        if (_scannedFiles > 15000) break;
      }
    } catch (e) {
      print('Scan error in ${dir.path}: $e');
    }
    return music;
  }

  // ==================== MANUAL FILE PICKER ====================
  Future<void> _pickMusicFilesManually() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result?.files.isNotEmpty ?? false) {
        final newSongs = <SongInfo>[];
        for (final platformFile in result!.files) {
          if (platformFile.path != null) {
            final file = File(platformFile.path!);
            final meta = await AudioMetadata.fromFile(file);
            if (meta != null) {
              newSongs.add(SongInfo(file: file, meta: meta));
            }
          }
        }
        setState(() {
          _musicFiles.addAll(newSongs);
          _musicFiles = _removeDuplicates(_musicFiles);
        });
        _showMessage('Added ${newSongs.length} songs');
      }
    } catch (e) {
      _showError('Pick failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ==================== PLAYBACK CONTROLS ====================
  Future<void> _playMusic(int index) async {
    final handler = _audioHandler as MyAudioHandler;

    if (_currentPlayingIndex == index) {
      if (_isPlaying) {
        await _audioHandler.pause();
      } else {
        await _audioHandler.play();
      }
      return;
    }

    _currentPlayingIndex = index;

    // Load queue & start from this index
    await handler.loadSongs(_musicFiles, startIndex: index);

    // Explicitly update the notification with the current MediaItem
    if (handler._queue.isNotEmpty) {
      final item = handler._queue[handler._currentIndex];
      handler.mediaItem.add(item);
    }

    // Just start playback
    await _audioHandler.play();

    setState(() {}); // Optional: UI may already update from mediaItem stream
  }

  Future<void> _playNext() async {
    await _audioHandler.skipToNext();
    if (_currentPlayingIndex != null &&
        _currentPlayingIndex! < _musicFiles.length - 1) {
      _currentPlayingIndex = _currentPlayingIndex! + 1;
    }
    setState(() {});
  }

  Future<void> _playPrevious() async {
    await _audioHandler.skipToPrevious();
    if (_currentPlayingIndex != null && _currentPlayingIndex! > 0) {
      _currentPlayingIndex = _currentPlayingIndex! - 1;
    }
    setState(() {});
  }

  Future<void> _stopMusic() async {
    await _audioHandler.stop();
    setState(() {
      _isPlaying = false;
      _position = Duration.zero;
    });
  }

  void _seekTo(double ms) {
    _audioHandler.seek(Duration(milliseconds: ms.toInt()));
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showError(String msg) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  void _showMessage(String msg) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));

  // ==================== GROUPING HELPERS ====================
  Map<String, List<SongInfo>> _groupByAlbum() {
    final map = <String, List<SongInfo>>{};
    for (final song in _musicFiles) {
      final key =
          song.meta.album?.trim().isNotEmpty == true
              ? song.meta.album!
              : 'Unknown Album';
      map.putIfAbsent(key, () => []).add(song);
    }
    return map;
  }

  Map<String, List<SongInfo>> _groupByArtist() {
    final map = <String, List<SongInfo>>{};
    for (final song in _musicFiles) {
      final key =
          song.meta.artist?.trim().isNotEmpty == true
              ? song.meta.artist!
              : 'Unknown Artist';
      map.putIfAbsent(key, () => []).add(song);
    }
    return map;
  }

  Uint8List? _getGroupCoverArt(List<SongInfo> songs) {
    for (final song in songs) {
      if (song.meta.albumArt != null) return song.meta.albumArt;
    }
    return null;
  }

  // ==================== UI BUILD ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Player'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Songs'),
            Tab(text: 'Albums'),
            Tab(text: 'Artists'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _startSafeAutoScan,
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_currentPlayingIndex != null) _buildNowPlayingBar(),
          if (_isScanning) _buildScanProgress(),
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSongsTab(),
                _buildAlbumsTab(),
                _buildArtistsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add',
        onPressed: _pickMusicFilesManually,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildScanProgress() {
    return LinearProgressIndicator(
      value: _scannedFiles / 10000,
      backgroundColor: Colors.grey.shade300,
    );
  }

  Widget _buildSongsTab() {
    if (_musicFiles.isEmpty) return const Center(child: Text('No songs found'));
    return ListView.builder(
      itemCount: _musicFiles.length,
      itemBuilder: (_, i) {
        final song = _musicFiles[i];
        final isPlaying = _currentPlayingIndex == i && _isPlaying;
        return ListTile(
          leading:
              isPlaying
                  ? const Icon(Icons.equalizer, color: Colors.blue)
                  : (song.meta.albumArt != null
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          song.meta.albumArt!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                      : const Icon(Icons.music_note)),
          title: Text(song.meta.title ?? _getFileName(song.file.path)),
          subtitle: Text(song.meta.artist ?? 'Unknown Artist'),
          onTap: () => _playMusic(i),
        );
      },
    );
  }

  Widget _buildAlbumsTab() {
    final grouped = _groupByAlbum();
    if (grouped.isEmpty) return const Center(child: Text('No albums'));
    final entries =
        grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final entry = entries[i];
        final cover = _getGroupCoverArt(entry.value);
        return ExpansionTile(
          leading:
              cover != null
                  ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      cover,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  )
                  : const Icon(Icons.album, size: 50),
          title: Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          children:
              entry.value.map((song) {
                final idx = _musicFiles.indexOf(song);
                return ListTile(
                  leading:
                      _currentPlayingIndex == idx && _isPlaying
                          ? const Icon(Icons.play_arrow)
                          : const Icon(Icons.music_note),
                  title: Text(song.meta.title ?? _getFileName(song.file.path)),
                  onTap: () => _playMusic(idx),
                );
              }).toList(),
        );
      },
    );
  }

  Widget _buildArtistsTab() {
    final grouped = _groupByArtist();
    if (grouped.isEmpty) return const Center(child: Text('No artists'));
    final entries =
        grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final entry = entries[i];
        final cover = _getGroupCoverArt(entry.value);
        return ExpansionTile(
          leading:
              cover != null
                  ? ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Image.memory(
                      cover,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  )
                  : const CircleAvatar(child: Icon(Icons.person)),
          title: Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          children:
              entry.value.map((song) {
                final idx = _musicFiles.indexOf(song);
                return ListTile(
                  leading:
                      _currentPlayingIndex == idx && _isPlaying
                          ? const Icon(Icons.play_arrow)
                          : const Icon(Icons.music_note),
                  title: Text(song.meta.title ?? _getFileName(song.file.path)),
                  subtitle: Text(song.meta.album ?? ''),
                  onTap: () => _playMusic(idx),
                );
              }).toList(),
        );
      },
    );
  }

  Widget _buildNowPlayingBar() {
    final song = _musicFiles[_currentPlayingIndex!];
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).appBarTheme.backgroundColor,
      child: Column(
        children: [
          Row(
            children: [
              if (song.meta.albumArt != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    song.meta.albumArt!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                )
              else
                const Icon(Icons.music_note, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.meta.title ?? _getFileName(song.file.path),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(song.meta.artist ?? 'Unknown'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(_formatDuration(_position)),
              Expanded(
                child: Slider(
                  value: _position.inMilliseconds.toDouble().clamp(
                    0,
                    _duration.inMilliseconds.toDouble(),
                  ),
                  min: 0,
                  max: _duration.inMilliseconds.toDouble(),
                  onChanged: _seekTo,
                ),
              ),
              Text(_formatDuration(_duration)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: _playPrevious,
              ),
              IconButton(
                iconSize: 48,
                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                onPressed: () {
                  if (_currentPlayingIndex != null) {
                    _playMusic(_currentPlayingIndex!);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: _playNext,
              ),
              IconButton(icon: const Icon(Icons.stop), onPressed: _stopMusic),
            ],
          ),
        ],
      ),
    );
  }
}
