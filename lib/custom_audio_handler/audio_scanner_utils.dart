import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/custom_audio_handler/custom_audio_handler_with_metadata.dart';

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

  Future<List<SongInfo>> scanDirectory(String path) async {
    _scannedFiles = 0;
    final dir = Directory(path);
    final files = await _scanDirectoryForMusic(dir);
    final found = <SongInfo>[];
    for (final file in files) {
      final meta = await AudioMetadata.fromFile(file);
      if (meta != null) found.add(SongInfo(file: file, meta: meta));
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
