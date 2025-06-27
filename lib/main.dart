import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/src/audio_services/audio_handler.dart';
import 'package:rhythm/src/components/miniplayer/mini_player.dart';
import 'package:rhythm/src/services/permisson_service.dart';
import 'package:rhythm/src/view/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize AudioHandler first
  final audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.audio',
      androidNotificationChannelName: 'Audio Player',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  
  // Register with GetX
  Get.put<AudioHandler>(audioHandler);
  
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    initialize();
    super.initState();
  }

  initialize() async{
    await PermissionService().checkAndRequestPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Rhythm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SplashScreen(),
      builder: (context, child) {
        return FullScreenBuilder(child: child!);
      },
    );
  }
}


class FullScreenBuilder extends StatefulWidget {
  final Widget child;
  const FullScreenBuilder({super.key, required this.child});
 
  @override
  State<FullScreenBuilder> createState() => _FullScreenBuilderState();
}

class _FullScreenBuilderState extends State<FullScreenBuilder> {
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final granted = await PermissionService().checkPermissionStatus(context, Permission.audio); // or Permission.media, etc.
    if (mounted) setState(() => _hasPermission = granted);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
          children: [
            widget.child,
            if (_hasPermission)
              const DraggableMiniPlayer(),
          ],
        ),
    );
  }
}
