// Reusable SongTile (stateless)
import 'package:flutter/material.dart';
import 'package:rhythm/src/audio_utils/custom_audio_handler/custom_audio_handler_with_metadata.dart';
import 'package:rhythm/src/app_config/app_utils.dart';
import 'package:rhythm/src/widgets/custom_image.dart';

class SongTile extends StatelessWidget {
  final SongInfo song;
  final bool isCurrent;
  final VoidCallback onTap;
  final int? trackNumber;
  final bool showDuration;

  const SongTile({
    super.key,
    required this.song,
    required this.isCurrent,
    required this.onTap,
    this.trackNumber,
    this.showDuration = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w500,
      color:
          isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
    );
    final subtitleStyle = TextStyle(color: Colors.grey[600]);
    final duration = Duration(milliseconds: song.meta.durationMs ?? 0);
    final formattedDuration = AppUtils.formatDuration(duration);
    Widget leading;
    Widget? subtitleWidget;
    Widget? trailing;
    if (trackNumber != null) {
      leading =
          isCurrent
              ? Icon(Icons.bar_chart_rounded)
              : Text('$trackNumber', style: subtitleStyle);
      subtitleWidget = null;
      trailing = Text(formattedDuration, style: subtitleStyle);
    } else {
      leading = SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: _buildArt(),
        ),
      );
      subtitleWidget = Text(
        song.meta.artist,
        style: subtitleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      trailing =
          isCurrent
              ? Icon(Icons.bar_chart_rounded, color: theme.colorScheme.primary)
              : null;
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 0,
      leading: leading,
      title: Text(
        song.meta.title,
        style: titleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitleWidget,
      trailing:
          trailing ??
          (showDuration ? Text(formattedDuration, style: subtitleStyle) : null),
      onTap: onTap,
      shape: const Border(bottom: BorderSide(color: Colors.grey, width: 0.1)),
    );
  }

  Widget _buildArt() {
    if (song.meta.artUri != null) {
      return CustomImage(
        uri: song.meta.artUri.toString(),
        fit: BoxFit.cover,
      );
    } else if (song.meta.albumArt != null) {
      return Image.memory(
        song.meta.albumArt!,
        fit: BoxFit.cover,
        errorBuilder:
            (context, error, stackTrace) =>
                const Icon(Icons.music_note_outlined),
      );
    } else {
      return const Icon(Icons.music_note_outlined);
    }
  }
}
