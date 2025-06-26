import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rhythm/src/audio_services/audio_handler.dart';

class AudioPlayerController extends GetxController {
  final OnAudioQuery audioQuery = OnAudioQuery();
  final RxList<SongModel> songs = <SongModel>[].obs;
  final RxList<AlbumModel> albums = <AlbumModel>[].obs;
  final RxList<ArtistModel> artists = <ArtistModel>[].obs;
  final RxList<MediaItem> mediaItems = <MediaItem>[].obs;
  final Rxn<MediaItem> currentMediaItem = Rxn<MediaItem>();
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final RxBool isPlaying = false.obs;
  final RxBool isLoading = true.obs;
  final RxBool isShuffleEnabled = false.obs;
  final Rx<LoopMode> loopMode = LoopMode.off.obs;
  final RxInt currentTabIndex = 0.obs; // 0: Songs, 1: Albums, 2: Artists
  final RxBool showAlbumSongs = false.obs;
  final RxBool showArtistSongs = false.obs;
  final RxList<MediaItem> currentAlbumSongs = <MediaItem>[].obs;
  final RxList<MediaItem> currentArtistSongs = <MediaItem>[].obs;
  final Rxn<AlbumModel> currentAlbum = Rxn<AlbumModel>();
  final Rxn<ArtistModel> currentArtist = Rxn<ArtistModel>();

  AudioHandler get audioHandler => Get.find<AudioHandler>();

  @override
  void onInit() {
    super.onInit();
    fetchMedia();
    _setupAudioHandlerListeners();
  }

  Future<void> fetchMedia() async {
    try {
      isLoading.value = true;
      
      // Fetch all data in parallel
      final results = await Future.wait([
        audioQuery.querySongs(
          sortType: SongSortType.DISPLAY_NAME,
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        ),
        audioQuery.queryAlbums(),
        audioQuery.queryArtists(),
      ]);
      
      // Process results
      final fetchedSongs = results[0] as List<SongModel>;
      songs.assignAll(fetchedSongs.where((song) => song.duration != null && song.duration! > 0));
      
      albums.assignAll(results[1] as List<AlbumModel>);
      artists.assignAll(results[2] as List<ArtistModel>);
      
      await _convertSongsToMediaItems();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _convertSongsToMediaItems() async {
    mediaItems.assignAll(await Future.wait(songs.map((song) => _songToMediaItem(song))));
  }

  Future<MediaItem> _songToMediaItem(SongModel song) async {
    Uri? artUri;
    try {
      final artBytes = await audioQuery.queryArtwork(song.id, ArtworkType.AUDIO);
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
      artUri: artUri,
      extras: {'uri': song.uri ?? song.data},
    );
  }

  Future<void> loadAlbumSongs(AlbumModel album) async {
    isLoading.value = true;
    try {
      currentAlbum.value = album;
      final albumSongs = await audioQuery.queryAudiosFrom(
        AudiosFromType.ALBUM_ID,
        album.id,
      );
      currentAlbumSongs.assignAll(
        await Future.wait(
          albumSongs.where((song) => song.duration != null && song.duration! > 0)
            .map((song) => _songToMediaItem(song))
        )
      );
      showAlbumSongs.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadArtistSongs(ArtistModel artist) async {
    isLoading.value = true;
    try {
      currentArtist.value = artist;
      final artistSongs = await audioQuery.queryAudiosFrom(
        AudiosFromType.ARTIST_ID,
        artist.id,
      );
      currentArtistSongs.assignAll(
        await Future.wait(
          artistSongs.where((song) => song.duration != null && song.duration! > 0)
            .map((song) => _songToMediaItem(song))
        )
      );
      showArtistSongs.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  void _setupAudioHandlerListeners() {
    final handler = audioHandler as AudioPlayerHandler;
    
    handler.mediaItem.listen((mediaItem) {
      currentMediaItem.value = mediaItem;
    });

    handler.playbackState.listen((state) {
      isPlaying.value = state.playing;
    });

    handler.positionDataStream.listen((positionData) {
      position.value = positionData.position;
      duration.value = positionData.duration;
    });

    isShuffleEnabled.listen((enabled) {
      if (enabled != handler.isShuffleEnabled) {
        handler.toggleShuffle();
      }
    });

    loopMode.listen((mode) {
      if (mode != handler.loopMode) {
        handler.toggleRepeat();
      }
    });
  }

  void playSong(int index) {
    final handler = audioHandler as AudioPlayerHandler;
    handler.updateQueue(mediaItems, initialIndex: index);
  }

  void playAlbum(int index) {
    final handler = audioHandler as AudioPlayerHandler;
    handler.updateQueue(currentAlbumSongs, initialIndex: index);
  }

  void playArtist(int index) {
    final handler = audioHandler as AudioPlayerHandler;
    handler.updateQueue(currentArtistSongs, initialIndex: index);
  }

  void playPause() {
    if (isPlaying.value) {
      audioHandler.pause();
    } else {
      audioHandler.play();
    }
  }

  void stopPlaying(){
    audioHandler.pause();
  }

  void seek(Duration position) {
    audioHandler.seek(position);
  }

  void skipToNext() {
    audioHandler.skipToNext();
  }

  void skipToPrevious() {
    audioHandler.skipToPrevious();
  }

  void toggleShuffle() {
    isShuffleEnabled.toggle();
  }

  void toggleRepeat() {
    loopMode.value = loopMode.value.next;
  }

  void backToAlbums() {
    showAlbumSongs.value = false;
    currentAlbum.value = null;
  }

  void backToArtists() {
    showArtistSongs.value = false;
    currentArtist.value = null;
  }
}

extension on LoopMode {
  LoopMode get next {
    switch (this) {
      case LoopMode.off:
        return LoopMode.one;
      case LoopMode.one:
        return LoopMode.all;
      case LoopMode.all:
        return LoopMode.off;
    }
  }
}