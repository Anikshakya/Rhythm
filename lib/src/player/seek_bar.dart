// SeekBar (stateless with internal state for drag)
import 'package:flutter/material.dart';

class SeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final ValueChanged<Duration>? onChangeEnd;
  final Color activeColor;
  final Color inactiveColor;

  const SeekBar({
    super.key,
    required this.duration,
    required this.position,
    this.onChangeEnd,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    double value = _dragValue ?? widget.position.inMilliseconds.toDouble();
    value = value.clamp(0.0, widget.duration.inMilliseconds.toDouble());
    final max = widget.duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
      ),
      child: Slider(
        min: 0.0,
        max: max,
        value: value,
        activeColor: widget.activeColor,
        inactiveColor: widget.inactiveColor,
        onChanged: (newValue) => setState(() => _dragValue = newValue),
        onChangeEnd: (newValue) {
          widget.onChangeEnd?.call(Duration(milliseconds: newValue.round()));
          setState(() => _dragValue = null);
        },
      ),
    );
  }
}
