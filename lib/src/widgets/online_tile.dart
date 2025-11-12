// Reusable OnlineTile (stateless)
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rhythm/src/widgets/custom_image.dart';

class OnlineTile extends StatelessWidget {
  final MediaItem item;
  final bool isCurrent;
  final VoidCallback onTap;

  const OnlineTile({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onTap,
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
    Widget leading = SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: _buildArt(),
      ),
    );
    Widget? trailing =
        isCurrent
            ? Icon(Icons.bar_chart_rounded, color: theme.colorScheme.primary)
            : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 0,
      leading: leading,
      title: Text(
        item.title,
        style: titleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        item.artist ?? 'Unknown',
        style: subtitleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: onTap,
      shape: const Border(bottom: BorderSide(color: Colors.grey, width: 0.1)),
    );
  }

  Widget _buildArt() {
      return CustomImage(uri: item.artUri.toString(), fit: BoxFit.cover);
  }
}
