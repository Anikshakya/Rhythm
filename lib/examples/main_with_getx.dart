// import 'dart:async';
// import 'dart:io';
// import 'dart:ui';
// import 'package:audio_service/audio_service.dart';
// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/cupertino.dart';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:just_audio/just_audio.dart';
// import 'package:path/path.dart' as path;
// import 'package:path_provider/path_provider.dart';
// import 'package:rhythm/src/app_config/app_theme.dart'; // Assuming this is your theme file
// import 'package:rhythm/src/audio_utils/audio_scanner_utils.dart'; // Assuming this exists
// import 'package:rhythm/custom_audio_handler/custom_audio_handler_with_metadata.dart'; // Assuming this exists
// import 'package:rxdart/rxdart.dart' as rx;
// import 'package:shared_preferences/shared_preferences.dart';
// import 'dart:convert';

// // Global audio handler
// late AudioHandler _audioHandler;

// // Entry point
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   _audioHandler = await AudioService.init(
//     builder: () => CustomAudioHandler(),
//     config: const AudioServiceConfig(
//       androidNotificationChannelId: 'com.myaudio.channel',
//       androidNotificationChannelName: 'Audio playback',
//       androidNotificationOngoing: true,
//       androidStopForegroundOnPause: true,
//     ),
//   );

//   Get.put(AppController());
//   Get.put(PlayerController());
//   Get.put(LibraryController());
//   Get.put(SleepTimerController());
//   Get.put(SearchController());

//   final libCtrl = Get.find<LibraryController>();
//   final playerCtrl = Get.find<PlayerController>();
//   await libCtrl.loadSavedSongs();
//   await playerCtrl.loadLastState();

//   runApp(const MyApp());
// }

// // Controllers
// class AppController extends GetxController {
//   Rx<ThemeMode> themeMode = ThemeMode.system.obs;
//   RxBool isPlayerBgImage = false.obs;
//   RxBool showFullPlayer = false.obs;

//   @override
//   void onInit() {
//     super.onInit();
//     _loadAppConfig();
//   }

//   Future<void> _loadAppConfig() async {
//     final prefs = await SharedPreferences.getInstance();
//     final savedTheme = prefs.getString('app_theme');
//     final savedPlayerBgState = prefs.getBool('is_player_bg_image');
//     themeMode.value =
//         savedTheme == 'dark'
//             ? ThemeMode.dark
//             : savedTheme == 'light'
//             ? ThemeMode.light
//             : ThemeMode.system;
//     isPlayerBgImage.value = savedPlayerBgState ?? false;
//   }

//   Future<void> toggleTheme() async {
//     final prefs = await SharedPreferences.getInstance();
//     final newTheme =
//         themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
//     themeMode.value = newTheme;
//     await prefs.setString(
//       'app_theme',
//       newTheme == ThemeMode.dark ? 'dark' : 'light',
//     );
//   }

//   Future<void> tooglePlayerBackGround() async {
//     final prefs = await SharedPreferences.getInstance();
//     final newState = isPlayerBgImage.value == true ? false : true;
//     isPlayerBgImage.value = newState;
//     await prefs.setBool('is_player_bg_image', newState == true ? true : false);
//   }
// }

// class PlayerController extends GetxController {
//   Rx<AudioServiceRepeatMode> repeatMode = AudioServiceRepeatMode.none.obs;
//   RxBool shuffleMode = false.obs;
//   RxString? currentId = RxString("");

//   StreamSubscription<PlaybackState>? _playbackSubscription;
//   StreamSubscription<MediaItem?>? _mediaItemSubscription;
//   StreamSubscription<List<MediaItem>>? _queueSubscription;

//   @override
//   void onInit() {
//     super.onInit();
//     _playbackSubscription = _audioHandler.playbackState.stream.listen((state) {
//       repeatMode.value = state.repeatMode;
//       shuffleMode.value = state.shuffleMode == AudioServiceShuffleMode.all;
//     });
//     _mediaItemSubscription = _audioHandler.mediaItem.stream.listen((item) {
//       currentId!.value = item!.id;
//       _saveCurrentState();
//     });
//     _queueSubscription = _audioHandler.queue.stream.listen(
//       (_) => _saveCurrentState(),
//     );
//   }

//   @override
//   void onClose() {
//     _playbackSubscription?.cancel();
//     _mediaItemSubscription?.cancel();
//     _queueSubscription?.cancel();
//     super.onClose();
//   }

//   Future<void> toggleShuffle() async {
//     final old = shuffleMode.value;
//     shuffleMode.value = !old;
//     try {
//       await (_audioHandler as CustomAudioHandler).toggleShuffle();
//     } catch (e) {
//       shuffleMode.value = old;
//     }
//   }

//   Future<void> cycleRepeat() async {
//     final old = repeatMode.value;
//     final next = switch (old) {
//       AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
//       AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
//       _ => AudioServiceRepeatMode.none,
//     };
//     repeatMode.value = next;
//     try {
//       await (_audioHandler as CustomAudioHandler).setRepeatMode(next);
//     } catch (e) {
//       repeatMode.value = old;
//     }
//   }

//   Future<void> _saveCurrentState() async {
//     final prefs = await SharedPreferences.getInstance();
//     final currentQueue = _audioHandler.queue.value;
//     if (currentQueue.isEmpty) return;
//     final queueList =
//         currentQueue
//             .map(
//               (item) => {
//                 'id': item.id,
//                 'title': item.title,
//                 'artist': item.artist,
//                 'album': item.album,
//                 'duration': item.duration?.inMilliseconds,
//                 'artUri': item.artUri?.toString(),
//               },
//             )
//             .toList();
//     await prefs.setString('last_queue', json.encode(queueList));
//     await prefs.setInt(
//       'last_index',
//       _audioHandler.playbackState.value.queueIndex ?? 0,
//     );
//     await prefs.setInt('last_position', 0); // Reset position for next launch
//   }

//   Future<void> loadLastState() async {
//     final prefs = await SharedPreferences.getInstance();
//     final lastQueueJson = prefs.getString('last_queue');
//     if (lastQueueJson == null) return;
//     final lastQueueList = json.decode(lastQueueJson) as List<dynamic>;
//     final items = <MediaItem>[];
//     final sources = <AudioSource>[];
//     for (final map in lastQueueList) {
//       final id = map['id'] as String;
//       final item = MediaItem(
//         id: id,
//         title: map['title'] as String? ?? 'Unknown Title',
//         artist: map['artist'] as String?,
//         album: map['album'] as String?,
//         duration: Duration(milliseconds: map['duration'] as int? ?? 0),
//         artUri:
//             map['artUri'] != null ? Uri.parse(map['artUri'] as String) : null,
//       );
//       items.add(item);
//       sources.add(AudioSource.uri(Uri.parse(id), tag: item));
//     }
//     if (items.isNotEmpty) {
//       final lastIndex = prefs.getInt('last_index') ?? 0;
//       final lastPosition = Duration(
//         milliseconds: prefs.getInt('last_position') ?? 0,
//       );
//       await (_audioHandler as CustomAudioHandler).loadPlaylist(
//         items,
//         sources,
//         initialIndex: lastIndex,
//       );
//       await _audioHandler.pause();
//       await _audioHandler.seek(lastPosition);
//     }
//   }
// }

// class LibraryController extends GetxController {
//   final LocalMusicScanner scanner = LocalMusicScanner();
//   RxList<SongInfo> musicFiles = <SongInfo>[].obs;
//   RxBool isScanning = false.obs;
//   RxString? message = RxString("");

//   Future<void> loadSavedSongs() async {
//     final prefs = await SharedPreferences.getInstance();
//     final savedSongsJson = prefs.getString('saved_songs');
//     if (savedSongsJson == null) {
//       message!.value = 'No saved songs found. Scan to find songs.';
//       return;
//     }
//     try {
//       final savedList = json.decode(savedSongsJson) as List<dynamic>;
//       final loadedSongs = <SongInfo>[];
//       for (final map in savedList) {
//         final song = await SongInfo.fromJson(
//           Map<String, dynamic>.from(map as Map),
//         );
//         if (song != null) loadedSongs.add(song);
//       }
//       musicFiles.value = loadedSongs;
//       message!.value = 'Loaded ${loadedSongs.length} saved songs.';
//     } catch (e) {
//       message!.value = 'Failed to load saved songs.';
//     }
//   }

//   Future<void> saveSongs() async {
//     final prefs = await SharedPreferences.getInstance();
//     final musicLists = musicFiles.map((item) => item.toJson()).toList();
//     await prefs.setString('saved_songs', json.encode(musicLists));
//   }

//   Future<void> startScan() async {
//     isScanning.value = true;
//     musicFiles.clear();
//     message!.value = 'Requesting permissions...';
//     final granted = await scanner.requestPermission();
//     if (!granted) {
//       isScanning.value = false;
//       message!.value = 'Storage permission denied. Cannot scan local files.';
//       return;
//     }
//     message!.value = 'Scanning directories...';
//     try {
//       final foundSongs = await scanner.startSafeAutoScan();
//       musicFiles.value = foundSongs;
//       message!.value = 'Found ${foundSongs.length} songs.';
//       await saveSongs();
//     } catch (e) {
//       message!.value = 'Scan failed: $e';
//     } finally {
//       isScanning.value = false;
//     }
//   }

//   Future<void> selectAndScanFolder() async {
//     final directoryPath = await FilePicker.platform.getDirectoryPath();
//     if (directoryPath == null) return;
//     isScanning.value = true;
//     musicFiles.clear();
//     message!.value = 'Requesting permissions...';
//     final granted = await scanner.requestPermission();
//     if (!granted) {
//       isScanning.value = false;
//       message!.value =
//           'Storage permission denied. Cannot scan selected folder.';
//       return;
//     }
//     message!.value = 'Scanning selected folder...';
//     try {
//       final foundSongs = await scanner.scanDirectory(directoryPath);
//       musicFiles.value = foundSongs;
//       message!.value = 'Found ${foundSongs.length} songs in selected folder.';
//       await saveSongs();
//     } catch (e) {
//       message!.value = 'Scan failed: $e';
//     } finally {
//       isScanning.value = false;
//     }
//   }
// }

// class SleepTimerController extends GetxController {
//   Timer? _sleepTimer;
//   Timer? _updateTimer;
//   Rx<Duration> remaining = Rx(Duration.zero);
//   RxBool isActive = RxBool(false);

//   void setSleepTimer(Duration duration) {
//     _sleepTimer?.cancel();
//     _updateTimer?.cancel();

//     if (duration == Duration.zero) {
//       isActive.value = false;
//       remaining.value = Duration.zero;
//       return;
//     }

//     remaining.value = duration;
//     isActive.value = true;

//     _sleepTimer = Timer(duration, () {
//       isActive.value = false;
//       remaining.value = Duration.zero;
//     });

//     _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
//       remaining.value -= const Duration(seconds: 1);
//       if (remaining.value <= Duration.zero) {
//         timer.cancel();
//         remaining.value = Duration.zero;
//         (_audioHandler as CustomAudioHandler).stop();
//         Get.snackbar('Sleep Timer', 'Your Sleep Timer Has Ended');
//       }
//     });
//   }

//   @override
//   void onClose() {
//     _sleepTimer?.cancel();
//     _updateTimer?.cancel();
//     super.onClose();
//   }
// }

// class SearchController extends GetxController {
//   RxString searchQuery = ''.obs;
//   final TextEditingController searchTextController = TextEditingController();

//   @override
//   void onInit() {
//     super.onInit();
//     searchTextController.addListener(() {
//       searchQuery.value = searchTextController.text.toLowerCase();
//     });
//   }

//   @override
//   void onClose() {
//     searchTextController.dispose();
//     super.onClose();
//   }
// }

// // Utility class
// class AppUtils {
//   static String formatDuration(Duration duration) {
//     if (duration == Duration.zero) return '--:--';
//     final hours = duration.inHours;
//     final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
//     final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
//     return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
//   }

//   static Uri? getAlbumArt(List<SongInfo> songs) {
//     if (songs.isEmpty) return null;
//     final song = songs.first;
//     return song.meta.artUri ??
//         (song.meta.albumArt != null
//             ? Uri.file(
//               '${(getTemporaryDirectory())}/art_${song.file.path.hashCode}.jpg',
//             )
//             : null);
//   }

//   static Uri? getArtistArt(List<SongInfo> songs) {
//     return getAlbumArt(songs);
//   }

//   static IconData getProcessingIcon(AudioProcessingState state) {
//     return switch (state) {
//       AudioProcessingState.loading ||
//       AudioProcessingState.buffering => Icons.cached,
//       AudioProcessingState.ready => Icons.done,
//       AudioProcessingState.completed => Icons.repeat,
//       _ => Icons.error,
//     };
//   }
// }

// // Reusable SongTile (stateless)
// class SongTile extends StatelessWidget {
//   final SongInfo song;
//   final bool isCurrent;
//   final VoidCallback onTap;
//   final int? trackNumber;
//   final bool showDuration;

//   const SongTile({
//     super.key,
//     required this.song,
//     required this.isCurrent,
//     required this.onTap,
//     this.trackNumber,
//     this.showDuration = false,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final titleStyle = TextStyle(
//       fontWeight: FontWeight.w500,
//       color:
//           isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
//     );
//     final subtitleStyle = TextStyle(color: Colors.grey[600]);
//     final duration = Duration(milliseconds: song.meta.durationMs ?? 0);
//     final formattedDuration = AppUtils.formatDuration(duration);
//     Widget leading;
//     Widget? subtitleWidget;
//     Widget? trailing;
//     if (trackNumber != null) {
//       leading =
//           isCurrent
//               ? Icon(Icons.bar_chart_rounded)
//               : Text('$trackNumber', style: subtitleStyle);
//       subtitleWidget = null;
//       trailing = Text(formattedDuration, style: subtitleStyle);
//     } else {
//       leading = SizedBox(
//         width: 48,
//         height: 48,
//         child: ClipRRect(
//           borderRadius: BorderRadius.circular(4),
//           child: _buildArt(),
//         ),
//       );
//       subtitleWidget = Text(
//         song.meta.artist,
//         style: subtitleStyle,
//         maxLines: 1,
//         overflow: TextOverflow.ellipsis,
//       );
//       trailing =
//           isCurrent
//               ? Icon(Icons.bar_chart_rounded, color: theme.colorScheme.primary)
//               : null;
//     }
//     return ListTile(
//       contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
//       minVerticalPadding: 0,
//       leading: leading,
//       title: Text(
//         song.meta.title,
//         style: titleStyle,
//         maxLines: 1,
//         overflow: TextOverflow.ellipsis,
//       ),
//       subtitle: subtitleWidget,
//       trailing:
//           trailing ??
//           (showDuration ? Text(formattedDuration, style: subtitleStyle) : null),
//       onTap: onTap,
//       shape: const Border(bottom: BorderSide(color: Colors.grey, width: 0.1)),
//     );
//   }

//   Widget _buildArt() {
//     if (song.meta.artUri != null) {
//       return Image.file(
//         File(song.meta.artUri!.path),
//         fit: BoxFit.cover,
//         errorBuilder:
//             (context, error, stackTrace) =>
//                 const Icon(Icons.music_note_outlined),
//       );
//     } else if (song.meta.albumArt != null) {
//       return Image.memory(
//         song.meta.albumArt!,
//         fit: BoxFit.cover,
//         errorBuilder:
//             (context, error, stackTrace) =>
//                 const Icon(Icons.music_note_outlined),
//       );
//     } else {
//       return const Icon(Icons.music_note_outlined);
//     }
//   }
// }

// // Reusable OnlineTile (stateless)
// class OnlineTile extends StatelessWidget {
//   final MediaItem item;
//   final bool isCurrent;
//   final VoidCallback onTap;

//   const OnlineTile({
//     super.key,
//     required this.item,
//     required this.isCurrent,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final titleStyle = TextStyle(
//       fontWeight: FontWeight.w500,
//       color:
//           isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
//     );
//     final subtitleStyle = TextStyle(color: Colors.grey[600]);
//     Widget leading = SizedBox(
//       width: 48,
//       height: 48,
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(4),
//         child: _buildArt(),
//       ),
//     );
//     Widget? trailing =
//         isCurrent
//             ? Icon(Icons.bar_chart_rounded, color: theme.colorScheme.primary)
//             : null;
//     return ListTile(
//       contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
//       minVerticalPadding: 0,
//       leading: leading,
//       title: Text(
//         item.title,
//         style: titleStyle,
//         maxLines: 1,
//         overflow: TextOverflow.ellipsis,
//       ),
//       subtitle: Text(
//         item.artist ?? 'Unknown',
//         style: subtitleStyle,
//         maxLines: 1,
//         overflow: TextOverflow.ellipsis,
//       ),
//       trailing: trailing,
//       onTap: onTap,
//       shape: const Border(bottom: BorderSide(color: Colors.grey, width: 0.1)),
//     );
//   }

//   Widget _buildArt() {
//     if (item.artUri != null) {
//       final uri = item.artUri!;
//       if (uri.scheme == 'file') {
//         return Image.file(
//           File(uri.path),
//           fit: BoxFit.cover,
//           errorBuilder:
//               (context, error, stackTrace) =>
//                   const Icon(Icons.cloud_queue_outlined),
//         );
//       } else {
//         return CachedNetworkImage(
//           imageUrl: uri.toString(),
//           fit: BoxFit.cover,
//           errorWidget:
//               (context, url, error) => const Icon(Icons.cloud_queue_outlined),
//         );
//       }
//     } else {
//       return const Icon(Icons.cloud_queue_outlined);
//     }
//   }
// }

// // Static online items
// final List<MediaItem> onlineItems = [
//   MediaItem(
//     id: 'https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3',
//     album: "Science Friday",
//     title: "A Salute To Head-Scratching Science (Online)",
//     artist: "Science Friday and WNYC Studios",
//     duration: const Duration(milliseconds: 5739820),
//     artUri: Uri.parse(
//       'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
//     ),
//   ),
//   MediaItem(
//     id: 'https://freepd.com/music/A%20Good%20Bass%20for%20Gambling.mp3',
//     title: 'A Good Bass for Gambling',
//     artist: 'Kevin MacLeod',
//     album: 'FreePD',
//     duration: Duration.zero,
//   ),
//   MediaItem(
//     id: 'https://freepd.com/music/A%20Surprising%20Encounter.mp3',
//     title: 'A Surprising Encounter',
//     artist: 'Kevin MacLeod',
//     album: 'FreePD',
//     duration: Duration.zero,
//   ),
// ];

// // MainScreen (GetView)
// class MainScreen extends GetView<LibraryController> {
//   const MainScreen({super.key});

//   void _playLocalSongs(List<SongInfo> playlist, int index) {
//     (_audioHandler as CustomAudioHandler).playLocalPlaylist(playlist, index);
//   }

//   void _playOnlineSongs(List<MediaItem> items, int index) {
//     (_audioHandler as CustomAudioHandler).playOnlinePlaylist(items, index);
//   }

//   Widget _buildTabContent(int index) {
//     switch (index) {
//       case 0:
//         return _buildSongsTab();
//       case 1:
//         return _buildOnlineTab();
//       case 2:
//         return _buildArtistsTab();
//       case 3:
//         return _buildAlbumsTab();
//       case 4:
//         return _buildFoldersTab();
//       default:
//         return const SizedBox.shrink();
//     }
//   }

//   Widget _buildSongsTab() {
//     if (controller.musicFiles.isEmpty) {
//       return const Center(child: Text('No local songs found.'));
//     }
//     return ListView.builder(
//       itemCount: controller.musicFiles.length,
//       padding: const EdgeInsets.only(bottom: 210),
//       itemBuilder: (context, index) {
//         final song = controller.musicFiles[index];
//         final songId = Uri.file(song.file.path).toString();
//         return Obx(
//           () => SongTile(
//             song: song,
//             isCurrent: Get.find<PlayerController>().currentId!.value == songId,
//             onTap: () => _playLocalSongs(controller.musicFiles, index),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildOnlineTab() {
//     if (onlineItems.isEmpty) {
//       return const Center(child: Text('No online found.'));
//     }
//     return ListView.builder(
//       itemCount: onlineItems.length,
//       padding: const EdgeInsets.only(bottom: 210),
//       itemBuilder: (context, index) {
//         final item = onlineItems[index];
//         return OnlineTile(
//           item: item,
//           isCurrent: Get.find<PlayerController>().currentId!.value == item.id,
//           onTap: () => _playOnlineSongs(onlineItems, index),
//         );
//       },
//     );
//   }

//   Widget _buildArtistsTab() {
//     if (controller.musicFiles.isEmpty) {
//       return const Center(child: Text('No local artists found.'));
//     }
//     final artists = <String, List<SongInfo>>{};
//     for (final song in controller.musicFiles) {
//       artists.putIfAbsent(song.meta.artist, () => []).add(song);
//     }
//     final artistList = artists.keys.toList()..sort();
//     if (artistList.isEmpty) {
//       return const Center(child: Text('No matching artists found.'));
//     }
//     return ListView.builder(
//       itemCount: artistList.length,
//       padding: const EdgeInsets.only(bottom: 210),
//       itemBuilder: (context, index) {
//         final artist = artistList[index];
//         final songs = artists[artist]!;
//         return Card(
//           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//           child: ListTile(
//             title: Text(artist),
//             subtitle: Text('${songs.length} songs'),
//             onTap:
//                 () => Get.to(
//                   () => ArtistDetailScreen(artist: artist, songs: songs),
//                 ),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildAlbumsTab() {
//     if (controller.musicFiles.isEmpty) {
//       return const Center(child: Text('No local albums found.'));
//     }
//     final albums = <String, List<SongInfo>>{};
//     for (final song in controller.musicFiles) {
//       albums.putIfAbsent(song.meta.album, () => []).add(song);
//     }
//     final albumList = albums.keys.toList()..sort();
//     if (albumList.isEmpty) {
//       return const Center(child: Text('No matching albums found.'));
//     }
//     return GridView.builder(
//       padding: const EdgeInsets.only(bottom: 210, top: 20),
//       gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//         crossAxisCount: 2,
//         childAspectRatio: 0.85,
//         crossAxisSpacing: 5,
//         mainAxisSpacing: 5,
//       ),
//       itemCount: albumList.length,
//       itemBuilder: (context, index) {
//         final album = albumList[index];
//         final songs = albums[album]!;
//         final artUri = AppUtils.getAlbumArt(songs);
//         final artist = songs.first.meta.artist;
//         return GestureDetector(
//           onTap:
//               () => Get.to(
//                 () => AlbumDetailScreen(
//                   album: album,
//                   artist: artist,
//                   songs: songs,
//                   artUri: artUri,
//                 ),
//               ),
//           child: Column(
//             children: [
//               Container(
//                 height: 160,
//                 width: 160,
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(8),
//                   image:
//                       artUri != null
//                           ? DecorationImage(
//                             image: FileImage(File(artUri.path)),
//                             fit: BoxFit.cover,
//                           )
//                           : null,
//                   color: Colors.grey[300],
//                 ),
//                 child:
//                     artUri == null ? const Icon(Icons.album, size: 60) : null,
//               ),
//               const SizedBox(height: 8),
//               Text(
//                 album,
//                 maxLines: 1,
//                 overflow: TextOverflow.ellipsis,
//                 style: const TextStyle(fontWeight: FontWeight.bold),
//               ),
//               Text(
//                 artist,
//                 maxLines: 1,
//                 overflow: TextOverflow.ellipsis,
//                 style: const TextStyle(color: Colors.grey),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildFoldersTab() {
//     if (controller.musicFiles.isEmpty) {
//       return const Center(child: Text('No folders found.'));
//     }
//     final folders = <String, List<SongInfo>>{};
//     for (final song in controller.musicFiles) {
//       final dir = path.dirname(song.file.path);
//       folders.putIfAbsent(dir, () => []).add(song);
//     }
//     final folderList = folders.keys.toList()..sort();
//     if (folderList.isEmpty) {
//       return const Center(child: Text('No matching folders found.'));
//     }
//     return ListView.builder(
//       itemCount: folderList.length,
//       padding: const EdgeInsets.only(bottom: 210),
//       itemBuilder: (context, index) {
//         final folder = folderList[index];
//         final songs = folders[folder]!;
//         return Card(
//           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//           child: ListTile(
//             title: Text(path.basename(folder)),
//             subtitle: Text('${songs.length} songs'),
//             onTap:
//                 () => Get.to(
//                   () => FolderDetailScreen(folder: folder, songs: songs),
//                 ),
//           ),
//         );
//       },
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     return DefaultTabController(
//       length: 5,
//       child: Scaffold(
//         drawer: AppDrawer(),
//         body: Obx(
//           () => Stack(
//             children: [
//               NestedScrollView(
//                 headerSliverBuilder: (context, innerBoxIsScrolled) {
//                   return <Widget>[
//                     SliverAppBar(
//                       floating: true,
//                       pinned: true,
//                       title: GestureDetector(
//                         onTap: () => Get.to(() => SearchScreen()),
//                         child: AbsorbPointer(
//                           child: SizedBox(
//                             height: 40,
//                             child: TextField(
//                               decoration: InputDecoration(
//                                 hintText:
//                                     'Search songs, playlists, and artists',
//                                 suffixIcon: const Icon(Icons.search_rounded),
//                                 contentPadding: const EdgeInsets.only(
//                                   top: 5,
//                                   left: 15,
//                                   right: 5,
//                                 ),
//                                 border: OutlineInputBorder(
//                                   borderRadius: BorderRadius.circular(30.0),
//                                 ),
//                                 filled: true,
//                                 fillColor:
//                                     Theme.of(
//                                       context,
//                                     ).colorScheme.surfaceVariant,
//                               ),
//                             ),
//                           ),
//                         ),
//                       ),
//                       bottom: const TabBar(
//                         unselectedLabelColor: Colors.grey,
//                         tabs: [
//                           Tab(text: 'Songs'),
//                           Tab(text: 'Online'),
//                           Tab(text: 'Artists'),
//                           Tab(text: 'Albums'),
//                           Tab(text: 'Folders'),
//                         ],
//                       ),
//                     ),
//                   ];
//                 },
//                 body: Column(
//                   children: [
//                     Container(
//                       color: theme.colorScheme.surfaceContainerHighest,
//                       width: double.infinity,
//                       padding: const EdgeInsets.symmetric(
//                         horizontal: 16,
//                         vertical: 8,
//                       ),
//                       child: Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Expanded(
//                             child: Text(
//                               controller.message!.value,
//                               style: TextStyle(
//                                 color: theme.colorScheme.onSurfaceVariant,
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                     Expanded(
//                       child: TabBarView(
//                         children: List.generate(
//                           5,
//                           (index) => _buildTabContent(index),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               if (controller.isScanning.value)
//                 const Center(child: CircularProgressIndicator()),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// // AppDrawer (stateless)
// class AppDrawer extends StatelessWidget {
//   AppDrawer({super.key});

//   final LibraryController libCtrl = Get.find<LibraryController>();
//   final AppController appCtrl = Get.find<AppController>();

//   @override
//   Widget build(BuildContext context) {
//     return Drawer(
//       child: SafeArea(
//         child: Obx(
//           () => ListView(
//             padding: const EdgeInsets.only(bottom: 210),
//             children: <Widget>[
//               ListTile(
//                 leading: const Icon(Icons.search),
//                 title: const Text('Scan Local Files (Automatic)'),
//                 onTap: () {
//                   Get.back();
//                   libCtrl.startScan();
//                 },
//               ),
//               ListTile(
//                 leading: const Icon(Icons.folder),
//                 title: const Text('Select Folder to Scan'),
//                 onTap: () {
//                   Get.back();
//                   libCtrl.selectAndScanFolder();
//                 },
//               ),
//               const Divider(),
//               ListTile(
//                 leading: Icon(
//                   appCtrl.themeMode.value == ThemeMode.dark
//                       ? Icons.light_mode
//                       : Icons.dark_mode,
//                 ),
//                 title: const Text('Dark Mode'),
//                 trailing: CupertinoSwitch(
//                   value: appCtrl.themeMode.value == ThemeMode.dark,
//                   onChanged: (_) => appCtrl.toggleTheme(),
//                 ),
//               ),
//               ListTile(
//                 leading: Icon(Icons.image_outlined),
//                 title: const Text('Image in Player Background'),
//                 trailing: CupertinoSwitch(
//                   value: appCtrl.isPlayerBgImage.value,
//                   onChanged: (value) => appCtrl.tooglePlayerBackGround(),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// // SearchScreen (GetView)
// class SearchScreen extends GetView<SearchController> {
//   SearchScreen({super.key});

//   final LibraryController libCtrl = Get.find<LibraryController>();

//   void _playLocalSongs(List<SongInfo> playlist, int index) {
//     (_audioHandler as CustomAudioHandler).playLocalPlaylist(playlist, index);
//   }

//   void _playOnlineSongs(List<MediaItem> items, int index) {
//     (_audioHandler as CustomAudioHandler).playOnlinePlaylist(items, index);
//     Get.snackbar('Playing', items[index].title);
//   }

//   Widget _buildSongsTab() {
//     final playerCtrl = Get.find<PlayerController>();

//     final filteredSongs =
//         libCtrl.musicFiles.where((song) {
//           final lowerTitle = song.meta.title.toLowerCase();
//           final lowerArtist = song.meta.artist.toLowerCase();
//           final lowerAlbum = song.meta.album.toLowerCase();
//           return lowerTitle.contains(controller.searchQuery.value) ||
//               lowerArtist.contains(controller.searchQuery.value) ||
//               lowerAlbum.contains(controller.searchQuery.value);
//         }).toList();

//     return ListView.builder(
//       itemCount: filteredSongs.length,
//       padding: const EdgeInsets.only(bottom: 210),
//       itemBuilder: (context, index) {
//         final song = filteredSongs[index];
//         final songId = Uri.file(song.file.path).toString();
//         return Obx(
//           () => SongTile(
//             song: song,
//             isCurrent: playerCtrl.currentId!.value == songId,
//             onTap: () => _playLocalSongs(filteredSongs, index),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildOnlineTab() {
//     return Obx(() {
//       final filteredItems =
//           onlineItems.where((item) {
//             final lowerTitle = item.title.toLowerCase();
//             final lowerArtist = (item.artist ?? '').toLowerCase();
//             final lowerAlbum = (item.album ?? '').toLowerCase();
//             return lowerTitle.contains(controller.searchQuery.value) ||
//                 lowerArtist.contains(controller.searchQuery.value) ||
//                 lowerAlbum.contains(controller.searchQuery.value);
//           }).toList();
//       if (filteredItems.isEmpty)
//         return const Center(child: Text('No matching online found.'));
//       return ListView.builder(
//         itemCount: filteredItems.length,
//         padding: const EdgeInsets.only(bottom: 210),
//         itemBuilder: (context, index) {
//           final item = filteredItems[index];
//           return OnlineTile(
//             item: item,
//             isCurrent: Get.find<PlayerController>().currentId!.value == item.id,
//             onTap: () => _playOnlineSongs(filteredItems, index),
//           );
//         },
//       );
//     });
//   }

//   Widget _buildArtistsTab() {
//     return Obx(() {
//       final artists = <String, List<SongInfo>>{};
//       for (final song in libCtrl.musicFiles) {
//         final lowerArtist = song.meta.artist.toLowerCase();
//         if (lowerArtist.contains(controller.searchQuery.value) ||
//             song.meta.title.toLowerCase().contains(
//               controller.searchQuery.value,
//             ) ||
//             song.meta.album.toLowerCase().contains(
//               controller.searchQuery.value,
//             )) {
//           artists.putIfAbsent(song.meta.artist, () => []).add(song);
//         }
//       }
//       final artistList = artists.keys.toList()..sort();
//       if (artistList.isEmpty)
//         return const Center(child: Text('No matching artists found.'));
//       return ListView.builder(
//         itemCount: artistList.length,
//         padding: const EdgeInsets.only(bottom: 210),
//         itemBuilder: (context, index) {
//           final artist = artistList[index];
//           final songs = artists[artist]!;
//           return Card(
//             margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//             child: ListTile(
//               title: Text(artist),
//               subtitle: Text('${songs.length} songs'),
//               onTap:
//                   () => Get.to(
//                     () => ArtistDetailScreen(artist: artist, songs: songs),
//                   ),
//             ),
//           );
//         },
//       );
//     });
//   }

//   Widget _buildAlbumsTab() {
//     return Obx(() {
//       final albums = <String, List<SongInfo>>{};
//       for (final song in libCtrl.musicFiles) {
//         final lowerAlbum = song.meta.album.toLowerCase();
//         if (lowerAlbum.contains(controller.searchQuery.value) ||
//             song.meta.title.toLowerCase().contains(
//               controller.searchQuery.value,
//             ) ||
//             song.meta.artist.toLowerCase().contains(
//               controller.searchQuery.value,
//             )) {
//           albums.putIfAbsent(song.meta.album, () => []).add(song);
//         }
//       }
//       final albumList = albums.keys.toList()..sort();
//       if (albumList.isEmpty)
//         return const Center(child: Text('No matching albums found.'));
//       return GridView.builder(
//         padding: const EdgeInsets.only(bottom: 210, top: 20),
//         gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//           crossAxisCount: 2,
//           childAspectRatio: 0.85,
//           crossAxisSpacing: 5,
//           mainAxisSpacing: 5,
//         ),
//         itemCount: albumList.length,
//         itemBuilder: (context, index) {
//           final album = albumList[index];
//           final songs = albums[album]!;
//           final artUri = AppUtils.getAlbumArt(songs);
//           final artist = songs.first.meta.artist;
//           return GestureDetector(
//             onTap:
//                 () => Get.to(
//                   () => AlbumDetailScreen(
//                     album: album,
//                     artist: artist,
//                     songs: songs,
//                     artUri: artUri,
//                   ),
//                 ),
//             child: Column(
//               children: [
//                 Container(
//                   height: 160,
//                   width: 160,
//                   decoration: BoxDecoration(
//                     borderRadius: BorderRadius.circular(8),
//                     image:
//                         artUri != null
//                             ? DecorationImage(
//                               image: FileImage(File(artUri.path)),
//                               fit: BoxFit.cover,
//                             )
//                             : null,
//                     color: Colors.grey[300],
//                   ),
//                   child:
//                       artUri == null ? const Icon(Icons.album, size: 60) : null,
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   album,
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: const TextStyle(fontWeight: FontWeight.bold),
//                 ),
//                 Text(
//                   artist,
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: const TextStyle(color: Colors.grey),
//                 ),
//               ],
//             ),
//           );
//         },
//       );
//     });
//   }

//   Widget _buildFoldersTab() {
//     return Obx(() {
//       final folders = <String, List<SongInfo>>{};
//       for (final song in libCtrl.musicFiles) {
//         final dir = path.dirname(song.file.path);
//         final lowerDir = dir.toLowerCase();
//         if (lowerDir.contains(controller.searchQuery.value) ||
//             song.meta.title.toLowerCase().contains(
//               controller.searchQuery.value,
//             ) ||
//             song.meta.artist.toLowerCase().contains(
//               controller.searchQuery.value,
//             ) ||
//             song.meta.album.toLowerCase().contains(
//               controller.searchQuery.value,
//             )) {
//           folders.putIfAbsent(dir, () => []).add(song);
//         }
//       }
//       final folderList = folders.keys.toList()..sort();
//       if (folderList.isEmpty)
//         return const Center(child: Text('No matching folders found.'));
//       return ListView.builder(
//         itemCount: folderList.length,
//         padding: const EdgeInsets.only(bottom: 210),
//         itemBuilder: (context, index) {
//           final folder = folderList[index];
//           final songs = folders[folder]!;
//           return Card(
//             margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//             child: ListTile(
//               title: Text(path.basename(folder)),
//               subtitle: Text('${songs.length} songs'),
//               onTap:
//                   () => Get.to(
//                     () => FolderDetailScreen(folder: folder, songs: songs),
//                   ),
//             ),
//           );
//         },
//       );
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return DefaultTabController(
//       length: 5,
//       child: Scaffold(
//         body: NestedScrollView(
//           headerSliverBuilder: (context, innerBoxIsScrolled) {
//             return <Widget>[
//               SliverAppBar(
//                 floating: true,
//                 pinned: true,
//                 title: SizedBox(
//                   height: 40,
//                   child: TextField(
//                     controller: controller.searchTextController,
//                     autofocus: true,
//                     decoration: InputDecoration(
//                       contentPadding: const EdgeInsets.only(
//                         top: 5,
//                         left: 15,
//                         right: 5,
//                       ),
//                       hintText: 'Search songs, playlists, and artists',
//                       suffixIcon: const Icon(Icons.search_rounded),
//                       border: OutlineInputBorder(
//                         borderRadius: BorderRadius.circular(30.0),
//                       ),
//                       filled: true,
//                       fillColor: Theme.of(context).colorScheme.surfaceVariant,
//                     ),
//                   ),
//                 ),
//                 bottom: const TabBar(
//                   unselectedLabelColor: Colors.grey,
//                   tabs: [
//                     Tab(text: 'Songs'),
//                     Tab(text: 'Online'),
//                     Tab(text: 'Artists'),
//                     Tab(text: 'Albums'),
//                     Tab(text: 'Folders'),
//                   ],
//                 ),
//               ),
//             ];
//           },
//           body: TabBarView(
//             children: [
//               _buildSongsTab(),
//               _buildOnlineTab(),
//               _buildArtistsTab(),
//               _buildAlbumsTab(),
//               _buildFoldersTab(),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// // FolderDetailScreen (stateless)
// class FolderDetailScreen extends StatelessWidget {
//   final String folder;
//   final List<SongInfo> songs;

//   const FolderDetailScreen({
//     super.key,
//     required this.folder,
//     required this.songs,
//   });

//   void _playSongs(int index, {bool shuffle = false}) {
//     final handler = _audioHandler as CustomAudioHandler;
//     if (shuffle) Get.find<PlayerController>().toggleShuffle();
//     handler.playLocalPlaylist(songs, index);
//   }

//   @override
//   Widget build(BuildContext context) {
//     final playerCtrl = Get.find<PlayerController>();
//     return Scaffold(
//       appBar: AppBar(title: Text(path.basename(folder))),
//       body: Column(
//         children: [
//           Text(
//             '${songs.length} songs',
//             style: Theme.of(context).textTheme.titleMedium,
//           ),
//           Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               ElevatedButton(
//                 onPressed: () => _playSongs(0),
//                 child: const Text('Play'),
//               ),
//               const SizedBox(width: 16),
//               ElevatedButton(
//                 onPressed: () => _playSongs(0, shuffle: true),
//                 child: const Text('Shuffle'),
//               ),
//             ],
//           ),
//           Expanded(
//             child: ListView.builder(
//               itemCount: songs.length,
//               itemBuilder: (context, index) {
//                 final song = songs[index];
//                 final songId = Uri.file(song.file.path).toString();
//                 return Obx(
//                   () => SongTile(
//                     song: song,
//                     isCurrent: playerCtrl.currentId!.value == songId,
//                     onTap: () => _playSongs(index),
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // MiniPlayer (stateless)
// class MiniPlayer extends StatelessWidget {
//   const MiniPlayer({super.key});

//   Stream<MediaState> get _mediaStateStream =>
//       rx.Rx.combineLatest2<MediaItem?, Duration, MediaState>(
//         _audioHandler.mediaItem.stream,
//         AudioService.position,
//         (item, pos) => MediaState(item, pos),
//       );

//   Widget _art(MediaItem item, double size) {
//     final uri = item.artUri;
//     Widget image = Icon(Icons.album, size: size, color: Colors.grey);
//     if (uri != null) {
//       if (uri.scheme == 'file') {
//         image = Image.file(
//           File(uri.path),
//           height: size,
//           width: size,
//           fit: BoxFit.cover,
//         );
//       } else {
//         image = CachedNetworkImage(
//           imageUrl: uri.toString(),
//           height: size,
//           width: size,
//           fit: BoxFit.cover,
//         );
//       }
//     }
//     return ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final inactive = theme.colorScheme.onSurface.withOpacity(0.4);
//     return StreamBuilder<MediaItem?>(
//       stream: _audioHandler.mediaItem.stream,
//       builder: (_, snap) {
//         final item = snap.data;
//         if (item == null) return const SizedBox.shrink();
//         return GestureDetector(
//           onTap: () {
//             Get.find<AppController>().showFullPlayer.value = true;
//             Get.to(() => const FullScreenPlayer());
//           },
//           child: Container(
//             padding: const EdgeInsets.all(12),
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(26),
//               color:
//                   theme.brightness == Brightness.dark
//                       ? const Color.fromARGB(255, 18, 18, 18).withOpacity(0.92)
//                       : theme.cardColor.withOpacity(0.9),
//               boxShadow: [
//                 BoxShadow(
//                   color: inactive.withOpacity(0.2),
//                   blurRadius: 10,
//                   spreadRadius: 2,
//                 ),
//               ],
//             ),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Row(
//                   children: [
//                     _art(item, 40),
//                     const SizedBox(width: 10),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             item.title,
//                             maxLines: 1,
//                             overflow: TextOverflow.ellipsis,
//                             style: const TextStyle(fontWeight: FontWeight.w600),
//                           ),
//                           Text(
//                             item.artist ?? 'Unknown',
//                             maxLines: 1,
//                             overflow: TextOverflow.ellipsis,
//                             style: TextStyle(color: inactive, fontSize: 12),
//                           ),
//                         ],
//                       ),
//                     ),
//                     StreamBuilder<AudioProcessingState>(
//                       stream:
//                           _audioHandler.playbackState.stream
//                               .map((state) => state.processingState)
//                               .distinct(),
//                       builder: (context, snapshot) {
//                         final state =
//                             snapshot.data ?? AudioProcessingState.idle;
//                         return Icon(
//                           AppUtils.getProcessingIcon(state),
//                           size: 20,
//                         );
//                       },
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 6),
//                 StreamBuilder<MediaState>(
//                   stream: _mediaStateStream,
//                   builder: (_, ss) {
//                     final pos = ss.data?.position ?? Duration.zero;
//                     final dur = ss.data?.mediaItem?.duration ?? Duration.zero;
//                     return Row(
//                       children: [
//                         Text(
//                           AppUtils.formatDuration(pos),
//                           style: TextStyle(color: inactive, fontSize: 10),
//                         ),
//                         const SizedBox(width: 8),
//                         Expanded(
//                           child: SeekBar(
//                             duration: dur,
//                             position: pos,
//                             activeColor: theme.colorScheme.primary,
//                             inactiveColor: inactive.withOpacity(0.3),
//                             onChangeEnd: _audioHandler.seek,
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         Text(
//                           AppUtils.formatDuration(dur),
//                           style: TextStyle(color: inactive, fontSize: 10),
//                         ),
//                       ],
//                     );
//                   },
//                 ),
//                 Controls(),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }
// }

// // ArtistDetailScreen (stateless)
// class ArtistDetailScreen extends StatelessWidget {
//   final String artist;
//   final List<SongInfo> songs;

//   const ArtistDetailScreen({
//     super.key,
//     required this.artist,
//     required this.songs,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final artUri = AppUtils.getArtistArt(songs);
//     return DetailScaffold(
//       title: artist,
//       subtitle: '${songs.length} tracks • ${songs.length} albums',
//       songs: songs,
//       artUri: artUri,
//       showArtist: false,
//     );
//   }
// }

// // AlbumDetailScreen (stateless)
// class AlbumDetailScreen extends StatelessWidget {
//   final String album;
//   final String artist;
//   final List<SongInfo> songs;
//   final Uri? artUri;

//   const AlbumDetailScreen({
//     super.key,
//     required this.album,
//     required this.artist,
//     required this.songs,
//     this.artUri,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return DetailScaffold(
//       title: album,
//       subtitle: artist,
//       songs: songs,
//       artUri: artUri,
//       showArtist: true,
//     );
//   }
// }

// // MediaState
// class MediaState {
//   final MediaItem? mediaItem;
//   final Duration position;

//   MediaState(this.mediaItem, this.position);
// }

// // SeekBar (stateless with internal state for drag)
// class SeekBar extends StatefulWidget {
//   final Duration duration;
//   final Duration position;
//   final ValueChanged<Duration>? onChangeEnd;
//   final Color activeColor;
//   final Color inactiveColor;

//   const SeekBar({
//     super.key,
//     required this.duration,
//     required this.position,
//     this.onChangeEnd,
//     required this.activeColor,
//     required this.inactiveColor,
//   });

//   @override
//   State<SeekBar> createState() => _SeekBarState();
// }

// class _SeekBarState extends State<SeekBar> {
//   double? _dragValue;

//   @override
//   Widget build(BuildContext context) {
//     double value = _dragValue ?? widget.position.inMilliseconds.toDouble();
//     value = value.clamp(0.0, widget.duration.inMilliseconds.toDouble());
//     final max = widget.duration.inMilliseconds.toDouble().clamp(
//       1.0,
//       double.infinity,
//     );
//     return SliderTheme(
//       data: SliderTheme.of(context).copyWith(
//         trackHeight: 4.0,
//         thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
//         overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
//       ),
//       child: Slider(
//         min: 0.0,
//         max: max,
//         value: value,
//         activeColor: widget.activeColor,
//         inactiveColor: widget.inactiveColor,
//         onChanged: (newValue) => setState(() => _dragValue = newValue),
//         onChangeEnd: (newValue) {
//           widget.onChangeEnd?.call(Duration(milliseconds: newValue.round()));
//           setState(() => _dragValue = null);
//         },
//       ),
//     );
//   }
// }

// // GlobalWrapper (stateless)
// class GlobalWrapper extends StatelessWidget {
//   final Widget child;

//   const GlobalWrapper({super.key, required this.child});

//   @override
//   Widget build(BuildContext context) {
//     final appCtrl = Get.find<AppController>();
//     return Material(
//       child: Stack(
//         alignment: Alignment.bottomCenter,
//         children: [
//           child,
//           Obx(
//             () => AnimatedSwitcher(
//               duration: 300.milliseconds,
//               child:
//                   !appCtrl.showFullPlayer.value
//                       ? SafeArea(
//                         child: Padding(
//                           padding: const EdgeInsets.all(12),
//                           child: const MiniPlayer(),
//                         ),
//                       )
//                       : const SizedBox.shrink(),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // FullScreenPlayer (stateless)
// class FullScreenPlayer extends StatelessWidget {
//   const FullScreenPlayer({super.key});

//   void _onBack() {
//     Get.back();
//     Get.find<AppController>().showFullPlayer.value = false;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return PopScope(
//       canPop: true,
//       onPopInvokedWithResult: (didPop, result) {
//         if (didPop) _onBack();
//         return;
//       },
//       child: Scaffold(
//         backgroundColor: Colors.transparent,
//         body: StreamBuilder<MediaItem?>(
//           stream: _audioHandler.mediaItem.stream,
//           builder: (_, snap) {
//             final item = snap.data;
//             if (item == null) return const SizedBox.shrink();
//             final appCtrl = Get.find<AppController>();
//             return Stack(
//               fit: StackFit.expand,
//               children: [
//                 Obx(
//                   () => AnimatedSwitcher(
//                     duration: 300.milliseconds,
//                     child:
//                         item.artUri != null && appCtrl.isPlayerBgImage.value
//                             ? ImageFiltered(
//                               imageFilter: ImageFilter.blur(
//                                 sigmaX: 40,
//                                 sigmaY: 40,
//                               ),
//                               child: MiniPlayer()._art(item, double.infinity),
//                             )
//                             : const SizedBox.shrink(),
//                   ),
//                 ),
//                 Container(
//                   color: Theme.of(
//                     context,
//                   ).scaffoldBackgroundColor.withOpacity(0.4),
//                 ),
//                 SafeArea(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Padding(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 8,
//                           vertical: 4,
//                         ),
//                         child: Row(
//                           mainAxisAlignment: MainAxisAlignment.start,
//                           children: [
//                             const SizedBox(width: 28),
//                             IconButton(
//                               icon: const Icon(
//                                 Icons.keyboard_arrow_down_rounded,
//                                 size: 35,
//                               ),
//                               onPressed: _onBack,
//                             ),
//                             const Spacer(),
//                             const SleepTimerButton(),
//                           ],
//                         ),
//                       ),
//                       const Expanded(child: PlayerBody()),
//                     ],
//                   ),
//                 ),
//               ],
//             );
//           },
//         ),
//       ),
//     );
//   }
// }

// // PlayerBody (stateless)
// class PlayerBody extends StatelessWidget {
//   const PlayerBody({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final inactive = theme.colorScheme.onSurface.withOpacity(0.4);
//     return StreamBuilder<MediaItem?>(
//       stream: _audioHandler.mediaItem.stream,
//       builder: (_, snap) {
//         final item = snap.data;
//         if (item == null) return const SizedBox.shrink();
//         return Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 24),
//           child: Column(
//             children: [
//               const Spacer(flex: 2),
//               StreamBuilder<PlaybackState>(
//                 stream: _audioHandler.playbackState,
//                 builder: (_, stateSnap) {
//                   final playing = stateSnap.data?.playing ?? false;
//                   return AnimatedScale(
//                     duration: const Duration(milliseconds: 500),
//                     curve: Curves.easeOut,
//                     scale: playing ? 1.0 : 0.7,
//                     child: Container(
//                       width: MediaQuery.of(context).size.width * 0.75,
//                       height: MediaQuery.of(context).size.width * 0.75,
//                       decoration: BoxDecoration(
//                         borderRadius: BorderRadius.circular(12),
//                         boxShadow: [
//                           BoxShadow(
//                             blurRadius: 30,
//                             spreadRadius: 4,
//                             color: theme.shadowColor.withOpacity(0.3),
//                           ),
//                         ],
//                       ),
//                       child: ClipRRect(
//                         borderRadius: BorderRadius.circular(12),
//                         child: Material(
//                           elevation: 10,
//                           clipBehavior: Clip.antiAlias,
//                           child: MiniPlayer()._art(item, double.infinity),
//                         ),
//                       ),
//                     ),
//                   );
//                 },
//               ),
//               const Spacer(),
//               Text(
//                 item.title,
//                 textAlign: TextAlign.center,
//                 style: theme.textTheme.headlineSmall?.copyWith(
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 6),
//               Text(
//                 item.artist ?? 'Unknown',
//                 textAlign: TextAlign.center,
//                 style: theme.textTheme.bodyLarge?.copyWith(color: inactive),
//               ),
//               const Spacer(),
//               StreamBuilder<MediaState>(
//                 stream: rx.Rx.combineLatest2<MediaItem?, Duration, MediaState>(
//                   _audioHandler.mediaItem.stream,
//                   AudioService.position,
//                   (a, b) => MediaState(a, b),
//                 ),
//                 builder: (_, ss) {
//                   final pos = ss.data?.position ?? Duration.zero;
//                   final dur = ss.data?.mediaItem?.duration ?? Duration.zero;
//                   return Column(
//                     children: [
//                       SeekBar(
//                         duration: dur,
//                         position: pos,
//                         activeColor: theme.colorScheme.primary,
//                         inactiveColor: inactive.withOpacity(0.3),
//                         onChangeEnd: _audioHandler.seek,
//                       ),
//                       Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 8.0),
//                         child: Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             Text(
//                               AppUtils.formatDuration(pos),
//                               style: TextStyle(color: inactive, fontSize: 12),
//                             ),
//                             Text(
//                               AppUtils.formatDuration(dur),
//                               style: TextStyle(color: inactive, fontSize: 12),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ],
//                   );
//                 },
//               ),
//               const Spacer(),
//               Controls(),
//               const Spacer(flex: 2),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }

// // Controls (stateless)
// class Controls extends StatelessWidget {
//   const Controls({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final inactive = theme.colorScheme.onSurface.withOpacity(0.4);
//     final primary = theme.colorScheme.primary;
//     final playerCtrl = Get.find<PlayerController>();
//     return StreamBuilder<PlaybackState>(
//       stream: _audioHandler.playbackState,
//       builder: (_, snap) {
//         final state = snap.data;
//         final playing = state?.playing ?? false;
//         final queueIndex = state?.queueIndex ?? 0;
//         final queueLen = _audioHandler.queue.value.length;
//         final repeat = playerCtrl.repeatMode.value;
//         final shuffle = playerCtrl.shuffleMode.value;
//         final hasPrev = repeat != AudioServiceRepeatMode.one && queueIndex > 0;
//         final hasNext =
//             repeat != AudioServiceRepeatMode.one && queueIndex < queueLen - 1;
//         return Row(
//           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//           children: [
//             IconButton(
//               icon: Icon(Icons.shuffle, color: shuffle ? primary : inactive),
//               onPressed: playerCtrl.toggleShuffle,
//             ),
//             IconButton(
//               icon: Icon(
//                 Icons.skip_previous,
//                 color: hasPrev ? primary : inactive,
//               ),
//               onPressed: hasPrev ? _audioHandler.skipToPrevious : null,
//             ),
//             IconButton(
//               icon: Icon(
//                 playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
//                 color: primary,
//               ),
//               onPressed: playing ? _audioHandler.pause : _audioHandler.play,
//             ),
//             IconButton(
//               icon: Icon(Icons.skip_next, color: hasNext ? primary : inactive),
//               onPressed: hasNext ? _audioHandler.skipToNext : null,
//             ),
//             IconButton(
//               icon: Icon(
//                 repeat == AudioServiceRepeatMode.one
//                     ? Icons.repeat_one
//                     : Icons.repeat,
//                 color:
//                     repeat != AudioServiceRepeatMode.none ? primary : inactive,
//               ),
//               onPressed: playerCtrl.cycleRepeat,
//             ),
//           ],
//         );
//       },
//     );
//   }
// }

// // DetailScaffold (stateless)
// class DetailScaffold extends StatelessWidget {
//   final String title;
//   final String subtitle;
//   final List<SongInfo> songs;
//   final Uri? artUri;
//   final bool showArtist;

//   const DetailScaffold({
//     super.key,
//     required this.title,
//     required this.subtitle,
//     required this.songs,
//     this.artUri,
//     this.showArtist = false,
//   });

//   void _playSongs(int index, {bool shuffle = false}) {
//     final handler = _audioHandler as CustomAudioHandler;
//     if (shuffle) Get.find<PlayerController>().toggleShuffle();
//     handler.playLocalPlaylist(songs, index);
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final isDark = theme.brightness == Brightness.dark;
//     final playerCtrl = Get.find<PlayerController>();
//     return Scaffold(
//       body: NestedScrollView(
//         headerSliverBuilder:
//             (context, innerBoxIsScrolled) => [
//               SliverAppBar(
//                 pinned: true,
//                 stretch: true,
//                 elevation: 0,
//                 expandedHeight: 320,
//                 backgroundColor: theme.scaffoldBackgroundColor,
//                 automaticallyImplyLeading: false,
//                 leading: IconButton(
//                   icon: const Icon(Icons.arrow_back),
//                   onPressed: Get.back,
//                 ),
//                 flexibleSpace: LayoutBuilder(
//                   builder: (context, constraints) {
//                     final percent =
//                         (constraints.maxHeight - kToolbarHeight) /
//                         (320 - kToolbarHeight);
//                     return FlexibleSpaceBar(
//                       centerTitle: false,
//                       titlePadding: const EdgeInsets.symmetric(
//                         horizontal: 50,
//                         vertical: 12,
//                       ),
//                       title: Opacity(
//                         opacity: 1 - percent.clamp(0.0, 1.0),
//                         child: Text(
//                           title,
//                           style: theme.textTheme.titleLarge?.copyWith(
//                             fontWeight: FontWeight.bold,
//                             color: isDark ? Colors.white : Colors.black,
//                           ),
//                         ),
//                       ),
//                       background: Stack(
//                         fit: StackFit.expand,
//                         children: [
//                           artUri != null
//                               ? Image.file(
//                                 File(artUri!.path),
//                                 fit: BoxFit.cover,
//                               )
//                               : const Center(
//                                 child: Icon(Icons.album, size: 100),
//                               ),
//                           Container(
//                             decoration: BoxDecoration(
//                               gradient: LinearGradient(
//                                 begin: Alignment.topCenter,
//                                 end: Alignment.bottomCenter,
//                                 colors:
//                                     isDark
//                                         ? [
//                                           Colors.transparent,
//                                           Colors.black.withOpacity(0.9),
//                                         ]
//                                         : [
//                                           Colors.transparent,
//                                           Colors.white.withOpacity(0.9),
//                                         ],
//                               ),
//                             ),
//                           ),
//                           Align(
//                             alignment: Alignment.bottomLeft,
//                             child: Padding(
//                               padding: const EdgeInsets.only(
//                                 left: 16,
//                                 bottom: 24,
//                               ),
//                               child: Opacity(
//                                 opacity: percent.clamp(0.0, 1.0),
//                                 child: Column(
//                                   mainAxisSize: MainAxisSize.min,
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     Text(
//                                       title,
//                                       style: theme.textTheme.headlineSmall
//                                           ?.copyWith(
//                                             fontWeight: FontWeight.bold,
//                                             color:
//                                                 isDark
//                                                     ? Colors.white
//                                                     : Colors.black,
//                                           ),
//                                     ),
//                                     if (showArtist) ...[
//                                       const SizedBox(height: 6),
//                                       Text(
//                                         subtitle,
//                                         style: theme.textTheme.titleMedium
//                                             ?.copyWith(
//                                               color: (isDark
//                                                       ? Colors.white
//                                                       : Colors.black)
//                                                   .withOpacity(0.8),
//                                             ),
//                                       ),
//                                     ],
//                                   ],
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ],
//         body: Obx(
//           () => ListView(
//             padding: const EdgeInsets.only(bottom: 210),
//             children: [
//               Padding(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 16,
//                   vertical: 16,
//                 ),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     if (showArtist)
//                       Text(subtitle, style: theme.textTheme.titleLarge),
//                     Text(
//                       '${songs.length} songs',
//                       style: theme.textTheme.titleMedium?.copyWith(
//                         color: theme.textTheme.bodyMedium?.color?.withOpacity(
//                           0.7,
//                         ),
//                       ),
//                     ),
//                     const SizedBox(height: 16),
//                     Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                       children: [
//                         FilledButton.icon(
//                           onPressed: () => _playSongs(0),
//                           icon: const Icon(Icons.play_arrow),
//                           label: const Text('Play'),
//                           style: FilledButton.styleFrom(
//                             minimumSize: const Size(140, 45),
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(14),
//                             ),
//                           ),
//                         ),
//                         FilledButton.tonalIcon(
//                           onPressed: () => _playSongs(0, shuffle: true),
//                           icon: const Icon(Icons.shuffle),
//                           label: const Text('Shuffle'),
//                           style: FilledButton.styleFrom(
//                             minimumSize: const Size(140, 45),
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(14),
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//               const Divider(height: 1),
//               ...List.generate(songs.length, (index) {
//                 final song = songs[index];
//                 final songId = Uri.file(song.file.path).toString();
//                 return SongTile(
//                   song: song,
//                   isCurrent: playerCtrl.currentId!.value == songId,
//                   onTap: () => _playSongs(index),
//                   trackNumber: index + 1,
//                   showDuration: true,
//                 );
//               }),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// // Reusable SleepTimerButton with the provided design
// class SleepTimerButton extends StatelessWidget {
//   const SleepTimerButton({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final controller =
//         Get.find<SleepTimerController>(); // Use find; put in init
//     final screenHeight = MediaQuery.of(context).size.height;
//     const percentage =
//         1.0; // Assuming full opacity; adjust if needed from your context

//     return Obx(() {
//       final hasTimer = controller.isActive.value;

//       return Opacity(
//         opacity: percentage,
//         child: AnimatedSwitcher(
//           duration: const Duration(milliseconds: 300),
//           transitionBuilder:
//               (child, anim) => ScaleTransition(scale: anim, child: child),
//           child:
//               hasTimer
//                   ? InkWell(
//                     onTap: () async {
//                       final duration = await _showSleepTimerDialog(context);
//                       if (duration != null) {
//                         controller.setSleepTimer(duration);
//                       }
//                     },
//                     child: Container(
//                       padding: EdgeInsets.all(5),
//                       decoration: BoxDecoration(
//                         borderRadius: BorderRadius.circular(12),
//                         color: Theme.of(
//                           context,
//                         ).colorScheme.primary.withOpacity(0.1),
//                       ),
//                       child: Row(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Icon(
//                             CupertinoIcons.moon_zzz_fill,
//                             size: screenHeight * 0.022,
//                             color: Theme.of(context).colorScheme.primary,
//                           ),
//                           const SizedBox(width: 4),
//                           Text(
//                             _formatDuration(controller.remaining.value),
//                             style: TextStyle(
//                               fontSize: screenHeight * 0.015,
//                               fontWeight: FontWeight.bold,
//                               color: Theme.of(context).colorScheme.primary,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   )
//                   : IconButton(
//                     onPressed: () async {
//                       final duration = await _showSleepTimerDialog(context);
//                       if (duration != null) {
//                         controller.setSleepTimer(duration);
//                       }
//                     },
//                     icon: Icon(
//                       CupertinoIcons.moon_zzz_fill,
//                       size: screenHeight * 0.022,
//                       color: Theme.of(context).colorScheme.onSurfaceVariant,
//                     ),
//                   ),
//         ),
//       );
//     });
//   }

//   String _formatDuration(Duration d) {
//     final minutes = d.inMinutes;
//     final seconds = d.inSeconds.remainder(60);
//     return '$minutes:${seconds.toString().padLeft(2, '0')}';
//   }

//   Future<Duration?> _showSleepTimerDialog(BuildContext parentContext) async {
//     final controller = Get.find<SleepTimerController>();
//     final List<Map<String, dynamic>> options = [
//       {'label': 'Off', 'duration': Duration.zero},
//       {'label': '1 minute', 'duration': const Duration(minutes: 1)},
//       {'label': '5 minutes', 'duration': const Duration(minutes: 5)},
//       {'label': '10 minutes', 'duration': const Duration(minutes: 10)},
//       {'label': '20 minutes', 'duration': const Duration(minutes: 20)},
//       {'label': '30 minutes', 'duration': const Duration(minutes: 30)},
//       {'label': '40 minutes', 'duration': const Duration(minutes: 40)},
//       {'label': '50 minutes', 'duration': const Duration(minutes: 50)},
//       {'label': '60 minutes', 'duration': const Duration(minutes: 60)},
//       {'label': 'Custom', 'duration': null},
//     ];

//     int selectedIndex = 0;
//     if (controller.isActive.value) {
//       final currentMin = controller.remaining.value.inMinutes;
//       selectedIndex = options.indexWhere(
//         (opt) =>
//             opt['duration'] != null &&
//             (opt['duration'] as Duration).inMinutes == currentMin,
//       );
//       if (selectedIndex == -1) selectedIndex = options.length - 1;
//     }

//     return await showCupertinoModalPopup<Duration?>(
//       context: parentContext,
//       builder: (BuildContext dialogContext) {
//         return StatefulBuilder(
//           builder: (BuildContext builderContext, StateSetter setState) {
//             return Container(
//               height: 300,
//               color: CupertinoColors.systemBackground.resolveFrom(
//                 builderContext,
//               ),
//               child: Column(
//                 children: [
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       CupertinoButton(
//                         child: const Text('Cancel'),
//                         onPressed: () => Navigator.pop(dialogContext, null),
//                       ),
//                       CupertinoButton(
//                         child: const Text('Set'),
//                         onPressed: () async {
//                           final opt = options[selectedIndex];
//                           Duration? selectedDuration;
//                           if (opt['duration'] == null) {
//                             selectedDuration = await _showCustomTimerPicker(
//                               builderContext,
//                             );
//                           } else {
//                             selectedDuration = opt['duration'] as Duration;
//                           }
//                           if (selectedDuration != null) {
//                             Navigator.pop(dialogContext, selectedDuration);
//                           }
//                         },
//                       ),
//                     ],
//                   ),
//                   Expanded(
//                     child: CupertinoPicker(
//                       itemExtent: 32,
//                       scrollController: FixedExtentScrollController(
//                         initialItem: selectedIndex,
//                       ),
//                       onSelectedItemChanged:
//                           (int index) => setState(() => selectedIndex = index),
//                       children:
//                           options
//                               .map(
//                                 (opt) =>
//                                     Center(child: Text(opt['label'] as String)),
//                               )
//                               .toList(),
//                     ),
//                   ),
//                 ],
//               ),
//             );
//           },
//         );
//       },
//     );
//   }

//   Future<Duration?> _showCustomTimerPicker(BuildContext parentContext) async {
//     final controller = Get.find<SleepTimerController>();
//     Duration selectedDuration =
//         controller.remaining.value != Duration.zero
//             ? controller.remaining.value
//             : const Duration(minutes: 30);

//     return await showCupertinoModalPopup<Duration?>(
//       context: parentContext,
//       builder: (BuildContext dialogContext) {
//         return Container(
//           height: 300,
//           color: CupertinoColors.systemBackground.resolveFrom(dialogContext),
//           child: Column(
//             children: [
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   CupertinoButton(
//                     child: const Text('Cancel'),
//                     onPressed: () => Navigator.pop(dialogContext, null),
//                   ),
//                   CupertinoButton(
//                     child: const Text('Done'),
//                     onPressed:
//                         () => Navigator.pop(dialogContext, selectedDuration),
//                   ),
//                 ],
//               ),
//               Expanded(
//                 child: CupertinoTimerPicker(
//                   mode: CupertinoTimerPickerMode.hm,
//                   minuteInterval: 1,
//                   initialTimerDuration: selectedDuration,
//                   onTimerDurationChanged:
//                       (Duration value) => selectedDuration = value,
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }

// // MyApp (stateless)
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final appCtrl = Get.find<AppController>();
//     return Obx(
//       () => GetMaterialApp(
//         debugShowCheckedModeBanner: false,
//         title: 'Rhythm Player',
//         theme: AppTheme.lightTheme,
//         darkTheme: AppTheme.darkTheme,
//         themeMode: appCtrl.themeMode.value,
//         home: const MainScreen(),
//         builder: (context, child) => GlobalWrapper(child: child!),
//       ),
//     );
//   }
// }
