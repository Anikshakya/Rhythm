import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppController extends GetxController {
  Rx<ThemeMode> themeMode = ThemeMode.system.obs;
  RxBool isPlayerBgImage = false.obs;
  RxBool showFullPlayer = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadAppConfig();
  }

  Future<void> _loadAppConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('app_theme');
    final savedPlayerBgState = prefs.getBool('is_player_bg_image');
    themeMode.value =
        savedTheme == 'dark'
            ? ThemeMode.dark
            : savedTheme == 'light'
            ? ThemeMode.light
            : ThemeMode.system;
    isPlayerBgImage.value = savedPlayerBgState ?? false;
  }

  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final newTheme =
        themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    themeMode.value = newTheme;
    await prefs.setString(
      'app_theme',
      newTheme == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  Future<void> tooglePlayerBackGround() async {
    final prefs = await SharedPreferences.getInstance();
    final newState = isPlayerBgImage.value == true ? false : true;
    isPlayerBgImage.value = newState;
    await prefs.setBool('is_player_bg_image', newState == true ? true : false);
  }
}
