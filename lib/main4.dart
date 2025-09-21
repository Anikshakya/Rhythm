import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/audio_handler.dart';
import 'package:rhythm/miniplayer/miniplayer.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:audio_service/audio_service.dart';
import 'package:rxdart/rxdart.dart' as rx;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize AudioService
  final audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.rhythm.channel.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  Get.put(MusicController(audioHandler));
  runApp(MyApp());
}

/// ---------------- Song Model ----------------
class Song {
  final String title;
  final String artist;
  final String url;
  final String? cover;
  final String? videoId;

  Song({
    required this.title,
    required this.artist,
    required this.url,
    this.cover,
    this.videoId,
  });

  MediaItem toMediaItem() => MediaItem(
    id: url,
    title: title,
    artist: artist,
    artUri: cover != null ? Uri.parse(cover!) : null,
    extras: {'uri': url, 'videoId': videoId},
  );
}

/// ---------------- Music Controller ----------------
class MusicController extends GetxController {
  final AudioPlayerHandler audioHandler;
  final RxList<Song> songs = <Song>[].obs;
  final RxInt currentIndex = (-1).obs; // Initialize to -1 (no song selected)
  final RxBool isPlaying = false.obs;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final RxBool isShuffling = false.obs;
  final Rx<LoopMode> loopMode = LoopMode.off.obs;
  final RxBool isLoading = false.obs;

  late final ValueNotifier<double> playerHeight;
  final double minHeight = playerMinHeight;

  List<int> originalOrder = [];
  List<int> shuffledOrder = [];
  int _playRequestId = 0;

  MusicController(this.audioHandler) {
    playerHeight = ValueNotifier<double>(playerMinHeight);
    _listenToAudioHandler();
  }

  void _listenToAudioHandler() {
    audioHandler.playbackState.listen((state) {
      print(
        "Playback state: ${state.processingState}, playing: ${state.playing}",
      );
      isPlaying.value = state.playing;
      isPlayingVN.value = state.playing;
      isLoading.value =
          state.processingState == AudioProcessingState.loading ||
          state.processingState == AudioProcessingState.buffering;
    });

    audioHandler.positionDataStream.listen((data) {
      position.value = data.position;
      duration.value = data.duration;
    });

    audioHandler.mediaItem.listen((mediaItem) {
      if (mediaItem != null) {
        final index = songs.indexWhere((song) => song.url == mediaItem.id);
        if (index != -1) {
          currentIndex.value = index;
          print(
            "Current media item: ${mediaItem.title}, index: ${currentIndex.value}",
          );
        }
      }
    });
  }

  Future<void> scanLocalAudio() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.storage.request();
      print("Storage permission status: $status");
      if (!status.isGranted) {
        Get.snackbar('Permission', 'Storage permission required.');
        return;
      }
      if (Platform.isAndroid) {
        final notificationStatus = await Permission.notification.request();
        print("Notification permission status: $notificationStatus");
        if (!notificationStatus.isGranted) {
          Get.snackbar('Permission', 'Notification permission required.');
        }
      }
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
    );
    if (result == null) {
      print("No files picked");
      return;
    }
    final picked =
        result.files
            .where((f) => f.path != null && File(f.path!).existsSync())
            .map((f) {
              print("Picked file: ${f.path}");
              return Song(
                title: f.name.split('.').first,
                artist: 'Unknown',
                url: f.path!,
              );
            })
            .toList();
    if (picked.isNotEmpty) {
      songs.assignAll(picked);
      await _setPlaylist();
      currentIndex.value = 0; // Set initial index after loading songs
    } else {
      Get.snackbar('Error', 'No valid audio files found');
    }
  }

  Future<void> playIndex(int index) async {
    if (index < 0 || index >= songs.length) {
      print("Invalid index: $index, songs length: ${songs.length}");
      return;
    }

    final requestId = ++_playRequestId;
    await Future.delayed(const Duration(milliseconds: 100));
    if (requestId != _playRequestId) {
      print("Cancelled play request $requestId");
      return;
    }

    final actualIndex = isShuffling.value ? shuffledOrder[index] : index;
    currentIndex.value = actualIndex;
    isLoading.value = true;

    try {
      final mediaItems = songs.map((s) => s.toMediaItem()).toList();
      await audioHandler.updateQueue(mediaItems, initialIndex: actualIndex);
      await audioHandler.skipToQueueItem(actualIndex);
      await audioHandler.play();

      if (requestId == _playRequestId) {
        isPlaying.value = true;
        isPlayingVN.value = true;
      }
    } catch (e, st) {
      print("Play error: $e\n$st");
      if (requestId == _playRequestId) {
        Get.snackbar(
          'Error',
          'Failed to play song: ${songs[actualIndex].title}',
        );
      }
    } finally {
      if (requestId == _playRequestId) {
        isLoading.value = false;
      }
    }
  }

  Future<void> _setPlaylist() async {
    if (songs.isEmpty) {
      print("No songs to set in playlist");
      Get.snackbar('Error', 'No songs available');
      currentIndex.value = -1;
      return;
    }
    final mediaItems = songs.map((s) => s.toMediaItem()).toList();
    print("Setting playlist with ${mediaItems.length} items");
    await audioHandler.updateQueue(mediaItems, initialIndex: 0);
    originalOrder = List.generate(songs.length, (index) => index);
    shuffledOrder = List.from(originalOrder)..shuffle();
    currentIndex.value = 0;
  }

  void togglePlayPause() async {
    if (songs.isEmpty) {
      Get.snackbar('Error', 'No songs to play');
      return;
    }
    if (audioHandler.playbackState.value.playing) {
      await audioHandler.pause();
    } else {
      await audioHandler.play();
    }
  }

  void next() async {
    if (songs.isEmpty) {
      Get.snackbar('Error', 'No songs to play');
      return;
    }
    isLoading.value = true;
    try {
      final nextIndex =
          isShuffling.value
              ? _getNextShuffledIndex()
              : (currentIndex.value + 1) % songs.length;
      await playIndex(nextIndex);
    } catch (e, st) {
      print("Next song error: $e\n$st");
      Get.snackbar('Error', 'Failed to play next song');
    } finally {
      isLoading.value = false;
    }
  }

  void prev() async {
    if (songs.isEmpty) {
      Get.snackbar('Error', 'No songs to play');
      return;
    }
    isLoading.value = true;
    try {
      final prevIndex =
          isShuffling.value
              ? _getPrevShuffledIndex()
              : (currentIndex.value - 1) < 0
              ? songs.length - 1
              : currentIndex.value - 1;
      await playIndex(prevIndex);
    } catch (e, st) {
      print("Previous song error: $e\n$st");
      Get.snackbar('Error', 'Failed to play previous song');
    } finally {
      isLoading.value = false;
    }
  }

  int _getNextShuffledIndex() {
    final current = shuffledOrder.indexOf(currentIndex.value);
    return shuffledOrder[(current + 1) % shuffledOrder.length];
  }

  int _getPrevShuffledIndex() {
    final current = shuffledOrder.indexOf(currentIndex.value);
    return shuffledOrder[(current - 1) < 0
        ? shuffledOrder.length - 1
        : current - 1];
  }

  void toggleShuffle() async {
    isShuffling.value = !isShuffling.value;
    audioHandler.toggleShuffle();
    if (isShuffling.value) {
      loopMode.value = LoopMode.off;
      shuffledOrder = List.from(originalOrder)..shuffle();
    } else {
      shuffledOrder = List.from(originalOrder);
    }
  }

  void toggleLoopMode() async {
    if (isShuffling.value) {
      isShuffling.value = false;
      audioHandler.toggleShuffle();
      shuffledOrder = List.from(originalOrder);
    }
    audioHandler.toggleRepeat();
    loopMode.value = audioHandler.loopMode;
  }

  void seekTo(Duration pos) => audioHandler.seek(pos);

  @override
  void onClose() {
    audioHandler.dispose();
    super.onClose();
  }
}

/// ---------------- YouTube Controller ----------------
class YouTubeController extends GetxController {
  final YoutubeExplode yt = YoutubeExplode();
  final RxList<Song> trendingSongs = <Song>[].obs;
  final RxList<Song> searchResults = <Song>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetchTrending();
  }

  Future<void> fetchTrending() async {
    try {
      final searchResults = await yt.search.search('trending music');
      final songs =
          searchResults.take(20).map((video) {
            print("Trending song: ${video.title}, URL: ${video.url}");
            return Song(
              title: video.title,
              artist: video.author,
              url: video.url,
              cover: video.thumbnails.mediumResUrl,
              videoId: video.id.value,
            );
          }).toList();
      trendingSongs.assignAll(songs);
    } catch (e) {
      print("YouTube trending error: $e");
      Get.snackbar('Error', 'Failed to fetch trending songs');
    }
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      searchResults.clear();
      return;
    }
    try {
      final results = await yt.search.search('$query music');
      final songs =
          results.take(20).map((video) {
            print("Search result: ${video.title}, URL: ${video.url}");
            return Song(
              title: video.title,
              artist: video.author,
              url: video.url,
              cover: video.thumbnails.mediumResUrl,
              videoId: video.id.value,
            );
          }).toList();
      searchResults.assignAll(songs);
    } catch (e) {
      print("YouTube search error: $e");
      Get.snackbar('Error', 'Failed to search songs');
    }
  }

  @override
  void onClose() {
    yt.close();
    super.onClose();
  }
}

/// ---------------- Global Vars ----------------
const double playerMinHeight = 70;
late double playerMaxHeight;
final ValueNotifier<double> playerExpandProgress = ValueNotifier(
  playerMinHeight,
);
final ValueNotifier<Color> appPrimaryColor = ValueNotifier(Colors.deepPurple);
final ValueNotifier<bool> isPlayingVN = ValueNotifier(false);

/// ---------------- MyApp ----------------
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: appPrimaryColor,
      builder: (context, color, child) {
        final lightScheme = ColorScheme.fromSeed(
          seedColor: color,
          brightness: Brightness.light,
        );
        final darkScheme = ColorScheme.fromSeed(
          seedColor: color,
          brightness: Brightness.dark,
        );

        return GetMaterialApp(
          title: 'Miniplayer Music Player',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightScheme,
            brightness: Brightness.light,
            scaffoldBackgroundColor: lightScheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: lightScheme.surface,
              foregroundColor: lightScheme.onSurface,
              elevation: 0,
              centerTitle: true,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: lightScheme.onSurface,
              ),
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: lightScheme.primary,
              foregroundColor: lightScheme.onPrimary,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            sliderTheme: SliderThemeData(
              activeTrackColor: lightScheme.primary,
              inactiveTrackColor: lightScheme.primaryContainer,
              thumbColor: lightScheme.primary,
              overlayColor: lightScheme.primary.withOpacity(0.1),
              trackHeight: 4,
            ),
            textTheme: const TextTheme().apply(
              bodyColor: Colors.black87,
              displayColor: Colors.black87,
            ),
            cardTheme: CardTheme(
              color: lightScheme.surface,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              elevation: 0,
              backgroundColor: lightScheme.primaryFixedDim.withOpacity(0.2),
              selectedItemColor: lightScheme.primary,
              unselectedItemColor: lightScheme.onSurfaceVariant,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkScheme,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: darkScheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: darkScheme.surface,
              foregroundColor: darkScheme.onSurface,
              elevation: 0,
              centerTitle: true,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: darkScheme.onSurface,
              ),
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: darkScheme.primary,
              foregroundColor: darkScheme.onPrimary,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            sliderTheme: SliderThemeData(
              activeTrackColor: darkScheme.primary,
              inactiveTrackColor: darkScheme.primaryContainer.withOpacity(0.6),
              thumbColor: darkScheme.primary,
              overlayColor: darkScheme.primary.withOpacity(0.2),
              trackHeight: 4,
            ),
            textTheme: const TextTheme().apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            cardTheme: CardTheme(
              color: darkScheme.surface,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              elevation: 0,
              backgroundColor: darkScheme.primaryFixedDim.withOpacity(0.12),
              selectedItemColor: darkScheme.primary,
              unselectedItemColor: darkScheme.onSurfaceVariant,
            ),
          ),
          home: MyHomePage(),
        );
      },
    );
  }
}

/// ---------------- Home ----------------
class MyHomePage extends StatefulWidget {
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  final _pages = [YouTubeHomePage(), LocalSongsPage(), ProfileScreen()];
  final musicCon = Get.find<MusicController>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    playerMaxHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          Navigator(
            key: _navigatorKey,
            onGenerateRoute:
                (_) =>
                    MaterialPageRoute(builder: (_) => _pages[_selectedIndex]),
          ),
          Obx(() {
            // Hide miniplayer if no songs or no valid song is selected
            if (musicCon.songs.isEmpty || musicCon.currentIndex.value < 0) {
              return SizedBox.shrink();
            }
            return Miniplayer(
              minHeight: playerMinHeight,
              maxHeight: playerMaxHeight,
              valueNotifier: musicCon.playerHeight,
              builder: (height, percentage) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  playerExpandProgress.value = height;
                });
                return PlayerUI(percentage: percentage);
              },
            );
          }),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<double>(
        valueListenable: playerExpandProgress,
        builder: (context, height, child) {
          final value = ((height - playerMinHeight) /
                  (playerMaxHeight - playerMinHeight))
              .clamp(0.0, 1.0);
          final translateY = kBottomNavigationBarHeight * value * 0.5;

          return Material(
            child: Align(
              heightFactor: 1 - value,
              child: Transform.translate(
                offset: Offset(0.0, translateY),
                child: BottomNavigationBar(
                  elevation: 0,
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    if (_selectedIndex == index) return;
                    setState(() => _selectedIndex = index);
                    _navigatorKey.currentState!.pushReplacement(
                      CupertinoPageRoute(builder: (_) => _pages[index]),
                    );
                  },
                  selectedItemColor: Theme.of(context).colorScheme.primary,
                  unselectedItemColor:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.08),
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.house_fill),
                      label: "YouTube",
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.music_note_2),
                      label: "Local",
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.person_fill),
                      label: "Profile",
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ---------------- YouTube Home ----------------
class YouTubeHomePage extends StatelessWidget {
  final youtubeCon = Get.put(YouTubeController());
  final musicCon = Get.find<MusicController>();
  final searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("YouTube Trending")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: "Search YouTube...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => youtubeCon.search(v),
            ),
          ),
          Expanded(
            child: Obx(() {
              final list =
                  searchCtrl.text.isEmpty
                      ? youtubeCon.trendingSongs
                      : youtubeCon.searchResults;
              if (list.isEmpty)
                return Center(child: CircularProgressIndicator());
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  final isPlaying =
                      musicCon.currentIndex.value == i &&
                      musicCon.songs.isNotEmpty &&
                      musicCon.songs.contains(s);

                  return ListTile(
                    leading:
                        s.cover != null
                            ? Image.network(
                              s.cover!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            )
                            : Icon(Icons.music_note),
                    title: Text(s.title),
                    subtitle: Text(s.artist),
                    trailing:
                        isPlaying
                            ? Icon(
                              Icons.equalizer,
                              color: Theme.of(context).colorScheme.primary,
                            )
                            : null,
                    onTap: () {
                      musicCon.songs.assignAll(list);
                      musicCon.playIndex(i);
                    },
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Local Songs ----------------
class LocalSongsPage extends StatelessWidget {
  final musicCon = Get.find<MusicController>();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Local Songs")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () => musicCon.scanLocalAudio(),
                child: Text('Scan local audio (pick files)'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SecondScreen()),
                    ),
                child: Text('Open SecondScreen'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed:
                    () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).push(MaterialPageRoute(builder: (_) => ThirdScreen())),
                child: Text('Open ThirdScreen with root Navigator'),
              ),
              const SizedBox(height: 20),
              Text(
                'Pick Theme Color:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 10,
                children:
                    Colors.primaries.map((c) {
                      return GestureDetector(
                        onTap: () => appPrimaryColor.value = c,
                        child: Container(width: 36, height: 36, color: c),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 20),
              Obx(() {
                if (musicCon.songs.isEmpty) return Text("No local songs yet.");
                return ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: musicCon.songs.length,
                  itemBuilder: (_, i) {
                    final s = musicCon.songs[i];
                    final isPlaying = musicCon.currentIndex.value == i;

                    return ListTile(
                      leading: Icon(Icons.music_note),
                      title: Text(s.title),
                      subtitle: Text(s.artist),
                      trailing:
                          isPlaying
                              ? Icon(
                                Icons.equalizer,
                                color: Theme.of(context).colorScheme.primary,
                              )
                              : null,
                      onTap: () => musicCon.playIndex(i),
                    );
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------- Dummy Screens ----------------
class SecondScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("Second Screen")),
    body: Center(child: Text("Second Screen")),
  );
}

class ThirdScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("Third Screen using root Navigator")),
    body: Center(child: Text("Third Screen")),
  );
}

/// ---------------- Profile ----------------
class ProfileScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("Profile")),
    body: Center(child: Text("Profile Page")),
  );
}

/// ---------------- Player UI ----------------
class PlayerUI extends StatelessWidget {
  final double percentage;
  PlayerUI({required this.percentage});
  final musicCon = Get.find<MusicController>();

  @override
  Widget build(BuildContext context) {
    return _buildAnimatedCollapsedRow(context, percentage);
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, "0");
    final min = two(d.inMinutes.remainder(60));
    final sec = two(d.inSeconds.remainder(60));
    return "$min:$sec";
  }

  Widget _buildAnimatedCollapsedRow(BuildContext context, double percentage) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final collapsedSize = screenHeight * 0.06;
    final expandedSize = screenHeight * 0.4;

    final imageSize = lerpDouble(collapsedSize, expandedSize, percentage)!;
    final imageLeft =
        lerpDouble(
          screenWidth * 0.023,
          (screenWidth - expandedSize) / 2,
          percentage,
        )!;
    final imageTop =
        lerpDouble(
          (playerMinHeight - collapsedSize) / 2,
          screenHeight * 0.19,
          percentage,
        )!;
    final imageRadius = lerpDouble(10.0, 20.0, percentage)!;

    final titleSize = lerpDouble(16.0, 24.0, percentage)!;
    final artistSize = lerpDouble(14.0, 18.0, percentage)!;
    final textLeft =
        lerpDouble(screenWidth * 0.178, screenWidth * 0.08, percentage)!;
    final textTop =
        lerpDouble(screenHeight * 0.014, screenHeight * 0.68, percentage)!;

    final collapsedIconSize = screenHeight * 0.035;
    final expandedIconSize = screenHeight * 0.05;
    final iconSize =
        lerpDouble(collapsedIconSize, expandedIconSize, percentage)!;
    final buttonLeft =
        lerpDouble(
          screenWidth - screenWidth * 0.18,
          screenWidth / 2 - iconSize * 0.8,
          percentage,
        )!;
    final buttonTop =
        lerpDouble(screenHeight * 0.012, screenHeight * 0.825, percentage)!;

    final sliderTop =
        lerpDouble(screenHeight * 0.079, screenHeight * 0.768, percentage)!;
    final horizontalPadding = lerpDouble(0, screenWidth * 0.06, percentage)!;

    final bgColor = lerpDouble(0.1, 0.05, percentage)!;
    final bgColorShadow = lerpDouble(0.08, 0.0, percentage)!;
    final bgTopRadius = lerpDouble(20, 0, percentage)!;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryFixedDim.withOpacity(bgColor),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(bgTopRadius),
          topRight: Radius.circular(bgTopRadius),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withOpacity(bgColorShadow),
            spreadRadius: 0,
            blurRadius: 0.5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Expanded controls + slider
          Positioned(
            left: 0,
            right: 0,
            top: sliderTop,
            child: IgnorePointer(
              ignoring: percentage < 0.01,
              child: Column(
                children: [
                  // slider
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Obx(() {
                      final dur = musicCon.duration.value.inMilliseconds;
                      final pos = musicCon.position.value.inMilliseconds;
                      double value = 0.0;
                      if (dur > 0) value = (pos / dur).clamp(0.0, 1.0);
                      return SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 2,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 0,
                          ),
                          trackHeight: lerpDouble(3, 8, percentage)!,
                        ),
                        child: Slider(
                          value: value,
                          onChanged: (v) {
                            final seekMs =
                                ((musicCon.duration.value.inMilliseconds) * v)
                                    .round();
                            musicCon.seekTo(Duration(milliseconds: seekMs));
                          },
                        ),
                      );
                    }),
                  ),
                  Opacity(
                    opacity: percentage,
                    child: Column(
                      children: [
                        SizedBox(height: screenHeight * 0.015),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.075,
                          ),
                          child: Obx(() {
                            final pos = musicCon.position.value;
                            final dur = musicCon.duration.value;
                            String fmt(Duration d) => _formatDuration(d);
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [Text(fmt(pos)), Text(fmt(dur))],
                            );
                          }),
                        ),
                        SizedBox(height: screenHeight * 0.018),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Shuffle button
                            Obx(
                              () => IconButton(
                                icon: Icon(
                                  Icons.shuffle,
                                  size: screenHeight * 0.033,
                                  color:
                                      musicCon.isShuffling.value
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.7),
                                ),
                                onPressed: musicCon.toggleShuffle,
                              ),
                            ),
                            SizedBox(width: 10),
                            IconButton(
                              icon: Icon(
                                Icons.skip_previous,
                                size: screenHeight * 0.042,
                              ),
                              onPressed: musicCon.prev,
                            ),
                            SizedBox(width: screenWidth * 0.24),
                            IconButton(
                              icon: Icon(
                                Icons.skip_next,
                                size: screenHeight * 0.042,
                              ),
                              onPressed: musicCon.next,
                            ),
                            SizedBox(width: 10),
                            // Repeat button
                            Obx(
                              () => IconButton(
                                icon: Icon(
                                  _getRepeatIcon(musicCon.loopMode.value),
                                  size: screenHeight * 0.033,
                                  color:
                                      musicCon.loopMode.value != LoopMode.off
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.7),
                                ),
                                onPressed: musicCon.toggleLoopMode,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Loading indicator or Album art
          Positioned(
            left: imageLeft,
            top: imageTop,
            child: Obx(() {
              if (musicCon.isLoading.value) {
                return Container(
                  height: imageSize,
                  width: imageSize,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(imageRadius),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                );
              }

              final idx = musicCon.currentIndex.value;
              final hasSong =
                  musicCon.songs.isNotEmpty &&
                  idx >= 0 &&
                  idx < musicCon.songs.length;
              final song = hasSong ? musicCon.songs[idx] : null;

              return ClipRRect(
                borderRadius: BorderRadius.circular(imageRadius),
                child: Container(
                  height: imageSize,
                  width: imageSize,
                  color: Theme.of(context).colorScheme.primary,
                  child:
                      song?.cover != null && song!.cover!.isNotEmpty
                          ? Image.network(
                            song.cover!,
                            width: imageSize,
                            height: imageSize,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              print("Image load error: $error");
                              return Icon(
                                Icons.music_note,
                                color: Colors.white,
                                size: imageSize * 0.4,
                              );
                            },
                          )
                          : Icon(
                            Icons.music_note,
                            color: Colors.white,
                            size: imageSize * 0.4,
                          ),
                ),
              );
            }),
          ),
          // Title + Artist
          Positioned(
            left: textLeft,
            top: textTop,
            child: Obx(() {
              if (musicCon.isLoading.value) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onBackground,
                      ),
                    ),
                    SizedBox(
                      height:
                          lerpDouble(screenHeight * 0.004, 0.0, percentage)!,
                    ),
                    Text(
                      'Please wait',
                      style: TextStyle(
                        fontSize: artistSize,
                        color: Theme.of(
                          context,
                        ).colorScheme.onBackground.withOpacity(0.6),
                      ),
                    ),
                  ],
                );
              }

              final idx = musicCon.currentIndex.value;
              final has =
                  musicCon.songs.isNotEmpty &&
                  idx >= 0 &&
                  idx < musicCon.songs.length;
              final title = has ? musicCon.songs[idx].title : 'Song Title';
              final artist = has ? musicCon.songs[idx].artist : 'Artist Name';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onBackground,
                    ),
                  ),
                  SizedBox(
                    height: lerpDouble(screenHeight * 0.004, 0.0, percentage)!,
                  ),
                  Text(
                    artist,
                    style: TextStyle(
                      fontSize: artistSize,
                      color: Theme.of(
                        context,
                      ).colorScheme.onBackground.withOpacity(0.6),
                    ),
                  ),
                ],
              );
            }),
          ),
          // Play button
          Positioned(
            left: buttonLeft,
            top: buttonTop,
            child: ValueListenableBuilder<bool>(
              valueListenable: isPlayingVN,
              builder: (context, playing, _) {
                return SizedBox(
                  height: iconSize * 1.65,
                  width: iconSize * 1.65,
                  child: FloatingActionButton(
                    elevation: 0,
                    onPressed: () {
                      musicCon.togglePlayPause();
                    },
                    shape:
                        playing
                            ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            )
                            : const CircleBorder(),
                    child: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      size: iconSize * 0.8,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getRepeatIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return Icons.repeat;
      case LoopMode.one:
        return Icons.repeat_one;
      case LoopMode.all:
        return Icons.repeat;
    }
  }
}
