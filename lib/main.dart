import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_service/audio_service.dart';
import 'package:rhythm/src/audio_services/audio_handler.dart';
import 'package:rhythm/src/components/miniplayer/mini_player.dart';
import 'package:rhythm/src/controllers/audio_controller.dart';
import 'package:rhythm/src/view/home_screen.dart';

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

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Audio Player',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: AudioPlayerPage(),
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
  State<FullScreenBuilder> createState() =>
      _FullScreenBuilderState();
}
 
class _FullScreenBuilderState extends State<FullScreenBuilder> {
  final AudioPlayerController controller = Get.put(AudioPlayerController());
  @override
  void initState() {
    super.initState();
  }
 
  @override
  Widget build(BuildContext context) {
    return Material(
      child: Obx(()=>
        Stack(
          children: [
            widget.child,
            if(controller.currentMediaItem.value != null)
            Positioned.fill(
              child: DraggableMiniPlayer()
            ),
          ],
        ),
      ),
    );
  }
}



