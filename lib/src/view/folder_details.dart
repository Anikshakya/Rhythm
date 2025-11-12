// FolderDetailScreen (stateless)
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/main.dart';
import 'package:rhythm/src/controllers/player_controller.dart';
import 'package:rhythm/src/widgets/song_tile.dart';
import 'package:path/path.dart' as path;

class FolderDetailScreen extends StatelessWidget {
  final String folder;
  final List<SongInfo> songs;

  const FolderDetailScreen({
    super.key,
    required this.folder,
    required this.songs,
  });

  void _playSongs(int index, {bool shuffle = false}) {
    final handler = audioHandler as CustomAudioHandler;
    if (shuffle) Get.find<PlayerController>().toggleShuffle();
    handler.playLocalPlaylist(songs, index);
  }

  @override
  Widget build(BuildContext context) {
    final playerCtrl = Get.find<PlayerController>();
    return Scaffold(
      appBar: AppBar(title: Text(path.basename(folder))),
      body: Column(
        children: [
          Text(
            '${songs.length} songs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => _playSongs(0),
                child: const Text('Play'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () => _playSongs(0, shuffle: true),
                child: const Text('Shuffle'),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                final songId = Uri.file(song.file.path).toString();
                return Obx(
                  () => SongTile(
                    song: song,
                    isCurrent: playerCtrl.currentId.value == songId,
                    onTap: () => _playSongs(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
