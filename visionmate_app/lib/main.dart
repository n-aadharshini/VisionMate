import 'package:flutter/material.dart';
import 'screens/travel_home_screen.dart';

void main() {
  runApp(VisionMateApp());
}

class VisionMateApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VisionMate Travel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: TravelHomeScreen(),
    );
  }
}
