// Controls (stateless)
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/main.dart';
import 'package:rhythm/src/controllers/player_controller.dart';

class Controls extends StatelessWidget {
  const Controls({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final primary = theme.colorScheme.primary;
    final playerCtrl = Get.find<PlayerController>();
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (_, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final queueIndex = state?.queueIndex ?? 0;
        final queueLen = audioHandler.queue.value.length;
        final repeat = playerCtrl.repeatMode.value;
        final shuffle = playerCtrl.shuffleMode.value;
        final hasPrev = repeat != AudioServiceRepeatMode.one && queueIndex > 0;
        final hasNext =
            repeat != AudioServiceRepeatMode.one && queueIndex < queueLen - 1;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(Icons.shuffle, color: shuffle ? primary : inactive),
              onPressed: playerCtrl.toggleShuffle,
            ),
            IconButton(
              icon: Icon(
                Icons.skip_previous,
                color: hasPrev ? primary : inactive,
              ),
              onPressed: hasPrev ? audioHandler.skipToPrevious : null,
            ),
            IconButton(
              icon: Icon(
                playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: primary,
              ),
              onPressed: playing ? audioHandler.pause : audioHandler.play,
            ),
            IconButton(
              icon: Icon(Icons.skip_next, color: hasNext ? primary : inactive),
              onPressed: hasNext ? audioHandler.skipToNext : null,
            ),
            IconButton(
              icon: Icon(
                repeat == AudioServiceRepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
                color:
                    repeat != AudioServiceRepeatMode.none ? primary : inactive,
              ),
              onPressed: playerCtrl.cycleRepeat,
            ),
          ],
        );
      },
    );
  }
}
