import 'dart:io';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rhythm/src/audio_services/audio_handler.dart';

class AudioController extends GetxController {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final RxList<SongModel> songs = <SongModel>[].obs;
  final RxList<AlbumModel> albums = <AlbumModel>[].obs;
  final RxList<ArtistModel> artists = <ArtistModel>[].obs;
  final RxBool isLoading = false.obs;
  
  MyAudioHandler get audioHandler => Get.find<MyAudioHandler>();

  @override
  void onInit() {
    super.onInit();
    initAudioData();
  }

  Future<void> initAudioData() async {
    await _requestPermissions();
    await fetchAllData();
  }

  Future<void> _requestPermissions() async {
    final storage = await Permission.storage.request();
    final audio = await Permission.audio.request();

    if (!storage.isGranted || !audio.isGranted) {
      throw 'Required permissions not granted';
    }
  }

  Future<void> fetchAllData() async {
    isLoading.value = true;
    try {
      await Future.wait([
        fetchSongs(),
        fetchAlbums(),
        fetchArtists(),
      ]);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchSongs() async {
    final fetchedSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    songs.assignAll(fetchedSongs.where((song) => song.duration != null && song.duration! > 0));
  }

  Future<void> fetchAlbums() async {
    final fetchedAlbums = await _audioQuery.queryAlbums();
    albums.assignAll(fetchedAlbums);
  }

  Future<void> fetchArtists() async {
    final fetchedArtists = await _audioQuery.queryArtists();
    artists.assignAll(fetchedArtists);
  }

  Future<MediaItem> songToMediaItem(SongModel song) async {
    Uri? artUri;

    try {
      final artBytes = await _audioQuery.queryArtwork(song.id, ArtworkType.AUDIO);
      if (artBytes != null) {
        final tempDir = await getTemporaryDirectory();
        final artPath = '${tempDir.path}/${song.id}_art.jpg';
        final file = File(artPath);
        await file.writeAsBytes(artBytes);
        artUri = Uri.file(artPath);
      }
    } catch (_) {}

    return MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist ?? 'Unknown Artist',
      album: song.album ?? 'Unknown Album',
      duration: Duration(milliseconds: song.duration ?? 0),
      // Use content URI directly for playback
      extras: {
        'uri': song.uri ?? song.data, // Use the content URI
        'song_id': song.id,
        'album_id': song.albumId,
        'artist_id': song.artistId,
        'artUri': artUri?.toString(), // Store artwork URI as string
      },
    );
  }

  Future<List<MediaItem>> songsToMediaItems(List<SongModel> songs) async {
    return await Future.wait(songs.map((song) => songToMediaItem(song)));
  }

  Future<void> playSong(SongModel song) async {
    final index = songs.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      await audioHandler.setQueue(songs, startIndex: index);
      await audioHandler.play();
    }
  }

  Future<void> playSongAtIndex(int index) async {
    if (index >= 0 && index < songs.length) {
      await audioHandler.setQueue(songs, startIndex: index);
      await audioHandler.play();
    }
  }

  Future<void> playAlbum(AlbumModel album) async {
    try {
      final albumSongs = songs.where((song) => song.albumId == album.id).toList();
      
      if (albumSongs.isEmpty) {
        throw Exception('No songs found in album');
      }

      await audioHandler.setQueue(albumSongs);
      await audioHandler.play();
      
      Get.snackbar('Playing', 'Album: ${album.album}');
    } catch (e) {
      print('Error playing album: $e');
      Get.snackbar('Error', 'Could not play album: ${album.album}');
    }
  }

  Future<void> playArtist(ArtistModel artist) async {
    try {
      final artistSongs = songs.where((song) => song.artistId == artist.id).toList();
      
      if (artistSongs.isEmpty) {
        throw Exception('No songs found by artist');
      }

      await audioHandler.setQueue(artistSongs);
      await audioHandler.play();
      
      Get.snackbar('Playing', 'Artist: ${artist.artist}');
    } catch (e) {
      print('Error playing artist: $e');
      Get.snackbar('Error', 'Could not play artist: ${artist.artist}');
    }
  }

  Future<void> playPlaylist(List<SongModel> playlist) async {
    await audioHandler.setQueue(playlist);
    await audioHandler.play();
  }

  // Loop control methods
  Future<void> setLoopMode(LoopMode mode) async {
    await audioHandler.setLoopMode(mode);
  }

  Future<void> toggleLoopMode() async {
    final current = audioHandler.currentLoopMode;
    final next = switch(current) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await setLoopMode(next);
  }

  // Shuffle control methods
  Future<void> toggleShuffle() async {
    await audioHandler.toggleShuffle();
  }

  // Add these getters
  LoopMode get currentLoopMode => audioHandler.currentLoopMode;
  bool get isShuffleEnabled => audioHandler.isShuffleEnabled;

  // Control methods that delegate to audio handler
  Future<void> pause() => audioHandler.pause();
  Future<void> resume() => audioHandler.play();
  Future<void> skipToNext() => audioHandler.skipToNext();
  Future<void> skipToPrevious() => audioHandler.skipToPrevious();
  Future<void> seek(Duration position) => audioHandler.seek(position);
  Future<void> stop() => audioHandler.stop();

  // Getters for current state
  RxList<SongModel> get currentQueue => audioHandler.internalQueue;
  RxInt get currentIndex => audioHandler.currentIndex;
  RxBool get isPlaying => audioHandler.isPlaying;
  Stream<Duration> get positionStream => audioHandler.positionStream;
  Stream<Duration?> get durationStream => audioHandler.durationStream;
  Stream<MediaItem?> get currentMediaItem => audioHandler.mediaItem;
}