import 'package:flutter/material.dart';
import 'dart:async';
import 'package:get/get.dart';
import 'package:rhythm/src/controllers/audio_controller.dart';

class SleepTimerManager {
  static final SleepTimerManager _instance = SleepTimerManager._internal();
  factory SleepTimerManager() => _instance;
  SleepTimerManager._internal();

  final Rx<SleepTimerConfig> config = SleepTimerConfig().obs;
  Timer? _timer;
  int _playedItemsCount = 0;

  AudioPlayerController get _audioController => Get.find<AudioPlayerController>();

  void startTimer() {
    if (_timer != null) _timer!.cancel();
    
    if (config.value.enableSleepAfterMins) {
      _startMinuteTimer();
    } else if (config.value.enableSleepAfterItems) {
      _playedItemsCount = 0;
      debugPrint("Track-based timer started - will stop after ${config.value.sleepAfterItems} tracks");
    }
  }

  void trackPlayed() {
    if (!config.value.enableSleepAfterItems) return;
    
    _playedItemsCount++;
    debugPrint("Track played: $_playedItemsCount/${config.value.sleepAfterItems}");
    
    if (_playedItemsCount >= config.value.sleepAfterItems) {
      _stopPlayback();
      resetTimer();
    }
  }

  void _startMinuteTimer() {
    _timer = Timer(Duration(minutes: config.value.sleepAfterMin), () {
      debugPrint("Time-based timer completed");
      _stopPlayback();
      resetTimer();
    });
    debugPrint("Time-based timer started - will stop after ${config.value.sleepAfterMin} minutes");
  }

  Future<void> _stopPlayback() async {
    try {
      debugPrint("Attempting to stop playback...");
      _audioController.stopPlaying(); // First try to stop completely
      debugPrint("Playback stopped successfully");
      
      Get.snackbar(
        'Sleep Timer', 
        'Playback stopped',
        snackPosition: SnackPosition.BOTTOM,
        duration: Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint("Error stopping playback: $e");
      try {
        debugPrint("Attempting to pause instead...");
        _audioController.stopPlaying();
        debugPrint("Playback paused successfully");
        
        Get.snackbar(
          'Sleep Timer', 
          'Playback paused',
          snackPosition: SnackPosition.BOTTOM,
          duration: Duration(seconds: 3),
        );
      } catch (e) {
        debugPrint("Error pausing playback: $e");
        Get.snackbar(
          'Error', 
          'Could not stop playback',
          snackPosition: SnackPosition.BOTTOM,
          duration: Duration(seconds: 3),
        );
      }
    }
  }

  void resetTimer() {
    debugPrint("Resetting timer...");
    _timer?.cancel();
    _timer = null;
    _playedItemsCount = 0;
    config.update((val) {
      val?.enableSleepAfterMins = false;
      val?.enableSleepAfterItems = false;
    });
    debugPrint("Timer reset complete");
  }

  void updateConfig({
    bool? enableSleepAfterMins,
    bool? enableSleepAfterItems,
    int? sleepAfterMin,
    int? sleepAfterItems,
  }) {
    debugPrint("Updating timer configuration...");
    config.update((val) {
      if (val != null) {
        val.enableSleepAfterMins = enableSleepAfterMins ?? val.enableSleepAfterMins;
        val.enableSleepAfterItems = enableSleepAfterItems ?? val.enableSleepAfterItems;
        val.sleepAfterMin = sleepAfterMin ?? val.sleepAfterMin;
        val.sleepAfterItems = sleepAfterItems ?? val.sleepAfterItems;
      }
    });
    startTimer();
  }

  static void openSleepTimerDialog(BuildContext context) {
    final manager = SleepTimerManager();
    final minutes = manager.config.value.sleepAfterMin.obs;
    final tracks = manager.config.value.sleepAfterItems.obs;

    Get.dialog(
      CustomBlurryDialog(
        title: 'Sleep Timer',
        icon: Icons.timer,
        normalTitleStyle: true,
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Get.back(),
          ),
          Obx(() {
            final currentConfig = manager.config.value;
            return currentConfig.enableSleepAfterMins || currentConfig.enableSleepAfterItems
                ? TextButton(
                    child: const Text('Stop'),
                    onPressed: () {
                      manager.resetTimer();
                      Get.back();
                      Get.snackbar(
                        'Sleep Timer Stopped',
                        '',
                        snackPosition: SnackPosition.BOTTOM,
                        duration: Duration(seconds: 2),
                      );
                    },
                  )
                : TextButton(
                    child: const Text('Start'),
                    onPressed: () {
                      if (minutes.value > 0 || tracks.value > 0) {
                        manager.updateConfig(
                          enableSleepAfterMins: minutes.value > 0,
                          enableSleepAfterItems: tracks.value > 0,
                          sleepAfterMin: minutes.value,
                          sleepAfterItems: tracks.value,
                        );
                        Get.snackbar(
                          'Sleep Timer Started',
                          minutes.value > 0 
                            ? 'Will stop after ${minutes.value} minutes'
                            : 'Will stop after ${tracks.value} tracks',
                          snackPosition: SnackPosition.BOTTOM,
                          duration: Duration(seconds: 3),
                        );
                      }
                      Get.back();
                    },
                  );
          }),
        ],
        child: Column(
          children: [
            const SizedBox(height: 32.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Minutes wheel
                Obx(() => CustomWheelSlider(
                  value: minutes.value,
                  min: 0,
                  max: 180,
                  onChanged: (val) => minutes.value = val,
                  label: 'Minutes',
                  valueText: '${minutes.value}m',
                )),
                Text('or', style: context.textTheme.bodyMedium),
                // Tracks wheel
                Obx(() => CustomWheelSlider(
                  value: tracks.value,
                  min: 0,
                  max: 100,
                  onChanged: (val) => tracks.value = val,
                  label: 'Tracks',
                  valueText: '${tracks.value} tracks',
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SleepTimerConfig {
  bool enableSleepAfterMins = false;
  bool enableSleepAfterItems = false;
  int sleepAfterMin = 30;
  int sleepAfterItems = 10;
}

class CustomWheelSlider extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String label;
  final String valueText;

  const CustomWheelSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.label,
    required this.valueText,
  });

  @override
  State<CustomWheelSlider> createState() => _CustomWheelSliderState();
}

class _CustomWheelSliderState extends State<CustomWheelSlider> {
  late FixedExtentScrollController _controller;
  late int _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = FixedExtentScrollController(initialItem: widget.value - widget.min);
  }

  @override
  void didUpdateWidget(CustomWheelSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _currentValue) {
      _currentValue = widget.value;
      _controller.jumpToItem(widget.value - widget.min);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: Column(
        children: [
          Text(
            widget.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListWheelScrollView(
              controller: _controller,
              itemExtent: 30,
              perspective: 0.01,
              diameterRatio: 1.5,
              squeeze: 1.0,
              onSelectedItemChanged: (index) {
                final newValue = index + widget.min;
                if (newValue != _currentValue) {
                  _currentValue = newValue;
                  widget.onChanged(newValue);
                }
              },
              children: List.generate(
                widget.max - widget.min + 1,
                (index) => Center(
                  child: Text(
                    '${index + widget.min}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
            ),
          ),
          Text(
            widget.valueText,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class CustomBlurryDialog extends StatelessWidget {
  final IconData? icon;
  final String? title;
  final Widget? titleWidget;
  final Widget? child;
  final List<Widget>? actions;
  final bool normalTitleStyle;
  final double horizontalInset;
  final double verticalInset;
  final EdgeInsetsGeometry contentPadding;
  final ThemeData? theme;

  const CustomBlurryDialog({
    super.key,
    this.child,
    this.title,
    this.titleWidget,
    this.actions,
    this.icon,
    this.normalTitleStyle = false,
    this.horizontalInset = 50.0,
    this.verticalInset = 32.0,
    this.contentPadding = const EdgeInsets.all(14.0),
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final ctxth = theme ?? context.theme;
    final double horizontalMargin = _calculateDialogHorizontalMargin(context, horizontalInset);
    
    return Center(
      child: Dialog(
        backgroundColor: ctxth.dialogTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: verticalInset),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 428.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (titleWidget != null) 
                titleWidget!,
              if (titleWidget == null && title != null)
                normalTitleStyle
                  ? Padding(
                      padding: const EdgeInsets.only(top: 28.0, left: 28.0, right: 24.0),
                      child: Row(
                        children: [
                          if (icon != null) ...[
                            Icon(icon),
                            const SizedBox(width: 10.0),
                          ],
                          Expanded(
                            child: Text(
                              title!,
                              style: ctxth.textTheme.displayLarge,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            Icon(icon),
                            const SizedBox(width: 10.0),
                          ],
                          Expanded(
                            child: Text(
                              title!,
                              style: ctxth.textTheme.displayMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),

              Padding(
                padding: contentPadding,
                child: SizedBox(
                  width: context.width,
                  child: child,
                ),
              ),

              if (actions != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: _buildActionsWithSeparators(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActionsWithSeparators() {
    final List<Widget> actionWidgets = [];
    for (int i = 0; i < actions!.length; i++) {
      actionWidgets.add(actions![i]);
      if (i < actions!.length - 1) {
        actionWidgets.add(const SizedBox(width: 6.0));
      }
    }
    return actionWidgets;
  }

  static double _calculateDialogHorizontalMargin(BuildContext context, double minimum) {
    final screenWidth = context.width;
    final val = (screenWidth / 1000).clamp(0.0, 1.0);
    double percentage = 0.25 * val * val;
    percentage = percentage.clamp(0.0, 0.25);
    return (screenWidth * percentage).clamp(minimum, double.infinity);
  }
}