import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppSearchController extends GetxController {
  RxString searchQuery = ''.obs;
  final TextEditingController searchTextController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    searchTextController.addListener(() {
      searchQuery.value = searchTextController.text.toLowerCase();
    });
  }

  @override
  void onClose() {
    searchTextController.dispose();
    super.onClose();
  }
}
