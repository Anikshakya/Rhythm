// FullScreenPlayer (stateless)
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/main.dart';
import 'package:rhythm/src/app_config/app_utils.dart';
import 'package:rhythm/src/audio_utils/media_state.dart';
import 'package:rhythm/src/controllers/app_controller.dart';
import 'package:rhythm/src/player/controls.dart';
import 'package:rhythm/src/player/miniplayer.dart';
import 'package:rhythm/src/player/seek_bar.dart';
import 'package:rhythm/src/widgets/sleep_timer_button.dart';
import 'package:rxdart/rxdart.dart' as rx;

class FullScreenPlayer extends StatelessWidget {
  const FullScreenPlayer({super.key});

  void _onBack() {
    Get.find<AppController>().showFullPlayer.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _onBack();
        return;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem.stream,
          builder: (_, snap) {
            final item = snap.data;
            if (item == null) return const SizedBox.shrink();
            final appCtrl = Get.find<AppController>();
            return Stack(
              fit: StackFit.expand,
              children: [
                Obx(
                  () => AnimatedSwitcher(
                    duration: 300.milliseconds,
                    child:
                        item.artUri != null && appCtrl.isPlayerBgImage.value
                            ? ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: 40,
                                sigmaY: 40,
                              ),
                              child: MiniPlayer().art(item, double.infinity),
                            )
                            : const SizedBox.shrink(),
                  ),
                ),
                Container(
                  color: Theme.of(
                    context,
                  ).scaffoldBackgroundColor.withValues(alpha: 0.4),
                ),
                SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 35,
                              ),
                              onPressed: (){
                                Get.back();
                                _onBack();
                              },
                            ),
                            const Spacer(),
                            const SleepTimerButton(),
                          ],
                        ),
                      ),
                      const Expanded(child: PlayerBody()),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// PlayerBody (stateless)
class PlayerBody extends StatelessWidget {
  const PlayerBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem.stream,
      builder: (_, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              StreamBuilder<PlaybackState>(
                stream: audioHandler.playbackState,
                builder: (_, stateSnap) {
                  final playing = stateSnap.data?.playing ?? false;
                  return AnimatedScale(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    scale: playing ? 1.0 : 0.7,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.75,
                      height: MediaQuery.of(context).size.width * 0.75,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 30,
                            spreadRadius: 4,
                            color: theme.shadowColor.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Material(
                          elevation: 10,
                          clipBehavior: Clip.antiAlias,
                          child: MiniPlayer().art(item, double.infinity),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Spacer(),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.artist ?? 'Unknown',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: inactive),
              ),
              const Spacer(),
              StreamBuilder<MediaState>(
                stream: rx.Rx.combineLatest2<MediaItem?, Duration, MediaState>(
                  audioHandler.mediaItem.stream,
                  AudioService.position,
                  (a, b) => MediaState(a, b),
                ),
                builder: (_, ss) {
                  final pos = ss.data?.position ?? Duration.zero;
                  final dur = ss.data?.mediaItem?.duration ?? Duration.zero;
                  return Column(
                    children: [
                      SeekBar(
                        duration: dur,
                        position: pos,
                        activeColor: theme.colorScheme.primary,
                        inactiveColor: inactive.withValues(alpha: 0.3),
                        onChangeEnd: audioHandler.seek,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppUtils.formatDuration(pos),
                              style: TextStyle(color: inactive, fontSize: 12),
                            ),
                            Text(
                              AppUtils.formatDuration(dur),
                              style: TextStyle(color: inactive, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const Spacer(),
              Controls(),
              const Spacer(flex: 2),
            ],
          ),
        );
      },
    );
  }
}
