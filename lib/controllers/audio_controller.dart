import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

class MyAudioController {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  final List<SongModel> songs = <SongModel>[];

  Future<void> fetchSongs() async {
    final isGranted = await _requestPermissions();
    if (!isGranted) return;

    final fetchedSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    songs.clear();
    songs.addAll(fetchedSongs);
  }

  Future<bool> _requestPermissions() async {
    // Check if permissions are already granted
    if (await Permission.audio.isGranted) {
      return true;
    }

    // Request the permission
    final result = await Permission.audio.request();
    return result.isGranted;
  }
}
