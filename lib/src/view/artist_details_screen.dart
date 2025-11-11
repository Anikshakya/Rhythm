// ArtistDetailScreen (stateless)
import 'package:flutter/material.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/src/app_config/app_utils.dart';
import 'package:rhythm/src/widgets/detailed_scaffold.dart';

class ArtistDetailScreen extends StatelessWidget {
  final String artist;
  final List<SongInfo> songs;

  const ArtistDetailScreen({
    super.key,
    required this.artist,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    final artUri = AppUtils.getArtistArt(songs);
    return DetailScaffold(
      title: artist,
      subtitle: '${songs.length} tracks • ${songs.length} albums',
      songs: songs,
      artUri: artUri,
      showArtist: false,
    );
  }
}
