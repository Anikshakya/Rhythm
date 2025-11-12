// MainScreen (GetView)
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/main.dart';
import 'package:rhythm/src/app_config/app_utils.dart';
import 'package:rhythm/src/controllers/library_controller.dart';
import 'package:rhythm/src/controllers/player_controller.dart';
import 'package:path/path.dart' as path;
import 'package:rhythm/src/view/album_details.dart';
import 'package:rhythm/src/view/app_drawer.dart';
import 'package:rhythm/src/view/artist_details_screen.dart';
import 'package:rhythm/src/view/folder_details.dart';
import 'package:rhythm/src/view/search_screen.dart';
import 'package:rhythm/src/widgets/online_tile.dart';
import 'package:rhythm/src/widgets/song_tile.dart';

class MainScreen extends GetView<LibraryController> {
  const MainScreen({super.key});

  void _playLocalSongs(List<SongInfo> playlist, int index) {
    (audioHandler as CustomAudioHandler).playLocalPlaylist(playlist, index);
  }

  void _playOnlineSongs(List<MediaItem> items, int index) {
    (audioHandler as CustomAudioHandler).playOnlinePlaylist(items, index);
  }

  Widget _buildTabContent(int index) {
    switch (index) {
      case 0:
        return _buildSongsTab();
      case 1:
        return _buildOnlineTab();
      case 2:
        return _buildArtistsTab();
      case 3:
        return _buildAlbumsTab();
      case 4:
        return _buildFoldersTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSongsTab() {
    if (controller.musicFiles.isEmpty) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: () async {
            await controller.startScan();
          },
          icon: const Icon(Icons.shuffle),
          label: const Text('Scan Songs'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(140, 45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: controller.musicFiles.length,
      padding: const EdgeInsets.only(bottom: 210),
      itemBuilder: (context, index) {
        final song = controller.musicFiles[index];
        final songId = Uri.file(song.file.path).toString();
        return Obx(
          () => SongTile(
            song: song,
            isCurrent: Get.find<PlayerController>().currentId!.value == songId,
            onTap: () => _playLocalSongs(controller.musicFiles, index),
          ),
        );
      },
    );
  }

  Widget _buildOnlineTab() {
    final List<MediaItem> onlineItems = [
      MediaItem(
        id: 'https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3',
        album: "Science Friday",
        title: "A Salute To Head-Scratching Science (Online)",
        artist: "Science Friday and WNYC Studios",
        duration: const Duration(milliseconds: 5739820),
        artUri: Uri.parse(
          'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
        ),
      ),
      MediaItem(
        id: 'https://freepd.com/music/A%20Good%20Bass%20for%20Gambling.mp3',
        title: 'A Good Bass for Gambling',
        artist: 'Kevin MacLeod',
        album: 'FreePD',
        duration: Duration.zero,
      ),
      MediaItem(
        id: 'https://freepd.com/music/A%20Surprising%20Encounter.mp3',
        title: 'A Surprising Encounter',
        artist: 'Kevin MacLeod',
        album: 'FreePD',
        duration: Duration.zero,
      ),
    ];
    if (onlineItems.isEmpty) {
      return const Center(child: Text('No online found.'));
    }
    return ListView.builder(
      itemCount: onlineItems.length,
      padding: const EdgeInsets.only(bottom: 210),
      itemBuilder: (context, index) {
        final item = onlineItems[index];
        return OnlineTile(
          item: item,
          isCurrent: Get.find<PlayerController>().currentId!.value == item.id,
          onTap: () => _playOnlineSongs(onlineItems, index),
        );
      },
    );
  }

  Widget _buildArtistsTab() {
    if (controller.musicFiles.isEmpty) {
      return const Center(child: Text('No local artists found.'));
    }
    final artists = <String, List<SongInfo>>{};
    for (final song in controller.musicFiles) {
      artists.putIfAbsent(song.meta.artist, () => []).add(song);
    }
    final artistList = artists.keys.toList()..sort();
    if (artistList.isEmpty) {
      return const Center(child: Text('No matching artists found.'));
    }
    return ListView.builder(
      itemCount: artistList.length,
      padding: const EdgeInsets.only(bottom: 210),
      itemBuilder: (context, index) {
        final artist = artistList[index];
        final songs = artists[artist]!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            title: Text(artist),
            subtitle: Text('${songs.length} songs'),
            onTap:
                () => Get.to(
                  () => ArtistDetailScreen(artist: artist, songs: songs),
                ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumsTab() {
    if (controller.musicFiles.isEmpty) {
      return const Center(child: Text('No local albums found.'));
    }
    final albums = <String, List<SongInfo>>{};
    for (final song in controller.musicFiles) {
      albums.putIfAbsent(song.meta.album, () => []).add(song);
    }
    final albumList = albums.keys.toList()..sort();
    if (albumList.isEmpty) {
      return const Center(child: Text('No matching albums found.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 210, top: 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: albumList.length,
      itemBuilder: (context, index) {
        final album = albumList[index];
        final songs = albums[album]!;
        final artUri = AppUtils.getAlbumArt(songs);
        final artist = songs.first.meta.artist;
        return GestureDetector(
          onTap:
              () => Get.to(
                () => AlbumDetailScreen(
                  album: album,
                  artist: artist,
                  songs: songs,
                  artUri: artUri,
                ),
              ),
          child: Column(
            children: [
              Container(
                height: 160,
                width: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image:
                      artUri != null
                          ? DecorationImage(
                            image: FileImage(File(artUri.path)),
                            fit: BoxFit.cover,
                          )
                          : null,
                  color: Colors.grey[300],
                ),
                child:
                    artUri == null ? const Icon(Icons.album, size: 60) : null,
              ),
              const SizedBox(height: 8),
              Text(
                album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFoldersTab() {
    if (controller.musicFiles.isEmpty) {
      return const Center(child: Text('No folders found.'));
    }
    final folders = <String, List<SongInfo>>{};
    for (final song in controller.musicFiles) {
      final dir = path.dirname(song.file.path);
      folders.putIfAbsent(dir, () => []).add(song);
    }
    final folderList = folders.keys.toList()..sort();
    if (folderList.isEmpty) {
      return const Center(child: Text('No matching folders found.'));
    }
    return ListView.builder(
      itemCount: folderList.length,
      padding: const EdgeInsets.only(bottom: 210),
      itemBuilder: (context, index) {
        final folder = folderList[index];
        final songs = folders[folder]!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            title: Text(path.basename(folder)),
            subtitle: Text('${songs.length} songs'),
            onTap:
                () => Get.to(
                  () => FolderDetailScreen(folder: folder, songs: songs),
                ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        drawer: AppDrawer(),
        body: Obx(
          () => Stack(
            children: [
              NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return <Widget>[
                    SliverAppBar(
                      floating: true,
                      pinned: true,
                      title: GestureDetector(
                        onTap: () => Get.to(() => SearchScreen()),
                        child: AbsorbPointer(
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              decoration: InputDecoration(
                                hintText:
                                    'Search songs, playlists, and artists',
                                suffixIcon: const Icon(Icons.search_rounded),
                                contentPadding: const EdgeInsets.only(
                                  top: 5,
                                  left: 15,
                                  right: 5,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30.0),
                                ),
                                filled: true,
                                fillColor:
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      bottom: const TabBar(
                        unselectedLabelColor: Colors.grey,
                        tabs: [
                          Tab(text: 'Songs'),
                          Tab(text: 'Online'),
                          Tab(text: 'Artists'),
                          Tab(text: 'Albums'),
                          Tab(text: 'Folders'),
                        ],
                      ),
                    ),
                  ];
                },
                body: Column(
                  children: [
                    Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              controller.message!.value,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: List.generate(
                          5,
                          (index) => _buildTabContent(index),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.isScanning.value)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}