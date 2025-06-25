import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:rhythm/src/controllers/audio_controller.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final audioController = Get.find<AudioController>();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Rhythm"),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Songs'),
              Tab(text: 'Albums'),
              Tab(text: 'Artists'),
            ],
          ),
        ),
        body: _buildContent(audioController),
        bottomNavigationBar: _buildNowPlayingBar(audioController),
      ),
    );
  }

  Widget _buildContent(AudioController audioController) {
    return Obx(() {
      if (audioController.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      return TabBarView(
        children: [
          _SongsTab(),
          _AlbumsTab(),
          _ArtistsTab(),
        ],
      );
    });
  }

  Widget _buildNowPlayingBar(AudioController audioController) {
    return Obx(() {
      if (audioController.currentQueue.isEmpty) {
        return const SizedBox.shrink();
      }

      return Container(
        height: 70,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: StreamBuilder<MediaItem?>(
          stream: audioController.currentMediaItem,
          builder: (context, snapshot) {
            final mediaItem = snapshot.data;
            if (mediaItem == null) {
              return const SizedBox.shrink();
            }

            return ListTile(
              leading: mediaItem.artUri != null
                  ? Image.network(mediaItem.artUri.toString(), width: 48, height: 48)
                  : const Icon(Icons.music_note),
              title: Text(
                mediaItem.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                mediaItem.artist ?? 'Unknown Artist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      audioController.isPlaying.value ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: () {
                      if (audioController.isPlaying.value) {
                        audioController.pause();
                      } else {
                        audioController.resume();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: audioController.skipToNext,
                  ),
                ],
              ),
              onTap: () {
                // Navigate to now playing screen
                // Get.to(() => NowPlayingScreen());
              },
            );
          },
        ),
      );
    });
  }
}

class _SongsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final audioController = Get.find<AudioController>();
    return Obx(() {
      return ListView.builder(
        itemCount: audioController.songs.length,
        itemBuilder: (context, index) {
          final song = audioController.songs[index];
          final isCurrent = audioController.currentIndex.value == index && 
              audioController.currentQueue.isNotEmpty &&
              audioController.currentQueue[audioController.currentIndex.value].id == song.id;

          return ListTile(
            leading: QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              artworkWidth: 48,
              artworkHeight: 48,
              nullArtworkWidget: const Icon(Icons.music_note, size: 48),
            ),
            title: Text(
              song.title,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent ? Theme.of(context).primaryColor : null,
              ),
            ),
            subtitle: Text(song.artist ?? 'Unknown Artist'),
            trailing: isCurrent
                ? Obx(() {
                    return IconButton(
                      icon: Icon(
                        audioController.isPlaying.value 
                            ? Icons.pause 
                            : Icons.play_arrow,
                        color: Theme.of(context).primaryColor,
                      ),
                      onPressed: () {
                        if (audioController.isPlaying.value) {
                          audioController.pause();
                        } else {
                          audioController.resume();
                        }
                      },
                    );
                  })
                : null,
            onTap: () => audioController.playSongAtIndex(index),
          );
        },
      );
    });
  }
}

class _AlbumsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final audioController = Get.find<AudioController>();
    return ListView.builder(
      itemCount: audioController.albums.length,
      itemBuilder: (context, index) {
        final album = audioController.albums[index];
        return ListTile(
          leading: QueryArtworkWidget(
            id: album.id,
            type: ArtworkType.ALBUM,
            artworkWidth: 48,
            artworkHeight: 48,
            nullArtworkWidget: const Icon(Icons.album, size: 48),
          ),
          title: Text(album.album),
          subtitle: Text('${album.numOfSongs} songs • ${album.artist}'),
          onTap: () => audioController.playAlbum(album),
        );
      },
    );
  }
}

class _ArtistsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final audioController = Get.find<AudioController>();
    return ListView.builder(
      itemCount: audioController.artists.length,
      itemBuilder: (context, index) {
        final artist = audioController.artists[index];
        return ListTile(
          leading: const Icon(Icons.person, size: 48),
          title: Text(artist.artist),
          subtitle: Text('${artist.numberOfAlbums} albums • ${artist.numberOfTracks} songs'),
          onTap: () => audioController.playArtist(artist),
        );
      },
    );
  }
}