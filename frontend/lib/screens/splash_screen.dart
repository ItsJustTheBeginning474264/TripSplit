import 'package:flutter/material.dart';

import '../services/auth_provider.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Screen 1 - shows the logo while a saved session is restored.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final auth = context.auth;
    await Future.wait([auth.restoreSession(), Future<void>.delayed(const Duration(milliseconds: 1200))]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => auth.isLoggedIn ? const HomeScreen() : const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.luggage, size: 84, color: scheme.onPrimary),
            const SizedBox(height: 16),
            Text(
              'TripSplit',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: scheme.onPrimary),
            ),
            const SizedBox(height: 8),
            Text('Split trip expenses, fairly.', style: TextStyle(color: scheme.onPrimary)),
            const SizedBox(height: 32),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: scheme.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
