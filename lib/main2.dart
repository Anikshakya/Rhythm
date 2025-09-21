// main.dart
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/miniplayer/miniplayer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Get.put(MusicController());
  Get.put(DeezerController());
  runApp(MyApp());
}

/// ---------------- Song Model ----------------
class Song {
  final String title;
  final String artist;
  final String url;
  final String? cover;
  Song({
    required this.title,
    required this.artist,
    required this.url,
    this.cover,
  });
}

/// ---------------- Music Controller ----------------
class MusicController extends GetxController {
  final AudioPlayer audioPlayer = AudioPlayer();
  final RxList<Song> songs = <Song>[].obs;
  final RxInt currentIndex = 0.obs;
  final RxBool isPlaying = false.obs;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;

  late final ValueNotifier<double> playerHeight;
  final double minHeight = playerMinHeight;

  @override
  void onInit() {
    super.onInit();
    playerHeight = ValueNotifier<double>(playerMinHeight);
    audioPlayer.positionStream.listen((p) => position.value = p);
    audioPlayer.durationStream.listen(
      (d) => duration.value = d ?? Duration.zero,
    );
    audioPlayer.playerStateStream.listen((state) {
      isPlaying.value = state.playing;
      isPlayingVN.value = state.playing;
      if (state.processingState == ProcessingState.completed) next();
    });
  }

  Future<void> scanLocalAudio() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        Get.snackbar('Permission', 'Storage permission required.');
      }
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
    );
    if (result == null) return;
    final picked =
        result.files
            .map(
              (f) => Song(
                title: f.name.split('.').first,
                artist: 'Unknown',
                url: f.path ?? '',
              ),
            )
            .toList();
    if (picked.isNotEmpty) {
      songs.assignAll(picked);
      await _setPlaylist();
    }
  }

  Future<void> playIndex(int index) async {
    if (index < 0 || index >= songs.length) return;
    currentIndex.value = index;
    final src = songs[index].url;
    try {
      if (src.startsWith('http')) {
        await audioPlayer.setUrl(src);
      } else {
        await audioPlayer.setAudioSource(AudioSource.uri(Uri.file(src)));
      }
      await audioPlayer.play();
      isPlaying.value = true;
      isPlayingVN.value = true;
    } catch (e) {
      print("Play error: $e");
    }
  }

  Future<void> _setPlaylist() async {
    final sources =
        songs
            .map(
              (s) => AudioSource.uri(
                s.url.startsWith('http') ? Uri.parse(s.url) : Uri.file(s.url),
              ),
            )
            .toList();
    await audioPlayer.setAudioSource(
      ConcatenatingAudioSource(children: sources),
    );
    currentIndex.value = 0;
  }

  void togglePlayPause() =>
      audioPlayer.playing ? audioPlayer.pause() : audioPlayer.play();
  void next() =>
      songs.isEmpty ? null : playIndex((currentIndex.value + 1) % songs.length);
  void prev() =>
      songs.isEmpty
          ? null
          : playIndex((currentIndex.value - 1 + songs.length) % songs.length);
  void seekTo(Duration pos) => audioPlayer.seek(pos);

  @override
  void onClose() {
    audioPlayer.dispose();
    super.onClose();
  }
}

/// ---------------- Deezer Controller ----------------
class DeezerController extends GetxController {
  final Dio dio = Dio();
  final RxList<Song> trendingSongs = <Song>[].obs;
  final RxList<Song> searchResults = <Song>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetchTrending();
  }

  Future<void> fetchTrending() async {
    try {
      final res = await dio.get("https://api.deezer.com/chart/0/tracks");
      final List data = res.data["data"];
      trendingSongs.assignAll(
        data.map(
          (e) => Song(
            title: e["title"],
            artist: e["artist"]["name"],
            url: e["preview"],
            cover: e["album"]["cover_medium"],
          ),
        ),
      );
    } catch (e) {
      print("Deezer error: $e");
    }
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      searchResults.clear();
      return;
    }
    try {
      final res = await dio.get(
        "https://api.deezer.com/search",
        queryParameters: {"q": query},
      );
      final List data = res.data["data"];
      searchResults.assignAll(
        data.map(
          (e) => Song(
            title: e["title"],
            artist: e["artist"]["name"],
            url: e["preview"],
            cover: e["album"]["cover_medium"],
          ),
        ),
      );
    } catch (e) {
      print("Deezer search error: $e");
    }
  }
}

/// ---------------- Global Vars ----------------
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
const double playerMinHeight = 70;
late double playerMaxHeight;
final ValueNotifier<double> playerExpandProgress = ValueNotifier(
  playerMinHeight,
);
final ValueNotifier<Color> appPrimaryColor = ValueNotifier(Colors.deepPurple);
final ValueNotifier<bool> isPlayingVN = ValueNotifier(true);

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
  final _pages = [DeezerHomePage(), LocalSongsPage(), ProfileScreen()];
  final musicCon = Get.find<MusicController>();

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
          Miniplayer(
            minHeight: playerMinHeight,
            maxHeight: playerMaxHeight,
            valueNotifier: musicCon.playerHeight,
            builder: (height, percentage) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                playerExpandProgress.value = height;
              });
              return PlayerUI(percentage: percentage);
            },
          ),
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
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    if (_selectedIndex == index) return;
                    setState(() => _selectedIndex = index);
                    _navigatorKey.currentState!.pushReplacement(
                      MaterialPageRoute(builder: (_) => _pages[index]),
                    );
                  },
                  selectedItemColor: Theme.of(context).colorScheme.primary,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home),
                      label: "Deezer",
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.music_note),
                      label: "Local",
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person),
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

/// ---------------- Deezer Home ----------------
class DeezerHomePage extends StatelessWidget {
  final deezerCon = Get.find<DeezerController>();
  final musicCon = Get.find<MusicController>();
  final searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Deezer Trending")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: "Search Deezer...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => deezerCon.search(v),
            ),
          ),
          Expanded(
            child: Obx(() {
              final list =
                  searchCtrl.text.isEmpty
                      ? deezerCon.trendingSongs
                      : deezerCon.searchResults;
              if (list.isEmpty)
                return Center(child: CircularProgressIndicator());
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  return ListTile(
                    leading:
                        s.cover != null
                            ? Image.network(s.cover!)
                            : Icon(Icons.music_note),
                    title: Text(s.title),
                    subtitle: Text(s.artist),
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
                    return ListTile(
                      leading: Icon(Icons.music_note),
                      title: Text(s.title),
                      subtitle: Text(s.artist),
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

    final musicCon = Get.find<MusicController>();

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
            offset: const Offset(0, -2), // 👈 negative Y = shadow on top only
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
                            IconButton(
                              icon: Icon(
                                Icons.shuffle,
                                size: screenHeight * 0.033,
                              ),
                              onPressed: () {},
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
                            IconButton(
                              icon: Icon(
                                Icons.repeat,
                                size: screenHeight * 0.033,
                              ),
                              onPressed: () {},
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

          // Album art
          Positioned(
            left: imageLeft,
            top: imageTop,
            child: // Album art
                Positioned(
              left: imageLeft,
              top: imageTop,
              child: Obx(() {
                final idx = musicCon.currentIndex.value;
                final has = musicCon.songs.isNotEmpty;
                final cover = has ? musicCon.songs[idx].cover : null;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(imageRadius),
                  child:
                      cover != null
                          ? Image.network(
                            cover,
                            height: imageSize,
                            width: imageSize,
                            fit: BoxFit.cover,
                          )
                          : Container(
                            height: imageSize,
                            width: imageSize,
                            color: Theme.of(context).colorScheme.primary,
                            child: Icon(Icons.music_note, color: Colors.white),
                          ),
                );
              }),
            ),
          ),

          // Title + Artist
          Positioned(
            left: textLeft,
            top: textTop,
            child: Obx(() {
              final idx = musicCon.currentIndex.value;
              final has = musicCon.songs.isNotEmpty;
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
}
