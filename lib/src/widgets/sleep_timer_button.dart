// Reusable SleepTimerButton with the provided design
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/src/controllers/sleep_timer_controller.dart';

class SleepTimerButton extends StatelessWidget {
  const SleepTimerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller =
        Get.find<SleepTimerController>(); // Use find; put in init
    final screenHeight = MediaQuery.of(context).size.height;
    const percentage =
        1.0; // Assuming full opacity; adjust if needed from your context

    return Obx(() {
      final hasTimer = controller.isActive.value;

      return Opacity(
        opacity: percentage,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder:
              (child, anim) => ScaleTransition(scale: anim, child: child),
          child:
              hasTimer
                  ? InkWell(
                    onTap: () async {
                      final duration = await _showSleepTimerDialog(context);
                      if (duration != null) {
                        controller.setSleepTimer(duration);
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.moon_zzz_fill,
                            size: screenHeight * 0.022,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(controller.remaining.value),
                            style: TextStyle(
                              fontSize: screenHeight * 0.015,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  : IconButton(
                    onPressed: () async {
                      final duration = await _showSleepTimerDialog(context);
                      if (duration != null) {
                        controller.setSleepTimer(duration);
                      }
                    },
                    icon: Icon(
                      CupertinoIcons.moon_zzz_fill,
                      size: screenHeight * 0.022,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
        ),
      );
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<Duration?> _showSleepTimerDialog(BuildContext parentContext) async {
    final controller = Get.find<SleepTimerController>();
    final List<Map<String, dynamic>> options = [
      {'label': 'Off', 'duration': Duration.zero},
      {'label': '1 minute', 'duration': const Duration(minutes: 1)},
      {'label': '5 minutes', 'duration': const Duration(minutes: 5)},
      {'label': '10 minutes', 'duration': const Duration(minutes: 10)},
      {'label': '20 minutes', 'duration': const Duration(minutes: 20)},
      {'label': '30 minutes', 'duration': const Duration(minutes: 30)},
      {'label': '40 minutes', 'duration': const Duration(minutes: 40)},
      {'label': '50 minutes', 'duration': const Duration(minutes: 50)},
      {'label': '60 minutes', 'duration': const Duration(minutes: 60)},
      {'label': 'Custom', 'duration': null},
    ];

    int selectedIndex = 0;
    if (controller.isActive.value) {
      final currentMin = controller.remaining.value.inMinutes;
      selectedIndex = options.indexWhere(
        (opt) =>
            opt['duration'] != null &&
            (opt['duration'] as Duration).inMinutes == currentMin,
      );
      if (selectedIndex == -1) selectedIndex = options.length - 1;
    }

    return await showCupertinoModalPopup<Duration?>(
      context: parentContext,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext builderContext, StateSetter setState) {
            return Container(
              height: 300,
              color: CupertinoColors.systemBackground.resolveFrom(
                builderContext,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.pop(dialogContext, null),
                      ),
                      CupertinoButton(
                        child: const Text('Set'),
                        onPressed: () async {
                          final opt = options[selectedIndex];
                          Duration? selectedDuration;
                          if (opt['duration'] == null) {
                            selectedDuration = await _showCustomTimerPicker(
                              builderContext,
                            );
                          } else {
                            selectedDuration = opt['duration'] as Duration;
                          }
                          if (selectedDuration != null) {
                            Navigator.pop(dialogContext, selectedDuration);
                          }
                        },
                      ),
                    ],
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 32,
                      scrollController: FixedExtentScrollController(
                        initialItem: selectedIndex,
                      ),
                      onSelectedItemChanged:
                          (int index) => setState(() => selectedIndex = index),
                      children:
                          options
                              .map(
                                (opt) =>
                                    Center(child: Text(opt['label'] as String)),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Duration?> _showCustomTimerPicker(BuildContext parentContext) async {
    final controller = Get.find<SleepTimerController>();
    Duration selectedDuration =
        controller.remaining.value != Duration.zero
            ? controller.remaining.value
            : const Duration(minutes: 30);

    return await showCupertinoModalPopup<Duration?>(
      context: parentContext,
      builder: (BuildContext dialogContext) {
        return Container(
          height: 300,
          color: CupertinoColors.systemBackground.resolveFrom(dialogContext),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.pop(dialogContext, null),
                  ),
                  CupertinoButton(
                    child: const Text('Done'),
                    onPressed:
                        () => Navigator.pop(dialogContext, selectedDuration),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hm,
                  minuteInterval: 1,
                  initialTimerDuration: selectedDuration,
                  onTimerDurationChanged:
                      (Duration value) => selectedDuration = value,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
