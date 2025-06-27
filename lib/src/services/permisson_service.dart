import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  // Request required permissions if they are not already granted
  Future<void> checkAndRequestPermissions() async {
    final permissions = [
      Permission.notification,
      Permission.storage,
      Permission.audio,
    ];

    for (var permission in permissions) {
      var status = await permission.status;
      if (!status.isGranted) {
        await permission.request();
      }
    }
  }

  Future<bool> checkPermissionStatus(BuildContext context, Permission permission) async {
    final status = await permission.status;

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      // Show dialog directing to app settings
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
            'This permission is permanently denied. Please enable it from settings.',
          ),
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
      return false;
    } else {
      final newStatus = await permission.request();
      return newStatus.isGranted;
    }
  }
}


