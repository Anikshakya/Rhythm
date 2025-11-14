

// Global audio handler
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/src/app_config/app_theme.dart';
import 'package:rhythm/src/controllers/app_controller.dart';
import 'package:rhythm/src/controllers/library_controller.dart';
import 'package:rhythm/src/controllers/player_controller.dart';
import 'package:rhythm/src/controllers/search_controller.dart';
import 'package:rhythm/src/controllers/sleep_timer_controller.dart';
import 'package:rhythm/src/player/miniplayer.dart';
import 'package:rhythm/src/view/splash_screen.dart';

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
  Get.put(AppSearchController());

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
        home: const SplashScreen(),
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