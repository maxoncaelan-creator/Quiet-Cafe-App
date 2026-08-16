import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize(); // no-op if SUPABASE_URL/SUPABASE_ANON_KEY aren't set — see supabase_service.dart
  runApp(const QuietRestaurantFinderApp());
}

class QuietRestaurantFinderApp extends StatelessWidget {
  const QuietRestaurantFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quiet Restaurant Finder',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
