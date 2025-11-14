import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/src/audio_utils/audio_scanner_utils.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LibraryController extends GetxController {
  final LocalMusicScanner scanner = LocalMusicScanner();
  RxList<SongInfo> musicFiles = <SongInfo>[].obs;
  RxBool isScanning = false.obs;
  RxString? message = RxString("");

  // @override
  // void onInit() {
  //   super.onInit();
  //   scanner.requestPermission();
  // }

  Future<void> loadSavedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSongsJson = prefs.getString('saved_songs');
    if (savedSongsJson == null) {
      message!.value = 'No saved songs found. Scan to find songs.';
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
      musicFiles.value = loadedSongs;
      message!.value = 'Loaded ${loadedSongs.length} saved songs.';
    } catch (e) {
      message!.value = 'Failed to load saved songs.';
    }
  }

  Future<void> saveSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final musicLists = musicFiles.map((item) => item.toJson()).toList();
    await prefs.setString('saved_songs', json.encode(musicLists));
  }

  Future<void> startScan() async {
    isScanning.value = true;
    musicFiles.clear();
    message!.value = 'Requesting permissions...';
    // ignore: unused_local_variable
    final granted = await scanner.requestPermission();
    if (granted == false) {
      isScanning.value = false;
      message!.value = 'Storage permission denied. Cannot scan local files.';
      openAppSettings();
      return;
    }
    message!.value = 'Scanning directories...';
    try {
      final foundSongs = await scanner.startSafeAutoScan();
      musicFiles.value = foundSongs;
      message!.value = 'Found ${foundSongs.length} songs.';
      await saveSongs();
    } catch (e) {
      message!.value = 'Scan failed: $e';
    } finally {
      isScanning.value = false;
    }
  }

  Future<void> selectAndScanFolder() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null) return;
    isScanning.value = true;
    musicFiles.clear();
    message!.value = 'Requesting permissions...';
    final granted = await scanner.requestPermission();
    if (!granted) {
      isScanning.value = false;
      message!.value =
          'Storage permission denied. Cannot scan selected folder.';
      return;
    }
    message!.value = 'Scanning selected folder...';
    try {
      final foundSongs = await scanner.scanDirectory(directoryPath);
      musicFiles.value = foundSongs;
      message!.value = 'Found ${foundSongs.length} songs in selected folder.';
      await saveSongs();
    } catch (e) {
      message!.value = 'Scan failed: $e';
    } finally {
      isScanning.value = false;
    }
  }
}
