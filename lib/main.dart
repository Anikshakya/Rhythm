import 'package:flutter/material.dart';
import 'package:rhythm/src/components/miniplayer/mini_player.dart';
import 'package:rhythm/view/mainscreen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rhythm',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MainScreen(),
      builder: (context, child) {
        return FullScreenBuilder(child: child!);
      },
    );
  }
}

class FullScreenBuilder extends StatefulWidget {
  final Widget child;
  const FullScreenBuilder({super.key, required this.child});
 
  @override
  State<FullScreenBuilder> createState() =>
      _FullScreenBuilderState();
}
 
class _FullScreenBuilderState extends State<FullScreenBuilder> {
 
  @override
  void initState() {
    super.initState();
  }
 
  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: DraggableMiniPlayer()
          ),
        ],
      ),
    );
  }
}
