// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerController extends GetxController {
  Rx<AudioServiceRepeatMode> repeatMode = AudioServiceRepeatMode.none.obs;
  RxBool shuffleMode = false.obs;
  RxString currentId = "".obs;

  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<List<MediaItem>>? _queueSubscription;

  @override
  void onInit() {
    super.onInit();

    _playbackSubscription = audioHandler.playbackState.stream.listen((state) {
      repeatMode.value = state.repeatMode;
      shuffleMode.value = state.shuffleMode == AudioServiceShuffleMode.all;
    });

    _mediaItemSubscription = audioHandler.mediaItem.stream.listen((item) {
      if (item != null) {
        currentId.value = item.id;
        _saveCurrentState();
      }
    });

    _queueSubscription = audioHandler.queue.stream.listen((queue) {
      if (queue.isNotEmpty) _saveCurrentState();
    });
  }

  @override
  void onClose() {
    _playbackSubscription?.cancel();
    _mediaItemSubscription?.cancel();
    _queueSubscription?.cancel();
    super.onClose();
  }

  Future<void> toggleShuffle() async {
    final old = shuffleMode.value;
    shuffleMode.value = !old;
    try {
      await (audioHandler as CustomAudioHandler).toggleShuffle();
    } catch (e) {
      shuffleMode.value = old;
    }
  }

  Future<void> cycleRepeat() async {
    final old = repeatMode.value;
    final next = switch (old) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    };
    repeatMode.value = next;
    try {
      await (audioHandler as CustomAudioHandler).setRepeatMode(next);
    } catch (e) {
      repeatMode.value = old;
    }
  }

  Future<void> _saveCurrentState() async {
    try {
      final currentQueue = audioHandler.queue.value;
      if (currentQueue.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final queueList =
          currentQueue.map((item) {
            return {
              'id': item.id,
              'title': item.title,
              'artist': item.artist,
              'album': item.album,
              'duration': item.duration?.inMilliseconds,
              'artUri': item.artUri?.toString(),
            };
          }).toList();

      await prefs.setString('last_queue', json.encode(queueList));
      await prefs.setInt(
        'last_index',
        audioHandler.playbackState.value.queueIndex ?? 0,
      );
      await prefs.setInt('last_position', 0);
    } catch (e) {
      // Prevent crash if handler or prefs not ready
      debugPrint('Error saving current state: $e');
    }
  }

  Future<void> loadLastState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastQueueJson = prefs.getString('last_queue');
      if (lastQueueJson == null) return;

      final lastQueueList = json.decode(lastQueueJson) as List<dynamic>;
      final items = <MediaItem>[];
      final sources = <AudioSource>[];

      for (final map in lastQueueList) {
        final id = map['id'] as String;
        final item = MediaItem(
          id: id,
          title: map['title'] as String? ?? 'Unknown Title',
          artist: map['artist'] as String?,
          album: map['album'] as String?,
          duration: Duration(milliseconds: map['duration'] as int? ?? 0),
          artUri:
              map['artUri'] != null ? Uri.parse(map['artUri'] as String) : null,
        );
        items.add(item);
        sources.add(AudioSource.uri(Uri.parse(id), tag: item));
      }

      if (items.isNotEmpty) {
        final lastIndex = prefs.getInt('last_index') ?? 0;
        final lastPosition = Duration(
          milliseconds: prefs.getInt('last_position') ?? 0,
        );
        await (audioHandler as CustomAudioHandler).loadPlaylist(
          items,
          sources,
          initialIndex: lastIndex,
        );
        await audioHandler.pause();
        await audioHandler.seek(lastPosition);
      }
    } catch (e) {
      debugPrint('Error loading last state: $e');
    }
  }
}
