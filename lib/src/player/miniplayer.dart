import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/main.dart';
import 'package:rhythm/src/app_config/app_utils.dart';
import 'package:rhythm/src/audio_utils/media_state.dart';
import 'package:rhythm/src/controllers/app_controller.dart';
import 'package:rhythm/src/player/controls.dart';
import 'package:rhythm/src/player/full_screen_player.dart';
import 'package:rhythm/src/player/seek_bar.dart';
import 'package:rhythm/src/widgets/custom_image.dart';

import 'package:rxdart/rxdart.dart' as rx;

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  Stream<MediaState> get _mediaStateStream =>
      rx.Rx.combineLatest2<MediaItem?, Duration, MediaState>(
        audioHandler.mediaItem.stream,
        AudioService.position,
        (item, pos) => MediaState(item, pos),
      );

  Widget art(MediaItem item, double size) {
    final uri = item.artUri;
    Widget image = Icon(Icons.album, size: size, color: Colors.grey);
    if (uri != null) {
      image = CustomImage(
        uri: uri.toString(),
        height: size,
        width: size,
        fit: BoxFit.cover,
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem.stream,
      builder: (_, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () {
            Get.find<AppController>().showFullPlayer.value = true;
            Get.to(() => const FullScreenPlayer());
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color:
                  theme.brightness == Brightness.dark
                      ? const Color.fromARGB(255, 18, 18, 18).withValues(alpha: 0.92)
                      : theme.cardColor.withValues(alpha: 0.9),
              boxShadow: [
                BoxShadow(
                  color: inactive.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    art(item, 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            item.artist ?? 'Unknown',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: inactive, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    StreamBuilder<AudioProcessingState>(
                      stream:
                          audioHandler.playbackState.stream
                              .map((state) => state.processingState)
                              .distinct(),
                      builder: (context, snapshot) {
                        final state =
                            snapshot.data ?? AudioProcessingState.idle;
                        return Icon(
                          AppUtils.getProcessingIcon(state),
                          size: 20,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                StreamBuilder<MediaState>(
                  stream: _mediaStateStream,
                  builder: (_, ss) {
                    final pos = ss.data?.position ?? Duration.zero;
                    final dur = ss.data?.mediaItem?.duration ?? Duration.zero;
                    return Row(
                      children: [
                        Text(
                          AppUtils.formatDuration(pos),
                          style: TextStyle(color: inactive, fontSize: 10),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SeekBar(
                            duration: dur,
                            position: pos,
                            activeColor: theme.colorScheme.primary,
                            inactiveColor: inactive.withValues(alpha: 0.3),
                            onChangeEnd: audioHandler.seek,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppUtils.formatDuration(dur),
                          style: TextStyle(color: inactive, fontSize: 10),
                        ),
                      ],
                    );
                  },
                ),
                Controls(),
              ],
            ),
          ),
        );
      },
    );
  }
}
