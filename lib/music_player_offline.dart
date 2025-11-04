import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/audio_meta_data/audio_meta_data.dart';

/// ------------------- NATIVE FUNCTION TYPEDEF (Optional for future FFI) -------------------
// typedef ReadFlacMetadataNative = Pointer<Utf8> Function(Pointer<Utf8> filePath);
// typedef ReadFlacMetadataDart = Pointer<Utf8> Function(Pointer<Utf8> filePath);

void main() {
  runApp(const MyApp());
}

/// ==================== MAIN APP ====================
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
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
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
    _tabController = TabController(length: 3, vsync: this);
    _initializeApp();
    _setupAudioPlayer();
    _startSafeAutoScan();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Initialize permissions
  Future<void> _initializeApp() async {
    await _requestPermission();
  }

  /// Setup audio player listeners
  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() => _isPlaying = state == PlayerState.playing);
    });

    _audioPlayer.onDurationChanged.listen((d) {
      setState(() => _duration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      setState(() => _position = p);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      _playNext();
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

    // Android external storage root
    Directory? extDir = Directory('/storage/emulated/0');
    if (await extDir.exists()) dirs.add(extDir);

    // Optional: add some known subfolders
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

    // Filter accessible dirs
    List<Directory> accessibleDirs = [];
    for (var dir in dirs) {
      try {
        await dir.list().take(1).toList(); // test access
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
            newSongs.add(SongInfo(file: file, meta: meta!));
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
    if (_currentPlayingIndex == index) {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() => _isPlaying = false);
      } else {
        await _audioPlayer.resume();
        setState(() => _isPlaying = true);
      }
      return;
    }

    try {
      // await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(_musicFiles[index].file.path));
      setState(() {
        _currentPlayingIndex = index;
        _isPlaying = true;
      });
    } catch (e) {
      _showError('Play failed: $e');
    }
  }

  Future<void> _playNext() async {
    if (_currentPlayingIndex != null &&
        _currentPlayingIndex! < _musicFiles.length - 1) {
      await _playMusic(_currentPlayingIndex! + 1);
    }
  }

  Future<void> _playPrevious() async {
    if (_currentPlayingIndex != null && _currentPlayingIndex! > 0) {
      await _playMusic(_currentPlayingIndex! - 1);
    }
  }

  Future<void> _stopMusic() async {
    await _audioPlayer.stop();
    setState(() {
      _isPlaying = false;
      _position = Duration.zero;
    });
  }

  void _seekTo(double ms) {
    _audioPlayer.seek(Duration(milliseconds: ms.toInt()));
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
            onPressed: () {
              _startSafeAutoScan();
            },
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      song.meta.artist ?? 'Unknown',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70),
              ),
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
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: _playPrevious,
                color: Colors.white,
              ),
              IconButton(
                iconSize: 48,
                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                onPressed: () => _playMusic(_currentPlayingIndex!),
                color: Colors.white,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: _playNext,
                color: Colors.white,
              ),
              IconButton(
                icon: const Icon(Icons.stop),
                onPressed: _stopMusic,
                color: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
