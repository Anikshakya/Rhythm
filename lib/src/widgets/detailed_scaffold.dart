// DetailScaffold (stateless)
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/main.dart';
import 'package:rhythm/src/controllers/player_controller.dart';
import 'package:rhythm/src/widgets/custom_image.dart';
import 'package:rhythm/src/widgets/song_tile.dart';

class DetailScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<SongInfo> songs;
  final Uri? artUri;
  final bool showArtist;

  const DetailScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.songs,
    this.artUri,
    this.showArtist = false,
  });

  void _playSongs(int index, {bool shuffle = false}) {
    final handler = audioHandler as CustomAudioHandler;
    if (shuffle) Get.find<PlayerController>().toggleShuffle();
    handler.playLocalPlaylist(songs, index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final playerCtrl = Get.find<PlayerController>();
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              SliverAppBar(
                pinned: true,
                stretch: true,
                elevation: 0,
                expandedHeight: 320,
                backgroundColor: theme.scaffoldBackgroundColor,
                automaticallyImplyLeading: false,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: Get.back,
                ),
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final percent =
                        (constraints.maxHeight - kToolbarHeight) /
                        (320 - kToolbarHeight);
                    return FlexibleSpaceBar(
                      centerTitle: false,
                      titlePadding: const EdgeInsets.symmetric(
                        horizontal: 50,
                        vertical: 12,
                      ),
                      title: Opacity(
                        opacity: 1 - percent.clamp(0.0, 1.0),
                        child: Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomImage(
                            uri: artUri.toString(),
                            fit: BoxFit.cover,
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors:
                                    isDark
                                        ? [
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.9),
                                        ]
                                        : [
                                          Colors.transparent,
                                          Colors.white.withValues(alpha: 0.9),
                                        ],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                bottom: 24,
                              ),
                              child: Opacity(
                                opacity: percent.clamp(0.0, 1.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color:
                                                isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                          ),
                                    ),
                                    if (showArtist) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        subtitle,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              color: (isDark
                                                      ? Colors.white
                                                      : Colors.black)
                                                  .withValues(alpha: 0.8),
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
        body: Obx(
          () => ListView(
            padding: const EdgeInsets.only(bottom: 210),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showArtist)
                      Text(subtitle, style: theme.textTheme.titleLarge),
                    Text(
                      '${songs.length} songs',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 
                          0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _playSongs(0),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(140, 45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _playSongs(0, shuffle: true),
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(140, 45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...List.generate(songs.length, (index) {
                final song = songs[index];
                final songId = Uri.file(song.file.path).toString();
                return SongTile(
                  song: song,
                  isCurrent: playerCtrl.currentId!.value == songId,
                  onTap: () => _playSongs(index),
                  trackNumber: index + 1,
                  showDuration: true,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
