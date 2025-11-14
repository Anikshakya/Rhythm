import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhythm/src/view/main_screen.dart';

class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key});

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen>
    with WidgetsBindingObserver {
  Map<String, PermissionStatus> _statuses = {};
  bool _fromSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _fromSettings) {
      _updateStatuses();
      _fromSettings = false;
    }
  }

  Future<bool> _isAndroid13Plus() async {
    try {
      if (!Platform.isAndroid) return false;
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      return (androidInfo.version.sdkInt) >= 33;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isAndroid11Plus() async {
    try {
      if (!Platform.isAndroid) return false;
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      return (androidInfo.version.sdkInt) >= 30;
    } catch (_) {
      return false;
    }
  }

  // -----------------------------
  // Update all statuses
  // -----------------------------
  Future<void> _updateStatuses() async {
    final isAndroid13Plus = await _isAndroid13Plus();
    final isAndroid11Plus = await _isAndroid11Plus();

    PermissionStatus audioStatus =
        isAndroid13Plus
            ? await Permission.audio.status
            : PermissionStatus.granted;
    PermissionStatus storageStatus =
        isAndroid13Plus
            ? PermissionStatus.granted
            : await Permission.storage.status;
    PermissionStatus manageStatus =
        isAndroid11Plus
            ? await Permission.manageExternalStorage.status
            : PermissionStatus.granted;
    PermissionStatus notificationStatus = await Permission.notification.status;

    setState(() {
      _statuses = {
        'audio': audioStatus,
        'storage': storageStatus,
        'manage': manageStatus,
        'notification': notificationStatus,
      };
    });
  }

  // -----------------------------
  // Request all permissions
  // -----------------------------
  Future<void> _requestPermissions() async {
    final isAndroid13Plus = await _isAndroid13Plus();
    final isAndroid11Plus = await _isAndroid11Plus();

    final List<Permission> requestList = [];

    if (isAndroid13Plus) requestList.add(Permission.audio);
    if (!isAndroid13Plus) requestList.add(Permission.storage);
    if (isAndroid11Plus) requestList.add(Permission.manageExternalStorage);
    requestList.add(Permission.notification);

    final results = await requestList.request();

    final needSettings = results.values.any((s) => s.isPermanentlyDenied);

    await _updateStatuses();

    if (needSettings) {
      _showOpenSettingsDialog();
    } else if (!_canProceed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please grant the required permissions to continue.'),
        ),
      );
    }
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Permissions Required'),
            content: const Text(
              'Some permissions are permanently denied. Please enable them from Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  _fromSettings = true;
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
    );
  }

  bool get _canProceed {
    return (_statuses['audio']?.isGranted ?? false) &&
        (_statuses['storage']?.isGranted ?? false) &&
        (_statuses['manage']?.isGranted ?? false);
  }

  void _goToNextPage() {
    Get.offAll(() => const MainScreen());
  }

  Widget _buildPermissionCard(
    String key,
    String title,
    String description,
    bool isRequired,
  ) {
    final status = _statuses[key] ?? PermissionStatus.denied;
    final isGranted = status.isGranted;

    IconData icon;
    switch (key) {
      case 'audio':
        icon = Icons.audiotrack;
        break;
      case 'storage':
        icon = Icons.storage;
        break;
      case 'manage':
        icon = Icons.folder;
        break;
      case 'notification':
        icon = Icons.notifications;
        break;
      default:
        icon = Icons.help;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          icon,
          color: isGranted ? Colors.green : Colors.red,
          size: 40,
        ),
        title: Text('$title ${isRequired ? "(Required)" : "(Optional)"}'),
        subtitle: Text(description),
        trailing: Icon(
          isGranted ? Icons.check_circle : Icons.cancel,
          color: isGranted ? Colors.green : Colors.red,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Permissions'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To provide the best experience, we need the following permissions:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: [
                  _buildPermissionCard(
                    'audio',
                    'Audio',
                    'Required to read audio files on Android 13+.',
                    true,
                  ),
                  _buildPermissionCard(
                    'storage',
                    'Storage',
                    'Required to read audio files on Android 12 and below.',
                    true,
                  ),
                  _buildPermissionCard(
                    'manage',
                    'Manage External Storage',
                    'Required for full access to all files on Android 11+.',
                    true,
                  ),
                  _buildPermissionCard(
                    'notification',
                    'Notifications',
                    'Optional, allows timely updates.',
                    false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _canProceed ? _goToNextPage : _requestPermissions,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(_canProceed ? 'Continue' : 'Grant Permissions'),
        ),
      ),
    );
  }
}
