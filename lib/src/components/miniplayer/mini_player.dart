import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rhythm/src/components/miniplayer/miniplayer_base.dart';
import 'package:rhythm/src/components/miniplayer/miniplayer_controller.dart';
import 'package:rhythm/src/controllers/audio_controller.dart';

class FadeIgnoreTransition extends AnimatedWidget {
  final Animation<double> opacity;
  final Widget child;
  final bool completelyKillWhenPossible;

  const FadeIgnoreTransition({
    super.key,
    required this.opacity,
    required this.child,
    this.completelyKillWhenPossible = false,
  }) : super(listenable: opacity);

  @override
  Widget build(BuildContext context) {
    final opacityValue = opacity.value;
    if (completelyKillWhenPossible && opacityValue == 0.0) {
      return const SizedBox();
    }
    return Opacity(
      opacity: opacityValue.clamp(0.0, 1.0),
      child: child,
    );
  }
}

class DraggableMiniPlayer extends StatefulWidget {
  const DraggableMiniPlayer({super.key});

  @override
  State<DraggableMiniPlayer> createState() => _DraggableMiniPlayerState();
}

class _DraggableMiniPlayerState extends State<DraggableMiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final double _minHeight = 80.0;
  late double _maxHeight;
  final AudioPlayerController controller = Get.put(AudioPlayerController());
  final ColorScheme _colorScheme = ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 0.0,
    );
    _maxHeight = 300.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maxHeight = MediaQuery.of(context).size.height;
    MiniPlayerController.inst.init(_controller, context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _createOpacityAnimation(double Function(double cp) transform) {
    return _controller.drive(
      Animatable.fromCallback(
        (p) {
          final double cp = p.clamp(0.0, 1.0);
          return transform(cp);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opacityAnimation = _createOpacityAnimation((cp) => cp);
    final inverseOpacityAnimation = _createOpacityAnimation((cp) => 1.0 - cp);
    if (controller.currentMediaItem.value == null) return const SizedBox();
    
    return MiniplayerRaw(
      builder: (maxOffset, bounceUp, bounceDown, topInset, bottomInset,
          rightInset, screenSize, sMaxOffset, p, cp, ip, icp, rp, rcp, qp,
          qcp, bp, bcp, miniplayerbottomnavheight, bottomOffset, navBarHeight) {
        final height = lerpDouble(_minHeight, _maxHeight, cp)!;
        final borderRadius = BorderRadius.vertical(
          top: Radius.circular(lerpDouble(18.0, 0.0, cp)!),
          bottom: Radius.circular(lerpDouble(18.0, 0.0, cp)!),
        );
        var padding = lerpDouble(10.0, 0.0, cp)!;

        return SizedBox.expand(
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomOffset,
                child: SafeArea(
                  top: false,
                  child: Container(
                    margin: EdgeInsets.all(padding),
                    height: height,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _colorScheme.surfaceContainerHigh,
                      borderRadius: borderRadius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2 + 0.1 * cp),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        FadeIgnoreTransition(
                          opacity: inverseOpacityAnimation,
                          child: _buildMiniPlayer(controller.currentMediaItem.value!),
                        ),
                        FadeIgnoreTransition(
                          opacity: opacityAnimation,
                          child: _buildExpandedPlayer(
                            borderRadius: borderRadius,
                            mediaItem: controller.currentMediaItem.value!,
                          ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: FadeIgnoreTransition(
                            opacity: opacityAnimation,
                            child: IconButton(
                              icon: Icon(Icons.close, color: _colorScheme.onSurface),
                              onPressed: () => _controller.reverse(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniPlayer(MediaItem mediaItem) {
    return GestureDetector(
      onTap: () => _controller.forward(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: _buildArtworkDecoration(mediaItem),
                color: _colorScheme.surfaceContainerHighest,
              ),
              child: _shouldShowFallbackIcon(mediaItem)
                  ? Icon(Icons.music_note, color: _colorScheme.onSurface)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mediaItem.title,
                    style: TextStyle(
                      color: _colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mediaItem.artist ?? 'Unknown Artist',
                    style: TextStyle(
                      color: _colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Obx(() => IconButton(
              icon: Icon(
                controller.isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: _colorScheme.primary,
                size: 28,
              ),
              onPressed: controller.playPause,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPlayer({
    required BorderRadius borderRadius,
    required MediaItem mediaItem,
  }) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
                image: _buildArtworkDecoration(mediaItem),
                color: _colorScheme.surfaceContainerHighest,
              ),
              child: _shouldShowFallbackIcon(mediaItem)
                  ? Center(
                      child: Icon(
                        Icons.music_note,
                        color: _colorScheme.onSurface,
                        size: 64,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (controller.currentMediaItem.value != null)
                        _buildNowPlaying(controller.currentMediaItem.value!),
                      _buildProgressBar(),
                      _buildControls(),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  DecorationImage? _buildArtworkDecoration(MediaItem mediaItem) {
    try {
      final artUri = mediaItem.artUri;
      if (artUri != null) {
        if (artUri.scheme == 'file') {
          final file = File(artUri.path);
          if (file.existsSync()) {
            return DecorationImage(
              image: FileImage(file),
              fit: BoxFit.cover,
            );
          }
        } else if (artUri.scheme == 'http' || artUri.scheme == 'https') {
          return DecorationImage(
            image: NetworkImage(artUri.toString()),
            fit: BoxFit.cover,
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading artwork: $e');
    }
    return null;
  }

  bool _shouldShowFallbackIcon(MediaItem mediaItem) {
    try {
      final artUri = mediaItem.artUri;
      if (artUri == null) return true;
      
      if (artUri.scheme == 'file') {
        final file = File(artUri.path);
        return !file.existsSync();
      }
      return false;
    } catch (e) {
      debugPrint('Error checking artwork existence: $e');
      return true;
    }
  }

  Widget _buildNowPlaying(MediaItem mediaItem) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Text(
            mediaItem.title, 
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            mediaItem.artist ?? 'Unknown Artist',
            style: TextStyle(
              fontSize: 16,
              color: _colorScheme.onSurface.withOpacity(0.8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            mediaItem.album ?? 'Unknown Album',
            style: TextStyle(
              fontSize: 14,
              color: _colorScheme.onSurface.withOpacity(0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24),
      child: Column(
        children: [
          Obx(() {
            final position = controller.position.value;
            final duration = controller.duration.value;
            return SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: _colorScheme.primary,
                inactiveTrackColor: _colorScheme.onSurface.withOpacity(0.1),
                thumbColor: _colorScheme.primary,
              ),
              child: Slider(
                min: 0,
                max: duration.inMilliseconds.toDouble(),
                value: min(position.inMilliseconds.toDouble(), duration.inMilliseconds.toDouble()),
                onChanged: (value) {
                  controller.position.value = Duration(milliseconds: value.toInt());
                },
                onChangeEnd: (value) {
                  controller.seek(Duration(milliseconds: value.toInt()));
                },
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Obx(() {
              final position = controller.position.value;
              final duration = controller.duration.value;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: TextStyle(
                      color: _colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: _colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.skip_previous, size: 40),
                onPressed: controller.skipToPrevious,
              ),
              Obx(() => IconButton(
                icon: Icon(
                  controller.isPlaying.value ? Icons.pause : Icons.play_arrow, 
                  size: 50
                ),
                onPressed: controller.playPause,
              )),
              IconButton(
                icon: Icon(Icons.skip_next, size: 40),
                onPressed: controller.skipToNext,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Obx(() => IconButton(
                icon: Icon(
                  controller.loopMode.value == LoopMode.one 
                    ? Icons.repeat_one 
                    : Icons.repeat,
                  color: controller.loopMode.value != LoopMode.off 
                    ? Colors.blue 
                    : Colors.grey,
                ),
                onPressed: controller.toggleRepeat,
              )),
              Obx(() => IconButton(
                icon: Icon(Icons.shuffle),
                color: controller.isShuffleEnabled.value 
                  ? Colors.blue 
                  : Colors.grey,
                onPressed: controller.toggleShuffle,
              )),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${twoDigits(seconds)}';
  }
}