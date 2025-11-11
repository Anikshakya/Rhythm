// Utility class
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';

class AppUtils {
  static String formatDuration(Duration duration) {
    if (duration == Duration.zero) return '--:--';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  static Uri? getAlbumArt(List<SongInfo> songs) {
    if (songs.isEmpty) return null;
    final song = songs.first;
    return song.meta.artUri ??
        (song.meta.albumArt != null
            ? Uri.file(
              '${(getTemporaryDirectory())}/art_${song.file.path.hashCode}.jpg',
            )
            : null);
  }

  static Uri? getArtistArt(List<SongInfo> songs) {
    return getAlbumArt(songs);
  }

  static IconData getProcessingIcon(AudioProcessingState state) {
    return switch (state) {
      AudioProcessingState.loading ||
      AudioProcessingState.buffering => Icons.cached,
      AudioProcessingState.ready => Icons.done,
      AudioProcessingState.completed => Icons.repeat,
      _ => Icons.error,
    };
  }
}