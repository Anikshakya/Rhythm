// AlbumDetailScreen (stateless)
import 'package:flutter/material.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/src/widgets/detailed_scaffold.dart';

class AlbumDetailScreen extends StatelessWidget {
  final String album;
  final String artist;
  final List<SongInfo> songs;
  final Uri? artUri;

  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.artist,
    required this.songs,
    this.artUri,
  });

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: album,
      subtitle: artist,
      songs: songs,
      artUri: artUri,
      showArtist: true,
    );
  }
}
