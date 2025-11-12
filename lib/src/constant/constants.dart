import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

class AppConstant {
  RxList<MediaItem> onlineItems = [
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
    for (int i = 1; i <= 27; i++)
      MediaItem(
        id:
            'https://www.archive.org/download/dracula_librivox/dracula_${i.toString().padLeft(2, '0')}_stoker.mp3',
        album: 'Dracula',
        title: 'Chapter $i - Dracula',
        artist: 'Bram Stoker',
        duration: const Duration(minutes: 28),
        artUri: Uri.parse(
          'https://ia800609.us.archive.org/30/items/dracula_librivox/Dracula_1104.jpg?cnt=0',
        ),
      ),
  ].obs;
}