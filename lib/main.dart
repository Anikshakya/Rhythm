import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final RxInt currentIndex = (-1).obs;
  final RxBool isPlaying = false.obs;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final RxBool isShuffling = false.obs;
  final Rx<LoopMode> loopMode = LoopMode.off.obs;
  final RxBool isLoading = false.obs;

  // Sleep timer
  Timer? _sleepTimer;
  Rx<Duration?> sleepTimer = Rx<Duration?>(null);

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
      print("Playback state: ${state.processingState}, playing: ${state.playing}");
      isPlaying.value = state.playing;
      isPlayingVN.value = state.playing;
      isLoading.value = state.processingState == AudioProcessingState.loading ||
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
          print("Current media item: ${mediaItem.title}, index: ${currentIndex.value}");
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
    final picked = result.files
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
      currentIndex.value = 0;
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
        Get.snackbar('Error', 'Failed to play song: ${songs[actualIndex].title}');
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
      int nextIndex = currentIndex.value;

      if (loopMode.value == LoopMode.one) {
        nextIndex = currentIndex.value;
      } else if (isShuffling.value) {
        final current = shuffledOrder.indexOf(currentIndex.value);
        final isLast = current == shuffledOrder.length - 1;

        if (loopMode.value == LoopMode.off && isLast) {
          await stop();
          return;
        }

        nextIndex = shuffledOrder[(current + 1) % shuffledOrder.length];
      } else {
        final isLast = currentIndex.value == songs.length - 1;

        if (loopMode.value == LoopMode.off && isLast) {
          await stop();
          return;
        }

        nextIndex = (currentIndex.value + 1) % songs.length;
      }

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
      int prevIndex = currentIndex.value;

      if (loopMode.value == LoopMode.one) {
        prevIndex = currentIndex.value;
      } else if (isShuffling.value) {
        final current = shuffledOrder.indexOf(currentIndex.value);
        final isFirst = current == 0;

        if (loopMode.value == LoopMode.off && isFirst) {
          await stop();
          return;
        }

        prevIndex = shuffledOrder[(current - 1) < 0 ? shuffledOrder.length - 1 : current - 1];
      } else {
        final isFirst = currentIndex.value == 0;

        if (loopMode.value == LoopMode.off && isFirst) {
          await stop();
          return;
        }

        prevIndex = (currentIndex.value - 1) < 0 ? songs.length - 1 : currentIndex.value - 1;
      }

      await playIndex(prevIndex);
    } catch (e, st) {
      print("Previous song error: $e\n$st");
      Get.snackbar('Error', 'Failed to play previous song');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> toggleShuffle() async {
    if (songs.isEmpty) return;

    isShuffling.value = !isShuffling.value;

    try {
      audioHandler.toggleShuffle();
    } catch (_) {}

    if (isShuffling.value) {
      shuffledOrder = List<int>.generate(songs.length, (i) => i);
      shuffledOrder.shuffle();
      final cur = currentIndex.value;
      if (shuffledOrder.contains(cur)) {
        shuffledOrder.remove(cur);
      }
      shuffledOrder.insert(0, cur);
    } else {
      shuffledOrder = List<int>.generate(songs.length, (i) => i);
    }

    print('toggleShuffle -> isShuffling: ${isShuffling.value}');
    print('originalOrder: $originalOrder');
    print('shuffledOrder: $shuffledOrder');
    print('currentIndex: ${currentIndex.value}');
  }

  void toggleLoopMode() {
    if (isShuffling.value) {
      isShuffling.value = false;
      audioHandler.toggleShuffle();
      shuffledOrder = List.from(originalOrder);
    }

    final newMode = audioHandler.toggleRepeat();
    loopMode.value = newMode;
  }

  int getNextShuffledIndex() {
    final current = shuffledOrder.indexOf(currentIndex.value);
    return shuffledOrder[(current + 1) % shuffledOrder.length];
  }

  int getPrevShuffledIndex() {
    final current = shuffledOrder.indexOf(currentIndex.value);
    return shuffledOrder[(current - 1) < 0 ? shuffledOrder.length - 1 : current - 1];
  }

  void seekTo(Duration pos) => audioHandler.seek(pos);

  Future<void> stop() async {
    await audioHandler.stop();
    isPlaying.value = false;
    isPlayingVN.value = false;
    isLoading.value = false;
  }

  Timer? _sleepCountdownTimer;

  void setSleepTimer(Duration? duration) {
    _sleepCountdownTimer?.cancel();
    sleepTimer.value = duration;

    if (duration != null) {
      _sleepCountdownTimer = Timer.periodic(Duration(seconds: 1), (_) {
        if (sleepTimer.value == null || sleepTimer.value!.inSeconds <= 0) {
          stop();
          sleepTimer.value = null;
          _sleepCountdownTimer?.cancel();
          SystemNavigator.pop();
        } else {
          sleepTimer.value = sleepTimer.value! - Duration(seconds: 1);
        }
      });
    }
  }

  void cancelSleepTimer() {
    _sleepCountdownTimer?.cancel();
    sleepTimer.value = null;
  }

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
  String? _trendingPageToken;
  String? _searchPageToken;
  final RxBool isLoadingMore = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchTrending();
  }

  int _trendingOffset = 0; // keeps track of how many songs have been loadedi
  int _searchoffset = 0; // keeps track of how many songs have been loadedi

Future<void> fetchTrending({bool loadMore = false}) async {
  try {
    isLoadingMore.value = loadMore;

    // Increment offset if loading more
    if (loadMore) {
      _trendingOffset += 20;
    } else {
      _trendingOffset = 0;
    }

    final searchResults = await yt.search.search(
      'trending music',
    );

    // Take the next 20 items based on offset
    final songs = searchResults
        .skip(_trendingOffset)
        .take(_trendingOffset)
        .map((video) {
          print("Trending song: ${video.title}, URL: ${video.url}");
          return Song(
            title: video.title,
            artist: video.author,
            url: video.url,
            cover: video.thumbnails.mediumResUrl,
            videoId: video.id.value,
          );
        })
        .toList();

    if (loadMore) {
      trendingSongs.addAll(songs);
    } else {
      trendingSongs.assignAll(songs);
    }
  } catch (e) {
    print("YouTube trending error: $e");
    Get.snackbar('Error', 'Failed to fetch trending songs');
  } finally {
    isLoadingMore.value = false;
  }
}


  Future<void> search(String query, {bool loadMore = false}) async {
    if (query.isEmpty) {
      searchResults.clear();
      _searchPageToken = null;
      return;
    }
    try {
      if (loadMore && _searchPageToken == null) return;
      isLoadingMore.value = loadMore;
      final results = await yt.search.search(
        '$query music',
      );
      final songs = results.take(20).map((video) {
        print("Search result: ${video.title}, URL: ${video.url}");
        return Song(
          title: video.title,
          artist: video.author,
          url: video.url,
          cover: video.thumbnails.mediumResUrl,
          videoId: video.id.value,
        );
      }).toList();
      if (loadMore) {
        searchResults.addAll(songs);
      } else {
        searchResults.assignAll(songs);
      }
      // Pagination not supported: nextPageToken is not available in VideoSearchList.
    } catch (e) {
      print("YouTube search error: $e");
      Get.snackbar('Error', 'Failed to search songs');
    } finally {
      isLoadingMore.value = false;
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
final ValueNotifier<double> playerExpandProgress = ValueNotifier(playerMinHeight);
final ValueNotifier<Color> appPrimaryColor = ValueNotifier(Colors.blue);
final ValueNotifier<bool> isPlayingVN = ValueNotifier(false);

/// ---------------- MyApp ----------------
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: appPrimaryColor,
      builder: (context, color, child) {
        return GetMaterialApp(
          title: 'Rhythm Music',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: color,
              brightness: Brightness.light,
            ),
            fontFamily: 'SF Pro',
            cupertinoOverrideTheme: CupertinoThemeData(
              primaryColor: color,
              scaffoldBackgroundColor: CupertinoColors.systemBackground,
              barBackgroundColor: CupertinoColors.systemBackground.withOpacity(0.8),
              textTheme: CupertinoTextThemeData(
                navTitleTextStyle: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label,
                  fontFamily: 'SF Pro',
                ),
                textStyle: TextStyle(
                  fontSize: 16,
                  color: CupertinoColors.label,
                  fontFamily: 'SF Pro',
                ),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: color,
              brightness: Brightness.dark,
            ),
            fontFamily: 'SF Pro',
            cupertinoOverrideTheme: CupertinoThemeData(
              brightness: Brightness.dark,
              primaryColor: color,
              scaffoldBackgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
              barBackgroundColor: CupertinoColors.systemBackground.resolveFrom(context).withOpacity(0.8),
              textTheme: CupertinoTextThemeData(
                navTitleTextStyle: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label.darkColor,
                  fontFamily: 'SF Pro',
                ),
                textStyle: TextStyle(
                  fontSize: 16,
                  color: CupertinoColors.label.darkColor,
                  fontFamily: 'SF Pro',
                ),
              ),
            ),
          ),
          themeMode: ThemeMode.system,
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
            onGenerateRoute: (_) => CupertinoPageRoute(builder: (_) => _pages[_selectedIndex]),
          ),
          Obx(() {
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
          final value = ((height - playerMinHeight) / (playerMaxHeight - playerMinHeight)).clamp(0.0, 1.0);
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
                  unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
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
class YouTubeHomePage extends StatefulWidget {
  @override
  _YouTubeHomePageState createState() => _YouTubeHomePageState();
}

class _YouTubeHomePageState extends State<YouTubeHomePage> {
  final youtubeCon = Get.put(YouTubeController());
  final musicCon = Get.find<MusicController>();
  final searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100 &&
          !youtubeCon.isLoadingMore.value) {
        if (searchCtrl.text.isEmpty) {
          youtubeCon.fetchTrending(loadMore: true);
        } else {
          youtubeCon.search(searchCtrl.text, loadMore: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = musicCon.songs.isNotEmpty && musicCon.currentIndex.value >= 0
        ? playerMinHeight + kBottomNavigationBarHeight
        : kBottomNavigationBarHeight;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          "Discover",
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
        border: null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: CupertinoSearchTextField(
                  controller: searchCtrl,
                  placeholder: "Search YouTube Music",
                  style: CupertinoTheme.of(context).textTheme.textStyle,
                  onChanged: (v) => youtubeCon.search(v),
                  prefixInsets: EdgeInsetsDirectional.fromSTEB(6, 0, 0, 0),
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: CupertinoColors.systemGrey6.resolveFrom(context),
                ),
              ),
            ),
            Obx(() {
              final list = searchCtrl.text.isEmpty ? youtubeCon.trendingSongs : youtubeCon.searchResults;
              return SliverList(
                delegate: SliverChildListDelegate([
                  CupertinoListSection.insetGrouped(
                    header: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        searchCtrl.text.isEmpty ? "Trending Now" : "Search Results",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ),
                    children: list.asMap().entries.map((entry) {
                      final i = entry.key;
                      final s = entry.value;
                      final isPlaying = musicCon.currentIndex.value == i &&
                          musicCon.songs.isNotEmpty &&
                          musicCon.songs.contains(s);

                      return CupertinoListTile(
                        leading: s.cover != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  s.cover!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Icon(
                                    CupertinoIcons.music_note_2,
                                    size: 30,
                                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                                  ),
                                ),
                              )
                            : Icon(
                                CupertinoIcons.music_note_2,
                                size: 30,
                                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                              ),
                        title: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CupertinoTheme.of(context).textTheme.textStyle,
                        ),
                        subtitle: Text(
                          s.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: CupertinoColors.secondaryLabel.resolveFrom(context),
                          ),
                        ),
                        trailing: isPlaying
                            ? Icon(
                                CupertinoIcons.waveform,
                                color: CupertinoTheme.of(context).primaryColor,
                                size: 24,
                              )
                            : null,
                        onTap: () {
                          musicCon.songs.assignAll(list);
                          musicCon.playIndex(i);
                        },
                      );
                    }).toList(),
                  ),
                  if (youtubeCon.isLoadingMore.value)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(child: CupertinoActivityIndicator(radius: 16)),
                    ),
                ]),
              );
            }),

            Obx(() {
              final list =
                  searchCtrl.text.isEmpty
                      ? youtubeCon.trendingSongs
                      : youtubeCon.searchResults;
              if (list.isEmpty && !youtubeCon.isLoadingMore.value) {
                return SliverToBoxAdapter(
                  child: Center(child: CupertinoActivityIndicator(radius: 16)),
                );
              }
              return SliverPadding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                sliver: CupertinoSliverRefreshControl(
                  onRefresh: () async {
                    if (searchCtrl.text.isEmpty) {
                      await youtubeCon.fetchTrending();
                    } else {
                      await youtubeCon.search(searchCtrl.text);
                    }
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// ---------------- Local Songs ----------------
class LocalSongsPage extends StatelessWidget {
  final musicCon = Get.find<MusicController>();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          "My Music",
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
        border: null,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CupertinoButton.filled(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  borderRadius: BorderRadius.circular(10),
                  child: Text(
                    'Scan Local Audio',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => musicCon.scanLocalAudio(),
                ),
                const SizedBox(height: 16),
                CupertinoButton(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  borderRadius: BorderRadius.circular(10),
                  color: CupertinoColors.systemGrey6.resolveFrom(context),
                  child: Text(
                    'Open Second Screen',
                    style: TextStyle(
                      color: CupertinoColors.label.resolveFrom(context),
                      fontSize: 16,
                    ),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => SecondScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                CupertinoButton(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  borderRadius: BorderRadius.circular(10),
                  color: CupertinoColors.systemGrey6.resolveFrom(context),
                  child: Text(
                    'Open Third Screen',
                    style: TextStyle(
                      color: CupertinoColors.label.resolveFrom(context),
                      fontSize: 16,
                    ),
                  ),
                  onPressed: () => Navigator.of(context, rootNavigator: true).push(
                    CupertinoPageRoute(builder: (_) => ThirdScreen()),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Choose Theme Color',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: Colors.primaries.map((c) {
                    return GestureDetector(
                      onTap: () => appPrimaryColor.value = c,
                      child: Container(
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: appPrimaryColor.value == c
                                ? CupertinoColors.white
                                : CupertinoColors.systemGrey4.resolveFrom(context),
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Obx(() {
                  if (musicCon.songs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "No local songs found. Try scanning your device.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    );
                  }
                  return CupertinoListSection.insetGrouped(
                    header: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        "Local Songs",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ),
                    children: musicCon.songs.asMap().entries.map((entry) {
                      final i = entry.key;
                      final s = entry.value;
                      final isPlaying = musicCon.currentIndex.value == i;

                      return CupertinoListTile(
                        leading: Icon(
                          CupertinoIcons.music_note_2,
                          size: 30,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                        title: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CupertinoTheme.of(context).textTheme.textStyle,
                        ),
                        subtitle: Text(
                          s.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: CupertinoColors.secondaryLabel.resolveFrom(context),
                          ),
                        ),
                        trailing: isPlaying
                            ? Icon(
                                CupertinoIcons.waveform,
                                color: CupertinoTheme.of(context).primaryColor,
                                size: 24,
                              )
                            : null,
                        onTap: () => musicCon.playIndex(i),
                      );
                    }).toList(),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------- Dummy Screens ----------------
class SecondScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(
            "Second Screen",
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
          backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
          border: null,
        ),
        child: SafeArea(
          child: Center(
            child: Text(
              "Second Screen",
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      );
}

class ThirdScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(
            "Third Screen",
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
          backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
          border: null,
        ),
        child: SafeArea(
          child: Center(
            child: Text(
              "Third Screen",
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      );
}

/// ---------------- Profile ----------------
class ProfileScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(
            "Profile",
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
          backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
          border: null,
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: CupertinoTheme.of(context).primaryColor,
                child: Icon(
                  CupertinoIcons.person_fill,
                  size: 60,
                  color: CupertinoColors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "User Profile",
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                "Manage your music preferences",
                style: TextStyle(
                  fontSize: 16,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 24),
              CupertinoButton.filled(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                borderRadius: BorderRadius.circular(10),
                child: Text(
                  'Sign Out',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () {
                  Get.snackbar('Sign Out', 'Signed out successfully');
                },
              ),
            ],
          ),
        ),
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
    final imageLeft = lerpDouble(screenWidth * 0.023, (screenWidth - expandedSize) / 2, percentage)!;
    final imageTop = lerpDouble((playerMinHeight - collapsedSize) / 2, screenHeight * 0.19, percentage)!;
    final imageRadius = lerpDouble(10.0, 20.0, percentage)!;

    final titleSize = lerpDouble(16.0, 24.0, percentage)!;
    final titleWidth = lerpDouble(245.0, 320.0, percentage)!;
    final artistSize = lerpDouble(14.0, 18.0, percentage)!;
    final textLeft = lerpDouble(screenWidth * 0.178, screenWidth * 0.08, percentage)!;
    final textTop = lerpDouble(screenHeight * 0.014, screenHeight * 0.68, percentage)!;

    final collapsedIconSize = screenHeight * 0.035;
    final expandedIconSize = screenHeight * 0.05;
    final iconSize = lerpDouble(collapsedIconSize, expandedIconSize, percentage)!;
    final buttonLeft = lerpDouble(screenWidth - screenWidth * 0.18, screenWidth / 2 - iconSize * 0.8, percentage)!;
    final buttonTop = lerpDouble(screenHeight * 0.012, screenHeight * 0.825, percentage)!;

    final sliderTop = lerpDouble(screenHeight * 0.079, screenHeight * 0.768, percentage)!;
    final horizontalPadding = lerpDouble(0, screenWidth * 0.06, percentage)!;

    final bgColor = lerpDouble(0.08, 0.05, percentage)!;
    final bgTopRadius = lerpDouble(20, 0, percentage)!;

    final sleeperTop = lerpDouble(screenHeight * 0.3, screenHeight * 0.94, percentage)!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(bgColor),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(bgTopRadius),
          topRight: Radius.circular(bgTopRadius),
        ),
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
                  // Slider
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Obx(() {
                      final dur = musicCon.duration.value.inMilliseconds;
                      final pos = musicCon.position.value.inMilliseconds;
                      double value = 0.0;
                      if (dur > 0) value = (pos / dur).clamp(0.0, 1.0);
                      return SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 2),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                          trackHeight: lerpDouble(3, 8, percentage)!,
                        ),
                        child: Slider(
                          value: value,
                          onChanged: (v) {
                            final seekMs = ((musicCon.duration.value.inMilliseconds) * v).round();
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
                          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.075),
                          child: Obx(() {
                            final pos = musicCon.position.value;
                            final dur = musicCon.duration.value;
                            String fmt(Duration d) => _formatDuration(d);
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(fmt(pos), style: Theme.of(context).textTheme.bodySmall),
                                Text(fmt(dur), style: Theme.of(context).textTheme.bodySmall),
                              ],
                            );
                          }),
                        ),
                        SizedBox(height: screenHeight * 0.025),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Shuffle button
                            Obx(
                              () => CupertinoButton(
                                padding: EdgeInsets.zero,
                                child: Icon(
                                  CupertinoIcons.shuffle,
                                  size: screenHeight * 0.033,
                                  color: musicCon.isShuffling.value
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                onPressed: musicCon.toggleShuffle,
                              ),
                            ),
                            SizedBox(width: 10),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              child: Icon(
                                CupertinoIcons.backward_end_alt_fill,
                                size: screenHeight * 0.042,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              onPressed: musicCon.prev,
                            ),
                            SizedBox(width: screenWidth * 0.24),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              child: Icon(
                                CupertinoIcons.forward_end_alt_fill,
                                size: screenHeight * 0.042,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              onPressed: musicCon.next,
                            ),
                            SizedBox(width: 10),
                            // Repeat button
                            Obx(
                              () => CupertinoButton(
                                padding: EdgeInsets.zero,
                                child: Icon(
                                  _getRepeatIcon(musicCon.loopMode.value),
                                  size: screenHeight * 0.033,
                                  color: musicCon.loopMode.value != LoopMode.off
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
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
                    child: CupertinoActivityIndicator(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                );
              }

              final idx = musicCon.currentIndex.value;
              final hasSong = musicCon.songs.isNotEmpty && idx >= 0 && idx < musicCon.songs.length;
              final song = hasSong ? musicCon.songs[idx] : null;

              return ClipRRect(
                borderRadius: BorderRadius.circular(imageRadius),
                child: Container(
                  height: imageSize,
                  width: imageSize,
                  color: Theme.of(context).colorScheme.primary,
                  child: song?.cover != null && song!.cover!.isNotEmpty
                      ? Image.network(
                          song.cover!,
                          width: imageSize,
                          height: imageSize,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            print("Image load error: $error");
                            return Icon(
                              CupertinoIcons.music_note_2,
                              color: Theme.of(context).colorScheme.onPrimary,
                              size: imageSize * 0.4,
                            );
                          },
                        )
                      : Icon(
                          CupertinoIcons.music_note_2,
                          color: Theme.of(context).colorScheme.onPrimary,
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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: lerpDouble(screenHeight * 0.004, 0.0, percentage)!),
                    Text(
                      'Please wait',
                      style: TextStyle(
                        fontSize: artistSize,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              }

              final idx = musicCon.currentIndex.value;
              final has = musicCon.songs.isNotEmpty && idx >= 0 && idx < musicCon.songs.length;
              final title = has ? musicCon.songs[idx].title : 'Song Title';
              final artist = has ? musicCon.songs[idx].artist : 'Artist Name';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: titleWidth,
                    child: Text(
                      overflow: TextOverflow.ellipsis,
                      title,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  SizedBox(height: lerpDouble(screenHeight * 0.004, 0.0, percentage)!),
                  Text(
                    artist,
                    style: TextStyle(
                      fontSize: artistSize,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
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
          // Sleep Timer button
          Positioned(
            top: sleeperTop,
            left: 0,
            right: 0,
            child: Obx(() {
              final timer = musicCon.sleepTimer.value;
              final hasTimer = timer != null;

              return Opacity(
                opacity: percentage,
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: hasTimer
                      ? CupertinoButton(
                          key: ValueKey('timer_text'),
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          onPressed: () => showSleepTimerDialog(context),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.moon_zzz_fill,
                                size: screenHeight * 0.022,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                _formatDuration(timer!),
                                style: TextStyle(
                                  fontSize: screenHeight * 0.022,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : CupertinoButton(
                          key: ValueKey('moon_icon'),
                          padding: EdgeInsets.zero,
                          child: Icon(
                            CupertinoIcons.moon_zzz_fill,
                            size: screenHeight * 0.03,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () => showSleepTimerDialog(context),
                        ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  IconData _getRepeatIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return CupertinoIcons.repeat;
      case LoopMode.one:
        return CupertinoIcons.repeat_1;
      case LoopMode.all:
        return CupertinoIcons.repeat;
    }
  }

  void showSleepTimerDialog(BuildContext context) {
    int selectedIndex = 0;

    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text("Sleep Timer"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Choose when playback should stop."),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: CupertinoPicker(
                itemExtent: 32.0,
                onSelectedItemChanged: (int index) {
                  selectedIndex = index;
                },
                children: List<Widget>.generate(13, (int index) {
                  if (index == 0) {
                    return const Center(child: Text('Off'));
                  }
                  final minutes = index * 5;
                  return Center(child: Text('$minutes Minutes'));
                }),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          CupertinoDialogAction(
            onPressed: () {
              if (selectedIndex > 0) {
                final minutes = selectedIndex * 5;
                musicCon.setSleepTimer(Duration(minutes: minutes));
              } else {
                musicCon.setSleepTimer(null);
              }
              Navigator.pop(context);
            },
            isDefaultAction: true,
            child: const Text("Done"),
          ),
        ],
      ),
    );
  }
}