import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/src/view/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndStartTimer();
  }

  void _checkPermissionAndStartTimer() async {
    final permission = Permission.audio;
    var status = await permission.status;

    if (!status.isGranted) {
      // Request permission once
      await permission.request();
    }

    // Start timer to poll every 500ms
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (await permission.isGranted) {
        timer.cancel();
        if (mounted) {
          Get.offAll(() =>  AudioPlayerPage());
        }
      } else if (await permission.isPermanentlyDenied) {
        timer.cancel();
        if (mounted) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Permission Required'),
              content: const Text('Permission is permanently denied. Please open app settings.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    openAppSettings();
                    Navigator.pop(context);
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
      } else {
        await permission.request();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
