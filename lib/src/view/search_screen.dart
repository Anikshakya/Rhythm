// SearchScreen (GetView)

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/main.dart';
import 'package:rhythm/src/app_config/app_utils.dart';
import 'package:rhythm/src/controllers/library_controller.dart';
import 'package:rhythm/src/controllers/player_controller.dart';
import 'package:rhythm/src/controllers/search_controller.dart';
import 'package:rhythm/src/view/album_details.dart';
import 'package:rhythm/src/view/artist_details_screen.dart';
import 'package:rhythm/src/view/folder_details.dart';
import 'package:rhythm/src/widgets/online_tile.dart';
import 'package:rhythm/src/widgets/song_tile.dart';

class SearchScreen extends GetView<AppSearchController> {
  SearchScreen({super.key});

  final LibraryController libCtrl = Get.find<LibraryController>();

  void _playLocalSongs(List<SongInfo> playlist, int index) {
    (audioHandler as CustomAudioHandler).playLocalPlaylist(playlist, index);
  }

  void _playOnlineSongs(List<MediaItem> items, int index) {
    (audioHandler as CustomAudioHandler).playOnlinePlaylist(items, index);
    Get.snackbar('Playing', items[index].title);
  }

  Widget _buildSongsTab() {
    final playerCtrl = Get.find<PlayerController>();

    return Obx(() {
      final query = controller.searchQuery.value.toLowerCase();

      final filteredSongs =
          libCtrl.musicFiles.where((song) {
            final lowerTitle = song.meta.title.toLowerCase();
            final lowerArtist = song.meta.artist.toLowerCase();
            final lowerAlbum = song.meta.album.toLowerCase();

            return lowerTitle.contains(query) ||
                lowerArtist.contains(query) ||
                lowerAlbum.contains(query);
          }).toList();

      if (filteredSongs.isEmpty) {
        return const Center(child: Text('No matching songs found.'));
      }

      return ListView.builder(
        itemCount: filteredSongs.length,
        padding: const EdgeInsets.only(bottom: 210),
        itemBuilder: (context, index) {
          final song = filteredSongs[index];
          final songId = Uri.file(song.file.path).toString();

          return Obx(
            () => SongTile(
              song: song,
              isCurrent: playerCtrl.currentId!.value == songId,
              onTap: () => _playLocalSongs(filteredSongs, index),
            ),
          );
        },
      );
    });
  }



  Widget _buildOnlineTab() {
    // Static online items
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
        id:
            'https://www.archive.org/download/pride_and_prejudice_0801_librivox/prideandprejudice_01_austen.mp3',
        album: 'Pride and Prejudice',
        title: 'Chapter 1 - Pride and Prejudice',
        artist: 'Jane Austen',
        duration: const Duration(minutes: 20),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/PrideAndPrejudiceTitlePage.jpg/640px-PrideAndPrejudiceTitlePage.jpg',
        ),
      ),
      MediaItem(
        id:
            'https://www.archive.org/download/dracula_librivox/dracula_01_stoker.mp3',
        album: 'Dracula',
        title: 'Chapter 1 - Dracula',
        artist: 'Bram Stoker',
        duration: const Duration(minutes: 28),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/7/7a/Dracula_1st_ed_cover_reproduction.jpg',
        ),
      ),
      MediaItem(
        id:
            'https://www.archive.org/download/frankenstein_1818_librivox/frankenstein_01_shelley_64kb.mp3',
        album: 'Frankenstein',
        title: 'Letter 1 - Frankenstein',
        artist: 'Mary Shelley',
        duration: const Duration(minutes: 25),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/3/35/Frankenstein_1818_edition_title_page.jpg',
        ),
      ),
      MediaItem(
        id:
            'https://www.archive.org/download/adventures_of_sherlock_holmes_0811_librivox/adventures_sherlockholmes_01_doyle_64kb.mp3',
        album: 'The Adventures of Sherlock Holmes',
        title: 'A Scandal in Bohemia',
        artist: 'Arthur Conan Doyle',
        duration: const Duration(minutes: 33),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/6/6b/Adventures_of_Sherlock_Holmes.jpg',
        ),
      ),
      MediaItem(
        id:
            'https://www.archive.org/download/mobydick_0811_librivox/mobydick_001_melville_64kb.mp3',
        album: 'Moby Dick',
        title: 'Chapter 1 - Loomings',
        artist: 'Herman Melville',
        duration: const Duration(minutes: 23),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/4/41/Moby-Dick_FE_title_page.jpg',
        ),
      ),
      MediaItem(
        id:
            'https://www.archive.org/download/les_miserables_vol1_1201_librivox/lesmiserables_vol1_01_hugo_64kb.mp3',
        album: 'Les Misérables (Vol 1)',
        title: 'Book 1 - Chapter 1',
        artist: 'Victor Hugo',
        duration: const Duration(minutes: 27),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/0/0b/Les_Mis%C3%A9rables_1862.jpg',
        ),
      ),
      MediaItem(
        id:
            'https://www.archive.org/download/warandpeace_01_tolstoy_64kb/warandpeace_01_tolstoy_64kb.mp3',
        album: 'War and Peace',
        title: 'Book 1 - Chapter 1',
        artist: 'Leo Tolstoy',
        duration: const Duration(minutes: 31),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/0/0b/War-and-peace-first-edition.jpg',
        ),
      ),
      MediaItem(
        id:
            'https://www.archive.org/download/great_expectations_0711_librivox/greatexpectations_001_dickens_64kb.mp3',
        album: 'Great Expectations',
        title: 'Chapter 1',
        artist: 'Charles Dickens',
        duration: const Duration(minutes: 21),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/1/1e/Great_Expectations_title_page.jpg',
        ),
      ),
      MediaItem(
        id:
            'https://www.archive.org/download/alice_wonderland_1002_librivox/aliceinwonderland_01_carroll_64kb.mp3',
        album: 'Alice in Wonderland',
        title: 'Down the Rabbit Hole',
        artist: 'Lewis Carroll',
        duration: const Duration(minutes: 17),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/6/6b/Alice_in_Wonderland_cover_1865.jpg',
        ),
      ),
      MediaItem(
        id:
            'https://www.archive.org/download/time_machine_librivox/time_machine_01_wells_64kb.mp3',
        album: 'The Time Machine',
        title: 'Chapter 1 - The Time Traveller',
        artist: 'H. G. Wells',
        duration: const Duration(minutes: 24),
        artUri: Uri.parse(
          'https://upload.wikimedia.org/wikipedia/commons/3/35/The_Time_Machine_%281895%29.djvu',
        ),
      ),
    ];

    return Obx(() {
      final filteredItems =
          onlineItems.where((item) {
            final lowerTitle = item.title.toLowerCase();
            final lowerArtist = (item.artist ?? '').toLowerCase();
            final lowerAlbum = (item.album ?? '').toLowerCase();
            return lowerTitle.contains(controller.searchQuery.value) ||
                lowerArtist.contains(controller.searchQuery.value) ||
                lowerAlbum.contains(controller.searchQuery.value);
          }).toList();
      if (filteredItems.isEmpty) {
        return const Center(child: Text('No matching online found.'));
      }
      return ListView.builder(
        itemCount: filteredItems.length,
        padding: const EdgeInsets.only(bottom: 210),
        itemBuilder: (context, index) {
          final item = filteredItems[index];
          return OnlineTile(
            item: item,
            isCurrent: Get.find<PlayerController>().currentId!.value == item.id,
            onTap: () => _playOnlineSongs(filteredItems, index),
          );
        },
      );
    });
  }

  Widget _buildArtistsTab() {
    return Obx(() {
      final artists = <String, List<SongInfo>>{};
      for (final song in libCtrl.musicFiles) {
        final lowerArtist = song.meta.artist.toLowerCase();
        if (lowerArtist.contains(controller.searchQuery.value) ||
            song.meta.title.toLowerCase().contains(
              controller.searchQuery.value,
            ) ||
            song.meta.album.toLowerCase().contains(
              controller.searchQuery.value,
            )) {
          artists.putIfAbsent(song.meta.artist, () => []).add(song);
        }
      }
      final artistList = artists.keys.toList()..sort();
      if (artistList.isEmpty)
        return const Center(child: Text('No matching artists found.'));
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
    });
  }

  Widget _buildAlbumsTab() {
    return Obx(() {
      final albums = <String, List<SongInfo>>{};
      for (final song in libCtrl.musicFiles) {
        final lowerAlbum = song.meta.album.toLowerCase();
        if (lowerAlbum.contains(controller.searchQuery.value) ||
            song.meta.title.toLowerCase().contains(
              controller.searchQuery.value,
            ) ||
            song.meta.artist.toLowerCase().contains(
              controller.searchQuery.value,
            )) {
          albums.putIfAbsent(song.meta.album, () => []).add(song);
        }
      }
      final albumList = albums.keys.toList()..sort();
      if (albumList.isEmpty)
        return const Center(child: Text('No matching albums found.'));
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
    });
  }

  Widget _buildFoldersTab() {
    return Obx(() {
      final folders = <String, List<SongInfo>>{};
      for (final song in libCtrl.musicFiles) {
        final dir = path.dirname(song.file.path);
        final lowerDir = dir.toLowerCase();
        if (lowerDir.contains(controller.searchQuery.value) ||
            song.meta.title.toLowerCase().contains(
              controller.searchQuery.value,
            ) ||
            song.meta.artist.toLowerCase().contains(
              controller.searchQuery.value,
            ) ||
            song.meta.album.toLowerCase().contains(
              controller.searchQuery.value,
            )) {
          folders.putIfAbsent(dir, () => []).add(song);
        }
      }
      final folderList = folders.keys.toList()..sort();
      if (folderList.isEmpty)
        return const Center(child: Text('No matching folders found.'));
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return <Widget>[
              SliverAppBar(
                floating: true,
                pinned: true,
                title: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: controller.searchTextController,
                    autofocus: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.only(
                        top: 5,
                        left: 15,
                        right: 5,
                      ),
                      hintText: 'Search songs, playlists, and artists',
                      suffixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceVariant,
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
          body: TabBarView(
            children: [
              _buildSongsTab(),
              _buildOnlineTab(),
              _buildArtistsTab(),
              _buildAlbumsTab(),
              _buildFoldersTab(),
            ],
          ),
        ),
      ),
    );
  }
}