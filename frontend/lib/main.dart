import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_client.dart';
import 'services/auth_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.loadCustomUrl();
  final api = ApiClient();
  final auth = AuthProvider(api: api);

  // If the server rejects our token (expired / logged out elsewhere) go back to Login.
  api.onUnauthorized = () {
    auth.clearSession();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  };

  runApp(ChangeNotifierProvider<AuthProvider>.value(value: auth, child: const TripSplitApp()));
}

class TripSplitApp extends StatelessWidget {
  const TripSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TripSplit',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B)),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const SplashScreen(),
    );
  }
}
