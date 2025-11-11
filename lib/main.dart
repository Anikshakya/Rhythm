

// Global audio handler
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/src/app_config/app_theme.dart';
import 'package:rhythm/src/controllers/app_controller.dart';
import 'package:rhythm/src/controllers/library_controller.dart';
import 'package:rhythm/src/controllers/player_controller.dart';
import 'package:rhythm/src/controllers/sleep_timer_controller.dart';
import 'package:rhythm/src/player/miniplayer.dart';
import 'package:rhythm/src/view/main_screen.dart';

late AudioHandler audioHandler;

// Entry point
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: () => CustomAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.myaudio.channel',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  Get.put(AppController());
  Get.put(PlayerController());
  Get.put(LibraryController());
  Get.put(SleepTimerController());
  Get.put(SearchController());

  final libCtrl = Get.find<LibraryController>();
  final playerCtrl = Get.find<PlayerController>();
  await libCtrl.loadSavedSongs();
  await playerCtrl.loadLastState();

  runApp(const MyApp());
}

// MyApp (stateless)
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = Get.find<AppController>();
    return Obx(
      () => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Rhythm Player',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: appCtrl.themeMode.value,
        home: const MainScreen(),
        builder: (context, child) => GlobalWrapper(child: child!),
      ),
    );
  }
}

// GlobalWrapper (stateless)
class GlobalWrapper extends StatelessWidget {
  final Widget child;

  const GlobalWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final appCtrl = Get.find<AppController>();
    return Material(
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          child,
          Obx(
            () => AnimatedSwitcher(
              duration: 300.milliseconds,
              child:
                  !appCtrl.showFullPlayer.value
                      ? SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: const MiniPlayer(),
                        ),
                      )
                      : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}


// Static online items
final List<MediaItem> onlineItems = [
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
  MediaItem(
    id: 'https://freepd.com/music/A%20Good%20Bass%20for%20Gambling.mp3',
    title: 'A Good Bass for Gambling',
    artist: 'Kevin MacLeod',
    album: 'FreePD',
    duration: Duration.zero,
  ),
  MediaItem(
    id: 'https://freepd.com/music/A%20Surprising%20Encounter.mp3',
    title: 'A Surprising Encounter',
    artist: 'Kevin MacLeod',
    album: 'FreePD',
    duration: Duration.zero,
  ),
];
