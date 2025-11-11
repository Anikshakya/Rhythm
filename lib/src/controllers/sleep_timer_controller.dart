import 'dart:async';

import 'package:get/get.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/main.dart';

class SleepTimerController extends GetxController {
  Timer? _sleepTimer;
  Timer? _updateTimer;
  Rx<Duration> remaining = Rx(Duration.zero);
  RxBool isActive = RxBool(false);

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _updateTimer?.cancel();

    if (duration == Duration.zero) {
      isActive.value = false;
      remaining.value = Duration.zero;
      return;
    }

    remaining.value = duration;
    isActive.value = true;

    _sleepTimer = Timer(duration, () {
      isActive.value = false;
      remaining.value = Duration.zero;
    });

    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining.value -= const Duration(seconds: 1);
      if (remaining.value <= Duration.zero) {
        timer.cancel();
        remaining.value = Duration.zero;
        (audioHandler as CustomAudioHandler).stop();
        Get.snackbar('Sleep Timer', 'Your Sleep Timer Has Ended');
      }
    });
  }

  @override
  void onClose() {
    _sleepTimer?.cancel();
    _updateTimer?.cancel();
    super.onClose();
  }
}
