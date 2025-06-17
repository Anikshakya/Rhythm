// FadeIgnoreTransition
import 'package:flutter/material.dart';
import 'package:rhythm/src/components/miniplayer/miniplayer_base.dart';
import 'package:rhythm/src/components/miniplayer/miniplayer_controller.dart';

class FadeIgnoreTransition extends AnimatedWidget {
  final Animation<double> opacity;
  final Widget child;
  final bool completelyKillWhenPossible;

  const FadeIgnoreTransition({
    super.key,
    required this.opacity,
    required this.child,
    this.completelyKillWhenPossible = false,
  }) : super(listenable: opacity);

  @override
  Widget build(BuildContext context) {
    final opacityValue = opacity.value;
    if (completelyKillWhenPossible && opacityValue == 0.0) {
      return const SizedBox();
    }
    return Opacity(
      opacity: opacityValue.clamp(0.0, 1.0),
      child: child,
    );
  }
}


class DraggableMiniPlayer extends StatefulWidget {
  const DraggableMiniPlayer({super.key});

  @override
  _DraggableMiniPlayerState createState() => _DraggableMiniPlayerState();
}

class _DraggableMiniPlayerState extends State<DraggableMiniPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final double _minHeight = 80.0;
  late double _maxHeight;

  bool get _isExpanded => _controller.value > 0.5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 0.0,
    );
    _maxHeight = 300.0; // Placeholder, updated in didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maxHeight = MediaQuery.of(context).size.height; // Full screen height
    MiniPlayerController.inst.init(_controller, context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _createOpacityAnimation(double Function(double cp) transform) {
    return _controller.drive(
      Animatable.fromCallback(
        (p) {
          final double cp = p.clamp(0.0, 1.0);
          return transform(cp);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opacityAnimation = _createOpacityAnimation((cp) => cp);
    final inverseOpacityAnimation = _createOpacityAnimation((cp) => 1.0 - cp);

    return MiniplayerRaw(
      builder: (maxOffset, bounceUp, bounceDown, topInset, bottomInset, rightInset, screenSize, sMaxOffset, p, cp, ip, icp, rp, rcp, qp, qcp, bp, bcp, miniplayerbottomnavheight, bottomOffset, navBarHeight) {
        final height = velpy(a: _minHeight, b: _maxHeight, c: cp);
        final borderRadius = BorderRadius.vertical(
          top: Radius.circular((18.0 + (20.0 - 18.0) * cp) - cp*20),
          bottom: Radius.circular((18.0 + (20.0 - 18.0) * cp)- cp*20),
        );
        var padding = 10.0 - cp * 10;

        return SizedBox.expand(
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomOffset,
                child: SafeArea(
                  top: false,
                  child: Container(
                    margin: EdgeInsets.all(padding),
                    height: height,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[900],
                      borderRadius: borderRadius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2 + 0.1 * cp),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Mini player content when collapsed
                        FadeIgnoreTransition(
                          opacity: inverseOpacityAnimation,
                          child: _buildMiniPlayer(),
                        ),
                        // Expanded player content
                        FadeIgnoreTransition(
                          opacity: opacityAnimation,
                          child: _buildExpandedPlayer(
                            borderRadius: borderRadius
                          ),
                        ),
                        // Close button for expanded view
                        Positioned(
                          top: 12,
                          right: 12,
                          child: FadeIgnoreTransition(
                            opacity: opacityAnimation,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => _controller.reverse(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniPlayer() {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text("Song Title", style: TextStyle(color: Colors.white)),
            Text("Artist Name", style: TextStyle(color: Colors.white70)),
          ],
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.play_arrow, color: Colors.white),
          onPressed: () => _controller.forward(),
        ),
      ],
    );
  }

  Widget _buildExpandedPlayer({required borderRadius}) {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: borderRadius,
            ),
            child: const Center(
              child: Icon(Icons.music_note, size: 100, color: Colors.white),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Song Title",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Artist Name • Album Name",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: 0.5,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.blue),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("1:30", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text("3:00", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous, color: Colors.white, size: 32),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white, size: 32),
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}