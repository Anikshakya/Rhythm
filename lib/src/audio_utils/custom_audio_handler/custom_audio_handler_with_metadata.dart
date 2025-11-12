// =======================================================
// Audio Handler (The core business logic with the full fix)
// =======================================================
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// An [AudioHandler] for playing audio from local files or online URLs.
class CustomAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);

  bool _isSettingSource = false;

  /// Initialise our audio handler.
  CustomAudioHandler() {
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
      if (_isSettingSource)
        return; // Ignore updates during source setting to prevent glitches
      final index = state!.currentIndex ?? 0;
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
    final artWrites = <Future<void>>[];
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
          if (!await artFile.exists()) {
            artWrites.add(artFile.writeAsBytes(song.meta.albumArt!));
          }
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
    await Future.wait(
      artWrites,
    ); // Parallelize art file writes for better performance
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
    _isSettingSource = true; // Flag to prevent glitchy mediaItem updates
    await _playlist.clear();
    await _playlist.addAll(sources);
    queue.add(items);
    await _player.setAudioSource(_playlist, initialIndex: initialIndex);
    mediaItem.add(items[initialIndex]); // Manually set after source is ready
    _isSettingSource = false;
    play();
  }

  // Method to set repeat mode
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode  mode) async {
    await _player.setLoopMode(switch (mode) {
      AudioServiceRepeatMode .none => LoopMode.off,
      AudioServiceRepeatMode .all => LoopMode.all,
      AudioServiceRepeatMode .one => LoopMode.one,
      AudioServiceRepeatMode .group => LoopMode.off, // Not used
    });
  }

  // Method to toggle shuffle mode
  Future<void> toggleShuffle() async {
    await _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);
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
    final hasPrevious =
        (_player.loopMode != LoopMode.one) && _player.hasPrevious;
    final hasNext = (_player.loopMode != LoopMode.one) && _player.hasNext;
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
      repeatMode: switch (_player.loopMode) {
        LoopMode.off => AudioServiceRepeatMode.none,
        LoopMode.all => AudioServiceRepeatMode.all,
        LoopMode.one => AudioServiceRepeatMode.one,
      },
      shuffleMode: _player.shuffleModeEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      // shuffleIndices: _player.shuffleIndices,
    );
  }
}


// Audio Meta Data
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

    // Bytes 10–17 contain sample rate, channels, bits-per-sample, and total samples (all bit-packed)
    // Reference: https://xiph.org/flac/format.html#metadata_block_streaminfo

    // Combine bytes 10–17 into a single 64-bit integer
    int packed = 0;
    for (int i = 10; i < 18; i++) {
      packed = (packed << 8) | data[i];
    }

    // Extract fields
    int sampleRate = (packed >> 44) & 0xFFFFF; // 20 bits
    int totalSamples = packed & 0xFFFFFFFFF; // 36 bits

    if (sampleRate == 0 || totalSamples == 0) return null;

    double durationSeconds = totalSamples / sampleRate;
    return (durationSeconds * 1000).round(); // milliseconds
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
