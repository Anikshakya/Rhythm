import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// ------------------- NATIVE FUNCTION TYPEDEF (Optional for future FFI) -------------------
// typedef ReadFlacMetadataNative = Pointer<Utf8> Function(Pointer<Utf8> filePath);
// typedef ReadFlacMetadataDart = Pointer<Utf8> Function(Pointer<Utf8> filePath);

void main() {
  runApp(const MyApp());
}

/// ==================== AUDIO METADATA EXTRACTOR ====================
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

  /// Extract metadata from file based on extension
  static Future<AudioMetadata?> fromFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();

      switch (ext) {
        case 'mp3':
          return _readMp3(bytes, file);
        case 'wav':
          return _readWav(file);
        case 'flac':
          return await _readFlac(file);
        case 'm4a':
        case 'mp4':
        case 'aac':
          return _readM4a(bytes, file);
        default:
          return AudioMetadata(title: file.path.split('/').last);
      }
    } catch (e) {
      print('Metadata extraction failed: $e');
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
    meta.title ??= file.path.split('/').last;
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

    meta.title ??= file.path.split('/').last;
    return meta;
  }

  static String _readAtomString(Uint8List data) {
    if (data.length <= 8) return '';
    return utf8.decode(data.sublist(8)).trim();
  }
}

/// ==================== SONG INFO HOLDER ====================
class SongInfo {
  final File file;
  final AudioMetadata meta;
  SongInfo({required this.file, required this.meta});
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
      _isPlaying ? await _audioPlayer.pause() : await _audioPlayer.resume();
      setState(() => _isPlaying = !_isPlaying);
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
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'scan',
            onPressed: _startSafeAutoScan,
            child: const Icon(Icons.search),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: _pickMusicFilesManually,
            child: const Icon(Icons.add),
          ),
        ],
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
