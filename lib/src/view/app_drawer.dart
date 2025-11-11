// AppDrawer (stateless)
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/src/controllers/app_controller.dart';
import 'package:rhythm/src/controllers/library_controller.dart';

class AppDrawer extends StatelessWidget {
  AppDrawer({super.key});

  final LibraryController libCtrl = Get.find<LibraryController>();
  final AppController appCtrl = Get.find<AppController>();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Obx(
          () => ListView(
            padding: const EdgeInsets.only(bottom: 210),
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Scan Local Files (Automatic)'),
                onTap: () {
                  Get.back();
                  libCtrl.startScan();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Select Folder to Scan'),
                onTap: () {
                  Get.back();
                  libCtrl.selectAndScanFolder();
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  appCtrl.themeMode.value == ThemeMode.dark
                      ? Icons.light_mode
                      : Icons.dark_mode,
                ),
                title: const Text('Dark Mode'),
                trailing: CupertinoSwitch(
                  value: appCtrl.themeMode.value == ThemeMode.dark,
                  onChanged: (_) => appCtrl.toggleTheme(),
                ),
              ),
              ListTile(
                leading: Icon(Icons.image_outlined),
                title: const Text('Image in Player Background'),
                trailing: CupertinoSwitch(
                  value: appCtrl.isPlayerBgImage.value,
                  onChanged: (value) => appCtrl.tooglePlayerBackGround(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
