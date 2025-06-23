import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:rhythm/controllers/audio_controller.dart';
import 'package:rhythm/src/components/miniplayer/miniplayer_base.dart';
import 'package:rhythm/src/components/miniplayer/miniplayer_controller.dart';

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
  _DraggableMiniPlayerState createState() => _DraggableMiniPlayerState();
}

class _DraggableMiniPlayerState extends State<DraggableMiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final double _minHeight = 80.0;
  late double _maxHeight;
  final MyAudioController _audioController = Get.put(MyAudioController());

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 0.0,
    );
    _maxHeight = 300.0; // Placeholder, updated in didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maxHeight = MediaQuery.of(context).size.height; // Full screen height
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

    return Obx(() {
      final handler = _audioController.audioHandler;
      final currentSong = handler.songQueue.isNotEmpty &&
              handler.currentIndex.value < handler.songQueue.length
          ? handler.songQueue[handler.currentIndex.value]
          : null;

      if (currentSong == null) {
        return const SizedBox.shrink(); // Hide player if no song is playing
      }

      return MiniplayerRaw(
        builder: (maxOffset, bounceUp, bounceDown, topInset, bottomInset,
            rightInset, screenSize, sMaxOffset, p, cp, ip, icp, rp, rcp, qp,
            qcp, bp, bcp, miniplayerbottomnavheight, bottomOffset, navBarHeight) {
          final height = velpy(a: _minHeight, b: _maxHeight, c: cp);
          final borderRadius = BorderRadius.vertical(
            top: Radius.circular((18.0 + (20.0 - 18.0) * cp) - cp * 20),
            bottom: Radius.circular((18.0 + (20.0 - 18.0) * cp) - cp * 20),
          );
          var padding = 10.0 - cp * 10;

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
                        color: Colors.blueGrey[900],
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
                            child: _buildMiniPlayer(currentSong),
                          ),
                          FadeIgnoreTransition(
                            opacity: opacityAnimation,
                            child: _buildExpandedPlayer(
                              currentSong: currentSong,
                              borderRadius: borderRadius,
                            ),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: FadeIgnoreTransition(
                              opacity: opacityAnimation,
                              child: IconButton(
                                icon:
                                    const Icon(Icons.close, color: Colors.white),
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
    });
  }

  Widget _buildMiniPlayer(SongModel currentSong) {
    return Row(
      children: [
        QueryArtworkWidget(
          id: currentSong.id,
          type: ArtworkType.AUDIO,
          artworkWidth: 60,
          artworkHeight: 60,
          artworkBorder: BorderRadius.circular(8),
          nullArtworkWidget: Container(
            width: 60,
            height: 60,
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.music_note, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentSong.title,
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                currentSong.artist ?? "Unknown Artist",
                style: const TextStyle(color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          ),
        StreamBuilder<bool>(
          stream: _audioController.audioHandler.isPlaying.stream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return IconButton(
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: isPlaying
                  ? _audioController.audioHandler.pause
                  : _audioController.audioHandler.play,
            );
          }
        )
      ],
    );
  }

  Widget _buildExpandedPlayer({
    required SongModel currentSong,
    required BorderRadius borderRadius,
  }) {
    return Column(
      children: [
        Expanded(
          child: QueryArtworkWidget(
            id: currentSong.id,
            type: ArtworkType.AUDIO,
            // artworkBorder: BorderRadius.radius(borderRadius.top),
            nullArtworkWidget: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: borderRadius,
              ),
              child: const Center(
                child: Icon(Icons.music_note, size: 100, color: Colors.white),
              ),
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
                  Text(
                    currentSong.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${currentSong.artist ?? 'Unknown Artist'} • ${currentSong.album ?? 'Unknown Album'}",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<Duration>(
                    stream: _audioController.audioHandler.positionStream,
                    builder: (context, positionSnapshot) {
                      final position = positionSnapshot.data ?? Duration.zero;
                      return StreamBuilder<Duration?>(
                        stream: _audioController.audioHandler.durationStream,
                        builder: (context, durationSnapshot) {
                          final duration = durationSnapshot.data ?? Duration.zero;
                          return Column(
                            children: [
                              Slider(
                                value: position.inSeconds.toDouble().clamp(
                                    0.0, duration.inSeconds.toDouble()),
                                max: duration.inSeconds.toDouble(),
                                activeColor: Colors.blue,
                                inactiveColor: Colors.white24,
                                onChanged: (value) =>
                                    _audioController.audioHandler
                                        .seek(Duration(seconds: value.toInt())),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(position),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                  Text(
                                    _formatDuration(duration),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous,
                            color: Colors.white, size: 32),
                        onPressed: _audioController.audioHandler.skipToPrevious,
                      ),
                      StreamBuilder<bool>(
                        stream: _audioController.audioHandler.isPlaying.stream,
                        builder: (context, snapshot) {
                          final isPlaying = snapshot.data ?? false;
                          return IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 40,
                            ),
                            onPressed: isPlaying
                                ? _audioController.audioHandler.pause
                                : _audioController.audioHandler.play,
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next,
                            color: Colors.white, size: 32),
                        onPressed: _audioController.audioHandler.skipToNext,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}