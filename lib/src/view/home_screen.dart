import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:rhythm/src/controllers/audio_controller.dart';
import 'package:rhythm/src/widgets/custom_blurry_container.dart';

class AudioPlayerPage extends StatelessWidget {
  final AudioPlayerController controller = Get.put(AudioPlayerController());

  AudioPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            icon: Icon(Icons.timer_outlined, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => SleepTimerManager.openSleepTimerDialog(context),
          ),
        ],
        title: Obx(() {
          final textStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              );
          if (controller.showAlbumSongs.value && controller.currentAlbum.value != null) {
            return Text(controller.currentAlbum.value!.album, style: textStyle);
          } else if (controller.showArtistSongs.value && controller.currentArtist.value != null) {
            return Text(controller.currentArtist.value!.artist, style: textStyle);
          }
          return Text('Now Playing', style: textStyle);
        }),
        leading: Obx(() {
          if (controller.showAlbumSongs.value || controller.showArtistSongs.value) {
            return IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.onSurface),
              onPressed: () {
                if (controller.showAlbumSongs.value) {
                  controller.backToAlbums();
                } else {
                  controller.backToArtists();
                }
              },
            );
          }
          return SizedBox.shrink();
        }),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return Center(child: CircularProgressIndicator());
        }

        if (controller.showAlbumSongs.value) {
          return _buildAlbumSongsList(context);
        } else if (controller.showArtistSongs.value) {
          return _buildArtistSongsList(context);
        }

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: TabBar(
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  tabs: const [
                    Tab(icon: Icon(Icons.music_note_rounded)),
                    Tab(icon: Icon(Icons.album_rounded)),
                    Tab(icon: Icon(Icons.person_rounded)),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildSongsTab(context),
                    _buildAlbumsTab(context),
                    _buildArtistsTab(context),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
  Widget _buildSongsTab(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: controller.songs.length,
      itemBuilder: (context, index) {
        final song = controller.songs[index];
        return Obx(() {
          final isPlaying = controller.currentMediaItem.value?.id.toString() == song.id.toString() &&
              controller.isPlaying.value;
          return Card(
            elevation: isPlaying ? 4 : 1,
            color: isPlaying 
                ? Theme.of(context).colorScheme.secondaryContainer 
                : Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: _buildAlbumArtwork(song.id, ArtworkType.AUDIO, 48),
              title: Text(
                song.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                      color: isPlaying 
                          ? Theme.of(context).colorScheme.onSecondaryContainer 
                          : Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              subtitle: Text(
                song.artist ?? 'Unknown Artist',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              trailing: isPlaying
                  ? Icon(
                      Icons.graphic_eq_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : Text(
                      _formatDuration(Duration(milliseconds: song.duration ?? 0)),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
              onTap: () => controller.playSong(index),
            ),
          );
        });
      },
    );
  }

  Widget _buildAlbumsTab(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: controller.albums.length,
      itemBuilder: (context, index) {
        final album = controller.albums[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => controller.loadAlbumSongs(album),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildAlbumArtwork(album.id, ArtworkType.ALBUM, double.infinity),
                ),
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.album,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${album.numOfSongs} songs • ${album.artist ?? 'Unknown Artist'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistsTab(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: controller.artists.length,
      itemBuilder: (context, index) {
        final artist = controller.artists[index];
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _buildAlbumArtwork(artist.id, ArtworkType.ARTIST, 48, isCircular: true),
            title: Text(
              artist.artist,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            subtitle: Text(
              '${artist.numberOfAlbums} albums • ${artist.numberOfTracks} songs',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            onTap: () => controller.loadArtistSongs(artist),
          ),
        );
      },
    );
  }

  Widget _buildAlbumSongsList(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _buildAlbumArtwork(
                  controller.currentAlbum.value!.id,
                  ArtworkType.ALBUM,
                  250,
                  borderRadius: 24,
                ),
                SizedBox(height: 24),
                Text(
                  controller.currentAlbum.value!.album,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  controller.currentAlbum.value!.artist ?? 'Unknown Artist',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      icon: Icon(Icons.shuffle_rounded),
                      label: Text('Shuffle'),
                      onPressed: () {
                        controller.isShuffleEnabled.value = true;
                        controller.playAlbum(0);
                      },
                    ),
                    SizedBox(width: 16),
                    FilledButton.icon(
                      icon: Icon(Icons.play_arrow_rounded),
                      label: Text('Play All'),
                      onPressed: () {
                        controller.isShuffleEnabled.value = false;
                        controller.playAlbum(0);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final mediaItem = controller.currentAlbumSongs[index];
              return Obx(() {
                final isPlaying = controller.currentMediaItem.value?.id.toString() == mediaItem.id.toString() &&
                    controller.isPlaying.value;
                return Card(
                  elevation: isPlaying ? 4 : 1,
                  color: isPlaying 
                      ? Theme.of(context).colorScheme.secondaryContainer 
                      : Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: _buildAlbumArtwork(mediaItem.id, ArtworkType.AUDIO, 48),
                    title: Text(
                      mediaItem.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                            color: isPlaying 
                                ? Theme.of(context).colorScheme.onSecondaryContainer 
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    subtitle: Text(
                      mediaItem.artist ?? 'Unknown Artist',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    trailing: isPlaying
                        ? Icon(
                            Icons.graphic_eq_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : Text(
                            _formatDuration(mediaItem.duration ?? Duration.zero),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                    onTap: () => controller.playAlbum(index),
                  ),
                );
              });
            },
            childCount: controller.currentAlbumSongs.length,
          ),
        ),
      ],
    );
  }

  Widget _buildArtistSongsList(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _buildAlbumArtwork(
                  controller.currentArtist.value!.id,
                  ArtworkType.ARTIST,
                  120,
                  isCircular: true,
                ),
                SizedBox(height: 24),
                Text(
                  controller.currentArtist.value!.artist,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  '${controller.currentArtist.value!.numberOfTracks} songs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      icon: Icon(Icons.shuffle_rounded),
                      label: Text('Shuffle'),
                      onPressed: () {
                        controller.isShuffleEnabled.value = true;
                        controller.playArtist(0);
                      },
                    ),
                    SizedBox(width: 16),
                    FilledButton.icon(
                      icon: Icon(Icons.play_arrow_rounded),
                      label: Text('Play All'),
                      onPressed: () {
                        controller.isShuffleEnabled.value = false;
                        controller.playArtist(0);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final mediaItem = controller.currentArtistSongs[index];
              return Obx(() {
                final isPlaying = controller.currentMediaItem.value?.id.toString() == mediaItem.id.toString() &&
                    controller.isPlaying.value;
                return Card(
                  elevation: isPlaying ? 4 : 1,
                  color: isPlaying 
                      ? Theme.of(context).colorScheme.secondaryContainer 
                      : Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: _buildAlbumArtwork(mediaItem.id, ArtworkType.AUDIO, 48),
                    title: Text(
                      mediaItem.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                            color: isPlaying 
                                ? Theme.of(context).colorScheme.onSecondaryContainer 
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    subtitle: Text(
                      mediaItem.album ?? 'Unknown Album',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    trailing: isPlaying
                        ? Icon(
                            Icons.graphic_eq_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : Text(
                            _formatDuration(mediaItem.duration ?? Duration.zero),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                    onTap: () => controller.playArtist(index),
                  ),
                );
              });
            },
            childCount: controller.currentArtistSongs.length,
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumArtwork(dynamic id, ArtworkType type, double size, {bool isCircular = false, double borderRadius = 8}) {
    return FutureBuilder<Uint8List?>(
      future: controller.audioQuery.queryArtwork(int.parse(id.toString()), type),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: isCircular ? BorderRadius.circular(size / 2) : BorderRadius.circular(borderRadius),
            child: Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: isCircular ? BorderRadius.circular(size / 2) : BorderRadius.circular(borderRadius),
          ),
          child: Icon(
            type == ArtworkType.ALBUM
                ? Icons.album_rounded
                : type == ArtworkType.ARTIST
                    ? Icons.person_rounded
                    : Icons.music_note_rounded,
            size: size / 2,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}