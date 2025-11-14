import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/src/view/main_screen.dart';
import 'package:rhythm/src/view/permission_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkPermissionsAndNavigate();
  }

  // -----------------------------
  // Check all required permissions
  // -----------------------------
  Future<void> _checkPermissionsAndNavigate() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      Permission permissionToCheck;

      if (sdkInt >= 33) {
        // Android 13+
        permissionToCheck = Permission.audio;
      } else if (sdkInt >= 30) {
        // Android 11+
        permissionToCheck = Permission.manageExternalStorage;
      } else {
        // Android 12 and below
        permissionToCheck = Permission.storage;
      }

      var status = await permissionToCheck.status;

      if (status.isGranted) {
        _navigateToMain();
      } else {
        _navigateToPermissionsPage();
      }
    } else if (Platform.isIOS) {
      var status = await Permission.mediaLibrary.status;
      if (status.isGranted) {
        _navigateToMain();
      } else {
        _navigateToPermissionsPage();
      }
    } else {
      // Other platforms
      _navigateToMain();
    }
  }

  void _navigateToMain() {
    Get.offAll(() => const MainScreen());
  }

  void _navigateToPermissionsPage() {
    Get.offAll(() => const PermissionOnboardingScreen());
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
