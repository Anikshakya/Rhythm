import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
