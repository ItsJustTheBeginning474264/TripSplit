import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Holds the logged-in user and the JWT, and persists the token between app starts.
class AuthProvider extends ChangeNotifier {
  AuthProvider({required this.api});

  static const _tokenKey = 'tripsplit_token';

  final ApiClient api;
  AppUser? user;

  bool get isLoggedIn => user != null;

  /// Restores a saved session (called by the splash screen).
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenKey);
    if (saved == null) return;
    api.token = saved;
    try {
      final res = await api.get('/api/profile');
      user = AppUser.fromJson(res['user'] as Map<String, dynamic>);
    } on ApiException {
      await clearSession();
    }
    notifyListeners();
  }

  Future<void> _startSession(Map<String, dynamic> res) async {
    api.token = res['token'] as String;
    user = AppUser.fromJson(res['user'] as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, api.token!);
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final res = await api.post('/api/login', body: {'email': email, 'password': password});
    await _startSession(res);
  }

  Future<void> register(String name, String email, String password) async {
    final res = await api.post('/api/register', body: {'name': name, 'email': email, 'password': password});
    await _startSession(res);
  }

  Future<void> logout() async {
    try {
      await api.post('/api/logout');
    } on ApiException {
      // the token is dropped locally either way
    }
    await clearSession();
  }

  /// Forgets the session locally (logout, or the server rejected the token).
  Future<void> clearSession() async {
    api.token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? currentPassword, String? newPassword}) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (newPassword != null) 'current_password': currentPassword,
      if (newPassword != null) 'new_password': newPassword,
    };
    final res = await api.put('/api/profile', body: body);
    user = AppUser.fromJson(res['user'] as Map<String, dynamic>);
    notifyListeners();
  }
}

extension ApiContext on BuildContext {
  ApiClient get api => read<AuthProvider>().api;
  AuthProvider get auth => read<AuthProvider>();
}
