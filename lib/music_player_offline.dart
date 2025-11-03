import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

typedef ReadFlacMetadataNative = Pointer<Utf8> Function(Pointer<Utf8> filePath);
typedef ReadFlacMetadataDart = Pointer<Utf8> Function(Pointer<Utf8> filePath);

void main() {
  runApp(const MyApp());
}

/// -------------------- AUDIO METADATA CLASS --------------------
class AudioMetadata {
  String? title;
  String? artist;
  String? album;
  String? genre;
  int? durationMs;
  Uint8List? albumArt;

  AudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs,
    this.albumArt,
  });

  static Future<AudioMetadata?> fromFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();

      switch (ext) {
        case 'mp3':
          return _readMp3(bytes);
        case 'wav':
          return _readWav(bytes);
        case 'flac':
          return _readFlac(file);
        case 'mp4':
          return _readM4a(bytes);
        case 'm4a':
          return _readM4a(bytes);
        case 'aac':
          return _readM4a(bytes);
        default:
          return AudioMetadata(title: file.path.split('/').last);
      }
    } catch (_) {
      return AudioMetadata(title: file.path.split('/').last);
    }
  }

  /// -------------------- MP3 --------------------
  static AudioMetadata _readMp3(Uint8List bytes) {
    final meta = AudioMetadata();
    if (String.fromCharCodes(bytes.sublist(0, 3)) == 'ID3') {
      int size = _syncSafeToInt(bytes.sublist(6, 10));
      int pos = 10;

      while (pos + 10 < size) {
        final frameId = ascii.decode(bytes.sublist(pos, pos + 4));
        final frameSize = _bytesToInt(bytes.sublist(pos + 4, pos + 8));
        if (frameSize <= 0) break;
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
    if (meta.title == null) meta.title = 'MP3 Audio';
    return meta;
  }

  static int _syncSafeToInt(List<int> bytes) =>
      (bytes[0] << 21) | (bytes[1] << 14) | (bytes[2] << 7) | bytes[3];

  static int _bytesToInt(List<int> bytes) =>
      bytes.fold(0, (prev, b) => (prev << 8) + b);

  static String _decodeTextFrame(Uint8List frameData) {
    if (frameData.isEmpty) return '';
    switch (frameData[0]) {
      case 0:
        return ascii.decode(frameData.sublist(1)).trim();
      case 3:
        return utf8.decode(frameData.sublist(1)).trim();
      default:
        return '';
    }
  }

  static Uint8List? _decodeApic(Uint8List frameData) {
    int i = 1;
    while (i < frameData.length && frameData[i] != 0) i++;
    i++;
    i++;
    while (i < frameData.length && frameData[i] != 0) i++;
    i++;
    return frameData.sublist(i);
  }

  static int _estimateMp3Duration(Uint8List bytes) {
    final bitrate = 128 * 1024;
    final sizeBits = bytes.length * 8;
    return (sizeBits / bitrate * 1000).toInt();
  }

  /// -------------------- WAV --------------------
  static AudioMetadata _readWav(Uint8List bytes) {
    final meta = AudioMetadata();
    meta.title = 'WAV Audio';
    return meta;
  }

  /// -------------------- FLAC --------------------

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

      // Fallbacks
      meta.artist ??= 'Unknown Artist';
      meta.album ??= 'Unknown Album';
      meta.genre ??= 'Unknown Genre';
      meta.title ??= 'FLAC Audio';
    } catch (e) {
      print('❌ Error reading FLAC: $e');
    }

    return meta;
  }

  /// --- STREAMINFO (duration) ---
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

  /// --- VORBIS COMMENTS (title, artist, etc.) ---
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

  /// --- PICTURE BLOCK (album art) ---
  static Uint8List? _parsePicture(Uint8List data) {
    final reader = ByteData.sublistView(data);
    int offset = 0;

    try {
      final type = reader.getUint32(offset); // picture type
      offset += 4;

      // MIME type
      final mimeLength = reader.getUint32(offset);
      offset += 4;
      final mime = utf8.decode(data.sublist(offset, offset + mimeLength));
      offset += mimeLength;

      // Description
      final descLength = reader.getUint32(offset);
      offset += 4;
      offset += descLength;

      // Skip width, height, color depth, indexed colors
      offset += 16;

      // Image data length
      final imgDataLength = reader.getUint32(offset);
      offset += 4;

      // Image bytes
      final imgBytes = data.sublist(offset, offset + imgDataLength);

      print("✅ FLAC album art extracted (${mime}, ${imgBytes.length} bytes)");
      return Uint8List.fromList(imgBytes);
    } catch (e) {
      print('⚠️ Failed to parse FLAC picture: $e');
      return null;
    }
  }

  /// -------------------- M4A / AAC --------------------
  static AudioMetadata _readM4a(Uint8List bytes) {
    final meta = AudioMetadata();

    int pos = 0;
    while (pos + 8 < bytes.length) {
      final size = _bytesToInt(bytes.sublist(pos, pos + 4));
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));

      if (size < 8) break;

      // Only look into 'moov', 'udta', 'meta'
      if (type == 'moov' || type == 'udta' || type == 'meta') {
        int end = pos + size;
        pos += 8;
        while (pos + 8 < end) {
          final childSize = _bytesToInt(bytes.sublist(pos, pos + 4));
          final childType = String.fromCharCodes(
            bytes.sublist(pos + 4, pos + 8),
          );
          if (childSize < 8) break;

          // Important tags in 'ilst' box
          switch (childType) {
            case '©nam':
              meta.title = _readUtf8String(
                bytes.sublist(pos + 8, pos + childSize),
              );
              break;
            case '©ART':
              meta.artist = _readUtf8String(
                bytes.sublist(pos + 8, pos + childSize),
              );
              break;
            case '©alb':
              meta.album = _readUtf8String(
                bytes.sublist(pos + 8, pos + childSize),
              );
              break;
            case '©gen':
              meta.genre = _readUtf8String(
                bytes.sublist(pos + 8, pos + childSize),
              );
              break;
          }

          pos += childSize;
        }
      } else {
        pos += size;
      }
    }

    return meta;
  }

  static String _readUtf8String(Uint8List data) {
    // Skip the first 4–8 bytes which are flags/size in the atom
    int start = 0;
    if (data.length > 8) start = 8;
    return utf8.decode(data.sublist(start)).trim();
  }
}

/// -------------------- SONG INFO --------------------
class SongInfo {
  File file;
  AudioMetadata meta;
  SongInfo({required this.file, required this.meta});
}

/// -------------------- APP --------------------
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

/// -------------------- MUSIC PLAYER SCREEN --------------------
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

  TabController? _tabController;

  final List<String> _supportedFormats = [
    'mp3',
    'wav',
    'aac',
    'm4a',
    'mp4',
    'ogg',
    'flac',
    'wma',
    'amr',
    'aiff',
    'opus',
    '3gp',
  ];

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _tabController = TabController(length: 3, vsync: this);
    _setupAudioPlayer();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await _requestPermission();
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() => _isPlaying = state == PlayerState.playing);
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() => _duration = duration);
    });

    _audioPlayer.onPositionChanged.listen((position) {
      setState(() => _position = position);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _playNext();
      });
    });
  }

  Future<bool> _requestPermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) status = await Permission.storage.request();

    if (await Permission.audio.status.isDenied)
      await Permission.audio.request();

    var manageStorageStatus = await Permission.manageExternalStorage.status;
    if (!manageStorageStatus.isGranted) {
      await Permission.manageExternalStorage.request();
    }

    return status.isGranted;
  }

  bool _isMusicFile(String path) {
    try {
      String ext = path.toLowerCase().split('.').last;
      return _supportedFormats.contains(ext);
    } catch (e) {
      return false;
    }
  }

  List<SongInfo> _removeDuplicates(List<SongInfo> files) {
    Set<String> paths = {};
    List<SongInfo> uniqueFiles = [];
    for (var file in files) {
      if (!paths.contains(file.file.path)) {
        paths.add(file.file.path);
        uniqueFiles.add(file);
      }
    }
    return uniqueFiles;
  }

  String _getFileName(String path) => path.split('/').last;

  /// ------------------- SCAN FUNCTION -------------------
  Future<void> _startSafeAutoScan() async {
    setState(() {
      _isScanning = true;
      _scannedFiles = 0;
    });

    try {
      List<SongInfo> foundFiles = [];
      List<Directory> accessibleDirs = await _getAccessibleDirectories();

      for (var dir in accessibleDirs) {
        if (await dir.exists()) {
          List<File> files = await _scanDirectoryForMusic(dir);
          for (var f in files) {
            final meta = await AudioMetadata.fromFile(f);
            if (meta != null) foundFiles.add(SongInfo(file: f, meta: meta));
          }
        }
      }

      foundFiles = _removeDuplicates(foundFiles);
      foundFiles.sort(
        (a, b) =>
            a.file.path.toLowerCase().compareTo(b.file.path.toLowerCase()),
      );

      setState(() {
        _musicFiles = foundFiles;
        _isScanning = false;
      });

      if (_musicFiles.isNotEmpty)
        _showMessage('Found ${_musicFiles.length} music files');
      else
        _showMessage('No music files found');
    } catch (e) {
      setState(() => _isScanning = false);
      _showError('Error scanning: $e');
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
    List<File> musicFiles = [];
    try {
      await for (FileSystemEntity entity in dir.list(recursive: true)) {
        if (entity is File) {
          setState(() => _scannedFiles++);
          if (_isMusicFile(entity.path)) musicFiles.add(entity);
        }
        if (_scannedFiles > 10000) break;
      }
    } catch (e) {
      print('Error scanning ${dir.path}: $e');
    }
    return musicFiles;
  }

  /// ------------------- PICK FILES -------------------
  Future<void> _pickMusicFilesManually() async {
    setState(() => _isLoading = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        List<SongInfo> newFiles = [];
        for (var path in result.paths) {
          if (path != null) {
            final file = File(path);
            final meta = await AudioMetadata.fromFile(file);
            newFiles.add(SongInfo(file: file, meta: meta!));
          }
        }
        setState(() {
          _musicFiles.addAll(newFiles);
          _musicFiles = _removeDuplicates(_musicFiles);
          _currentPlayingIndex = null;
          _isPlaying = false;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
        _showMessage('Added ${newFiles.length} music files');
      }
    } catch (e) {
      _showError('Error picking files: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// ------------------- PLAY CONTROLS -------------------
  Future<void> _playMusic(int index) async {
    if (_currentPlayingIndex == index && _isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
      return;
    }

    if (_currentPlayingIndex == index && !_isPlaying) {
      await _audioPlayer.resume();
      setState(() => _isPlaying = true);
      return;
    }

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(_musicFiles[index].file.path));
      setState(() {
        _currentPlayingIndex = index;
        _isPlaying = true;
      });
    } catch (e) {
      _showError('Error playing music: $e');
    }
  }

  Future<void> _playNext() async {
    if (_currentPlayingIndex != null &&
        _currentPlayingIndex! < _musicFiles.length - 1) {
      _playMusic(_currentPlayingIndex! + 1);
    }
  }

  Future<void> _playPrevious() async {
    if (_currentPlayingIndex != null && _currentPlayingIndex! > 0) {
      _playMusic(_currentPlayingIndex! - 1);
    }
  }

  Future<void> _stopMusic() async {
    await _audioPlayer.stop();
    setState(() {
      _isPlaying = false;
      _position = Duration.zero;
    });
  }

  void _seekToPosition(double value) {
    final pos = Duration(milliseconds: value.toInt());
    _audioPlayer.seek(pos);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// ------------------- BUILD -------------------
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
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_currentPlayingIndex != null) _buildNowPlayingSection(),
          if (_isLoading || _isScanning) _buildProgressIndicator(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMusicList(_musicFiles),
                _buildGroupedList(_groupByAlbum()),
                _buildGroupedList(_groupByArtist()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'scan',
            child: const Icon(Icons.search),
            onPressed: _startSafeAutoScan,
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            heroTag: 'pick',
            child: const Icon(Icons.add),
            onPressed: _pickMusicFilesManually,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return LinearProgressIndicator(
      value: _scannedFiles / 10000,
      minHeight: 5,
      backgroundColor: Colors.grey.shade300,
      color: Colors.blue,
    );
  }

  Widget _buildMusicList(List<SongInfo> files) {
    if (files.isEmpty) return const Center(child: Text('No Music Files'));
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final song = files[index];
        return ListTile(
          leading:
              _currentPlayingIndex == index && _isPlaying
                  ? const Icon(Icons.equalizer)
                  : (song.meta.albumArt != null
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(
                          8,
                        ), // optional: rounded corners
                        child: Image.memory(
                          song.meta.albumArt!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                      : const Icon(Icons.music_note)),
          title: Text(song.meta.title ?? _getFileName(song.file.path)),
          subtitle: Text(song.meta.artist ?? ''),
          onTap: () => _playMusic(index),
        );
      },
    );
  }

  Map<String, List<SongInfo>> _groupByAlbum() {
    Map<String, List<SongInfo>> map = {};
    for (var song in _musicFiles) {
      String key = song.meta.album ?? 'Unknown Album';
      map.putIfAbsent(key, () => []).add(song);
    }
    return map;
  }

  Map<String, List<SongInfo>> _groupByArtist() {
    Map<String, List<SongInfo>> map = {};
    for (var song in _musicFiles) {
      String key = song.meta.artist ?? 'Unknown Artist';
      map.putIfAbsent(key, () => []).add(song);
    }
    return map;
  }

  Widget _buildGroupedList(Map<String, List<SongInfo>> groupedFiles) {
    if (groupedFiles.isEmpty)
      return const Center(child: Text('No Music Files'));
    return ListView(
      children:
          groupedFiles.entries.map((entry) {
            return ExpansionTile(
              title: Text(entry.key),
              children:
                  entry.value.map((song) {
                    final index = _musicFiles.indexOf(song);
                    return ListTile(
                      leading:
                          _currentPlayingIndex == index && _isPlaying
                              ? const Icon(Icons.equalizer)
                              : const Icon(Icons.music_note),
                      title: Text(
                        song.meta.title ?? _getFileName(song.file.path),
                      ),
                      subtitle: Text(song.meta.artist ?? ''),
                      onTap: () => _playMusic(index),
                    );
                  }).toList(),
            );
          }).toList(),
    );
  }

  Widget _buildNowPlayingSection() {
    if (_currentPlayingIndex == null) return const SizedBox.shrink();
    final song = _musicFiles[_currentPlayingIndex!];
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Text(
            song.meta.title ?? _getFileName(song.file.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
          Text(
            song.meta.artist ?? '',
            style: const TextStyle(color: Colors.white70),
          ),
          Row(
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70),
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: _duration.inMilliseconds.toDouble(),
                  value:
                      _position.inMilliseconds
                          .clamp(0, _duration.inMilliseconds)
                          .toDouble(),
                  onChanged: _seekToPosition,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white38,
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
                color: Colors.white,
                onPressed: _playPrevious,
              ),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                color: Colors.white,
                iconSize: 40,
                onPressed: () => _playMusic(_currentPlayingIndex!),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                color: Colors.white,
                onPressed: _playNext,
              ),
              IconButton(
                icon: const Icon(Icons.stop),
                color: Colors.white,
                onPressed: _stopMusic,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
